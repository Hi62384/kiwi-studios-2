class_name ActorPicker
extends PopupPanel
signal actor_chosen(index: int)
var definitions: Array[ActorDefinition] = []
var search: LineEdit
var cards: VBoxContainer
var category: String = "All"
var location_label: Label
var result_label: Label
var _matches: Array[int] = []
var expanded: Dictionary = {}


func setup(types: Array[ActorDefinition]) -> void:
	definitions = types
	add_theme_stylebox_override("panel", _box(Color("101923"), Color("496579"), 13, 2))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "Add an actor"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Close"
	close.pressed.connect(hide)
	header.add_child(close)
	location_label = Label.new()
	location_label.modulate = Color("91b4c5")
	column.add_child(location_label)
	search = LineEdit.new()
	search.placeholder_text = "Search actors…"
	search.clear_button_enabled = true
	search.custom_minimum_size.y = 38
	column.add_child(search)
	search.text_changed.connect(func(_text: String): rebuild())
	search.text_submitted.connect(func(_text: String):
		if not _matches.is_empty():
			choose(_matches[0]))
	var navigation := HBoxContainer.new()
	column.add_child(navigation)
	result_label = Label.new()
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_label.add_theme_color_override("font_color", Color("829eb2"))
	navigation.add_child(result_label)
	var expand_all := Button.new()
	expand_all.text = "Expand all"
	expand_all.flat = true
	expand_all.pressed.connect(func():
		for definition in definitions: expanded[definition.category] = true
		rebuild())
	navigation.add_child(expand_all)
	var collapse_all := Button.new()
	collapse_all.text = "Collapse all"
	collapse_all.flat = true
	collapse_all.pressed.connect(func():
		for definition in definitions: expanded[definition.category] = false
		rebuild())
	navigation.add_child(collapse_all)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 330)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	cards = VBoxContainer.new()
	cards.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cards.add_theme_constant_override("separation", 8)
	scroll.add_child(cards)
	rebuild()


func open(layer: int, time: float) -> void:
	category = "All"
	location_label.text = "LAYER %d    /    %.2f s" % [layer + 1, time]
	search.text = ""
	rebuild()
	popup_centered(Vector2i(620, 600))
	search.grab_focus()


func rebuild() -> void:
	for child in cards.get_children():
		cards.remove_child(child)
		child.queue_free()
	_matches.clear()
	var groups: Dictionary = {}
	for index in definitions.size():
		var definition := definitions[index]
		if category != "All" and category != definition.category:
			continue
		if not search.text.strip_edges().is_empty() and not (definition.display_name + " " + definition.description + " " + definition.category).to_lower().contains(search.text.strip_edges().to_lower()):
			continue
		_matches.append(index)
		if not groups.has(definition.category):
			var section := VBoxContainer.new()
			cards.add_child(section)
			var header := Button.new()
			header.alignment = HORIZONTAL_ALIGNMENT_LEFT
			header.toggle_mode = true
			header.button_pressed = expanded.get(definition.category, definition.category in ["Shapes", "Text"]) or not search.text.is_empty()
			header.custom_minimum_size.y = 38
			header.text = ("▾  " if header.button_pressed else "▸  ") + _category_symbol(definition.category) + "  " + definition.category + "    %d" % _category_count(definition.category)
			header.add_theme_color_override("font_color", Color("85d9c0"))
			section.add_child(header)
			var body := VBoxContainer.new()
			body.add_theme_constant_override("separation", 6)
			body.visible = header.button_pressed
			section.add_child(body)
			groups[definition.category] = body
			var group_name := definition.category
			header.toggled.connect(func(value: bool):
				expanded[group_name] = value
				body.visible = value
				header.text = ("▾  " if value else "▸  ") + _category_symbol(group_name) + "  " + group_name + "    %d" % _category_count(group_name))
		var card := Button.new()
		card.name = "Actor_" + str(definition.type_id)
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.custom_minimum_size.y = 58
		card.add_theme_font_size_override("font_size", 13)
		var accent: Color = {"Shapes": Color("85d9c0"), "Text": Color("bfa4ed"), "Media": Color("83cddd"), "Lighting": Color("efc47f"), "Utilities": Color("8fbcef"), "Video": Color("e48da8")}.get(definition.category, Color("aebfcc"))
		var style := StyleBoxFlat.new()
		style.bg_color = Color("253345")
		style.border_color = accent
		style.border_width_left = 3
		style.set_corner_radius_all(7)
		card.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = Color("344c60")
		card.add_theme_stylebox_override("hover", hover)
		var icon := TextureRect.new()
		icon.texture = definition.icon
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(icon)
		icon.position = Vector2(14, 14)
		var title := Label.new()
		title.text = definition.display_name + "   /   " + definition.category
		title.add_theme_font_size_override("font_size", 15)
		title.modulate = accent
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(title)
		title.position = Vector2(76, 10)
		var description := Label.new()
		description.text = definition.description
		description.add_theme_font_size_override("font_size", 12)
		description.modulate = Color("bdcddd")
		description.mouse_filter = Control.MOUSE_FILTER_IGNORE
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(description)
		description.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		description.offset_left = 76
		description.offset_right = -16
		description.offset_top = 34
		description.offset_bottom = -6
		card.pressed.connect(choose.bind(index))
		(groups[definition.category] as VBoxContainer).add_child(card)
	if _matches.is_empty():
		var empty := Label.new()
		empty.text = "No matching actors. Try another search or category."
		cards.add_child(empty)
	result_label.text = "%d actor%s  •  Enter adds the first match" % [_matches.size(), "" if _matches.size() == 1 else "s"]


func _category_count(category_name: String) -> int:
	var count := 0
	var query := search.text.strip_edges().to_lower() if search != null else ""
	for definition in definitions:
		if definition.category != category_name:
			continue
		if query.is_empty() or (definition.display_name + " " + definition.description + " " + definition.category).to_lower().contains(query):
			count += 1
	return count


func _category_symbol(category_name: String) -> String:
	return {"Shapes": "◇", "Text": "T", "Media": "▣", "Lighting": "☀", "Utilities": "⌁", "Video": "▶"}.get(category_name, "•")


func _box(color: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style


func choose(index: int) -> void:
	hide()
	actor_chosen.emit(index)
