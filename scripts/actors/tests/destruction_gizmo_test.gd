extends SceneTree
var checks:=0
var failures:=0
var editor: ActorTimelineEditor
var gizmo: ActorUIGizmo
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func button(point: Vector2,pressed: bool) -> void:
	var event:=InputEventMouseButton.new(); event.position=gizmo.get_global_transform_with_canvas()*point; event.global_position=event.position; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; root.push_input(event,true)
func drag(actor: ActorData,offset: Vector2) -> void:
	editor.model.select(editor.model.clip_for_actor_id(actor.id).id); actor.set_meta("damage_viewport_tool",true); actor.set_meta("damage_selected_operation","cut"); await process_frame
	var runtime:=editor._runtime_for_clip(editor.model.clip_for_actor_id(actor.id).id); var point: Vector2=gizmo.spatial.project(runtime.remote_transform()*actor.values.destruction_operations.cut.position)
	button(point,true); var event:=InputEventMouseMotion.new(); event.position=gizmo.get_global_transform_with_canvas()*(point+offset); event.global_position=event.position; event.button_mask=MOUSE_BUTTON_MASK_LEFT; root.push_input(event,true); button(point+offset,false); await process_frame
func run() -> void:
	root.size=Vector2i(1000,720); editor=ActorTimelineEditor.new(); root.add_child(editor); editor.hide()
	var view:=SubViewport.new(); view.size=Vector2i(1000,600); root.add_child(view); var lens:=Camera3D.new(); lens.position=Vector3(0,0,5); view.add_child(lens); lens.make_current(); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var display:=TextureRect.new(); display.size=Vector2(950,600); display.texture=view.get_texture(); display.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; root.add_child(display)
	gizmo=ActorUIGizmo.new(); gizmo.editor=editor; gizmo.display=display; display.add_child(gizmo)
	var actors: Array[ActorData]=[]
	for i in 2:
		var clip:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0,{&"position":Vector3(i*1.5-.75,0,0),&"destruction_enabled":true}); clip.start_time=0; clip.layer=i
		var actor:=editor.model.selected_actor(); var op:=KiwiDestructionDefinition.operation(0,3); actor.values.destruction_operations={"cut":op}; actors.append(actor)
	editor.model.changed.emit(); await process_frame; editor.model.history.clear_history()
	await drag(actors[0],Vector2(50,0)); var first: Vector3=actors[0].values.destruction_operations.cut.position
	check(first.x>.1,"Dragging the visible damage handle edits the operation's local center")
	await drag(actors[1],Vector2(0,40)); var second: Vector3=actors[1].values.destruction_operations.cut.position
	check(second.length()>.1,"A second actor can be edited independently in the same viewport")
	editor.model.undo(); check(actors[1].values.destruction_operations.cut.position==Vector3.ZERO and actors[0].values.destruction_operations.cut.position==first,"Undo targets the correct actor after changing selection")
	editor.model.undo(); check(actors[0].values.destruction_operations.cut.position==Vector3.ZERO,"A complete pointer gesture occupies one undo entry")
	editor.model.redo(); check(actors[0].values.destruction_operations.cut.position==first,"Redo restores the exact authored damage center")
	var host:=ActorInspector.new(); host.model=editor.model; root.add_child(host)
	var control:=preload("res://scripts/actors/physics/destruction/destruction_control.gd").new(); host.add_child(control); control.setup(host,actors[0]); await process_frame
	var path:=PackedStringArray(["destruction_operations","cut","time"])
	editor.canvas.playhead=0; editor.model.playhead_time=0; editor.model.add_keyframe(actors[0],path,"Damage start",3.0); editor.canvas.playhead=.5; editor.model.playhead_time=.5; actors[0].animation_time=.5; editor.model.history.clear_history()
	var number:=control.find_child("Damage_time",true,false) as DragNumber
	number.interaction_started.emit(); number.preview_changed.emit(4.0)
	check(ActorAnimation.sampled_value(actors[0],path,.5)==4.0 and actors[0].values.destruction_operations.cut.time==3.0,"Numeric dragging previews keyed damage without changing its base value")
	number.drag_committed.emit(4.0)
	check(actors[0].animation_track(path).keys.size()==2 and ActorAnimation.sampled_value(actors[0],path,.5)==4.0 and actors[0].animation_previews.is_empty(),"Releasing a keyed numeric drag inserts a real keyframe and clears its preview")
	editor.model.undo(); check(actors[0].animation_track(path).keys.size()==1,"A keyed numeric drag is one undoable animation edit")
	editor.model.redo(); check(actors[0].animation_track(path).keys.size()==2,"Redo restores the authored destruction keyframe")
	number.interaction_started.emit(); number.preview_changed.emit(6.0); number.drag_cancelled.emit()
	check(ActorAnimation.sampled_value(actors[0],path,.5)==4.0 and actors[0].animation_previews.is_empty(),"Cancelling a keyed drag restores the sampled animation without a stray preview")
	var vector_number:=control.find_child("Damage_position_1",true,false) as DragNumber; var original: Vector3=actors[0].values.destruction_operations.cut.position
	editor.model.history.clear_history(); vector_number.interaction_started.emit(); vector_number.preview_changed.emit(2.0)
	check(actors[0].values.destruction_operations.cut.position.y==2.0,"Vector damage controls preview their geometry while dragging")
	vector_number.drag_committed.emit(2.0); editor.model.undo()
	check(actors[0].values.destruction_operations.cut.position==original,"Vector dragging restores the complete original center in one undo")
	KiwiDestructionDefinition.edit(editor.model,actors[0],{},"Remove keyed operation")
	check(actors[0].animation_track(path)==null and ActorAnimation.sampled_values(actors[0],.5).destruction_operations.is_empty(),"Deleting a keyed operation removes its tracks so sampling cannot resurrect it")
	editor.model.undo(); check(actors[0].animation_track(path)!=null and actors[0].values.destruction_operations.has("cut"),"Undo restores both the removed operation and all its keyframes")
	editor.model.select(editor.model.clip_for_actor_id(actors[0].id).id)
	var radius_path:=PackedStringArray(["destruction_operations","cut","radius"])
	editor.canvas.playhead=0; editor.model.playhead_time=0; editor.model.add_keyframe(actors[0],radius_path,"Damage radius",.5); editor.canvas.playhead=.5; editor.model.playhead_time=.5; actors[0].animation_time=.5; editor.model.history.clear_history()
	var wheel:=InputEventMouseButton.new(); wheel.button_index=MOUSE_BUTTON_WHEEL_UP; wheel.pressed=true; wheel.shift_pressed=true
	gizmo.spatial.damage.handle_event(wheel)
	check(actors[0].animation_track(radius_path).keys.size()==2 and is_equal_approx(ActorAnimation.sampled_value(actors[0],radius_path,.5),.55) and actors[0].values.destruction_operations.cut.radius==.5,"Viewport radius scrolling edits its keyframe instead of the base radius")
	editor.model.undo(); check(actors[0].animation_track(radius_path).keys.size()==1,"Viewport radius scrolling is undoable as a single animation edit")
	host.queue_free(); await process_frame
	editor.physics.dispose(); editor.model.history.clear_history(); editor.queue_free(); display.queue_free(); view.queue_free(); await process_frame
	print("DESTRUCTION GIZMO: %d checks, %d failures"%[checks,failures]); quit(failures)
