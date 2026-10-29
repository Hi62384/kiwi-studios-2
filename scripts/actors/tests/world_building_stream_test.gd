extends "res://scripts/actors/tests/surface_growth_test.gd"
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
const Massing=preload("res://Workspaces/EnvironmentWorkspace/world/world_building_massing.gd")
const Stream=preload("res://Workspaces/EnvironmentWorkspace/world/world_building_stream.gd")
func run() -> void:
	var authored: Resource=Buildings.rectangular(8.,10.,2,false); authored.source_id="streamed-building"; var mesh_key:=Builder.mesh_key(Massing.mesh(authored))
	var document:=KiwiEnvironmentDocument.new(); var owner:=KiwiModelComponent.new(); owner.id="stream-world"; owner.title="World"; var world_source:=preload("res://Workspaces/EnvironmentWorkspace/world/world_source.gd").new(); world_source.building_detail_distance=80.; world_source.max_active_buildings=4; owner.parameters.world_source=world_source; document.components.append(owner); document.component_settings[owner.id]={"kind":"group"}
	var item:=KiwiModelComponent.new(); item.id=authored.source_id; item.title="Streamed building"; item.parent_id=owner.id; item.transform.origin=Vector3.ZERO; item.mesh=Massing.mesh(authored); item.parameters={"architecture_source":authored,"architecture_type":"building","architecture_owner":item.id,"world_lazy_building":true,"world_owner":owner.id,"_architecture_mesh":mesh_key,"_architecture_materials":[]}; document.components.append(item); document.component_settings[item.id]={"kind":"building","collision":true}
	check(document.validate().is_empty(),"A saved low-detail building keeps a valid authored building source")
	var path:="user://lazy_building_"+ActorData.new_id()+".tres"; var saved:=ResourceSaver.save(document,path); var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(saved==OK and reopened!=null and reopened.component_kind(item.id)=="building" and reopened.component(item.id).parameters.world_lazy_building,"Low-detail authored building state survives native save and reopen")
	var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(480,360); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); var camera:=Camera3D.new(); camera.position=Vector3(0,8,16); view.add_child(camera); camera.look_at(Vector3.ZERO); camera.current=true
	var runtime:=KiwiEnvironmentRuntime.new(); view.add_child(runtime); runtime.configure(document); var started:=Time.get_ticks_msec()
	while not runtime.geometry_ready(false) and Time.get_ticks_msec()-started<15000: await process_frame
	var streamed: Node3D=runtime.nodes.get(item.id); var shell:=streamed.get_node_or_null("BuildingDistanceShell") as MeshInstance3D; var detail:=streamed.get_node_or_null("BuildingDetail") as KiwiEnvironmentRuntime
	check(runtime.geometry_ready(false) and detail!=null and detail.nodes.size()>1 and shell!=null and not shell.visible,"Near-camera streamed buildings replace the saved massing shell with complete native detail")
	var first_builds: int=runtime.building_stream.builds; camera.position=Vector3(0,0,500); runtime.geometry_ready(false); await process_frame
	check(not is_instance_valid(streamed.get_node_or_null("BuildingDetail")) and shell.visible and runtime.building_stream.cache_bytes>0,"Distant buildings release rendered detail but retain their bounded CPU detail cache")
	camera.position=Vector3(0,8,16); started=Time.get_ticks_msec()
	while not runtime.geometry_ready(false) and Time.get_ticks_msec()-started<5000: await process_frame
	check(runtime.geometry_ready(false) and runtime.building_stream.builds==first_builds,"Returning near a cached building reuses its generated detail")
	camera.position=Vector3(0,0,500); started=Time.get_ticks_msec()
	while not runtime.geometry_ready(true) and Time.get_ticks_msec()-started<15000: await process_frame
	var full_detail:=streamed.get_node_or_null("BuildingDetail") as KiwiEnvironmentRuntime; var collision_found:=false
	if full_detail!=null:
		for collision: CollisionShape3D in full_detail.find_children("*","CollisionShape3D",true,false): collision_found=collision_found or collision.shape!=null
	check(runtime.geometry_ready(true) and full_detail!=null and not full_detail.visible and collision_found and shell.visible,"Physics preparation materializes complete distant building collision while keeping coarse massing visible")
	runtime.building_stream.dispose(); view.queue_free(); DirAccess.remove_absolute(path)
	print("WORLD BUILDING STREAM: %d checks, %d failures"%[checks,failures]); quit(failures)
