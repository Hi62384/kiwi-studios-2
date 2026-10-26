class_name KiwiTransformationComponents
extends Tree
signal reorder_requested(id: String, index: int)
var session: KiwiTransformationSession
func _get_drag_data(at: Vector2) -> Variant:
	var item := get_item_at_position(at)
	if item==null: return null
	var preview := Label.new(); preview.text=item.get_text(0); set_drag_preview(preview); return {"transformation_component":item.get_metadata(0)}
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	drop_mode_flags=Tree.DROP_MODE_INBETWEEN
	return data is Dictionary and data.has("transformation_component")
func _drop_data(at: Vector2, data: Variant) -> void:
	var item := get_item_at_position(at)
	if item==null: return
	var target := session.document.component(str(item.get_metadata(0))); var source := session.document.component(str(data.transformation_component))
	var index := session.document.components.find(target); var old := session.document.components.find(source)
	if get_drop_section_at_position(at)<0: index+=1
	if old<index: index-=1
	reorder_requested.emit(str(data.transformation_component),index)
