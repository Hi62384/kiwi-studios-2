class_name IntArrayProperty
extends ActorPropertyType

@export var _value: Array[int] = []


func set_value(_val: Variant) -> void:
	_value = _val
	super(_val)


func get_value() -> Variant:
	return _value
