extends PanelContainer
var index: int
var reorder: Callable
func _get_drag_data(_at: Vector2) -> Variant:
	var label:=Label.new(); label.text="Move operation"; set_drag_preview(label)
	return {"value_operation":index,"owner":get_parent().get_instance_id()}
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("owner")==get_parent().get_instance_id() and data.has("value_operation")
func _drop_data(_at: Vector2, data: Variant) -> void:
	reorder.call(int(data.value_operation),index)
