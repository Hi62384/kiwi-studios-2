extends Panel


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
@onready var extra_file_ui: FileSystemExtraUi = $FileActions
@onready var file_mover: FileMover = $FileMover
@onready var file_search_line_edit: LineEdit = $VBoxContainer/HBoxContainer/LineEdit
@onready var file_system_actions: FileSystemCallableActions = $FileSystemActions

var _expanded_folders: Array[String]
var _ordered_expandable_buttons: Array[ExpandableButton]
var _filtered_files_to_display: Array[String]



func _ready() -> void:
	LocalProjectFilesystem.node.file_tree_recreated.connect(update_filesystem_display)
	file_search_line_edit.text_changed.connect(func(_text):
		update_filesystem_display()
		)
	


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
	
	_style_expandable_button(
		expandable_button,
		root_folder.path.get_file(),
		FileOperations.get_file_thumbnail(root_folder.path)
	)
	
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
		
		_style_expandable_button(
			child_expandable_button,
			file.path.get_file(),
			FileOperations.get_file_thumbnail(file.path),
			file is LocalProjectFilesystem.Folder
		)
		
		if file is LocalProjectFilesystem.Folder:
			#if file_search_line_edit.text != ""
			update_folder_display(file, child_expandable_button)
		else:
			_setup_file_expandable_button(file, child_expandable_button)



#setups folder expandable button
func _setup_folder_expandable_button(folder: LocalProjectFilesystem.Folder, button: ExpandableButton) -> void:
	button.set_meta("path", folder.path)
	
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
	
	button.get_main_button().mouse_entered.connect(file_mover.set_hovered_expandable_button.bind(button))
	button.get_main_button().mouse_exited.connect(file_mover.set_hovered_expandable_button.bind(null))
	button.get_main_button().pressed.connect(file_pressed.bind(button))
	button.get_main_button().gui_input.connect(func(event):
		_connect_expandable_button_right_click(event, file_right_clicked, button)
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
	if Input.is_action_pressed("left_click"): 
		file_mover.start_moving_selected_files()
	elif clicked_already_selected_file and expandable_button != null:
		files_selector.handle_input_for_clicked_file(expandable_button)
	



func file_right_clicked(expandable_button: ExpandableButton) -> void:
	files_selector.handle_input_for_right_clicked_file(expandable_button)
	extra_file_ui.display_operations(expandable_button)



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
