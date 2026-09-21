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
	model.create_actor(editor.registry.get_definition(&"point_3d"), 0)
	var actor := model.selected_actor()
	var path := PackedStringArray(["position"])
	model.playhead_time = 0
	model.add_keyframe(actor, path, "Transform / Position", Vector3.ZERO)
	model.playhead_time = 4
	model.add_keyframe(actor, path, "Transform / Position", Vector3(8, 4, 2))
	var first_id := actor.animation_track(path).keys[0].id
	check(actor.animation_track(path).sample(2) == Vector3(4, 2, 1), "New keys use linear easing")
	var quadratic := ActorValueCurve.preset("Quadratic")
	model.edit_keyframe(actor, first_id, {"value_curve": quadratic})
	check(actor.animation_track(path).sample(2).is_equal_approx(Vector3(2, 1, 0.5)), "Outgoing curve controls interpolation to next key")
	check(actor.animation_track(path).sample(4) == Vector3(8, 4, 2), "Easing preserves exact right-key value")
	quadratic.set_point_value(1, 0.9)
	check(is_equal_approx(actor.animation_track(path).keys[0].value_curve.sample(0.5), 0.25), "Key curves are copied, not shared with editor")
	model.undo()
	check(actor.animation_track(path).sample(2) == Vector3(4, 2, 1), "Curve edit undoes")
	model.redo()
	check(actor.animation_track(path).sample(2).is_equal_approx(Vector3(2, 1, 0.5)), "Curve edit redoes")
	for preset in ["Linear", "Exponential", "Quadratic", "Ease out", "Smoothstep", "Sine", "Step"]:
		var curve := ActorValueCurve.preset(preset)
		check(is_equal_approx(curve.sample(0), 0) and is_equal_approx(curve.sample(1), 1), "Preset %s anchors endpoints" % preset)
	model.separate_track(actor, path)
	check(actor.animation_tracks.size() == 3, "Vector3 separates into three tracks")
	check(ActorAnimation.sampled_value(actor, path, 2).is_equal_approx(Vector3(2, 1, 0.5)), "Separated curves preserve combined sampled values")
	var x_track := actor.animation_tracks[0]
	model.edit_keyframe(actor, x_track.keys[1].id, {"value": 12.0})
	check(ActorAnimation.sampled_values(actor, 4)[&"position"] == Vector3(12, 4, 2), "Editing X component does not change Y or Z")
	model.playhead_time = 2
	editor.canvas.playhead = 2
	var sampled: Vector3 = ActorAnimation.sampled_value(actor, path, 2)
	model.preview_property(actor, editor.registry.get_definition(&"point_3d"), &"position", sampled + Vector3(1, 0, 0))
	check(ActorAnimation.sampled_value(actor, path, 2) == sampled + Vector3(1, 0, 0), "Separated inspector values preview as a composite")
	model.commit_property_preview(actor, editor.registry.get_definition(&"point_3d"), &"position", sampled, sampled + Vector3(1, 0, 0))
	check(actor.animation_tracks[0].key_at(2) != null and actor.animation_tracks[1].key_at(2) == null,
		"Inspector change keys only changed component")
	model.undo()
	check(actor.animation_tracks[0].key_at(2) == null, "Separated property edit undoes in one action")
	model.overlay_actor_id = actor.id
	model.overlay_path = path
	model.changed.emit()
	await process_frame
	var overlay := editor.property_overlay
	check(overlay.displayed_tracks().size() == 3, "Property diamond displays all component tracks")
	var first_y := overlay.key_position(actor.animation_tracks[0].keys[0], 0).y
	var last_y := overlay.key_position(actor.animation_tracks[2].keys[0], 2).y
	check(first_y < last_y, "Component diamonds occupy staggered heights on actor")
	var old_id := actor.animation_tracks[0].keys[0].id
	editor.keyframe_editor.lanes.selected_keys.assign([old_id])
	editor.keyframe_editor._build_details()
	var has_unseparate := false
	for child in editor.keyframe_editor.details.get_children():
		if child is Button and child.text == "Unseparate": has_unseparate = true
	check(has_unseparate, "Component key offers Unseparate")
	model.unseparate_track(actor, path)
	check(actor.animation_tracks.size() == 1 and actor.animation_track(path).component == -1, "Unseparate restores a combined track")
	check(ActorAnimation.sampled_value(actor, path, 4) == Vector3(12, 4, 2), "Unseparate retains component key values")
	model.undo()
	check(actor.animation_tracks.size() == 3, "Unseparate undo restores independent tracks")
	var color_path := PackedStringArray(["test_color"])
	actor.values[&"test_color"] = Color.BLACK
	model.playhead_time = 0
	model.add_keyframe(actor, color_path, "Color", Color(0.1, 0.2, 0.3, 0.4))
	model.separate_track(actor, color_path)
	var color_tracks := 0
	for track in actor.animation_tracks:
		if track.path == color_path: color_tracks += 1
	check(color_tracks == 4 and ActorAnimation.sampled_value(actor, color_path, 0) == Color(0.1, 0.2, 0.3, 0.4), "Color separates into RGBA tracks")
	var save_path := "user://curve_components_" + ActorData.new_id() + ".tres"
	check(ResourceSaver.save(actor, save_path) == OK, "Save actor with curves and components")
	var loaded := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorData
	check(loaded.animation_track(path).component == 0 and loaded.animation_track(path).keys[0].value_curve != null,
		"Curve and component metadata survive save/load")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	editor.keyframe_editor._open_curve_menu(actor.animation_tracks[0].keys[0].id)
	await process_frame
	check(is_instance_valid(editor.keyframe_editor.curve_popup), "Value curve button opens an editable popup")
	var curve_key_id := actor.animation_tracks[0].keys[0].id
	var graph := editor.keyframe_editor.curve_popup.get_child(0).get_child(1) as ActorValueCurve
	var point_count := graph.curve.point_count
	var had_curve := model.keyframe_for_id(actor, curve_key_id).value_curve != null
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = graph.graph_point(Vector2(0.3, 0.7))
	press.global_position = graph.get_global_transform() * press.position
	graph._gui_input(press)
	check(graph.curve.point_count == point_count + 1, "Clicking curve graph inserts a point")
	var motion := InputEventMouseMotion.new()
	motion.position = graph.get_global_transform() * graph.graph_point(Vector2(0.31, 0.8))
	graph._input(motion)
	check(model.keyframe_for_id(actor, curve_key_id).value_curve.point_count == point_count + 1, "Dragging curve updates key easing live")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	graph._input(release)
	model.undo()
	var restored_curve := model.keyframe_for_id(actor, curve_key_id).value_curve
	check((restored_curve != null and restored_curve.point_count == point_count) if had_curve else restored_curve == null,
		"Curve point drag undoes as one action")
	check(graph.curve.point_count == point_count, "Open curve menu refreshes immediately after undo")
	graph.selected_point = 0
	press.position = graph.tangent_position(0, 1)
	press.global_position = graph.get_global_transform() * press.position
	graph._gui_input(press)
	check(graph._drag_handle == 1, "Gold outgoing handle starts tangent editing")
	motion.position = graph.get_global_transform() * (graph.graph_point(Vector2.ZERO) + Vector2(45, 0))
	graph._input(motion)
	check(is_zero_approx(graph.curve.get_point_right_tangent(0)), "Dragging handle horizontally flattens tangent")
	check(graph.curve.sample(0.5) < 0.5, "Tangent bends interpolation between endpoints rather than drawing a straight line")
	graph._input(release)
	model.undo()
	check(is_equal_approx(graph.curve.sample(0.5), 0.5), "Tangent drag undoes as one action")
	press.position = graph.tangent_position(0, 1)
	press.global_position = graph.get_global_transform() * press.position
	graph._gui_input(press)
	graph._input(motion)
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	graph._input(escape)
	check(is_equal_approx(graph.curve.sample(0.5), 0.5), "Esc cancels tangent editing")
	press.position = graph.tangent_position(0, 1)
	press.global_position = graph.get_global_transform() * press.position
	graph._gui_input(press)
	graph._input(motion)
	graph._input(release)
	var bent_sample := graph.curve.sample(0.5)
	graph.reset_tangents()
	check(is_equal_approx(graph.curve.sample(0.5), 0.5), "Reset tangents restores a straight segment")
	check(graph.curve.get_point_right_mode(0) == Curve.TANGENT_LINEAR, "Reset uses automatic linear tangents")
	model.undo()
	check(is_equal_approx(graph.curve.sample(0.5), bent_sample), "Tangent reset undoes in one action")
	model.redo()
	check(is_equal_approx(graph.curve.sample(0.5), 0.5), "Tangent reset redoes")
	editor.keyframe_editor.curve_popup.hide()
	editor.queue_free()
	await process_frame
	print("Keyframe curve/component checks: %d failures" % failures)
	quit(failures)
