extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var model:=KiwiModelSession.new(); model.add("Box"); var path:="user://environment-async-tree.tres"; ResourceSaver.save(model.document,path)
	var document:=KiwiEnvironmentDocument.new(); var terrain:=document.add_terrain(); var layer:=document.add_group("Forest"); layer.parent_id=terrain.id; var rules:=KiwiEnvironmentScatter.new(); rules.terrain_id=terrain.id; rules.palette=[{"source":path,"weight":1.}]; rules.region=Rect2(-15,-15,30,30); rules.density=5.; rules.minimum_distance=.3; rules.budget=2000; document.component_settings[layer.id]={"kind":"scatter","scatter":rules}
	var runtime:=KiwiEnvironmentRuntime.new(); runtime.progressive=true; root.add_child(runtime); runtime.configure(document)
	check(runtime.scatter_jobs.size()==1 and runtime.instances==0,"Large preview scatter starts a worker without creating partial instances")
	await drain(runtime)
	check(runtime.instances==2000 and runtime.nodes[layer.id].get_child_count()==1,"Completed worker output becomes a native batch with the full requested count")
	var expected:=rules.generate(document.terrain(terrain.id)); var batch:=runtime.nodes[layer.id].get_child(0) as MultiMeshInstance3D
	check(batch.multimesh.get_instance_transform(0).is_equal_approx(expected.batches[0][0]),"Background generation preserves deterministic synchronous placement results")
	rules.seed=99; runtime.sync(); runtime.cancel_scatter_generation(); await process_frame; check(runtime.scatter_jobs.is_empty() and runtime.instances==2000,"Canceling scatter retains the previous completed preview")
	rules.seed=100; runtime.sync(); var other:=KiwiEnvironmentDocument.new(); other.add_terrain(); runtime.configure(other); await drain(runtime)
	check(not runtime.nodes.has(layer.id) and runtime.instances==0,"Old scatter workers cannot add instances after switching documents")
	runtime.queue_free(); await process_frame; model._undo.clear(); model._redo.clear(); DirAccess.remove_absolute(path); print("ENVIRONMENT SCATTER ASYNC: %d checks, %d failures"%[checks,failures]); quit(failures)
func drain(runtime: KiwiEnvironmentRuntime) -> void:
	var deadline:=Time.get_ticks_msec()+20000
	while not runtime.scatter_jobs.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(runtime.scatter_jobs.is_empty(),"Scatter worker completes within the bounded test window")
