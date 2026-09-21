class_name ActorSceneExportButton
extends Button
## Scene-level MP4 export panel. The duration belongs to the editable scene.

const SceneExporter = preload("res://scripts/actors/core/actor_scene_exporter.gd")

var timeline: ActorTimelineEditor
var panel: PanelContainer
var overlay_layer: CanvasLayer
var duration_input: SpinBox
var duration_reset: Button
var resolution_input: OptionButton
var fps_input: OptionButton
var destination_label: Label
var status_label: Label
var export_button: Button
var project_button: Button
var computer_button: Button
var destination := ""
var destination_kind := ""
var busy := false
var _destination_tab := -1


func _ready() -> void:
	timeline = get_node_or_null("../../HSplitContainer/VSplitContainer2/ActorTimeline") as ActorTimelineEditor
	pressed.connect(_open)
	if timeline != null: timeline.model.changed.connect(_sync_duration_ui)
	tooltip_text = "Render the scene from 0 seconds to its video duration"


func _exit_tree() -> void:
	if is_instance_valid(overlay_layer): overlay_layer.queue_free()


func _open() -> void:
	if busy or timeline == null: return
	var tabs := get_node_or_null("../../../../../Tabs") as ActorSceneTabs
	if tabs != null and tabs.current_tab != _destination_tab:
		destination = ""
		destination_kind = ""
		_destination_tab = tabs.current_tab
	if is_instance_valid(overlay_layer): overlay_layer.queue_free()
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 100
	get_tree().root.add_child(overlay_layer)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.06, 0.09, 0.68)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay_layer.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size.x = 500
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	panel.add_theme_stylebox_override("panel", _style(Color("111b27"), Color("527183"), 14))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 460
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var top_row := HBoxContainer.new()
	column.add_child(top_row)
	var kicker := Label.new()
	kicker.text = "VIDEO EXPORT"
	kicker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kicker.add_theme_color_override("font_color", Color("6cddc4"))
	kicker.add_theme_font_size_override("font_size", 11)
	top_row.add_child(kicker)
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Close export settings"
	close.custom_minimum_size = Vector2(30, 30)
	close.pressed.connect(_close)
	top_row.add_child(close)
	var title := Label.new()
	title.text = "Render this scene"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	var description := Label.new()
	description.text = "The viewport is rendered frame by frame, beginning at 0 s."
	description.add_theme_color_override("font_color", Color("a5bac8"))
	column.add_child(description)
	duration_input = SpinBox.new()
	duration_input.min_value = 0.01
	duration_input.max_value = 86400.0
	duration_input.step = 0.01
	duration_input.suffix = " s"
	duration_input.value = timeline.video_duration
	duration_input.value_changed.connect(func(value: float): timeline.set_video_duration(value))
	var duration_row := HBoxContainer.new()
	duration_row.add_theme_constant_override("separation", 10)
	column.add_child(duration_row)
	var duration_label := Label.new()
	duration_label.text = "Video duration"
	duration_label.custom_minimum_size.x = 150
	duration_row.add_child(duration_label)
	duration_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	duration_input.tooltip_text = "Automatically follows the rightmost actor unless changed"
	duration_row.add_child(duration_input)
	duration_reset = _button("↻", false)
	duration_reset.custom_minimum_size = Vector2(38, 35)
	duration_reset.size_flags_horizontal = Control.SIZE_SHRINK_END
	duration_reset.tooltip_text = "Use the rightmost actor's end time again"
	duration_reset.pressed.connect(func(): timeline.reset_video_duration())
	duration_row.add_child(duration_reset)
	_sync_duration_ui()
	resolution_input = OptionButton.new()
	for label in ["HD · 1280 × 720", "Full HD · 1920 × 1080", "4K · 3840 × 2160"]:
		resolution_input.add_item(label)
	resolution_input.select(1)
	_field(column, "Resolution", resolution_input)
	fps_input = OptionButton.new()
	for fps in [24, 30, 60]: fps_input.add_item("%d fps" % fps, fps)
	fps_input.select(1)
	_field(column, "Frame rate", fps_input)
	var path_header := Label.new()
	path_header.text = "SAVE VIDEO TO"
	path_header.add_theme_color_override("font_color", Color("8da9ba"))
	path_header.add_theme_font_size_override("font_size", 11)
	column.add_child(path_header)
	var path_row := HBoxContainer.new()
	path_row.add_theme_constant_override("separation", 8)
	column.add_child(path_row)
	project_button = _button("Project files", false)
	project_button.pressed.connect(_choose_project)
	path_row.add_child(project_button)
	computer_button = _button("Anywhere…", false)
	computer_button.pressed.connect(_choose_external)
	path_row.add_child(computer_button)
	_update_destination_buttons()
	destination_label = Label.new()
	destination_label.text = "No location selected"
	destination_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	destination_label.custom_minimum_size.y = 44
	destination_label.add_theme_color_override("font_color", Color("afc5d1"))
	column.add_child(destination_label)
	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_color_override("font_color", Color("72dec7"))
	column.add_child(status_label)
	_set_destination(destination)
	export_button = _button("Export MP4", true)
	export_button.custom_minimum_size.y = 42
	export_button.pressed.connect(_export)
	column.add_child(export_button)


func _close() -> void:
	if is_instance_valid(overlay_layer): overlay_layer.queue_free()
	overlay_layer = null
	panel = null


func _field(parent: VBoxContainer, label_text: String, control: Control, hint: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 150
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	if not hint.is_empty(): control.tooltip_text = hint


func _choose_project() -> void:
	var suggested := "Scene"
	var tabs := get_node_or_null("../../../../../Tabs") as ActorSceneTabs
	if tabs != null: suggested = tabs.current_scene_name()
	var result := await ActorProjectResourceSaveDialog.pick(self, "Export video to project",
		suggested, "mp4", false)
	if not result.get("cancelled", true):
		_set_destination(str(result.get("path", "")), "project")


func _choose_external() -> void:
	var picker := FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	picker.use_native_dialog = true
	picker.add_filter("*.mp4", "MP4 video")
	picker.title = "Export video"
	add_child(picker)
	picker.file_selected.connect(func(path: String):
		_set_destination(path, "anywhere")
		picker.queue_free())
	picker.canceled.connect(func():
		picker.queue_free())
	picker.popup_centered(Vector2i(900, 600))


func _set_destination(path: String, kind: String = "") -> void:
	destination = path
	if path.is_empty(): destination_kind = ""
	elif not kind.is_empty(): destination_kind = kind
	_update_destination_buttons()
	if not is_instance_valid(destination_label): return
	destination_label.text = "No location selected" if path.is_empty() else "✓  " + path.get_file() + "\n" + path.get_base_dir()
	destination_label.tooltip_text = path
	if is_instance_valid(status_label):
		status_label.text = "" if path.is_empty() else "Ready to export to the selected location."


func _update_destination_buttons() -> void:
	_style_destination_button(project_button, "Project files", destination_kind == "project")
	_style_destination_button(computer_button, "Anywhere…", destination_kind == "anywhere")


func _style_destination_button(button: Button, label: String, selected: bool) -> void:
	if not is_instance_valid(button): return
	button.text = ("✓  " if selected else "") + label
	button.add_theme_stylebox_override("normal", _style(
		Color("20544e") if selected else Color("223346"),
		Color("68ddc5") if selected else Color("456174"), 8))
	button.add_theme_stylebox_override("hover", _style(
		Color("327468") if selected else Color("34516a"), Color("9af1db"), 8))
	button.add_theme_color_override("font_color", Color("d6fff5") if selected else Color("dce9f2"))


func _sync_duration_ui() -> void:
	if is_instance_valid(duration_input):
		duration_input.set_value_no_signal(timeline.video_duration)
	if is_instance_valid(duration_reset):
		duration_reset.visible = timeline.video_duration_is_custom()


func _export() -> void:
	if busy: return
	if destination.is_empty():
		status_label.text = "Choose a save location first."
		return
	if FileAccess.file_exists(destination):
		var confirm := ConfirmationDialog.new()
		confirm.title = "Replace exported video?"
		confirm.dialog_text = "This will replace %s." % destination.get_file()
		add_child(confirm)
		confirm.confirmed.connect(func():
			confirm.queue_free()
			_render_to_destination())
		confirm.canceled.connect(confirm.queue_free)
		confirm.popup_centered()
		return
	_render_to_destination()


func _render_to_destination() -> void:
	busy = true
	export_button.disabled = true
	var dimensions := [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(3840, 2160)]
	var size: Vector2i = dimensions[resolution_input.selected]
	var error: String = await SceneExporter.render(timeline, destination, size.x, size.y,
		fps_input.get_selected_id(), _progress)
	busy = false
	export_button.disabled = false
	if error.is_empty():
		status_label.text = "Exported · " + destination.get_file()
		if LocalProjectFilesystem.node != null: LocalProjectFilesystem.update_root_folder()
	else:
		status_label.text = error
		push_warning(error)


func _progress(done: int, total: int, stage: String) -> void:
	if not is_instance_valid(status_label): return
	status_label.text = "%s · %d / %d frames" % [stage, done, total]


func _button(label_text: String, accent: bool) -> Button:
	var button := Button.new()
	button.text = label_text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 35
	button.add_theme_stylebox_override("normal", _style(Color("20544e") if accent else Color("223346"), Color("68ddc5") if accent else Color("456174"), 8))
	button.add_theme_stylebox_override("hover", _style(Color("327468") if accent else Color("34516a"), Color("9af1db"), 8))
	return button


func _style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style
