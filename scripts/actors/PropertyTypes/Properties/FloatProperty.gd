class_name FloatProperty
extends ActorPropertyType

@export var _value: float = 0
@export var min_max_range: Vector2 = Vector2(-INF,INF)


func set_value(_val: Variant) -> void:
	_val = clampf(_val, min_max_range.x, min_max_range.y)
	_value = _val
	super(_val)


func get_value() -> Variant:
	return _value
