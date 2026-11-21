class_name KiwiTransformationComponents
extends Tree
signal reorder_requested(id: String, index: int)
var session: KiwiTransformationSession
func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_match")
func _get_drag_data(at: Vector2) -> Variant: return _native().call("drag_data", self, at)
func _can_drop_data(_at: Vector2, data: Variant) -> bool: return _native().call("can_drop", self, data)
func _drop_data(at: Vector2, data: Variant) -> void: _native().call("drop", self, at, data)
