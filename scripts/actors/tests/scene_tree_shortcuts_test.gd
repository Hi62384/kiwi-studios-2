extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func key(code: Key, control: bool = false, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.ctrl_pressed = control
	event.shift_pressed = shift
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func run() -> void:
	var editor := ActorTimelineEditor.new()
	editor.size = Vector2(1000, 300)
	root.add_child(editor)
	var scene_tree := ActorSceneTree.new()
	root.add_child(scene_tree)
	scene_tree.setup(editor.model, editor.registry)
	var model := editor.model
	model.create_actor(editor.registry.get_definition(&"point_3d"), 0)
	await process_frame
	scene_tree.grab_focus()
	key(KEY_D, true)
	await process_frame
	check(model.actors.size() == 2, "Scene tree Ctrl+D duplicates selected actor")
	key(KEY_Z, true)
	await process_frame
	check(model.actors.size() == 1, "Scene tree Ctrl+Z undoes duplication")
	key(KEY_Z, true, true)
	await process_frame
	check(model.actors.size() == 2, "Scene tree Ctrl+Shift+Z redoes duplication")
	key(KEY_A, true)
	await process_frame
	check(model.selected_ids.size() == 2, "Scene tree Ctrl+A selects actors")
	key(KEY_P)
	await process_frame
	check(not model.actors[0].parent_id.is_empty() or not model.actors[1].parent_id.is_empty(),
		"Scene tree P parents selected actors")
	key(KEY_P, false, true)
	await process_frame
	check(model.actors[0].parent_id.is_empty() and model.actors[1].parent_id.is_empty(), "Scene tree Shift+P unparents actors")
	key(KEY_C, true)
	await process_frame
	check(editor._actor_clipboard.size() == 2, "Scene tree Ctrl+C copies actors")
	key(KEY_V, true)
	await process_frame
	check(model.actors.size() == 4, "Scene tree Ctrl+V pastes actors")
	key(KEY_BACKSPACE)
	await process_frame
	check(model.actors.size() == 2, "Scene tree Backspace deletes pasted selection")
	scene_tree.queue_free()
	editor.queue_free()
	await process_frame
	print("Scene tree shortcut checks: %d failures" % failures)
	quit(failures)
