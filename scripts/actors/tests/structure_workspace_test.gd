extends "res://scripts/actors/tests/powder_material_workspace_test.gd"
func run() -> void:
	root.size=Vector2i(1600,1000); root.gui_embed_subwindows=true
	var folder:=ProjectSettings.globalize_path("user://structure_ui_"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash")); var project:=Project.new("Structure verification"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(12); editor=(get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs).timeline
	var clip:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0,{&"position":Vector3(-1,1,0),&"structure_enabled":true,&"structure_role":1}); clip.start_time=0; clip.duration=3; var support:=editor.model.selected_actor()
	clip=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0,{&"position":Vector3(1,1,0)}); clip.start_time=0; clip.duration=3; clip.layer=1; var beam:=editor.model.selected_actor()
	editor.model.select(editor.model.clip_for_actor_id(support.id).id); editor.inspector.select_main_tab("Properties"); editor.inspector.select_section("Structure"); await settle(8)
	var button:=editor.inspector.find_child("ConnectStructure",true,false) as Button; check(button!=null and not button.disabled,"The running Scene Workspace provides explicit joint creation in the Structure section")
	await click(button); var key: String=support.values.structure_connections.keys()[0]
	check(support.values.structure_connections[key].target==beam.id and beam.values.structure_enabled,"A real inspector click creates a stable connection and enables both structural elements")
	editor.model.undo(); await settle(); check(support.values.structure_connections.is_empty() and not beam.values.structure_enabled,"Undo restores both elements before connection creation")
	editor.model.redo(); await settle(); var viewport_button:=editor.inspector.find_child("StructuralViewport",true,false) as Button; editor.inspector.content_scroll.ensure_control_visible(viewport_button); await settle(); await click(viewport_button)
	check(support.get_meta("structure_tool",false),"Viewport joint editing is activated through the native inspector")
	var path:=PackedStringArray(["structure_connections",key,"strength"]); editor.canvas.playhead=0; editor.model.playhead_time=0; editor.model.add_keyframe(support,path,"Joint strength",1.0); editor.canvas.playhead=.3; editor._evaluate_runtimes(); await settle()
	var strength:=editor.inspector.find_child("Structure_strength",true,false) as DragNumber; strength.interaction_started.emit(); strength.preview_changed.emit(.8); strength.drag_committed.emit(.8)
	check(support.animation_track(path).keys.size()==2 and support.values.structure_connections[key].strength==1.0,"Inspector strength dragging inserts keyframes without overwriting authored defaults")
	editor.model.undo(); await settle(); check(support.animation_track(path).keys.size()==1,"An inspector strength gesture occupies one undo entry")
	var lens:=editor.runtime_holder.get_viewport().get_camera_3d(); lens.global_position=Vector3(2,2.4,5); lens.look_at(Vector3(0,1,0)); await settle()
	var gizmo:=editor.viewport_gizmo; var runtime:=editor._runtime_for_clip(editor.model.clip_for_actor_id(support.id).id); var point: Vector3=runtime.remote_transform()*support.values.structure_connections[key].pivot; var screen: Vector2=gizmo.spatial.project(point)
	for pressed in [true,false]:
		var mouse:=InputEventMouseButton.new(); mouse.button_index=MOUSE_BUTTON_LEFT; mouse.pressed=pressed; mouse.position=gizmo.get_global_transform_with_canvas()*(screen+(Vector2(35,10) if not pressed else Vector2.ZERO)); mouse.global_position=mouse.position; root.push_input(mouse,true)
		if pressed:
			var motion:=InputEventMouseMotion.new(); motion.button_mask=MOUSE_BUTTON_MASK_LEFT; motion.position=gizmo.get_global_transform_with_canvas()*(screen+Vector2(35,10)); motion.global_position=motion.position; root.push_input(motion,true)
	await settle(); check(support.values.structure_connections[key].pivot!=Vector3.RIGHT,"Dragging a visible joint endpoint edits its local attachment point")
	await RenderingServer.frame_post_draw; check(root.get_texture().get_image().save_png("res://.godot/verification/structure_workspace.png")==OK,"Native connection/load overlay screenshot is captured")
	# A short scene-video check, not an application export.
	var cut:=KiwiDestructionDefinition.operation(0,.12); cut.impulse=.2; beam.values.destruction_enabled=true; beam.values.physics={"enabled":true,"gravity":0.0}; KiwiDestructionDefinition.edit(editor.model,beam,{"cut":cut}); editor.set_video_duration(.5)
	var captures:=[]; var paths:=[folder.path_join("12 fps.mp4"),folder.path_join("24 fps.mp4")]
	for pass_index in 2:
		var frames:=[]; var fps:=12 if pass_index==0 else 24
		var progress:=func(frame: int,_total: int,stage: String):
			if stage=="Rendering" and (pass_index==0 or (frame-1)%2==0):
				var signatures:=[]; var keys:=editor.physics.vfx.nodes.keys(); keys.sort()
				for effect_key: String in keys:
					var node: MultiMeshInstance3D=editor.physics.vfx.nodes[effect_key]
					if node.visible: signatures.append([effect_key,node.multimesh.instance_count,hash(node.multimesh.buffer)])
				var state: Dictionary=editor.physics.display_states[beam.id]; frames.append([state.get("destruction_events",[]).duplicate(true),state.get("destruction_fragments",[]).map(func(part: Dictionary): return [part.id,part.pose]),signatures])
		var error:=await ActorSceneExporter.render(editor,paths[pass_index],192,108,fps,progress)
		check(error.is_empty() and FileAccess.file_exists(paths[pass_index]),"Native scene video renders debris/effects at %d fps"%fps); captures.append(frames)
	check(not captures[0].is_empty() and captures[0]==captures[1],"Corresponding export frames have identical physical transforms and event timing at different FPS")
	for output_path: String in paths: DirAccess.remove_absolute(output_path)
	editor.physics.dispose(); editor.model.history.clear_history(); main.queue_free(); await settle(3)
	print("STRUCTURE WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
