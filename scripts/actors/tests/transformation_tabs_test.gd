extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func settle() -> void:
	for i in 8: await process_frame
func run() -> void:
	root.size=Vector2i(1440,1000); root.gui_embed_subwindows=true
	var folder := ProjectSettings.globalize_path("user://transformation_project_"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash"))
	var project := Project.new("Transformation verification"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle()
	var tabs := get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs
	tabs.new_transformation(); await settle(); var workspace := tabs.transformation_workspace; var initial := workspace.session
	check(workspace.is_visible_in_tree() and tabs.documents.back().type=="transformation" and not tabs.scene_workspace.visible,"New Transformation tab opens in the real application")
	check(initial.document.components.size()==1 and initial.document.components[0].states.size()==1,"New tab starts with an editable blank drawing state")
	workspace.open_example("Layered face"); await settle(); var face := workspace.session; var index := tabs._active_index
	check(face.document.components.size()==6 and face.document.components[3].states.size()==4,"Worked face opens in another tab with independent eye, mouth and brow states")
	face.selected.assign([face.document.components[3].id]); face.edit_states[face.primary().id]=face.primary().states[2].id; workspace.edit_mode(); await settle()
	workspace.canvas.zoom=1.75; workspace.canvas.pan=Vector2(20,-33); workspace.timeline.offset=27.; workspace.timeline.pixels_per_second=225.
	face.action("Edit mouth position",func(): face.active_state().artwork.position.x+=9)
	var first := folder.path_join("Face.tres"); check(await workspace.save_to(first)==OK,"Native animated document saves in the project filesystem")
	check(tabs.documents[index].path==first and not tabs.documents[index].dirty,"Saving updates the real tab path and dirty indicator")
	var thumbnail: Texture2D=await FileOperations.get_file_thumbnail(first)
	check(thumbnail!=null and thumbnail.get_width()<=192,"Project filesystem creates a distinctive native asset thumbnail")
	var count := tabs.documents.size(); tabs._filesystem_resource_opened(first); await settle()
	check(tabs.documents.size()==count and workspace.session==face,"Double-clicking the saved asset reuses its existing tab")
	var second := folder.path_join("Face Copy.res"); check(await workspace.save_to(second)==OK,"Save As also writes the native binary resource format")
	face.action("Edit independent copy",func(): face.active_state().artwork.opacity=.4); await workspace.save()
	var original := KiwiTransformationWorkspace.resolve(first).document as KiwiTransformationImage2D
	check(is_equal_approx(original.components[3].states[2].artwork.opacity,1.),"Saving an independent copy never overwrites the original file")
	tabs._capture_current(); tabs._open_index(1); await settle()
	check(workspace.session==initial and initial.document.components.size()==1,"Multiple Transformation tabs retain separate unsaved documents")
	tabs._capture_current(); tabs._open_index(index); await settle()
	check(workspace.session==face and workspace.canvas.pan==Vector2(20,-33) and is_equal_approx(workspace.canvas.zoom,1.75),"Returning to the document preserves canvas pan, zoom and the edit session")
	check(is_equal_approx(workspace.timeline.pixels_per_second,225.) and is_equal_approx(workspace.timeline.offset,27.),"Tab switching preserves timeline view state")
	var selected_state := face.active_state().id; tabs.close_scene(index); await settle()
	check(tabs.documents.size()==count-1,"A saved Transformation tab closes without discarding a different document")
	tabs._filesystem_resource_opened(second); await settle(); face=workspace.session
	check(face.document.validate().is_empty() and face.primary().states.size()==4 and face.active_state().id==selected_state,"Reopening restores every state and the chosen state definition")
	check(face.document.components[1].keys.size()==5 and face.document.components[2].keys.size()==5 and face.primary().keys.size()==5,"Independent simultaneous component animation survives a full close/reopen")
	var position := face.active_state().artwork.position
	face.action("Reopened artwork edit",func(): face.active_state().artwork.position+=Vector2(5,3)); face.undo()
	check(face.active_state().artwork.position==position,"Reopened native drawings remain independently editable and undoable")
	var bad := face.document.snapshot(); bad.components[0].default_state_id="missing"; var current := workspace.session
	check(not tabs.open_transformation(bad) and workspace.session==current,"Invalid native data reports an error without replacing the current document")
	var error_popup := tabs.get_node_or_null("TransformationOpenError") as AcceptDialog
	check(error_popup!=null and error_popup.visible,"Invalid files display a visible explanation instead of failing silently")
	if error_popup!=null: error_popup.queue_free(); await settle()
	tabs.new_image(); await settle(); check(tabs.image_workspace.visible and not workspace.visible,"Image workspace stays isolated from the Transformation renderers")
	tabs.new_shader(); await settle(); check(tabs.shader_workspace.visible and not workspace.visible,"Shader workspace stays isolated from Transformation artwork")
	tabs._capture_current(); tabs._open_index(0); await settle(); check(tabs.scene_workspace.visible and not workspace.visible,"Original scene returns without artwork or preview bleeding into it")
	tabs._capture_current(); tabs._open_index(1); await settle(); tabs.close_scene(1); await settle()
	var confirmation: ConfirmationDialog
	for child in tabs.get_children():
		if child is ConfirmationDialog and child.title=="Unsaved Transformation Image": confirmation=child
	check(confirmation!=null and confirmation.visible,"Unsaved Transformation documents have an explicit save/discard/cancel confirmation")
	if confirmation!=null: confirmation.canceled.emit(); confirmation.hide()
	tabs._capture_current(); tabs._open_index(2); await settle(); workspace.canvas.fit(); workspace.seek(1.1); await settle()
	for i in 240:
		if workspace.animation_renderer.cache.worker==null and workspace.animation_renderer.cache.requests.is_empty(): break
		await process_frame
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/verification/transformation_full_application.png")
	main.queue_free(); await settle(); StaticData.loaded_project=null
	print("TRANSFORMATION_TABS checks=%d failures=%d"%[checks,failures]); quit(failures)
