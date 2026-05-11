class_name IntProperty
extends ActorPropertyType

@export var _value: int = 0
@export var min_max_range: Vector2i = Vector2i(-INF,INF)


func set_value(_val: Variant) -> void:
	_val = clampi(_val, min_max_range.x, min_max_range.y)
	_value = _val
	super(_val)


func get_value() -> Variant:
	return _value
