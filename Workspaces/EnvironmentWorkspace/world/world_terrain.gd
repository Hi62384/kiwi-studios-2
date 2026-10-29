extends RefCounted
const Routing=preload("res://Workspaces/EnvironmentWorkspace/world/road_routing.gd")
const Geometry=preload("res://Workspaces/EnvironmentWorkspace/world/road_geometry.gd")
static func context(session: KiwiEnvironmentSession,id: String,source: Resource) -> Dictionary:
	var owner:=session.document.component(id); var ground:=session.document.component(source.terrain_id); var terrain:=session.environment().terrain(source.terrain_id)
	if owner==null or ground==null or terrain==null: return {"error":"Choose a terrain reference for this world first."}
	var pose:=session.document.world_transform(owner); var ground_pose:=session.document.world_transform(ground)
	if absf(pose.basis.determinant())<.00001 or absf(ground_pose.basis.determinant())<.00001: return {"error":"A zero-sized world or terrain cannot be sampled."}
	if pose.basis.y.normalized().dot(Vector3.UP)<.999 or ground_pose.basis.y.normalized().dot(Vector3.UP)<.999: return {"error":"Road terrain fitting requires upright world and terrain groups."}
	terrain.prepare(); return {"error":"","terrain":terrain,"to_ground":ground_pose.affine_inverse()*pose,"to_world":pose.affine_inverse()*ground_pose}
static func sample(info: Dictionary,point: Vector2) -> Dictionary:
	var local: Vector3=info.to_ground*Vector3(point.x,0.,point.y); var terrain:=info.terrain as KiwiEnvironmentTerrain; var uv:=Vector2(local.x,local.z)/terrain.dimensions+Vector2.ONE*.5
	if uv.x<0. or uv.y<0. or uv.x>1. or uv.y>1.: return {}
	var p:=uv*(terrain.resolution-1); var cell:=Vector2i(p.floor()); var f:=p-Vector2(cell); var height:=lerpf(lerpf(terrain.height(cell.x,cell.y),terrain.height(cell.x+1,cell.y),f.x),lerpf(terrain.height(cell.x,cell.y+1),terrain.height(cell.x+1,cell.y+1),f.x),f.y); var position: Vector3=info.to_world*Vector3(local.x,height,local.z)
	var water:=terrain.water_at(Vector3(local.x,height+.001,local.z)); var wet:=not water.is_empty() and float(water.get("depth",0.))>.03
	return {"height":position.y+.03,"water":wet,"water_level":(info.to_world*(water.get("surface",Vector3(local.x,height,local.z)) as Vector3)).y,"water_depth":float(water.get("depth",0.))}
static func fit(session: KiwiEnvironmentSession,id: String,source: Resource,index: int,automatic: bool=false) -> Dictionary:
	var info:=context(session,id,source)
	if not info.error.is_empty(): return {"source":null,"error":info.error}
	var next: Resource=source.copy(); var road: Dictionary=next.roads[index]; var controls: PackedVector3Array=road.points; var points:=Geometry.sample(controls,2.)
	if automatic:
		var from:=sample(info,Vector2(controls[0].x,controls[0].z)); var to:=sample(info,Vector2(controls[-1].x,controls[-1].z))
		if from.is_empty() or to.is_empty(): return {"source":null,"error":"Both road endpoints must lie on the referenced terrain."}
		var exclusions: Array=[]
		for area: Dictionary in next.exclusions:
			if area.get("protected",true): exclusions.append(area.get("polygon",PackedVector2Array()))
		var route:=Routing.route(Vector3(controls[0].x,from.height,controls[0].z),Vector3(controls[-1].x,to.height,controls[-1].z),Rect2(-next.dimensions*.5,next.dimensions),func(point: Vector2): return sample(info,point),exclusions)
		if not route.error.is_empty(): return {"source":null,"error":route.error}
		points=Geometry.sample(route.points,2.)
	if points.size()>512: return {"source":null,"error":"Split this road into segments under about one kilometer before detailed terrain fitting."}
	for point in points.size():
		var position:=points[point]; var surface:=sample(info,Vector2(position.x,position.z))
		if surface.is_empty(): return {"source":null,"error":"Road "+str(road.get("name",""))+" leaves the referenced terrain."}
		position.y=surface.height; points[point]=position
	road.points=points; next.nodes[road.from]=points[0]; next.nodes[road.to]=points[-1]
	for other: Dictionary in next.roads:
		var values: PackedVector3Array=other.points
		if next.nodes.has(other.from): values[0]=next.nodes[other.from]
		if next.nodes.has(other.to): values[-1]=next.nodes[other.to]
		other.points=values
	return {"source":next,"error":""}
static func grade(session: KiwiEnvironmentSession,id: String,source: Resource,remove: bool=false) -> String:
	var plan:=grading_plan(session,id,source,remove)
	if not str(plan.error).is_empty(): return plan.error
	session.regenerate_terrain(str(plan.id),plan.settings); return ""
static func grading_plan(session: KiwiEnvironmentSession,id: String,source: Resource,remove: bool=false) -> Dictionary:
	var info:=context(session,id,source)
	if not info.error.is_empty(): return {"error":info.error}
	var terrain:=info.terrain as KiwiEnvironmentTerrain; var generator:=terrain.generation.duplicate(true) as KiwiTerrainGenerator if terrain.generation!=null else KiwiTerrainGenerator.new()
	if terrain.generation==null: generator.medium_weight=0.; generator.fine_weight=0.
	var layers: Array[Dictionary]=[]
	for layer in generator.layers:
		if layer.get("world_road_owner","")!=id: layers.append(layer)
	if not remove:
		var owner:=session.document.component(id); var roads: Array=owner.parameters.get("world_graph",{}).get("edges",source.roads)
		for road: Dictionary in roads:
			if not road.get("enabled",true) or road.get("bridge",false) or str(road.get("mode","Ground"))!="Ground": continue
			var points:=Geometry.sample(road.points,2.)
			for segment in points.size()-1:
				var a: Vector3=points[segment]; var b: Vector3=points[segment+1]
				if Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))<.02: continue
				var direction: Vector3=(b-a).normalized(); var side:=Vector3(-direction.z,0.,direction.x).normalized()*(preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").outer_half(road)+.5); var polygon:=PackedVector2Array()
				for p: Vector3 in [a+side,a-side,b-side,b+side]: var point: Vector3=info.to_ground*(p-Vector3.UP*.03); polygon.append(Vector2(point.x,point.z))
				var plane:=Plane(info.to_ground*(a-Vector3.UP*.03),info.to_ground*(b-Vector3.UP*.03),info.to_ground*(a+side-Vector3.UP*.03))
				if absf(plane.normal.y)<.2: return {"error":"A road section is too steep to grade safely."}
				layers.append({"id":"roadbed:"+str(road.id)+":"+str(segment),"type":"Foundation","world_road_owner":id,"road_id":road.id,"polygon":polygon,"plane":plane,"feather":2.,"enabled":true,"surface_target":true})
	generator.foundation_edits=terrain.edits.duplicate()
	generator.layers=layers; var errors:=generator.validate()
	if not errors.is_empty(): return {"error":errors[0]}
	if not layers.any(func(layer: Dictionary): return layer.get("surface_target",false)): generator.foundation_edits=PackedFloat32Array()
	return {"error":"","id":source.terrain_id,"settings":{"generation":generator}}
static func tunnels_plan(session: KiwiEnvironmentSession,id: String,source: Resource) -> Dictionary:
	var original:=session.environment().terrain(source.terrain_id); var needed:=false
	for road: Dictionary in source.roads: needed=needed or (road.get("enabled",true) and str(road.get("mode","Ground"))=="Tunnel")
	if original!=null:
		for cave: KiwiTerrainCave in original.caves: needed=needed or (cave.has_meta("world_road_owner") and str(cave.get_meta("world_road_owner"))==id)
	if not needed: return {"error":""}
	var info:=context(session,id,source)
	if not info.error.is_empty(): return info
	var caves: Array[KiwiTerrainCave]=[]; var portal_points: Dictionary={}; var portal_frames: Dictionary={}
	for cave: KiwiTerrainCave in original.caves:
		if not cave.has_meta("world_road_owner") or str(cave.get_meta("world_road_owner"))!=id: caves.append(cave)
	for road: Dictionary in source.roads:
		if not road.get("enabled",true) or str(road.get("mode","Ground"))!="Tunnel": continue
		var points:=Geometry.sample(road.points,.5); var height:=float(road.width)*.65+2.; var radius:=sqrt(pow(float(road.width)*.5+.35,2.)+pow(height*.5,2.))
		for endpoint in [points[0],points[-1]]:
			var ground:=sample(info,Vector2(endpoint.x,endpoint.z))
			if ground.is_empty() or float(ground.height)>endpoint.y+.3: return {"error":"Extend both tunnel endpoints beyond the hillside so the entrances can open to the surface."}
		var portals:=PackedVector3Array(); var frames: Array=[]; var last_inside:=false; var previous: Vector3=points[0]; var previous_depth:=-1.
		for point in points:
			var ground:=sample(info,Vector2(point.x,point.z))
			if ground.is_empty(): return {"error":"The tunnel must stay within its referenced terrain."}
			var depth:=float(ground.height)-point.y-height*.5-radius+.3; var inside:=depth>0.
			if inside!=last_inside:
				var t:=clampf(-previous_depth/maxf(.00001,absf(depth-previous_depth))*(1. if depth>previous_depth else -1.),0.,1.); var entrance:=previous.lerp(point,t); portals.append(entrance); frames.append({"position":entrance,"direction":(point-previous).normalized()}); last_inside=inside
			previous=point; previous_depth=depth
		if portals.size()<2: return {"error":"This road does not pass beneath enough terrain to form a tunnel. Use a ground road or lower its elevation."}
		portal_points[road.id]=portals; portal_frames[road.id]=frames
		var path:=PackedVector3Array(); var scale: Vector3=(info.to_ground as Transform3D).basis.get_scale().abs(); var local_radius:=radius*maxf(scale.x,maxf(scale.y,scale.z))
		for index in points.size():
			if index>0 and index<points.size()-1 and (points[index]-points[index-1]).normalized().dot((points[index+1]-points[index]).normalized())>.9995: continue
			path.append(info.to_ground*(points[index]+Vector3.UP*height*.5))
		path[0]-=(path[1]-path[0]).normalized()*local_radius; path[-1]+=(path[-1]-path[-2]).normalized()*local_radius
		var cave:=KiwiTerrainCave.new(); cave.cave_id=id+":tunnel:"+str(road.id); cave.title="Road tunnel · "+str(road.get("name","Road")); cave.radius=local_radius; cave.radius_variation=0.; cave.roughness=0.; cave.junction_smoothing=.1; cave.paths=[path]; cave.set_meta("world_road_owner",id); caves.append(cave)
	return {"error":"","id":source.terrain_id,"source":original,"signature":original.signature(),"portal_points":portal_points,"portal_frames":portal_frames,"settings":{"caves":caves}}
