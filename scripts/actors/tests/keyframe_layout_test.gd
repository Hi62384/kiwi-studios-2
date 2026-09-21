extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var split := VSplitContainer.new()
	split.size = Vector2(1200, 800)
	root.add_child(split)
	var viewport_area := Control.new()
	viewport_area.custom_minimum_size.y = 100
	viewport_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(viewport_area)
	var editor := ActorTimelineEditor.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(editor)
	await process_frame
	await process_frame
	var model := editor.model
	model.create_actor(editor.registry.get_definition(&"point_3d"), 0)
	await process_frame
	var actor := model.selected_actor()
	var minimum := editor.get_combined_minimum_size()
	var viewport_height := viewport_area.size.y
	for index in 20:
		model.add_keyframe(actor, PackedStringArray(["test_%d" % index]), "Track %d" % index, 0.0)
	await process_frame
	await process_frame
	check(not editor.keyframe_view.visible, "Adding keys never opens the keyframe view")
	check(editor.get_combined_minimum_size() == minimum, "Tracks do not inflate timeline minimum size")
	check(is_equal_approx(viewport_area.size.y, viewport_height), "Adding keys leaves viewport height unchanged")
	editor.set_keyframe_view(true)
	await process_frame
	await process_frame
	check(editor.keyframe_view.visible and not editor.actor_view.visible, "Keyframes explicitly replace actors in the same area")
	check(editor.get_combined_minimum_size().y <= minimum.y, "Opening many tracks does not inflate timeline minimum size")
	check(viewport_area.size.y >= viewport_height, "Opening keyframes never reduces viewport height")
	check(editor.keyframe_editor.lanes.size.y > editor.keyframe_editor.lanes.get_parent().size.y,
		"Long keyframe content scrolls within the timeline")
	check(not editor.breadcrumb_panel.visible, "Keyframe view hides hierarchy breadcrumbs")
	var key_editor := editor.keyframe_editor
	var ruler_position := key_editor.ruler.global_position
	var properties_position := key_editor.detail_scroll.global_position
	key_editor.track_scroll.scroll_vertical = 100
	await process_frame
	check(key_editor.ruler.global_position == ruler_position, "Ruler stays pinned while tracks scroll")
	check(key_editor.detail_scroll.global_position == properties_position, "Key properties stay pinned while tracks scroll")
	check(key_editor.detail_scroll.position.y + key_editor.detail_scroll.size.y <= key_editor.size.y + 1,
		"Key properties stay inside the allocated timeline area")
	check(key_editor.track_scroll.clip_contents, "Scrolled tracks cannot paint over pinned ruler or properties")
	key_editor.lanes.selected_keys.assign([actor.animation_tracks[0].keys[0].id])
	key_editor._build_details()
	await process_frame
	await process_frame
	check(key_editor.detail_scroll.size.y <= 36, "Keyframe properties use a slim single-row strip")
	for test_height in [160.0, 300.0, 500.0]:
		editor.size.y = test_height
		await process_frame
		await process_frame
		check(key_editor.track_scroll.position.y >= key_editor.ruler.position.y + key_editor.ruler.size.y - 1,
			"Track area starts below the ruler when resizing")
		check(key_editor.track_scroll.position.y + key_editor.track_scroll.size.y <= key_editor.detail_scroll.position.y + 1,
			"Track area ends before key properties when resizing")
		check(key_editor.detail_scroll.position.y + key_editor.detail_scroll.size.y <= key_editor.size.y + 1,
			"Key properties remain fully inside the editor when resizing")
	var lanes := key_editor.lanes
	var old_height := lanes.track_height()
	editor.y_zoom.value *= 2
	await process_frame
	check(is_equal_approx(lanes.track_height(), old_height * 2), "Y scale adjusts keyframe track height")
	check(is_equal_approx(lanes.custom_minimum_size.y, lanes.track_height() * 20), "Y scale updates scrollable track extent")
	key_editor.track_scroll.scroll_vertical = 0
	await process_frame
	var first := actor.animation_tracks[0].keys[0]
	var second := actor.animation_tracks[1].keys[0]
	var start := lanes.key_position(first, 0) + Vector2(30, -10)
	var finish := lanes.key_position(second, 1) + Vector2(-5, 10)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	press.global_position = lanes.get_global_transform() * start
	lanes._gui_input(press)
	check(lanes.box_selecting and not key_editor._editing, "Empty-space drag starts box selection, not an animation edit")
	var motion := InputEventMouseMotion.new()
	motion.position = lanes.get_global_transform() * finish
	lanes._input(motion)
	check(lanes.selected_keys.size() == 2 and lanes.selected_keys.has(first.id) and lanes.selected_keys.has(second.id),
		"Box selects keys across multiple tracks")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = motion.position
	lanes._input(release)
	check(not lanes.box_selecting, "Release finishes keyframe box selection")
	press.ctrl_pressed = true
	lanes._gui_input(press)
	motion.ctrl_pressed = true
	lanes._input(motion)
	release.ctrl_pressed = true
	lanes._input(release)
	check(lanes.selected_keys.is_empty(), "Ctrl box selection removes enclosed keys")
	press.ctrl_pressed = false
	press.shift_pressed = true
	lanes._gui_input(press)
	motion.ctrl_pressed = false
	motion.shift_pressed = true
	lanes._input(motion)
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	lanes._input(escape)
	check(lanes.selected_keys.is_empty() and not lanes.box_selecting, "Esc restores selection before box drag")
	editor.keyframe_editor.close_requested.emit()
	model.set_selection([])
	model.select(actor.id)
	await process_frame
	check(not editor.keyframe_view.visible and editor.actor_view.visible, "Reselecting actor does not reopen closed keyframe view")
	check(editor.breadcrumb_panel.visible, "Actor view restores hierarchy breadcrumbs")
	check(actor.animation_tracks.size() == 20, "Closing the view preserves all tracks")
	model.undo()
	check(actor.animation_tracks.size() == 19, "View switching does not alter keyframe undo history")
	model.redo()
	check(actor.animation_tracks.size() == 20, "Keyframe redo remains available")
	split.queue_free()
	await process_frame
	print("Keyframe layout checks: %d failures" % failures)
	quit(failures)
