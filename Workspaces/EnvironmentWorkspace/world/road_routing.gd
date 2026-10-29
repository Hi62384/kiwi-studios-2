extends AStar3D
var slope_weight:=40.
func _compute_cost(from_id: int,to_id: int) -> float:
	var a:=get_point_position(from_id); var b:=get_point_position(to_id); var horizontal:=Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))
	return horizontal*(1.+pow(absf(a.y-b.y)/maxf(.01,horizontal),2.)*slope_weight)
func _estimate_cost(from_id: int,to_id: int) -> float:
	var a:=get_point_position(from_id); var b:=get_point_position(to_id)
	return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))
static func route(start: Vector3,end: Vector3,bounds: Rect2,surface: Callable,restricted: Array=[],resolution: int=49,cancel: Callable=Callable(),allow_water: bool=false) -> Dictionary:
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x<=0. or bounds.size.y<=0.: return {"points":PackedVector3Array(),"error":"Choose a positive, finite routing region."}
	for point in [start,end]:
		var sample: Dictionary=surface.call(Vector2(point.x,point.z))
		if sample.is_empty() or (sample.get("water",false) and not allow_water): return {"points":PackedVector3Array(),"error":"Road endpoints must be on accessible dry ground, or bridges must be enabled."}
	var graph:=load("res://Workspaces/EnvironmentWorkspace/world/road_routing.gd").new() as AStar3D; var count:=clampi(resolution,9,97); var enabled: Dictionary={}; var step:=bounds.size/(count-1)
	for z in count:
		if cancel.is_valid() and cancel.call(): return {"points":PackedVector3Array(),"error":"Generation canceled.","cancelled":true}
		for x in count:
			var p:=bounds.position+Vector2(x,z)*step; var blocked:=false
			for polygon: PackedVector2Array in restricted:
				if Geometry2D.is_point_in_polygon(p,polygon): blocked=true; break
			if blocked: continue
			var sample: Dictionary=surface.call(p)
			if sample.is_empty() or (sample.get("water",false) and not allow_water): continue
			var height:=float(sample.height)
			if sample.get("water",false): height=maxf(height,float(sample.get("water_level",height))+.7)
			var id:=x+z*count; graph.add_point(id,Vector3(p.x,height,p.y),5. if sample.get("water",false) else 1.); enabled[id]=true
	for id: int in enabled:
		if cancel.is_valid() and cancel.call(): return {"points":PackedVector3Array(),"error":"Generation canceled.","cancelled":true}
		var x:=id%count; var z:=id/count
		for offset: Vector2i in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(-1,1)]:
			var next:=Vector2i(x,z)+offset; var target:=next.x+next.y*count
			if next.x<0 or next.y<0 or next.x>=count or next.y>=count or not enabled.has(target): continue
			if offset.x!=0 and offset.y!=0 and (not enabled.has(next.x+z*count) or not enabled.has(x+next.y*count)): continue
			var first:=graph.get_point_position(id); var last:=graph.get_point_position(target); var blocked:=false
			for polygon: PackedVector2Array in restricted:
				for edge in polygon.size():
					if Geometry2D.segment_intersects_segment(Vector2(first.x,first.z),Vector2(last.x,last.z),polygon[edge],polygon[(edge+1)%polygon.size()])!=null: blocked=true; break
				if blocked: break
			if blocked: continue
			if not allow_water:
				for portion in [ .25,.5,.75 ]:
					var point:=first.lerp(last,portion); var sample: Dictionary=surface.call(Vector2(point.x,point.z))
					if sample.is_empty() or sample.get("water",false): blocked=true; break
			if blocked: continue
			graph.connect_points(id,target)
	var a:=_reachable(graph,enabled,start,surface,restricted,allow_water,cancel); var b:=_reachable(graph,enabled,end,surface,restricted,allow_water,cancel)
	if a<0 or b<0: return {"points":PackedVector3Array(),"error":"No dry, unrestricted route is available."}
	var points:=graph.get_point_path(a,b)
	if points.is_empty(): return {"points":PackedVector3Array(),"error":"The road endpoints are disconnected by water or protected land."}
	if a==b and _legal(start,end,surface,restricted,allow_water,cancel): return {"points":PackedVector3Array([start,end]),"error":""}
	if not points[0].is_equal_approx(start): points.insert(0,start)
	if not points[-1].is_equal_approx(end): points.append(end)
	# Drop collinear grid steps without cutting corners through blocked cells.
	var result:=PackedVector3Array([points[0]])
	for index in range(1,points.size()-1):
		var before: Vector3=(points[index]-points[index-1]).normalized(); var after: Vector3=(points[index+1]-points[index]).normalized()
		if before.dot(after)<.9995: result.append(points[index])
	result.append(points[-1]); return {"points":result,"error":""}
static func _reachable(graph: AStar3D,enabled: Dictionary,point: Vector3,surface: Callable,restricted: Array,allow_water: bool,cancel: Callable) -> int:
	var candidates: Array=enabled.keys(); candidates.sort_custom(func(a: int,b: int): return graph.get_point_position(a).distance_squared_to(point)<graph.get_point_position(b).distance_squared_to(point))
	for index in mini(16,candidates.size()):
		var id:=int(candidates[index])
		if _legal(point,graph.get_point_position(id),surface,restricted,allow_water,cancel): return id
	return -1
static func _legal(a: Vector3,b: Vector3,surface: Callable,restricted: Array,allow_water: bool,cancel: Callable) -> bool:
	for index in restricted.size():
		if index%64==0 and cancel.is_valid() and cancel.call(): return false
		var polygon: PackedVector2Array=restricted[index]
		if Geometry2D.is_point_in_polygon(Vector2(a.x,a.z),polygon) or Geometry2D.is_point_in_polygon(Vector2(b.x,b.z),polygon): return false
		for edge in polygon.size():
			if Geometry2D.segment_intersects_segment(Vector2(a.x,a.z),Vector2(b.x,b.z),polygon[edge],polygon[(edge+1)%polygon.size()])!=null: return false
	if not allow_water:
		for portion in [ .25,.5,.75 ]:
			var point:=a.lerp(b,portion); var sample: Dictionary=surface.call(Vector2(point.x,point.z))
			if sample.is_empty() or sample.get("water",false): return false
	return true
