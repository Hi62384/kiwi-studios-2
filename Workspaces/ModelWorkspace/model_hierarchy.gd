extends Tree
## Drag onto a component to parent; drag into empty tree space to unparent.
var session: KiwiModelSession

func _get_drag_data(position: Vector2) -> Variant:
	var row := get_item_at_position(position)
	if row==null or session==null or get_column_at_position(position)!=0: return null
	var id := str(row.get_metadata(0))
	var ids: Array[String]=session.selected.duplicate() if session.selected.has(id) else [id]
	var preview := Label.new(); preview.text="↳ %d component(s)"%ids.size(); set_drag_preview(preview)
	return {"kiwi_model_tree":get_instance_id(),"ids":ids}

func _can_drop_data(position: Vector2, data: Variant) -> bool:
	drop_mode_flags=Tree.DROP_MODE_ON_ITEM
	if not data is Dictionary or data.get("kiwi_model_tree",0)!=get_instance_id() or session==null: return false
	var row := get_item_at_position(position)
	var parent := str(row.get_metadata(0)) if row!=null else ""
	return session.can_reparent(data.ids,parent)

func _drop_data(position: Vector2, data: Variant) -> void:
	if not _can_drop_data(position,data): return
	var row := get_item_at_position(position)
	session.reparent_components(data.ids,str(row.get_metadata(0)) if row!=null else "")
