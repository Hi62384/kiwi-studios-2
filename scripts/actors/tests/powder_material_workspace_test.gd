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
func click(button: BaseButton) -> void:
	var point:=button.get_global_transform_with_canvas()*(button.size*.5)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new(); event.position=point; event.global_position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; root.push_input(event,true); await process_frame
	await settle()
func run() -> void:
	root.size=Vector2i(1600,1000); root.gui_embed_subwindows=true
	var folder:=ProjectSettings.globalize_path("user://powder_material_ui_"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash"))
	var project:=Project.new("Powder materials"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(12)
	var tabs:=get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs; editor=tabs.timeline
	var actors: Array[ActorData]=[]
	for i in 5:
		var clip:=editor.model.create_actor(editor.registry.get_definition(&"powder"),0,{&"position":Vector3((i-2)*.7,.3,0),&"powder_dimensions":Vector3(.55,.55,.55),&"powder_simulate":false,&"powder_show_source":false}); clip.start_time=0; clip.layer=i; clip.duration=3
		var actor:=editor.model.selected_actor(); actor.display_name=KiwiPowderMaterial.NAMES[i]; actors.append(actor); KiwiPowderMaterial.apply(editor.model,[actor],ActorObjectReference.from_object(KiwiPowderMaterial.preset(i)))
	var lens:=editor.runtime_holder.get_viewport().get_camera_3d(); lens.global_position=Vector3(1.4,1.9,3.8); lens.look_at(Vector3(0,.3,0)); editor.canvas.playhead=0; editor.model.select(editor.model.clip_for_actor_id(actors[0].id).id)
	editor.inspector.select_main_tab("Properties"); editor.inspector.select_section("Appearance"); await settle(8)
	var preset:=editor.inspector.find_child("PowderPreset",true,false) as OptionButton; var apply:=editor.inspector.find_child("ApplyPowderPreset",true,false) as Button
	check(preset!=null and preset.item_count==7 and preset.get_item_icon(0)!=null,"Native Powder inspector exposes all seven recipes with thumbnails")
	check(apply!=null and apply.get_global_rect().end.x<=editor.inspector.get_global_rect().end.x+2,"Preset controls fit the existing inspector width")
	preset.select(5); await click(apply)
	check(ActorAnimation.resolve_reference(actors[0].values.powder_material).values.material_name=="Salt","A real inspector click applies the selected recipe")
	editor.model.undo(); await settle(); check(ActorAnimation.resolve_reference(actors[0].values.powder_material).values.material_name=="Sand","The preset button commits exactly one undoable change")
	for actor in actors:
		var runtime:=editor._runtime_for_clip(editor.model.clip_for_actor_id(actor.id).id) as KiwiPowderRuntime
		check(runtime.instance_count()>0 and runtime.batches.size()<=8 and runtime.grain_material!=null,actor.display_name+" appears through bounded instanced batches")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.godot/verification/powder_material_workspace.png")==OK,"Native material-gallery screenshot is captured")
	var clip:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0,{&"position":Vector3(0,1.5,0)}); clip.start_time=0; clip.layer=6
	var actor:=editor.model.selected_actor(); editor.inspector.select_main_tab("Properties"); editor.inspector.select_section("Destruction"); await settle()
	await click(editor.inspector.find_child("destruction_enabled",true,false) as BaseButton)
	check(actor.values.destruction_enabled and editor.inspector.find_child("DamageMaterialPreset",true,false)!=null,"Destruction enables on an ordinary mesh using the existing inspector")
	var material_preset:=editor.inspector.find_child("DamageMaterialPreset",true,false) as OptionButton; material_preset.select(3); await click(editor.inspector.find_child("ApplyDamageMaterial",true,false) as BaseButton)
	check(ActorAnimation.resolve_reference(actor.values.destruction_material).values.material_name=="Wood","Native damage-material selector applies reusable physical material data")
	await click(editor.inspector.find_child("AddDamageOperation",true,false) as BaseButton)
	check(actor.values.destruction_operations.size()==1,"Native operation editor adds a real non-destructive damage operation")
	var button:=editor.inspector.find_child("DamageViewportHandle",true,false) as BaseButton
	await click(button); check(actor.get_meta("damage_viewport_tool",false),"Viewport damage positioning can be activated from the operation editor")
	await RenderingServer.frame_post_draw; check(root.get_texture().get_image().save_png("res://.godot/verification/destruction_workspace.png")==OK,"Native destruction-editor screenshot is captured")
	editor.physics.dispose(); editor.model.history.clear_history(); main.queue_free(); await settle(3)
	print("POWDER / DESTRUCTION UI: %d checks, %d failures"%[checks,failures]); quit(failures)
