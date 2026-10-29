extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	if DisplayServer.get_name()=="headless": push_error("GPU benchmark requires a native renderer."); quit(1); return
	var session:=KiwiModelSession.new(); session.add("Plane",{"size":Vector3(2,1,2)}); KiwiSurfaceGrowth.add(session,1); var component:=session.primary(); component.growth.settings.density=1000.; component.growth.settings.quality=1; component.growth.rendering.automatic_lod=false; session.document.prepare_growth()
	var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport); var camera:=Camera3D.new(); viewport.add_child(camera); camera.position=Vector3(0,1,3); camera.look_at(Vector3.ZERO); camera.current=true
	var instance:=KiwiSurfaceGrowthInstance.new(); viewport.add_child(instance); instance.configure(component,true)
	var curve:=PackedVector3Array(); var delta:=PackedVector3Array()
	for i in 9: curve.append(Vector3(0,float(i)/8.*.12,0)); delta.append(Vector3.ZERO)
	instance.data.motion_guides={"g":{"points":curve,"delta_points":delta}}; instance.data.motion_binding=3
	for row: Dictionary in instance.data.roots: instance.data.motion_weights[str(row.id)]={"g":1.}
	var start:=Time.get_ticks_usec(); instance.update_growth(); var prepare_ms:=(Time.get_ticks_usec()-start)/1000.; var cached:=instance.mesh; var builds:=instance.data.chunk_builds; var bytes:=instance.gpu.uploaded_bytes; var costs:=[]
	for i in 12:
		delta[8]=Vector3(float(i)*.001,0,0); instance.data.motion_guides.g.delta_points=delta; start=Time.get_ticks_usec(); instance.update_growth(); costs.append((Time.get_ticks_usec()-start)/1000.)
	check(instance.data.roots.size()==8000 and instance.mesh==cached and instance.data.chunk_builds==builds,"Dense guide playback retains all static strand buffers")
	check(instance.gpu.uploaded_bytes-bytes<=12*144,"Steady motion uploads the bounded guide table, not all strand vertices")
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	print("DENSE_GPU roots=",instance.data.roots.size()," guides=1 prepare_ms=",prepare_ms," cpu_upload_update_ms=",costs," steady_uploaded_bytes=",instance.gpu.uploaded_bytes-bytes," chunks=",instance.data.chunks.size()," total_draw_calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," static_memory_bytes=",Performance.get_monitor(Performance.MEMORY_STATIC))
	instance.data.motion_guides={}; instance.data.motion_weights={}; instance.data.motion_binding=4
	for guide in 32: instance.data.motion_guides[str(guide)]={"points":curve,"delta_points":delta.duplicate()}
	for index in instance.data.roots.size(): instance.data.motion_weights[str(instance.data.roots[index].id)]={str(index*32/instance.data.roots.size()):1.}
	instance.update_growth(); var retained:=instance.mesh; var many_costs:=[]; var frame_times:=[]; var last:=Time.get_ticks_usec()
	if RenderingServer.has_method("viewport_set_measure_render_time"): RenderingServer.call("viewport_set_measure_render_time",viewport.get_viewport_rid(),true)
	for frame in 30:
		for guide in 32:
			var values: PackedVector3Array=instance.data.motion_guides[str(guide)].delta_points; values[8]=Vector3(sin(float(frame)*.1+guide)*.01,0,0); instance.data.motion_guides[str(guide)].delta_points=values
		start=Time.get_ticks_usec(); instance.update_growth(); many_costs.append((Time.get_ticks_usec()-start)/1000.); await process_frame; var now:=Time.get_ticks_usec(); frame_times.append((now-last)/1000.); last=now
	await RenderingServer.frame_post_draw
	var gpu_time: Variant="unavailable"; var cpu_time: Variant="unavailable"
	if RenderingServer.has_method("viewport_get_measured_render_time_gpu"):
		var measured: float=RenderingServer.call("viewport_get_measured_render_time_gpu",viewport.get_viewport_rid())
		if measured>0.: gpu_time=measured
	if RenderingServer.has_method("viewport_get_measured_render_time_cpu"):
		var measured: float=RenderingServer.call("viewport_get_measured_render_time_cpu",viewport.get_viewport_rid())
		if measured>0.: cpu_time=measured
	check(instance.mesh==retained,"Many-guide deformation retains static strand buffers over animated frames")
	print("DENSE_GPU_MULTI guides=32 update_ms=",many_costs," observed_frame_ms=",frame_times," measured_render_cpu_ms=",cpu_time," measured_render_gpu_ms=",gpu_time)
	viewport.queue_free(); await process_frame; await process_frame; print("GPU PERFORMANCE: %d checks, %d failures"%[checks,failures]); quit(failures)
