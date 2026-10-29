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
func click(button: BaseButton) -> void:
	var point:=button.get_global_transform_with_canvas()*(button.size*.5)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; root.push_input(event,true); await process_frame
	await settle()
func run() -> void:
	root.size=Vector2i(1600,1000); root.gui_embed_subwindows=true
	var folder:=ProjectSettings.globalize_path("user://powder_workspace_"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash"))
	var project:=Project.new("Powder verification"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(12)
	var tabs:=get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs; editor=tabs.timeline
	var definition:=editor.registry.get_definition(&"powder")
	var clip:=editor.model.create_actor(definition,0,{&"powder_dimensions":Vector3(.64,.64,.64)})
	clip.duration=2; clip.start_time=0; var actor:=editor.model.selected_actor(); editor.model.changed.emit(); await settle()
	var lens:=editor.runtime_holder.get_viewport().get_camera_3d(); lens.global_position=Vector3(1.5,1.2,2); lens.look_at(Vector3.ZERO)
	editor.inspector.select_main_tab("Properties"); editor.inspector.select_section("Powder"); await settle()
	check(editor.inspector.find_child("PowderStatus",true,false)!=null and editor.inspector.find_child("powder_simulate",true,false)!=null,"Full Scene workspace exposes Powder source status and simulation switch")
	check((editor.inspector.find_child("PowderStatus",true,false) as Label).text.begins_with("64 grains"),"Paused inspector status displays the generated grain count without reselecting")
	await click(editor.inspector.find_child("powder_simulate",true,false) as BaseButton)
	check(not actor.values.powder_simulate,"Actual mouse input toggles source-only preview in the native inspector")
	await click(editor.inspector.find_child("powder_simulate",true,false) as BaseButton)
	check(actor.values.powder_simulate,"Actual mouse input re-enables granular simulation")
	editor.inspector.select_main_tab("Actor"); editor.inspector.select_section("Physics"); await settle()
	check(editor.inspector.find_child("Physics_type",true,false)==null and editor.inspector.find_child("Physics_attachment",true,false)!=null,"Powder has actor/bone source attachment and no ordinary mesh physics type menu")
	editor.inspector.select_main_tab("Properties"); editor.inspector.select_section("Physical Properties"); await settle()
	var friction:=editor.inspector.find_child("powder_friction",true,false) as DragNumber
	check(friction!=null and friction.is_visible_in_tree(),"Compact physical-properties page uses the existing draggable numeric inspector")
	check(not definition.find_property(&"powder_radius").can_keyframe() and definition.find_property(&"powder_friction").can_keyframe(),"Structural radius is explicitly non-keyframable while dynamic material properties support keys")
	var before:=float(actor.values.powder_friction)
	friction.interaction_started.emit(); friction.preview_changed.emit(.3); friction.preview_changed.emit(.9); friction.drag_committed.emit(.9); friction.interaction_ended.emit(); await settle()
	check(is_equal_approx(float(actor.values.powder_friction),.9),"Continuous material edit previews and commits")
	editor.model.undo(); await settle(); check(is_equal_approx(float(actor.values.powder_friction),before),"One undo restores the whole material drag")
	editor.model.redo(); await settle(); check(is_equal_approx(float(actor.values.powder_friction),.9),"Redo restores the whole material drag")
	var effective:=KiwiPowderSettings.effective(actor.values)
	editor.inspector.property_batch.edit(actor,&"powder_advanced_material",true); await settle()
	check(is_equal_approx(float(actor.values.powder_static_friction),float(effective.static_friction)),"Switching to advanced contact controls preserves effective simple-mode friction")
	editor.model.undo(); await settle(); check(not actor.values.powder_advanced_material and is_equal_approx(float(actor.values.powder_friction),.9),"Mode switching is one undoable material edit")
	await seek(.05); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/verification/powder_workspace.png")
	var runtime:=editor._runtime_for_clip(clip.id) as KiwiPowderRuntime
	check(runtime.instance_count()==64 and runtime.grains.get_child_count()==0,"Viewport renders the real grain state in bounded MultiMesh batches, not per-grain nodes")
	var bake_error: String=await editor.physics.bake(editor,actor,0,.25); check(bake_error.is_empty(),"Native workspace can bake powder through existing physics actions")
	editor.set_video_duration(.25)
	var rendered:=[]; var paths:=[folder.path_join("Powder A.mp4"),folder.path_join("Powder B.mp4")]
	for pass_index in 2:
		await seek(.8 if pass_index==0 else .1)
		var frames:=[]
		var progress:=func(_frame: int,_total: int,stage: String):
			if stage=="Rendering": frames.append(editor.physics.display_states[actor.id].points.duplicate())
		var error: String=await ActorSceneExporter.render(editor,paths[pass_index],192,108,12,progress)
		check(error.is_empty() and FileAccess.file_exists(paths[pass_index]),"Powder scene-video pass %d renders through the normal viewport"%(pass_index+1)); rendered.append(frames)
	check(not rendered[0].is_empty() and rendered[0]==rendered[1],"Baked powder video samples are independent of prior seeks")
	for path: String in paths: DirAccess.remove_absolute(path)
	var scene:=editor.capture_scene_data(); var path:=folder.path_join("Powder.tres"); ResourceSaver.save(scene,path)
	await seek(.2); var saved: PackedVector3Array=editor.physics.display_states[actor.id].points.duplicate()
	editor.restore_scene_data(ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)); await settle(); await seek(.2)
	check(editor.physics.display_states[actor.id].points==saved,"Reopening the saved scene reconstructs the same baked viewport state")
	main.queue_free(); await settle()
	print("POWDER WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
