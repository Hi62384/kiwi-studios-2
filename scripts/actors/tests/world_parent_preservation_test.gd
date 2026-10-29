extends "res://scripts/actors/tests/surface_growth_test.gd"
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
const Remap=preload("res://Workspaces/ModelWorkspace/model_reference_remap.gd")
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var world:=Worlds.add(session,Vector3(12,3,4)); var id:=world.id; var source: Resource=Worlds.add_road(Worlds.source(world),Vector3(-25,0,5),Vector3(25,0,5)); var result:=await Edit.request(session,id,source); var road: KiwiModelComponent
	for item in session.document.components:
		if item.parameters.has("world_road"): road=item; break
	var road_id:=road.id
	check(result.errors.is_empty() and road.parameters.get("world_parent","")==id,"Generated parts record their expected parent identity")
	session.reparent_components([road_id],""); var pose:=session.document.world_transform(session.document.component(road_id)); source=Worlds.source(session.document.component(id)).copy(); source.render_distance+=10.; result=await Edit.request(session,id,source)
	var count:=0
	for item in session.document.components:
		if item.id==road_id: count+=1
	road=session.document.component(road_id)
	check(result.errors.is_empty() and count==1 and road.parent_id.is_empty() and session.document.world_transform(road).is_equal_approx(pose),"Regeneration retains an externally parented road once, at its original global pose")
	check(session.environment().validate().is_empty(),"Manual parent preservation keeps the native hierarchy valid")
	session.undo(); session.redo(); road=session.document.component(road_id); check(road.parent_id.is_empty() and session.document.world_transform(road).is_equal_approx(pose),"Regeneration undo/redo preserves manual hierarchy and pose")
	var copied:=road.copy_component(); Remap.component(copied,{id:"new-world",road_id:"new-road"}); check(copied.parameters.world_owner=="new-world" and copied.parameters.world_parent=="new-world","Copied world parent baselines follow remapped native identities")
	var detached:=road.copy_component(); Remap.component(detached,{}); check(not detached.parameters.has("world_parent") and not detached.parameters.has("world_manual_parent"),"Independent copies discard procedural parent ownership")
	print("WORLD PARENT PRESERVATION: %d checks, %d failures"%[checks,failures]); quit(failures)
