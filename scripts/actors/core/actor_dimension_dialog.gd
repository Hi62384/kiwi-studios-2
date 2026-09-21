class_name ActorDimensionDialog
extends AcceptDialog
signal choice_made(choice: StringName)
static func choose(owner: Node, asset: String) -> StringName:
	if DisplayServer.get_name() == "headless": return &"3d"
	var dialog := ActorDimensionDialog.new()
	owner.add_child(dialog)
	dialog.build(asset)
	dialog.popup_centered(Vector2i(430, 210))
	var result: StringName = await dialog.choice_made
	dialog.queue_free()
	return result
func build(asset: String) -> void:
	title = "Add to scene"
	get_ok_button().hide()
	canceled.connect(func(): choice_made.emit(&""))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	add_child(column)
	var heading := Label.new()
	heading.text = asset
	heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_theme_font_size_override("font_size", 18)
	column.add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	for dimension in ["2d", "3d"]:
		var button := Button.new()
		button.name = "Choose" + dimension.to_upper()
		button.text = "▣  2D UI\nScreen-space overlay" if dimension == "2d" else "◇  3D Scene\nPosition in the world"
		button.custom_minimum_size = Vector2(190, 90)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var style := StyleBoxFlat.new()
		style.bg_color = Color("243742")
		style.border_color = Color("85d9c0") if dimension == "2d" else Color("bfa4ed")
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		button.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = Color("36525a")
		button.add_theme_stylebox_override("hover", hover)
		row.add_child(button)
		button.pressed.connect(func(): hide(); choice_made.emit(StringName(dimension)))
