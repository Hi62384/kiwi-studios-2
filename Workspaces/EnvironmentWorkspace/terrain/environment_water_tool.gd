extends RefCounted
## Water path handles share the scene camera, snapping and transactional edits.
var canvas: Control
var river_index:=0
var point_index:=0
var _drag: Dictionary={}
func target() -> Dictionary:
	if canvas==null or canvas.environment_session()==null: return {}
	var session: KiwiEnvironmentSession=canvas.environment_session(); var selected:=session.primary()
	if selected==null: return {}
	var terrain:=session.environment().terrain(selected.id)
	if terrain==null or terrain.hydrology==null or terrain.hydrology.manual_rivers.is_empty(): return {}
	return {"id":selected.id,"terrain":terrain,"source":terrain.hydrology,"transform":session.document.world_transform(selected)}
func path_points(info: Dictionary,index: int) -> PackedVector3Array:
	var source:=info.source as KiwiTerrainHydrology; var river: Dictionary=source.manual_rivers[index]; var id:=str(river.get("id",""))
	for generated: Dictionary in (info.terrain as KiwiEnvironmentTerrain).water_data.get("paths",[]):
		if not generated.get("automatic",false) and str(generated.get("id",""))==id and not id.is_empty(): return generated.points
	return river.get("points",PackedVector3Array())
func draw() -> void:
	if canvas.environment_tool!="Water paths":
		if not _drag.is_empty(): cancel()
		return
	var info:=target()
	if info.is_empty(): return
	var source:=info.source as KiwiTerrainHydrology; var pose: Transform3D=info.transform
	for path in source.manual_rivers.size():
		var points:=path_points(info,path); var line:=PackedVector2Array()
		for index in points.size():
			var local:=points[index]
			if not _drag.is_empty() and path==river_index and index==point_index: local=_drag.position
			var world:=pose*local
			if canvas.camera.is_position_behind(world):
				if line.size()>1: canvas.overlay.draw_polyline(line,Color("6dc9ff"),2.,true)
				line.clear(); continue
			var screen: Vector2=canvas.project(world); line.append(screen); canvas.overlay.draw_circle(screen,7.,Color("10242f")); canvas.overlay.draw_circle(screen,4.5,Color("ffc678") if path==river_index and index==point_index else Color("6dc9ff"))
		if line.size()>1: canvas.overlay.draw_polyline(line,Color("6dc9ff"),2.,true)
func input(event: InputEvent) -> bool:
	if canvas.environment_tool!="Water paths": return false
	if (event is InputEventKey and event.pressed and (event.keycode==KEY_ESCAPE or event.ctrl_pressed and event.keycode in [KEY_Z,KEY_Y])) or (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT and not _drag.is_empty()):
		if not _drag.is_empty(): cancel(); return true
	if canvas._navigating or canvas._panning or canvas._orbiting: return false
	var info:=target()
	if info.is_empty(): return false
	var original:=info.source as KiwiTerrainHydrology
	if event is InputEventKey and event.pressed and event.keycode in [KEY_DELETE,KEY_BACKSPACE]: return _remove(info)
	if event is InputEventMouseMotion and not _drag.is_empty():
		var ray: Dictionary=canvas.ray(event.position); var hit: Variant=(_drag.plane as Plane).intersects_ray(ray.origin,ray.direction)
		if hit is Vector3:
			var point: Vector3=(info.transform as Transform3D).affine_inverse()*hit
			if canvas.snap!=event.ctrl_pressed: point=point.snapped(Vector3.ONE*canvas.grid_step)
			_drag.position=point; canvas.overlay.queue_redraw()
		return true
	if not event is InputEventMouseButton: return false
	if event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and not _drag.is_empty():
		var next:=original.duplicate(true) as KiwiTerrainHydrology; var points: PackedVector3Array=next.manual_rivers[river_index].points; var position: Vector3=_drag.position
		if bool(next.manual_rivers[river_index].get("follow_terrain",true)): position.y=points[point_index].y
		var changed:=not position.is_equal_approx(points[point_index]); points[point_index]=position; next.manual_rivers[river_index].points=points; _drag={}
		if changed: canvas.water_replaced.emit(str(info.id),next)
		canvas.gesture_finished.emit(); return true
	if not event.pressed or not event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: return false
	var nearest: Dictionary={}; var best:=12.
	for path in original.manual_rivers.size():
		var points:=path_points(info,path)
		for index in points.size():
			var world: Vector3=(info.transform as Transform3D)*points[index]
			if canvas.camera.is_position_behind(world): continue
			var distance: float=(canvas.project(world) as Vector2).distance_to(event.position)
			if distance<best: best=distance; nearest={"path":path,"index":index,"point":points[index]}
	if not nearest.is_empty():
		river_index=int(nearest.path); point_index=int(nearest.index); canvas.grab_focus()
		if event.button_index==MOUSE_BUTTON_RIGHT: return _remove(info)
		var pose: Transform3D=info.transform; var world:=pose*(nearest.point as Vector3); var normal: Vector3=(pose.basis*Vector3.UP).normalized() if bool(original.manual_rivers[river_index].get("follow_terrain",true)) else canvas.camera.global_basis.z
		_drag={"position":nearest.point,"plane":Plane(normal,world)}; return true
	if event.button_index==MOUSE_BUTTON_LEFT and event.shift_pressed:
		var next:=original.duplicate(true) as KiwiTerrainHydrology; river_index=clampi(river_index,0,next.manual_rivers.size()-1); var points:=path_points(info,river_index); var edge:=0; var distance:=INF
		for index in points.size()-1:
			var a: Vector2=canvas.project((info.transform as Transform3D)*points[index]); var b: Vector2=canvas.project((info.transform as Transform3D)*points[index+1]); var candidate: float=event.position.distance_to(Geometry2D.get_closest_point_to_segment(event.position,a,b))
			if candidate<distance: edge=index; distance=candidate
		var pose: Transform3D=info.transform; var plane:=Plane((pose.basis*Vector3.UP).normalized(),pose*points[edge].lerp(points[edge+1],.5)); var ray: Dictionary=canvas.ray(event.position); var hit: Variant=plane.intersects_ray(ray.origin,ray.direction)
		if hit is Vector3:
			var values: PackedVector3Array=next.manual_rivers[river_index].points; values.insert(edge+1,pose.affine_inverse()*hit); next.manual_rivers[river_index].points=values; point_index=edge+1; canvas.water_replaced.emit(str(info.id),next)
		return true
	return false
func _remove(info: Dictionary) -> bool:
	var next: KiwiTerrainHydrology=(info.source as KiwiTerrainHydrology).duplicate(true)
	if river_index>=next.manual_rivers.size(): return true
	var points: PackedVector3Array=next.manual_rivers[river_index].points
	if points.size()<=2 or point_index>=points.size(): return true
	points.remove_at(point_index); point_index=mini(point_index,points.size()-1); next.manual_rivers[river_index].points=points; canvas.water_replaced.emit(str(info.id),next); return true
func cancel() -> void: _drag={}; canvas.overlay.queue_redraw()
