extends SceneTree

var failures: int = 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var packed := load("res://Workspaces/SceneWorkspace/Timeline.tscn") as PackedScene
	var editor := packed.instantiate() as ActorTimelineEditor
	root.add_child(editor)
	editor.size = Vector2(850, 300)
	await process_frame
	await process_frame
	check(editor.undo_button.disabled, "Empty toolbar state")
	var ruler_press := InputEventMouseButton.new()
	ruler_press.button_index = MOUSE_BUTTON_LEFT
	ruler_press.pressed = true
	ruler_press.position = Vector2(ActorTimelineCanvas.LABEL_WIDTH + 65, 10)
	editor.canvas._gui_input(ruler_press)
	check(editor.canvas.scrubbing and editor.canvas.playhead == 1.0, "Ruler press starts scrub")
	for time in [2.0, 4.0, 3.0]:
		var motion := InputEventMouseMotion.new()
		motion.position = editor.canvas.get_global_transform_with_canvas() * Vector2(ActorTimelineCanvas.LABEL_WIDTH + time * 65, 70)
		editor.canvas._input(motion)
		check(is_equal_approx(editor.canvas.playhead, time), "Ruler drag continuously follows pointer outside header")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = editor.canvas.get_global_transform_with_canvas() * Vector2(ActorTimelineCanvas.LABEL_WIDTH + 195, 70)
	editor.canvas._input(release)
	check(not editor.canvas.scrubbing and editor.canvas.playhead == 3.0, "Release ends scrub at final time")
	check(not editor.model.history.has_undo(), "Scrubbing does not create edit history")
	editor.canvas.time_selected.emit(2.0)
	editor.actor_picker.choose(0)
	var clip := editor.model.clips[0]
	var actor := editor.model.actors[0]
	check(clip.start_time == 2.0 and clip.actor_id == actor.id, "Create at cursor via menu")
	check(not editor.undo_button.disabled, "Toolbar updates after create")
	# Exercise the same hit testing and drag preview used by the mouse.
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = editor.canvas.clip_rect(0).position + Vector2(12, 10)
	editor.canvas._gui_input(press)
	check(editor.canvas.drag_id == clip.id, "Clip click begins drag")
	editor.canvas.update_drag(press.position.x + editor.canvas.pixels_per_second * 3.0)
	check(clip.start_time == 2.0, "Drag preview does not mutate document")
	editor.canvas.finish_drag()
	check(is_equal_approx(clip.start_time, 5.0), "Drag commits new start")
	editor.undo_button.pressed.emit()
	check(clip.start_time == 2.0, "One undo reverses complete drag")
	editor.redo_button.pressed.emit()
	check(is_equal_approx(clip.start_time, 5.0), "Redo restores drag")
	press.position = editor.canvas.clip_rect(0).position + Vector2(12, 10)
	editor.canvas._gui_input(press)
	editor.canvas.update_drag(press.position.x + 100)
	editor.canvas.cancel_drag()
	check(is_equal_approx(clip.start_time, 5.0), "Cancel leaves original time")
	editor.start_input.value = 8.0
	check(clip.start_time == 8.0, "Exact start control")
	editor.delete_selected()
	check(editor.model.clips.is_empty() and editor.model.actors.is_empty(), "Delete removes actor and clip")
	editor.undo()
	check(editor.model.clips[0] == clip and editor.model.actors[0] == actor, "Undo delete retains identity")
	check(editor.model.selected_id == clip.id and clip.start_time == 8.0, "Undo delete restores selection and time")
	editor.undo()
	check(is_equal_approx(clip.start_time, 5.0), "Undo exact start")
	editor.undo()
	editor.undo()
	check(editor.model.clips.is_empty(), "Undo entire edit sequence")
	editor.redo()
	check(editor.model.clips[0] == clip, "Redo creation retains identity")
	editor.model.move_clip(clip.id, -10.0)
	check(clip.start_time == 0.0, "Clamp negative time")
	check(not editor.model.history.has_redo(), "New edits clear redo branch")
	# Keyboard events pass through the actual viewport with the canvas focused.
	editor.canvas.grab_focus()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_DELETE
	key.physical_keycode = KEY_DELETE
	root.push_input(key)
	await process_frame
	check(editor.model.clips.is_empty(), "Delete shortcut")
	key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_Z
	key.physical_keycode = KEY_Z
	key.ctrl_pressed = true
	root.push_input(key)
	await process_frame
	check(editor.model.clips.size() == 1, "Undo shortcut")
	var other_focus := FocusableKeyInput.new()
	FocusableKeyInput.current_focused_instance = other_focus
	key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_DELETE
	editor._unhandled_key_input(key)
	check(editor.model.clips.size() == 1, "Other panels cannot trigger timeline deletion")
	FocusableKeyInput.current_focused_instance = null
	other_focus.free()
	# Shift-click accumulates a selection, and the last actor clicked becomes the
	# primary actor used by the inspector and single-actor toolbar actions.
	var multi_model := ActorTimeline.new()
	var definition := editor.registry.get_definitions()[0]
	multi_model.selected_layer = 0
	var first := multi_model.create_actor(definition, 0.0)
	multi_model.selected_layer = 1
	var second := multi_model.create_actor(definition, 0.0)
	var multi_canvas := ActorTimelineCanvas.new()
	multi_canvas.model = multi_model
	multi_canvas.registry = editor.registry
	multi_canvas.size = Vector2(850, 180)
	root.add_child(multi_canvas)
	await process_frame
	var multi_press := InputEventMouseButton.new()
	multi_press.button_index = MOUSE_BUTTON_LEFT
	multi_press.pressed = true
	multi_press.position = multi_canvas.clip_rect(0).get_center()
	multi_canvas._gui_input(multi_press)
	multi_canvas.cancel_drag()
	multi_press = InputEventMouseButton.new()
	multi_press.button_index = MOUSE_BUTTON_LEFT
	multi_press.pressed = true
	multi_press.shift_pressed = true
	multi_press.position = multi_canvas.clip_rect(1).get_center()
	multi_canvas._gui_input(multi_press)
	multi_canvas.cancel_drag()
	check(multi_model.selected_ids.size() == 2
		and multi_model.is_selected(first.id) and multi_model.is_selected(second.id),
		"Shift-click keeps both actors selected")
	check(multi_model.selected_id == second.id and multi_model.selected_actor().id == second.actor_id,
		"Last Shift-clicked actor is the primary selection")
	multi_press.position = multi_canvas.clip_rect(0).get_center()
	multi_canvas._gui_input(multi_press)
	multi_canvas.cancel_drag()
	check(multi_model.selected_ids.size() == 2 and multi_model.selected_id == first.id,
		"Shift-clicking an existing selection makes it primary without deselecting others")
	# Moving and trimming the primary clip applies the same delta to the complete selection.
	multi_canvas._gui_input(multi_press)
	multi_canvas.update_drag(multi_press.position.x + multi_canvas.pixels_per_second)
	multi_canvas.finish_drag()
	check(is_equal_approx(first.start_time, 1.0) and is_equal_approx(second.start_time, 1.0),
		"Dragging moves every selected actor by the same amount")
	multi_model.undo()
	check(is_equal_approx(first.start_time, 0.0) and is_equal_approx(second.start_time, 0.0),
		"One undo restores a grouped move")
	# The expanded edge hit area includes the pixels just beyond the visual right edge.
	multi_press.position = multi_canvas.clip_rect(0).end + Vector2(2, -20)
	multi_canvas._gui_input(multi_press)
	check(multi_canvas.drag_mode == "right", "Right actor edge starts a trim gesture")
	multi_canvas.update_drag(multi_press.position.x + multi_canvas.pixels_per_second)
	multi_canvas.finish_drag()
	check(is_equal_approx(first.duration, 6.0) and is_equal_approx(second.duration, 6.0),
		"Right trim changes every selected actor by the same amount")
	multi_model.undo()
	# Left-edge trimming also applies as a group.
	multi_press.position = multi_canvas.clip_rect(0).position + Vector2(2, 20)
	multi_canvas._gui_input(multi_press)
	check(multi_canvas.drag_mode == "left", "Left actor edge starts a trim gesture")
	multi_canvas.update_drag(multi_press.position.x + multi_canvas.pixels_per_second)
	multi_canvas.finish_drag()
	check(is_equal_approx(first.start_time, 1.0) and is_equal_approx(second.start_time, 1.0)
		and is_equal_approx(first.duration, 4.0) and is_equal_approx(second.duration, 4.0),
		"Left trim changes every selected actor by the same amount")
	multi_model.undo()
	var first_actor := multi_model.actor_for_id(first.actor_id)
	var second_actor := multi_model.actor_for_id(second.actor_id)
	multi_model.parent_many([second_actor.id], first_actor.id)
	check(second_actor.parent_id == first_actor.id, "Group parenting uses the primary actor as parent")
	multi_model.unparent_many([first_actor.id, second_actor.id])
	check(second_actor.parent_id.is_empty(), "Unparent applies to the selected actor group")
	multi_model.undo()
	check(second_actor.parent_id == first_actor.id, "Undo reverses grouped unparenting")
	multi_model.undo()
	check(second_actor.parent_id.is_empty(), "Undo reverses grouped parenting")
	multi_model.delete_selected()
	check(multi_model.clips.is_empty(), "Delete removes every selected actor")
	multi_model.undo()
	check(multi_model.clips.size() == 2 and multi_model.selected_ids.size() == 2,
		"One undo restores a grouped deletion and its selection")
	multi_press.shift_pressed = false
	multi_press.position = multi_canvas.clip_rect(1).get_center()
	multi_canvas._gui_input(multi_press)
	multi_canvas.cancel_drag()
	check(multi_model.selected_ids.size() == 2 and multi_model.selected_id == second.id,
		"Normal press on a selected actor preserves the group for dragging")
	multi_canvas.free()
	# Ctrl+A is scoped to timeline focus and retains the current primary actor.
	editor.model.selected_layer = 1
	var select_all_clip := editor.model.create_actor(definition, 10.0)
	editor.canvas.grab_focus()
	key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_A
	key.ctrl_pressed = true
	editor._unhandled_key_input(key)
	check(editor.model.selected_ids.size() == editor.model.clips.size()
		and editor.model.selected_id == select_all_clip.id, "Ctrl+A selects every timeline actor")
	editor._show_context_menu(Vector2(200, 200))
	check(editor.context_menu.get_item_index(ActorTimelineEditor.MENU_DUPLICATE) >= 0
		and editor.context_menu.get_item_index(ActorTimelineEditor.MENU_COPY) >= 0
		and editor.context_menu.get_item_index(ActorTimelineEditor.MENU_PARENT) >= 0
		and editor.context_menu.get_item_index(ActorTimelineEditor.MENU_UNPARENT) >= 0
		and editor.context_menu.get_item_index(ActorTimelineEditor.MENU_DELETE) >= 0,
		"Actor context menu exposes grouped actor actions")
	editor.context_menu.hide()
	var workspace_tree := ActorSceneTree.new()
	root.add_child(workspace_tree)
	workspace_tree.custom_minimum_size = Vector2(280, 180)
	workspace_tree.setup(editor.model, editor.registry)
	await process_frame
	var tree_right_click := InputEventMouseButton.new()
	tree_right_click.button_index = MOUSE_BUTTON_RIGHT
	tree_right_click.pressed = true
	tree_right_click.position = workspace_tree.get_item_area_rect(
		workspace_tree._items[editor.model.selected_actor().id]).get_center()
	workspace_tree._gui_input(tree_right_click)
	check(editor.context_menu.get_item_index(ActorTimelineEditor.MENU_COPY) >= 0,
		"Scene Tree right-click opens the shared actor action menu")
	editor.context_menu.hide()
	editor.copy_selected()
	tree_right_click.position = workspace_tree.get_item_area_rect(workspace_tree.get_root()).get_center()
	workspace_tree._gui_input(tree_right_click)
	var scene_paste_index := editor.context_menu.get_item_index(ActorTimelineEditor.MENU_PASTE)
	check(scene_paste_index >= 0 and not editor.context_menu.is_item_disabled(scene_paste_index),
		"Scene root right-click offers Paste for copied actors")
	editor.context_menu.hide()
	workspace_tree.free()
	var original_parent_ids: Array[String] = []
	for selected_actor in editor.model.selected_actors():
		original_parent_ids.append(selected_actor.id)
	editor.copy_selected()
	var count_before_paste := editor.model.clips.size()
	editor.paste_copied(true, 20.0, 0)
	check(editor.model.clips.size() == count_before_paste + original_parent_ids.size() * 2,
		"Actor-menu paste creates one clipboard copy for every selected parent")
	var child_counts: Dictionary = {}
	for parent_id in original_parent_ids:
		child_counts[parent_id] = 0
	for pasted_actor in editor.model.selected_actors():
		if child_counts.has(pasted_actor.parent_id):
			child_counts[pasted_actor.parent_id] += 1
	check(child_counts.values().all(func(value: int): return value == 2),
		"Each targeted paste is parented to its corresponding selected actor")
	editor.undo()
	editor.canvas.playhead = 24.0
	editor._show_context_menu(Vector2(240, 220), false, 40.0, 2)
	check(editor.context_menu.get_item_index(ActorTimelineEditor.MENU_PASTE) >= 0,
		"Empty timeline context menu offers Paste")
	editor.context_menu.hide()
	editor._context_action_selected(ActorTimelineEditor.MENU_PASTE)
	var pasted_start := INF
	for pasted_clip_id in editor.model.selected_ids:
		pasted_start = minf(pasted_start, editor.model.clips[editor.model._index_of(pasted_clip_id)].start_time)
	check(editor.model.clips.size() == count_before_paste + 2
		and pasted_start == 24.0
		and editor.model.selected_actors().all(func(item: ActorData): return item.parent_id.is_empty()),
		"Empty-timeline paste creates root actors starting at the clicked cursor")
	editor.undo()
	editor.duplicate_selected()
	check(editor.model.clips.size() == count_before_paste + 2
		and editor.model.selected_actors().all(func(item: ActorData): return item.display_name.ends_with(" Copy")),
		"Duplicate creates a selected copy of every selected actor")
	editor.undo()
	# Verify integration without initializing unrelated filesystem services.
	var main := load("res://scenes/Main.tscn") as PackedScene
	var state := main.get_state()
	var found := false
	for index in state.get_node_count():
		if state.get_node_name(index) == &"ActorTimeline":
			found = state.get_node_instance(index) == packed
	check(found, "Main scene contains timeline")
	editor.free()
	print("Timeline checks: ", failures, " failures")
	quit(1 if failures else 0)
