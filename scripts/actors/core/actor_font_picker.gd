class_name ActorFontPicker
extends PopupPanel
## Searchable system-font browser whose rows preview the actual font face.

signal font_chosen(family: String)

var search: LineEdit
var options: VBoxContainer
var result_count: Label
var current_family: String
var families: PackedStringArray


func setup(selected: String) -> void:
	current_family = selected
	families = ActorTextSettings.system_fonts()
	add_theme_stylebox_override("panel", _box(Color("101923"), Color("496579"), 12, 2))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var title := Label.new()
	title.text = "Choose a font"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color("eff7ff"))
	titles.add_child(title)
	result_count = Label.new()
	result_count.add_theme_font_size_override("font_size", 11)
	result_count.add_theme_color_override("font_color", Color("7f9eb3"))
	titles.add_child(result_count)
	var close := Button.new()
	close.text = "×"
	close.custom_minimum_size = Vector2(38, 34)
	close.pressed.connect(hide)
	header.add_child(close)
	search = LineEdit.new()
	search.name = "FontSearch"
	search.placeholder_text = "Search installed fonts…"
	search.clear_button_enabled = true
	search.custom_minimum_size.y = 40
	search.text_changed.connect(_rebuild)
	column.add_child(search)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(430, 350)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	options = VBoxContainer.new()
	options.name = "FontOptions"
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	options.add_theme_constant_override("separation", 4)
	scroll.add_child(options)
	_rebuild("")


func _rebuild(query: String) -> void:
	for child in options.get_children():
		options.remove_child(child)
		child.queue_free()
	var normalized := query.strip_edges().to_lower()
	var count := 0
	for family in families:
		if not normalized.is_empty() and not family.to_lower().contains(normalized):
			continue
		count += 1
		var row := Button.new()
		row.name = "FontOption"
		row.text = ("✓  " if family == current_family else "    ") + family
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size.y = 42
		row.add_theme_font_override("font", ActorTextSettings.font({&"font": family}))
		row.add_theme_font_size_override("font_size", 16)
		row.add_theme_color_override("font_color", Color("eef5fa") if family != current_family else Color("78e1c6"))
		row.add_theme_stylebox_override("normal", _box(Color("17232f"), Color("243746"), 6, 1))
		row.add_theme_stylebox_override("hover", _box(Color("294153"), Color("65d8bd"), 6, 1))
		row.pressed.connect(_choose.bind(family))
		options.add_child(row)
	result_count.text = "%d installed font%s" % [count, "" if count == 1 else "s"]
	if count == 0:
		var empty := Label.new()
		empty.text = "No installed fonts match that search."
		empty.add_theme_color_override("font_color", Color("95aabd"))
		options.add_child(empty)


func _choose(family: String) -> void:
	font_chosen.emit(family)
	hide()


func _box(color: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style
