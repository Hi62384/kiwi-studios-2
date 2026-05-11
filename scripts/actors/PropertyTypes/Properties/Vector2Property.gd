class_name Vector2Property
extends ActorPropertyType

@export var _value: Vector2


func set_value(_val: Variant) -> void:
	_value = _val
	super(_val)


func get_value() -> Variant:
	return _value
