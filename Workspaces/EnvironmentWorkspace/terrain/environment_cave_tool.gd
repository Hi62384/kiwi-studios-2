extends RefCounted
## Handles are editor-only. A drag/stroke edits a private resource and emits one
## replacement on release; the workspace generates and commits it atomically.
var canvas: Control
var cave_id:=""
var path_index:=0
var point_index:=0
var strength:=1.
var _drag: Dictionary={}
var _stroke: Dictionary={}
var _hit: Dictionary={}
func target() -> Dictionary:
	if canvas==null or canvas.environment_session()==null: return {}
	var session: KiwiEnvironmentSession=canvas.environment_session(); var selected:=session.primary(); var candidates: Array[KiwiModelComponent]=[]
	if selected!=null and session.environment().terrain(selected.id)!=null:
		var terrain:=session.environment().terrain(selected.id)
		for cave in terrain.caves:
			if cave_id.is_empty() or cave.cave_id==cave_id: cave_id=cave.cave_id; return {"id":selected.id,"cave":cave,"transform":session.document.world_transform(selected)}
		if not terrain.caves.is_empty(): cave_id=terrain.caves[0].cave_id; return {"id":selected.id,"cave":terrain.caves[0],"transform":session.document.world_transform(selected)}
		return {}
	for item in session.document.components:
		if not candidates.has(item) and session.environment().terrain(item.id)!=null: candidates.append(item)
	for item in candidates:
		var terrain:=session.environment().terrain(item.id)
		for cave in terrain.caves:
			if cave_id.is_empty() or cave.cave_id==cave_id: return {"id":item.id,"cave":cave,"transform":session.document.world_transform(item)}
	return {}
func points(info: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]; var cave:=info.cave as KiwiTerrainCave
	for path in cave.paths.size():
		for index in cave.paths[path].size(): result.append({"path":path,"point":index,"position":cave.paths[path][index]})
	for index in cave.chambers.size():
		var chamber:=cave.chambers[index]; result.append({"path":-1,"point":index,"position":Vector3(chamber.x,chamber.y,chamber.z)})
	return result
func draw() -> void:
	if not str(canvas.environment_tool).begins_with("Cave "): return
	var info:=target()
	if info.is_empty(): return
	var cave:=info.cave as KiwiTerrainCave; var transform: Transform3D=info.transform
	if canvas.environment_tool=="Cave path":
		for path in cave.paths.size():
			var polyline:=PackedVector2Array()
			for index in cave.paths[path].size():
				var position:=cave.paths[path][index]
				if not _drag.is_empty() and _drag.path==path and _drag.point==index: position=_drag.position
				var world:=transform*position
				if not canvas.camera.is_position_behind(world): polyline.append(canvas.project(world))
			if polyline.size()>1: canvas.overlay.draw_polyline(polyline,Color("6ddcc5"),2.,true)
		for handle in points(info):
			var position: Vector3=handle.position
			if not _drag.is_empty() and handle.path==_drag.path and handle.point==_drag.point: position=_drag.position
			var world:=transform*position
			if canvas.camera.is_position_behind(world): continue
			var point: Vector2=canvas.project(world); canvas.overlay.draw_circle(point,7.,Color("10242f")); canvas.overlay.draw_circle(point,4.5,Color("ffc678") if handle.path==path_index and handle.point==point_index else Color("76e3c9"))
	elif not _hit.is_empty():
		var local: Vector3=_hit.local; var normal: Vector3=(transform.basis.transposed()*(_hit.normal as Vector3)).normalized(); var side:=normal.cross(Vector3.UP if absf(normal.y)<.9 else Vector3.RIGHT).normalized(); var up:=side.cross(normal).normalized(); var ring:=PackedVector2Array()
		for index in 49: ring.append(canvas.project(transform*(local+(side*cos(index*TAU/48.)+up*sin(index*TAU/48.))*canvas.brush_radius)))
		canvas.overlay.draw_polyline(ring,Color("ffb77c") if canvas.environment_tool=="Cave fill" else Color("6ddcc5"),2.,true)
func input(event: InputEvent) -> bool:
	if not str(canvas.environment_tool).begins_with("Cave "): return false
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and (not _drag.is_empty() or not _stroke.is_empty()): cancel(); return true
	if event is InputEventKey and event.pressed and event.ctrl_pressed and event.keycode in [KEY_Z,KEY_Y] and (not _drag.is_empty() or not _stroke.is_empty()): cancel(); return true
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed and (not _drag.is_empty() or not _stroke.is_empty()): cancel(); return true
	if canvas._navigating or canvas._panning or canvas._orbiting: return false
	if event is InputEventMouseButton and event.pressed and event.shift_pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		canvas.brush_radius=clampf(canvas.brush_radius*(1.15 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1./1.15),.1,100.); canvas.brush_settings_changed.emit(); return true
	var info:=target()
	if info.is_empty(): return false
	if event is InputEventKey and event.pressed and event.keycode in [KEY_DELETE,KEY_BACKSPACE] and canvas.environment_tool=="Cave path":
		var cave: KiwiTerrainCave=(info.cave as KiwiTerrainCave).duplicate(true)
		if path_index<0 and point_index<cave.chambers.size(): cave.chambers.remove_at(point_index)
		elif path_index>=0 and path_index<cave.paths.size() and point_index<cave.paths[path_index].size() and cave.paths[path_index].size()>2:
			var path:=cave.paths[path_index].duplicate(); path.remove_at(point_index); cave.paths[path_index]=path
		else: return true
		canvas.cave_replaced.emit(str(info.id),cave); return true
	if canvas.environment_tool=="Cave path": return _path_input(event,info)
	if event is InputEventMouseMotion:
		_hit=canvas.pick_terrain(event.position)
		if not _stroke.is_empty() and not _hit.is_empty() and str(_hit.id)==str(info.id): _stroke_dab(_hit.local,event.ctrl_pressed)
		canvas.overlay.queue_redraw(); return not _stroke.is_empty()
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			canvas.grab_focus(); _hit=canvas.pick_terrain(event.position)
			if not _hit.is_empty() and str(_hit.id)==str(info.id): _stroke={"id":info.id,"cave":(info.cave as KiwiTerrainCave).duplicate(true),"last":_hit.local}; _stroke_dab(_hit.local,event.ctrl_pressed,true)
		elif not _stroke.is_empty():
			canvas.cave_replaced.emit(str(_stroke.id),_stroke.cave); _stroke={}; canvas.gesture_finished.emit()
		canvas.overlay.queue_redraw(); return true
	return false
func _stroke_dab(point: Vector3,invert: bool,first: bool=false) -> void:
	var last: Vector3=_stroke.last; var spacing:=maxf(.1,float(canvas.brush_radius)*float(canvas.brush_spacing))
	if not first and last.distance_to(point)<spacing: return
	var count:=clampi(ceili(last.distance_to(point)/spacing),1,32); var cave:=_stroke.cave as KiwiTerrainCave
	for index in range(1,count+1): cave.edits.append({"center":last.lerp(point,float(index)/count),"radius":maxf(.1,float(canvas.brush_radius)),"strength":strength,"smooth":canvas.environment_tool=="Cave smooth","fill":(canvas.environment_tool=="Cave fill")!=invert})
	_stroke.last=point
func _path_input(event: InputEvent,info: Dictionary) -> bool:
	if event is InputEventMouseMotion and not _drag.is_empty():
		var ray: Dictionary=canvas.ray(event.position); var hit: Variant=(_drag.plane as Plane).intersects_ray(ray.origin,ray.direction)
		if hit is Vector3: _drag.position=(info.transform as Transform3D).affine_inverse()*(hit as Vector3); canvas.overlay.queue_redraw()
		return true
	if not event is InputEventMouseButton: return false
	if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and not _drag.is_empty():
		var cave: KiwiTerrainCave=(info.cave as KiwiTerrainCave).duplicate(true); _set_point(cave,int(_drag.path),int(_drag.point),_drag.position); _drag={}; canvas.cave_replaced.emit(str(info.id),cave); canvas.gesture_finished.emit(); return true
	if not event.pressed or not event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: return false
	var nearest: Dictionary={}; var best:=12.
	for handle in points(info):
		var world: Vector3=(info.transform as Transform3D)*(handle.position as Vector3)
		if canvas.camera.is_position_behind(world): continue
		var distance: float=(canvas.project(world) as Vector2).distance_to(event.position)
		if distance<best: best=distance; nearest=handle
	if not nearest.is_empty():
		path_index=int(nearest.path); point_index=int(nearest.point); cave_id=str(info.cave.cave_id); canvas.grab_focus()
		if event.button_index==MOUSE_BUTTON_RIGHT:
			var cave: KiwiTerrainCave=(info.cave as KiwiTerrainCave).duplicate(true)
			if path_index<0: cave.chambers.remove_at(point_index)
			elif cave.paths[path_index].size()>2:
				var path:=cave.paths[path_index].duplicate(); path.remove_at(point_index); cave.paths[path_index]=path
			else: return true
			canvas.cave_replaced.emit(str(info.id),cave); return true
		var world: Vector3=(info.transform as Transform3D)*(nearest.position as Vector3); _drag={"path":path_index,"point":point_index,"position":nearest.position,"plane":Plane(canvas.camera.global_basis.z,world)}; return true
	if event.button_index==MOUSE_BUTTON_LEFT and event.shift_pressed:
		var cave: KiwiTerrainCave=(info.cave as KiwiTerrainCave).duplicate(true)
		if cave.paths.is_empty(): return false
		var chosen:=clampi(path_index,0,cave.paths.size()-1); var path:=cave.paths[chosen].duplicate(); var edge:=0; var distance:=INF
		for index in path.size()-1:
			var a: Vector2=canvas.project((info.transform as Transform3D)*path[index]); var b: Vector2=canvas.project((info.transform as Transform3D)*path[index+1]); var candidate: float=event.position.distance_to(Geometry2D.get_closest_point_to_segment(event.position,a,b))
			if candidate<distance: edge=index; distance=candidate
		var plane:=Plane(canvas.camera.global_basis.z,(info.transform as Transform3D)*path[edge].lerp(path[edge+1],.5)); var ray: Dictionary=canvas.ray(event.position); var hit: Variant=plane.intersects_ray(ray.origin,ray.direction)
		if hit is Vector3: path.insert(edge+1,(info.transform as Transform3D).affine_inverse()*(hit as Vector3)); cave.paths[chosen]=path; path_index=chosen; point_index=edge+1; canvas.cave_replaced.emit(str(info.id),cave); return true
	return false
func _set_point(cave: KiwiTerrainCave,path_index: int,point_index: int,point: Vector3) -> void:
	if path_index<0:
		var chamber:=cave.chambers[point_index]; cave.chambers[point_index]=Vector4(point.x,point.y,point.z,chamber.w)
	else:
		var path:=cave.paths[path_index].duplicate(); path[point_index]=point; cave.paths[path_index]=path
func cancel() -> void: _drag={}; _stroke={}; _hit={}; canvas.overlay.queue_redraw()
