extends SceneTree
var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var editor := load("res://Workspaces/SceneWorkspace/Timeline.tscn").instantiate() as ActorTimelineEditor
	root.add_child(editor)
	editor.size = Vector2(850, 350)
	await process_frame
	await process_frame
	editor.create_actor(0)
	editor.create_actor(0)
	var a := editor.model.clips[0]
	var b := editor.model.clips[1]
	check(a.layer == 0 and b.layer == 0 and b.start_time == 5, "Creation fills free space in shared layer")
	check(editor.canvas.clip_rect(0).position.y == editor.canvas.clip_rect(1).position.y, "Clips drawn on shared row")
	editor.model.move_clip(b.id, 1, 0)
	check(b.start_time == 5, "Overlapping move snaps after neighbor")
	editor.model.trim_clip(a.id, 0, 6)
	check(a.duration == 5, "Model rejects overlapping trim")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = editor.canvas.clip_rect(1).position + Vector2(20, 12)
	editor.canvas._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = editor.canvas.get_global_transform_with_canvas() * (press.position + Vector2(-260, 48))
	editor.canvas._input(motion)
	check(editor.canvas.preview_layer == 1 and editor.canvas.preview_valid, "Vertical drag previews different layer")
	editor.canvas.finish_drag()
	check(b.layer == 1 and b.start_time == 1, "Drag commits layer and time together")
	editor.undo()
	check(b.layer == 0 and b.start_time == 5, "One undo restores layer and time")
	editor.redo()
	check(b.layer == 1 and b.start_time == 1, "Redo restores layer and time")
	press.position = editor.canvas.clip_rect(1).position + Vector2(20, 12)
	editor.canvas._gui_input(press)
	motion.position = editor.canvas.get_global_transform_with_canvas() * (press.position - Vector2(0, 48))
	editor.canvas._input(motion)
	check(editor.canvas.preview_valid and editor.canvas.preview_time == 5, "Overlapping layer preview snaps to free edge")
	editor.canvas.finish_drag()
	check(b.layer == 0 and b.start_time == 5, "Drop commits snapped placement")
	editor.undo()
	check(b.layer == 1 and b.start_time == 1, "Undo snapped drop restores layer and time")
	editor.model.move_clip(a.id, 10, 0)
	check(editor.model.nearest_free_start(b.id, 8, 5, 0) == 5, "Collision near left edge snaps before neighbor")
	check(editor.model.nearest_free_start(b.id, 13, 5, 0) == 15, "Collision near right edge snaps after neighbor")
	editor.undo()
	editor.model.move_clip(b.id, 5, 0)
	check(b.layer == 0 and b.start_time == 5, "Touching edges valid")
	editor.free()
	print("Layer checks: ", failures, " failures")
	quit(1 if failures else 0)
