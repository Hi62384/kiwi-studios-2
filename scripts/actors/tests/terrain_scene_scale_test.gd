extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var memory_before:=OS.get_static_memory_usage(); var source:=KiwiEnvironmentTerrain.new(); var job:=preload("res://Workspaces/EnvironmentWorkspace/environment_generation_job.gd").new(); job.start(source,{"resolution":513,"dimensions":Vector2(1024,1024),"amplitude":15.},false)
	while not job.complete(): await process_frame
	job.collect(); var document:=KiwiEnvironmentDocument.new(); var item:=document.add_terrain(job.terrain); var path:="user://scene-scale.res"; ResourceSaver.save(document,path,ResourceSaver.FLAG_COMPRESS); var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(400,300); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); var camera:=Camera3D.new(); view.add_child(camera); camera.position=Vector3(0,900,900); camera.look_at(Vector3.ZERO); camera.far=5000.; camera.current=true; var data:=ActorData.new(); data.type_id=&"environment_asset"; data.values[&"environment_path"]=path; var actor:=preload("res://Workspaces/EnvironmentWorkspace/environment_actor.gd").new(); actor.bind(data); var start:=Time.get_ticks_usec(); view.add_child(actor); actor.set_active(true); var start_ms:=float(Time.get_ticks_usec()-start)/1000.; actor.set_process(false); actor.content.set_process(false)
	check(not actor.physics_geometry_ready(),"A large Scene asset defers CPU preparation and native uploads rather than exposing incomplete collision")
	var peak:=0.; var passes:=0; var deadline:=Time.get_ticks_msec()+45000
	while not actor.physics_geometry_ready() and Time.get_ticks_msec()<deadline:
		start=Time.get_ticks_usec(); actor._process(0.); actor.content._process(0.); peak=maxf(peak,float(Time.get_ticks_usec()-start)/1000.); passes+=1; await process_frame
	check(actor.physics_geometry_ready() and actor.error.is_empty() and actor.content.nodes[item.id].get_child_count()==256,"All 256 real terrain chunks and their colliders finish loading before Scene physics captures the asset")
	check(actor.content.find_children("*","Node",true,false).size()<1024 and KiwiEnvironmentTerrain._base_cache_size<=KiwiEnvironmentTerrain.BASE_CACHE_BYTES,"Large scene geometry stays chunked and its shared CPU cache respects the byte budget")
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color.BLACK; environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=1.; view.add_child(environment)
	var high:=0; var low:=0
	if DisplayServer.get_name()!="headless":
		view.mesh_lod_threshold=0.
		for i in 5: await RenderingServer.frame_post_draw
		high=view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME); view.mesh_lod_threshold=1000.
		for i in 5: await RenderingServer.frame_post_draw
		low=view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME); check(high>10000 and low<high*.7,"The actual large Scene render uses fewer primitives at lower detail without reducing its collision data")
	print("TERRAIN SCENE SCALE actor_start_ms=",start_ms," max_upload_pass_ms=",peak," passes=",passes," tracked_memory_delta=",OS.get_static_memory_usage()-memory_before," GPU_primitives_full=",high," coarse=",low); view.queue_free(); await process_frame; DirAccess.remove_absolute(path); print("TERRAIN SCENE SCALE: %d checks, %d failures"%[checks,failures]); quit(failures)
