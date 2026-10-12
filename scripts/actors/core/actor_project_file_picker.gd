class_name ActorProjectFilePicker
extends PopupPanel
## Generic, read-only asset picker constrained to the loaded project directory.

signal finished(path: String)

## Distinct from Cancel (empty string): the caller must clear its resource slot.
const EMPTY_RESOURCE := "::empty-resource::"

var project_root: String
var allowed_extensions: PackedStringArray
var allowed_raw_extensions: PackedStringArray
var allowed_resource_type: StringName
var accepted_object_types: PackedStringArray
var allowed_native_types: PackedStringArray
var current_directory: String
var selected_path: String = ""
var search: LineEdit
var folders: Tree
var files: ItemList
var breadcrumb: Label
var file_count: Label
var selection_name: Label
var selection_path: Label
var selection_preview: TextureRect
var choose_button: Button
var _resolved: bool = false
var _refresh_generation: int = 0
var _tree_generation: int = 0
var _thumbnail_cache: Dictionary = {}
var _thumbnail_jobs: Array[Dictionary]=[]
var _thumbnail_running:=false
var _indexed_paths: Array[String]=[]
var _scan_ready:=false
var _scan_entries:=0
var _path_match_cache: Dictionary={}


static func pick(owner: Node, property: ActorProperty, title: String = "Choose a project asset") -> String:
	var picker := ActorProjectFilePicker.new()
	owner.add_child(picker)
	picker._build(property, title)
	picker.popup_centered(Vector2i(980, 650))
	picker.search.grab_focus()
	var result: String = await picker.finished
	picker.queue_free()
	return result


static func root_directory() -> String:
	if StaticData.loaded_project != null and not StaticData.loaded_project.resource_path.is_empty():
		return LocalProjectFilesystem.get_project_root_directory().simplify_path()
	return ProjectSettings.globalize_path("res://").simplify_path()


static func is_allowed_path(root: String, path: String, extensions: PackedStringArray) -> bool:
	var normalized_root := root.simplify_path()
	var normalized_path := path.simplify_path()
	var extension_allowed := extensions.is_empty() or extensions.has(normalized_path.get_extension().to_lower())
	return FileOperations.is_path_inside(normalized_root, normalized_path) \
		and FileAccess.file_exists(normalized_path) and extension_allowed


func _build(property: ActorProperty, title_text: String) -> void:
	project_root = root_directory()
	current_directory = project_root
	allowed_extensions = PackedStringArray(property.options.get("extensions", []))
	allowed_raw_extensions = PackedStringArray(property.options.get("raw_extensions", []))
	allowed_resource_type = property.object_type
	accepted_object_types = PackedStringArray(property.options.get("accepted_object_types", [str(allowed_resource_type)]))
	allowed_native_types = PackedStringArray(property.options.get("native_resource_types", []))
	for index in allowed_extensions.size():
		allowed_extensions[index] = allowed_extensions[index].trim_prefix(".").to_lower()
	add_theme_stylebox_override("panel", _box(Color("111923"), Color("466075"), 12, 2))
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
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(mark)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var title_label := Label.new()
	title_label.text = title_text
	title_label.add_theme_font_size_override("font_size", 23)
	title_label.add_theme_color_override("font_color", Color("eff7ff"))
	titles.add_child(title_label)
	var scope := Label.new()
	var formats := "all files" if allowed_extensions.is_empty() else ", ".join(allowed_extensions)
	scope.text = "PROJECT ASSETS  •  %s  •  %s" % [project_root.get_file(), formats]
	scope.add_theme_font_size_override("font_size", 11)
	scope.add_theme_color_override("font_color", Color("7fa0b8"))
	titles.add_child(scope)
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Cancel"
	close.custom_minimum_size = Vector2(42, 38)
	close.pressed.connect(func(): _resolve(""))
	header.add_child(close)

	search = LineEdit.new()
	search.name = "AssetSearch"
	search.placeholder_text = "Search matching files across this project…"
	search.clear_button_enabled = true
	search.custom_minimum_size.y = 42
	search.text_changed.connect(func(_text: String): _refresh_files())
	column.add_child(search)

	var browser_panel := PanelContainer.new()
	browser_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser_panel.add_theme_stylebox_override("panel", _box(Color("17222e"), Color("314457"), 8, 1))
	column.add_child(browser_panel)
	var browser := HSplitContainer.new()
	browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.split_offset = 220
	browser_panel.add_child(browser)

	var folder_column := VBoxContainer.new()
	folder_column.custom_minimum_size.x = 220
	folder_column.add_theme_constant_override("separation", 7)
	browser.add_child(folder_column)
	var folder_heading := Label.new()
	folder_heading.text = "  FOLDERS"
	folder_heading.add_theme_font_size_override("font_size", 11)
	folder_heading.add_theme_color_override("font_color", Color("80dbc4"))
	folder_column.add_child(folder_heading)
	folders = Tree.new()
	folders.name = "ProjectFolders"
	folders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folders.size_flags_vertical = Control.SIZE_EXPAND_FILL
	folders.hide_root = false
	folders.add_theme_stylebox_override("panel", _box(Color("131d27"), Color.TRANSPARENT, 5, 0))
	folders.add_theme_color_override("font_selected_color", Color("ffffff"))
	folders.add_theme_color_override("guide_color", Color("34495a"))
	folders.item_selected.connect(_tree_item_selected)
	folders.item_activated.connect(_tree_item_activated)
	folder_column.add_child(folders)

	var file_column := VBoxContainer.new()
	file_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	file_column.add_theme_constant_override("separation", 7)
	browser.add_child(file_column)
	var file_header := HBoxContainer.new()
	file_column.add_child(file_header)
	breadcrumb = Label.new()
	breadcrumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	breadcrumb.add_theme_color_override("font_color", Color("dbe9f5"))
	file_header.add_child(breadcrumb)
	file_count = Label.new()
	file_count.add_theme_font_size_override("font_size", 11)
	file_count.add_theme_color_override("font_color", Color("7f9bb0"))
	file_header.add_child(file_count)
	files = ItemList.new()
	files.name = "ProjectFiles"
	files.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	files.icon_mode = ItemList.ICON_MODE_TOP
	files.fixed_icon_size = Vector2i(118, 86)
	files.fixed_column_width = 150
	files.same_column_width = true
	files.max_text_lines = 2
	files.allow_reselect = true
	files.add_theme_stylebox_override("panel", _box(Color("101820"), Color.TRANSPARENT, 5, 0))
	files.add_theme_constant_override("h_separation", 10)
	files.add_theme_constant_override("v_separation", 12)
	files.item_selected.connect(_file_selected)
	files.item_activated.connect(func(_index: int): _choose())
	file_column.add_child(files)

	var selection_panel := PanelContainer.new()
	selection_panel.custom_minimum_size.y = 72
	selection_panel.add_theme_stylebox_override("panel", _box(Color("182631"), Color("304759"), 7, 1))
	column.add_child(selection_panel)
	var selection_row := HBoxContainer.new()
	selection_row.add_theme_constant_override("separation", 12)
	selection_panel.add_child(selection_row)
	selection_preview = TextureRect.new()
	selection_preview.custom_minimum_size = Vector2(58, 50)
	selection_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	selection_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	selection_preview.texture = FileOperations.FILE_COLORED_TEXTURE
	selection_row.add_child(selection_preview)
	var selection_text := VBoxContainer.new()
	selection_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selection_row.add_child(selection_text)
	selection_name = Label.new()
	selection_name.text = "No asset selected"
	selection_name.add_theme_color_override("font_color", Color("e8f2fa"))
	selection_text.add_child(selection_name)
	selection_path = Label.new()
	selection_path.text = "Choose a matching file from the project"
	selection_path.clip_text = true
	selection_path.add_theme_font_size_override("font_size", 11)
	selection_path.add_theme_color_override("font_color", Color("7895aa"))
	selection_text.add_child(selection_path)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(func(): _resolve(""))
	selection_row.add_child(cancel)
	var empty:=Button.new()
	empty.text="Proceed empty"
	empty.tooltip_text="Use no resource (null)"
	empty.pressed.connect(func(): _resolve(EMPTY_RESOURCE))
	selection_row.add_child(empty)
	choose_button = Button.new()
	choose_button.text = "Choose asset"
	choose_button.disabled = true
	choose_button.custom_minimum_size.x = 125
	choose_button.pressed.connect(_choose)
	selection_row.add_child(choose_button)
	file_count.text="Scanning project…"
	search.editable=false
	_rebuild_folders.call_deferred()


func _rebuild_folders() -> void:
	_tree_generation += 1
	folders.clear()
	var scan: Dictionary = await _scan_directory(project_root)
	if _resolved: return
	var root_item := folders.create_item()
	root_item.set_text(0, "%s  (%d)" % [project_root.get_file(), int(scan.count)])
	root_item.set_icon(0, FileOperations.FOLDER_COLORED_TEXTURE)
	root_item.set_icon_max_width(0, 18)
	root_item.set_metadata(0, project_root)
	root_item.set_meta("is_file", false)
	root_item.set_collapsed(false)
	_populate_tree(root_item, scan)
	_scan_ready=true; search.editable=true
	folders.set_selected(root_item, 0)
	_refresh_files()


func _scan_directory(directory: String) -> Dictionary:
	var matching_files: Array[String] = []
	var child_folders: Array[Dictionary] = []
	var file_names := Array(DirAccess.get_files_at(directory))
	file_names.sort()
	for file_name: String in file_names:
		if _resolved: break
		_scan_entries+=1
		if _scan_entries%16==0: await get_tree().process_frame
		var path := directory.path_join(file_name).simplify_path()
		if _path_allowed(path):
			matching_files.append(path)
			_indexed_paths.append(path)
	var folder_names := Array(DirAccess.get_directories_at(directory))
	folder_names.sort()
	for folder_name: String in folder_names:
		if _resolved: break
		if folder_name.begins_with("."):
			continue
		var access:=DirAccess.open(directory)
		if access!=null and access.is_link(folder_name): continue
		var child_scan: Dictionary = await _scan_directory(directory.path_join(folder_name).simplify_path())
		if int(child_scan.count) > 0:
			child_folders.append(child_scan)
	var total := matching_files.size()
	for child_scan: Dictionary in child_folders:
		total += int(child_scan.count)
	return {"path": directory, "files": matching_files, "folders": child_folders, "count": total}


func _populate_tree(parent: TreeItem, scan: Dictionary) -> void:
	for child_scan: Dictionary in scan.folders:
		var path := str(child_scan.path)
		var item := folders.create_item(parent)
		item.set_text(0, "%s  (%d)" % [path.get_file(), int(child_scan.count)])
		item.set_icon(0, FileOperations.FOLDER_COLORED_TEXTURE)
		item.set_icon_max_width(0, 18)
		item.set_metadata(0, path)
		item.set_meta("is_file", false)
		_populate_tree(item, child_scan)
	for path: String in scan.files:
		var item := folders.create_item(parent)
		item.set_text(0, path.get_file())
		item.set_icon(0, FileOperations.FILE_COLORED_TEXTURE)
		item.set_icon_max_width(0, 20)
		item.set_metadata(0, path)
		item.set_meta("is_file", true)
		_load_tree_thumbnail(path, item, _tree_generation)


func _tree_item_selected() -> void:
	var item := folders.get_selected()
	if item == null:
		return
	var path := str(item.get_metadata(0)).simplify_path()
	if item.get_meta("is_file", false):
		_select_asset(path, item.get_icon(0))
		for index in files.item_count:
			if str(files.get_item_metadata(index)) == path:
				files.select(index)
				files.ensure_current_is_visible()
				break
		return
	if not FileOperations.is_path_inside(project_root, path) or not DirAccess.dir_exists_absolute(path):
		return
	current_directory = path
	if search.text.is_empty():
		_refresh_files()
	else:
		search.text = ""


func _tree_item_activated() -> void:
	var item := folders.get_selected()
	if item != null and item.get_meta("is_file", false):
		_choose()


func _refresh_files() -> void:
	if files == null or not _scan_ready or _resolved:
		return
	_refresh_generation += 1
	var generation := _refresh_generation
	files.clear()
	selected_path = ""
	choose_button.disabled = true
	selection_preview.texture = FileOperations.FILE_COLORED_TEXTURE
	selection_name.text = "No asset selected"
	selection_path.text = "Choose a matching file from the project"
	var paths: Array[String] = []
	var query := search.text.strip_edges().to_lower()
	for path in _indexed_paths:
		if query.is_empty():
			if FileOperations.is_path_inside(current_directory,path): paths.append(path)
		elif path.get_file().to_lower().contains(query): paths.append(path)
	paths.sort()
	for path: String in paths:
		var display := path.get_file()
		var relative_folder := _relative_to_project(path).get_base_dir()
		if relative_folder != ".":
			display += "\n" + relative_folder
		files.add_item(display, FileOperations.FILE_COLORED_TEXTURE)
		var index := files.item_count - 1
		files.set_item_metadata(index, path)
		_load_thumbnail(path, index, generation)
	breadcrumb.text = "Project" if current_directory == project_root else "Project  /  " + _relative_to_project(current_directory).replace("/", "  /  ")
	file_count.text = "%d matching file%s" % [paths.size(), "" if paths.size() == 1 else "s"]
	if paths.is_empty():
		files.add_item("No matching files in this folder")
		files.set_item_disabled(0, true)


func _collect_files(directory: String, result: Array[String], recursive: bool, query: String = "") -> void:
	for file_name: String in DirAccess.get_files_at(directory):
		var path := directory.path_join(file_name).simplify_path()
		if _path_allowed(path) and (query.is_empty() or file_name.to_lower().contains(query)):
			result.append(path)
	if recursive:
		for folder_name: String in DirAccess.get_directories_at(directory):
			if not folder_name.begins_with("."):
				_collect_files(directory.path_join(folder_name), result, true, query)


func _load_thumbnail(path: String, index: int, generation: int) -> void:
	_thumbnail_jobs.append({"path":path,"index":index,"generation":generation})


func _load_tree_thumbnail(path: String, item: TreeItem, generation: int) -> void:
	_thumbnail_jobs.append({"path":path,"item":item,"generation":generation})

func _process(_delta: float) -> void:
	if _resolved or _thumbnail_running or _thumbnail_jobs.is_empty(): return
	_thumbnail_running=true
	_process_thumbnail(_thumbnail_jobs.pop_front())

func _process_thumbnail(job: Dictionary) -> void:
	var path: String=job.path
	var thumbnail: Texture2D=_thumbnail_cache.get(path)
	if thumbnail==null:
		thumbnail=await FileOperations.get_file_thumbnail(path)
		if thumbnail!=null and maxf(thumbnail.get_width(),thumbnail.get_height())>192:
			var bitmap:=thumbnail.get_image()
			if bitmap!=null:
				var ratio:=192.0/maxi(bitmap.get_width(),bitmap.get_height())
				bitmap.resize(maxi(1,roundi(bitmap.get_width()*ratio)),maxi(1,roundi(bitmap.get_height()*ratio)),Image.INTERPOLATE_BILINEAR)
				thumbnail=ImageTexture.create_from_image(bitmap)
		if thumbnail!=null: _thumbnail_cache[path]=thumbnail
	_thumbnail_running=false
	if _resolved or thumbnail==null: return
	if job.has("item"):
		if job.generation==_tree_generation and is_instance_valid(job.item): job.item.set_icon(0,thumbnail)
	elif job.generation==_refresh_generation and is_instance_valid(files) and job.index<files.item_count and str(files.get_item_metadata(job.index))==path:
		files.set_item_icon(job.index,thumbnail)
		if path==selected_path: selection_preview.texture=thumbnail


func _file_selected(index: int) -> void:
	if index < 0 or index >= files.item_count or files.is_item_disabled(index):
		return
	_select_asset(str(files.get_item_metadata(index)).simplify_path(), files.get_item_icon(index))


func _select_asset(path: String, preview: Texture2D) -> void:
	selected_path = path
	choose_button.disabled = not _path_allowed(selected_path)
	selection_name.text = selected_path.get_file()
	selection_path.text = _relative_to_project(selected_path)
	selection_path.tooltip_text = selected_path
	selection_preview.texture = preview


func _relative_to_project(path: String) -> String:
	var root := project_root.replace("\\", "/").simplify_path().rstrip("/")
	var normalized := path.replace("\\", "/").simplify_path()
	if normalized == root:
		return "."
	if normalized.begins_with(root + "/"):
		return normalized.substr(root.length() + 1)
	return normalized


func _path_allowed(path: String) -> bool:
	if _path_match_cache.has(path): return _path_match_cache[path]
	var result:=_path_allowed_uncached(path)
	_path_match_cache[path]=result
	return result

func _path_allowed_uncached(path: String) -> bool:
	if not is_allowed_path(project_root, path, allowed_extensions):
		return false
	# Image documents embed full layer images. Read their type declaration
	# instead of deserializing every document just to list its filename.
	if path.get_extension().to_lower()=="tres" and allowed_native_types==PackedStringArray(["KiwiImageDocument"]):
		var file:=FileAccess.open(path,FileAccess.READ)
		return file!=null and file.get_line().contains('script_class="KiwiImageDocument"')
	if not allowed_native_types.is_empty() and path.get_extension().to_lower() in ["tres", "res", "mesh"]:
		var load_path := _godot_resource_path(path)
		var native_resource := ResourceLoader.load(load_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		return (allowed_native_types.has("Environment") and native_resource is Environment) \
			or (allowed_native_types.has("Mesh") and native_resource is Mesh) \
			or (allowed_native_types.has("PackedScene") and native_resource is PackedScene) \
			or (allowed_native_types.has("Texture2D") and native_resource is Texture2D) \
			or (allowed_native_types.has("ActorSceneData") and native_resource is ActorSceneData) \
			or (allowed_native_types.has("KiwiImageDocument") and native_resource is KiwiImageDocument) \
			or (native_resource is ActorObjectData and not allowed_resource_type.is_empty() and accepted_object_types.has(str(native_resource.type_id)))
	if allowed_resource_type.is_empty():
		return true
	if allowed_raw_extensions.has(path.get_extension().to_lower()):
		return true
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	if resource == null:
		return false
	return accepted_object_types.has(str(resource.type_id))


func _godot_resource_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	var godot_root := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	var normalized := path.replace("\\", "/")
	if normalized.begins_with(godot_root + "/"):
		return "res://" + normalized.substr(godot_root.length() + 1)
	return path


func _choose() -> void:
	if _path_allowed(selected_path):
		_resolve(selected_path)


func _resolve(path: String) -> void:
	if _resolved:
		return
	_resolved = true
	_thumbnail_jobs.clear()
	finished.emit(path)
	hide()


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
