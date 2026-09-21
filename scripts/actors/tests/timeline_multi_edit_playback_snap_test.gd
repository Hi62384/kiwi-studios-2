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
	editor.size = Vector2(1100, 350)
	root.add_child(editor)
	var model := editor.model
	var first_clip := model.create_actor(editor.registry.get_definition(&"point_3d"), 0)
	var first := model.selected_actor()
	var second_clip := model.create_actor(editor.registry.get_definition(&"basic_shape"), 10)
	var second := model.selected_actor()
	second.values[&"position"] = Vector3(2, 2, 2)
	model.set_selection([first_clip.id, second_clip.id], second_clip.id)
	var inspector := ActorInspector.new()
	root.add_child(inspector)
	inspector.setup(model, editor.registry)
	var batch := inspector.property_batch
	batch.edit(second, &"position", Vector3(7, 7, 7))
	check(first.values[&"position"] == Vector3(7, 7, 7) and second.values[&"position"] == Vector3(7, 7, 7), "Common property changes selected actors of different types")
	model.undo()
	check(first.values[&"position"] == Vector3.ZERO and second.values[&"position"] == Vector3(2, 2, 2), "One undo restores each actor's original property")
	batch.preview(second, &"position", Vector3(9, 9, 9))
	check(first.values[&"position"] == Vector3(9, 9, 9), "Multi-actor drag previews live")
	batch.preview(second, &"position", Vector3(2, 2, 2))
	check(first.values[&"position"] == Vector3.ZERO and second.values[&"position"] == Vector3(2, 2, 2), "Cancelling preview restores differing actor values")
	batch.preview(second, &"position", Vector3(9, 9, 9))
	batch.finish(second, &"position", Vector3(2, 2, 2), Vector3(10, 10, 10))
	model.undo()
	check(first.values[&"position"] == Vector3.ZERO and second.values[&"position"] == Vector3(2, 2, 2), "Multi-actor drag is one undo action")
	model.select(first_clip.id)
	var path := PackedStringArray(["position"])
	model.playhead_time = 0
	model.add_keyframe(first, path, "Position", Vector3(0, 1, 2))
	model.playhead_time = 2
	model.add_keyframe(first, path, "Position", Vector3(4, 5, 6))
	var track := first.animation_track(path)
	var first_id := track.keys[0].id
	var second_id := track.keys[1].id
	editor.keyframe_editor.lanes.selected_keys.assign([first_id, second_id])
	editor.keyframe_editor._change_keys(first_id, {"value": Vector3(3, 0, 0)}, false, 0)
	check(model.keyframe_for_id(first, first_id).value == Vector3(3, 1, 2) and model.keyframe_for_id(first, second_id).value == Vector3(3, 5, 6), "Multi-key component edit preserves each key's other components")
	model.undo()
	editor.keyframe_editor._change_keys(first_id, {"time": 1.0})
	check(model.keyframe_for_id(first, first_id).time == 1 and model.keyframe_for_id(first, second_id).time == 3, "Multi-key time edit preserves spacing")
	model.undo()
	editor.keyframe_editor._change_keys(first_id, {"value_curve": ActorValueCurve.preset("Quadratic")})
	check(model.keyframe_for_id(first, first_id).value_curve != null and model.keyframe_for_id(first, second_id).value_curve != null, "Curve changes apply to all selected keys")
	model.undo()
	editor.canvas.magnet_enabled = true
	check(is_equal_approx(editor.canvas.magnetic_delta(9.94, [0.0], [first_clip.id]), 10), "Magnet snaps moving clip to another clip edge")
	check(is_equal_approx(editor.canvas.magnetic_delta(1.96, [0.0], [], [first_id], true), 2), "Keyframe view magnet snaps to other displayed keys")
	check(is_equal_approx(editor.canvas.magnetic_delta(1.96, [0.0]), 1.96), "Normal timeline ignores keys not displayed")
	model.overlay_actor_id = first.id
	model.overlay_path = path
	check(is_equal_approx(editor.canvas.magnetic_delta(1.96, [0.0], [], [first_id]), 2), "Normal timeline magnet includes property overlay keys")
	check(is_equal_approx(editor.canvas.magnetic_delta(1.96, [0.0], [], [first_id, second_id]), 1.96), "Magnet excludes moving keys")
	editor.canvas.magnet_enabled = false
	check(is_equal_approx(editor.canvas.magnetic_delta(9.94, [0.0]), 9.94), "Magnet toggle disables magnetic snapping")
	editor.canvas.playhead = 0
	editor.toggle_playback()
	editor._process(0.5)
	check(editor.playing and editor.canvas.playhead == 0.5 and model.playhead_time == 0.5, "Playback advances and evaluates the playhead")
	editor.toggle_playback()
	editor._process(0.5)
	check(not editor.playing and editor.canvas.playhead == 0.5, "Pause stops playhead advancement")
	inspector.queue_free()
	editor.queue_free()
	await process_frame
	print("Multi-edit/playback/snap checks: %d failures" % failures)
	quit(failures)
