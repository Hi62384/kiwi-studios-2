class_name KiwiGroomTool
extends RefCounted
const TOOLS:=["Brush","Comb","Cut","Grow","Curl","Clump","Density","Length","Smooth","Relax","Part","Feather width","Spread","Protect","Reset region","Guide","Color paint","Select strands"]
var paint_color:=Color.WHITE
var selected_preset:=-1
var clump_start:=0.
var clump_end:=1.
var clump_variation:=.15
var canvas: KiwiModelViewport
var enabled:=false
var tool:="Comb"
var radius:=.35
var strength:=.3
var falloff:=.65
var spacing:=.12
var value:=.3
var frequency:=3.0
var symmetry:=-1
var through:=false
var replace:=false
var target_cut:=false
var drawing:=false
var cursor:=Vector2.ZERO
var previous:=Vector3.ZERO
var last_world:=Vector3.INF
var component_id:=""
var triangle_mesh: TriangleMesh
var hit_key:=0
var last_hit: Dictionary={}
var stroke_id:=""
var touched:=0
var distance_metric:=Basis.IDENTITY
var selected_root:=-1
var selected_guide:=""
var guide_point:=-1
var guide_before: Dictionary={}
var guide_plane:=Plane()
func item() -> KiwiModelComponent: return canvas.session.primary()
func active() -> bool: return enabled and item()!=null and item().growth!=null and item().growth.source_valid
func hit(position: Vector2) -> Dictionary:
	var component:=item()
	if component==null or component.growth==null: return {}
	var data:=component.growth; var visual: KiwiSurfaceGrowthInstance=canvas.visuals.get(component.id); var skeleton:=visual.growth_skeleton if is_instance_valid(visual) else null; var points:=KiwiSurfaceGrowth.posed_points(data,skeleton); var world:=skeleton.global_transform if is_instance_valid(skeleton) else canvas.session.document.world_transform(component)
	var key:=hash([data.topology,points])
	if triangle_mesh==null or key!=hit_key:
		triangle_mesh=TriangleMesh.new(); var faces:=PackedVector3Array()
		for triangle: Dictionary in data.surface_triangles:
			for axis in 3: faces.append(points[triangle.indices[axis]])
		triangle_mesh.create_from_faces(faces); hit_key=key
	var ray:=canvas.ray(position); var inverse:=world.affine_inverse(); var result:=triangle_mesh.intersect_ray(inverse*ray.origin,(inverse.basis*ray.direction).normalized())
	if result.is_empty(): return {}
	result.world=world*result.position; result.transform=world; result.points=points
	return result
func build_grid(data: KiwiSurfaceGrowthData) -> void:
	if not data.candidate_grid.is_empty(): return
	for index in data.roots.size():
		var root: Dictionary=data.roots[index]; var cell:=Vector3i((root.position/data.grid_size).floor())
		if not data.candidate_grid.has(cell): data.candidate_grid[cell]=[]
		data.candidate_grid[cell].append(index)
func query(data: KiwiSurfaceGrowthData,center: Vector3,local_radius: float) -> Array[int]:
	build_grid(data); var result: Array[int]=[]; var extent:=ceili(local_radius/data.grid_size); var cell:=Vector3i((center/data.grid_size).floor())
	if extent>12:
		for i in data.roots.size():
			if (data.roots[i].position as Vector3).distance_squared_to(center)<=local_radius*local_radius: result.append(i)
		return result
	for x in range(-extent,extent+1):
		for y in range(-extent,extent+1):
			for z in range(-extent,extent+1):
				for i: int in data.candidate_grid.get(cell+Vector3i(x,y,z),[]):
					if (data.roots[i].position as Vector3).distance_squared_to(center)<=local_radius*local_radius: result.append(i)
	return result
func apply_at(data: KiwiSurfaceGrowthData,center: Vector3,movement: Vector3,normal: Vector3,invert: bool=false) -> int:
	var started:=Time.get_ticks_usec(); var indices:=query(data,center,radius); var count:=0
	var average_direction:=Vector3.ZERO; var average_offset:=Vector3.ZERO; var average_length:=0.0; var average_density:=0.0
	if tool=="Smooth" and not indices.is_empty():
		for index in indices:
			var root: Dictionary=data.roots[index]; var edit:=KiwiSurfaceGrowth.style(data,root); var frame:=KiwiSurfaceGrowth.point_frame(data,root,data.source_points)
			average_direction+=frame.basis*(edit.get("direction",Vector3.UP) as Vector3); average_offset+=frame.basis*(edit.get("offset",Vector3.ZERO) as Vector3); average_length+=float(edit.length); average_density+=float(edit.density)
		average_direction=average_direction.normalized(); average_offset/=indices.size(); average_length/=indices.size(); average_density/=indices.size()
	for index in indices:
		var root: Dictionary=data.roots[index]
		if data.protected_faces.has(int(root.face)) and tool!="Protect": continue
		if not through and (root.normal as Vector3).dot(normal)<.1: continue
		if not through and canvas!=null and triangle_mesh!=null and not last_hit.is_empty():
			var posed:=KiwiSurfaceGrowth.point_frame(data,root,last_hit.points).origin; var origin: Vector3=(last_hit.transform as Transform3D).affine_inverse()*canvas.camera.global_position
			var visible:=triangle_mesh.intersect_ray(origin,(posed-origin).normalized())
			if not visible.is_empty() and origin.distance_to(visible.position)+maxf(.0001,radius*.01)<origin.distance_to(posed): continue
		var distance: float=(distance_metric*(root.position-center)).length()/maxf(.0001,radius); var weight:=strength*pow(clampf(1-distance,0,1),lerpf(.05,4,falloff))
		if weight<.0001: continue
		var id:=str(root.id); var edit:=KiwiSurfaceGrowth.style(data,root); var frame:=KiwiSurfaceGrowth.point_frame(data,root,data.source_points); var delta:=frame.basis.inverse()*movement; var sign: float=-1.0 if invert else 1.0; var change:={}
		match tool:
			"Color paint": change.color=(edit.get("color",Color.WHITE) as Color).lerp(Color.WHITE if invert else paint_color,weight)
			"Brush": change.offset=edit.get("offset",Vector3.ZERO)+delta*weight*sign
			"Comb":
				if delta.length_squared()>.0000001: change.direction=(edit.get("direction",Vector3.UP) as Vector3).slerp(delta.normalized(),clampf(weight,0,1)).normalized()
			"Cut": change.length=maxf(0,lerpf(float(edit.length),minf(float(edit.length),value),weight) if target_cut else float(edit.length)-weight*maxf(.01,value)*sign)
			"Grow": change.length=maxf(0,float(edit.length)+weight*maxf(.01,value)*sign)
			"Length": change.length=maxf(0,lerpf(float(edit.length),value,weight) if replace else float(edit.length)+value*weight*sign)
			"Curl":
				if int(data.settings.get("type",0))==2: change.offset=edit.get("offset",Vector3.ZERO)+Vector3(0,0,value*weight*sign)
				else: change.curl=clampf(float(edit.get("curl",0))+weight*sign,-4,4); change.frequency=frequency
			"Clump":
				var grid_size:=maxf(.02,value); var clump_center: Vector3=(root.position as Vector3).snapped(Vector3.ONE*grid_size); change.clump=clampf(float(edit.get("clump",0))+weight*sign,0,1); change.clump_target=frame.basis.inverse()*(clump_center-root.position)+Vector3.UP*float(edit.length); change.clump_id=str(Vector3i(clump_center/grid_size))
				change.clump_start=clump_start; change.clump_end=clump_end; change.clump_variation=clump_variation
			"Density": change.density=clampf(lerpf(float(edit.density),value,weight) if replace else float(edit.density)+weight*sign,0,1)
			"Smooth":
				change.offset=(edit.get("offset",Vector3.ZERO) as Vector3).lerp(frame.basis.inverse()*average_offset,weight); change.direction=(edit.get("direction",Vector3.UP) as Vector3).lerp(frame.basis.inverse()*average_direction,weight).normalized(); change.length=lerpf(float(edit.length),average_length,weight); change.density=lerpf(float(edit.density),average_density,weight)
			"Relax":
				change.offset=(edit.get("offset",Vector3.ZERO) as Vector3).lerp(Vector3.ZERO,weight); change.curl=lerpf(float(edit.get("curl",0)),0,weight); change.direction=(edit.get("direction",Vector3.UP) as Vector3).lerp(Vector3.UP,weight).normalized()
			"Part":
				var axis:=movement.normalized(); var away: Vector3=root.position-center; away-=axis*away.dot(axis); change.direction=Vector3.UP.lerp(frame.basis.inverse()*away.normalized(),clampf(weight*2,0,1)).normalized()
			"Feather width": change.width=maxf(.001,float(edit.get("width",data.settings.get("width",.14)))+weight*value*sign)
			"Spread": change.offset=(edit.get("offset",Vector3.ZERO) as Vector3)+(frame.basis.inverse()*(root.position-center))*weight*sign
			"Protect": change.locked=not invert
			"Reset region": change={"offset":Vector3.ZERO,"direction":Vector3.UP,"curl":0.0,"clump":0.0,"length":float(data.settings.get("length",.5)),"density":1.0/float(data.settings.get("candidate_multiplier",2))}
		if edit.get("locked",false) and tool!="Protect": continue
		if not data.pending.has(id): data.pending[id]={}
		data.pending[id].merge(change,true); data.dirty_chunks[index/128]=true; count+=1
	data.revision+=1; data.groom_usec=Time.get_ticks_usec()-started; touched+=count; return count
func stroke(position: Vector2,invert: bool=false) -> void:
	last_hit=hit(position)
	if last_hit.is_empty(): return
	if last_world.is_finite() and last_world.distance_to(last_hit.world)<radius*spacing: return
	var data:=item().growth; var points: PackedVector3Array=last_hit.points; var local: Vector3=last_hit.position; var normal: Vector3=last_hit.normal
	# Convert posed surface hit to its rest triangle using barycentric coordinates.
	var face:=int(last_hit.get("face_index",-1))
	if face>=0 and face<data.surface_triangles.size():
		var ids: Vector3i=data.surface_triangles[face].indices; var a:=points[ids.x]; var b:=points[ids.y]; var c:=points[ids.z]; var u:=b-a; var v:=c-a; var p:=local-a; var denominator:=u.dot(u)*v.dot(v)-u.dot(v)*u.dot(v)
		if absf(denominator)>.0000001:
			var y: float=(v.dot(v)*p.dot(u)-u.dot(v)*p.dot(v))/denominator; var z: float=(u.dot(u)*p.dot(v)-u.dot(v)*p.dot(u))/denominator; local=data.source_points[ids.x]*(1-y-z)+data.source_points[ids.y]*y+data.source_points[ids.z]*z; normal=data.surface_triangles[face].normal
	var movement:=local-previous if last_world.is_finite() else Vector3.ZERO; previous=local; last_world=last_hit.world
	var scale: Vector3=(last_hit.transform as Transform3D).basis.get_scale().abs(); var world_scale:=maxf(.0001,minf(scale.x,minf(scale.y,scale.z))); var world_radius:=radius; radius=world_radius/world_scale; distance_metric=(last_hit.transform as Transform3D).basis.scaled(Vector3.ONE/world_scale)
	var steps:=clampi(ceili(movement.length()/maxf(.001,radius*spacing)),1,24)
	for i in steps: apply_at(data,local-movement*(1-float(i+1)/steps),movement/steps,normal,invert)
	if symmetry>=0:
		local[symmetry]=-local[symmetry]; movement[symmetry]=-movement[symmetry]; normal[symmetry]=-normal[symmetry]
		for i in steps: apply_at(data,local-movement*(1-float(i+1)/steps),movement/steps,normal,invert)
	radius=world_radius; distance_metric=Basis.IDENTITY
	var visual: KiwiSurfaceGrowthInstance=canvas.visuals.get(item().id)
	if is_instance_valid(visual): visual.update_growth()
	canvas.overlay.queue_redraw()
func finish(cancel: bool=false) -> void:
	if not drawing: return
	drawing=false; var session:=canvas.session; var component:=session.document.component(component_id)
	if component==null or component.growth==null: return
	var data:=component.growth; var changes:=data.pending.duplicate(true); data.pending.clear(); data.revision+=1; data.render_cache=null
	if not cancel and not changes.is_empty():
		var entries:=changes.size()
		for layer: Dictionary in data.groom_layers: entries+=layer.changes.size()
		if entries>65536 or data.groom_layers.size()>=128:
			canvas.notice.emit("Groom history budget reached. Apply groom layers before adding more strokes."); session.changed.emit(); return
		var layer:={"id":stroke_id,"tool":tool,"enabled":true,"changes":changes}; var id:=component_id
		var reference: WeakRef=weakref(session)
		var apply:=func(add: bool):
			var active_session:=reference.get_ref() as KiwiModelSession
			if active_session==null: return
			var target:=active_session.document.component(id)
			if target==null or target.growth==null: return
			var layers:=target.growth.groom_layers
			for i in range(layers.size()-1,-1,-1):
				if layers[i].id==layer.id: layers.remove_at(i)
			if add: layers.append(layer.duplicate(true))
			target.growth.revision+=1; target.growth.render_cache=null
		apply.call(true); session.custom_action("Groom · "+tool,apply.bind(false),apply.bind(true),changes.size()*8)
	else: session.changed.emit()
	canvas.gesture_finished.emit()
func handle(event: InputEvent) -> bool:
	if not active():
		if drawing: finish(true)
		return false
	if tool=="Guide" and guide_event(event): return true
	if tool=="Select strands" and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			var visual: KiwiSurfaceGrowthInstance=canvas.visuals.get(item().id); var world:=visual.global_transform if visual!=null else canvas.session.document.world_transform(item()); var positions:=KiwiSurfaceGrowth.posed_points(item().growth,visual.growth_skeleton if visual!=null else null); var best:=12.; selected_root=-1
			for root: Dictionary in item().growth.roots:
				var point: Vector3=world*KiwiSurfaceGrowth.point_frame(item().growth,root,positions).origin
				if canvas.camera.is_position_behind(point): continue
				var distance:=canvas.project(point).distance_to(event.position)
				if distance<best: best=distance; selected_root=int(root.id)
			canvas.gesture_finished.emit()
		return true
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		if drawing: finish(true)
		else: enabled=false
		return true
	if event is InputEventMouseButton:
		if event.pressed and event.shift_pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: radius=clampf(radius*(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.12),.005,100); canvas.gesture_finished.emit(); return true
		if event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed: drawing=true; component_id=item().id; stroke_id=ActorData.new_id(); last_world=Vector3.INF; touched=0; stroke(event.position,event.ctrl_pressed)
			else: finish()
			return true
	if event is InputEventMouseMotion:
		cursor=event.position
		if drawing: stroke(event.position,event.ctrl_pressed)
		else: last_hit=hit(event.position)
		return true
	return false
func draw() -> void:
	if not active(): return
	if tool=="Guide": draw_guide()
	if tool=="Select strands" and selected_root>=0:
		var data:=item().growth; var visual: KiwiSurfaceGrowthInstance=canvas.visuals.get(item().id); var world:=visual.global_transform if visual!=null else canvas.session.document.world_transform(item()); var positions:=KiwiSurfaceGrowth.posed_points(data,visual.growth_skeleton if visual!=null else null)
		for root: Dictionary in data.roots:
			if int(root.id)!=selected_root: continue
			var frame:=world*KiwiSurfaceGrowth.point_frame(data,root,positions); var curve:=KiwiSurfaceGrowth.curve(data,root)
			for i in range(1,curve.size()):
				if not canvas.camera.is_position_behind(frame*curve[i]): canvas.overlay.draw_line(canvas.project(frame*curve[i-1]),canvas.project(frame*curve[i]),Color("ffd078"),3.,true)
	if last_hit.is_empty(): return
	var center: Vector2=canvas.project(last_hit.world); var edge: Vector2=canvas.project(last_hit.world+canvas.camera.global_basis.x*radius)
	canvas.overlay.draw_arc(center,center.distance_to(edge),0,TAU,64,Color("77e1ce"),1.5,true)
	canvas.overlay.draw_string(ThemeDB.fallback_font,Vector2(14,24),tool+" · Shift-wheel radius · Ctrl invert · Esc cancel",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("77e1ce"))
func create_guide(root_index: int) -> void:
	var component:=item()
	if component==null or root_index<0 or root_index>=component.growth.roots.size(): return
	var data:=component.growth; var root: Dictionary=data.roots[root_index]; var guide_id:=ActorData.new_id(); var before:=data.guides.duplicate(true); var after:=before.duplicate(true)
	after[guide_id]={"root":int(root.id),"points":KiwiSurfaceGrowth.curve(data,root),"influence":1.0,"locked":false,"group":""}; var assignment_before:=data.groom.duplicate(true); var assignment_after:=assignment_before.duplicate(true)
	for index in query(data,root.position,radius):
		var id:=str(data.roots[index].id)
		if not assignment_after.has(id): assignment_after[id]={}
		var weights: Dictionary=assignment_after[id].get("guide_weights",{}).duplicate()
		weights[guide_id]=maxf(.001,1.-(data.roots[index].position as Vector3).distance_to(root.position)/maxf(.001,radius))
		while weights.size()>4:
			var weakest: String=weights.keys()[0]
			for key: String in weights:
				if float(weights[key])<float(weights[weakest]): weakest=key
			weights.erase(weakest)
		assignment_after[id].guide_weights=weights
		assignment_after[id].guide=guide_id
	var session:=canvas.session; var id:=component.id; var reference: WeakRef=weakref(session)
	var apply:=func(guides: Dictionary,groom: Dictionary):
		var active_session:=reference.get_ref() as KiwiModelSession
		if active_session==null: return
		var target:=active_session.document.component(id)
		if target!=null and target.growth!=null: target.growth.guides=guides.duplicate(true); target.growth.groom=groom.duplicate(true); target.growth.revision+=1; target.growth.render_cache=null
	apply.call(after,assignment_after); session.custom_action("Create hair guide",apply.bind(before,assignment_before),apply.bind(after,assignment_after),assignment_after.size()*4); selected_guide=guide_id; selected_root=int(root.id)
func guide_frame() -> Transform3D:
	var data:=item().growth; var visual: KiwiSurfaceGrowthInstance=canvas.visuals.get(item().id); var points:=KiwiSurfaceGrowth.posed_points(data,visual.growth_skeleton if visual!=null else null); var world:=visual.global_transform if visual!=null else canvas.session.document.world_transform(item())
	var guide: Dictionary=data.guides.get(selected_guide,{})
	for root: Dictionary in data.roots:
		if int(root.id)==int(guide.get("root",-1)): return world*KiwiSurfaceGrowth.point_frame(data,root,points)
	return world
func draw_guide() -> void:
	var data:=item().growth
	if not data.guides.has(selected_guide): return
	var frame:=guide_frame(); var points: PackedVector3Array=data.guides[selected_guide].points
	for i in points.size():
		var point:=frame*points[i]
		if canvas.camera.is_position_behind(point): continue
		var screen:=canvas.project(point); canvas.overlay.draw_circle(screen,5,Color("ffd078"))
		if i>0: canvas.overlay.draw_line(canvas.project(frame*points[i-1]),screen,Color("ffd078"),2,true)
func guide_event(event: InputEvent) -> bool:
	var data:=item().growth
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and guide_point>=0:
		data.guides=guide_before.duplicate(true); data.revision+=1; data.render_cache=null; guide_point=-1; canvas.request_sync(); return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			if data.guides.has(selected_guide) and not data.guides[selected_guide].get("locked",false):
				var frame:=guide_frame(); var points: PackedVector3Array=data.guides[selected_guide].points; var best:=10.0; var selected:=-1
				for i in range(1,points.size()):
					var distance:=canvas.project(frame*points[i]).distance_to(event.position)
					if distance<best: best=distance; selected=i
				if selected>=0: guide_point=selected; guide_before=data.guides.duplicate(true); guide_plane=Plane(canvas.camera.global_basis.z,frame*points[selected]); return true
			var closest:=12.0; var chosen:=-1; var visual: KiwiSurfaceGrowthInstance=canvas.visuals.get(item().id); var world:=visual.global_transform if visual!=null else canvas.session.document.world_transform(item()); var points:=KiwiSurfaceGrowth.posed_points(data,visual.growth_skeleton if visual!=null else null)
			for i in data.roots.size():
				var point: Vector3=world*KiwiSurfaceGrowth.point_frame(data,data.roots[i],points).origin
				if canvas.camera.is_position_behind(point): continue
				var distance:=canvas.project(point).distance_to(event.position)
				if distance<closest: closest=distance; chosen=i
			if chosen>=0: create_guide(chosen); canvas.gesture_finished.emit()
			return true
		elif guide_point>=0:
			var after:=data.guides.duplicate(true); var before:=guide_before.duplicate(true); guide_point=-1; var id:=item().id; var session:=canvas.session; var reference: WeakRef=weakref(session)
			var apply:=func(value: Dictionary):
				var active_session:=reference.get_ref() as KiwiModelSession
				if active_session==null: return
				var target:=active_session.document.component(id)
				if target!=null and target.growth!=null: target.growth.guides=value.duplicate(true); target.growth.revision+=1; target.growth.render_cache=null
			session.custom_action("Move groom guide point",apply.bind(before),apply.bind(after),after.size()*16); return true
		return true
	if event is InputEventMouseMotion and guide_point>=0:
		var ray:=canvas.ray(event.position); var hit: Variant=guide_plane.intersects_ray(ray.origin,ray.direction)
		if hit!=null:
			var points: PackedVector3Array=data.guides[selected_guide].points; points[guide_point]=guide_frame().affine_inverse()*hit; data.guides[selected_guide].points=points; data.revision+=1; data.render_cache=null
			var visual: KiwiSurfaceGrowthInstance=canvas.visuals.get(item().id)
			if visual!=null: visual.update_growth()
		return true
	return false
