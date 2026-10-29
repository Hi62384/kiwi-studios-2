extends "res://scripts/actors/tests/destruction_gizmo_test.gd"
const Field=preload("res://scripts/actors/fog/fog_field.gd")
func run() -> void:
	root.size=Vector2i(1000,720); editor=ActorTimelineEditor.new(); root.add_child(editor); editor.hide()
	var view:=SubViewport.new(); view.size=Vector2i(1000,600); root.add_child(view); var lens:=Camera3D.new(); lens.position=Vector3(0,0,5); view.add_child(lens); lens.make_current(); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var display:=TextureRect.new(); display.size=Vector2(950,600); display.texture=view.get_texture(); display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; root.add_child(display)
	gizmo=ActorUIGizmo.new(); gizmo.editor=editor; gizmo.display=display; display.add_child(gizmo)
	var data:=Field.definition().create_object(); data.values[&"mode"]=5; var clip:=editor.model.create_actor(editor.registry.get_definition(&"fog_volume"),0,{&"position":Vector3.ZERO,&"field":ActorObjectReference.from_object(data)}); var actor:=editor.model.actor_for_id(clip.actor_id); data=ActorAnimation.resolve_reference(actor.values[&"field"]); actor.set_meta("editor_fog_field",data); editor.model.changed.emit(); await process_frame; await process_frame; editor.model.history.clear_history()
	var point: Vector2=gizmo.spatial.project(Vector3.ZERO); button(point,true); var motion:=InputEventMouseMotion.new(); motion.position=gizmo.get_global_transform_with_canvas()*(point+Vector2(35,0)); motion.global_position=motion.position; motion.button_mask=MOUSE_BUTTON_MASK_LEFT; root.push_input(motion,true); button(point+Vector2(35,0),false); await process_frame
	var voxels: Dictionary=ActorData.copy_value(data.get_value(&"paint",{})); check(voxels.size()>20,"Real viewport pointer input paints a three-dimensional density stroke")
	var zs:={}
	for p: Vector3i in voxels: zs[p.z]=true
	check(zs.size()>1,"Viewport painting edits volume depth, not a flat image")
	editor.model.undo(); check((data.get_value(&"paint",{}) as Dictionary).is_empty(),"One viewport stroke is one undo action")
	editor.model.redo(); check(data.get_value(&"paint",{})==voxels,"Viewport stroke redo restores identical voxels")
	button(point-Vector2(80,0),true); var escape:=InputEventKey.new(); escape.pressed=true; escape.keycode=KEY_ESCAPE; root.push_input(escape,true); await process_frame
	check(data.get_value(&"paint",{})==voxels,"Escape cancels the preview stroke without erasing previous density")
	root.push_input(escape,true); await process_frame; check(not actor.has_meta("editor_fog_field"),"Escape exits the viewport painting tool")
	editor.physics.dispose(); editor.model.history.clear_history(); editor.queue_free(); display.queue_free(); view.queue_free(); await process_frame; print("FOG VIEWPORT PAINT: %d checks, %d failures"%[checks,failures]); quit(failures)
