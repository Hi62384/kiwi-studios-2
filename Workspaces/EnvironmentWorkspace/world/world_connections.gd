extends RefCounted
const Section=preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd")
const Routing=preload("res://Workspaces/EnvironmentWorkspace/world/road_routing.gd")
static func augment(source: Resource,nodes: Dictionary,roads: Array[Dictionary],cancel: Callable=Callable()) -> Dictionary:
	var result: Dictionary={"connections":[],"warnings":PackedStringArray()}
	if not source.connect_settlements: return result
	var settlements: Array=[]; var gates: Dictionary={}; var groups: Dictionary={}
	for settlement: Dictionary in source.settlements:
		if not settlement.get("enabled",true): continue
		var id:=str(settlement.id); var candidates: Dictionary={}
		for road: Dictionary in roads:
			if str(road.get("settlement",""))==id and road.get("enabled",true): candidates[road.from]=true; candidates[road.to]=true
		if candidates.is_empty(): continue
		settlements.append(settlement); gates[id]=candidates.keys(); groups[id]=id
	if settlements.size()<2: return result
	for road: Dictionary in source.roads:
		if not road.get("enabled",true): continue
		var a:=str(road.get("connection_from","")); var b:=str(road.get("connection_to",""))
		if groups.has(a) and groups.has(b): _union(groups,a,b)
	var pairs: Array[Dictionary]=[]
	for a in settlements.size():
		for b in range(a+1,settlements.size()):
			var from: String=settlements[a].id; var to: String=settlements[b].id; var id:="connection:"+(from if from<to else to)+":"+(to if from<to else from); var best:=INF; var ends: Array=[]
			for first: String in gates[from]:
				for last: String in gates[to]:
					var distance: float=(nodes[first] as Vector3).distance_squared_to(nodes[last])
					if distance<best: best=distance; ends=[first,last]
			pairs.append({"id":id,"from":from,"to":to,"ends":ends,"distance":best,"name":str(settlements[a].get("name","Settlement"))+" ↔ "+str(settlements[b].get("name","Settlement"))})
	pairs.sort_custom(func(a: Dictionary,b: Dictionary): return float(a.distance)<float(b.distance) if not is_equal_approx(float(a.distance),float(b.distance)) else str(a.id)<str(b.id))
	var profile:=Section.defaults(source.connection_road_type); var restricted: Array=[]
	for area: Dictionary in source.exclusions+source.occupied:
		if not area.get("protected",true): continue
		for polygon in Geometry2D.offset_polygon(area.polygon,Section.outer_half(profile)+1.): restricted.append(polygon)
	for pair: Dictionary in pairs:
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		if _root(groups,pair.from)==_root(groups,pair.to) or source.connection_overrides.get(pair.id,{}).get("disabled",false): continue
		var first: Vector3=nodes[pair.ends[0]]; var last: Vector3=nodes[pair.ends[1]]; var routed: Dictionary
		if source.terrain_field!=null:
			var field: RefCounted=source.terrain_field
			routed=Routing.route(first,last,Rect2(-source.dimensions*.5,source.dimensions),func(point: Vector2): return field.sample(point),restricted,49,cancel,source.connection_bridges)
		else: routed={"points":PackedVector3Array([first,last]),"error":""}
		if routed.get("cancelled",false): return {"cancelled":true}
		if not str(routed.error).is_empty(): result.warnings.append(str(pair.name)+": "+str(routed.error)); continue
		var parts:=_parts(source,pair,routed.points,profile,cancel)
		if parts.get("cancelled",false): return {"cancelled":true}
		if not str(parts.error).is_empty(): result.warnings.append(str(pair.name)+": "+str(parts.error)); continue
		for road: Dictionary in parts.roads: nodes[road.from]=road.points[0]; nodes[road.to]=road.points[-1]; roads.append(road)
		_union(groups,pair.from,pair.to); result.connections.append({"id":pair.id,"name":pair.name,"from":pair.from,"to":pair.to,"roads":parts.roads,"length":parts.length,"bridges":parts.bridges})
	var islands: Dictionary={}
	for id in groups: islands[_root(groups,id)]=true
	if islands.size()>1: result.warnings.append("Some settlements could not be connected without crossing protected terrain, water or excessive grades.")
	return result
static func _parts(source: Resource,pair: Dictionary,path: PackedVector3Array,profile: Dictionary,cancel: Callable) -> Dictionary:
	var points:=PackedVector3Array(); var distance:=0.
	for index in path.size()-1:
		var count:=maxi(1,ceili(path[index].distance_to(path[index+1])/2.))
		if points.size()+count>32768: return {"error":"Connection sampling exceeds its region budget."}
		for step in count: points.append(path[index].lerp(path[index+1],float(step)/count))
	points.append(path[-1]); var ground:=PackedFloat32Array(); var wet:=PackedByteArray(); var target:=PackedFloat32Array(); var arc:=PackedFloat32Array([0.])
	for index in points.size():
		if cancel.is_valid() and cancel.call(): return {"cancelled":true}
		var point:=points[index]; var surface: Dictionary=source.terrain_field.sample(Vector2(point.x,point.z)) if source.terrain_field!=null else {"height":point.y}
		if surface.is_empty(): return {"error":"Connection leaves its terrain."}
		var height:=float(surface.height)+.03; ground.append(height); wet.append(1 if surface.get("water",false) else 0); target.append(maxf(height,float(surface.get("water_level",height))+.7) if surface.get("water",false) else height)
		if index>0: arc.append(arc[-1]+Vector2(point.x,point.z).distance_to(Vector2(points[index-1].x,points[index-1].z)))
	# Max-slope envelopes form approach ramps without jumping the road at a bank.
	for index in range(1,points.size()): target[index]=maxf(target[index],target[index-1]-.15*(arc[index]-arc[index-1]))
	for index in range(points.size()-2,-1,-1): target[index]=maxf(target[index],target[index+1]-.15*(arc[index+1]-arc[index]))
	if target[0]>ground[0]+.08 or target[-1]>ground[-1]+.08: return {"error":"Bridge approaches or terrain grades cannot meet the settlement gates. Move a gate or route this connection manually."}
	var elevated:=PackedByteArray(); var roads: Array[Dictionary]=[]; var bridges:=0
	for index in points.size():
		elevated.append(1 if wet[index] or target[index]>ground[index]+.05 else 0); points[index].y=target[index]
		if index>0 and absf(target[index]-target[index-1])>maxf(.01,arc[index]-arc[index-1])*.3: return {"error":"A connection exceeds its safe construction grade."}
	if not source.connection_bridges and elevated.count(1)>0: return {"error":"A bridge or major embankment is required. Enable connection bridges or route around this obstacle."}
	var start:=0; var mode:=int(elevated[0])
	for index in range(1,points.size()):
		if elevated[index]==mode and index<points.size()-1: continue
		var end:=index if index==points.size()-1 else index; var first:=maxi(0,start-1) if mode==1 else start
		if end>first:
			var road:=profile.duplicate(true); road.id=str(pair.id)+":"+str(roads.size()); road.name=pair.name; road.from=str(pair.ends[0]) if first==0 else str(pair.id)+":point:"+str(first); road.to=str(pair.ends[1]) if end==points.size()-1 else str(pair.id)+":point:"+str(end); road.points=points.slice(first,end+1); road.enabled=true; road.mode="Bridge" if mode==1 else "Ground"; road.auto_piers=mode==1; road.connection=pair.id; road.connection_from=pair.from; road.connection_to=pair.to; roads.append(road)
			if mode==1: bridges+=1
		start=index; mode=int(elevated[index])
	# Share exact boundary nodes even when a ramp starts one sample before water.
	for index in range(1,roads.size()):
		var boundary: Vector3=roads[index].points[0]; var previous: PackedVector3Array=roads[index-1].points
		while previous.size()>2 and previous[-2].distance_to(boundary)<previous[-1].distance_to(boundary): previous.remove_at(previous.size()-1)
		previous[-1]=boundary; roads[index-1].points=previous; roads[index-1].to=roads[index].from
	return {"roads":roads,"bridges":bridges,"length":arc[-1],"error":""}
static func _root(groups: Dictionary,id: String) -> String:
	while str(groups[id])!=id: id=str(groups[id])
	return id
static func _union(groups: Dictionary,a: String,b: String) -> void: groups[_root(groups,b)]=_root(groups,a)
static func make_editable(source: Resource,connection: Dictionary) -> Resource:
	var next: Resource=source.copy(); next.connection_overrides[connection.id]={"disabled":true}
	for original: Dictionary in connection.roads:
		var points: PackedVector3Array=original.points; var start:=0; var chunk:=0; var from:=str(original.from)
		while start<points.size()-1:
			var end:=mini(points.size()-1,start+511); var road:=original.duplicate(true); road.id=str(original.id)+":editable:"+str(chunk); road.points=points.slice(start,end+1); road.from=from; road.to=str(original.to) if end==points.size()-1 else str(original.id)+":cut:"+str(end); next.nodes[road.from]=road.points[0]; next.nodes[road.to]=road.points[-1]; next.roads.append(road); from=road.to; start=end; chunk+=1
	return next

