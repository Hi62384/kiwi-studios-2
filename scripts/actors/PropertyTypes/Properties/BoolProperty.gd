class_name BoolProperty
extends ActorPropertyType

@export var _value: bool = false


func set_value(_val: Variant) -> void:
	_value = _val
	super(_val)


func get_value() -> Variant:
	return _value
