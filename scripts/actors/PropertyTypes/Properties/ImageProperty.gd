class_name ImageProperty
extends ActorPropertyType

@export var _value: Texture2D


func can_be_chosen_from_filesystem_filetype() -> FileOperations.FileType:
	return FileOperations.FileType.IMAGE


func set_value(_val: Variant) -> void:
	_value = _val
	super(_val)


func get_value() -> Variant:
	return _value
