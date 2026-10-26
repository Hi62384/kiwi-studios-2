class_name KiwiImageCanvas
extends Control
## Canvas navigation and gestures. One gesture produces one history entry.

signal selection_changed
signal gesture_started
signal gesture_changed
signal gesture_finished
signal gesture_cancelled
signal create_requested(kind: String, bounds: Rect2, points: PackedVector2Array)
signal duplicate_requested
signal text_edit_requested
signal files_dropped(paths: PackedStringArray, at: Vector2)
signal color_sampled(color: Color)
signal hint_changed(message: String)
signal brush_size_changed(value: float)
signal correction_scale_changed(value: float)
signal threshold_changed(value: float)
signal polygon_committed(points: PackedVector2Array)

var document: KiwiImageDocument
var preview: Texture2D
var preview_screen_space:=false
var selected: Array[String] = []
var tool := "move"
var zoom := 0.7
var pan := Vector2.ZERO
var snapping := true
var snap_guides_x: Array[float]=[]
var snap_guides_y: Array[float]=[]
var color := Color("62d9bc")
var _value_inverse_key: int=0
var _value_inverse_color:=Color.WHITE
var _value_mask: Image
var _value_mask_mapping:=Transform2D.IDENTITY

func _prepare_source_color() -> void:
	if _paint_layer==null: return
	_value_mask_mapping=Transform2D.IDENTITY
	if _paint_layer.properties.has("values_selection_frame"):
		var frame: Transform2D=_paint_layer.properties.values_selection_frame
		_value_mask_mapping=frame.scaled_local(Vector2(_paint_layer.properties.get("values_selection_dimensions",_paint_layer.dimensions))/_paint_layer.dimensions.max(Vector2.ONE))*document.world_transform(_paint_layer).affine_inverse()
	var math_script=preload("res://Workspaces/ImageWorkspace/image_values.gd")
	var key:=hash([color,_paint_layer.id,math_script.operations(_paint_layer),_paint_layer.properties.get("values_selection")])
	if key!=_value_inverse_key:
		_value_inverse_key=key; _value_inverse_color=math_script.inverse_color(color,_paint_layer)
		var mask: Texture2D=_paint_layer.properties.get("values_selection")
		_value_mask=mask.get_image() if mask!=null else null

func _source_color(point: Vector2) -> Color:
	if _material_region!=null: return Color.WHITE
	if _paint_layer==null: return color
	if bool(_paint_layer.properties.get("values_selection_only",false)):
		if _value_mask==null: return color
		var p:=Vector2i(_value_mask_mapping*point)
		if _paint_layer.properties.get("values_selection_local",false):
			var local:=_paint_layer.unproject_point(document.world_transform(_paint_layer).affine_inverse()*point)
			p=Vector2i(local/_paint_layer.content_dimensions()*Vector2(_value_mask.get_size()))
		if not Rect2i(Vector2i.ZERO,_value_mask.get_size()).has_point(p) or _value_mask.get_pixelv(p).a<=0: return color
	return _value_inverse_color
var painting_mode:="color"
var material_strength:=1.0
var _material_region: KiwiLivePaintRegion
var _material_template_id:=""
var _material_bake_after:=false
var _material_previous_template:=""
var _material_busy:=false
var _material_flood_source: Image
var _material_stroke_anchor:=Vector2.ZERO
var _material_direction_set:=false
var _material_stamps: RefCounted
var _live_eraser: RefCounted
var brush_size := 28.0
var hardness := 0.8
var brush_opacity := 1.0
var fill_threshold := 0.08
var brush_mode := "freehand"
var brush_type:="normal"
var soften_strength:=.5
var _soften_source: Image
var _soften_opaque:=false
var stroke_correct: bool:
	get: return brush_type=="stroke_correct"
	set(value):
		if value: brush_type="stroke_correct"
		elif brush_type=="stroke_correct": brush_type="normal"
var correction_strength := 0.5
var correction_scale := 1.0
var _erase_modifier:=false
var _corrector: KiwiStrokeCorrector
var _corrected_tail_bounds:=Rect2i()
var _ink_origin:=Vector2i.ZERO
var _corrected_stamp_distance:=0.0
var _corrected_started:=false
var _corrected_all_bounds:=Rect2i()
var paint_new_layer := false
var selection: Image
var selection_transform:=Transform2D.IDENTITY
var selection_inverse:=Transform2D.IDENTITY
var selection_forward_warp: Callable
var selection_inverse_warp: Callable
var selection_preview_origin:=Vector2.ZERO
var _selection_preview_size:=Vector2.ZERO
var selection_texture: ImageTexture
var pixel_selection_bounds := Rect2()
var path_layer_id: String=""
var pixel_mode: String="brush"
var pixel_box_select:=false
var _pixel_area_base: Image
var _pixel_area_previous:=Rect2i()
var pixel_match_all:=false
var edge_magnet:=false
var edge_threshold:=.4
var object_threshold:=.5
var smart_selection:=KiwiPixelSelectionEngine.new()
var _edge_follower:=KiwiPixelEdgeMagnet.new()
var _edge_preview:=Vector2.INF
var _smart_base: Image
var _smart_seed:=Vector2.ZERO
var _object_committed: Dictionary={}
var _pan_previous_drag:=""
var _edge_motion_pending:=false
var _edge_motion_point:=Vector2.ZERO
var _edge_hover_pending:=false
var _smart_request:=-1
var _smart_subtract:=false
var _smart_ready:=false
var _smart_has_proposal:=false
var _smart_apply_when_ready:=false
var paint_selection_only:=false
var _polygon_before:=PackedVector2Array()
var _polygon_index: int=-1
var _selection_overlay:=TextureRect.new()
var warp_tool:=preload("res://Workspaces/ImageWorkspace/image_warp_interaction.gd").new()
var repair_tool:=preload("res://Workspaces/ImageWorkspace/image_repair_interaction.gd").new()
var pixel_source: Image
var selection_alpha:=1.0
var selection_falloff:=0.0
var _pixel_alpha_base: Image
var _pixel_alpha_ink: Image
var _pixel_alpha_stamp: Image
var _pixel_alpha_stamp_key:=""
var pixel_domain:=Rect2i()
var _drag := ""
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _mouse := Vector2.ZERO
var _bounds := Rect2()
var _resize_grab_offset:=Vector2.ZERO
var _resize_proxy_active:=false
var _resize_proxy_screen:=Vector2.ZERO
var _originals: Array[Dictionary] = []
var _points := PackedVector2Array()
var _paint_image: Image
var _paint_data := PackedByteArray()
var _paint_layer: KiwiImageLayer
var _stroke_base: Image
var _stroke_points := PackedVector2Array()
var _paint_created_layer := false
var _selection_operation := 0
var _moved := false
var _vertex_index := -1
var _pending_single := ""
var _active_mode := "freehand"
var _shape_end := Vector2.ZERO
var _shape_control := Vector2.ZERO
var _shape_control_end:=Vector2.ZERO
var _shape_grab_offset:=Vector2.ZERO
var _circle_profiles:=Vector4(2,2,2,2)
var _shape_handle := -1
var _stamp: Image
var _stamp_key := ""
var _stroke_ink: Image
var _stroke_dirty:=Rect2i()


func _ready() -> void:
	warp_tool.canvas=self
	add_child(smart_selection); smart_selection.proposed.connect(_smart_proposed)
	smart_selection.analyzed.connect(func(): _edge_follower.field=smart_selection.edges; hint_changed.emit("Edge analysis ready"))
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var blending := CanvasItemMaterial.new()
	blending.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	material = blending
	gui_input.connect(_input_canvas)
	mouse_exited.connect(queue_redraw)
	_selection_overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_selection_overlay.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	_selection_overlay.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var mask_shader:=Shader.new()
	mask_shader.code="""shader_type canvas_item;
render_mode unshaded;
uniform float strength=0.65;
uniform bool warped=false;
uniform vec3 row0=vec3(1.0,0.0,0.0);
uniform vec3 row1=vec3(0.0,1.0,0.0);
uniform vec3 row2=vec3(0.0,0.0,1.0);
void fragment(){
 vec2 sample_uv=UV;
 if(warped){vec3 p=vec3(UV,1.0); float w=dot(row2,p); sample_uv=abs(w)>0.000001 ? vec2(dot(row0,p),dot(row1,p))/w : vec2(-1.0);}
 float a=texture(TEXTURE,sample_uv).a;
 if(any(lessThan(sample_uv,vec2(0.0))) || any(greaterThan(sample_uv,vec2(1.0)))) a=0.0;
 float stripe=step(0.5,fract((FRAGCOORD.x+FRAGCOORD.y)/12.0));
 COLOR=vec4(vec3(stripe),a*strength);
}"""
	var mask_material:=ShaderMaterial.new(); mask_material.shader=mask_shader
	_selection_overlay.material=mask_material
	add_child(_selection_overlay)
	_selection_overlay.hide()
	resized.connect(_sync_selection_overlay)


func _process(_delta: float) -> void:
	if tool=="warp": warp_tool.process(_delta)
	if tool=="repair": repair_tool.process()
	if _drag=="paint" and _corrector!=null: _flush_corrected_stroke()
	_flush_edge_motion()
	if _edge_hover_pending:
		_edge_hover_pending=false
		if _drag.is_empty() and tool=="pixel_select" and edge_magnet and smart_selection.edges!=null:
			var ridge:=smart_selection.edges.nearest(to_document(_mouse),edge_threshold)
			_edge_preview=smart_selection.edges.refine(ridge) if ridge>=0 else Vector2.INF
			queue_redraw()
	_sync_selection_overlay()
	if tool!="pixel_select" or not edge_magnet: _edge_preview=Vector2.INF

func _sync_selection_overlay() -> void:
	var visible: bool=(tool=="pixel_select" or (paint_selection_only and tool in ["brush","eraser","fill"])) and selection_texture!=null and document!=null
	if visible:
		(_selection_overlay.material as ShaderMaterial).set_shader_parameter("strength",.65 if tool=="pixel_select" else .16)
		_selection_overlay.texture=selection_texture
		_selection_overlay.size=_selection_preview_size if _selection_preview_size!=Vector2.ZERO else Vector2(selection_texture.get_size())
		# Use the Control's own transform. A raw RenderingServer override was
		# overwritten by deferred Control layout updates, flashing an offset mask.
		_selection_overlay.position=origin()+selection_preview_origin*zoom
		_selection_overlay.scale=Vector2.ONE*zoom
	_selection_overlay.visible=visible


func origin() -> Vector2:
	return size * .5 - Vector2(document.canvas_size) * zoom * .5 + pan if document != null else Vector2.ZERO


func to_document(point: Vector2) -> Vector2:
	return (point-origin())/zoom


func fit() -> void:
	if document == null: return
	zoom = clampf(minf((size.x-100)/document.canvas_size.x,(size.y-100)/document.canvas_size.y),.03,8.0)
	pan = Vector2.ZERO
	queue_redraw()


func set_zoom(value: float, anchor: Vector2 = Vector2(-1,-1)) -> void:
	if document == null: return
	if anchor.x < 0: anchor = size*.5
	var at := to_document(anchor)
	zoom = clampf(value,.03,32.0)
	pan += anchor-(origin()+at*zoom)
	queue_redraw()


func selection_bounds() -> Rect2:
	var result := Rect2()
	var first := true
	if document == null: return result
	for layer in document.selected_roots(selected):
		var world:=document.world_transform(layer)
		var rect:=Rect2(world*layer.project_point(Vector2.ZERO),Vector2.ZERO)
		for uv in [Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]: rect=rect.expand(world*layer.project_point(uv*layer.dimensions))
		result = rect if first else result.merge(rect)
		first = false
	return result


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("101720"))
	if document == null: return
	var rect := Rect2(origin(),Vector2(document.canvas_size)*zoom)
	draw_rect(rect.grow(6),Color(0,0,0,.25))
	draw_rect(rect,Color("27313e"))
	var clipped := rect.intersection(Rect2(Vector2.ZERO,size))
	for y in range(floori(clipped.position.y/14),ceili(clipped.end.y/14)):
		for x in range(floori(clipped.position.x/14),ceili(clipped.end.x/14)):
			if (x+y)%2 == 0: draw_rect(Rect2(Vector2(x,y)*14,Vector2.ONE*14).intersection(rect),Color("303b48"))
	if preview != null:
		if preview_screen_space: draw_texture_rect_region(preview,clipped,clipped)
		else: draw_texture_rect(preview,rect,false)
	draw_rect(rect,Color("536176"),false,1)
	if tool=="warp": warp_tool.draw()
	if tool=="repair": repair_tool.draw()
	for guide in snap_guides_x:
		var x:=origin().x+guide*zoom; draw_line(Vector2(x,0),Vector2(x,size.y),Color("66e0c1"),1)
	for guide in snap_guides_y:
		var y:=origin().y+guide*zoom; draw_line(Vector2(0,y),Vector2(size.x,y),Color("66e0c1"),1)
	if tool == "move" and not selected.is_empty():
		var bounds := selection_bounds()
		var screen := Rect2(origin()+bounds.position*zoom,bounds.size*zoom)
		var outline:=_projected_handles(screen)
		draw_polyline(PackedVector2Array([outline[0],outline[2],outline[4],outline[6],outline[0]]),Color("68e3c7"),1.5,true)
		for handle in _handles(screen):
			draw_rect(Rect2(handle-Vector2.ONE*4,Vector2.ONE*8),Color("132a2c"))
			draw_rect(Rect2(handle-Vector2.ONE*4,Vector2.ONE*8),Color("8ff4df"),false,1.5)
		var rotate_handle:=_rotation_handle(screen)
		draw_line(_handles(screen)[1],rotate_handle,Color("68e3c7"),1.5)
		draw_circle(rotate_handle,4.5,Color("8ff4df"))
	if _drag in ["rect_select","crop","shape","box","pixel_box"]:
		var drag_rect := Rect2(origin()+_start*zoom,(_last-_start)*zoom).abs()
		draw_rect(drag_rect,Color(.03,.085,.07,.1))
		draw_rect(drag_rect,Color("8ff4df"),false,1.5)
	if tool=="path":
		var draft:=_points.duplicate()
		var screen_points:=PackedVector2Array()
		for p in draft: screen_points.append(origin()+p*zoom)
		var handles:=screen_points.duplicate()
		var shape:=document.layer_for_id(path_layer_id)
		if shape!=null: screen_points=KiwiImageLayer.rounded_polygon(screen_points,float(shape.properties.get("radius",0))*zoom)
		var fill: Color=shape.properties.get("color",color) if shape!=null else color
		fill.r*=fill.a; fill.g*=fill.a; fill.b*=fill.a
		if screen_points.size()>2 and (shape==null or shape.properties.get("filled",true)):
			var triangles:=Geometry2D.triangulate_polygon(screen_points)
			for i in range(0,triangles.size(),3): draw_colored_polygon(PackedVector2Array([screen_points[triangles[i]],screen_points[triangles[i+1]],screen_points[triangles[i+2]]]),fill)
		if screen_points.size()>1:
			screen_points.append(screen_points[0])
			var stroke: float=float(shape.properties.get("stroke",0)) if shape!=null else 0.0
			var outline: Color=shape.properties.get("stroke_color",Color.BLACK) if shape!=null else Color.BLACK
			draw_polyline(screen_points,outline if stroke>0 else Color("8ff4df"),maxf(1,stroke*zoom),true)
		for p in handles:
			draw_circle(p,6,Color("101720")); draw_circle(p,4,Color("8ff4df"))
		if _polygon_index<0 and Rect2(Vector2.ZERO,size).has_point(_mouse):
			var candidate:=origin()+_snap_polygon_point(to_document(_mouse),Input.is_key_pressed(KEY_CTRL))*zoom
			draw_circle(candidate,6,Color("101720")); draw_circle(candidate,4,Color("f6ce80"))
	elif _points.size() > 1:
		var points := PackedVector2Array()
		for point in _points: points.append(origin()+point*zoom)
		if _drag in ["lasso_crop","pixel_lasso"] and points.size()>2:
			var triangles:=Geometry2D.triangulate_polygon(points)
			for index in range(0,triangles.size(),3):
				draw_colored_polygon(PackedVector2Array([points[triangles[index]],points[triangles[index+1]],points[triangles[index+2]]]),Color(.04,.14,.12,.22))
		if tool=="path" and points.size()>2: points.append(points[0])
		draw_polyline(points,Color("8ff4df"),1.5,true)
		if tool=="path":
			for vertex in points: draw_circle(vertex,4,Color("8ff4df"))
	if _drag in ["shape_stroke","stroke_edit"]:
		var guide:=_shape_path()
		for index in guide.size(): guide[index]=origin()+guide[index]*zoom
		var tint:=color; tint.a*=brush_opacity; tint.r*=tint.a; tint.g*=tint.a; tint.b*=tint.a
		if guide.size()>1: draw_polyline(guide,tint,maxf(1,brush_size*zoom),true)
		if _active_mode!="line":
			var handles:=_shape_handles()
			for index in handles.size():
				var at:=_shape_screen_handle(handles[index])
				if _active_mode=="circle" and index in [0,2,4,6]:
					draw_colored_polygon(PackedVector2Array([at+Vector2(0,-7),at+Vector2(7,0),at+Vector2(0,7),at+Vector2(-7,0)]),Color("efb865"))
				else: draw_circle(at,6,Color("17212d")); draw_arc(at,6,0,TAU,24,Color("8ff4df"),1.5,true)
		if _active_mode=="curve":
			draw_line(origin()+_start*zoom,origin()+_shape_control*zoom,Color("749c98"),1,true)
			draw_line(origin()+_shape_control_end*zoom,origin()+_shape_end*zoom,Color("749c98"),1,true)
	if tool=="path" and not selected.is_empty():
		var layer:=document.layer_for_id(selected[-1])
		if layer!=null and layer.kind=="path":
			var points: PackedVector2Array=layer.properties.get("points",PackedVector2Array())
			var source_size: Vector2=layer.properties.get("path_size",layer.dimensions)
			for point in points:
				var screen:=origin()+(document.world_transform(layer)*(point*layer.dimensions/source_size.max(Vector2.ONE)))*zoom
				draw_circle(screen,4,Color("8ff4df"))
	if (tool in ["brush","eraser"] or (tool=="pixel_select" and pixel_mode in ["brush","erase"] and not pixel_box_select)) and Rect2(Vector2.ZERO,size).has_point(_mouse):
		draw_arc(_mouse,brush_size*zoom*.5,0,TAU,48,Color.WHITE,1.0,true)
	if _edge_preview!=Vector2.INF and tool=="pixel_select" and edge_magnet:
		var at:=origin()+_edge_preview*zoom
		draw_arc(at,maxf(3,brush_size*zoom*.5),0,TAU,48,Color("8ff4df"),1.5,true)
		draw_circle(at,2,Color("8ff4df"))


func _projected_handles(rect: Rect2) -> Array[Vector2]:
	if document!=null:
		var roots:=document.selected_roots(selected)
		if roots.size()==1:
			var layer:=roots[0]; var world:=document.world_transform(layer)
			var frame:=layer.projected_bounds()
			var points: Array[Vector2]=[]
			for uv in [Vector2.ZERO,Vector2(.5,0),Vector2.RIGHT,Vector2(1,.5),Vector2.ONE,Vector2(.5,1),Vector2.DOWN,Vector2(0,.5)]:
				points.append(origin()+(world*(frame.position+uv*frame.size))*zoom)
			return points
	return _raw_handles(rect)


func _raw_handles(rect: Rect2) -> Array[Vector2]:
	return [rect.position,Vector2(rect.get_center().x,rect.position.y),Vector2(rect.end.x,rect.position.y),
		Vector2(rect.end.x,rect.get_center().y),rect.end,Vector2(rect.get_center().x,rect.end.y),
		Vector2(rect.position.x,rect.end.y),Vector2(rect.position.x,rect.get_center().y)]


func _handles(rect: Rect2) -> Array[Vector2]:
	var points:=_projected_handles(rect)
	var visible:=Rect2(Vector2.ONE*8,(size-Vector2.ONE*16).max(Vector2.ONE))
	for index in points.size(): points[index]=points[index].clamp(visible.position,visible.end)
	if _resize_proxy_active and _drag.begins_with("resize"):
		points[int(_drag.trim_prefix("resize"))]=_resize_proxy_screen.clamp(visible.position,visible.end)
	return points


func _rotation_handle(rect: Rect2) -> Vector2:
	var points:=_projected_handles(rect)
	var outward: Vector2=(points[1]-points[5]).normalized()
	return (points[1]+outward*25).clamp(Vector2.ONE*8,(size-Vector2.ONE*8).max(Vector2.ONE*8))


func hit(point: Vector2) -> KiwiImageLayer:
	for index in range(document.layers.size()-1,-1,-1):
		var layer:=document.layers[index]
		if layer.kind == "group" or not document.can_edit(layer): continue
		var local := layer.unproject_point(document.world_transform(layer).affine_inverse()*point)
		if not Rect2(Vector2.ZERO,layer.content_dimensions()).has_point(local): continue
		if selected.has(layer.id): return layer
		if layer.kind == "shape" and layer.properties.get("shape","") == "ellipse":
			if ((local/layer.dimensions-Vector2(.5,.5))*2).length_squared()>1: continue
		if layer.kind in ["image","paint","basic"] and layer.texture!=null:
			var bitmap:=layer.texture.get_image()
			if bitmap!=null:
				var pixel:=Vector2i(local/layer.dimensions*Vector2(bitmap.get_size())).clamp(Vector2i.ZERO,bitmap.get_size()-Vector2i.ONE)
				if bitmap.get_pixelv(pixel).a<.02: continue
		return layer
	return null


func _input_canvas(event: InputEvent) -> void:
	if _material_busy: return
	if document == null: return
	if tool=="warp" and warp_tool.handle(event): accept_event(); return
	if tool=="repair" and repair_tool.handle(event): accept_event(); return
	if tool=="path" and event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		_mouse=event.position
		var at:=to_document(_mouse)
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			if _polygon_index>=0: _points=_polygon_before.duplicate(); _polygon_index=-1
			else:
				for i in _points.size():
					if _points[i].distance_to(at)*zoom<10: _points.remove_at(i); polygon_committed.emit(_points.duplicate()); break
		elif event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:
				grab_focus(); _polygon_before=_points.duplicate(); _polygon_index=-1
				for i in _points.size():
					if _points[i].distance_to(at)*zoom<10: _polygon_index=i; break
				if _polygon_index<0:
					var candidate:=_snap_polygon_point(at,event.ctrl_pressed)
					_polygon_index=_polygon_insert(candidate); _points.insert(_polygon_index,candidate)
			else:
				if _polygon_index>=0: polygon_committed.emit(_points.duplicate())
				_polygon_index=-1
		queue_redraw(); accept_event(); return
	if tool=="path" and event is InputEventMouseMotion:
		_mouse=event.position
		if _polygon_index>=0: _points[_polygon_index]=_snap_polygon_point(to_document(_mouse),event.ctrl_pressed)
		queue_redraw(); return
	if event is InputEventMouseButton:
		_mouse = event.position
		var point := to_document(event.position)
		if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
			if tool in ["crop","lasso_crop"] or (tool=="pixel_select" and pixel_mode in ["crop","lasso_crop"]) or _drag in ["shape_stroke","stroke_edit","pixel_box","pixel_lasso"]:
				cancel_gesture(); accept_event(); return
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			if event.alt_pressed and stroke_correct:
				correction_scale=clampf(correction_scale*(1.1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1.0/1.1),.1,16.0)
				correction_scale_changed.emit(correction_scale); accept_event(); return
			if event.shift_pressed and (tool=="fill" or (tool=="pixel_select" and pixel_mode=="fill" and not edge_magnet)):
				fill_threshold=clampf(fill_threshold+(.01 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -.01),0,1)
				threshold_changed.emit(fill_threshold); accept_event(); return
			if event.shift_pressed and (tool in ["brush","eraser"] or (tool=="pixel_select" and ((pixel_mode in ["brush","erase"] and not pixel_box_select) or (pixel_mode=="fill" and edge_magnet)))):
				brush_size=clampf(brush_size+maxf(1,brush_size*.12)*(1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1),1.0,500.0)
				brush_size_changed.emit(brush_size); queue_redraw(); accept_event(); return
			set_zoom(zoom*(1.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.15),event.position)
			accept_event(); return
		if event.button_index == MOUSE_BUTTON_MIDDLE or (event.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SPACE)):
			if event.pressed:
				_pan_previous_drag=_drag; _drag="pan"
			else:
				_drag=_pan_previous_drag; _pan_previous_drag=""
				if _drag=="object_preview" and _smart_ready and _smart_apply_when_ready: commit_object_selection()
			_last = event.position
			accept_event(); return
		if event.button_index != MOUSE_BUTTON_LEFT: return
		if event.pressed: grab_focus()
		if _drag=="stroke_edit":
			if event.pressed:
				_shape_handle=-1
				var handles:=_shape_handles()
				for index in handles.size():
					if _shape_screen_handle(handles[index]).distance_to(event.position)<14:
						_shape_handle=index; _shape_grab_offset=handles[index]-point; break
				if _shape_handle<0: confirm_stroke()
			else: _shape_handle=-1
			accept_event(); return
		if event.pressed:
			_start = point; _last = point; _moved = false; _pending_single=""
			_selection_operation = -1 if event.ctrl_pressed else (1 if event.shift_pressed else 0)
			if tool in ["brush","fill","pixel_select"]: _set_erase_modifier(event.ctrl_pressed)
			if tool == "move":
				var clicked:=hit(point)
				if event.double_click and clicked!=null and clicked.kind=="text":
					selected.assign([clicked.id]); selection_changed.emit(); text_edit_requested.emit(); accept_event(); return
				if not selected.is_empty():
					_bounds = selection_bounds()
					var screen := Rect2(origin()+_bounds.position*zoom,_bounds.size*zoom)
					var handles := _handles(screen)
					var nearest: int=-1
					var nearest_distance:=9.0
					for i in handles.size():
						var distance:=handles[i].distance_to(event.position)
						if distance<nearest_distance: nearest=i; nearest_distance=distance
					if nearest>=0:
						_begin_transform("resize"+str(nearest)); return
					if _rotation_handle(screen).distance_to(event.position)<10:
						_begin_transform("rotate"); return
				var layer := hit(point)
				if layer == null:
					_drag = "box"; return
				if event.double_click and layer.kind == "text":
					selected.assign([layer.id]); selection_changed.emit(); text_edit_requested.emit(); return
				if event.ctrl_pressed or event.shift_pressed:
					if selected.has(layer.id): selected.erase(layer.id)
					else: selected.append(layer.id)
				elif selected.has(layer.id) and selected.size()>1: _pending_single=layer.id
				else: selected.assign([layer.id])
				selection_changed.emit()
				if selected.is_empty(): return
				if event.alt_pressed: duplicate_requested.emit()
				_bounds = selection_bounds()
				_begin_transform("move")
			elif tool in ["brush","eraser","fill"]:
				_active_mode="circle" if Input.is_physical_key_pressed(KEY_O) else ("curve" if Input.is_physical_key_pressed(KEY_Q) else ("line" if event.shift_pressed else "freehand"))
				_begin_paint(point)
			elif tool=="pixel_select":
				if pixel_mode in ["crop","lasso_crop"]:
					_drag=pixel_mode
					if pixel_mode=="lasso_crop": _points=PackedVector2Array([point])
				else: _begin_pixel_selection(point,event.shift_pressed)
			elif tool == "picker":
				if preview != null:
					var bitmap := preview.get_image()
					if bitmap != null and Rect2(Vector2.ZERO,Vector2(document.canvas_size)).has_point(point):
						var sample:=bitmap.get_pixelv(Vector2i(point*Vector2(bitmap.get_size())/Vector2(document.canvas_size)))
						if sample.a>0: sample.r/=sample.a; sample.g/=sample.a; sample.b/=sample.a
						color_sampled.emit(sample)
			elif tool == "text": create_requested.emit("text",Rect2(point,Vector2(420,220)),PackedVector2Array())
			elif tool == "path":
				if not selected.is_empty():
					var path_layer:=document.layer_for_id(selected[-1])
					if path_layer!=null and path_layer.kind=="path" and document.can_edit(path_layer):
						var vertices: PackedVector2Array=path_layer.properties.get("points",PackedVector2Array())
						var source_size: Vector2=path_layer.properties.get("path_size",path_layer.dimensions)
						for index in vertices.size():
							var world:=document.world_transform(path_layer)*(vertices[index]*path_layer.dimensions/source_size.max(Vector2.ONE))
							if world.distance_to(point)<9/zoom:
								_vertex_index=index; _drag="vertex"; gesture_started.emit(); return
				_points.append(point); hint_changed.emit("Click adds a point · Drag handles edits a path · Enter closes path · Esc cancels")
			else:
				_drag = tool
				if tool == "lasso_crop": _points = PackedVector2Array([point])
		else:
			_finish(point)
		queue_redraw(); accept_event()
	elif event is InputEventMouseMotion:
		_mouse = event.position
		var point := to_document(event.position)
		if _drag.is_empty() and tool=="pixel_select" and edge_magnet and pixel_mode in ["brush","fill"] and not pixel_box_select and smart_selection.edges!=null:
			_edge_hover_pending=true
		if _drag == "pan": pan += event.position-_last; _last=event.position
		elif _drag == "move" or _drag.begins_with("resize") or _drag == "rotate":
			_transform(point,event.shift_pressed,event.ctrl_pressed)
		elif _drag == "paint":
			_set_erase_modifier(event.ctrl_pressed if tool=="brush" else false)
			if _corrector!=null: _corrector.add(point,Time.get_ticks_usec()/1000000.0)
			else: _paint_line(_last,point); gesture_changed.emit()
			_last=point
		elif _drag=="pixel_select":
			_set_erase_modifier(event.ctrl_pressed)
			if pixel_mode in ["brush","erase"] and not pixel_box_select:
				_edge_motion_pending=true; _edge_motion_point=point
			else:
				_pixel_brush_line(_last,point); _last=point; _update_selection_preview()
		elif _drag=="pixel_box":
			_set_erase_modifier(event.ctrl_pressed); _last=point; _update_pixel_box(point)
		elif _drag=="pixel_lasso":
			_set_erase_modifier(event.ctrl_pressed); _last=point
			if _points[-1].distance_to(point)>2.0/zoom: _points.append(point)
		elif _drag=="shape_stroke":
			_shape_end=_constrain_shape_point(point,event.shift_pressed); var chord:=_shape_end-_start
			_shape_control=_start.lerp(_shape_end,1.0/3)+Vector2(-chord.y,chord.x)*.5
			_shape_control_end=_start.lerp(_shape_end,2.0/3)+Vector2(-chord.y,chord.x)*.5
		elif _drag=="stroke_edit":
			_move_shape_handle(point+_shape_grab_offset,event.shift_pressed)
		elif _drag=="vertex":
			var path_layer:=document.layer_for_id(selected[-1])
			var vertices: PackedVector2Array=path_layer.properties.points
			var source_size: Vector2=path_layer.properties.get("path_size",path_layer.dimensions)
			vertices[_vertex_index]=(document.world_transform(path_layer).affine_inverse()*point)*source_size/path_layer.dimensions
			path_layer.properties.points=vertices; _moved=true; gesture_changed.emit()
		elif not _drag.is_empty():
			_last=point
			if _drag == "lasso_crop" and (_points.is_empty() or _points[-1].distance_to(point)>3/zoom): _points.append(point)
		queue_redraw()


func _begin_transform(action: String) -> void:
	snap_guides_x.clear(); snap_guides_y.clear()
	_resize_grab_offset=Vector2.ZERO; _resize_proxy_active=false
	if action.begins_with("resize"):
		var index:=int(action.trim_prefix("resize"))
		var screen:=Rect2(origin()+_bounds.position*zoom,_bounds.size*zoom)
		var actual:=_projected_handles(screen)[index]
		var visible:=_handles(screen)[index]
		_resize_proxy_active=not actual.is_equal_approx(visible)
		_resize_proxy_screen=origin()+_start*zoom
		_resize_grab_offset=(actual-_resize_proxy_screen)/zoom
	_drag = action
	_originals.clear()
	for layer in document.selected_roots(selected):
		if document.can_edit(layer): _originals.append({"layer":layer,"position":layer.position,"dimensions":layer.dimensions,"rotation":layer.rotation,"world":document.world_transform(layer),
			"flip_x":bool(layer.properties.get("flip_x",false)),"flip_y":bool(layer.properties.get("flip_y",false))})
	gesture_started.emit()
	hint_changed.emit("Ctrl temporarily toggles snap · Shift constrains · Esc cancels · Release commits")


func _transform(point: Vector2, constrained: bool, control: bool=false) -> void:
	snap_guides_x.clear(); snap_guides_y.clear()
	var delta := point-_start
	_moved = _moved or delta.length()>0.1
	var use_snap:=snapping != control
	if _drag == "move":
		if constrained:
			if absf(delta.x)>absf(delta.y): delta.y=0
			else: delta.x=0
		if use_snap:
			var moved := Rect2(_bounds.position+delta,_bounds.size)
			var targets_x := [0.0,document.canvas_size.x*.5,float(document.canvas_size.x)]
			var targets_y := [0.0,document.canvas_size.y*.5,float(document.canvas_size.y)]
			for other in document.layers:
				if selected.has(other.id) or not other.visible: continue
				var r := document.world_transform(other)*Rect2(Vector2.ZERO,other.dimensions)
				targets_x.append_array([r.position.x,r.get_center().x,r.end.x]); targets_y.append_array([r.position.y,r.get_center().y,r.end.y])
			var best := Vector2(7/zoom,7/zoom)
			for target: float in targets_x:
				for edge in [moved.position.x,moved.get_center().x,moved.end.x]:
					if absf(target-edge)<absf(best.x): best.x=target-edge
			for target: float in targets_y:
				for edge in [moved.position.y,moved.get_center().y,moved.end.y]:
					if absf(target-edge)<absf(best.y): best.y=target-edge
			if absf(best.x)<7/zoom:
				delta.x+=best.x
				var snapped:=Rect2(_bounds.position+delta,_bounds.size)
				for target: float in targets_x:
					if absf(target-snapped.position.x)<.01 or absf(target-snapped.get_center().x)<.01 or absf(target-snapped.end.x)<.01: snap_guides_x.append(target); break
			if absf(best.y)<7/zoom:
				delta.y+=best.y
				var snapped:=Rect2(_bounds.position+delta,_bounds.size)
				for target: float in targets_y:
					if absf(target-snapped.position.y)<.01 or absf(target-snapped.get_center().y)<.01 or absf(target-snapped.end.y)<.01: snap_guides_y.append(target); break
		for entry in _originals:
			var parent := document.layer_for_id(entry.layer.parent_id)
			var inverse := document.world_transform(parent).affine_inverse() if parent != null else Transform2D.IDENTITY
			entry.layer.position = entry.position + inverse.basis_xform(delta)
	elif _drag == "rotate":
		var center := _bounds.get_center()
		var angle := (_start-center).angle_to(point-center)
		if constrained or use_snap: angle=snappedf(angle,PI/12)
		for entry in _originals:
			entry.layer.rotation = entry.rotation+angle
			var world_center: Vector2 = entry.world*(entry.dimensions*.5)
			var destination := center+(world_center-center).rotated(angle)
			var parent := document.layer_for_id(entry.layer.parent_id)
			if parent != null: destination=document.world_transform(parent).affine_inverse()*destination
			entry.layer.position=destination-entry.dimensions*.5
	else:
		var index := int(_drag.trim_prefix("resize"))
		_resize_proxy_screen=origin()+point*zoom
		point+=_resize_grab_offset
		if _originals.size()==1:
			_resize_single(point,index,constrained,use_snap)
			gesture_changed.emit()
			return
		var low := _bounds.position
		var high := _bounds.end
		if index in [0,6,7]: low.x=point.x
		if index in [0,1,2]: low.y=point.y
		if index in [2,3,4]: high.x=point.x
		if index in [4,5,6]: high.y=point.y
		if absf(high.x-low.x)<1: high.x=low.x+(1 if high.x>=low.x else -1)
		if absf(high.y-low.y)<1: high.y=low.y+(1 if high.y>=low.y else -1)
		if use_snap:
			var targets_x: Array[float]=[0.0,document.canvas_size.x*.5,float(document.canvas_size.x)]
			var targets_y: Array[float]=[0.0,document.canvas_size.y*.5,float(document.canvas_size.y)]
			for other in document.layers:
				if selected.has(other.id) or not other.visible: continue
				var target_rect:=document.world_transform(other)*Rect2(Vector2.ZERO,other.dimensions)
				targets_x.append_array([target_rect.position.x,target_rect.get_center().x,target_rect.end.x])
				targets_y.append_array([target_rect.position.y,target_rect.get_center().y,target_rect.end.y])
			for target in targets_x:
				if index in [0,6,7] and absf(low.x-target)<7/zoom: low.x=target; snap_guides_x.assign([target])
				if index in [2,3,4] and absf(high.x-target)<7/zoom: high.x=target; snap_guides_x.assign([target])
			for target in targets_y:
				if index in [0,1,2] and absf(low.y-target)<7/zoom: low.y=target; snap_guides_y.assign([target])
				if index in [4,5,6] and absf(high.y-target)<7/zoom: high.y=target; snap_guides_y.assign([target])
		var ratio := (high-low)/_bounds.size.max(Vector2.ONE)
		var keep_aspect:=constrained
		for entry in _originals:
			if bool(entry.layer.properties.get("keep_aspect",false)): keep_aspect=true
		if keep_aspect:
			# A side handle drives only its own axis. The untouched axis stays at
			# ratio 1, so taking max(x,y) prevents shrinking and makes the anchor drift.
			var magnitude: float
			if index in [3,7]: magnitude=absf(ratio.x)
			elif index in [1,5]: magnitude=absf(ratio.y)
			else:
				# Project onto the original diagonal instead of switching driving axes.
				# This is continuous even when one cursor axis grows and the other shrinks.
				magnitude=(ratio*_bounds.size).dot(_bounds.size)/maxf(1,_bounds.size.length_squared())
				var minimum:=1.0/maxf(1,minf(_bounds.size.x,_bounds.size.y))
				if absf(magnitude)<minimum: magnitude=minimum*(-1 if magnitude<0 else 1)
			if index in [0,2,4,6]: ratio=Vector2.ONE*magnitude
			else: ratio=Vector2(magnitude*(-1 if ratio.x<0 else 1),magnitude*(-1 if ratio.y<0 else 1))
			# Hold the opposite corner, or the opposite edge's midpoint, fixed.
			var anchor:=_bounds.get_center()
			if index in [0,6,7]: anchor.x=_bounds.end.x
			elif index in [2,3,4]: anchor.x=_bounds.position.x
			if index in [0,1,2]: anchor.y=_bounds.end.y
			elif index in [4,5,6]: anchor.y=_bounds.position.y
			low=anchor+(_bounds.position-anchor)*ratio
		for entry in _originals:
			var world_center: Vector2 = entry.world*(entry.dimensions*.5)
			var destination := low+(world_center-_bounds.position)*ratio
			var parent := document.layer_for_id(entry.layer.parent_id)
			var inverse:=document.world_transform(parent).affine_inverse() if parent!=null else Transform2D.IDENTITY
			destination=inverse*destination
			var scaled_basis:=Transform2D(entry.world.x*ratio,entry.world.y*ratio,Vector2.ZERO)
			var original_basis:=inverse*Transform2D(entry.world.x,entry.world.y,Vector2.ZERO)
			var local_basis:=inverse*scaled_basis
			var dimensions: Vector2=entry.dimensions*Vector2(local_basis.x.length()/maxf(.001,original_basis.x.length()),local_basis.y.length()/maxf(.001,original_basis.y.length()))
			document.resize_layer(entry.layer,dimensions.max(Vector2.ONE))
			local_basis=local_basis.scaled_local(entry.dimensions/entry.layer.dimensions)
			entry.layer.set_linear_basis(local_basis)
			entry.layer.position=destination-entry.layer.dimensions*.5
	gesture_changed.emit()


func _resize_single(point: Vector2, index: int, constrained: bool, use_snap: bool) -> void:
	var entry: Dictionary=_originals[0]
	var layer: KiwiImageLayer=entry.layer
	var handles: Array[Vector2]=[Vector2.ZERO,Vector2(.5,0),Vector2.RIGHT,Vector2(1,.5),Vector2.ONE,Vector2(.5,1),Vector2.DOWN,Vector2(0,.5)]
	var uv:=handles[index]; var anchor:=handles[(index+4)%8]
	var original: Vector2=entry.dimensions
	var world: Transform2D=entry.world
	var frame:=layer.projected_bounds(original)
	var fixed: Vector2=world*(frame.position+anchor*frame.size)
	if use_snap:
		var targets: Array[Vector2]=[Vector2.ZERO,Vector2(document.canvas_size)*.5,Vector2(document.canvas_size)]
		for other in document.layers:
			if selected.has(other.id) or not other.visible: continue
			var bounds:=document.world_transform(other)*Rect2(Vector2.ZERO,other.dimensions)
			targets.append_array([bounds.position,bounds.get_center(),bounds.end])
		var best:=Vector2.ONE*(7/zoom)
		for target in targets:
			for axis in 2:
				if absf(target[axis]-point[axis])<absf(best[axis]): best[axis]=target[axis]-point[axis]
		for axis in 2:
			if absf(best[axis])<7/zoom: point[axis]+=best[axis]
	var desired:=world.affine_inverse().basis_xform(point-fixed)
	var span:=func(d: Vector2) -> Vector2: return (uv-anchor)*layer.projected_bounds(d).size
	var dimensions:=original
	if constrained or bool(layer.properties.get("keep_aspect",false)):
		var initial: Vector2=span.call(original)
		# Use world coordinates so the visible diagonal drives aspect locking.
		var screen_span:=world.basis_xform(initial)
		var factor:=maxf(1.0/minf(original.x,original.y),(point-fixed).dot(screen_span)/maxf(.0001,screen_span.length_squared()))
		dimensions=original*factor
	else:
		# Resize the projected envelope, not a perspective diagonal. At steep
		# yaw two opposite corners can have almost the same X/Y, making that
		# diagonal singular even though the visible image still has width/height.
		var initial: Vector2=span.call(original)
		for axis in 2:
			if not is_zero_approx(uv[axis]-anchor[axis]):
				dimensions[axis]=original[axis]*desired[axis]/initial[axis]
		dimensions=dimensions.clamp(Vector2.ONE,Vector2.ONE*100000)
	document.resize_layer(layer,dimensions)
	var parent:=document.layer_for_id(layer.parent_id)
	var inverse:=document.world_transform(parent).affine_inverse() if parent!=null else Transform2D.IDENTITY
	var basis:=layer.local_transform()
	var resized_frame:=layer.projected_bounds(dimensions)
	var local_anchor:=resized_frame.position+anchor*resized_frame.size
	layer.position=inverse*fixed-dimensions*.5-basis.basis_xform(local_anchor-dimensions*.5)


func _finish(point: Vector2) -> void:
	if warp_tool.active: warp_tool.finish(); return
	if _drag in ["object_preview","edge_pending"]: return
	_flush_edge_motion()
	snap_guides_x.clear(); snap_guides_y.clear()
	if _drag=="paint" and _corrector!=null:
		_corrector.add(point,Time.get_ticks_usec()/1000000.0)
		_flush_corrected_stroke()
	if _drag=="shape_stroke":
		_shape_end=_constrain_shape_point(point,Input.is_key_pressed(KEY_SHIFT))
		if _active_mode=="line": confirm_stroke()
		else:
			_drag="stroke_edit"; _shape_handle=-1
			hint_changed.emit("Diagonal handles: curvature · Edges: size · Center: move · Enter applies · Right-click cancels" if _active_mode=="circle" else "Drag tangent handles: bend · Endpoints: stretch · Center: move · Enter applies · Right-click cancels")
		queue_redraw(); return
	var action := _drag
	var created_paint_layer:=_paint_created_layer
	_drag = ""
	if action in ["pixel_select","pixel_box","pixel_lasso"]:
		if action=="pixel_box": _update_pixel_box(point)
		elif action=="pixel_lasso":
			_points.append(point); _apply_pixel_lasso()
		if action in ["pixel_box","pixel_lasso"]:
			var coverage:=Image.create(selection.get_width(),selection.get_height(),false,Image.FORMAT_RGBA8)
			if action=="pixel_box":
				var area:=Rect2i(Vector2i(Rect2(_start,point-_start).abs().position.floor()),Vector2i((point-_start).abs().ceil())).intersection(pixel_domain)
				coverage.fill_rect(area,Color.WHITE)
			else:
				var composed:=selection; selection=coverage; _apply_pixel_lasso(true); coverage=selection; selection=composed
			selection=preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").blend(_pixel_alpha_base,preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").feather(coverage,selection_falloff),selection_alpha,_erase_modifier or pixel_mode=="erase")
		document.pixel_selection=ImageTexture.create_from_image(selection)
		document.pixel_selection_owner=selected[-1]
		var owner:=document.layer_for_id(selected[-1])
		document.pixel_selection_reference=owner.copy_layer() if owner!=null else null
		document.pixel_selection_reference_world=document.world_transform(owner) if owner!=null else Transform2D.IDENTITY
		gesture_finished.emit(); _update_selection_preview(); _erase_modifier=false
		_points.clear(); _pixel_area_base=null; _pixel_area_previous=Rect2i(); return
	if action=="paint" and _paint_layer!=null and _paint_image!=null:
		if bool(_paint_layer.properties.get("generated_stroke",false)):
			var used:=_paint_image.get_used_rect()
			if used.size.x>0 and used.size.y>0:
				_paint_image=_paint_image.get_region(used); _paint_data=_paint_image.get_data()
				_paint_layer.position=Vector2(used.position); _paint_layer.dimensions=Vector2(used.size)
				var blank:=Image.create(used.size.x,used.size.y,false,Image.FORMAT_RGBA8); blank.fill(Color(0,0,0,0))
				_paint_layer.paint_base=ImageTexture.create_from_image(blank)
			_paint_layer.properties.erase("generated_stroke")
		# Commit a fresh texture as well as the live GPU update. This keeps the
		# final pixels authoritative on every renderer backend and in saved history.
		_replace_paint_texture()
		if _material_stamps!=null: _material_stamps.commit(_material_region)
		if _material_region!=null and _material_bake_after:
			_material_busy=true
			var finishing_document:=document; var finishing_layer:=_paint_layer
			repair_tool.workspace.renderer.sync(document)
			await repair_tool.workspace.renderer.bake_live_material(_material_template_id)
			if document!=finishing_document or _paint_layer!=finishing_layer:
				_material_busy=false; _material_region=null; return
			if document.live_material_for_id(_material_previous_template)!=null: document.active_live_material_id=_material_previous_template
			_material_busy=false
		elif (tool=="eraser" or _erase_modifier) and not _paint_layer.live_paint.is_empty() and _stroke_ink!=null and _live_eraser==null:
			var erase_mask:=Image.create(_paint_image.get_width(),_paint_image.get_height(),false,Image.FORMAT_RGBA8)
			erase_mask.blit_rect(_stroke_ink,Rect2i(Vector2i.ZERO,_stroke_ink.get_size()),_ink_origin)
			var erase_bytes:=erase_mask.get_data(); var erase_frame:=document.world_transform(_paint_layer); var erase_scale:=_paint_layer.dimensions/Vector2(erase_mask.get_size())
			for y in erase_mask.get_height():
				for x in erase_mask.get_width():
					var offset: int=(y*erase_mask.get_width()+x)*4+3
					erase_bytes[offset]=roundi(erase_bytes[offset]*brush_opacity*(selection_coverage(erase_frame*Vector2(x,y)*erase_scale) if paint_selection_only else 1.0))
			erase_mask.set_data(erase_mask.get_width(),erase_mask.get_height(),false,Image.FORMAT_RGBA8,erase_bytes)
			_paint_layer.erase_live_paint(erase_mask)
	if action in ["move","rotate","paint","vertex"] or action.begins_with("resize"):
		if action=="move" and not _moved and not _pending_single.is_empty():
			gesture_cancelled.emit(); selected.assign([_pending_single]); selection_changed.emit()
		elif action == "paint" or _moved: gesture_finished.emit()
		else: gesture_cancelled.emit()
	elif action == "box":
		if _selection_operation == 0: selected.clear()
		var rect := Rect2(_start,point-_start).abs()
		for layer in document.layers:
			if layer.kind == "group" or not document.can_edit(layer): continue
			if rect.intersects(document.world_transform(layer)*Rect2(Vector2.ZERO,layer.dimensions)):
				if _selection_operation == -1: selected.erase(layer.id)
				elif not selected.has(layer.id): selected.append(layer.id)
		selection_changed.emit()
	elif action=="lasso_crop" and _points.size()>2:
		var bounds:=Rect2(_points[0],Vector2.ZERO)
		for vertex in _points: bounds=bounds.expand(vertex)
		create_requested.emit("lasso_crop",bounds,_points.duplicate())
	elif action in ["crop","shape"]:
		var rect := Rect2(_start,point-_start).abs()
		if rect.size.x>2 and rect.size.y>2: create_requested.emit(action,rect,PackedVector2Array())
	if tool != "path": _points.clear()
	_material_region=null; _material_template_id=""; _material_stamps=null; _live_eraser=null
	_paint_image = null; _paint_data.clear(); _paint_layer = null; _stroke_base=null; _stroke_points.clear()
	_corrector=null; _corrected_tail_bounds=Rect2i(); _ink_origin=Vector2i.ZERO
	_erase_modifier=false
	_pending_single=""
	_paint_created_layer=false
	hint_changed.emit("")
	if created_paint_layer: selection_changed.emit()
	if painting_mode=="material": repair_tool.workspace._refresh_context()


func cancel_gesture() -> void:
	warp_tool.cancel()
	repair_tool.cancel()
	_edge_motion_pending=false; _edge_hover_pending=false
	_object_committed.clear(); _pan_previous_drag=""
	smart_selection.cancel_request(); _smart_request=-1; _smart_ready=false; _smart_apply_when_ready=false
	_edge_follower.previous=-1; _edge_preview=Vector2.INF
	snap_guides_x.clear(); snap_guides_y.clear()
	_polygon_index=-1
	if not _drag.is_empty() and _drag not in ["pan","box","shape","crop","lasso_crop"]: gesture_cancelled.emit()
	_material_region=null; _material_template_id=""; _material_stamps=null; _live_eraser=null
	_drag=""; _points.clear(); _paint_image=null; _paint_data.clear(); _paint_layer=null; _stroke_base=null; _stroke_points.clear()
	_corrector=null; _corrected_tail_bounds=Rect2i(); _ink_origin=Vector2i.ZERO
	_erase_modifier=false
	sync_pixel_selection()
	_pixel_area_base=null; _pixel_area_previous=Rect2i()
	if _paint_created_layer: selected.clear(); _paint_created_layer=false; selection_changed.emit()
	queue_redraw()


func finish_path() -> void:
	_polygon_index=-1
	if _points.size()<3: return
	var rect := Rect2(_points[0],Vector2.ZERO)
	for point in _points: rect=rect.expand(point)
	var local := PackedVector2Array()
	for point in _points: local.append(point-rect.position)
	create_requested.emit("path",rect,local)
	_points.clear(); queue_redraw()


func _begin_paint(point: Vector2) -> void:
	if _material_busy: return
	_material_region=null; _material_template_id=""; _material_flood_source=null; _material_stamps=null; _live_eraser=null
	if paint_selection_only and selection==null:
		hint_changed.emit("Select pixels first, or turn off Selection only."); return
	if paint_new_layer and tool=="brush" and brush_type!="soften" and not _erase_modifier:
		gesture_started.emit()
		_paint_layer=KiwiImageLayer.create("basic",document.canvas_size); _paint_layer.label="Brush stroke"
		_paint_layer.properties.generated_stroke=true
		document.layers.append(_paint_layer); selected.assign([_paint_layer.id]); _paint_created_layer=true
	elif selected.is_empty(): return
	else: _paint_layer=document.layer_for_id(selected[-1])
	if _paint_layer == null or not document.can_edit(_paint_layer): return
	if _paint_layer.kind not in ["image","paint","basic"]:
		hint_changed.emit("Preparing this layer for pixel editing…"); return
	if _paint_layer.texture==null:
		hint_changed.emit("This layer has no raster pixels to paint."); return
	var material_paint:=painting_mode=="material" and tool in ["brush","fill"] and (tool=="fill" or brush_type!="soften") and not _erase_modifier
	if tool=="fill" and (material_paint or not _paint_layer.live_paint.is_empty()):
		if _paint_layer.live_paint.is_empty(): _material_flood_source=_paint_layer.texture.get_image().duplicate()
		else:
			var source_document:=document; var source_layer:=_paint_layer; var source_tool:=tool
			_material_busy=true
			_material_flood_source=await repair_tool.workspace.renderer.source_image(source_layer)
			_material_busy=false
			if document!=source_document or _paint_layer!=source_layer or tool!=source_tool or document.layer_for_id(source_layer.id)!=source_layer: return
			if _material_flood_source==null: hint_changed.emit("Could not read this layer for Bucket fill."); return
	if not _paint_created_layer: gesture_started.emit()
	if material_paint:
		_material_previous_template=document.active_live_material_id
		var template=document.live_material_for_id(document.active_live_material_id) if document.live_edit_enabled else null
		if template==null: template=document.create_live_material(repair_tool.material)
		_material_template_id=template.id; _material_bake_after=not document.live_edit_enabled
		var mapping:=document.world_transform(_paint_layer) if template.material.alignment=="canvas" else Transform2D.IDENTITY
		if template.material.alignment=="stroke":
			mapping=Transform2D(0.0,-(document.world_transform(_paint_layer).affine_inverse()*point))
		_material_region=document.add_live_region(_paint_layer,template.id,null,mapping)
		_material_stroke_anchor=point; _material_direction_set=false
		_paint_layer.properties.erase("generated_stroke")
	_paint_image=_paint_layer.texture.get_image() if _paint_layer.texture != null else null
	if _material_region!=null: _paint_image=_material_region.coverage.get_image()
	if _paint_image == null: gesture_cancelled.emit(); return
	if _paint_layer.paint_base==null: _paint_layer.paint_base=_paint_layer.texture
	_paint_image=_paint_image.duplicate()
	_paint_image.convert(Image.FORMAT_RGBA8)
	_paint_data=_paint_image.get_data()
	if _material_region!=null and tool=="brush":
		var material=document.live_material_for_id(_material_template_id).material
		if material.application in ["stamp","scatter"]:
			_material_stamps=preload("res://Workspaces/ImageWorkspace/image_material_stamps.gd").new()
			_material_stamps.begin(self,material)
	_replace_paint_texture()
	_stroke_base=_paint_image.duplicate(); _stroke_points=PackedVector2Array([point])
	_soften_source=null
	_stroke_ink=Image.create(_paint_image.get_width(),_paint_image.get_height(),false,Image.FORMAT_RGBA8)
	_stroke_ink.fill(Color(0,0,0,0)); _stroke_dirty=Rect2i()
	_corrector=null; _corrected_tail_bounds=Rect2i(); _ink_origin=Vector2i.ZERO
	_corrected_stamp_distance=0.0; _corrected_started=false
	_corrected_all_bounds=Rect2i()
	_drag="paint"
	if tool == "fill":
		if _material_region!=null: _material_flood(point)
		else: _flood(point)
		_finish(point)
	elif _active_mode!="freehand" and tool=="brush":
		_start=point; _shape_end=point; _shape_control=point; _shape_control_end=point; _circle_profiles=Vector4(2,2,2,2); _drag="shape_stroke"
	elif tool=="brush" and stroke_correct and correction_strength>0.0 and not _erase_modifier:
		_corrector=KiwiStrokeCorrector.new()
		_corrector.begin(point,correction_strength,brush_size,Time.get_ticks_usec()/1000000.0,correction_scale)
		_flush_corrected_stroke()
	else: _paint_line(point,point)
	gesture_changed.emit()


func _shape_path() -> PackedVector2Array:
	if _active_mode=="line": return PackedVector2Array([_start,_shape_end])
	var points:=PackedVector2Array()
	if _active_mode=="circle":
		var center:=(_start+_shape_end)*.5; var radius:=(_shape_end-_start).abs()*.5
		var count:=clampi(ceili(TAU*maxf(radius.x,radius.y)/maxf(2,brush_size*.2)),24,256)
		for index in count+1:
			var angle:=TAU*index/count
			var power:=2.0/_circle_profiles[mini(3,int(floor(angle/(PI*.5))))]
			var direction:=Vector2(cos(angle),sin(angle))
			points.append(center+Vector2(signf(direction.x)*pow(absf(direction.x),power),signf(direction.y)*pow(absf(direction.y),power))*radius)
	else:
		var count:=clampi(ceili((_start.distance_to(_shape_control)+_shape_control.distance_to(_shape_end))/maxf(2,brush_size*.2)),8,256)
		for index in count+1:
			var t:=float(index)/count
			points.append(_start*pow(1-t,3)+_shape_control*3*pow(1-t,2)*t+_shape_control_end*3*(1-t)*t*t+_shape_end*t*t*t)
	return points


func _shape_handles() -> Array[Vector2]:
	if _active_mode=="line": return []
	if _active_mode=="curve": return [_start,_shape_end,_shape_control,_shape_control_end,(_start+_shape_end)*.5]
	var rect:=Rect2(_start,_shape_end-_start).abs()
	var center:=rect.get_center(); var radius:=rect.size*.5
	return [center-radius*pow(.5,1.0/_circle_profiles.z),Vector2(center.x,rect.position.y),center+Vector2(1,-1)*radius*pow(.5,1.0/_circle_profiles.w),Vector2(rect.end.x,center.y),center+radius*pow(.5,1.0/_circle_profiles.x),Vector2(center.x,rect.end.y),center+Vector2(-1,1)*radius*pow(.5,1.0/_circle_profiles.y),Vector2(rect.position.x,center.y),center]


func _shape_screen_handle(point: Vector2) -> Vector2:
	return (origin()+point*zoom).clamp(Vector2.ONE*12,(size-Vector2.ONE*12).max(Vector2.ONE*12))


func _move_shape_handle(point: Vector2,constrained: bool) -> void:
	if _shape_handle<0: return
	if _shape_handle==(4 if _active_mode=="curve" else 8):
		var delta:=point-(_start+_shape_end)*.5
		_start+=delta; _shape_end+=delta; _shape_control+=delta; _shape_control_end+=delta
	elif _active_mode=="curve":
		match _shape_handle:
			0: _shape_control+=point-_start; _start=point
			1: _shape_control_end+=point-_shape_end; _shape_end=point
			2: _shape_control=point
			3: _shape_control_end=point
	else:
		var rect:=Rect2(_start,_shape_end-_start).abs(); _start=rect.position; _shape_end=rect.end
		if _shape_handle in [0,2,4,6]:
			var relative:=(point-rect.get_center()).abs()/(rect.size*.5).max(Vector2.ONE)
			var fraction:=clampf((relative.x+relative.y)*.5,.18,.94)
			_circle_profiles[[2,3,0,1][_shape_handle/2]]=clampf(log(.5)/log(fraction),.4,12)
			return
		if _shape_handle in [0,6,7]: _start.x=point.x
		if _shape_handle in [0,1,2]: _start.y=point.y
		if _shape_handle in [2,3,4]: _shape_end.x=point.x
		if _shape_handle in [4,5,6]: _shape_end.y=point.y
		_shape_end=_constrain_shape_point(_shape_end,constrained)


func _constrain_shape_point(point: Vector2,constrained: bool) -> Vector2:
	if _active_mode!="circle" or not constrained: return point
	var delta:=point-_start
	var diameter:=maxf(absf(delta.x),absf(delta.y))
	return _start+Vector2(-diameter if delta.x<0 else diameter,-diameter if delta.y<0 else diameter)


func confirm_stroke() -> void:
	if _drag not in ["shape_stroke","stroke_edit"]: return
	var path:=_shape_path()
	for index in range(1,path.size()): _paint_line(path[index-1],path[index],false)
	if _erase_modifier: _upload_paint()
	else: _upload_native_paint()
	_drag="paint"; _finish(_shape_end)


func selected_pixel(point: Vector2) -> bool:
	return selection_coverage(point)>0.0

func selection_coverage(point: Vector2) -> float:
	if selection == null: return 1.0
	var source_point: Vector2=selection_inverse_warp.call(point) if selection_inverse_warp.is_valid() else selection_inverse*point
	var at := Vector2i(source_point.floor())
	return selection.get_pixelv(at).a if at.x>=0 and at.y>=0 and at.x<selection.get_width() and at.y<selection.get_height() else 0.0


func _paint_pixel_allowed(point: Vector2) -> bool:
	return not paint_selection_only or (selection!=null and selected_pixel(point))


func _set_erase_modifier(enabled: bool) -> void:
	if _material_region!=null and _drag=="paint": return
	if _erase_modifier==enabled: return
	if _drag=="pixel_select" and _pixel_alpha_ink!=null and selection!=null:
		_pixel_alpha_base=selection.duplicate(); _pixel_alpha_ink.fill(Color.TRANSPARENT)
	if _drag=="paint" and _paint_image!=null:
		if _corrector!=null: _flush_corrected_stroke()
		_corrector=null
		# Each modifier phase starts from the live pixels. A later drawing
		# preview must not restore pixels erased earlier in the same gesture.
		_paint_data=_paint_image.get_data(); _stroke_base=_paint_image.duplicate()
		_soften_source=null; _live_eraser=null
		_stroke_ink.fill(Color.TRANSPARENT); _stroke_dirty=Rect2i()
		_corrected_tail_bounds=Rect2i(); _corrected_all_bounds=Rect2i()
		_corrected_started=false; _corrected_stamp_distance=0.0
		if not enabled and tool=="brush" and _active_mode=="freehand" and stroke_correct and correction_strength>0:
			_corrector=KiwiStrokeCorrector.new()
			_corrector.begin(_last,correction_strength,brush_size,Time.get_ticks_usec()/1000000.0,correction_scale)
	_erase_modifier=enabled


func _corrected_path_bounds(path: PackedVector2Array) -> Rect2i:
	if path.is_empty(): return Rect2i()
	var inverse:=document.world_transform(_paint_layer).affine_inverse()
	var ratio:=Vector2(_paint_image.get_size())/_paint_layer.dimensions
	var bounds:=Rect2((inverse*path[0])*ratio,Vector2.ZERO)
	for point in path: bounds=bounds.expand((inverse*point)*ratio)
	var radius: Vector2=Vector2.ONE*brush_size*ratio*.5*(_material_stamps.radius_factor() if _material_stamps!=null else 1.0)+Vector2.ONE*3
	return Rect2i(Vector2i((bounds.position-radius).floor()),Vector2i((bounds.size+radius*2).ceil())).intersection(Rect2i(Vector2i.ZERO,_paint_image.get_size()))


func _paint_corrected_path(path: PackedVector2Array,commit: bool=false) -> void:
	if path.is_empty(): return
	# Raster sampling depends on brush width, not the number of fitted knots.
	# This avoids hundreds of identical large-brush stamps along a short tail.
	# Keep a continuous stamp phase across sealed patches, so event frequency
	# and preview revisions do not alter the softness or thickness of a stroke.
	var interval: float=_material_stamps.interval(self) if _material_stamps!=null else maxf(1.0,brush_size*.15)
	var distance:=_corrected_stamp_distance
	var stamped:=Vector2(INF,INF)
	if not _corrected_started:
		_paint_line(path[0],path[0],false); stamped=path[0]
		if commit: _corrected_started=true
	for index in range(1,path.size()):
		if _material_stamps!=null: _material_stamps.direction=(document.world_transform(_paint_layer).affine_inverse().basis_xform(path[index]-path[index-1])).angle()
		var length:=path[index-1].distance_to(path[index])
		var travel:=interval-distance
		while travel<=length and length>.00001:
			stamped=path[index-1].lerp(path[index],travel/length)
			_paint_line(stamped,stamped,false); travel+=interval
		distance=fmod(distance+length,interval)
	if commit: _corrected_stamp_distance=distance
	elif not stamped.is_equal_approx(path[-1]): _paint_line(path[-1],path[-1],false)


func _flush_corrected_stroke() -> void:
	if _corrector==null or _paint_layer==null or _paint_image==null: return
	var patch:=_corrector.update()
	if patch.is_empty(): return
	if _material_stamps!=null: _material_stamps.restore_tail()
	if patch.has("replace"):
		var shape: PackedVector2Array=patch.replace
		var area:=_corrected_path_bounds(shape)
		if _corrected_all_bounds.has_area(): area=area.merge(_corrected_all_bounds)
		if not area.has_area(): return
		_stroke_ink.fill_rect(area,Color.TRANSPARENT)
		_corrected_started=false; _corrected_stamp_distance=0.0
		_paint_corrected_path(shape)
		_stroke_dirty=area; _upload_native_paint()
		_corrected_all_bounds=area
		gesture_changed.emit(); return
	var fixed: PackedVector2Array=patch.fixed
	var tail: PackedVector2Array=patch.tail
	_paint_corrected_path(fixed,true)
	var tail_bounds:=_corrected_path_bounds(tail)
	var region:=tail_bounds
	for area in [_corrected_tail_bounds,_stroke_dirty]:
		if area.has_area(): region=region.merge(area) if region.has_area() else area
	if region.has_area():
		# Stable ink contains only sealed segments. The mutable tail is rebuilt
		# on a small tile, then composited once against the original stroke base.
		# Old tail pixels disappear cleanly, including at self intersections.
		var stable:=_stroke_ink
		if _material_stamps!=null: _material_stamps.capture_tail(region)
		_stroke_ink=stable.get_region(region); _ink_origin=region.position
		_paint_corrected_path(tail)
		_stroke_dirty=region
		_upload_native_paint()
		_stroke_ink=stable; _ink_origin=Vector2i.ZERO
	_corrected_tail_bounds=tail_bounds
	if region.has_area(): _corrected_all_bounds=region if not _corrected_all_bounds.has_area() else _corrected_all_bounds.merge(region)
	gesture_changed.emit()


func _paint_line(from: Vector2,to: Vector2,upload: bool=true) -> void:
	if _material_stamps!=null:
		_material_stamps.paint_line(self,from,to,upload); return
	if _material_region!=null and not _material_direction_set and from.distance_squared_to(to)>1:
		var template=document.live_material_for_id(_material_template_id)
		if template!=null and template.material.alignment=="stroke":
			var inverse:=document.world_transform(_paint_layer).affine_inverse()
			var angle:=-((inverse*to)-(inverse*from)).angle()
			_material_region.mapping=Transform2D(angle,-(inverse*_material_stroke_anchor).rotated(angle))
		_material_direction_set=true
	if _paint_image == null or _paint_layer == null: return
	if _stroke_ink!=null:
		_prepare_source_color()
		var stamp_color:=color if bool(_paint_layer.properties.get("values_selection_only",false)) else _value_inverse_color
		if _material_region!=null: stamp_color=Color.WHITE
		if tool=="eraser" or _erase_modifier: stamp_color=Color.WHITE
		elif tool=="brush" and brush_type=="soften": stamp_color=Color.WHITE
		var inverse:=document.world_transform(_paint_layer).affine_inverse()
		var ratio:=Vector2(_paint_image.get_size())/_paint_layer.dimensions
		var stamp_size:=Vector2i((Vector2.ONE*brush_size*ratio).ceil()).max(Vector2i.ONE)
		var key:=str([stamp_size,hardness,stamp_color])
		if _stamp==null or _stamp_key!=key:
			_stamp_key=key
			var source_size:=mini(64,maxi(stamp_size.x,stamp_size.y))
			_stamp=Image.create(source_size,source_size,false,Image.FORMAT_RGBA8)
			for y in source_size:
				for x in source_size:
					var distance:=(Vector2(x,y)-Vector2.ONE*floorf(source_size*.5)).length()/maxf(.5,source_size*.5)
					var tint:=stamp_color; tint.a=clampf((1-distance)/maxf(.001,1-hardness),0,1)
					_stamp.set_pixel(x,y,tint)
			_stamp.resize(stamp_size.x,stamp_size.y,Image.INTERPOLATE_BILINEAR)
		var steps:=maxi(1,ceili(from.distance_to(to)/maxf(1,brush_size*.15)))
		for index in (1 if from.is_equal_approx(to) else steps+1):
			var center:=(inverse*from.lerp(to,float(index)/steps))*ratio
			var target:=Vector2i(center)-stamp_size/2
			_stroke_ink.blend_rect(_stamp,Rect2i(Vector2i.ZERO,stamp_size),target-_ink_origin)
			var area:=Rect2i(target,stamp_size).intersection(Rect2i(Vector2i.ZERO,_paint_image.get_size()))
			if area.has_area(): _stroke_dirty=area if not _stroke_dirty.has_area() else _stroke_dirty.merge(area)
		if upload: _upload_native_paint()
		return
	var transform := document.world_transform(_paint_layer)
	var inverse := transform.affine_inverse()
	var ratio := Vector2(_paint_image.get_size())/_paint_layer.dimensions
	var steps := maxi(1,ceili(from.distance_to(to)/maxf(1,brush_size*.25)))
	var radius := maxf(.5,brush_size*.5*ratio.x)
	for step in steps+1:
		var center := (inverse*from.lerp(to,float(step)/steps))*ratio
		for y in range(maxi(0,floori(center.y-radius)),mini(_paint_image.get_height(),ceili(center.y+radius+1))):
			for x in range(maxi(0,floori(center.x-radius)),mini(_paint_image.get_width(),ceili(center.x+radius+1))):
				var distance := Vector2(x,y).distance_to(center)/radius
				if distance>1 or not _paint_pixel_allowed(transform*(Vector2(x,y)/ratio)): continue
				var alpha := brush_opacity*clampf((1-distance)/maxf(.001,1-hardness),0,1)*(selection_coverage(transform*(Vector2(x,y)/ratio)) if paint_selection_only else 1.0)
				var offset: int=(y*_paint_image.get_width()+x)*4
				var old_alpha:=float(_paint_data[offset+3])/255.0
				if tool == "eraser" or _erase_modifier: _paint_data[offset+3]=clampi(roundi(float(_paint_data[offset+3])*(1.0-alpha)),0,255)
				else:
					var source_alpha:=alpha*color.a; var result_alpha:=source_alpha+old_alpha*(1.0-source_alpha)
					for channel in 3:
						var old_value:=float(_paint_data[offset+channel])/255.0
						var source_value: float=float(color[channel])
						_paint_data[offset+channel]=clampi(roundi(255.0*(source_value*source_alpha+old_value*old_alpha*(1.0-source_alpha))/maxf(result_alpha,.00001)),0,255)
					_paint_data[offset+3]=clampi(roundi(result_alpha*255.0),0,255)
	if upload: _upload_paint()


func _upload_paint() -> void:
	_paint_image.set_data(_paint_image.get_width(),_paint_image.get_height(),false,Image.FORMAT_RGBA8,_paint_data)
	_update_paint_texture()
	queue_redraw()


func _upload_native_paint() -> void:
	_prepare_source_color()
	if _stroke_ink!=null and _stroke_dirty.has_area():
		var ink:=_stroke_ink.get_region(Rect2i(_stroke_dirty.position-_ink_origin,_stroke_dirty.size))
		if tool=="brush" and brush_type=="soften" and not _erase_modifier:
			var soften=preload("res://Workspaces/ImageWorkspace/image_soften_brush.gd")
			if _soften_source==null:
				_soften_opaque=_stroke_base.detect_alpha()==Image.ALPHA_NONE
				_soften_source=soften.prepare(_stroke_base,brush_size*.08*float(_paint_image.get_width())/maxf(1,_paint_layer.dimensions.x))
			var coverage:=Callable()
			if paint_selection_only:
				var frame:=document.world_transform(_paint_layer); var scale:=_paint_layer.dimensions/Vector2(_paint_image.get_size())
				coverage=func(point: Vector2): return selection_coverage(frame*_paint_layer.project_point(point*scale))
			var patch: Image=soften.composite(_stroke_base,_soften_source,ink,_stroke_dirty,soften_strength,brush_opacity,coverage,_soften_opaque)
			_paint_image.blit_rect(patch,Rect2i(Vector2i.ZERO,patch.get_size()),_stroke_dirty.position)
			_stroke_dirty=Rect2i(); _update_paint_texture(); queue_redraw(); return
		if tool=="eraser" or _erase_modifier:
			var bytes:=_stroke_base.get_region(_stroke_dirty).get_data(); var coverage_bytes:=ink.get_data()
			var frame:=document.world_transform(_paint_layer); var ratio:=_paint_layer.dimensions/Vector2(_paint_image.get_size())
			for y in _stroke_dirty.size.y:
				for x in _stroke_dirty.size.x:
					var offset: int=(y*_stroke_dirty.size.x+x)*4+3
					var point:=frame*_paint_layer.project_point(Vector2(_stroke_dirty.position+Vector2i(x,y))*ratio)
					var coverage:=coverage_bytes[offset]/255.0*brush_opacity*(selection_coverage(point) if paint_selection_only else 1.0)
					bytes[offset]=roundi(bytes[offset]*(1-coverage))
					coverage_bytes[offset]=roundi(coverage*255)
			_paint_image.blit_rect(Image.create_from_data(_stroke_dirty.size.x,_stroke_dirty.size.y,false,Image.FORMAT_RGBA8,bytes),Rect2i(Vector2i.ZERO,_stroke_dirty.size),_stroke_dirty.position)
			if not _paint_layer.live_paint.is_empty():
				if _live_eraser==null:
					_live_eraser=preload("res://Workspaces/ImageWorkspace/image_live_eraser.gd").new(); _live_eraser.begin(_paint_layer,_paint_image.get_size())
				_live_eraser.apply(_stroke_dirty,Image.create_from_data(ink.get_width(),ink.get_height(),false,Image.FORMAT_RGBA8,coverage_bytes))
			_stroke_dirty=Rect2i(); _update_paint_texture(); queue_redraw(); return
		var masked_values:=_material_region==null and bool(_paint_layer.properties.get("values_selection_only",false)) and not preload("res://Workspaces/ImageWorkspace/image_values.gd").operations(_paint_layer).is_empty()
		var opacity:=clampf(brush_opacity*(material_strength if _material_region!=null else (color.a if masked_values else _value_inverse_color.a)),0,1)
		if opacity<1 and not paint_selection_only and not masked_values:
			var bytes:=ink.get_data()
			for offset in range(3,bytes.size(),4): bytes[offset]=roundi(bytes[offset]*opacity)
			ink.set_data(ink.get_width(),ink.get_height(),false,Image.FORMAT_RGBA8,bytes)
		elif paint_selection_only or masked_values:
			var bytes:=ink.get_data()
			var transform:=document.world_transform(_paint_layer)
			var ratio:=_paint_layer.dimensions/Vector2(_paint_image.get_size())
			for y in ink.get_height():
				for x in ink.get_width():
					var offset: int=(y*ink.get_width()+x)*4+3
					bytes[offset]=roundi(bytes[offset]*opacity)
					if bytes[offset]>0 and masked_values:
						var source:=_source_color(transform*(Vector2(_stroke_dirty.position+Vector2i(x,y))*ratio))
						bytes[offset]=clampi(roundi(bytes[offset]*source.a/maxf(.00001,color.a)),0,255)
						for channel in 3: bytes[offset-3+channel]=roundi(clampf(source[channel],0,1)*255)
			ink.set_data(ink.get_width(),ink.get_height(),false,Image.FORMAT_RGBA8,bytes)
		_paint_image.blit_rect(_stroke_base,_stroke_dirty,_stroke_dirty.position)
		_paint_image.blend_rect(ink,Rect2i(Vector2i.ZERO,ink.get_size()),_stroke_dirty.position)
		if paint_selection_only:
			var changed:=_paint_image.get_region(_stroke_dirty).get_data(); var original:=_stroke_base.get_region(_stroke_dirty).get_data()
			var frame:=document.world_transform(_paint_layer); var pixel_scale:=_paint_layer.dimensions/Vector2(_paint_image.get_size())
			for y in _stroke_dirty.size.y:
				for x in _stroke_dirty.size.x:
					var coverage:=selection_coverage(frame*_paint_layer.project_point(Vector2(_stroke_dirty.position+Vector2i(x,y))*pixel_scale))
					var offset: int=(y*_stroke_dirty.size.x+x)*4
					for channel in 4: changed[offset+channel]=roundi(lerpf(original[offset+channel],changed[offset+channel],coverage))
			_paint_image.blit_rect(Image.create_from_data(_stroke_dirty.size.x,_stroke_dirty.size.y,false,Image.FORMAT_RGBA8,changed),Rect2i(Vector2i.ZERO,_stroke_dirty.size),_stroke_dirty.position)
		_stroke_dirty=Rect2i()
	_update_paint_texture()
	queue_redraw()


func _replace_paint_texture() -> void:
	if _material_region!=null: _material_region.coverage=ImageTexture.create_from_image(_paint_image)
	else: _paint_layer.texture=ImageTexture.create_from_image(_paint_image)

func _update_paint_texture() -> void:
	if _material_stamps!=null and _material_region!=null: _material_stamps.upload(_material_region)
	if _material_region!=null:
		if _material_region.coverage is ImageTexture: (_material_region.coverage as ImageTexture).update(_paint_image)
		else: _material_region.coverage=ImageTexture.create_from_image(_paint_image)
	elif _paint_layer.texture is ImageTexture: (_paint_layer.texture as ImageTexture).update(_paint_image)
	else: _paint_layer.texture=ImageTexture.create_from_image(_paint_image)
	if repair_tool!=null and is_instance_valid(repair_tool.workspace): repair_tool.workspace.renderer.invalidate_layer(_paint_layer.id)


func _paint_curve(from: Vector2,control: Vector2,to: Vector2) -> void:
	var previous:=from
	for index in 33:
		var t:=float(index)/32.0
		var next:=from*(1.0-t)*(1.0-t)+control*2.0*(1.0-t)*t+to*t*t
		_paint_line(previous,next,false); previous=next
	_upload_native_paint()


func _curve_control(from: Vector2,to: Vector2) -> Vector2:
	if _stroke_points.size()<2 or from.distance_squared_to(to)<1: return from.lerp(to,.5)
	var chord:=to-from; var length_squared:=chord.length_squared(); var best:=from.lerp(to,.5); var best_distance:=-1.0; var best_t:=.5
	for point in _stroke_points:
		var t:=clampf((point-from).dot(chord)/length_squared,.12,.88)
		var distance:=point.distance_squared_to(from+chord*t)
		if distance>best_distance: best_distance=distance; best=point; best_t=t
	var inverse:=2.0*(1.0-best_t)*best_t
	return (best-from*(1.0-best_t)*(1.0-best_t)-to*best_t*best_t)/maxf(inverse,.001)


func _flood(point: Vector2) -> void:
	_prepare_source_color()
	var transform := document.world_transform(_paint_layer)
	var ratio := Vector2(_paint_image.get_size())/_paint_layer.dimensions
	var start := Vector2i((transform.affine_inverse()*point)*ratio)
	if not Rect2i(Vector2i.ZERO,_paint_image.get_size()).has_point(start): return
	# Empty paint layers are the overwhelmingly common full-canvas fill. Let the
	# native Image implementation handle it in one call instead of visiting a
	# million transparent pixels in script.
	if _material_flood_source==null and not paint_selection_only and not bool(_paint_layer.properties.get("values_selection_only",false)) and _paint_image.get_used_rect().size==Vector2i.ZERO:
		_paint_image.fill(Color.TRANSPARENT if _erase_modifier else _source_color(point)); _paint_data=_paint_image.get_data(); _upload_paint(); return
	var width:=_paint_image.get_width(); var height:=_paint_image.get_height(); var start_offset:=(start.y*width+start.x)*4
	var detection:=_material_flood_source.get_data() if _material_flood_source!=null else _paint_data.duplicate()
	var target:=detection.slice(start_offset,start_offset+4)
	var fill_color:=Color.TRANSPARENT if _erase_modifier else color
	var replacement:=PackedByteArray([roundi(fill_color.r*255),roundi(fill_color.g*255),roundi(fill_color.b*255),roundi(fill_color.a*255)])
	if target==replacement: return
	var stack: Array[Vector2i] = [start]
	var visited := PackedByteArray(); visited.resize(width*height)
	var lower_erase: Image=Image.create(width,height,false,Image.FORMAT_RGBA8) if _erase_modifier and not _paint_layer.live_paint.is_empty() else null
	var threshold_squared:=pow(canvas_threshold_bytes(fill_threshold),2)
	var matches:=func(x: int,y: int) -> bool:
		if x<0 or y<0 or x>=width or y>=height: return false
		var pixel_index:=y*width+x
		if visited[pixel_index]!=0: return false
		var offset:=pixel_index*4; var difference:=0.0
		for channel in 4: difference+=pow(float(detection[offset+channel])-float(target[channel]),2)
		return difference<=threshold_squared and _paint_pixel_allowed(transform*(Vector2(x,y)/ratio))
	while not stack.is_empty():
		var p: Vector2i=stack.pop_back()
		if not matches.call(p.x,p.y): continue
		var x:=p.x
		while matches.call(x-1,p.y): x-=1
		var span_up:=false; var span_down:=false
		while x<width and matches.call(x,p.y):
			var pixel_index:=p.y*width+x; visited[pixel_index]=1; var offset:=pixel_index*4
			var source:=Color.TRANSPARENT if _erase_modifier else _source_color(transform*(Vector2(x,p.y)/ratio))
			var coverage:=selection_coverage(transform*(Vector2(x,p.y)/ratio)) if paint_selection_only else 1.0
			for channel in 4: _paint_data[offset+channel]=roundi(lerpf(_paint_data[offset+channel],clampf(source[channel],0,1)*255,coverage))
			if lower_erase!=null: lower_erase.set_pixel(x,p.y,Color(1,1,1,coverage))
			var up: bool=p.y>0 and bool(matches.call(x,p.y-1))
			if up and not span_up: stack.append(Vector2i(x,p.y-1))
			span_up=up
			var down: bool=p.y<height-1 and bool(matches.call(x,p.y+1))
			if down and not span_down: stack.append(Vector2i(x,p.y+1))
			span_down=down; x+=1
	if lower_erase!=null: _paint_layer.erase_live_paint(lower_erase)
	_upload_paint()


func canvas_threshold_bytes(value: float) -> float:
	return clampf(value,0,1)*510.0


func _make_selection(kind: String,rect: Rect2) -> void:
	if selection == null or _selection_operation == 0:
		selection=Image.create(document.canvas_size.x,document.canvas_size.y,false,Image.FORMAT_RGBA8)
		selection.fill(Color(0,0,0,0))
	if kind == "lasso" and _points.size()>2:
		rect=Rect2(_points[0],Vector2.ZERO)
		for point in _points: rect=rect.expand(point)
	for y in range(maxi(0,floori(rect.position.y)),mini(selection.get_height(),ceili(rect.end.y))):
		for x in range(maxi(0,floori(rect.position.x)),mini(selection.get_width(),ceili(rect.end.x))):
			var inside := true
			if kind == "lasso": inside=_points.size()>2 and Geometry2D.is_point_in_polygon(Vector2(x,y),_points)
			if inside: selection.set_pixel(x,y,Color(0,0,0,0) if _selection_operation==-1 else Color.WHITE)
	selection_texture=ImageTexture.create_from_image(selection)
	pixel_selection_bounds=Rect2(rect.position.floor(),rect.size.ceil())
	hint_changed.emit("Selection ready · Paint inside it, or choose Selection → Mask / Copy / Clear")


func clear_selection() -> void:
	_selection_preview_size=Vector2.ZERO
	selection_transform=Transform2D.IDENTITY; selection_inverse=Transform2D.IDENTITY
	selection_forward_warp=Callable(); selection_inverse_warp=Callable(); selection_preview_origin=Vector2.ZERO
	selection=null; selection_texture=null; pixel_selection_bounds=Rect2(); _sync_selection_overlay(); queue_redraw()


func sync_pixel_selection() -> void:
	selection_transform=Transform2D.IDENTITY; selection_inverse=Transform2D.IDENTITY
	selection_forward_warp=Callable(); selection_inverse_warp=Callable(); selection_preview_origin=Vector2.ZERO
	# History snapshots share immutable mask textures. Never update a texture
	# belonging to the state we just left while restoring a different mask.
	selection_texture=null
	if document!=null and not selected.is_empty() and document.pixel_selection_owner==selected[-1] and document.pixel_selection!=null:
		selection=document.pixel_selection.get_image().duplicate()
		var old:=document.pixel_selection_reference
		var current:=document.layer_for_id(document.pixel_selection_owner)
		if old!=null and current!=null:
			var from:=document.pixel_selection_reference_world
			var to:=document.world_transform(current)
			var same_yaw:=is_equal_approx(float(old.properties.get("yaw_up_down",0)),float(current.properties.get("yaw_up_down",0))) and is_equal_approx(float(old.properties.get("yaw_left_right",0)),float(current.properties.get("yaw_left_right",0)))
			if not (from.is_equal_approx(to) and old.dimensions.is_equal_approx(current.dimensions) and same_yaw):
				var current_state:=current.copy_layer()
				selection_forward_warp=func(point: Vector2) -> Vector2:
					var local:=old.unproject_point(from.affine_inverse()*point)
					return to*current_state.project_point(local/old.dimensions.max(Vector2.ONE)*current_state.dimensions)
				selection_inverse_warp=func(point: Vector2) -> Vector2:
					var local:=current_state.unproject_point(to.affine_inverse()*point)
					return from*old.project_point(local/current_state.dimensions.max(Vector2.ONE)*old.dimensions)
		_update_selection_preview()
	else: clear_selection()


func _update_selection_preview() -> void:
	if selection==null: return
	if selection_forward_warp.is_valid() and selection_inverse_warp.is_valid():
		_update_warped_selection_preview()
		return
	_selection_preview_size=Vector2.ZERO
	(_selection_overlay.material as ShaderMaterial).set_shader_parameter("warped",false)
	if selection_texture!=null and selection_texture.get_size()==Vector2(selection.get_size()): (selection_texture as ImageTexture).update(selection)
	else: selection_texture=ImageTexture.create_from_image(selection)
	selection_preview_origin=Vector2.ZERO
	var used:=selection.get_used_rect(); pixel_selection_bounds=selection_transform*Rect2(used.position,used.size); _sync_selection_overlay(); queue_redraw()


func _update_warped_selection_preview() -> void:
	var used:=selection.get_used_rect()
	if not used.has_area():
		selection_texture=null; pixel_selection_bounds=Rect2(); _sync_selection_overlay(); queue_redraw(); return
	var bounds:=Rect2(selection_forward_warp.call(Vector2(used.position)),Vector2.ZERO)
	for corner in [Vector2(used.end.x,used.position.y),Vector2(used.end),Vector2(used.position.x,used.end.y)]:
		bounds=bounds.expand(selection_forward_warp.call(corner))
	# The preview is clipped to the visible document for performance. The source
	# mask is deliberately not clipped, so moving/yawing it back restores every
	# selected pixel that temporarily went off canvas.
	var visible:=Rect2i(Vector2i(bounds.position.floor()),Vector2i(bounds.end.ceil()-bounds.position.floor())).intersection(Rect2i(Vector2i.ZERO,document.canvas_size))
	pixel_selection_bounds=bounds
	if not visible.has_area():
		selection_texture=null; _sync_selection_overlay(); queue_redraw(); return
	# A planar layer's translation, scale, rotation and yaw form a projective
	# mapping. Solve its four corners once, then let the GPU sample the mask.
	# The old per-pixel Callable loop could block every pointer update for seconds.
	var corners:=PackedVector2Array()
	for corner in [Vector2(used.position),Vector2(used.end.x,used.position.y),Vector2(used.end),Vector2(used.position.x,used.end.y)]:
		corners.append((selection_forward_warp.call(corner)-Vector2(visible.position))/Vector2(visible.size))
	var rows:=_selection_projection(corners)
	if rows.is_empty(): return
	var preview:=selection.get_region(used)
	selection_preview_origin=Vector2(visible.position)
	_selection_preview_size=Vector2(visible.size)
	if selection_texture!=null and selection_texture.get_size()==Vector2(preview.get_size()): selection_texture.update(preview)
	else: selection_texture=ImageTexture.create_from_image(preview)
	var material:=_selection_overlay.material as ShaderMaterial
	material.set_shader_parameter("warped",true)
	for i in 3: material.set_shader_parameter("row%d" % i,rows[i])
	_sync_selection_overlay()
	queue_redraw()

static func _selection_projection(corners: PackedVector2Array) -> Array[Vector3]:
	var equations: Array[PackedFloat64Array]=[]
	var uv:=[Vector2.ZERO,Vector2.RIGHT,Vector2.ONE,Vector2.DOWN]
	for i in 4:
		var x:=corners[i].x; var y:=corners[i].y; var u: float=uv[i].x; var v: float=uv[i].y
		equations.append(PackedFloat64Array([x,y,1,0,0,0,-u*x,-u*y,u]))
		equations.append(PackedFloat64Array([0,0,0,x,y,1,-v*x,-v*y,v]))
	for column in 8:
		var pivot:=column
		for row in range(column+1,8):
			if absf(equations[row][column])>absf(equations[pivot][column]): pivot=row
		if absf(equations[pivot][column])<.000000001: return []
		var swapped:=equations[column]; equations[column]=equations[pivot]; equations[pivot]=swapped
		var factor:=equations[column][column]
		for j in range(column,9): equations[column][j]/=factor
		for row in 8:
			if row==column: continue
			factor=equations[row][column]
			for j in range(column,9): equations[row][j]-=factor*equations[column][j]
	return [Vector3(equations[0][8],equations[1][8],equations[2][8]),Vector3(equations[3][8],equations[4][8],equations[5][8]),Vector3(equations[6][8],equations[7][8],1)]


func bake_selection_transform() -> void:
	if selection==null or (selection_transform.is_equal_approx(Transform2D.IDENTITY) and not selection_forward_warp.is_valid()): return
	var source:=selection
	var used:=source.get_used_rect()
	var bounds:=selection_transform*Rect2(used.position,used.size)
	if selection_forward_warp.is_valid():
		bounds=Rect2(selection_forward_warp.call(Vector2(used.position)),Vector2.ZERO)
		for corner in [Vector2(used.end.x,used.position.y),Vector2(used.end),Vector2(used.position.x,used.end.y)]: bounds=bounds.expand(selection_forward_warp.call(corner))
	var area:=Rect2i(Vector2i(bounds.position.floor()),Vector2i(bounds.end.ceil()-bounds.position.floor())).intersection(Rect2i(Vector2i.ZERO,document.canvas_size))
	selection=Image.create(document.canvas_size.x,document.canvas_size.y,false,Image.FORMAT_RGBA8)
	if not selection_forward_warp.is_valid() and is_zero_approx(selection_transform.x.y) and is_zero_approx(selection_transform.y.x) and used.has_area():
		var piece:=source.get_region(used)
		piece.resize(maxi(1,roundi(bounds.size.x)),maxi(1,roundi(bounds.size.y)),Image.INTERPOLATE_NEAREST)
		if selection_transform.x.x<0: piece.flip_x()
		if selection_transform.y.y<0: piece.flip_y()
		selection.blit_rect(piece,Rect2i(Vector2i.ZERO,piece.get_size()),Vector2i(bounds.position.round()))
	else:
		for y in range(area.position.y,area.end.y):
			var sample: Vector2=selection_inverse_warp.call(Vector2(area.position.x,y)+Vector2.ONE*.5) if selection_inverse_warp.is_valid() else selection_inverse*(Vector2(area.position.x,y)+Vector2.ONE*.5)
			for x in range(area.position.x,area.end.x):
				var pixel:=Vector2i(sample.floor())
				if used.has_point(pixel): selection.set_pixel(x,y,source.get_pixelv(pixel))
				if selection_inverse_warp.is_valid(): sample=selection_inverse_warp.call(Vector2(x+1,y)+Vector2.ONE*.5)
				else: sample+=selection_inverse.x
	selection_transform=Transform2D.IDENTITY; selection_inverse=Transform2D.IDENTITY; selection_texture=null
	selection_forward_warp=Callable(); selection_inverse_warp=Callable(); selection_preview_origin=Vector2.ZERO
	_update_selection_preview()


func _begin_pixel_selection(point: Vector2,lasso: bool=false) -> void:
	if selected.is_empty() or pixel_source==null or not pixel_domain.has_point(Vector2i(point)): return
	if _drag=="object_preview": commit_object_selection()
	if edge_magnet and pixel_mode in ["brush","fill"] and not pixel_box_select:
		prepare_smart_selection()
		if smart_selection.edges==null: hint_changed.emit("Analyzing edges… try again when ready"); return
		if smart_selection.edges.nearest(point,edge_threshold)<0: hint_changed.emit("No nearby edge at this threshold"); return
	if pixel_mode=="object": prepare_smart_selection()
	gesture_started.emit()
	selection_texture=null
	if selection==null or selection.get_size()!=document.canvas_size:
		selection=Image.create(document.canvas_size.x,document.canvas_size.y,false,Image.FORMAT_RGBA8); selection.fill(Color(0,0,0,0))
	else: selection=selection.duplicate()
	_drag="pixel_select"; _last=point
	_pixel_alpha_base=selection.duplicate()
	_pixel_alpha_ink=Image.create(selection.get_width(),selection.get_height(),false,Image.FORMAT_RGBA8)
	_edge_follower.previous=-1
	if pixel_box_select and pixel_mode in ["brush","erase"]:
		_start=point; _pixel_area_base=selection.duplicate(); _pixel_area_previous=Rect2i()
		_drag="pixel_lasso" if lasso else "pixel_box"
		if lasso: _points=PackedVector2Array([point])
	elif pixel_mode=="object" or (pixel_mode=="fill" and edge_magnet):
		_smart_base=selection.duplicate(); _smart_seed=point; _smart_subtract=_erase_modifier
		_smart_ready=false; _smart_has_proposal=false; _smart_apply_when_ready=false
		_drag="object_preview" if pixel_mode=="object" else "edge_pending"
		_smart_request=_request_smart_mask("object" if pixel_mode=="object" else "edge",point,object_threshold if pixel_mode=="object" else edge_threshold,brush_size)
		hint_changed.emit("Finding object…" if pixel_mode=="object" else "Following connected edge…")
	elif pixel_mode=="fill": _pixel_flood(Vector2i(point)); _finish(point)
	else: _pixel_brush_line(point,point)
	_update_selection_preview()

func _update_pixel_box(point: Vector2) -> void:
	if _pixel_area_base==null: return
	var rect:=Rect2(_start,point-_start).abs()
	var area:=Rect2i(Vector2i(rect.position.floor()),Vector2i(rect.size.ceil())).intersection(pixel_domain)
	var changed:=area.merge(_pixel_area_previous) if _pixel_area_previous.has_area() else area
	if changed.has_area(): selection.blit_rect(_pixel_area_base,changed,changed.position)
	if area.has_area():
		var coverage:=Image.create(area.size.x,area.size.y,false,Image.FORMAT_RGBA8); coverage.fill(Color.WHITE)
		coverage=preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").feather(coverage,selection_falloff)
		selection.blit_rect(preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").blend(_pixel_area_base.get_region(area),coverage,selection_alpha,_erase_modifier or pixel_mode=="erase"),Rect2i(Vector2i.ZERO,area.size),area.position)
	_pixel_area_previous=area; _update_selection_preview()

func _apply_pixel_lasso(coverage_only: bool=false) -> void:
	if _points.size()<3: return
	var bounds:=Rect2(_points[0],Vector2.ZERO)
	for point in _points: bounds=bounds.expand(point)
	var area:=Rect2i(Vector2i(bounds.position.floor()),Vector2i(bounds.size.ceil())).intersection(pixel_domain)
	var tint:=Color.WHITE if coverage_only else (Color.TRANSPARENT if _erase_modifier or pixel_mode=="erase" else Color.WHITE)
	# Even-odd scanline filling supports concave and self-crossing lassos, with
	# native span writes instead of testing every pixel against every edge.
	for y in range(area.position.y,area.end.y):
		var intersections:=PackedFloat32Array(); var line:=y+.5
		for i in _points.size():
			var a:=_points[i]; var b:=_points[(i+1)%_points.size()]
			if (a.y<=line and b.y>line) or (b.y<=line and a.y>line): intersections.append(a.x+(line-a.y)*(b.x-a.x)/(b.y-a.y))
		intersections.sort()
		for i in range(0,intersections.size()-1,2):
			var left:=maxi(area.position.x,ceili(intersections[i]-.5)); var right:=mini(area.end.x,ceili(intersections[i+1]-.5))
			if right>left: selection.fill_rect(Rect2i(left,y,right-left,1),tint)


func _flush_edge_motion() -> void:
	if not _edge_motion_pending: return
	_edge_motion_pending=false
	if _drag!="pixel_select": return
	_pixel_brush_line(_last,_edge_motion_point); _last=_edge_motion_point
	_update_selection_preview()

func _pixel_brush_line(from: Vector2,to: Vector2) -> void:
	if edge_magnet and pixel_mode=="brush" and not pixel_box_select:
		if smart_selection.edges==null: return
		_edge_follower.field=smart_selection.edges
		var path:=_edge_follower.follow(to,edge_threshold,to-from)
		_edge_preview=Vector2.INF
		if not path.is_empty():
			_edge_preview=path[-1]
			_pixel_alpha_path(path)
		return
	_pixel_alpha_path(PackedVector2Array([from,to])); return


func prepare_smart_selection() -> void:
	if pixel_source!=null and pixel_domain.has_area() and smart_selection.source!=pixel_source:
		smart_selection.prepare(pixel_source,pixel_domain); _edge_follower.previous=-1

func set_object_threshold(value: float) -> void:
	object_threshold=clampf(value,0,1)
	# Applied selections remain adjustable until a different edit changes the
	# mask/source/owner. Reopen against the original base, not the last result.
	if _drag.is_empty() and not _object_committed.is_empty() and pixel_mode=="object" and tool=="pixel_select":
		if document.pixel_selection==_object_committed.texture and pixel_source==_object_committed.source and not selected.is_empty() and selected[-1]==_object_committed.owner:
			gesture_started.emit()
			_smart_base=_object_committed.base.duplicate(); _smart_seed=_object_committed.seed; _smart_subtract=_object_committed.subtract
			_drag="object_preview"; _smart_apply_when_ready=false
		else: _object_committed.clear()
	if _drag=="object_preview":
		_smart_ready=false
		_smart_request=_request_smart_mask("object",_smart_seed,object_threshold)
		hint_changed.emit("Updating object selection…")

func commit_object_selection() -> void:
	if _drag=="pan" and _pan_previous_drag=="object_preview": _smart_apply_when_ready=true; return
	if _drag!="object_preview": return
	if not _smart_ready: _smart_apply_when_ready=true; return
	var context:={"base":_smart_base.duplicate(),"seed":_smart_seed,"subtract":_smart_subtract,"source":pixel_source,"owner":selected[-1]}
	_drag="pixel_select"; _finish(_smart_seed)
	context.texture=document.pixel_selection; _object_committed=context

func _smart_proposed(mask: Image,kind: String,request: int) -> void:
	var action:=_pan_previous_drag if _drag=="pan" else _drag
	if request!=_smart_request or action not in ["object_preview","edge_pending"]: return
	if mask==null:
		if kind=="object":
			selection=_smart_base.duplicate(); _smart_ready=false; _smart_has_proposal=false; _smart_apply_when_ready=false
			_update_selection_preview()
			hint_changed.emit("No confident boundary · Adjust Object Threshold or Esc to cancel"); return
		cancel_gesture(); hint_changed.emit("No confident object boundary found" if kind=="object" else "No connected edge found"); return
	selection=mask
	_smart_ready=true; _smart_has_proposal=true; _update_selection_preview()
	if kind=="edge": _drag="pixel_select"; _finish(_smart_seed)
	elif _smart_apply_when_ready: commit_object_selection()
	else: hint_changed.emit("Object preview · Click adds · Ctrl-click subtracts · Threshold adjusts this object · Enter applies · Esc cancels")

func _request_smart_mask(kind: String,point: Vector2,threshold: float,width: float=1) -> int:
	return smart_selection.request(kind,point,threshold,width,{"base":_smart_base,"alpha":selection_alpha,"falloff":selection_falloff,"subtract":_smart_subtract,"origin":pixel_domain.position})

func _pixel_flood(start: Vector2i) -> void:
	var coverage:=Image.create(selection.get_width(),selection.get_height(),false,Image.FORMAT_RGBA8)
	var tint:=Color.WHITE
	var width:=pixel_source.get_width(); var bytes:=pixel_source.get_data()
	var target:=(start.y*width+start.x)*4
	var visited:=PackedByteArray(); visited.resize(width*pixel_source.get_height())
	var limit:=pow(canvas_threshold_bytes(fill_threshold),2)
	var matches:=func(x: int,y: int) -> bool:
		if not pixel_domain.has_point(Vector2i(x,y)) or visited[y*width+x]!=0: return false
		var offset:=(y*width+x)*4; var delta:=0.0
		for component in 4: delta+=pow(float(bytes[offset+component])-float(bytes[target+component]),2)
		return delta<=limit
	var stack: Array[Vector2i]=[start]
	if pixel_match_all:
		for y in range(pixel_domain.position.y,pixel_domain.end.y):
			for x in range(pixel_domain.position.x,pixel_domain.end.x):
				if matches.call(x,y): coverage.set_pixel(x,y,tint)
		selection=preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").blend(_pixel_alpha_base,preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").feather(coverage,selection_falloff),selection_alpha,_erase_modifier)
		return
	while not stack.is_empty():
		var at: Vector2i=stack.pop_back()
		if not matches.call(at.x,at.y): continue
		var left:=at.x
		while matches.call(left-1,at.y): left-=1
		var x:=left; var above:=false; var below:=false
		while matches.call(x,at.y):
			visited[at.y*width+x]=1
			var up: bool=matches.call(x,at.y-1); var down: bool=matches.call(x,at.y+1)
			if up and not above: stack.append(Vector2i(x,at.y-1))
			if down and not below: stack.append(Vector2i(x,at.y+1))
			above=up; below=down; x+=1
		coverage.fill_rect(Rect2i(left,at.y,x-left,1),tint)
	selection=preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").blend(_pixel_alpha_base,preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").feather(coverage,selection_falloff),selection_alpha,_erase_modifier)

func _pixel_alpha_path(path: PackedVector2Array) -> void:
	if _pixel_alpha_base==null or _pixel_alpha_ink==null or path.is_empty(): return
	var key:=str([brush_size,selection_falloff])
	if _pixel_alpha_stamp==null or key!=_pixel_alpha_stamp_key:
		_pixel_alpha_stamp=preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").stamp(brush_size,selection_falloff); _pixel_alpha_stamp_key=key
	var size:=_pixel_alpha_stamp.get_size()
	var area:=Rect2i()
	for i in path.size():
		var a:=path[maxi(0,i-1)]; var b:=path[i]
		var steps:=maxi(1,ceili(a.distance_to(b)/maxf(1,brush_size*.2)))
		for step in steps+1:
			var at:=Vector2i(a.lerp(b,float(step)/steps))-size/2
			_pixel_alpha_ink.blend_rect(_pixel_alpha_stamp,Rect2i(Vector2i.ZERO,size),at)
			var changed:=Rect2i(at,size).intersection(pixel_domain)
			if changed.has_area(): area=area.merge(changed) if area.has_area() else changed
	preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").blend_region(selection,_pixel_alpha_base,_pixel_alpha_ink,area,selection_alpha,_erase_modifier or pixel_mode=="erase")


func _can_drop_data(_position: Vector2,data: Variant) -> bool:
	return data is Dictionary and (data.has("files") or data.has("paths"))


func _snap_polygon_point(at: Vector2, control: bool=false) -> Vector2:
	if snapping==control: return at
	var targets: Array[Vector2]=[Vector2.ZERO,Vector2(document.canvas_size)*.5,Vector2(document.canvas_size)]
	for i in _points.size():
		if i!=_polygon_index: targets.append(_points[i])
	for layer in document.layers:
		if layer.id==path_layer_id or not document.can_edit(layer): continue
		var bounds:=document.world_transform(layer)*Rect2(Vector2.ZERO,layer.dimensions)
		targets.append_array([bounds.position,bounds.get_center(),bounds.end])
	var best:=Vector2.ONE*7.0/zoom
	var result:=at
	for target in targets:
		if absf(target.x-at.x)<best.x: best.x=absf(target.x-at.x); result.x=target.x
		if absf(target.y-at.y)<best.y: best.y=absf(target.y-at.y); result.y=target.y
	return result


func _polygon_insert(at: Vector2) -> int:
	if _points.size()<2: return _points.size()
	var nearest:=0; var distance:=INF
	for i in _points.size():
		var next:=(i+1)%_points.size()
		if _points[i].is_equal_approx(_points[next]): continue
		# Measure proximity to the edge itself, not to its endpoints. Summing
		# endpoint distances unfairly favors short edges on the opposite side.
		var closest:=Geometry2D.get_closest_point_to_segment(at,_points[i],_points[next])
		var cost:=closest.distance_squared_to(at)
		if cost<distance: distance=cost; nearest=i+1
	return nearest


func _drop_data(at: Vector2,data: Variant) -> void:
	files_dropped.emit(PackedStringArray(data.get("files",data.get("paths",[]))),to_document(at))

func _material_flood(point: Vector2) -> void:
	# Region detection reads the original composition; coverage writes never change it.
	var source:=_material_flood_source
	if source==null: return
	source.convert(Image.FORMAT_RGBA8)
	var width:=source.get_width(); var height:=source.get_height()
	var frame:=document.world_transform(_paint_layer)
	var ratio:=Vector2(source.get_size())/_paint_layer.dimensions
	var start:=Vector2i(frame.affine_inverse()*point*ratio)
	if not Rect2i(Vector2i.ZERO,source.get_size()).has_point(start): return
	if not paint_selection_only and not source.get_used_rect().has_area():
		var full:=Image.create(width,height,false,Image.FORMAT_RGBA8); full.fill(Color(1,1,1,brush_opacity*material_strength))
		_paint_image.blend_rect(full,Rect2i(Vector2i.ZERO,full.get_size()),Vector2i.ZERO)
		_paint_data=_paint_image.get_data(); _update_paint_texture(); return
	var bytes:=source.get_data(); var seed_offset:=(start.y*width+start.x)*4
	var target:=bytes.slice(seed_offset,seed_offset+4)
	var visited:=PackedByteArray(); visited.resize(width*height)
	var threshold_squared:=pow(canvas_threshold_bytes(fill_threshold),2)
	var matches:=func(x: int,y: int) -> bool:
		if x<0 or y<0 or x>=width or y>=height: return false
		var index:=y*width+x
		if visited[index]!=0: return false
		var difference:=0.0
		for channel in 4: difference+=pow(float(bytes[index*4+channel])-float(target[channel]),2)
		return difference<=threshold_squared and _paint_pixel_allowed(frame*(Vector2(x,y)/ratio))
	var stack: Array[Vector2i]=[start]
	while not stack.is_empty():
		var p: Vector2i=stack.pop_back()
		if not matches.call(p.x,p.y): continue
		var x:=p.x
		while matches.call(x-1,p.y): x-=1
		var span_up:=false; var span_down:=false
		while x<width and matches.call(x,p.y):
			var index:=p.y*width+x; visited[index]=1
			var coverage:=brush_opacity*material_strength*(selection_coverage(frame*(Vector2(x,p.y)/ratio)) if paint_selection_only else 1.0)
			var prior:=_paint_data[index*4+3]/255.0
			for channel in 3: _paint_data[index*4+channel]=255
			_paint_data[index*4+3]=roundi((coverage+prior*(1-coverage))*255)
			var up: bool=p.y>0 and bool(matches.call(x,p.y-1))
			if up and not span_up: stack.append(Vector2i(x,p.y-1))
			span_up=up
			var down: bool=p.y<height-1 and bool(matches.call(x,p.y+1))
			if down and not span_down: stack.append(Vector2i(x,p.y+1))
			span_down=down; x+=1
	_upload_paint()
