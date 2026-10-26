class_name ActorProjectResourceSaveDialog
extends PopupPanel
## Polished, project-scoped Save As browser for editable actor resources.

signal finished(result: Dictionary)

var project_root: String
var selected_directory: String
var extension: String
var format_picker: OptionButton
var folders: Tree
var files: ItemList
var filename: LineEdit
var breadcrumb: Label
var destination: Label
var status: Label
var save_button: Button
var embedded_toggle: CheckButton
var allow_embedded: bool = true
var _resolved: bool = false
var _file_generation: int = 0
var _thumbnail_cache: Dictionary = {}
var clipboard_value: Variant


static func pick(owner: Node, title_text: String, suggested_name: String,
		file_extension: String = "tres", can_embed: bool = true, formats: PackedStringArray = PackedStringArray(), snapshot: Variant=null) -> Dictionary:
	var dialog := ActorProjectResourceSaveDialog.new()
	dialog.clipboard_value=snapshot
	owner.add_child(dialog)
	dialog._build(title_text, suggested_name, file_extension, can_embed, formats)
	dialog.popup_centered(Vector2i(900, 620))
	dialog.filename.grab_focus()
	dialog.filename.select_all()
	var result: Dictionary = await dialog.finished
	dialog.queue_free()
	return result


func _build(title_text: String, suggested_name: String, file_extension: String,
		can_embed: bool = true, formats: PackedStringArray = PackedStringArray()) -> void:
	project_root = ActorProjectFilePicker.root_directory()
	selected_directory = project_root
	extension = file_extension.trim_prefix(".").to_lower()
	allow_embedded = can_embed
	add_theme_stylebox_override("panel", _box(Color("101821"), Color("466075"), 12, 2))
	popup_hide.connect(func():
		if not _resolved:
			_resolve(""))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var mark := ColorRect.new()
	mark.color = Color("58d6bd")
	mark.custom_minimum_size = Vector2(5, 48)
	header.add_child(mark)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color("eff7ff"))
	titles.add_child(title)
	var scope := Label.new()
	scope.text = "SAVE TO PROJECT  •  %s FILES  •  %s" % [extension.to_upper(), project_root.get_file()]
	scope.add_theme_font_size_override("font_size", 11)
	scope.add_theme_color_override("font_color", Color("7fa0b8"))
	titles.add_child(scope)
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Cancel"
	close.custom_minimum_size = Vector2(42, 38)
	close.pressed.connect(func(): _resolve(""))
	header.add_child(close)
	if clipboard_value!=null and KiwiSuperClipboardService.instance!=null:
		var clipboard_row:=HBoxContainer.new(); column.add_child(clipboard_row)
		var clipboard:=Button.new(); clipboard.name="SaveToSuperClipboard"; clipboard.text="Save copy to Super Clipboard"; clipboard_row.add_child(clipboard)
		var folder:=OptionButton.new(); folder.fit_to_longest_item=false; folder.size_flags_horizontal=Control.SIZE_EXPAND_FILL; clipboard_row.add_child(folder)
		var library:=KiwiSuperClipboardService.instance
		for id: String in library.store.data.folders:
			if library.store.folder_valid(id): folder.add_item(str(library.store.data.folders[id].name)); folder.set_item_metadata(folder.item_count-1,id)
		clipboard.pressed.connect(func():
			var value: Variant=clipboard_value.call() if clipboard_value is Callable else clipboard_value
			var id:=library.quick_save(value,filename.text if filename!=null else suggested_name,str(folder.get_selected_metadata()))
			if not id.is_empty(): _resolve({"cancelled":true,"clipboard_saved":id,"embedded":false,"path":""})
			else: status.text=library.store.error; status.add_theme_color_override("font_color",Color("ffab99")))
	var browser_panel := PanelContainer.new()
	browser_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser_panel.add_theme_stylebox_override("panel", _box(Color("17222e"), Color("314457"), 8, 1))
	column.add_child(browser_panel)
	var browser := HSplitContainer.new()
	browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.split_offset = 310
	browser_panel.add_child(browser)
	var tree_column := VBoxContainer.new()
	tree_column.custom_minimum_size.x = 300
	tree_column.add_theme_constant_override("separation", 7)
	browser.add_child(tree_column)
	var tree_heading := Label.new()
	tree_heading.text = "  PROJECT FILESYSTEM"
	tree_heading.add_theme_font_size_override("font_size", 11)
	tree_heading.add_theme_color_override("font_color", Color("80dbc4"))
	tree_column.add_child(tree_heading)
	folders = Tree.new()
	folders.name = "SaveProjectTree"
	folders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folders.size_flags_vertical = Control.SIZE_EXPAND_FILL
	folders.hide_root = false
	folders.add_theme_stylebox_override("panel", _box(Color("131d27"), Color.TRANSPARENT, 5, 0))
	folders.add_theme_color_override("guide_color", Color("34495a"))
	folders.item_selected.connect(_tree_selected)
	folders.item_activated.connect(_tree_activated)
	tree_column.add_child(folders)
	var file_column := VBoxContainer.new()
	file_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	file_column.add_theme_constant_override("separation", 7)
	browser.add_child(file_column)
	breadcrumb = Label.new()
	breadcrumb.add_theme_color_override("font_color", Color("dbe9f5"))
	file_column.add_child(breadcrumb)
	files = ItemList.new()
	files.name = "ExistingResources"
	files.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	files.icon_mode = ItemList.ICON_MODE_TOP
	files.fixed_icon_size = Vector2i(82, 64)
	files.fixed_column_width = 130
	files.same_column_width = true
	files.max_text_lines = 2
	files.add_theme_stylebox_override("panel", _box(Color("101820"), Color.TRANSPARENT, 5, 0))
	files.item_selected.connect(_existing_file_selected)
	files.item_activated.connect(_existing_file_selected)
	file_column.add_child(files)
	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", _box(Color("182631"), Color("304759"), 7, 1))
	column.add_child(footer)
	var footer_column := VBoxContainer.new()
	footer_column.add_theme_constant_override("separation", 7)
	footer.add_child(footer_column)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	footer_column.add_child(name_row)
	var name_label := Label.new()
	name_label.text = "File name"
	name_label.custom_minimum_size.x = 75
	name_row.add_child(name_label)
	filename = LineEdit.new()
	filename.name = "ResourceFilename"
	filename.text = suggested_name.get_basename().validate_filename()
	filename.placeholder_text = "Resource name"
	filename.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filename.text_changed.connect(func(_text: String): _validate())
	filename.text_submitted.connect(func(_text: String): _save())
	name_row.add_child(filename)
	format_picker = OptionButton.new()
	format_picker.name = "SaveFormat"
	if formats.is_empty(): formats = PackedStringArray([extension])
	for format in formats:
		format_picker.add_item("." + format)
		if format == extension: format_picker.select(format_picker.item_count - 1)
	format_picker.disabled = formats.size() == 1
	format_picker.item_selected.connect(func(index: int):
		extension = format_picker.get_item_text(index).trim_prefix(".")
		_validate())
	name_row.add_child(format_picker)
	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 10)
	footer_column.add_child(action_row)
	embedded_toggle = CheckButton.new()
	embedded_toggle.name = "EmbeddedResource"
	embedded_toggle.text = "Embedded resource"
	embedded_toggle.tooltip_text = "Keep this resource inside the actor instead of creating a project file"
	embedded_toggle.visible = allow_embedded
	embedded_toggle.toggled.connect(func(_enabled: bool): _validate())
	action_row.add_child(embedded_toggle)
	var path_column := VBoxContainer.new()
	path_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(path_column)
	destination = Label.new()
	destination.clip_text = true
	destination.add_theme_font_size_override("font_size", 11)
	destination.add_theme_color_override("font_color", Color("9db4c5"))
	path_column.add_child(destination)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 11)
	path_column.add_child(status)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): _resolve(""))
	action_row.add_child(cancel)
	save_button = Button.new()
	save_button.text = "Save resource"
	save_button.custom_minimum_size.x = 135
	save_button.pressed.connect(_save)
	action_row.add_child(save_button)
	_rebuild_tree()
	_refresh_files()
	_validate()


func _rebuild_tree() -> void:
	folders.clear()
	var root_item := folders.create_item()
	root_item.set_text(0, project_root.get_file())
	root_item.set_icon(0, FileOperations.FOLDER_COLORED_TEXTURE)
	root_item.set_icon_max_width(0, 18)
	root_item.set_metadata(0, project_root)
	root_item.set_meta("is_file", false)
	root_item.set_collapsed(false)
	_add_tree_entries(root_item, project_root)
	folders.set_selected(root_item, 0)


func _add_tree_entries(parent: TreeItem, directory: String) -> void:
	var directory_names := Array(DirAccess.get_directories_at(directory))
	directory_names.sort()
	for name: String in directory_names:
		if name.begins_with("."):
			continue
		var path := directory.path_join(name).simplify_path()
		var item := folders.create_item(parent)
		item.set_text(0, name)
		item.set_icon(0, FileOperations.FOLDER_COLORED_TEXTURE)
		item.set_icon_max_width(0, 18)
		item.set_metadata(0, path)
		item.set_meta("is_file", false)
		_add_tree_entries(item, path)
	var file_names := Array(DirAccess.get_files_at(directory))
	file_names.sort()
	for name: String in file_names:
		if name.get_extension().to_lower() != extension:
			continue
		var path := directory.path_join(name).simplify_path()
		var item := folders.create_item(parent)
		item.set_text(0, name)
		item.set_icon(0, FileOperations.FILE_COLORED_TEXTURE)
		item.set_icon_max_width(0, 18)
		item.set_metadata(0, path)
		item.set_meta("is_file", true)


func _tree_selected() -> void:
	var item := folders.get_selected()
	if item == null:
		return
	var path := str(item.get_metadata(0)).simplify_path()
	if item.get_meta("is_file", false):
		_select_existing_path(path)
		return
	if FileOperations.is_path_inside(project_root, path) and DirAccess.dir_exists_absolute(path):
		selected_directory = path
		_refresh_files()
		_validate()


func _tree_activated() -> void:
	var item := folders.get_selected()
	if item != null and item.get_meta("is_file", false):
		_select_existing_path(str(item.get_metadata(0)))


func _refresh_files() -> void:
	if files == null:
		return
	_file_generation += 1
	var generation := _file_generation
	files.clear()
	var paths: Array[String] = []
	for name: String in DirAccess.get_files_at(selected_directory):
		if name.get_extension().to_lower() == extension:
			paths.append(selected_directory.path_join(name).simplify_path())
	paths.sort()
	for path: String in paths:
		files.add_item(path.get_file(), FileOperations.FILE_COLORED_TEXTURE)
		var index := files.item_count - 1
		files.set_item_metadata(index, path)
		_load_thumbnail(path, index, generation)
	if paths.is_empty():
		files.add_item("No .%s resources in this folder" % extension)
		files.set_item_disabled(0, true)
	breadcrumb.text = "Project" if selected_directory == project_root else "Project  /  " + _relative_to_project(selected_directory).replace("/", "  /  ")


func _load_thumbnail(path: String, index: int, generation: int) -> void:
	var thumbnail: Texture2D
	if _thumbnail_cache.has(path):
		thumbnail = _thumbnail_cache[path]
	else:
		thumbnail = await FileOperations.get_file_thumbnail(path)
		if thumbnail != null:
			_thumbnail_cache[path] = thumbnail
	if is_instance_valid(files) and generation == _file_generation and thumbnail != null and index < files.item_count \
			and str(files.get_item_metadata(index)) == path:
		files.set_item_icon(index, thumbnail)


func _existing_file_selected(index: int) -> void:
	if index >= 0 and index < files.item_count and not files.is_item_disabled(index):
		_select_existing_path(str(files.get_item_metadata(index)))


func _select_existing_path(path: String) -> void:
	path = path.simplify_path()
	selected_directory = path.get_base_dir()
	filename.text = path.get_file().get_basename()
	_refresh_files()
	_validate()


func _target_path() -> String:
	var clean := filename.text.strip_edges().validate_filename()
	return selected_directory.path_join(clean + "." + extension).simplify_path()


func _validate() -> void:
	if filename == null or destination == null or status == null or save_button == null:
		return
	var raw_name := filename.text.strip_edges()
	var clean := raw_name.validate_filename()
	var target := _target_path()
	var exists := FileAccess.file_exists(target)
	var embedding := allow_embedded and embedded_toggle != null and embedded_toggle.button_pressed
	filename.editable = not embedding
	folders.mouse_filter = Control.MOUSE_FILTER_IGNORE if embedding else Control.MOUSE_FILTER_STOP
	files.mouse_filter = Control.MOUSE_FILTER_IGNORE if embedding else Control.MOUSE_FILTER_STOP
	folders.modulate = Color(1, 1, 1, 0.42) if embedding else Color.WHITE
	files.modulate = Color(1, 1, 1, 0.42) if embedding else Color.WHITE
	if embedding:
		save_button.disabled = false
		save_button.text = "Use embedded"
		destination.text = "Stored inside this actor"
		destination.tooltip_text = "No project file will be created"
		status.text = "The resource will travel with the actor until you save it later."
		status.add_theme_color_override("font_color", Color("80dbc4"))
		return
	save_button.text = "Save resource"
	var valid := not clean.is_empty() and clean == raw_name \
		and FileOperations.is_path_inside(project_root, target) and not exists
	save_button.disabled = not valid
	destination.text = "Project  /  " + _relative_to_project(target)
	destination.tooltip_text = target
	if exists:
		status.text = "A resource with this name already exists in this folder."
		status.add_theme_color_override("font_color", Color("ff9b91"))
	elif clean.is_empty() or clean != raw_name:
		status.text = "Enter a valid file name."
		status.add_theme_color_override("font_color", Color("ffca80"))
	else:
		status.text = "Ready to save inside the project."
		status.add_theme_color_override("font_color", Color("80dbc4"))


func _save() -> void:
	_validate()
	if not save_button.disabled:
		var embedding := allow_embedded and embedded_toggle != null and embedded_toggle.button_pressed
		_resolve({"cancelled": false, "embedded": embedding, "path": "" if embedding else _target_path()})


func _resolve(result: Variant) -> void:
	if _resolved:
		return
	_resolved = true
	if result is String:
		finished.emit({"cancelled": result.is_empty(), "embedded": false, "path": result})
	else:
		finished.emit(result)
	hide()


func _relative_to_project(path: String) -> String:
	var root := project_root.replace("\\", "/").simplify_path().rstrip("/")
	var normalized := path.replace("\\", "/").simplify_path()
	if normalized == root:
		return "."
	if normalized.begins_with(root + "/"):
		return normalized.substr(root.length() + 1)
	return normalized


func _box(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style
