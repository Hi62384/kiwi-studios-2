class_name ActorReferenceProperty
extends ActorPropertyType

var _value: Node
@export var _node_path: NodePath


func can_be_chosen_from_filesystem_filetype() -> FileOperations.FileType:
	return -2


func set_value(_val: Variant) -> void:
	_value = _val
	super(_val)


func get_value() -> Variant:
	return _value
