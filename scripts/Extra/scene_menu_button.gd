class_name ActorSceneMenuButton
extends Button

var current_scene_path: String = ""
var menu: PopupPanel
var path_label: Label
var timeline: ActorTimelineEditor
var scene_tabs: ActorSceneTabs


func _ready() -> void:
	timeline = get_node_or_null("../../HSplitContainer/VSplitContainer2/ActorTimeline") as ActorTimelineEditor
	scene_tabs = get_node_or_null("../../../../../Tabs") as ActorSceneTabs
	pressed.connect(_open_menu)
	tooltip_text = "Save or load an editable scene"


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or not event.ctrl_pressed:
		return
	if event.keycode == KEY_S and event.shift_pressed:
		_save_as()
	elif event.keycode == KEY_S:
		_save()
	elif event.keycode == KEY_O:
		_load()
	else:
		return
	get_viewport().set_input_as_handled()


func _open_menu() -> void:
	if is_instance_valid(menu):
		menu.queue_free()
	menu = PopupPanel.new()
	add_child(menu)
	menu.add_theme_stylebox_override("panel", _box(Color("101a25"), Color("4b6a80"), 12, 2))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	menu.add_child(margin)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 330
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)
	var eyebrow := Label.new()
	eyebrow.text = "EDITABLE SCENE"
	eyebrow.add_theme_font_size_override("font_size", 10)
	eyebrow.add_theme_color_override("font_color", Color("6fdcc1"))
	column.add_child(eyebrow)
	var title := Label.new()
	title.text = "Scene file"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color("eff7ff"))
	column.add_child(title)
	path_label = Label.new()
	var active_path := scene_tabs.current_scene_path() if scene_tabs != null else current_scene_path
	path_label.text = "Not saved yet" if active_path.is_empty() else _relative_path(active_path)
	path_label.clip_text = true
	path_label.tooltip_text = active_path
	path_label.add_theme_color_override("font_color", Color("8da7ba"))
	column.add_child(path_label)
	var separator := HSeparator.new()
	column.add_child(separator)
	_add_action(column, "Save Scene", "Ctrl+S", "Save every actor and editor state", _save)
	_add_action(column, "Save Scene As…", "Ctrl+Shift+S", "Choose a new project location", _save_as)
	_add_action(column, "Load Scene…", "Ctrl+O", "Open a .tres editable scene", _load)
	_add_action(column, "Instantiate Scene…", "", "Add another scene under a linked 3D point", _instantiate_scene)
	menu.popup_hide.connect(func(): if is_instance_valid(menu): menu.queue_free())
	menu.position = Vector2i(global_position + Vector2(0, size.y + 4))
	menu.popup()


func _add_action(parent: VBoxContainer, title: String, shortcut: String, subtitle: String, action: Callable) -> void:
	var button := Button.new()
	button.custom_minimum_size.y = 52
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.text = "  %s\n  %s" % [title, subtitle]
	button.tooltip_text = shortcut
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", Color("edf6ff"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_stylebox_override("normal", _box(Color("182532"), Color("263a4a"), 7, 1))
	button.add_theme_stylebox_override("hover", _box(Color("254052"), Color("65d8bd"), 7, 1))
	button.pressed.connect(func():
		if is_instance_valid(menu): menu.hide()
		action.call())
	parent.add_child(button)


func _save() -> void:
	var active_path := scene_tabs.current_scene_path() if scene_tabs != null else current_scene_path
	if active_path.is_empty():
		await _save_as()
	else:
		_write_scene(active_path)


func _save_as() -> void:
	if timeline == null:
		return
	var active_path := scene_tabs.current_scene_path() if scene_tabs != null else current_scene_path
	var suggested := active_path.get_file().get_basename() if not active_path.is_empty() else (scene_tabs.current_scene_name() if scene_tabs != null else "New Scene")
	var result := await ActorProjectResourceSaveDialog.pick(self, "Save editable scene", suggested, "tres", false)
	if result.get("cancelled", true):
		return
	var path := str(result.get("path", ""))
	if not path.is_empty():
		_write_scene(path)


func _write_scene(path: String) -> void:
	if scene_tabs != null:
		var tab_error := scene_tabs.save_current(path)
		if tab_error != OK:
			push_error("Could not save actor scene '%s' (error %d)." % [path, tab_error])
		return
	var scene := timeline.capture_scene_data() if timeline != null else null
	if scene == null:
		return
	scene.resource_name = path.get_file().get_basename()
	var error := ResourceSaver.save(scene, path)
	if error != OK:
		push_error("Could not save actor scene '%s' (error %d)." % [path, error])
		return
	current_scene_path = path
	if LocalProjectFilesystem.node != null:
		LocalProjectFilesystem.update_root_folder()


func _load() -> void:
	if timeline == null:
		return
	var property := ActorProperty.new()
	property.options = {"extensions": PackedStringArray(["tres"]),
		"native_resource_types": PackedStringArray(["ActorSceneData"])}
	var path := await ActorProjectFilePicker.pick(self, property, "Load editable scene")
	if path.is_empty():
		return
	var scene := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	if scene == null:
		push_error("The chosen file is not an editable actor scene: " + path)
		return
	if scene_tabs != null:
		scene_tabs.open_scene(path)
	else:
		current_scene_path = path
		timeline.restore_scene_data(scene)


func _instantiate_scene() -> void:
	if timeline == null:
		return
	var property := ActorProperty.new()
	property.options = {"extensions": PackedStringArray(["tres"]),
		"native_resource_types": PackedStringArray(["ActorSceneData"])}
	var path := await ActorProjectFilePicker.pick(self, property, "Instantiate a scene")
	if path.is_empty():
		return
	var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	if source != null:
		timeline.model.instantiate_scene(source, timeline.registry.get_definition(&"point_3d"),
			timeline.canvas.playhead, timeline.model.selected_layer, path.get_file().get_basename())


func _relative_path(path: String) -> String:
	var root := ActorProjectFilePicker.root_directory().replace("\\", "/").rstrip("/")
	var normalized := path.replace("\\", "/")
	return "Project / " + normalized.trim_prefix(root + "/")


func _box(color: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style
