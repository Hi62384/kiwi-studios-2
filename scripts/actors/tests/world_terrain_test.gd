extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Terrain=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/world/world_source.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var ground:=session.add_terrain(); var terrain:=session.environment().terrain(ground.id); terrain.dimensions=Vector2(100,100); terrain.resolution=65; terrain.amplitude=0.; terrain.prepare(); var owner:=Worlds.add(session); var id:=owner.id; var source: Resource=Worlds.source(owner).copy(); source.terrain_id=ground.id; source.dimensions=Vector2(100,100); source.configure_regions(); source=Worlds.add_road(source,Vector3(-30,4,0),Vector3(30,4,0))
	var fitted:=Terrain.fit(session,id,source,0); check(fitted.error.is_empty() and fitted.source.roads[0].points.size()>2,"Terrain fitting samples the whole curved road rather than just its endpoints")
	var follows:=true
	for point: Vector3 in fitted.source.roads[0].points: follows=follows and absf(point.y-.03)<.0001
	check(follows,"Road fitting evaluates the referenced terrain in the same world coordinates")
	var installed:=Worlds.update(session,id,source); var before:=terrain.height(32,32); var edits:=terrain.edits.duplicate(); var error:=Terrain.grade(session,id,source)
	check(installed.errors.is_empty() and error.is_empty() and absf(terrain.height(32,32)-3.97)<.02,"Roadbed grading creates a real terrain cut/fill modifier matching the road elevation")
	check(terrain.edits==edits and absf(terrain.height(2,2)-before)<.0001,"Grading preserves authored sculpt samples and terrain away from the road")
	session.undo(); terrain=session.environment().terrain(ground.id); check(absf(terrain.height(32,32)-before)<.0001,"Road grading undoes through normal environment history")
	session.redo(); terrain=session.environment().terrain(ground.id); error=Terrain.grade(session,id,source,true); check(error.is_empty() and absf(terrain.height(32,32)-before)<.0001,"Removing the non-destructive road modifier restores the original base terrain")
	terrain.edits[32+32*65]=.75; var sculpt:=terrain.edits.duplicate(); error=Terrain.grade(session,id,source)
	check(error.is_empty() and absf(terrain.height(32,32)-3.97)<.02 and terrain.edits==sculpt,"Grading a sculpted surface reaches the road elevation once while preserving authored sculpt values")
	session.regenerate_terrain(ground.id,{"resolution":129}); terrain=session.environment().terrain(ground.id)
	check(absf(terrain.height(64,64)-3.97)<.02,"Changing terrain resolution resamples the frozen sculpt correction consistently")
	error=Terrain.grade(session,id,source,true); check(error.is_empty() and absf(terrain.height(64,64)-.75)<.0001,"Removing grading restores the original sculpted surface instead of erasing or doubling it")
	owner=session.document.component(id); owner.transform.origin=Vector3(10,0,15); var transformed: Resource=Worlds.source(owner).copy(); transformed.terrain_id=ground.id; var info:=Terrain.context(session,id,transformed); var sample:=Terrain.sample(info,Vector2.ZERO)
	check(info.error.is_empty() and not sample.is_empty() and absf(sample.height-.03)<.0001,"Terrain sampling respects translated world-group coordinates")
	owner.transform.basis=Basis(Vector3.RIGHT,.5); check(not Terrain.context(session,id,transformed).error.is_empty(),"Unsupported tilted terrain fitting reports a clear error instead of silently sampling the wrong position")
	var split_source: Resource=Source.new(); split_source.dimensions=Vector2(256,128); split_source.region_size=128.; split_source.configure_regions(); split_source=Worlds.add_road(split_source,Vector3(-60,0,10),Vector3(60,0,10)); var network:=preload("res://Workspaces/EnvironmentWorkspace/world/road_network.gd").generate(split_source); var graph: Dictionary=network.document.component(split_source.world_id).parameters.world_graph
	check(graph.edges.size()==2 and graph.adjacency.values().any(func(edges: Array): return edges.size()==2),"A cross-region road has one shared border node and two deterministic owned sections")
	split_source.regions[0].enabled=false; network=preload("res://Workspaces/EnvironmentWorkspace/world/road_network.gd").generate(split_source); var hidden:=0
	for item: KiwiModelComponent in network.document.components:
		if item.parameters.has("world_road") and not item.visible: hidden+=1
	check(hidden==1,"Disabling one region affects only its owned road section")
	print("WORLD TERRAIN: %d checks, %d failures"%[checks,failures]); quit(failures)
