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
	root.add_child(editor)
	await process_frame
	var model := editor.model
	var definition := editor.registry.get_definition(&"point_3d")
	var root_clip := model.create_actor(definition, 0)
	var child := model.create_actor(definition, 6)
	var grandchild := model.create_actor(definition, 12)
	var deep := model.create_actor(definition, 18)
	var sibling := model.create_actor(definition, 24)
	var outside := model.create_actor(definition, 36)
	model.set_parent(child.actor_id, root_clip.actor_id)
	model.set_parent(grandchild.actor_id, child.actor_id)
	model.set_parent(deep.actor_id, grandchild.actor_id)
	model.set_parent(sibling.actor_id, root_clip.actor_id)
	model.select(root_clip.id)
	model.select(child.id, true)
	editor.canvas.grab_focus()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_F
	editor._unhandled_key_input(key)
	check(model.focused_actor_id == child.actor_id and model.selected_ids == [child.id], "F focuses only last selected actor")
	check(model.visible_clips().size() == 3 and not model.clip_is_visible(model._index_of(sibling.id)),
		"Focus shows actor and recursive descendants, but excludes sibling branches and ancestors")
	model.focus_actor(deep.actor_id)
	check(model.focus_path().size() == 4 and model.visible_clips() == [deep], "Focus supports arbitrary nesting with full ancestor path")
	check(editor.breadcrumb_row.get_child_count() == 9, "Breadcrumb includes section and all four ancestor buttons")
	var child_breadcrumb := editor.breadcrumb_row.get_child(4) as Button
	child_breadcrumb.pressed.emit()
	check(model.focused_actor_id == child.actor_id and model.visible_clips().size() == 3, "Clicking ancestor breadcrumb restores its branch view")
	key.keycode = KEY_LEFT
	key.alt_pressed = true
	editor._unhandled_key_input(key)
	check(model.focused_actor_id == root_clip.actor_id, "Alt+Left navigates up one actual parent")
	key.keycode = KEY_HOME
	editor._unhandled_key_input(key)
	check(model.focused_actor_id.is_empty() and model.visible_clips().size() == 6, "Alt+Home restores section view")
	model.set_timeline_children_visible(root_clip.actor_id, false)
	check(not model.can_place(root_clip.id, child.start_time, root_clip.duration, child.layer),
		"Parent is obstructed by hidden child in section overview")
	check(not model.can_place(deep.id, root_clip.start_time, deep.duration, root_clip.layer),
		"Hidden descendants are also obstructed by their ancestor")
	var original_start := root_clip.start_time
	model.move_clip(root_clip.id, child.start_time, child.layer)
	check(not (root_clip.layer == child.layer and root_clip.start_time < child.start_time + child.duration
		and root_clip.start_time + root_clip.duration > child.start_time), "Moving parent snaps away from hidden child")
	if not is_equal_approx(root_clip.start_time, original_start):
		model.undo()
	model.focus_actor(child.actor_id)
	check(model.visible_clips().size() == 3, "Focused branch is not hidden by an ancestor outside the view")
	model.set_timeline_children_visible(child.actor_id, false)
	check(model.visible_clips().size() == 3, "Focus overrides its own children visibility toggle")
	model.set_timeline_children_visible(grandchild.actor_id, false)
	check(not model.clip_is_visible(model._index_of(deep.id)), "Nested eye toggles hide descendants unless that nested actor is focused")
	model.focus_actor(grandchild.actor_id)
	check(model.clip_is_visible(model._index_of(deep.id)), "Focusing nested hidden actor reveals its own children")
	model.focus_parent()
	check(not model.clip_is_visible(model._index_of(deep.id)), "Going back restores nested hidden branch")
	model.leave_actor_focus()
	check(model.visible_clips() == [root_clip, outside], "Returning to section restores original hidden-children settings")
	model.focus_actor(child.actor_id)
	check(not model.actor_for_id(root_clip.actor_id).show_timeline_children
		and not model.actor_for_id(child.actor_id).show_timeline_children
		and not model.actor_for_id(grandchild.actor_id).show_timeline_children,
		"Focus does not modify saved visibility toggles")
	model.set_timeline_children_visible(child.actor_id, true)
	var added := model.create_actor(definition, 30)
	check(model.actor_for_id(added.actor_id).parent_id == child.actor_id and model.clip_is_visible(model._index_of(added.id)),
		"Actors created in focused view belong to its branch")
	model.undo()
	model.select(child.id)
	editor._show_context_menu(Vector2.ZERO)
	check(editor.context_menu.get_item_index(ActorTimelineEditor.MENU_FOCUS_ACTOR) >= 0, "Actor context menu includes Focus Actor")
	editor.context_menu.hide()
	model.delete_selected()
	check(model.focused_actor_id.is_empty(), "Deleting focused actor safely falls back to section view")
	model.undo()
	model.focus_actor(grandchild.actor_id)
	model.focus_actor(grandchild.actor_id)
	check(model.focused_actor_id == child.actor_id, "Focusing current actor goes up one level")
	model.focus_actor(child.actor_id)
	check(model.focused_actor_id == root_clip.actor_id, "Repeated focus can navigate recursively up the branch")
	model.focus_actor(root_clip.actor_id)
	check(model.focused_actor_id.is_empty(), "Focusing current root returns to section")
	model.focus_actor(child.actor_id)
	check(model.can_place(deep.id, sibling.start_time, deep.duration, sibling.layer),
		"Descendants of hidden actor are not obstructed by actors outside the focused branch")
	check(model.hidden_clip_obstructs_view(model._index_of(sibling.id)),
		"Hidden outsiders that still obstruct the visible focused actor receive ghost boxes")
	check(model.hidden_clip_obstructs_view(model._index_of(root_clip.id)),
		"Focused view displays hidden parent's obstruction box, including hidden-children parents")
	check(not model.can_place(child.id, root_clip.start_time, child.duration, root_clip.layer),
		"Parent ghost accurately corresponds to a placement obstruction")
	model.focus_actor(root_clip.actor_id)
	check(model.hidden_clip_obstructs_view(model._index_of(outside.id))
		and not model.can_place(root_clip.id, outside.start_time, root_clip.duration, outside.layer),
		"Focused actor still displays and respects overview sibling obstructions when its children are hidden")
	model.set_timeline_children_visible(child.actor_id, false)
	check(model.clip_is_visible(model._index_of(child.id)) and not model.clip_is_visible(model._index_of(grandchild.id))
		and not model.clip_is_visible(model._index_of(deep.id)), "Hidden child branch stays hidden while focusing its ancestor")
	check(not model.hidden_clip_obstructs_view(model._index_of(grandchild.id)), "Descendant obstructions stop at hidden child branch")
	check(model.can_place(root_clip.id, grandchild.start_time, root_clip.duration, grandchild.layer),
		"Clips beyond a hidden descendant boundary do not obstruct the ancestor")
	model.select("")
	check(not model.hidden_clip_obstructs_view(model._index_of(grandchild.id)), "Hidden child obstruction box disappears when ancestor is deselected")
	check(not model.can_place(root_clip.id, child.start_time, root_clip.duration, child.layer),
		"First hidden descendant still obstructs deselected ancestor without drawing its box")
	model.select(sibling.id)
	check(not model.hidden_clip_obstructs_view(model._index_of(grandchild.id)), "Selecting unrelated actor does not reveal hidden child boxes")
	model.select(child.id)
	check(model.hidden_clip_obstructs_view(model._index_of(grandchild.id)), "Selecting direct parent reveals its hidden child obstruction box")
	model.focus_actor(child.actor_id)
	check(model.clip_is_visible(model._index_of(grandchild.id)), "Focusing child reveals that child's hidden descendants")
	model.focus_actor(deep.actor_id)
	check(model.hidden_clip_obstructs_view(model._index_of(grandchild.id))
		and not model.hidden_clip_obstructs_view(model._index_of(child.id))
		and not model.hidden_clip_obstructs_view(model._index_of(root_clip.id)),
		"Ancestor obstruction traversal includes first hidden parent but stops before higher ancestors")
	check(not model.can_place(deep.id, grandchild.start_time, deep.duration, grandchild.layer)
		and model.can_place(deep.id, root_clip.start_time, deep.duration, root_clip.layer),
		"Ancestor collision rules match bounded obstruction traversal")
	model.focus_actor(child.actor_id)
	check(model.hidden_clip_obstructs_view(model._index_of(root_clip.id))
		and not model.hidden_clip_obstructs_view(model._index_of(outside.id)),
		"Isolated focused child retains its parent's obstruction box without showing outside siblings")
	check(not model.can_place(child.id, grandchild.start_time, child.duration, grandchild.layer),
		"Actors shown together in focused branch still obstruct each other")
	editor.x_zoom.value = 90
	editor.y_zoom.value = 64
	editor.canvas.playhead = 43.25
	editor.h_scroll.value = 8
	editor.v_scroll.value = 20
	editor.canvas.snap_enabled = false
	var saved_x := editor.canvas.scroll_time
	var saved_y := editor.canvas.scroll_rows
	var new_section := model.create_section()
	check(model.focused_actor_id.is_empty(), "Changing section clears branch focus")
	editor.x_zoom.value = 40
	editor.y_zoom.value = 22
	editor.canvas.playhead = 7
	model.select_section("default")
	check(model.focused_actor_id == child.actor_id and editor.canvas.playhead == 43.25
		and editor.canvas.pixels_per_second == 90 and editor.canvas.row_height == 64
		and is_equal_approx(editor.canvas.scroll_time, saved_x) and is_equal_approx(editor.canvas.scroll_rows, saved_y)
		and not editor.canvas.snap_enabled, "Returning to section restores focus, scroll, zoom, cursor and snap")
	model.select_section(new_section.id)
	check(editor.canvas.playhead == 7 and editor.canvas.pixels_per_second == 40 and editor.canvas.row_height == 22,
		"Timeline view state is independent per section")
	editor.queue_free()
	await process_frame
	print("Timeline focus checks: %d failures" % failures)
	quit(failures)
