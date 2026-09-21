extends Panel

signal file_resource_opened(path: String)
signal shader_file_opened(path: String)


const EXPANDABLE_BUTTON = preload("uid://basy0qkxblg2m")
const ExpandableButton = preload("uid://dk22ixmn3cmrb")
const FileSystemFilesSelector = preload("uid://plyim2uw3aj1")
const FileSystemExtraUi = preload("uid://btkxwby3ldicm")
const FileMover = preload("uid://biler6763synl")
const FileSystemCallableActions = preload("uid://b5gm21p0e2sbv")

@export var text_settings: LabelSettings
@export var panel_style: StyleBox

@onready var container: VBoxContainer = $VBoxContainer/Panel/ScrollContainer/VBoxContainer
@onready var files_selector: FileSystemFilesSelector = $FilesSelector
@onready var file_system_extra_ui: FileSystemExtraUi = $FileSystemExtraUI
@onready var file_mover: FileMover = $FileMover
@onready var file_search_line_edit: LineEdit = $VBoxContainer/HBoxContainer/LineEdit
@onready var file_system_callable_actions: FileSystemCallableActions = $FileSystemCallableActions


@onready var undo_button: Button = $VBoxContainer/HBoxContainer/undo_button
@onready var redo_button: Button = $VBoxContainer/HBoxContainer/redo_button

var _expanded_folders: Array[String]
var _ordered_expandable_buttons: Array[ExpandableButton]
var _filtered_files_to_display: Array[String]
var _display_generation := 0



func _ready() -> void:
	LocalProjectFilesystem.node.file_tree_recreated.connect(update_filesystem_display)
	file_search_line_edit.text_changed.connect(func(_text):
		update_filesystem_display()
		)
	
	undo_button.pressed.connect(file_system_callable_actions.undo)
	redo_button.pressed.connect(file_system_callable_actions.redo)



#creates array for _filtered_files_to_display of all individual files/folders that should be filtered
func _recursive_check_for_files_to_filter(file: LocalProjectFilesystem.File) -> void:
	var file_name: String = file.path.get_file()
	var filter_file: bool = file_name.contains(file_search_line_edit.text)
	if filter_file: _filtered_files_to_display.append(file.path)
	
	if file is LocalProjectFilesystem.Folder:
		for child_file: LocalProjectFilesystem.File in file.contains:
			_recursive_check_for_files_to_filter(child_file)



func _should_display_file(file_path: String) -> bool:
	if !_should_filter_files():
		return true
	
	var file_name: String = file_path.get_file()
	if file_name.contains(file_search_line_edit.text):
		_filtered_files_to_display.erase(file_path)
		return true
	
	#if is a folder, check if any filtered files are contained within it
	if file_path.get_extension() == "":
		for filtered_file: String in _filtered_files_to_display:
			if FileOperations.is_path_inside(file_path, filtered_file):
				return true
	
	return false



func _should_filter_files() -> bool:
	return file_search_line_edit.text != ""



func update_filesystem_display() -> void:
	_display_generation += 1
	files_selector.clear_selected()
	NodeOperations.delete_children(container)
	
	var expanded_folders_before: Array[String] = _expanded_folders.duplicate()
	
	var root_folder: LocalProjectFilesystem.Folder = LocalProjectFilesystem.root_folder
	var expandable_button: ExpandableButton = EXPANDABLE_BUTTON.instantiate()
	
	if _should_filter_files():
		_filtered_files_to_display = []
		_recursive_check_for_files_to_filter(root_folder)
	
	_ordered_expandable_buttons = [expandable_button]
	
	container.add_child(expandable_button)
	
	_style_expandable_button(expandable_button, root_folder.path.get_file(), FileOperations.FOLDER_COLORED_TEXTURE)
	_load_button_thumbnail(root_folder.path, expandable_button, _display_generation)
	
	update_folder_display(root_folder, expandable_button)
	
	#remove missing folders from _expanded_folders
	var new_expanded_folders: Array[String]
	for folder_before: String in expanded_folders_before:
		if !_expanded_folders.has(folder_before):
			new_expanded_folders.append(folder_before)
	_expanded_folders = new_expanded_folders



#recursive function to setup expandable buttons inside a folder
func update_folder_display(folder: LocalProjectFilesystem.Folder, expandable_button: ExpandableButton) -> void:
	_setup_folder_expandable_button(folder, expandable_button)
	for file: LocalProjectFilesystem.File in folder.contains:
		if !_should_display_file(file.path): continue
		
		var child_expandable_button: ExpandableButton = EXPANDABLE_BUTTON.instantiate()
		
		_ordered_expandable_buttons.append(child_expandable_button)
		
		expandable_button.add_child_in_expand(child_expandable_button)
		
		_style_expandable_button(child_expandable_button, file.path.get_file(),
			FileOperations.FOLDER_COLORED_TEXTURE if file is LocalProjectFilesystem.Folder else FileOperations.FILE_COLORED_TEXTURE,
			file is LocalProjectFilesystem.Folder)
		_load_button_thumbnail(file.path, child_expandable_button, _display_generation)
		
		if file is LocalProjectFilesystem.Folder:
			#if file_search_line_edit.text != ""
			update_folder_display(file, child_expandable_button)
		else:
			_setup_file_expandable_button(file, child_expandable_button)



func _load_button_thumbnail(path: String, button: Variant, generation: int) -> void:
	var thumbnail: Texture2D = await FileOperations.get_file_thumbnail(path)
	_apply_button_thumbnail(button, thumbnail, generation)

func _apply_button_thumbnail(button: Variant, thumbnail: Texture2D, generation: int) -> void:
	if generation != _display_generation or not is_instance_valid(button) or button.is_queued_for_deletion(): return
	if thumbnail != null: button.icon = thumbnail

#setups folder expandable button
func _setup_folder_expandable_button(folder: LocalProjectFilesystem.Folder, button: ExpandableButton) -> void:
	button.set_meta("path", folder.path)
	var main_button := button.get_main_button() as ProjectFileDragButton
	main_button.accepts_drop = _can_drop_files_on_folder.bind(folder.path)
	main_button.receives_drop = _drop_files_on_folder.bind(folder.path)
	
	#expand if should be expanded
	if _expanded_folders.has(folder.path):
		button.expanded = true
		_expanded_folders.erase(folder.path)
	
	button.toggled.connect(func(on: bool):
				_expandable_button_toggled(folder.path, on))
	
	button.get_main_button().mouse_entered.connect(file_mover.set_hovered_expandable_button.bind(button))
	button.get_main_button().mouse_exited.connect(file_mover.set_hovered_expandable_button.bind(null))
	button.get_main_button().pressed.connect(file_pressed.bind(button))
	button.get_main_button().gui_input.connect(func(event):
		_connect_expandable_button_right_click(event, file_right_clicked, button)
		)


#setups file expandable button
func _setup_file_expandable_button(file: LocalProjectFilesystem.File, button: ExpandableButton) -> void:
	button.set_meta("path", file.path)
	var main_button := button.get_main_button() as ProjectFileDragButton
	main_button.drag_paths_provider = _dragged_file_paths.bind(button)

	main_button.mouse_entered.connect(file_mover.set_hovered_expandable_button.bind(button))
	main_button.mouse_exited.connect(file_mover.set_hovered_expandable_button.bind(null))
	main_button.pressed.connect(file_pressed.bind(button))
	main_button.gui_input.connect(func(event):
		_connect_expandable_button_right_click(event, file_right_clicked, button)
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
			if file.path.get_extension().to_lower() == "gdshader":
				shader_file_opened.emit(file.path)
			else:
				file_resource_opened.emit(file.path)
			get_viewport().set_input_as_handled()
		)



#right click pressed on a expandable button
func _connect_expandable_button_right_click(event, callable: Callable, expandable_button: ExpandableButton) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			callable.call(expandable_button)



func file_pressed(expandable_button: ExpandableButton) -> void:
	var clicked_already_selected_file: bool = false
	
	if files_selector.expandable_button_is_selected(expandable_button):
		clicked_already_selected_file = true
	#if clicked file isnt already selected, handle it normally
	else:
		files_selector.handle_input_for_clicked_file(expandable_button)
	
	#hold file to move it
	await get_tree().create_timer(0.2).timeout
	if not is_instance_valid(expandable_button) or expandable_button.is_queued_for_deletion(): return
	# Files use native GUI drag-and-drop so inspector resource fields can receive
	# them. Folders retain the existing hold gesture.
	if FileAccess.file_exists(str(expandable_button.get_meta("path"))):
		return
	if Input.is_action_pressed("left_click"): 
		file_mover.start_moving_selected_files()
	elif clicked_already_selected_file and expandable_button != null:
		files_selector.handle_input_for_clicked_file(expandable_button)


func _dragged_file_paths(button: ExpandableButton) -> PackedStringArray:
	var paths := PackedStringArray()
	var selected: Array[ExpandableButton] = files_selector.get_expandable_buttons_top_selected_files()
	if not files_selector.expandable_button_is_selected(button):
		paths.append(str(button.get_meta("path")))
		return paths
	for selected_button: ExpandableButton in selected:
		var path := str(selected_button.get_meta("path"))
		if FileAccess.file_exists(path):
			paths.append(path)
	if paths.is_empty():
		paths.append(str(button.get_meta("path")))
	return paths


func _paths_from_drag(data: Variant) -> Array[String]:
	if not data is Dictionary:
		return []
	var values: Variant = data.get("paths", [])
	var paths: Array[String] = []
	if values is PackedStringArray or values is Array:
		for value: Variant in values:
			paths.append(str(value).simplify_path())
	return paths


func _can_drop_files_on_folder(data: Variant, folder_path: String) -> bool:
	var paths := _paths_from_drag(data)
	if paths.is_empty():
		return false
	for path: String in paths:
		if not FileAccess.file_exists(path) or path.get_base_dir().simplify_path() == folder_path.simplify_path():
			return false
	return true


func _drop_files_on_folder(data: Variant, folder_path: String) -> void:
	var paths: Array[String] = _paths_from_drag(data)
	if not paths.is_empty():
		file_system_callable_actions.move_files(folder_path, paths)
	



func file_right_clicked(expandable_button: ExpandableButton) -> void:
	files_selector.handle_input_for_right_clicked_file(expandable_button)
	file_system_extra_ui.display_operations(expandable_button)



func _expandable_button_toggled(file_path: String, on: bool) -> void:
	if on:
		_expanded_folders.append(file_path)
	else:
		_expanded_folders.erase(file_path)



func _style_expandable_button(expndblebton: ExpandableButton, text: String, icon: Texture2D, show_expandable: bool = true) -> void:
	expndblebton.text = text
	expndblebton.icon = icon
	expndblebton.label_settings = text_settings
	expndblebton.panel_stylebox = panel_style
	expndblebton.get_expandable_icon_button().visible = show_expandable
	expndblebton.get_main_button().action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS



func expandable_button_arr_to_path_arr(buttons: Array[ExpandableButton]) -> Array[String]:
	var paths: Array[String]
	for button: ExpandableButton in buttons:
		paths.append(button.get_meta("path"))
	return paths
