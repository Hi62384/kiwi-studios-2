extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
const Roads=preload("res://Workspaces/EnvironmentWorkspace/world/road_network.gd")
const Geometry=preload("res://Workspaces/EnvironmentWorkspace/world/road_geometry.gd")
const Routing=preload("res://Workspaces/EnvironmentWorkspace/world/road_routing.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session); var id:=world.id; var source: Resource=Worlds.source(world).copy()
	check(source.regions.size()==4 and source.validate().is_empty(),"World starts with valid stable region coordinates and authored source settings")
	var identities: Array=[]
	for region: Dictionary in source.regions: identities.append(region.id)
	source.configure_regions(); check(source.regions.map(func(region: Dictionary): return region.id)==identities,"Reconfiguring unchanged world bounds preserves region identities")
	source=Worlds.add_road(source,Vector3(-40,0,0),Vector3(40,0,0)); source=Worlds.add_road(source,Vector3(0,0,-40),Vector3(0,0,40)); var first:=Roads.generate(source); var second:=Roads.generate(source); var graph: Dictionary=first.document.component(id).parameters.world_graph; var junctions:=0
	for node in graph.adjacency: if graph.adjacency[node].size()==4: junctions+=1
	check(first.errors.is_empty() and graph.edges.size()==4 and junctions==1,"Crossing roads split into an explicit connected four-way junction")
	check(hash(graph)==hash(second.document.component(id).parameters.world_graph),"Identical authored world and road data generate deterministic topology")
	var geometry_valid:=true
	for item: KiwiModelComponent in first.document.components:
		if item.mesh!=null:
			geometry_valid=geometry_valid and item.mesh.validate().is_empty()
			for face in item.mesh.faces.size(): geometry_valid=geometry_valid and item.mesh.normal(face).is_finite() and item.mesh.normal(face).length()>.9
	check(geometry_valid,"Solid road sections and junctions have valid nondegenerate actual geometry")
	var installed:=await Edit.request(session,id,source,"Create crossing roads"); var count:=session.document.components.size(); check(installed.errors.is_empty() and count>6 and session.environment().validate().is_empty(),"Worker results install native road sections and surface details in the existing environment hierarchy")
	session.undo(); var absent:=session.document.components.size()==1; session.redo(); check(absent and session.document.components.size()==count,"One undo/redo restores the source graph and all generated road sections together")
	var road: KiwiModelComponent=session.document.components[1]; var road_id:=road.id; road.transform.origin.y=2.; var mesh:=road.mesh; var next: Resource=Worlds.source(session.document.component(id)).copy(); next.render_distance=2000.; await Edit.request(session,id,next)
	check(session.document.component(road_id).transform.origin.y==2. and session.document.component(road_id).mesh==mesh,"Unrelated source changes preserve local road transforms and reuse unchanged meshes")
	var path:="user://world_roads.res"; ResourceSaver.save(session.environment(),path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(loaded!=null and loaded.validate().is_empty() and Worlds.source(loaded.component(id)).roads.size()==2,"Environment save/reload preserves editable world source, regions, graph and generated road geometry")
	var sample:=func(point: Vector2): return {"height":16.*exp(-pow(point.x/8.,2.)-pow(point.y/8.,2.))}
	var route:=Routing.route(Vector3(-40,0,0),Vector3(40,0,0),Rect2(-50,-50,100,100),sample)
	var avoids:=false
	for point: Vector3 in route.points: avoids=avoids or absf(point.z)>10.
	check(route.error.is_empty() and avoids,"Cost-based road routing chooses a manageable path around a steep hill")
	var curve:=Geometry.sample(PackedVector3Array([Vector3.ZERO,Vector3(10,0,5),Vector3(20,0,0)])); var strip:=Geometry.strip(curve,4.)
	check(strip.vertices.size()==curve.size()*2 and strip.faces.size()==curve.size()-1,"Curved roads share cross-section vertices continuously instead of overlapping disconnected strips")
	print("WORLD ROADS: %d checks, %d failures"%[checks,failures]); quit(failures)
