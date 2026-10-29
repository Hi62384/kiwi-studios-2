extends RefCounted
## Constrained rectangular plans; manual polygon editing remains authoritative elsewhere.
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
static func generate(authored: Resource,room_count: int=5,corridor_width: float=1.2,types: PackedStringArray=PackedStringArray(),weights: PackedFloat32Array=PackedFloat32Array()) -> Dictionary:
	var source: Resource=Source.copy(authored); var errors: PackedStringArray=source.validate()
	if not errors.is_empty(): return {"source":null,"errors":errors}
	if room_count<2 or room_count>12: errors.append("Choose between two and twelve rooms per level.")
	if corridor_width<.9: errors.append("The hallway must be at least 0.9 m wide.")
	for floor: Dictionary in source.floors:
		var polygon: PackedVector2Array=floor.get("footprint",source.footprint); var bounds:=Rect2(polygon[0],Vector2.ZERO)
		for point in polygon: bounds=bounds.expand(point)
		if polygon.size()!=4 or not _rectangle(polygon,bounds): errors.append("Automatic layouts support rectangular, axis-aligned levels. Edit this footprint manually."); continue
		if bounds.size.x<corridor_width+3. or bounds.size.y<3.: errors.append("This footprint is too small for two room wings and a usable hallway."); continue
		var walls: Array=[]
		for wall: Dictionary in floor.walls:
			var a: Vector2=wall.a; var b: Vector2=wall.b
			var boundary: bool=(is_equal_approx(a.x,b.x) and (is_equal_approx(a.x,bounds.position.x) or is_equal_approx(a.x,bounds.end.x))) or (is_equal_approx(a.y,b.y) and (is_equal_approx(a.y,bounds.position.y) or is_equal_approx(a.y,bounds.end.y)))
			if boundary:
				var openings: Array=[]
				for opening: Dictionary in wall.get("openings",[]):
					if opening.get("type","")!="window": openings.append(opening)
				wall.openings=openings; walls.append(wall)
		var center:=bounds.get_center().x; var left:=center-corridor_width*.5; var right:=center+corridor_width*.5
		var rooms: Array=[{"id":"hall","name":"Hallway","type":"corridor","polygon":_polygon(Rect2(left,bounds.position.y,corridor_width,bounds.size.y))}]
		for side in 2:
			var count: int=(room_count+1)/2 if side==0 else room_count/2; var rng:=RandomNumberGenerator.new(); rng.seed=hash([source.seed,str(floor.id),side]); var sizes: Array[float]=[]; var total:=0.
			for index in count:
				var ordinal:=index*2+side; var weight:=float(weights[ordinal]) if ordinal<weights.size() else 1.; var size:=maxf(.1,weight)*rng.randf_range(.92,1.08); sizes.append(size); total+=size
			var cursor:=bounds.position.y; var x:=left if side==0 else right
			for index in count:
				var ordinal:=index*2+side; var end:=bounds.end.y if index==count-1 else cursor+bounds.size.y*sizes[index]/total
				if end-cursor<1.5: errors.append("Some rooms are narrower than 1.5 m. Reduce the room count or enlarge the footprint."); continue
				var area:=Rect2(bounds.position.x if side==0 else right,cursor,left-bounds.position.x if side==0 else bounds.end.x-right,end-cursor); var kind: String=str(types[ordinal]) if ordinal<types.size() else ["Living area","Kitchen","Bedroom","Bedroom","Bathroom"][ordinal%5]
				rooms.append({"id":"layout:room"+str(ordinal),"name":kind,"type":kind.to_snake_case(),"polygon":_polygon(area)})
				walls.append({"id":"layout:doorwall"+str(ordinal),"a":Vector2(x,cursor),"b":Vector2(x,end),"height_mode":"level","openings":[{"id":"layout:door"+str(ordinal),"type":"door","t":.5,"width":.85,"height":2.05,"bottom":0.,"angle":0.}]})
				if index>0: walls.append({"id":"layout:partition"+str(ordinal),"a":Vector2(area.position.x,cursor),"b":Vector2(area.end.x,cursor),"height_mode":"level","openings":[]})
				cursor=end
		# Place windows within room spans so interior partitions never split the glazing.
		for room: Dictionary in rooms:
			if room.get("type","")=="corridor": continue
			var room_polygon: PackedVector2Array=room.polygon; var room_bounds:=Rect2(room_polygon[0],Vector2.ZERO)
			for point in room_polygon: room_bounds=room_bounds.expand(point)
			var side_x:=bounds.position.x if room_bounds.position.x<left else bounds.end.x; var point:=Vector2(side_x,room_bounds.get_center().y)
			for wall: Dictionary in walls:
				var a: Vector2=wall.a; var b: Vector2=wall.b
				if not is_equal_approx(a.x,side_x) or not is_equal_approx(b.x,side_x) or point.y<minf(a.y,b.y) or point.y>maxf(a.y,b.y): continue
				wall.openings.append({"id":"layout:window:"+str(room.id),"type":"window","t":(point-a).dot(b-a)/a.distance_squared_to(b),"width":minf(1.4,room_bounds.size.y*.5),"height":1.2,"bottom":1.}); break
		floor.rooms=rooms; floor.walls=walls
	if errors.is_empty(): errors.append_array(source.validate())
	return {"source":source if errors.is_empty() else null,"errors":errors}
static func _rectangle(polygon: PackedVector2Array,bounds: Rect2) -> bool:
	for point in polygon:
		if not ((is_equal_approx(point.x,bounds.position.x) or is_equal_approx(point.x,bounds.end.x)) and (is_equal_approx(point.y,bounds.position.y) or is_equal_approx(point.y,bounds.end.y))): return false
	return true
static func _polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])
static func connectivity(source: Resource) -> Dictionary:
	var regions: Dictionary={}; var edges: Array[Dictionary]=[]; var warnings:=PackedStringArray(); var exterior:="outside"
	regions[exterior]={"name":"Exterior","floor":""}
	for floor: Dictionary in source.floors:
		for room: Dictionary in floor.get("rooms",[]): regions[str(floor.id)+":"+str(room.id)]={"name":str(room.get("name","Room")),"floor":str(floor.id),"polygon":room.get("polygon",PackedVector2Array()),"holes":room.get("holes",[])}
		for wall: Dictionary in floor.get("walls",[]):
			var a: Vector2=wall.a; var b: Vector2=wall.b; var direction: Vector2=(b-a).normalized(); var offset:=Vector2(-direction.y,direction.x)*(float(source.wall_thickness)*.5+.05)
			for opening: Dictionary in wall.get("openings",[]):
				if opening.get("type","") not in ["door","slider","arch"] or float(opening.get("bottom",0.))>.15: continue
				var point:=a.lerp(b,float(opening.get("t",.5))); var one:=_region(floor,point+offset,source); var two:=_region(floor,point-offset,source)
				if one.is_empty() or two.is_empty() or one==two: warnings.append("Opening "+str(opening.id)+" does not connect two usable regions."); continue
				if float(opening.get("width",1.))<.65 or float(opening.get("height",2.))<1.8: warnings.append("Opening "+str(opening.id)+" is too small for ordinary pedestrian clearance."); continue
				edges.append({"from":one,"to":two,"kind":"door","opening":str(opening.id),"floor":str(floor.id),"position":Vector3(point.x,float(floor.elevation),point.y)})
	for stair: Dictionary in source.stairs:
		var from:=""; var to:=""; var points:=stair_endpoints(stair); var low:=0.; var high:=0.
		for floor: Dictionary in source.floors:
			if str(floor.id)==str(stair.get("from","")): from=_region(floor,points[0],source); low=float(floor.elevation)
			if str(floor.id)==str(stair.get("to","")): to=_region(floor,points[1],source); high=float(floor.elevation)
		if from.is_empty() or to.is_empty() or from==exterior or to==exterior or high<=low: warnings.append("A staircase is disconnected from its level's rooms.")
		else: edges.append({"from":from,"to":to,"kind":"stairs","stair":str(stair.get("id",""))})
	var reached: Dictionary={exterior:true}; var queue: Array[String]=[exterior]; var index:=0
	while index<queue.size():
		var current:=queue[index]; index+=1
		for edge: Dictionary in edges:
			var next: String=edge.to if edge.from==current else (edge.from if edge.to==current else "")
			if not next.is_empty() and not reached.has(next): reached[next]=true; queue.append(next)
	for id: String in regions:
		if not reached.has(id): warnings.append(str(regions[id].name)+" has no connected route from outside.")
	return {"regions":regions,"connections":edges,"reachable":reached,"warnings":warnings}
static func stair_endpoints(stair: Dictionary) -> PackedVector2Array:
	var width:=maxf(.3,float(stair.get("width",1.))); var length:=maxf(.5,float(stair.get("length",4.))); var type:=int(stair.get("type",0)); var start:=Vector2(0.,-.08); var end:=Vector2(0.,length+.08)
	if type==1: end=Vector2(length*.5+width*.5+.08,length*.5+width*.5)
	elif type==2: end=Vector2(width*2.,-.08)
	elif type==3:
		start=Vector2(width*.75,-.08); var angle:=TAU*maxf(.5,float(stair.get("turns",1.))); end=Vector2(cos(angle),sin(angle))*width*.75+Vector2(-sin(angle),cos(angle))*.08
	var position: Vector2=stair.get("position",Vector2.ZERO); var rotation: float=-deg_to_rad(float(stair.get("yaw",0.)))
	return PackedVector2Array([start.rotated(rotation)+position,end.rotated(rotation)+position])
static func _region(floor: Dictionary,point: Vector2,source: Resource) -> String:
	for room: Dictionary in floor.get("rooms",[]):
		if not Geometry2D.is_point_in_polygon(point,room.get("polygon",PackedVector2Array())): continue
		var in_hole:=false
		for hole: PackedVector2Array in room.get("holes",[]): in_hole=in_hole or Geometry2D.is_point_in_polygon(point,hole)
		if not in_hole: return str(floor.id)+":"+str(room.id)
	return "outside" if not Geometry2D.is_point_in_polygon(point,floor.get("footprint",source.footprint)) else ""
