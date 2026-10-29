extends "res://scripts/actors/tests/surface_growth_test.gd"
const Workspace=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
func run() -> void:
	root.size=Vector2i(1280,800); var folder:=ProjectSettings.globalize_path("user://terrain-erosion-workspace"); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash")); var project:=Project.new("Terrain erosion"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var document:=KiwiEnvironmentDocument.new(); var source:=KiwiEnvironmentTerrain.new(); source.amplitude=10.; source.generation=KiwiTerrainGenerator.preset(2); var item:=document.add_terrain(source); var workspace:=Workspace.new(); root.add_child(workspace); check(workspace.open_source(document),"Steep generated terrain opens as a valid editable environment")
	workspace.session.select(item.id); workspace._advanced_generation=true; workspace._refresh_properties()
	for i in 8: await process_frame
	var original:=workspace.session.environment().terrain(item.id)._base.duplicate(); var operation:=KiwiTerrainErosion.new(); operation.mode=1; operation.iterations=12; operation.strength=1.; operation.mobility=1.; operation.mask={"center":Vector2.ZERO,"radius":12.,"falloff":.2}; workspace._expanded_landforms[operation.operation_id]=true
	workspace._edit_erosion(item.id,func(operations: Array[KiwiTerrainErosion]): operations.append(operation))
	check(workspace._generation_jobs.size()==1 and workspace.session.environment().terrain(item.id).erosion.is_empty(),"Erosion edits run in a cancelable worker while keeping the previous authored terrain intact")
	await drain(workspace)
	var terrain:=workspace.session.environment().terrain(item.id)
	check(terrain.erosion.size()==1 and terrain._base!=original and terrain.derived_fields.has(operation.operation_id),"Finished editor erosion commits actual geometry and its derived fields together")
	for i in 8: await process_frame
	var chunk:=workspace.canvas.renderer.nodes[item.id].get_node("Chunk_0_0") as MeshInstance3D
	check(chunk.mesh.get_faces()==chunk.get_node("Collision/Shape").shape.get_faces(),"Eroded native mesh and collision geometry remain consistent")
	workspace.session.undo(); for i in 5: await process_frame
	check(workspace.session.environment().terrain(item.id).erosion.is_empty() and workspace.session.environment().terrain(item.id)._base==original,"Undo restores the original cached procedural terrain without rerunning an erosion job")
	workspace.session.redo(); for i in 5: await process_frame
	terrain=workspace.session.environment().terrain(item.id); check(terrain.erosion.size()==1 and terrain._base!=original,"Redo restores the eroded source and native terrain")
	var cached:=terrain._base.duplicate(); var recreated:=terrain.duplicate(true) as KiwiEnvironmentTerrain; var started:=Time.get_ticks_usec(); recreated.prepare(); var milliseconds:=float(Time.get_ticks_usec()-started)/1000.
	check(recreated._base==cached and recreated.derived_fields.has(operation.operation_id),"Reopened terrain reuses matching bounded CPU generation data and flow fields")
	var path:=folder.path_join("Eroded Terrain.tres"); var error:=await workspace.save_to(path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument; loaded.terrain(item.id).prepare()
	check(error==OK and loaded.terrain(item.id)._base==cached and loaded.terrain(item.id).erosion[0].iterations==12,"Saving and reopening preserves editable erosion operations and matching terrain heights")
	print("TERRAIN CACHE reopen_65x65_ms=",milliseconds," cache_bytes=",KiwiEnvironmentTerrain._base_cache_size)
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("TERRAIN EROSION WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
func drain(workspace: Control) -> void:
	var deadline:=Time.get_ticks_msec()+20000
	while not workspace._generation_jobs.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(workspace._generation_jobs.is_empty(),"Editor terrain job finishes within the bounded test window")
