class_name SelectableIntProperty
extends ActorPropertyType


@export var options: Array[String]


@export var _value: int = 0


func set_value(_val: Variant) -> void:
	_value = _val
	super(_val)


func get_value() -> Variant:
	return _value
