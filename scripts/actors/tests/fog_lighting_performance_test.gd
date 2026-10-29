extends "res://scripts/actors/tests/fog_lighting_render_test.gd"
func run() -> void:
	registry=ActorRegistry.new(); BasicActors.register_all(registry); viewport=SubViewport.new(); viewport.own_world_3d=true; viewport.size=Vector2i(512,384); viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var environment:=Environment.new(); environment.background_mode=Environment.BG_COLOR; environment.background_color=Color.BLACK; environment.volumetric_fog_density=0.; environment.volumetric_fog_temporal_reprojection_enabled=false; environment.volumetric_fog_length=30.; viewport.find_world_3d().environment=environment
	lens=Camera3D.new(); viewport.add_child(lens); lens.position=Vector3(6,3,7); lens.look_at(Vector3(0,1,-2)); lens.current=true
	var volumes: Array[ActorRuntime]=[]; var lights: Array[ActorRuntime]=[]
	for i in 3: volumes.append(make_actor(&"fog_volume",{&"position":Vector3(i*2-2,1,-2),&"volume_size":Vector3(8,6,12),&"density":.04})); volumes[-1].set_active(i==0)
	for i in 4:
		var light:=make_actor(&"light_3d",{&"light_type":2 if i%2==0 else 1,&"position":Vector3(i*2-3,2,2),&"energy":5.,&"volumetric_fog_energy":1.,&"range":12.,&"shadows":false}); lights.append(light); light.set_active(i==0)
	make_actor(&"basic_shape",{&"position":Vector3(0,1,0),&"scale":Vector3(1,2,.2)})
	var measurable:=RenderingServer.has_method("viewport_set_measure_render_time")
	if measurable: RenderingServer.call("viewport_set_measure_render_time",viewport.get_viewport_rid(),true)
	for scenario in [[1,0,1,Vector2i(64,32)],[4,0,1,Vector2i(64,32)],[4,4,1,Vector2i(64,32)],[4,4,3,Vector2i(64,32)],[4,4,3,Vector2i(192,96)]]:
		RenderingServer.environment_set_volumetric_fog_volume_size(scenario[3].x,scenario[3].y)
		for i in lights.size(): lights[i].set_active(i<scenario[0]); lights[i].actor.values[&"shadows"]=i<scenario[1]; lights[i].evaluate(0.,lights[i].actor.values)
		for i in volumes.size(): volumes[i].set_active(i<scenario[2])
		await capture(); var cpu:=[]; var gpu:=[]; var frames:=[]
		for i in 12:
			var start:=Time.get_ticks_usec(); await process_frame; frames.append(float(Time.get_ticks_usec()-start)/1000.)
			if measurable:
				cpu.append(RenderingServer.call("viewport_get_measured_render_time_cpu",viewport.get_viewport_rid())); gpu.append(RenderingServer.call("viewport_get_measured_render_time_gpu",viewport.get_viewport_rid()))
		print("FOG PROFILE lights=",scenario[0]," shadow_lights=",scenario[1]," volumes=",scenario[2]," viewport=512x384 froxels=",scenario[3]," render_cpu_ms=",cpu," render_gpu_ms=",gpu," observed_frame_ms=",frames)
	check(is_equal_approx(viewport.scaling_3d_scale,1.),"Shadow-buffer refresh restores the viewport's authored internal scale")
	preload("res://scripts/actors/fog/fog_render_settings.gd").apply({}); viewport.queue_free(); await process_frame; await process_frame; print("FOG PERFORMANCE: %d checks, %d failures"%[checks,failures]); quit(failures)
