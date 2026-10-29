extends "res://scripts/actors/tests/surface_growth_test.gd"
const Workspace=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
func run() -> void:
	root.size=Vector2i(1440,900); var folder:=ProjectSettings.globalize_path("user://environment-workspace-test"); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash")); var project:=Project.new("Environment workspace test"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var document:=KiwiEnvironmentDocument.new(); var terrain_item:=document.add_terrain(); var workspace:=Workspace.new(); root.add_child(workspace); workspace.open_source(document)
	for i in 5: await process_frame
	workspace.canvas.frame(true); await process_frame
	check(workspace.canvas.renderer.nodes.size()==1 and workspace.canvas.renderer.chunks_rebuilt==4,"Environment workspace opens a live chunked 3D terrain viewport")
	var hit:=workspace.canvas.pick_terrain(workspace.canvas.project(Vector3.ZERO)); check(not hit.is_empty() and str(hit.id)==terrain_item.id,"Viewport picking finds the actual terrain surface")
	var canvas:=workspace.canvas; canvas.environment_tool="Raise"; var point:=canvas.project(Vector3.ZERO); var down:=InputEventMouseButton.new(); down.button_index=MOUSE_BUTTON_LEFT; down.pressed=true; down.position=point; canvas._gui_input(down); var up:=down.duplicate(); up.pressed=false; canvas._gui_input(up)
	var terrain:=workspace.session.environment().terrain(terrain_item.id)
	check(terrain.sample(Vector2.ZERO).height>0.,"Clicking the terrain with Raise changes real geometry through the workspace tool")
	workspace.session.undo(); check(absf(float(workspace.session.environment().terrain(terrain_item.id).sample(Vector2.ZERO).height))<.00001,"Workspace terrain strokes undo through the shared edit session")
	var state:=workspace.capture_state(); var other:=KiwiEnvironmentDocument.new(); other.add_terrain(); workspace.open_source(other); workspace.open_source(document,state)
	check(workspace.session==state.session and workspace.canvas.camera.position.is_finite(),"Opening another environment and restoring preserves the independent session and camera")
	var path:=folder.path_join("environment.tres"); var saved:=await workspace.save_to(path); check(saved==OK and not workspace.session.dirty,"Saving the workspace writes its complete environment document")
	var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument; check(loaded!=null and loaded.workspace_state.has("view"),"Saved environments retain viewport editing state")
	var picker:=ActorProjectFilePicker.new(); picker.project_root=folder; picker.allowed_extensions=PackedStringArray(["tres","res"]); picker.allowed_native_types=PackedStringArray(["KiwiEnvironmentDocument"]); check(picker._path_allowed(path),"Environment files are accepted by the shared project picker used by Open and actor source properties"); picker.free()
	var model:=KiwiModelSession.new(); model.add("Box"); var model_path:=folder.path_join("Preview Rock.tres"); ResourceSaver.save(model.document,model_path); workspace.library.scan()
	for i in 10: await process_frame
	workspace.library.search.text="Preview Rock"; workspace.library.refresh(); check(workspace.library.list.item_count==1 and str(workspace.library.list.get_item_metadata(0))==model_path,"Project library discovers compatible saved models and filters them by search")
	workspace.canvas.frame(true)
	for i in 5: await process_frame
	var placement_point:=workspace.canvas.project(Vector3.ZERO); var data:={"files":[model_path]}; var before_components:=workspace.session.document.components.size(); var preview:=workspace.canvas._can_drop_data(placement_point,data)
	check(preview and workspace.canvas._drop_preview!=null and workspace.session.document.components.size()==before_components,"Dragging a library model creates a viewport preview without committing an authored component")
	workspace.canvas._clear_preview(); await process_frame; check(workspace.canvas._drop_preview==null and workspace.session.document.components.size()==before_components,"Canceling placement removes its preview without changing the document")
	workspace.canvas._drop_data(placement_point,data); check(workspace.session.document.components.size()==before_components+1,"Dropping the file commits a real terrain-aligned environment asset")
	workspace.session.undo(); check(workspace.session.document.components.size()==before_components,"File placement undoes as one environment action")
	model._undo.clear(); model._redo.clear()
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://.godot/verification/environment_workspace.png")
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("ENVIRONMENT WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
