extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Cities=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session,Vector3(10,3,20),true); var id:=world.id; var initial:=Worlds.source(world); var terrain:=session.environment().terrain(initial.terrain_id); terrain.amplitude=.3; terrain.frequency=.025; terrain.prepare(); var source: Resource=Cities.create(initial,Vector3.ZERO,"Town"); var result:=await Edit.request(session,id,source,"Generate terrain-aware town"); var authored:=Worlds.source(session.document.component(id)); var field: RefCounted=authored.terrain_field
	check(result.errors.is_empty() and field!=null and authored.terrain_dependency_key!=0,"World jobs capture a shared immutable terrain dependency before settlement generation")
	var buildings:=0; var clear:=true; var reference_heights: Dictionary={}
	for component in session.document.components:
		if not component.parameters.has("architecture_source"): continue
		buildings+=1; var pose:=session.document.world_transform(session.document.component(id)).affine_inverse()*session.document.world_transform(component); var blueprint: Resource=component.parameters.architecture_source
		for corner: Vector2 in blueprint.footprint:
			var point:=pose*Vector3(corner.x,0.,corner.y); var surface: Dictionary=field.sample(Vector2(point.x,point.z)); clear=clear and not surface.is_empty() and point.y>float(surface.height)+.1
		reference_heights[component.id]=pose.origin.y
	check(buildings==9 and clear,"Town foundations place actual floor geometry above the sampled terrain across each footprint")
	var entries:=0; var connected:=true
	for component in session.document.components:
		if component.title!="Entrance steps": continue
		entries+=1; var parent:=session.document.component(component.parent_id); var bounds: AABB=session.document.world_transform(component)*component.mesh.bounds(); var door_height:=session.document.world_transform(parent).origin.y; connected=connected and absf(bounds.end.y-door_height)<.03 and component.mesh.validate().is_empty()
	check(entries==buildings and connected,"Native entrance steps connect the road elevation to each terrain-adapted building floor")
	var graph: Dictionary=session.document.component(id).parameters.world_graph; var follows:=true
	for road: Dictionary in graph.edges:
		for point: Vector3 in road.points:
			var surface: Dictionary=field.sample(Vector2(point.x,point.z)); follows=follows and not surface.is_empty() and absf(point.y-float(surface.height)-.03)<.06
	check(follows,"Generated settlement streets follow the same world-relative terrain field as their buildings")
	var grading:=preload("res://Workspaces/EnvironmentWorkspace/world/world_terrain.gd").grading_plan(session,id,authored)
	print("CITY GRADING error=",grading.error," graph_edges=",graph.edges.size()," layers=",grading.get("settings",{}).get("generation").layers.size() if grading.has("settings") else -1)
	check(str(grading.error).is_empty() and not grading.settings.generation.layers.is_empty() and authored.roads.is_empty(),"Roadbed grading includes derived city streets rather than only manually drawn roads")
	var saved_path:="user://world_settlement_terrain.res"; var saved:=ResourceSaver.save(session.environment(),saved_path); var loaded:=ResourceLoader.load(saved_path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(saved==OK and loaded!=null and loaded.validate().is_empty() and Worlds.source(loaded.component(id)).terrain_field==null,"Native saves store editable source and dependency keys without serializing live worker snapshots")
	terrain=session.environment().terrain(authored.terrain_id); terrain.base_height+=.5; terrain.prepare(); result=await Edit.request(session,id,authored,"Refresh changed terrain"); var shifted:=true
	for component_id in reference_heights:
		var component:=session.document.component(component_id); var pose:=session.document.world_transform(session.document.component(id)).affine_inverse()*session.document.world_transform(component); shifted=shifted and absf(pose.origin.y-float(reference_heights[component_id])-.5)<.01
	check(result.errors.is_empty() and shifted,"Changing terrain invalidates the dependency and updates untouched building elevations while retaining their IDs")
	print("WORLD SETTLEMENT TERRAIN: %d checks, %d failures"%[checks,failures]); quit(failures)
