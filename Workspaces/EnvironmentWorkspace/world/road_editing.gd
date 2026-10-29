extends RefCounted
## Pure source edits. The existing world transaction installs geometry and undo.
static func reverse(source: Resource,index: int) -> Dictionary:
	if index<0 or index>=source.roads.size(): return _error("Choose an existing road.")
	var next: Resource=source.copy(); var road: Dictionary=next.roads[index]; var points: PackedVector3Array=road.points; points.reverse(); road.points=points; var from:=str(road.from); road.from=road.to; road.to=from; return _result(next,index)
static func remove_point(source: Resource,index: int,point: int) -> Dictionary:
	if index<0 or index>=source.roads.size(): return _error("Choose an existing road.")
	var next: Resource=source.copy(); var road: Dictionary=next.roads[index]; var points: PackedVector3Array=road.points
	if points.size()<3 or point<0 or point>=points.size(): return _error("A road needs at least two control points.")
	var endpoint:=point==0 or point==points.size()-1; points.remove_at(point); road.points=points
	if endpoint:
		var id:=ActorData.new_id(); next.nodes[id]=points[0] if point==0 else points[-1]
		if point==0: road.from=id
		else: road.to=id
	_cleanup(next); return _result(next,index)
static func split(source: Resource,index: int,point: int=-1) -> Dictionary:
	if index<0 or index>=source.roads.size(): return _error("Choose an existing road.")
	var next: Resource=source.copy(); var road: Dictionary=next.roads[index]; var points: PackedVector3Array=road.points
	if point<1 or point>=points.size()-1:
		var middle:=points.size()/2; points.insert(middle,points[middle-1].lerp(points[middle],.5)); point=middle
	road.source_family=road.get("source_family",road.id); var node:=ActorData.new_id(); next.nodes[node]=points[point]; var second:=road.duplicate(true); second.id=ActorData.new_id(); second.name=str(road.get("name","Road"))+" · B"; second.from=node; second.points=points.slice(point); road.to=node; road.points=points.slice(0,point+1); next.roads.insert(index+1,second); return _result(next,index)
static func join(source: Resource,index: int,other: int) -> Dictionary:
	if index<0 or other<0 or index>=source.roads.size() or other>=source.roads.size() or index==other: return _error("Choose two different roads.")
	var next: Resource=source.copy(); var first: Dictionary=next.roads[index]; var second: Dictionary=next.roads[other].duplicate(true); var a: PackedVector3Array=first.points; var b: PackedVector3Array=second.points
	if str(first.get("mode","Ground"))!=str(second.get("mode","Ground")): return _error("Join roads with the same ground, bridge or tunnel mode.")
	if a[-1].distance_to(b[-1])<a[-1].distance_to(b[0]): b.reverse(); var from:=str(second.from); second.from=second.to; second.to=from
	if a[-1].distance_to(b[0])>.25: return _error("The end of the selected road must meet an endpoint of the other road.")
	a[-1]=(a[-1]+b[0])*.5; a.append_array(b.slice(1)); first.points=a; first.to=second.to; next.roads.remove_at(other); _cleanup(next); return _result(next,index-1 if other<index else index)
static func _cleanup(source: Resource) -> void:
	var used: Dictionary={}
	for road: Dictionary in source.roads: used[road.from]=true; used[road.to]=true
	for id in source.nodes.keys():
		if not used.has(id): source.nodes.erase(id)
static func _result(source: Resource,index: int) -> Dictionary: return {"source":source,"index":index,"error":""}
static func _error(message: String) -> Dictionary: return {"source":null,"error":message}
