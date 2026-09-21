extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var editor := ActorTimelineEditor.new()
	editor.size = Vector2(1200, 280)
	root.add_child(editor)
	var model := editor.model
	model.create_actor(editor.registry.get_definition(&"point_3d"), 3)
	var actor := model.selected_actor()
	editor.canvas.playhead = 3
	model.playhead_time = 3
	var inspector := ActorInspector.new()
	root.add_child(inspector)
	inspector.setup(model, editor.registry)
	await process_frame
	await process_frame
	var button := inspector.fields.find_child("position_keyframe", true, false) as Button
	button.set_pressed_no_signal(true)
	button.pressed.emit()
	var path := PackedStringArray(["position"])
	check(model.overlay_path == path and model.overlay_actor_id == actor.id, "Diamond enables property overlay")
	check(button.has_theme_stylebox_override("pressed") and button.button_pressed,
		"Active diamond has explicit highlighted pressed style")
	check(actor.animation_track(path).keys.size() == 1, "First diamond click inserts initial key")
	check(not editor.keyframe_view.visible, "Diamond does not switch timeline views")
	var insert := inspector.fields.find_child("position_insert_keyframe", true, false) as Button
	editor.canvas.time_selected.emit(4)
	insert.pressed.emit()
	check(actor.animation_track(path).keys.size() == 2, "Insert button adds unchanged value at playhead")
	model.edit_property(actor, editor.registry.get_definition(&"point_3d"), &"position", Vector3.ONE)
	check(actor.animation_track(path).key_at(1).value == Vector3.ONE, "Property changes update animation at playhead")
	var scale_button := inspector.fields.find_child("scale_keyframe", true, false) as Button
	scale_button.set_pressed_no_signal(true)
	scale_button.pressed.emit()
	check(model.overlay_path == PackedStringArray(["scale"]), "Another diamond replaces the one displayed property")
	check(not button.button_pressed, "Previous property diamond switches off")
	scale_button.set_pressed_no_signal(false)
	scale_button.pressed.emit()
	check(model.overlay_path.is_empty(), "Diamond disables overlay without deleting animation")
	button.set_pressed_no_signal(true)
	button.pressed.emit()
	var overlay := editor.canvas.get_node("PropertyKeyframeOverlay") as ActorKeyframeCanvas
	check(overlay.displayed_tracks().size() == 1, "Overlay contains exactly one track")
	var key := actor.animation_track(path).keys[0]
	var key_id := key.id
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = overlay.get_global_transform() * overlay.key_position(key, 0)
	press.global_position = press.position
	overlay._input(press)
	check(overlay._dragging, "Inline diamond captures drag instead of dragging actor")
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(editor.canvas.pixels_per_second * 0.5, 0)
	overlay._input(motion)
	check(model.keyframe_for_id(actor, key_id).time == 0.5, "Inline key moves live")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	overlay._input(release)
	model.undo()
	check(model.keyframe_for_id(actor, key_id).time == 0, "Inline key drag is one undoable action")
	editor.set_keyframe_view(true)
	await process_frame
	var lanes := editor.keyframe_editor.ruler
	press.position = Vector2(ActorTimelineCanvas.LABEL_WIDTH + 5 * editor.canvas.pixels_per_second, 10)
	press.global_position = lanes.get_global_transform() * press.position
	lanes._gui_input(press)
	check(editor.canvas.playhead == 5, "Keyframe ruler sets timeline playhead")
	motion.position = lanes.get_global_transform() * Vector2(ActorTimelineCanvas.LABEL_WIDTH + 6 * editor.canvas.pixels_per_second, 10)
	lanes._input(motion)
	check(editor.canvas.playhead == 6 and model.playhead_time == 6, "Keyframe ruler scrubs continuously")
	lanes._input(release)
	check(not lanes._scrubbing, "Releasing ruler ends scrub")
	check(editor.get_combined_minimum_size().y < 190, "Compact toolbar lets timeline shrink below old minimum height")
	inspector.queue_free()
	editor.queue_free()
	await process_frame
	print("Inline keyframe checks: %d failures" % failures)
	quit(failures)
