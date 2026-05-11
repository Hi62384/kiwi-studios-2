class_name GdsShaderProperty
extends ActorPropertyType

@export var _value: Shader


func can_be_chosen_from_filesystem_filetype() -> FileOperations.FileType:
	return FileOperations.FileType.GDSHADER


func set_value(_val: Variant) -> void:
	_value = _val
	super(_val)


func get_value() -> Variant:
	return _value
