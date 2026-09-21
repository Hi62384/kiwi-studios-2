extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void: run.call_deferred()

func run() -> void:
	root.size = Vector2i(1100, 700)
	var filesystem: Node = load("res://CustomNodes/FileSystem/file_system.gd").new()
	var row: Node = filesystem.EXPANDABLE_BUTTON.instantiate()
	root.add_child(row)
	var texture: Texture2D = FileOperations.FILE_COLORED_TEXTURE
	filesystem._display_generation = 2
	filesystem._apply_button_thumbnail(row, texture, 1)
	check(row.icon != texture, "Stale thumbnail generation cannot update a current row")
	filesystem._apply_button_thumbnail(row, texture, 2)
	check(row.icon == texture, "Current thumbnail updates the row")
	row.free()
	filesystem._apply_button_thumbnail(row, texture, 2)
	check(not is_instance_valid(row), "Freed thumbnail targets are safely ignored")
	filesystem.free()
	var editor := ActorTimelineEditor.new()
	root.add_child(editor)
	editor.position = Vector2(0, 300)
	editor.size = Vector2(1000, 230)
	await process_frame
	await process_frame
	editor.model.selected_layer = 6
	var clip := editor.model.create_actor(editor.registry.get_definition(&"point_3d"), 20.0)
	editor.h_scroll.value = 10.0
	editor.v_scroll.value = 230.0
	var x := editor.h_scroll.value
	var y := editor.v_scroll.value
	check(y > 0.0, "Timeline starts scrolled down")
	editor.model.focus_actor(clip.actor_id)
	check(is_equal_approx(editor.v_scroll.value, y) and is_equal_approx(editor.canvas.scroll_rows, y), "Actor focus preserves vertical scroll")
	check(is_equal_approx(editor.h_scroll.value, x), "Actor focus preserves horizontal scroll")
	editor.model.focus_parent()
	check(is_equal_approx(editor.v_scroll.value, y), "Unfocus preserves scroll too")
	var number := DragNumber.new()
	number.step = 0.01
	number.position = Vector2(25, 25)
	number.custom_minimum_size = Vector2(160, 32)
	root.add_child(number)
	var cover := Panel.new()
	cover.position = Vector2(20, 20)
	cover.size = Vector2(180, 50)
	cover.z_index = 100
	root.add_child(cover)
	await process_frame
	await process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = number.get_line_edit().get_global_rect().get_center()
	root.push_input(click)
	check(not number._pressed, "Covered numeric input cannot steal a frontmost panel click")
	click = click.duplicate()
	click.pressed = false
	root.push_input(click)
	cover.hide()
	click = click.duplicate()
	click.pressed = true
	root.push_input(click)
	check(number._pressed, "Uncovered numeric input still begins dragging via GUI")
	var motion := InputEventMouseMotion.new()
	motion.position = click.position + Vector2(8, 0)
	root.push_input(motion)
	check(number.dragging and is_equal_approx(number.value, 0.2), "GUI-started numeric drag still previews values")
	click = click.duplicate()
	click.position = motion.position
	click.pressed = false
	root.push_input(click)
	check(not number._pressed and not number.dragging, "Numeric drag releases normally")
	cover.free()
	number.free()
	editor.free()
	await process_frame
	print("Runtime UI priority checks: %d failures" % failures)
	quit(failures)
