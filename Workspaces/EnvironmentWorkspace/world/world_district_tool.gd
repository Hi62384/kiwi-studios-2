extends RefCounted
var canvas: Control
var drag: Dictionary={}
func cancel() -> void:
	drag.clear()
	if canvas!=null: canvas.overlay.queue_redraw()
func selection() -> Dictionary:
	var info: Dictionary=canvas.road_tool.target()
	if info.is_empty(): return {}
	var selected: Dictionary=canvas.get_meta("world_district_selection",{})
	if selected.get("world","")!=info.id: return {}
	for settlement in info.source.settlements.size():
		for index in info.source.settlements[settlement].get("districts",[]).size():
			var district: Dictionary=info.source.settlements[settlement].districts[index]
			if district.id==selected.get("district",""): info.settlement=settlement; info.index=index; info.district=district; return info
	return {}
func draw() -> void:
	if canvas.environment_tool!="District boundary":
		if not drag.is_empty(): cancel()
		return
	var info:=selection()
	if info.is_empty(): cancel(); return
	var polygon: PackedVector2Array=drag.get("polygon",info.district.polygon); var projected:=PackedVector2Array()
	for point in polygon:
		var world:=_world(info,point)
		if canvas.camera.is_position_behind(world): return
		projected.append(canvas.project(world))
	if projected.size()<3: return
	if not Geometry2D.triangulate_polygon(projected).is_empty(): canvas.overlay.draw_colored_polygon(projected,Color(.35,.85,.75,.12))
	var line:=projected.duplicate(); line.append(projected[0]); canvas.overlay.draw_polyline(line,Color("75dfc5"),2.,true)
	for point in projected: canvas.overlay.draw_circle(point,6.,Color("10242f")); canvas.overlay.draw_circle(point,4.,Color("ffc678"))
func _world(info: Dictionary,point: Vector2) -> Vector3:
	var height:=.08
	if info.source.terrain_field!=null:
		var sample: Dictionary=info.source.terrain_field.sample(point)
		if not sample.is_empty(): height=float(sample.height)+.08
	return info.pose*Vector3(point.x,height,point.y)
func input(event: InputEvent) -> bool:
	if canvas.environment_tool!="District boundary": return false
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: cancel(); return true
	if canvas._navigating or canvas._panning or canvas._orbiting: return false
	var info:=selection()
	if info.is_empty(): return false
	if not drag.is_empty() and str(drag.district)!=str(info.district.id): cancel()
	if event is InputEventMouseMotion and not drag.is_empty():
		var point: Variant=canvas.road_tool._position(info,event.position,Vector3.ZERO,event.ctrl_pressed)
		if point is Vector3: drag.polygon[int(drag.point)]=Vector2(point.x,point.z); canvas.overlay.queue_redraw()
		return true
	if not event is InputEventMouseButton: return false
	if event.button_index==MOUSE_BUTTON_RIGHT and not drag.is_empty(): cancel(); return true
	if event.button_index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]: return false
	if not event.pressed:
		if event.button_index==MOUSE_BUTTON_LEFT and not drag.is_empty(): _commit(info,drag.polygon); cancel(); return true
		return false
	var polygon: PackedVector2Array=info.district.polygon.duplicate(); var nearest:=-1; var distance:=12.
	for index in polygon.size():
		var world:=_world(info,polygon[index])
		if canvas.camera.is_position_behind(world): continue
		var next: float=(canvas.project(world) as Vector2).distance_to(event.position)
		if next<distance: distance=next; nearest=index
	if event.button_index==MOUSE_BUTTON_RIGHT:
		if nearest<0: return false
		if polygon.size()>3: polygon.remove_at(nearest); _commit(info,polygon)
		else: canvas.notice.emit("A district needs at least three boundary points.")
		return true
	canvas.grab_focus()
	if nearest>=0: drag={"district":info.district.id,"polygon":polygon,"point":nearest}; return true
	var point: Variant=canvas.road_tool._position(info,event.position,Vector3.ZERO,event.ctrl_pressed)
	if not point is Vector3: return true
	var local:=Vector2(point.x,point.z); var edge:=0; var best:=INF
	for index in polygon.size():
		var value:=local.distance_squared_to(Geometry2D.get_closest_point_to_segment(local,polygon[index],polygon[(index+1)%polygon.size()]))
		if value<best: best=value; edge=index
	polygon.insert(edge+1,local); drag={"district":info.district.id,"polygon":polygon,"point":edge+1}; canvas.overlay.queue_redraw(); return true
func _commit(info: Dictionary,polygon: PackedVector2Array) -> void:
	if polygon==info.district.polygon: return
	var next: Resource=info.source.copy(); next.settlements[int(info.settlement)].districts[int(info.index)].polygon=polygon.duplicate()
	var errors:=preload("res://Workspaces/EnvironmentWorkspace/world/world_districts.gd").validate(next.settlements[int(info.settlement)])
	if not errors.is_empty(): canvas.notice.emit(errors[0]); return
	canvas.world_replaced.emit(str(info.id),next)
