class_name ActorSceneTree
extends Tree
## Hierarchy workspace for timeline actors. Drag an actor onto another actor to
## reparent it, or onto the Scene root to unparent it.

var model: ActorTimeline
var registry: ActorRegistry
var _rebuilding := false
var _rebuild_scheduled := false
var _items: Dictionary = {}
var _selection_anchor: String = ""
var _structure_signature: String = ""


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	hide_root = false
	allow_reselect = true
	select_mode = Tree.SELECT_MULTI
	drop_mode_flags = Tree.DROP_MODE_ON_ITEM
	custom_minimum_size = Vector2(220, 150)
	_apply_theme()
	button_clicked.connect(_section_button_clicked)
	item_edited.connect(_section_edited)


func _section_button_clicked(item: TreeItem, _column: int, id: int, mouse_button: int) -> void:
	if mouse_button == MOUSE_BUTTON_LEFT and model != null:
		if item == get_root() and id == 0:
			model.create_section()
		elif id == 1:
			var actor := model.actor_for_id(str(item.get_metadata(0)))
			if actor != null:
				model.set_timeline_children_visible(actor.id, not actor.show_timeline_children)
		elif id == 2:
			var actor := model.actor_for_id(str(item.get_metadata(0)))
			if actor != null: model.set_timeline_children_linked(actor.id, not actor.link_timeline_children)


func _section_edited() -> void:
	var item := get_edited()
	if item != null:
		var id := str(item.get_metadata(0))
		if id.begins_with("section:"):
			model.rename_section(id.trim_prefix("section:"), item.get_text(0))


func setup(timeline: ActorTimeline, types: ActorRegistry) -> void:
	if model != null and model.changed.is_connected(_request_rebuild):
		model.changed.disconnect(_request_rebuild)
	model = timeline
	registry = types
	if model != null:
		model.changed.connect(_request_rebuild)
	_request_rebuild()


func _exit_tree() -> void:
	if model != null and model.changed.is_connected(_request_rebuild):
		model.changed.disconnect(_request_rebuild)
	_rebuild_scheduled = false
	_items.clear()


func _request_rebuild() -> void:
	if _rebuild_scheduled or not is_inside_tree() or is_queued_for_deletion():
		return
	_rebuild_scheduled = true
	call_deferred("_refresh_from_model")


func _refresh_from_model() -> void:
	_rebuild_scheduled = false
	if model == null or not is_inside_tree() or is_queued_for_deletion():
		return
	if _structure_signature == _model_structure_signature():
		_sync_selection()
	else:
		_rebuild()


func _rebuild() -> void:
	_rebuild_scheduled = false
	if model == null or not is_inside_tree() or is_queued_for_deletion():
		return
	var collapsed: Dictionary = {}
	for actor_id: String in _items:
		var item := _items[actor_id] as TreeItem
		if item != null:
			collapsed[actor_id] = item.collapsed
	_rebuilding = true
	clear()
	_items.clear()
	var scene_root := create_item()
	if scene_root == null:
		_rebuilding = false
		return
	scene_root.set_text(0, "SCENE")
	scene_root.set_metadata(0, "")
	scene_root.set_custom_color(0, Color("8de0ca"))
	scene_root.set_selectable(0, false)
	scene_root.add_button(0, preload("res://resources/Images/ActorIcons/AddSection.svg"), 0, false, "Create section")
	var children: Dictionary = {"": []}
	for actor in model.actors:
		var parent_id := actor.parent_id if model.actor_for_id(actor.parent_id) != null else "section:" + actor.section_id
		if not children.has(parent_id):
			children[parent_id] = []
		children[parent_id].append(actor)
	for section in model.sections:
		var section_item := create_item(scene_root)
		var key := "section:" + section.id
		section_item.set_text(0, section.display_name)
		section_item.set_metadata(0, key)
		section_item.set_editable(0, true)
		section_item.set_tooltip_text(0, "Select to edit this section's timeline. Drag actors here to move them. Double-click to rename.")
		section_item.set_custom_color(0, Color("8de0ca"))
		section_item.collapsed = bool(collapsed.get(key, false))
		_items[key] = section_item
		_add_children(section_item, key, children, collapsed, {})
	_structure_signature = _model_structure_signature()
	_sync_selection()
	var selected_actor := model.selected_actor()
	if selected_actor != null and _items.has(selected_actor.id):
		scroll_to_item(_items[selected_actor.id], true)
		if _selection_anchor.is_empty():
			_selection_anchor = selected_actor.id
	_rebuilding = false


func _model_structure_signature() -> String:
	if model == null:
		return ""
	var parts := PackedStringArray()
	for section in model.sections:
		parts.append("section:%s|%s" % [section.id, section.display_name])
	for actor in model.actors:
		parts.append("%s|%s|%s|%s|%s|%s|%s" % [actor.id, actor.parent_id, actor.type_id, actor.display_name, actor.section_id, actor.show_timeline_children, actor.link_timeline_children])
	return "\n".join(parts)


func _sync_selection() -> void:
	if model == null or not is_inside_tree():
		return
	_rebuilding = true
	deselect_all()
	var section_key := "section:" + model.selected_section_id
	for key: String in _items:
		if key.begins_with("section:"):
			(_items[key] as TreeItem).set_custom_bg_color(0, Color("203f46") if key == section_key else Color.TRANSPARENT)
	if model.selected_ids.is_empty() and _items.has(section_key):
		(_items[section_key] as TreeItem).select(0)
	for clip_id in model.selected_ids:
		var index := model._index_of(clip_id)
		if index >= 0 and _items.has(model.actors[index].id):
			(_items[model.actors[index].id] as TreeItem).select(0)
	_rebuilding = false


func _add_children(parent_item: TreeItem, parent_id: String, children: Dictionary,
		collapsed: Dictionary, visited: Dictionary) -> void:
	if visited.has(parent_id):
		return
	visited[parent_id] = true
	var branch: Array = children.get(parent_id, [])
	branch.sort_custom(func(a: ActorData, b: ActorData): return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	for actor: ActorData in branch:
		var item := create_item(parent_item)
		item.set_text(0, actor.display_name)
		item.set_metadata(0, actor.id)
		if not children.get(actor.id, []).is_empty():
			item.add_button(0, preload("res://resources/Images/ActorIcons/TimelineChildrenShown.svg") if actor.show_timeline_children else preload("res://resources/Images/ActorIcons/TimelineChildrenHidden.svg"),
				1, false, "Collapse children in timeline (does not hide objects in the viewport)" if actor.show_timeline_children else "Expand children in timeline (does not change viewport visibility)")
			item.add_button(0, preload("res://resources/Images/ActorIcons/ChildrenLinked.svg") if actor.link_timeline_children else preload("res://resources/Images/ActorIcons/ChildrenUnlinked.svg"),
				2, false, "Unlink child clip movement and trimming" if actor.link_timeline_children else "Link child clip movement and trimming")
		item.set_tooltip_text(0, model.actor_path(actor.id))
		item.collapsed = bool(collapsed.get(actor.id, false))
		var definition := registry.get_definition(actor.type_id) if registry != null else null
		if definition != null and definition.icon != null:
			item.set_icon(0, definition.icon)
			item.set_icon_max_width(0, 20)
		_items[actor.id] = item
		_add_children(item, actor.id, children, collapsed, visited.duplicate())


func _input(event: InputEvent) -> void:
	# Handle editing shortcuts before Tree's built-in search/navigation consumes
	# the key, but never while a section-name LineEdit owns keyboard focus.
	if has_focus() and event is InputEventKey and model != null:
		var editor := get_tree().get_first_node_in_group("actor_timeline_editors") as ActorTimelineEditor
		if editor != null and editor.model == model:
			editor.handle_actor_shortcut(event)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and model != null:
		var editor := get_tree().get_first_node_in_group("actor_timeline_editors") as ActorTimelineEditor
		if editor != null and editor.model == model and editor.handle_actor_shortcut(event):
			accept_event()
		return
	if event is InputEventMouseButton and event.pressed:
		FocusableKeyInput.current_focused_instance = null
	if model == null or _rebuilding or not event is InputEventMouseButton or not event.pressed:
		return
	var item := get_item_at_position(event.position)
	var actor_id := str(item.get_metadata(0)) if item != null else ""
	var clip := model.clip_for_actor_id(actor_id)
	if event.button_index == MOUSE_BUTTON_LEFT and actor_id.begins_with("section:"):
		model.select_section(actor_id.trim_prefix("section:"))
		_selection_anchor = ""
		return
	if event.button_index == MOUSE_BUTTON_LEFT and clip != null:
		if model.actor_for_id(actor_id).section_id != model.selected_section_id:
			model.select_section(model.actor_for_id(actor_id).section_id)
		if event.shift_pressed:
			_select_range(actor_id)
		elif event.ctrl_pressed:
			model.select(clip.id, true)
			_selection_anchor = actor_id
		else:
			# Match timeline dragging: pressing an actor already in the selection
			# keeps the group intact and only makes this actor primary.
			model.select(clip.id, model.is_selected(clip.id))
			_selection_anchor = actor_id
	elif event.button_index == MOUSE_BUTTON_RIGHT and clip != null:
		model.select(clip.id, model.is_selected(clip.id))
		_selection_anchor = actor_id
		var timeline := get_tree().get_first_node_in_group("actor_timeline_editors") as ActorTimelineEditor
		if timeline != null:
			timeline._show_context_menu(event.global_position, true, clip.start_time, clip.layer)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT and (item == get_root() or actor_id.begins_with("section:")):
		if actor_id.begins_with("section:"):
			model.select_section(actor_id.trim_prefix("section:"))
		var timeline := get_tree().get_first_node_in_group("actor_timeline_editors") as ActorTimelineEditor
		if timeline != null:
			timeline._show_context_menu(event.global_position, false, timeline.canvas.playhead,
				timeline.model.selected_layer, item.get_text(0) if actor_id.begins_with("section:") else "SCENE",
				actor_id.trim_prefix("section:") if actor_id.begins_with("section:") else "")
		accept_event()


func _select_range(clicked_actor_id: String) -> void:
	var visible_ids := _visible_actor_ids()
	var anchor := visible_ids.find(_selection_anchor)
	var clicked := visible_ids.find(clicked_actor_id)
	if anchor < 0 or clicked < 0:
		var clip := model.clip_for_actor_id(clicked_actor_id)
		if clip != null:
			model.select(clip.id)
		_selection_anchor = clicked_actor_id
		return
	var first := mini(anchor, clicked)
	var last := maxi(anchor, clicked)
	var clip_ids: Array[String] = []
	for index in range(first, last + 1):
		var clip := model.clip_for_actor_id(visible_ids[index])
		if clip != null:
			clip_ids.append(clip.id)
	var primary := model.clip_for_actor_id(clicked_actor_id)
	model.set_selection(clip_ids, primary.id if primary != null else "")


func _visible_actor_ids() -> Array[String]:
	var result: Array[String] = []
	var item := get_root().get_next_visible() if get_root() != null else null
	while item != null:
		var actor_id := str(item.get_metadata(0))
		if model.actor_for_id(actor_id) != null and model.actor_for_id(actor_id).section_id == model.selected_section_id:
			result.append(actor_id)
		item = item.get_next_visible()
	return result


func _get_drag_data(at_position: Vector2) -> Variant:
	var item := get_item_at_position(at_position)
	var actor_id := str(item.get_metadata(0)) if item != null else ""
	if model.actor_for_id(actor_id) == null:
		return null
	var preview := Label.new()
	preview.text = "  %s  " % model.actor_for_id(actor_id).display_name
	preview.add_theme_color_override("font_color", Color("eaf8f4"))
	set_drag_preview(preview)
	var actor_ids: Array[String] = [actor_id]
	var clip := model.clip_for_actor_id(actor_id)
	if clip != null and model.is_selected(clip.id):
		actor_ids.clear()
		for selected_actor in model.selected_actors():
			actor_ids.append(selected_actor.id)
	return {"type": "actor_scene_tree", "actor_id": actor_id, "actor_ids": actor_ids}


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if model == null or not data is Dictionary or data.get("type") != "actor_scene_tree":
		return false
	var item := get_item_at_position(at_position)
	if item == null:
		return false
	var parent_id := str(item.get_metadata(0))
	if parent_id.begins_with("section:"):
		return model.section_for_id(parent_id.trim_prefix("section:")) != null
	var actor_ids: Array = data.get("actor_ids", [str(data.get("actor_id", ""))])
	if actor_ids.has(parent_id):
		return false
	for child_id in actor_ids:
		if str(child_id) == parent_id or not model.can_set_parent(str(child_id), parent_id):
			return false
	return true


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if not _can_drop_data(at_position, data):
		return
	var item := get_item_at_position(at_position)
	var parent_id := str(item.get_metadata(0))
	var actor_ids: Array[String] = []
	for actor_id in data.get("actor_ids", [str(data.actor_id)]):
		actor_ids.append(str(actor_id))
	if parent_id.begins_with("section:"):
		model.move_to_section(actor_ids, parent_id.trim_prefix("section:"))
	elif parent_id.is_empty():
		model.unparent_many(actor_ids)
	elif actor_ids.size() == 1:
		model.set_parent(actor_ids[0], parent_id)
	else:
		model.parent_many(actor_ids, parent_id)


func _apply_theme() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("131c27")
	panel.border_color = Color("33485c")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(7)
	panel.content_margin_left = 5
	panel.content_margin_right = 5
	panel.content_margin_top = 5
	panel.content_margin_bottom = 5
	add_theme_stylebox_override("panel", panel)
	var selected := StyleBoxFlat.new()
	selected.bg_color = Color("245b5b")
	selected.border_color = Color("72cfb8")
	selected.set_border_width_all(1)
	selected.set_corner_radius_all(5)
	add_theme_stylebox_override("selected", selected)
	add_theme_stylebox_override("selected_focus", selected)
	var hover := selected.duplicate() as StyleBoxFlat
	hover.bg_color = Color("263b4b")
	hover.border_color = Color("49677f")
	add_theme_stylebox_override("hovered", hover)
	add_theme_color_override("font_color", Color("cedbe7"))
	add_theme_color_override("font_selected_color", Color.WHITE)
	add_theme_constant_override("v_separation", 5)
	add_theme_constant_override("h_separation", 7)
