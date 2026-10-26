extends SceneTree

var failures: int = 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var host := Control.new()
	root.add_child(host)
	var split := HSplitContainer.new()
	split.name = "HSplitContainer"
	host.add_child(split)
	var panel := Panel.new()
	panel.name = "PropertiesPanel"
	split.add_child(panel)
	var editor := load("res://Workspaces/SceneWorkspace/Timeline.tscn").instantiate() as ActorTimelineEditor
	host.add_child(editor)
	editor.size = Vector2(850, 300)
	await process_frame
	await process_frame
	editor.canvas.playhead = 2.0
	editor.create_actor(0)
	var clip := editor.model.clips[0]
	var actor := editor.model.actors[0]
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = editor.canvas.clip_rect(0).position + Vector2(2, 12)
	editor.canvas._gui_input(press)
	check(editor.canvas.drag_mode == "left", "Left handle hit")
	editor.canvas.update_drag(press.position.x + 65.0)
	check(clip.start_time == 2.0 and clip.duration == 5.0, "Trim only previews before release")
	editor.canvas.finish_drag()
	check(clip.start_time == 3.0 and clip.duration == 4.0 and clip.source_offset == 1.0, "Left trim preserves right edge and source alignment")
	editor.undo()
	check(clip.start_time == 2.0 and clip.duration == 5.0 and clip.source_offset == 0.0, "Undo left trim")
	editor.redo()
	check(clip.duration == 4.0, "Redo left trim")
	press.position = Vector2(editor.canvas.clip_rect(0).end.x - 2, editor.canvas.clip_rect(0).position.y + 12)
	editor.canvas._gui_input(press)
	check(editor.canvas.drag_mode == "right", "Right handle hit")
	editor.canvas.update_drag(press.position.x + 130.0)
	editor.canvas.finish_drag()
	check(clip.start_time == 3.0 and clip.duration == 6.0, "Right trim leaves start unchanged")
	editor.undo()
	check(clip.duration == 4.0, "Undo right trim")
	check(editor.start_input.step == 0.01 and editor.end_input.step == 0.01,
		"Timeline timing controls display hundredth-second precision")
	editor.start_input.interaction_started.emit()
	editor.start_input.preview_changed.emit(3.25)
	check(is_equal_approx(clip.start_time, 3.25), "Dragging Start previews timing live")
	editor.start_input.drag_committed.emit(3.25)
	editor.undo()
	check(is_equal_approx(clip.start_time, 3.0), "Start drag commits as one undo action")
	editor.end_input.value = 7.75
	check(is_equal_approx(clip.duration, 4.75), "End timing field accepts hundredth-second values")
	editor.undo()
	check(is_equal_approx(clip.duration, 4.0), "Undo restores typed End value")
	editor.y_zoom.value = 64.0
	check(editor.canvas.row_height == 64.0 and editor.canvas.clip_rect(0).size.y == 56.0,
		"Y scale slider changes timeline layer height")
	editor.y_zoom.value = editor.y_zoom.min_value
	var compact_rect := editor.canvas.clip_rect(0)
	check(editor.y_zoom.min_value == 12.0 and editor.y_zoom.max_value == 180.0
		and compact_rect.position.y >= ActorTimelineCanvas.HEADER
		and compact_rect.end.y <= ActorTimelineCanvas.HEADER + editor.canvas.row_height,
		"Extreme compact Y scale keeps actors inside their layer row")
	editor.y_zoom.value = 64.0
	editor.x_zoom.value = 100.0
	check(editor.canvas.pixels_per_second == 100.0, "X scale slider changes timeline time scale")
	check(editor.inspector != null, "Existing properties panel connected")
	var general_category := editor.inspector.find_child("Category_General", true, false) as Button
	var transform_category := editor.inspector.find_child("Category_Transform", true, false) as Button
	check(general_category != null and transform_category != null, "Inspector displays property categories")
	check(transform_category.button_pressed and editor.inspector._sections["Actor/Transform"].page.visible, "Shared transform section starts selected")
	editor.inspector.select_section("General")
	check(not editor.inspector._sections["Actor/Transform"].page.visible, "Selecting another section hides the old page")
	check(editor.inspector_ui_state.section_for(actor.id, "Actor") == "General", "Selected section saved by actor")
	editor.inspector._actor = null
	editor.inspector.refresh()
	transform_category = editor.inspector.find_child("Category_Transform", true, false) as Button
	check(not transform_category.button_pressed and not editor.inspector._sections["Actor/Transform"].page.visible, "Section choice survives inspector rebuild")
	editor.inspector.select_section("Transform")
	var field := editor.inspector.find_child("position_0", true, false) as SpinBox
	check(field != null, "Generated vector property field")
	field.value = 7.5
	check(actor.get_value(&"position") == Vector3(7.5, 0, 0), "Inspector edits actor")
	editor.undo()
	check(actor.get_value(&"position") == Vector3.ZERO and field.value == 0.0, "Undo refreshes inspector")
	editor.redo()
	check(field.value == 7.5, "Redo refreshes inspector")
	var name_input := editor.inspector.find_child("ActorName", true, false) as LineEdit
	name_input.text = "Hero"
	name_input.text_submitted.emit(name_input.text)
	check(actor.display_name == "Hero", "Rename through inspector")
	editor.undo()
	check(actor.display_name == "3D Point" and name_input.text == "3D Point", "Undo rename refreshes field")
	editor.redo()
	check(actor.display_name == "Hero", "Redo rename")
	var number := field as DragNumber
	var number_press := InputEventMouseButton.new()
	number_press.button_index = MOUSE_BUTTON_LEFT
	number_press.pressed = true
	number_press.position = number.get_line_edit().get_global_rect().get_center()
	number._line_edit_input(number_press.xformed_by(number.get_line_edit().get_global_transform_with_canvas().affine_inverse()))
	var history_before_drag := editor.model.history.get_current_action_name()
	var motion := InputEventMouseMotion.new()
	motion.position = number_press.position + Vector2(4, 0)
	number._input(motion)
	check(is_equal_approx(number.value, 7.6), "Default numeric drag increment")
	check(editor.hint_label.text == "Esc cancels drag", "Property drag contextual hint")
	motion.position.x += 4
	motion.ctrl_pressed = true
	number._input(motion)
	check(is_equal_approx(number.value, 8.6), "Ctrl drag increment")
	motion.position.x += 4
	motion.shift_pressed = true
	number._input(motion)
	check(is_equal_approx(number.value, 8.61), "Shift drag increment takes precedence")
	check(is_equal_approx(actor.get_value(&"position").x, 8.61), "Value drag updates actor during gesture")
	check(editor.model.history.get_current_action_name() == history_before_drag, "Preview does not add undo entries")
	number.finish_drag()
	check(is_equal_approx(actor.get_value(&"position").x, 8.61), "Value drag commits")
	check(not editor.hint_label.text.contains("Esc cancels") and editor.hint_label.text.contains("Ctrl+D"),
		"Hint returns to selected-actor shortcuts after property drag")
	editor.undo()
	check(number.value == 7.5, "Entire value drag is one undo step")
	number._line_edit_input(number_press.xformed_by(number.get_line_edit().get_global_transform_with_canvas().affine_inverse()))
	motion.position = number_press.position + Vector2(8, 0)
	number._input(motion)
	number.cancel_drag()
	check(number.value == 7.5 and actor.get_value(&"position").x == 7.5, "Cancel numeric drag restores value")
	check(not editor.hint_label.text.contains("Esc cancels") and editor.hint_label.text.contains("Ctrl+C"),
		"Cancel restores selected-actor shortcuts")
	var reset := editor.inspector.find_child("position_reset", true, false) as Button
	check(reset.visible, "Modified property shows reset")
	reset.pressed.emit()
	check(actor.get_value(&"position") == Vector3.ZERO and not reset.visible, "Reset restores default and hides button")
	editor.undo()
	check(actor.get_value(&"position").x == 7.5 and reset.visible, "Undo reset restores altered value")
	var link := editor.inspector.find_child("position_link", true, false) as Button
	link.button_pressed = true
	check(editor.inspector_ui_state.vector_linked(actor.id, &"position"), "Vector link preference saved by actor")
	number.value = 4.0
	check(actor.get_value(&"position") == Vector3(4, 4, 4), "Linked edit sets all components equally")
	editor.undo()
	check(actor.get_value(&"position") == Vector3(7.5, 0, 0), "Linked edit is one undo action")
	editor.redo()
	check(actor.get_value(&"position") == Vector3(4, 4, 4), "Redo linked edit")
	link.button_pressed = false
	number.value = 2.0
	check(actor.get_value(&"position") == Vector3(2, 4, 4), "Unlinked edit only changes one axis")
	var bounds := Rect2(0, 0, 800, 600)
	check(DragNumber.wrap_target(Vector2(799, 300), bounds) == Vector2(4, 300), "Right edge wraps left")
	check(DragNumber.wrap_target(Vector2(1, 300), bounds) == Vector2(796, 300), "Left edge wraps right")
	check(DragNumber.wrap_target(Vector2(400, 599), bounds) == Vector2(400, 4), "Bottom edge wraps up")
	check(DragNumber.wrap_target(Vector2(400, 1), bounds) == Vector2(400, 596), "Top edge wraps down")
	var before_wrap := number.value
	number._wrap_pointer(Vector2(root.get_visible_rect().end.x - 1, 100))
	check(number._last_x == 4 and number.value == before_wrap, "Wrap rebases pointer without changing value")
	press.position = editor.canvas.clip_rect(0).position + Vector2(20, 12)
	editor.canvas._gui_input(press)
	editor.canvas.update_drag(editor.canvas.size.x + 20)
	editor.canvas.advance_auto_scroll(0.5)
	check(editor.canvas.scroll_time > 0 and editor.h_scroll.value == editor.canvas.scroll_time, "Right edge scrolls and updates scrollbar")
	var old_scroll := editor.canvas.scroll_time
	editor.canvas.update_drag(ActorTimelineCanvas.LABEL_WIDTH - 20)
	editor.canvas.advance_auto_scroll(0.1)
	check(editor.canvas.scroll_time < old_scroll, "Left edge scrolls back")
	editor.canvas.cancel_drag()
	check(clip.start_time == 3.0, "Cancel auto-scrolled drag preserves data")
	editor.delete_selected()
	check(editor.inspector._actor == null, "Deleted selection clears inspector")
	editor.undo()
	check(editor.inspector._actor == actor, "Undo deletion restores inspector")
	editor.inspector_ui_state.set_scroll(actor.id, 73.0)
	var state_path := "user://inspector_state_" + ActorData.new_id() + ".tres"
	check(ResourceSaver.save(editor.inspector_ui_state, state_path) == OK, "Save inspector UI state")
	var loaded_state := ResourceLoader.load(state_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorInspectorState
	check(loaded_state != null and loaded_state.scroll_for(actor.id) == 73.0, "Reload actor scroll position")
	check(loaded_state.section_for(actor.id, "Actor") == "Transform", "Reload selected inspector section")
	check(not loaded_state.vector_linked(actor.id, &"position"), "Reload vector link state")
	DirAccess.remove_absolute(state_path)
	host.free()
	await process_frame
	print("Timeline edit checks: ", failures, " failures")
	quit(1 if failures else 0)
