extends RefCounted
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
var canvas: Control
var _drag: Dictionary={}
var _first: Variant=null
var _hover: Variant=null
var road_index:=0
var point_index:=0
var _world_id:=""
var district_tool:=preload("res://Workspaces/EnvironmentWorkspace/world/world_district_tool.gd").new()
func target() -> Dictionary:
	if canvas==null or canvas.environment_session()==null: return {}
	var session: KiwiEnvironmentSession=canvas.environment_session(); var item:=session.primary()
	while item!=null:
		if Worlds.source(item)!=null: return {"id":item.id,"source":Edit.source(session,item.id),"pose":session.document.world_transform(item)}
		item=session.document.component(item.parent_id)
	return {}
func cancel() -> void: _drag={}; _first=null; _hover=null; district_tool.canvas=canvas; district_tool.cancel(); canvas.overlay.queue_redraw()
func draw() -> void:
	district_tool.canvas=canvas; district_tool.draw()
	if canvas.environment_tool=="District boundary": return
	if canvas.environment_tool=="World regions": _draw_regions(); return
	if canvas.environment_tool not in ["Draw road","Road points"]:
		if not _drag.is_empty() or _first!=null: cancel()
		return
	var info:=target()
	if info.is_empty(): return
	if _world_id!=str(info.id): cancel(); _world_id=str(info.id)
	for road in info.source.roads.size():
		var points: PackedVector3Array=info.source.roads[road].points; var line:=PackedVector2Array()
		if not _drag.is_empty() and road==road_index:
			points=points.duplicate(); points[point_index]=_drag.point; _draw_strip(info,points,float(info.source.roads[road].width))
		for index in points.size():
			var point: Vector3=_drag.point if not _drag.is_empty() and road==road_index and index==point_index else points[index]; var world: Vector3=info.pose*point
			if canvas.camera.is_position_behind(world): line.clear(); continue
			var screen: Vector2=canvas.project(world); line.append(screen); canvas.overlay.draw_circle(screen,6.,Color("10242f")); canvas.overlay.draw_circle(screen,4.,Color("ffc678") if road==road_index and index==point_index else Color("75dfc5"))
		if line.size()>1: canvas.overlay.draw_polyline(line,Color("75dfc5"),2.,true)
	if _first is Vector3:
		var point: Vector3=info.pose*_first
		if not canvas.camera.is_position_behind(point): canvas.overlay.draw_circle(canvas.project(point),5.,Color("ffc678"))
		if _hover is Vector3 and (_hover as Vector3).distance_to(_first)>.05:
			_draw_strip(info,PackedVector3Array([_first,_hover]),6.)
			var end: Vector3=info.pose*_hover
			if not canvas.camera.is_position_behind(end): canvas.overlay.draw_circle(canvas.project(end),5.,Color("ffc678"))
func _draw_strip(info: Dictionary,points: PackedVector3Array,width: float) -> void:
	var geometry:=preload("res://Workspaces/EnvironmentWorkspace/world/road_geometry.gd"); var strip: KiwiModelMesh=geometry.strip(geometry.sample(points),width); var projected:=PackedVector2Array(); var valid:=PackedByteArray()
	for point: Vector3 in strip.vertices:
		var world: Vector3=info.pose*point; projected.append(canvas.project(world)); valid.append(0 if canvas.camera.is_position_behind(world) else 1)
	for face: PackedInt32Array in strip.faces:
		var polygon:=PackedVector2Array(); var visible:=true
		for index in face: polygon.append(projected[index]); visible=visible and bool(valid[index])
		if not visible: continue
		canvas.overlay.draw_colored_polygon(polygon,Color(.99,.75,.4,.22)); canvas.overlay.draw_line(polygon[0],polygon[1],Color("ffc678"),1.5,true); canvas.overlay.draw_line(polygon[2],polygon[3],Color("ffc678"),1.5,true)
func _draw_regions() -> void:
	var info:=target()
	if info.is_empty(): return
	for region: Dictionary in info.source.regions:
		var bounds: Rect2=region.bounds; var corners:=PackedVector2Array([bounds.position,Vector2(bounds.end.x,bounds.position.y),bounds.end,Vector2(bounds.position.x,bounds.end.y)]); var color:=Color("ffc678") if region.get("locked",false) else (Color("75dfc5") if region.get("enabled",true) else Color("6e7e88"))
		for edge in 4:
			var a: Vector3=info.pose*Vector3(corners[edge].x,.05,corners[edge].y); var b: Vector3=info.pose*Vector3(corners[(edge+1)%4].x,.05,corners[(edge+1)%4].y)
			if not canvas.camera.is_position_behind(a) and not canvas.camera.is_position_behind(b): canvas.overlay.draw_line(canvas.project(a),canvas.project(b),color,1.5,true)
		var center: Vector3=info.pose*Vector3(bounds.get_center().x,.05,bounds.get_center().y)
		if not canvas.camera.is_position_behind(center): canvas.overlay.draw_string(canvas.get_theme_default_font(),canvas.project(center)+Vector2(4,-6),str(region.get("name","Region")),HORIZONTAL_ALIGNMENT_LEFT,-1,13,color)
func _position(info: Dictionary,screen: Vector2,at: Vector3=Vector3.ZERO,ctrl: bool=false) -> Variant:
	var pose: Transform3D=info.pose; var normal: Vector3=(pose.basis*Vector3.UP).normalized(); var ray: Dictionary=canvas.ray(screen); var hit: Variant=Plane(normal,pose*at).intersects_ray(ray.origin,ray.direction); var ground_mode: bool=canvas.environment_tool in ["Draw road","District boundary"] or road_index<info.source.roads.size() and str(info.source.roads[road_index].get("mode","Ground"))=="Ground"
	if ground_mode and not str(info.source.terrain_id).is_empty():
		var surface: Dictionary=canvas.pick_terrain(screen)
		if not surface.is_empty() and str(surface.id)==str(info.source.terrain_id): hit=(surface.point as Vector3)+normal*.03
	if not hit is Vector3: return null
	var local:=pose.affine_inverse()*(hit as Vector3)
	if canvas.snap!=ctrl:
		local.x=snappedf(local.x,.5); local.z=snappedf(local.z,.5)
		if ground_mode and not str(info.source.terrain_id).is_empty():
			var context:=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain.gd").context(canvas.environment_session(),info.id,info.source)
			if str(context.error).is_empty():
				var surface:=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain.gd").sample(context,Vector2(local.x,local.z))
				if not surface.is_empty(): local.y=surface.height
	return local
func input(event: InputEvent) -> bool:
	district_tool.canvas=canvas
	if canvas.environment_tool=="District boundary": return district_tool.input(event)
	if canvas.environment_tool not in ["Draw road","Road points"]: return false
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE: cancel(); return true
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT and (not _drag.is_empty() or _first!=null): cancel(); return true
	if canvas._navigating or canvas._panning or canvas._orbiting: return false
	var info:=target()
	if info.is_empty(): return false
	if _world_id!=str(info.id): cancel(); _world_id=str(info.id)
	if not _drag.is_empty() and (road_index>=info.source.roads.size() or str(info.source.roads[road_index].id)!=str(_drag.road_id) or point_index>=(info.source.roads[road_index].points as PackedVector3Array).size()): cancel(); return true
	if event is InputEventKey and event.pressed and event.keycode in [KEY_DELETE,KEY_BACKSPACE] and canvas.environment_tool=="Road points":
		var result:=preload("res://Workspaces/EnvironmentWorkspace/world/road_editing.gd").remove_point(info.source,road_index,point_index)
		if result.source==null: canvas.notice.emit(result.error)
		else: _drag={}; canvas.world_replaced.emit(str(info.id),result.source)
		return true
	if event is InputEventMouseMotion and _first is Vector3 and canvas.environment_tool=="Draw road":
		_hover=_position(info,event.position,_first,event.ctrl_pressed); canvas.overlay.queue_redraw(); return true
	if event is InputEventMouseMotion and not _drag.is_empty():
		var point: Variant=_position(info,event.position,_drag.point,event.ctrl_pressed)
		if point is Vector3: _drag.point=point; canvas.overlay.queue_redraw()
		return true
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT: return false
	if not event.pressed:
		if _drag.is_empty(): return false
		var next: Resource=info.source.copy(); var points: PackedVector3Array=next.roads[road_index].points; var point: Vector3=_drag.point; _drag={}
		if points[point_index].is_equal_approx(point): return true
		points[point_index]=point; next.roads[road_index].points=points
		if point_index in [0,points.size()-1]:
			var node: String=next.roads[road_index].from if point_index==0 else next.roads[road_index].to; next.nodes[node]=point
			for road: Dictionary in next.roads:
				var controls: PackedVector3Array=road.points
				if road.from==node: controls[0]=point
				if road.to==node: controls[-1]=point
				road.points=controls
		canvas.world_replaced.emit(str(info.id),next); return true
	canvas.grab_focus()
	if canvas.environment_tool=="Draw road":
		var point: Variant=_position(info,event.position,Vector3.ZERO,event.ctrl_pressed)
		if not point is Vector3: return true
		if _first==null: _first=point; _hover=point; canvas.overlay.queue_redraw(); return true
		if (_first as Vector3).distance_to(point)<1.: return true
		var next:=Worlds.add_road(info.source,_first,point); _first=null; _hover=null; canvas.world_replaced.emit(str(info.id),next); return true
	var best:=12.; var nearest: Dictionary={}
	for road in info.source.roads.size():
		var points: PackedVector3Array=info.source.roads[road].points
		for index in points.size():
			var world: Vector3=info.pose*points[index]
			if canvas.camera.is_position_behind(world): continue
			var distance: float=(canvas.project(world) as Vector2).distance_to(event.position)
			if distance<best: best=distance; nearest={"road":road,"index":index,"point":points[index]}
	if not nearest.is_empty(): road_index=nearest.road; point_index=nearest.index; _drag={"point":nearest.point,"road_id":info.source.roads[road_index].id}; return true
	if event.shift_pressed:
		var best_edge:=INF; var edge_info: Dictionary={}
		for road in info.source.roads.size():
			var points: PackedVector3Array=info.source.roads[road].points
			for edge in points.size()-1:
				var a: Vector3=info.pose*points[edge]; var b: Vector3=info.pose*points[edge+1]
				if canvas.camera.is_position_behind(a) or canvas.camera.is_position_behind(b): continue
				var distance: float=event.position.distance_to(Geometry2D.get_closest_point_to_segment(event.position,canvas.project(a),canvas.project(b)))
				if distance<best_edge: best_edge=distance; edge_info={"road":road,"edge":edge,"point":points[edge].lerp(points[edge+1],.5)}
		if not edge_info.is_empty():
			var point: Variant=_position(info,event.position,edge_info.point,event.ctrl_pressed)
			if point is Vector3:
				var next: Resource=info.source.copy(); var points: PackedVector3Array=next.roads[edge_info.road].points; points.insert(int(edge_info.edge)+1,point); next.roads[edge_info.road].points=points; canvas.world_replaced.emit(str(info.id),next)
	return true
