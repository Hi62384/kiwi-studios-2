extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void: run.call_deferred()

func run() -> void:
	var editor := ActorTimelineEditor.new()
	root.add_child(editor)
	editor.size = Vector2(1000, 300)
	var model := editor.model
	var definition := editor.registry.get_definition(&"point_3d")
	var a := model.create_actor(definition, 1.0)
	model.selected_layer = 1
	var b := model.create_actor(definition, 1.0)
	model.selected_layer = 2
	var c := model.create_actor(definition, 1.0)
	model.set_parent(b.actor_id, a.actor_id)
	model.set_parent(c.actor_id, b.actor_id)
	model.set_timeline_children_linked(a.actor_id, true)
	model.set_timeline_children_linked(b.actor_id, true)
	model.set_timeline_children_visible(a.actor_id, false)
	var ids: Array[String] = [a.id, b.id]
	check(model.linked_clip_ids(ids).size() == 3, "Nested linking includes hidden grandchildren exactly once")
	model.move_clip(a.id, 2.0)
	check(is_equal_approx(b.start_time, 2.0) and is_equal_approx(c.start_time, 2.0), "Nested linked movement propagates recursively")
	model.history.undo()
	var tree := ActorSceneTree.new()
	root.add_child(tree)
	tree.setup(model, editor.registry)
	await process_frame
	await process_frame
	check(tree._items[a.actor_id].get_button_count(0) == 2, "Parent has collapse and child-link buttons")
	check(tree._items[c.actor_id].get_button_count(0) == 0, "Leaf actor has no child controls")
	model.select(a.id)
	editor.canvas.snap_enabled = false
	editor.canvas.magnet_enabled = false
	var rect := editor.canvas.clip_rect(model._index_of(a.id))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(rect.end.x - 2, rect.get_center().y)
	editor.canvas._gui_input(press)
	check(editor.canvas._drag_ids.size() == 3, "Timeline gesture includes linked hidden descendants")
	editor.canvas.update_drag(press.position.x - editor.canvas.pixels_per_second)
	check(editor.canvas.preview_valid, "Linked right trim previews remain valid")
	editor.canvas.finish_drag()
	check(is_equal_approx(a.duration, 4.0) and is_equal_approx(b.duration, 4.0) and is_equal_approx(c.duration, 4.0), "Timeline right trim updates linked descendants")
	model.history.undo()
	check(is_equal_approx(a.duration, 5.0) and is_equal_approx(c.duration, 5.0), "Gesture trim undoes as one operation")
	editor.end_input.value = 5.0
	check(is_equal_approx(a.duration, 4.0) and is_equal_approx(c.duration, 4.0), "Clip timing dialog also trims linked descendants")
	model.history.undo()
	var data := model.actor_for_id(a.actor_id)
	var saved := "user://linked_actor_" + ActorData.new_id() + ".tres"
	check(ResourceSaver.save(data, saved) == OK, "Actor link state is saveable")
	var loaded := ResourceLoader.load(saved, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorData
	check(loaded.link_timeline_children and loaded.copy_actor().link_timeline_children, "Saving and duplication retain child link state")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved))
	tree.free()
	editor.free()
	await process_frame
	print("Child link controls checks: %d failures" % failures)
	quit(failures)
