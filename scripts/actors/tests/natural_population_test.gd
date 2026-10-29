extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var model:=KiwiModelSession.new(); model.add("Plant / Grass",{"branches":5}); var path:="user://population_grass.res"; ResourceSaver.save(model.document,path)
	var document:=KiwiEnvironmentDocument.new(); var terrain:=KiwiEnvironmentTerrain.new(); terrain.dimensions=Vector2(128,128); terrain.amplitude=0.; var ground:=document.add_terrain(terrain)
	var layer:=document.add_group("20000 blades clumps"); layer.parent_id=ground.id; var source:=KiwiEnvironmentScatter.new(); source.terrain_id=ground.id; source.palette=[{"source":path}]; source.budget=20000; source.density=2.; source.minimum_distance=.3; source.region=Rect2(-64,-64,128,128); document.component_settings[layer.id]={"kind":"scatter","scatter":source}
	var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(400,300); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); var camera:=Camera3D.new(); view.add_child(camera); camera.position=Vector3(0,60,70); camera.look_at(Vector3.ZERO); camera.current=true
	var before:=OS.get_static_memory_usage(); var runtime:=KiwiEnvironmentRuntime.new(); view.add_child(runtime); var start:=Time.get_ticks_usec(); runtime.configure(document); var milliseconds:=(Time.get_ticks_usec()-start)/1000.
	var node: Node=runtime.nodes[layer.id]; var batches:=0; var count:=0
	for child in node.get_children():
		if child is MultiMeshInstance3D: batches+=1; count+=child.multimesh.instance_count
	check(count==20000 and batches==1,"Twenty thousand generated grass clumps use one native instance batch")
	check(node.get_child_count()==1,"Decorative population does not create per-instance nodes or collision bodies")
	var initial: Dictionary=node.get_meta("scatter_result"); var poses: Dictionary=initial.placements.duplicate(true); runtime.sync()
	check((node.get_meta("scatter_result") as Dictionary).placements==poses,"Unchanged runtime sync retains stable population")
	var delta:=OS.get_static_memory_usage()-before
	check(milliseconds<10000. and delta<300000000,"Population generation/upload stays within measured CPU time and memory budgets")
	if DisplayServer.get_name()!="headless":
		for i in 6: await RenderingServer.frame_post_draw
		var primitives:=view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		check(primitives>20000,"Native renderer retains actual grass silhouettes at distant LOD")
		print("NATURAL POPULATION native_primitives=",primitives)
	print("NATURAL POPULATION count=",count," batches=",batches," generation_upload_ms=",milliseconds," tracked_cpu_bytes=",delta)
	view.queue_free(); await process_frame; print("NATURAL POPULATION: %d checks, %d failures"%[checks,failures]); quit(failures)
