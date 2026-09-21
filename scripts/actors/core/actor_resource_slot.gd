class_name ActorResourceSlot
extends Button
## A resource field that accepts project-file drags from Kiwi's filesystem.

signal file_dropped(path: String)

var accepts_file: Callable


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var path := path_from_drag(data)
	var accepted: bool = not path.is_empty() and (not accepts_file.is_valid() or bool(accepts_file.call(path)))
	self_modulate = Color("b8fff0") if accepted else Color.WHITE
	return accepted


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	self_modulate = Color.WHITE
	var path := path_from_drag(data)
	if not path.is_empty() and (not accepts_file.is_valid() or accepts_file.call(path)):
		file_dropped.emit(path)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		self_modulate = Color.WHITE


static func path_from_drag(data: Variant) -> String:
	if data is String:
		return _normalize_path(data)
	if data is PackedStringArray or data is Array:
		return _normalize_path(str(data[0])) if not data.is_empty() else ""
	if data is Dictionary:
		for collection_key in [&"paths", &"files"]:
			var paths: Variant = data.get(collection_key)
			if (paths is PackedStringArray or paths is Array) and not paths.is_empty():
				return _normalize_path(str(paths[0]))
		for single_key in [&"path", &"file"]:
			var path := str(data.get(single_key, ""))
			if not path.is_empty():
				return _normalize_path(path)
	return ""


static func _normalize_path(path: String) -> String:
	if path.begins_with("res://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	return path.simplify_path()
