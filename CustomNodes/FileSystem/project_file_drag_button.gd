class_name ProjectFileDragButton
extends Button
## Supplies a standard payload when a project file is dragged outside the tree.

var drag_paths_provider: Callable
var accepts_drop: Callable
var receives_drop: Callable


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not drag_paths_provider.is_valid():
		return null
	var paths: PackedStringArray = drag_paths_provider.call()
	if paths.is_empty():
		return null
	var preview := PanelContainer.new()
	var label := Label.new()
	label.text = paths[0].get_file() if paths.size() == 1 else "%s  +%d files" % [paths[0].get_file(), paths.size() - 1]
	label.add_theme_color_override("font_color", Color("eff7ff"))
	preview.add_child(label)
	# Godot calls this method during a real GUI drag. Keeping the guard also
	# makes payload validation usable in headless tests and other callers.
	if get_viewport().gui_is_dragging():
		set_drag_preview(preview)
	else:
		preview.free()
	return {
		"type": "project_files",
		"path": paths[0],
		"paths": paths,
	}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return accepts_drop.is_valid() and bool(accepts_drop.call(data))


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if receives_drop.is_valid() and _can_drop_data(Vector2.ZERO, data):
		receives_drop.call(data)
