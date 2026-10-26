extends SceneTree
var checks:=0
var failures:=0
var editor: ActorTimelineEditor
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func settle(count: int=4) -> void:
	for i in count: await process_frame
func seek(time: float) -> void:
	editor.canvas.playhead=time; editor._evaluate_runtimes()
	while editor.physics.pending: await process_frame; editor._evaluate_runtimes()
func run() -> void:
	root.size=Vector2i(1600,1000); root.gui_embed_subwindows=true
	var folder:=ProjectSettings.globalize_path("user://fluid_workspace_"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash"))
	var project:=Project.new("Fluid verification"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(12)
	var tabs:=get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs; editor=tabs.timeline
	var clip:=editor.model.create_actor(editor.registry.get_definition(&"fluid"),0,{&"fluid_dimensions":Vector3(.8,.8,.8),&"fluid_quality":0})
	clip.duration=2; clip.start_time=0; var actor:=editor.model.selected_actor(); editor.model.changed.emit(); await settle()
	var lens:=editor.runtime_holder.get_viewport().get_camera_3d(); lens.global_position=Vector3(2,1.5,3); lens.look_at(Vector3.ZERO)
	editor.inspector.select_main_tab("Properties"); editor.inspector.select_section("Fluid"); await settle()
	check(editor.inspector.find_child("FluidPreset",true,false)!=null,"Running Scene Workspace exposes compact Fluid preset controls")
	editor.inspector.select_main_tab("Actor"); editor.inspector.select_section("Physics"); await settle()
	check(editor.inspector.find_child("Physics_type",true,false)==null and editor.inspector.find_child("Physics_enabled",true,false)!=null,"Fluid has specialized timeline Physics settings, not an unrelated rigid-body type selector")
	await seek(.1); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/verification/fluid_workspace.png")
	editor.set_video_duration(.25)
	var rendered:=[]; var paths:=[folder.path_join("Fluid A.mp4"),folder.path_join("Fluid B.mp4")]
	for pass_index in 2:
		await seek(.8 if pass_index==0 else .1)
		var frames:=[]
		var progress:=func(_frame: int,_total: int,stage: String):
			if stage=="Rendering": frames.append(editor.physics.display_states[actor.id].points.duplicate())
		var error: String=await ActorSceneExporter.render(editor,paths[pass_index],192,108,12,progress)
		check(error.is_empty() and FileAccess.file_exists(paths[pass_index]),"Fluid scene video pass %d renders through the viewport (not an application export)"%(pass_index+1)); rendered.append(frames)
	check(not rendered[0].is_empty() and rendered[0]==rendered[1],"Fluid exports sample the same states regardless of prior scrubbing")
	for path: String in paths: DirAccess.remove_absolute(path)
	main.queue_free(); await settle()
	print("FLUID WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
