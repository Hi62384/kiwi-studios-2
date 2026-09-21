extends "res://scripts/Extra/editor_settings_button.gd"
signal recording_requested(options: Dictionary, target: Dictionary)
var is_recording: Callable
var stop_recording: Callable

func _ready() -> void:
	pressed.connect(func():
		if is_recording.is_valid() and is_recording.call(): stop_recording.call()
		else: open_settings())

func _add_capture_options(column: VBoxContainer) -> void:
	var heading := Label.new()
	heading.text = "SCREEN CAPTURE"
	column.add_child(heading)
	var targets := ActorScreenRecorder.targets()
	var filtered: Array[Dictionary] = []
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	var selector := OptionButton.new()
	selector.name = "CaptureTarget"
	selector.custom_minimum_size.x = 300
	selector.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(selector)
	var note := Label.new()
	note.text = "Keep the selected browser tab visible while recording."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 300
	note.add_theme_font_size_override("font_size", 11)
	note.modulate = Color("8fb5b1")
	note.hide()
	column.add_child(note)
	var group := ButtonGroup.new()
	for category in ["Entire display", "Windows"]:
		var tab := Button.new()
		tab.text = category
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.custom_minimum_size.y = 34
		var style := StyleBoxFlat.new()
		style.bg_color = Color("24423f")
		style.border_color = Color("78d9c4")
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		tab.add_theme_stylebox_override("pressed", style)
		tabs.add_child(tab)
		tab.pressed.connect(func():
			selector.clear()
			filtered.clear()
			for target in targets:
				if target.get("category", "Entire display") == category:
					filtered.append(target)
					selector.add_item(target.label)
			selector.disabled = filtered.is_empty()
			if filtered.is_empty(): selector.add_item("No available sources")
			note.visible = category != "Entire display"
			note.text = "Keep the selected window visible and uncovered during capture.")
	(tabs.get_child(0) as Button).button_pressed = true
	(tabs.get_child(0) as Button).pressed.emit()
	var resolution := OptionButton.new()
	resolution.name = "CaptureResolution"
	resolution.add_item("Native resolution · original pixels", 0)
	for height in [720, 1080, 1440, 2160]: resolution.add_item(str(height) + "p · preserve aspect ratio", height)
	column.add_child(resolution)
	var fps := OptionButton.new()
	for value in [24, 30, 60]: fps.add_item(str(value) + " fps", value)
	fps.select(1)
	column.add_child(fps)
	var cursor := CheckBox.new()
	cursor.text = "Include mouse pointer"
	cursor.button_pressed = true
	column.add_child(cursor)
	var start := Button.new()
	start.text = "● Start screen recording"
	column.add_child(start)
	start.pressed.connect(func():
		if filtered.is_empty(): return
		var options := preferences.duplicate()
		options.screen_fps = fps.get_selected_id()
		options.screen_resolution = resolution.get_selected_id()
		options.screen_cursor = cursor.button_pressed
		popup.hide()
		recording_requested.emit(options, filtered[selector.selected]))
