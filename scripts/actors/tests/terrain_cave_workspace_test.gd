extends "res://scripts/actors/tests/surface_growth_test.gd"
const Workspace=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
func run() -> void:
	root.size=Vector2i(1440,900); var folder:=ProjectSettings.globalize_path("user://terrain-cave-workspace"); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash")); var project:=Project.new("Cave workspace"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var document:=KiwiEnvironmentDocument.new(); var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=33; terrain.dimensions=Vector2(16,16); var item:=document.add_terrain(terrain); var workspace:=Workspace.new(); root.add_child(workspace); workspace.open_source(document); workspace.session.select(item.id)
	for i in 5: await process_frame
	workspace._add_cave(1); check(workspace._generation_jobs.size()==1 and workspace.session.environment().terrain(item.id).caves.is_empty(),"Adding a tunnel starts worker generation without committing unfinished cave fields")
	await drain(workspace)
	terrain=workspace.session.environment().terrain(item.id); check(terrain.caves.size()==1 and terrain.volumes_valid(),"Completed cave creation commits its editable source and native geometry together")
	for i in 8: await process_frame
	workspace.canvas.frame(true); var original_cave:=terrain.caves[0]; workspace._refresh_properties(); var old:=original_cave.paths[0][2]; var screen: Vector2=workspace.canvas.project(old); var down:=InputEventMouseButton.new(); down.button_index=MOUSE_BUTTON_LEFT; down.pressed=true; down.position=screen; workspace.canvas._gui_input(down)
	check(not workspace.canvas.cave_tool._drag.is_empty(),"Clicking a visible cave point begins its viewport handle drag")
	var motion:=InputEventMouseMotion.new(); motion.position=screen+Vector2(25,0); motion.relative=Vector2(25,0); motion.button_mask=MOUSE_BUTTON_MASK_LEFT; workspace.canvas._gui_input(motion); var expected: Vector3=workspace.canvas.cave_tool._drag.get("position",old)
	check(expected.distance_to(old)>.05 and original_cave.paths[0][2]==old,"Cave handle movement previews a private point without changing its authored source mid-drag")
	var up:=down.duplicate(); up.pressed=false; up.position=motion.position; workspace.canvas._gui_input(up); await drain(workspace)
	check(workspace.session.environment().terrain(item.id).caves[0].paths[0][2].distance_to(expected)<.00001,"Releasing a cave handle commits its new saved position through an undoable generation action")
	workspace.session.undo(); for i in 5: await process_frame
	check(workspace.session.environment().terrain(item.id).caves[0].paths[0][2]==old,"Undo restores the previous cave path and generated data")
	workspace.session.redo(); for i in 5: await process_frame
	var state:=workspace.capture_state(); check(state.cave_view.cutaway and state.cave_view.id==original_cave.cave_id,"Workspace state preserves its selected cave and preview cutaway")
	var path:=folder.path_join("Cave.tres"); check(await workspace.save_to(path)==OK,"Cave workspace saves valid generated data with its editable source")
	var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument; check(reopened.terrain(item.id).volumes_valid(),"Reopened cave workspace needs no synchronous voxel regeneration")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://.godot/verification/terrain_cave_workspace.png")
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("TERRAIN CAVE WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
func drain(workspace: Control) -> void:
	var deadline:=Time.get_ticks_msec()+20000
	while not workspace._generation_jobs.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(workspace._generation_jobs.is_empty(),"Cave generation finishes within the bounded test window")
