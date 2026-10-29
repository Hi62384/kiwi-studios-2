extends "res://scripts/actors/tests/powder_material_workspace_test.gd"
func seek(time: float) -> void:
	editor.canvas.playhead=time; editor._evaluate_runtimes()
	while editor.physics.pending: await process_frame; editor._evaluate_runtimes()
func run() -> void:
	root.size=Vector2i(1600,1000); root.gui_embed_subwindows=true
	var folder:=ProjectSettings.globalize_path("user://directed_ui_"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash")); var project:=Project.new("Directed destruction"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(12); editor=(get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs).timeline
	var clip:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0,{&"destruction_enabled":true,&"position":Vector3(0,1,0)}); clip.start_time=0; clip.duration=2; var actor:=editor.model.selected_actor(); actor.values.physics={"enabled":true,"gravity":0.0}; var cut:=KiwiDestructionDefinition.operation(0,.1); KiwiDestructionDefinition.edit(editor.model,actor,{"cut":cut}); editor.inspector.select_main_tab("Properties"); editor.inspector.select_section("Destruction"); await settle(8)
	var preview:=editor.inspector.find_child("PreviewFracturePattern",true,false) as CheckButton; check(preview!=null,"Native destruction section offers an intact fracture-pattern preview"); editor.inspector.content_scroll.ensure_control_visible(preview); await settle(); await click(preview); check(actor.get_meta("damage_pattern_preview",false),"Preview toggles the editor-only fracture boundary overlay")
	var duplicate:=editor.inspector.find_child("DamageDuplicate",true,false) as Button; editor.inspector.content_scroll.ensure_control_visible(duplicate); await settle(); await click(duplicate); check(actor.values.destruction_operations.size()==2,"Native operation duplication preserves an editable stack"); editor.model.undo(); await settle()
	await seek(.3); await settle(); var button: Button
	for candidate in editor.inspector.find_children("*","Button",true,false):
		if candidate.text=="Direct fragments…": button=candidate; break
	check(button!=null,"Fragment direction is reachable from the same compact inspector"); editor.inspector.content_scroll.ensure_control_visible(button); await settle(); await click(button)
	var dialog:=editor.inspector.find_child("FragmentDirector",true,false) as AcceptDialog; check(dialog!=null and dialog.visible,"Native fragment director opens after fracture")
	if dialog!=null:
		var list:=dialog.find_child("FragmentList",true,false) as ItemList; list.select(0); list.multi_selected.emit(0,true); await settle()
		var input:=dialog.find_child("Fragment_strength_0",true,false) as DragNumber; input.interaction_started.emit(); input.drag_committed.emit(40)
		var id: String=list.get_item_metadata(0); check(actor.values.destruction_fragments[id].strength==40,"A native fragment edit writes real guidance settings"); editor.model.undo(); await settle(); check(not actor.values.destruction_fragments.has(id),"Fragment numeric gesture commits one undoable action"); dialog.hide(); dialog.queue_free(); await settle()
	var error:=await editor.physics.bake_group(editor,0,.5,60); check(error.is_empty(),"Native scene bakes topology and interacting physics into compressed chunks")
	await seek(.3); var fragment_id:=KiwiDestructionAuthoring.fragment_key(actor.id,editor.physics.display_states[actor.id].destruction_fragments[0].id); KiwiDestructionAuthoring.edit_fragments(editor.model,actor,&"destruction_overrides",[fragment_id],"offset",Vector3(0,.3,0)); editor.set_video_duration(.5)
	var captures:=[]; var paths:=[folder.path_join("directed 12.mp4"),folder.path_join("directed 24.mp4")]
	for pass_index in 2:
		var frames:=[]; var fps:=12 if pass_index==0 else 24
		var progress:=func(frame: int,_total: int,stage: String):
			if stage=="Rendering" and (pass_index==0 or (frame-1)%2==0):
				var state: Dictionary=editor.physics.display_states[actor.id]; var particles:=[]
				for key: String in editor.physics.vfx.nodes:
					var node: MultiMeshInstance3D=editor.physics.vfx.nodes[key]
					if node.visible: particles.append([key,hash(node.multimesh.buffer)])
				frames.append([state.get("destruction_fragments",[]).map(func(part: Dictionary): return [part.id,part.pose]),state.get("destruction_events",[]).duplicate(true),particles])
		error=await ActorSceneExporter.render(editor,paths[pass_index],192,108,fps,progress); check(error.is_empty(),"Post-bake corrected destruction renders a real %d fps scene video"%fps); captures.append(frames)
	check(not captures[0].is_empty() and captures[0]==captures[1],"Baked topology, corrected fragment transforms and VFX buffers match across export rates")
	for path: String in paths: DirAccess.remove_absolute(path)
	editor.physics.dispose(); editor.model.history.clear_history(); main.queue_free(); await settle(); print("DESTRUCTION AUTHORING UI: %d checks, %d failures"%[checks,failures]); quit(failures)
