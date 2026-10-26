extends SceneTree
var checks:=0
var failures:=0
var editor: ActorTimelineEditor
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func settle(count: int=5) -> void:
	for i in count: await process_frame
func seek(time: float) -> void:
	editor.canvas.playhead=time; editor._evaluate_runtimes()
	while editor.physics.pending: await process_frame; editor._evaluate_runtimes()
func click(button: Button) -> void:
	var point:=button.get_global_transform_with_canvas()*(button.size/2)
	await click_point(point)
func click_point(point: Vector2) -> void:
	var motion:=InputEventMouseMotion.new(); motion.position=point; motion.global_position=point; root.push_input(motion,true)
	var event:=InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; root.push_input(event,true)
	await process_frame
	event=event.duplicate(); event.pressed=false; root.push_input(event,true); await settle()
func run() -> void:
	root.size=Vector2i(1600,1000); root.gui_embed_subwindows=true
	var folder:=ProjectSettings.globalize_path("user://physics_workspace_"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash"))
	var project:=Project.new("Physics verification"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(12)
	var tabs:=get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs; editor=tabs.timeline
	var floor_clip:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0,{&"position":Vector3(0,-.5,0),&"box_size":Vector3(10,1,10)})
	floor_clip.duration=3
	var floor_actor:=editor.model.selected_actor(); floor_actor.values[&"physics"]={"enabled":true,"body_mode":1}
	var clip:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0,{&"position":Vector3(0,3,0)})
	clip.start_time=0; clip.layer=1; clip.duration=3; var actor:=editor.model.selected_actor(); editor.model.changed.emit(); await settle()
	var lens:=editor.runtime_holder.get_viewport().get_camera_3d(); lens.global_position=Vector3(6,4,8); lens.look_at(Vector3(0,1,0))
	var inspector:=editor.inspector
	check(inspector._sections.has("Actor/Physics"),"3D actors expose Physics inside Actor, not material properties")
	inspector.select_main_tab("Actor"); inspector.select_section("Physics"); await settle()
	check(inspector.find_child("Physics_enabled",true,false)!=null and inspector.find_child("Physics_type",true,false)==null,"Disabled physics shows one compact toggle without unrelated settings")
	await click(inspector.find_child("Physics_enabled",true,false))
	check(KiwiPhysicsSettings.authored(actor).enabled and inspector.find_child("Physics_type",true,false)!=null,"Clicking Physics creates functional settings in the running editor")
	var number:=inspector.find_child("Physics_gravity",true,false) as DragNumber
	check(number!=null and inspector._sections["Actor/Physics"].content.is_visible_in_tree(),"Physics section contains editable contextual controls")
	var old_gravity:=number.value; number._origin=old_gravity; number.dragging=true; number.interaction_started.emit(); number.preview_changed.emit(3.0)
	check(is_equal_approx(KiwiPhysicsSettings.authored(actor).gravity,3.0),"Numeric drag previews update the actual simulation settings")
	number.dragging=false; number.drag_committed.emit(3.0); editor.model.undo(); await settle()
	check(is_equal_approx(KiwiPhysicsSettings.authored(actor).gravity,old_gravity),"A complete numeric drag undoes in one step")
	var category:=inspector.find_child("Category_Physics_Advanced",true,false) as Button
	check(category!=null and not category.button_pressed,"Advanced settings start collapsed")
	category.button_pressed=true; await settle()
	var vector:=inspector.find_child("Physics_velocity_0",true,false) as DragNumber
	vector._origin=0.0; vector.dragging=true; vector.interaction_started.emit(); vector.preview_changed.emit(2.0); vector.dragging=false; vector.drag_committed.emit(2.0)
	check(is_equal_approx(KiwiPhysicsSettings.authored(actor).velocity.x,2.0),"Vector drag gestures edit velocity, not just typed values")
	editor.model.undo(); await settle(); check(KiwiPhysicsSettings.authored(actor).velocity==Vector3.ZERO,"Vector drag changes undo as a single transaction")
	for kind in [1,2,3,4,5,0]:
		var choice:=inspector.find_child("Physics_type",true,false) as OptionButton; choice.select(kind); choice.item_selected.emit(kind); await settle()
		check(int(KiwiPhysicsSettings.authored(actor).type)==kind,"Physics type %s switches through the inspector"%KiwiPhysicsSettings.TYPES[kind])
		if kind==5: check(inspector.find_child("Physics_rope_length",true,false)!=null and inspector.find_child("Physics_bounce",true,false)==null,"Rope settings do not show unrelated rigid-body fields")
	var forces:=inspector.find_child("Category_Physics_Forces and impulses",true,false) as Button
	forces.button_pressed=true; await settle()
	var add_event: Button
	for node in forces.get_parent().find_children("*","Button",true,false):
		if node.text=="＋ Force / impulse event": add_event=node
	check(add_event!=null,"Forces and impulses can be authored without editing code")
	inspector.content_scroll.ensure_control_visible(add_event); await settle()
	await click(add_event); check(KiwiPhysicsSettings.authored(actor).forces.size()==1,"Adding a force event updates the saved actor settings")
	editor.model.undo(); await settle(); check(KiwiPhysicsSettings.authored(actor).forces.is_empty(),"Force event creation is undoable")
	var enabled_key:=inspector.find_child("physics_enabled_keyframe",true,false) as Button
	check(enabled_key!=null,"Physics activation has the same diamond controls as ordinary animation")
	await seek(.5); var before: Transform3D=editor.physics.display_states[actor.id].pose
	editor.playing=true; await settle(15); editor.playing=false; await seek(editor.canvas.playhead)
	check(editor.canvas.playhead>.5 and editor.physics.display_states[actor.id].pose.origin.y<before.origin.y,"Play advances physics through the existing Scene Workspace transport")
	var paused: Transform3D=editor.physics.display_states[actor.id].pose; var count:=editor.physics.steps_taken; await settle(20)
	check(editor.physics.steps_taken==count and editor.physics.display_states[actor.id].pose==paused,"Leaving the full editor paused never advances physics")
	await seek(.4); inspector.scroll_vertical=0; await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/verification/physics_workspace.png")
	if not ActorVideo.executable("ffmpeg").is_empty():
		var cloth_clip:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0,{&"position":Vector3(2,3,0),&"shape":4,&"plane_orientation":2,&"plane_size":Vector2(1.4,1.4),&"plane_subdivide_width":4,&"plane_subdivide_depth":4})
		cloth_clip.start_time=0; cloth_clip.layer=2; cloth_clip.duration=3
		var cloth:=editor.model.selected_actor(); cloth.values[&"physics"]={"enabled":true,"type":4,"pin_region":1,"wind":Vector3(0,0,3),"particles":40}; editor.model.changed.emit()
		await seek(0); cloth.set_meta("editor_physics_pin_mode",true); await settle()
		var gizmo:=editor.viewport_gizmo; var point: Vector3=editor.physics.display_states[cloth.id].points[0]
		check(gizmo.spatial.physics_pins.active(),"Point-pin editing activates on the selected deformable actor")
		await click_point(gizmo.get_global_transform_with_canvas()*gizmo.spatial.project(point))
		check(KiwiPhysicsSettings.authored(cloth).pins.size()==1,"Clicking a viewport simulation point creates a saved pin")
		editor.model.undo(); cloth.set_meta("editor_physics_pin_mode",false); await settle()
		check(KiwiPhysicsSettings.authored(cloth).pins.is_empty(),"Viewport pin creation undoes cleanly")
		var bake_error: String=await editor.physics.bake(editor,cloth,0,1.0)
		check(bake_error.is_empty(),"Cloth deformation can be baked before video rendering")
		editor.set_video_duration(1.0)
		var paths:=[folder.path_join("Physics A.mp4"),folder.path_join("Physics B.mp4")]; var states:=[]; var errors:=[]
		for pass_index in 2:
			await seek(2.0 if pass_index==0 else .1)
			var frames:=[]
			var progress:=func(_frame: int,_total: int,stage: String):
				if stage=="Rendering": frames.append({"pose":editor.physics.display_states[actor.id].pose,"cloth":editor.physics.display_states[cloth.id].points.duplicate()})
			var error: String=await ActorSceneExporter.render(editor,paths[pass_index],192,108,12,progress)
			errors.append(error); states.append(frames)
		check(errors[0].is_empty() and errors[1].is_empty(),"Two short scene videos render and encode successfully (no application export)")
		check(states[0].size()==ceili(editor.video_duration*12) and states[0]==states[1],"Repeated video exports sample identical physics regardless of prior seeks")
		for index in states[0].size():
			await seek(float(index)/12)
			if not (states[0][index].pose as Transform3D).is_equal_approx(editor.physics.display_states[actor.id].pose) or states[0][index].cloth!=editor.physics.display_states[cloth.id].points: failures+=1; push_error("Viewport/export physics mismatch")
		check(FileAccess.file_exists(paths[0]) and FileAccess.get_file_as_bytes(paths[0]).size()>200,"The export produced a real encoded scene video")
		for path: String in paths: DirAccess.remove_absolute(path)
	else:
		check(false,"FFmpeg is available for the required video export test")
	main.queue_free(); await settle(5)
	print("PHYSICS_WORKSPACE checks=%d failures=%d"%[checks,failures]); quit(failures)
