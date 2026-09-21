extends Button
## Application preferences, deliberately separate from project undo history.
var popup: PopupPanel
var device: OptionButton
var preferences: Dictionary

func _ready() -> void:
	pressed.connect(open_settings)

func open_settings() -> void:
	preferences = EditorAudioSettings.read()
	if is_instance_valid(popup): popup.queue_free()
	popup = PopupPanel.new()
	add_child(popup)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("15232b")
	panel.border_color = Color("4d867c")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(10)
	panel.content_margin_left = 18
	panel.content_margin_right = 18
	panel.content_margin_top = 16
	panel.content_margin_bottom = 16
	popup.add_theme_stylebox_override("panel", panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	popup.add_child(column)
	var title := Label.new()
	title.text = "Recording options"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("b4f1de"))
	column.add_child(title)
	_add_capture_options(column)
	var heading := Label.new()
	heading.text = "AUDIO SOURCES"
	heading.add_theme_font_size_override("font_size", 11)
	heading.modulate = Color("8fb5b1")
	column.add_child(heading)
	for source in ["record_mic", "record_system"]:
		var enabled := CheckBox.new()
		enabled.name = "RecordMicrophone" if source == "record_mic" else "RecordSystemAudio"
		enabled.text = "Record microphone audio" if source == "record_mic" else "Record system audio"
		enabled.button_pressed = preferences[source]
		column.add_child(enabled)
		enabled.toggled.connect(func(value: bool):
			preferences[source] = value
			EditorAudioSettings.write(preferences))
	var row := HBoxContainer.new()
	column.add_child(row)
	device = OptionButton.new()
	device.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(device)
	var refresh := Button.new()
	refresh.text = "↻"
	refresh.tooltip_text = "Refresh input devices"
	row.add_child(refresh)
	refresh.pressed.connect(_refresh_devices)
	_refresh_devices()
	device.item_selected.connect(func(index: int):
		preferences.device = device.get_item_text(index)
		EditorAudioSettings.write(preferences))
	var gain_row := HBoxContainer.new()
	column.add_child(gain_row)
	var gain_label := Label.new()
	gain_label.text = "Input gain"
	gain_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gain_row.add_child(gain_label)
	var gain := DragNumber.new()
	gain.name = "InputGain"
	gain.min_value = -36
	gain.max_value = 24
	gain.step = 0.01
	gain.suffix = " dB"
	gain.value = preferences.gain_db
	gain.custom_minimum_size.x = 120
	gain_row.add_child(gain)
	gain.value_changed.connect(func(value: float):
		preferences.gain_db = value
		EditorAudioSettings.write(preferences))
	gain.preview_changed.connect(func(value: float): preferences.gain_db = value)
	gain.drag_committed.connect(func(value: float):
		preferences.gain_db = value
		EditorAudioSettings.write(preferences))
	gain.drag_cancelled.connect(func(): preferences.gain_db = gain.value)
	var mono := CheckButton.new()
	mono.text = "Record mono"
	mono.button_pressed = preferences.mono
	column.add_child(mono)
	mono.toggled.connect(func(value: bool):
		preferences.mono = value
		EditorAudioSettings.write(preferences))
	var close := Button.new()
	close.text = "Close"
	column.add_child(close)
	close.pressed.connect(popup.hide)
	popup.size = Vector2i(340, 0)
	popup.position = Vector2i(get_screen_position() + Vector2(0, size.y + 5))
	popup.popup()

func _refresh_devices() -> void:
	device.clear()
	var devices := AudioServer.get_input_device_list()
	if not devices.has("Default"): devices.insert(0, "Default")
	for name in devices:
		device.add_item(name)
		if name == preferences.device: device.select(device.item_count - 1)

func _add_capture_options(_column: VBoxContainer) -> void:
	pass
