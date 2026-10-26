extends SceneTree
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,message:String)->void:
	if not value:failures+=1;push_error(message)
	print("PASS " if value else "FAIL ",message)
func shot(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	var directory:=ProjectSettings.globalize_path("user://handoff_screenshots");DirAccess.make_dir_recursive_absolute(directory)
	check(root.get_texture().get_image().save_png(directory.path_join(label+".png"))==OK,"Native screenshot: "+label)
func run()->void:
	root.size=Vector2i(1440,1000);root.gui_embed_subwindows=true
	var project_path:="user://handoff_project_"+ActorData.new_id();DirAccess.make_dir_recursive_absolute(project_path.path_join(".proj/.trash"))
	var project:=Project.new("Handoff verification");check(ResourceSaver.save(project,project_path.path_join(".proj/Project.tres"))==OK,"Isolated project fixture saves")
	project.take_over_path(ProjectSettings.globalize_path(project_path.path_join(".proj/Project.tres")))
	StaticData.loaded_project=project
	var main:Node=load("res://scenes/Main.tscn").instantiate();root.add_child(main)
	for i in 10:await process_frame
	var tabs:=get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs
	check(tabs!=null and tabs.timeline!=null and tabs.documents.size()>0,"Full application initializes scene tabs")
	var owned_histories:Array[int]=[tabs.timeline.model.history.get_instance_id()]
	if tabs==null or tabs.timeline==null:quit(1);return
	await shot("scene_workspace")
	tabs.new_audio();await process_frame
	check(tabs.audio_workspace.visible and not tabs.scene_workspace.visible,"Actual application opens Audio tab")
	var audio:KiwiAudioWorkspace=tabs.audio_workspace
	owned_histories.append(audio.session.history.get_instance_id());owned_histories.append(audio.playback.model.history.get_instance_id())
	var source:=PackedVector2Array();source.resize(4800);source.fill(Vector2(.1,.1))
	audio.session.insert_source(KiwiAudioSourceCache.to_wav(source,48000),0,audio.session.selected_track,"Fixture")
	audio.modulation_matrix_dialog();await process_frame
	for child in audio.get_children():
		if child is Window:child.queue_free()
	await shot("audio_workspace")
	tabs.new_shader();for i in 8:await process_frame
	check(tabs.shader_workspace.visible and not tabs.audio_workspace.visible,"Actual application switches to independent Shader tab")
	await shot("shader_workspace")
	var catalog:=preload("res://Workspaces/ShaderWorkspace/library/shader_sample_catalog.gd")
	check(catalog.get_entries().size()==162 and catalog.get_code(catalog.get_entries()[0]).contains("shader_type"),"Complete shader sources remain available in runtime/export")
	tabs.new_image();for i in 4:await process_frame
	check(tabs.image_workspace.visible and not tabs.shader_workspace.visible,"Actual application switches to Image tab")
	await shot("image_workspace")
	tabs._capture_current();tabs._open_index(0);for i in 3:await process_frame
	check(tabs.scene_workspace.visible and not tabs.image_workspace.visible,"Returning to original scene restores workspace isolation")
	owned_histories.append(tabs.timeline.model.history.get_instance_id())
	project.actor_inspector_state.set_scroll("save-on-close-fixture",42.)
	tabs.timeline._schedule_ui_state_save()
	main.queue_free();await process_frame;await process_frame
	var persisted:Project=ResourceLoader.load(project_path.path_join(".proj/Project.tres"),"",ResourceLoader.CACHE_MODE_IGNORE)
	check(persisted!=null and persisted.actor_inspector_state.scroll_for("save-on-close-fixture")==42.,"Closing the workspace flushes pending inspector state to its original project")
	persisted=null
	StaticData.loaded_project=null;project=null
	for id in owned_histories:check(not is_instance_id_valid(id),"Workspace releases owned undo history %d"%id)
	print("APPLICATION_HANDOFF_SMOKE failures=%d renderer=%s"%[failures,DisplayServer.get_name()]);quit(failures)
