extends RefCounted
## Bounded faces of the actual ground-road graph, followed by native plot fitting.
static func extract(graph: Dictionary,cancel: Callable=Callable()) -> Dictionary:
	var half: Dictionary={}; var outgoing: Dictionary={}; var warnings:=PackedStringArray(); var blocks: Array[Dictionary]=[]
	for edge: Dictionary in _cycle_edges(graph):
		for reverse in 2:
			var points: PackedVector3Array=edge.points.duplicate()
			if reverse: points.reverse()
			var from:=str(edge.to if reverse else edge.from); var to:=str(edge.from if reverse else edge.to); var id:=str(edge.id)+":"+str(reverse); var delta:=Vector2(points[1].x-points[0].x,points[1].z-points[0].z)
			half[id]={"id":id,"twin":str(edge.id)+":"+str(1-reverse),"from":from,"to":to,"points":points,"angle":delta.angle(),"source":str(edge.get("source_road_id",edge.id)),"family":str(edge.get("source_family",edge.get("source_road_id",edge.id))),"clearance":preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").outer_half(edge)}
			if not outgoing.has(from): outgoing[from]=[]
			outgoing[from].append(id)
	for id in outgoing: outgoing[id].sort_custom(func(a: String,b: String): return float(half[a].angle)<float(half[b].angle))
	var visited: Dictionary={}; var used_ids: Dictionary={}; var keys:=half.keys(); keys.sort()
	for start: String in keys:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		if visited.has(start): continue
		var current:=start; var polygon:=PackedVector2Array(); var sequence:=PackedStringArray(); var boundary: Array[Dictionary]=[]; var clearance:=0.; var closed:=false
		for step in half.size()+1:
			if visited.has(current): closed=current==start; break
			visited[current]=true; var edge: Dictionary=half[current]; var points: PackedVector3Array=edge.points; boundary.append(edge); clearance=maxf(clearance,float(edge.clearance))
			if sequence.is_empty() or sequence[-1]!=str(edge.family): sequence.append(str(edge.family))
			for index in points.size()-1: polygon.append(Vector2(points[index].x,points[index].z))
			var choices: Array=outgoing.get(edge.to,[]); var twin:=choices.find(edge.twin)
			if twin<0: break
			current=choices[posmod(twin-1,choices.size())]
		if not closed or polygon.size()<3 or _area(polygon)<=1.: continue
		polygon=_simplify(polygon)
		if polygon.size()>4096 or Geometry2D.triangulate_polygon(polygon).is_empty(): warnings.append("A road block is too complex or self-crossing. Simplify its boundary before generating plots."); continue
		if sequence.size()>1 and sequence[0]==sequence[-1]: sequence.remove_at(sequence.size()-1)
		var canonical:=""
		for offset in sequence.size():
			var rotated:=PackedStringArray()
			for index in sequence.size(): rotated.append(sequence[(index+offset)%sequence.size()])
			var candidate:="|".join(rotated)
			if canonical.is_empty() or candidate<canonical: canonical=candidate
		var id:="block:"+str(hash(canonical)); var count:=int(used_ids.get(id,0)); used_ids[id]=count+1
		if count>0: id+=":"+str(count)
		blocks.append({"id":id,"polygon":polygon,"clearance":clearance,"boundary":boundary})
	return {"blocks":blocks,"warnings":warnings}
static func _cycle_edges(graph: Dictionary) -> Array:
	var edges: Dictionary={}; var adjacent: Dictionary={}; var degree: Dictionary={}; var queue: Array=[]
	for edge: Dictionary in graph.edges:
		if str(edge.get("mode","Ground"))!="Ground": continue
		edges[edge.id]=edge
		for node in [edge.from,edge.to]:
			if not adjacent.has(node): adjacent[node]=[]
			adjacent[node].append(edge.id); degree[node]=int(degree.get(node,0))+1
	for node in degree:
		if int(degree[node])<2: queue.append(node)
	var at:=0
	while at<queue.size():
		var node: String=queue[at]; at+=1
		for id in adjacent[node]:
			if not edges.has(id): continue
			var edge: Dictionary=edges[id]; var other: String=edge.to if edge.from==node else edge.from; edges.erase(id); degree[other]=int(degree[other])-1
			if int(degree[other])==1: queue.append(other)
	return edges.values()
static func plots(block: Dictionary,settlement: Dictionary,budget: int,cancel: Callable=Callable()) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]; var interior:=Geometry2D.offset_polygon(block.polygon,-float(block.clearance)-float(settlement.get("setback",2.))); var lot_size:=clampf(float(settlement.get("lot_size",18.)),10.,64.)
	for piece_index in interior.size():
		var piece: PackedVector2Array=interior[piece_index]
		if piece.size()<3 or absf(_area(piece))<36.: continue
		var bounds:=_bounds(piece); var columns:=maxi(1,ceili(bounds.size.x/lot_size)); var rows:=maxi(1,ceili(bounds.size.y/lot_size)); var size:=bounds.size/Vector2(columns,rows)
		for z in rows:
			if cancel.is_valid() and cancel.call(): return []
			for x in columns:
				if result.size()>=budget: return result
				var start:=bounds.position+Vector2(x,z)*size; var cell:=PackedVector2Array([start,start+Vector2(size.x,0),start+size,start+Vector2(0,size.y)]); var clipped:=Geometry2D.intersect_polygons(piece,cell)
				for part in clipped.size():
					if result.size()>=budget: return result
					var polygon: PackedVector2Array=clipped[part]
					if absf(_area(polygon))<25.: continue
					var fitted:=fit(polygon,block.boundary,cancel)
					if fitted.is_empty(): continue
					if float(fitted.distance)>float(block.clearance)+float(settlement.get("setback",2.))+lot_size*.75: continue # retain road-accessible frontage lots
					var id:=str(settlement.id)+":"+str(block.id)+":lot:"+str(piece_index)+":"+str(x)+":"+str(z)+":"+str(part); var pose: Transform3D=fitted.pose
					result.append({"id":id,"settlement":settlement.id,"block":block.id,"polygon":polygon,"pose":pose,"width":fitted.width,"depth":fitted.depth,"frontage":fitted.frontage,"district":"Residential","reserved":false})
	return result
static func fit(polygon: PackedVector2Array,boundary: Array,cancel: Callable=Callable()) -> Dictionary:
	var bounds:=_bounds(polygon); var candidates:=PackedVector2Array([bounds.get_center()]); var triangles:=Geometry2D.triangulate_polygon(polygon)
	for offset in range(0,triangles.size(),maxi(3,(triangles.size()/96)*3)):
		if offset+2<triangles.size(): candidates.append((polygon[triangles[offset]]+polygon[triangles[offset+1]]+polygon[triangles[offset+2]])/3.)
	var best: Dictionary={}; var area:=0.
	for center in candidates:
		if cancel.is_valid() and cancel.call(): return {}
		if not Geometry2D.is_point_in_polygon(center,polygon): continue
		var frontage:=_frontage(center,boundary)
		if frontage.is_empty(): continue
		var direction: Vector2=(frontage.point as Vector2)-center
		if direction.length()<.01: continue
		var pose:=Transform3D(Basis.looking_at(Vector3(direction.x,0,direction.y).normalized(),Vector3.UP),Vector3(center.x,0,center.y)); var low:=0.; var high:=minf(24.,bounds.size.length())
		for step in 12:
			var scale:=(low+high)*.5
			if contains_rectangle(polygon,pose,scale,scale*.9): low=scale
			else: high=scale
		var width:=low*.92; var depth:=width*.9
		if width<4. or depth<4. or width*depth<=area: continue
		area=width*depth; best={"pose":pose,"width":width,"depth":depth,"frontage":frontage.source,"distance":sqrt(float(frontage.distance))}
	return best
static func contains_rectangle(polygon: PackedVector2Array,pose: Transform3D,width: float,depth: float) -> bool:
	var rectangle:=PackedVector2Array()
	for point: Vector2 in [Vector2(-width,-depth),Vector2(width,-depth),Vector2(width,depth),Vector2(-width,depth)]:
		var transformed:=pose*Vector3(point.x*.5,0.,point.y*.5); var corner:=Vector2(transformed.x,transformed.z)
		if not Geometry2D.is_point_in_polygon(corner,polygon): return false
		rectangle.append(corner)
	for side in 4:
		for edge in polygon.size():
			if Geometry2D.segment_intersects_segment(rectangle[side],rectangle[(side+1)%4],polygon[edge],polygon[(edge+1)%polygon.size()])!=null: return false
	return true
static func _frontage(point: Vector2,boundary: Array) -> Dictionary:
	var best:=INF; var result: Dictionary={}
	for edge: Dictionary in boundary:
		var points: PackedVector3Array=edge.points
		for index in points.size()-1:
			var closest:=Geometry2D.get_closest_point_to_segment(point,Vector2(points[index].x,points[index].z),Vector2(points[index+1].x,points[index+1].z)); var distance:=point.distance_squared_to(closest)
			if distance<best: best=distance; result={"point":closest,"source":edge.source,"distance":distance}
	return result
static func _bounds(polygon: PackedVector2Array) -> Rect2:
	var result:=Rect2(polygon[0],Vector2.ZERO)
	for point in polygon: result=result.expand(point)
	return result
static func _area(polygon: PackedVector2Array) -> float:
	var result:=0.
	for index in polygon.size(): result+=polygon[index].cross(polygon[(index+1)%polygon.size()])
	return result*.5
static func _simplify(polygon: PackedVector2Array) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for index in polygon.size():
		var before:=polygon[index]-polygon[posmod(index-1,polygon.size())]; var after:=polygon[(index+1)%polygon.size()]-polygon[index]
		if before.length()<.001 or after.length()<.001 or before.normalized().dot(after.normalized())>.99999: continue
		result.append(polygon[index])
	return result
