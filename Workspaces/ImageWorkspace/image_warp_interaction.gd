extends RefCounted
## Canvas input and overlays; compact geometry transactions use existing history.
signal settings_changed
var canvas: Control
var mode:="brush"
var brush:="push"
var diameter:=180.0
var strength:=.5
var hardness:=.25
var pressure_enabled:=true
var show_grid:=false
var show_freeze:=true
var selection_only:=false
var pin_radius:=.3
var mesh_resolution:=4
var mesh_radius:=.5
var mesh_attenuation:=2.0
var _mesh_weights:=PackedFloat32Array()
var selected_points:=PackedInt32Array()
var selected_pin:=-1
var active:=false
var _layer_id:=""
var _last:=Vector2.ZERO
var _pointer:=Vector2.ZERO
var _start:=Vector2.ZERO
var _original:=PackedVector2Array()
var _pending:=false
var _pressure:=1.0
var _freeze_erase:=false
var _changed:=false

func settings() -> Dictionary:
	return {"mode":mode,"brush":brush,"diameter":diameter,"strength":strength,"hardness":hardness,"pressure":pressure_enabled,"grid":show_grid,"freeze":show_freeze,"selection":selection_only,"pin_radius":pin_radius,"resolution":mesh_resolution,"mesh_radius":mesh_radius,"mesh_attenuation":mesh_attenuation}

func restore_settings(values: Dictionary) -> void:
	mode=str(values.get("mode","brush")); brush=str(values.get("brush","push")); diameter=float(values.get("diameter",180))
	strength=float(values.get("strength",.5)); hardness=float(values.get("hardness",.25)); pressure_enabled=values.get("pressure",true)
	show_grid=values.get("grid",false); show_freeze=values.get("freeze",true); selection_only=values.get("selection",false)
	pin_radius=float(values.get("pin_radius",.3)); mesh_resolution=int(values.get("resolution",4))
	mesh_radius=float(values.get("mesh_radius",.5)); mesh_attenuation=float(values.get("mesh_attenuation",2.0))

func layer() -> KiwiImageLayer:
	if canvas.document==null or canvas.selected.is_empty(): return null
	return canvas.document.layer_for_id(canvas.selected[-1])

func local_uv(document_point: Vector2,item: KiwiImageLayer) -> Vector2:
	var local:=item.unproject_point(canvas.document.world_transform(item).affine_inverse()*document_point)
	return local/item.content_dimensions().max(Vector2.ONE)

func screen(uv: Vector2,item: KiwiImageLayer) -> Vector2:
	return canvas.origin()+canvas.document.world_transform(item)*item.project_point(uv*item.content_dimensions())*canvas.zoom

func ensure_data(item: KiwiImageLayer) -> KiwiImageWarpData:
	if item.warp==null:
		item.warp=KiwiImageWarpData.new(); item.warp.initialize(item.content_dimensions())
		item.warp.reset_mesh(mesh_resolution)
	return item.warp

func begin(item: KiwiImageLayer,uv: Vector2) -> void:
	canvas.gesture_started.emit(); active=true; _changed=false; _layer_id=item.id
	var data:=ensure_data(item)
	if mode=="brush": data.refine_for_brush(item.content_dimensions(),diameter)
	data.capture_baseline()
	data.restriction.clear()
	if selection_only and canvas.selection!=null:
		data.restriction.resize(data.displacement.size())
		for i in data.restriction.size():
			var world: Vector2=canvas.document.world_transform(item)*item.project_point(data.node_uv(i)*item.content_dimensions())
			var sample: Vector2=canvas.selection_inverse_warp.call(world) if canvas.selection_inverse_warp.is_valid() else canvas.selection_inverse*world
			var at:=Vector2i(sample.floor())
			data.restriction[i]=canvas.selection.get_pixelv(at).a if Rect2i(Vector2i.ZERO,canvas.selection.get_size()).has_point(at) else 0.0
	elif selection_only:
		data.restriction.resize(data.displacement.size()); data.restriction.fill(0)
	data.touch(); _last=uv; _pointer=uv; _start=uv
	canvas._drag="warp"; canvas.gesture_changed.emit()

func handle(event: InputEvent) -> bool:
	var item:=layer()
	if event is InputEventMouseMotion:
		if canvas._drag=="pan": return false
		canvas._mouse=event.position; canvas.queue_redraw()
		if active and item!=null and item.id==_layer_id:
			_pointer=local_uv(canvas.to_document(event.position),item); _pending=true
			_pressure=event.pressure if pressure_enabled and event.pressure>0 else 1.0
			_freeze_erase=event.ctrl_pressed
		return true
	if not event is InputEventMouseButton: return false
	canvas._mouse=event.position
	if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if event.pressed and event.shift_pressed:
			if mode=="mesh":
				var direction:=1.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1.0
				mesh_radius=clampf(snappedf(mesh_radius+maxf(.01,mesh_radius*.12)*direction,.01),0,2)
				if active and item!=null:
					_mesh_weights=mesh_weights(_original,selected_points,item.content_dimensions(),mesh_radius,mesh_attenuation); _pending=true
			else: diameter=clampf(diameter*(1.1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.1),2,2048)
			settings_changed.emit(); canvas.queue_redraw(); return true
		return false
	if event.button_index==MOUSE_BUTTON_MIDDLE or Input.is_key_pressed(KEY_SPACE): return false
	if item==null or not canvas.document.can_edit(item):
		if event.pressed: canvas.hint_changed.emit("Select an unlocked layer to warp")
		return true
	if item.kind=="group":
		canvas.hint_changed.emit("Use Rasterize group for warp to edit the combined artwork")
		return true
	var uv:=local_uv(canvas.to_document(event.position),item)
	if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
		if active: cancel(); return true
		if mode=="pins" and item.warp!=null:
			var hit:=hit_pin(item,event.position)
			if hit>=0:
				begin(item,uv); item.warp.pins.remove_at(hit); item.warp.touch(); _changed=true; selected_pin=-1; finish()
		return true
	if event.button_index!=MOUSE_BUTTON_LEFT: return false
	if not event.pressed: finish(); return true
	canvas.grab_focus()
	if mode=="brush":
		if not Rect2(Vector2.ZERO,Vector2.ONE).grow(diameter/maxf(1,item.content_dimensions().length())).has_point(uv): return true
		begin(item,uv); _pending=true; _freeze_erase=event.ctrl_pressed
	elif mode=="mesh":
		if not show_grid: return true
		var hit:=hit_mesh(item,event.position)
		if hit<0: return true
		if event.shift_pressed:
			if selected_points.has(hit): selected_points.remove_at(selected_points.find(hit))
			else: selected_points.append(hit)
		elif not selected_points.has(hit): selected_points=PackedInt32Array([hit])
		begin(item,uv); _original=item.warp.mesh_points.duplicate()
		_mesh_weights=mesh_weights(_original,selected_points,item.content_dimensions(),mesh_radius,mesh_attenuation)
	elif mode=="pins":
		var hit:=hit_pin(item,event.position)
		if hit<0 and item.warp!=null and item.warp.pins.size()>=128:
			canvas.hint_changed.emit("Pin limit reached · Remove unused pins before adding more")
			return true
		begin(item,uv)
		if hit<0:
			item.warp.pins.append({"source":uv,"target":uv,"radius":pin_radius,"locked":false}); hit=item.warp.pins.size()-1; _changed=true
			item.warp.touch()
		selected_pin=hit
		if event.ctrl_pressed:
			item.warp.pins[hit].locked=not bool(item.warp.pins[hit].get("locked",false)); item.warp.touch(); _changed=true; finish(); return true
		_original=PackedVector2Array([item.warp.pins[hit].target]); settings_changed.emit()
	canvas.queue_redraw(); return true

func process(delta: float) -> void:
	if not active or canvas._drag=="pan": return
	var item:=layer()
	if item==null or item.id!=_layer_id: cancel(); return
	var data:=item.warp
	if mode=="brush":
		if not _pending and brush=="push": return
		var kind:="thaw" if brush=="freeze" and _freeze_erase else brush
		if KiwiImageWarpBrush.stroke(data,item.content_dimensions(),_last,_pointer,diameter,strength*_pressure,hardness,kind,minf(2,delta*60)):
			_changed=true; canvas.gesture_changed.emit()
		_last=_pointer
	elif _pending and mode=="mesh":
		for index in _original.size():
			data.mesh_points[index]=_original[index]+(_pointer-_start)*_mesh_weights[index]
		data.touch(); _changed=true; canvas.gesture_changed.emit()
	elif _pending and mode=="pins" and selected_pin>=0 and selected_pin<data.pins.size():
		if not data.pins[selected_pin].get("locked",false):
			data.pins[selected_pin].target=_original[0]+_pointer-_start; data.touch(); _changed=true; canvas.gesture_changed.emit()
	_pending=false; canvas.queue_redraw()

static func mesh_weights(points: PackedVector2Array,selected: PackedInt32Array,extent: Vector2,radius: float,attenuation: float) -> PackedFloat32Array:
	var weights:=PackedFloat32Array(); weights.resize(points.size())
	var metric:=extent/maxf(1,maxf(extent.x,extent.y))
	for i in points.size():
		if selected.has(i): weights[i]=1; continue
		if radius<=0: continue
		var distance:=INF
		for index in selected:
			if index>=0 and index<points.size(): distance=minf(distance,((points[i]-points[index])*metric).length())
		var t:=clampf(1-distance/radius,0,1)
		weights[i]=pow(t*t*(3-2*t),maxf(.1,attenuation))
	return weights

func finish() -> void:
	if not active: return
	if _pending: process(1.0/60)
	active=false; canvas._drag=""
	if _changed: canvas.gesture_finished.emit()
	else: canvas.gesture_cancelled.emit()
	canvas.queue_redraw()

func cancel() -> void:
	if not active: return
	active=false; _pending=false; canvas._drag=""; canvas.gesture_cancelled.emit(); canvas.queue_redraw()

func hit_mesh(item: KiwiImageLayer,at: Vector2) -> int:
	var points:=item.warp.mesh_points if item.warp!=null else PackedVector2Array()
	var resolution:=item.warp.mesh_resolution if item.warp!=null else mesh_resolution
	if points.is_empty():
		for i in resolution*resolution: points.append(Vector2(i%resolution,i/resolution)/float(resolution-1))
	for i in points.size():
		if screen(points[i],item).distance_to(at)<10: return i
	return -1

func hit_pin(item: KiwiImageLayer,at: Vector2) -> int:
	if item.warp==null: return -1
	for i in item.warp.pins.size():
		if screen(item.warp.pins[i].target,item).distance_to(at)<11: return i
	return -1

func draw() -> void:
	var item:=layer()
	if item==null: return
	var data:=item.warp
	if mode=="mesh" and mesh_radius>0 and canvas.get_global_rect().has_point(canvas.get_global_mouse_position()):
		var center:=local_uv(canvas.to_document(canvas._mouse),item); var ring:=PackedVector2Array()
		var extent:=item.content_dimensions(); var radius:=mesh_radius*maxf(extent.x,extent.y)
		for i in 65: ring.append(screen(center+Vector2(cos(TAU*i/64.0),sin(TAU*i/64.0))*radius/extent,item))
		canvas.draw_polyline(ring,Color(0,0,0,.75),3,true); canvas.draw_polyline(ring,Color("95e4d0"),1.2,true)
	if mode=="brush":
		var uv:=local_uv(canvas.to_document(canvas._mouse),item); var points:=PackedVector2Array()
		for i in 49:
			var offset:=Vector2(cos(i*TAU/48),sin(i*TAU/48))*diameter*.5/item.content_dimensions()
			points.append(screen(uv+offset,item))
		canvas.draw_polyline(points,Color(0,0,0,.85),3,true); canvas.draw_polyline(points,Color("b0f5df"),1.25,true)
	if show_grid:
		var resolution:=data.mesh_resolution if data!=null else mesh_resolution
		var points:=data.mesh_points if data!=null else PackedVector2Array()
		if points.is_empty():
			for i in resolution*resolution: points.append(Vector2(i%resolution,i/resolution)/float(resolution-1))
		for i in points.size():
			var p:=screen(points[i],item)
			if mode=="brush" and data!=null: p=screen(data.forward(data.mesh_origin(i)),item)
			if i%resolution+1<resolution:
				var neighbor:=screen(data.forward(data.mesh_origin(i+1)),item) if mode=="brush" and data!=null else screen(points[i+1],item)
				canvas.draw_line(p,neighbor,Color(.4,.9,.8,.65),1,true)
			if i/resolution+1<resolution:
				var neighbor:=screen(data.forward(data.mesh_origin(i+resolution)),item) if mode=="brush" and data!=null else screen(points[i+resolution],item)
				canvas.draw_line(p,neighbor,Color(.4,.9,.8,.65),1,true)
			if mode=="mesh":
				canvas.draw_circle(p,5.5,Color("101b24")); canvas.draw_circle(p,3.5,Color("ffc575") if selected_points.has(i) else Color("93e9db"))
	if mode=="pins" and data!=null:
		for i in data.pins.size():
			var pin: Dictionary=data.pins[i]; var p:=screen(pin.target,item)
			canvas.draw_line(screen(pin.source,item),p,Color(.7,.8,.9,.5),1,true)
			canvas.draw_circle(p,8,Color("101b24")); canvas.draw_circle(p,5,Color("ffc575") if pin.get("locked",false) else (Color.WHITE if i==selected_pin else Color("75e3cb")))
	if show_freeze and data!=null:
		for i in data.freeze.size():
			if data.freeze[i]<.02: continue
			canvas.draw_circle(screen(data.node_uv(i),item),maxf(2,diameter*canvas.zoom*.025),Color(.3,.65,1,data.freeze[i]*.32))
