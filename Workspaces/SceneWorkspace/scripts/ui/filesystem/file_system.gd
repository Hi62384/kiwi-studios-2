extends Panel


const EXPANDABLE_BUTTON = preload("uid://basy0qkxblg2m")
const ExpandableButton = preload("uid://dk22ixmn3cmrb")
const FileSystemFilesSelector = preload("uid://plyim2uw3aj1")


@export var text_settings: LabelSettings
@export var panel_style: StyleBox

@onready var container: VBoxContainer = $VBoxContainer/Panel/ScrollContainer/VBoxContainer
@onready var files_selector: FileSystemFilesSelector = $FilesSelector

var _expanded_folders: Array[String]
var _ordered_expandable_buttons: Array[ExpandableButton]

func _ready() -> void:
	LocalProjectFilesystem.node.file_tree_recreated.connect(update_filesystem_display)



func update_filesystem_display() -> void:
	NodeOperations.delete_children(container)
	
	var expanded_folders_before: Array[String] = _expanded_folders.duplicate()
	
	var root_folder: LocalProjectFilesystem.Folder = LocalProjectFilesystem.root_folder
	var expandable_button: ExpandableButton = EXPANDABLE_BUTTON.instantiate()
	
	_ordered_expandable_buttons = [expandable_button]
	
	container.add_child(expandable_button)
	
	style_expandable_button(
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
		var child_expandable_button: ExpandableButton = EXPANDABLE_BUTTON.instantiate()
		
		_ordered_expandable_buttons.append(child_expandable_button)
		
		expandable_button.add_child_in_expand(child_expandable_button)
		
		expandable_button.set_meta("path", file.path)
		
		style_expandable_button(
			child_expandable_button,
			file.path.get_file(),
			FileOperations.get_file_thumbnail(file.path),
			file is LocalProjectFilesystem.Folder
		)
		
		if file is LocalProjectFilesystem.Folder:
			update_folder_display(file, child_expandable_button)
		else:
			_setup_file_expandable_button(file, child_expandable_button)



#setups folder expandable button
func _setup_folder_expandable_button(folder: LocalProjectFilesystem.Folder, button: ExpandableButton) -> void:
	#expand if should be expanded
	if _expanded_folders.has(folder.path):
		button.expanded = true
		_expanded_folders.erase(folder.path)
	
	button.toggled.connect(func(on: bool):
				_expandable_button_toggled(folder.path, on))
			
	button.get_main_button().pressed.connect(file_pressed.bind(button))
	button.get_main_button().gui_input.connect(func(event):
		_connect_expandable_button_right_click(event, file_right_clicked, button)
		)


#setups file expandable button
func _setup_file_expandable_button(file: LocalProjectFilesystem.File, button: ExpandableButton) -> void:
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
	files_selector.handle_input_for_clicked_file(expandable_button)



func file_right_clicked(expandable_button: ExpandableButton) -> void:
	print("Boog")



func _expandable_button_toggled(file_path: String, on: bool) -> void:
	if on:
		_expanded_folders.append(file_path)
	else:
		_expanded_folders.erase(file_path)



func style_expandable_button(expndblebton: ExpandableButton, text: String, icon: Texture2D, show_expandable: bool = true) -> void:
	expndblebton.text = text
	expndblebton.icon = icon
	expndblebton.label_settings = text_settings
	expndblebton.panel_stylebox = panel_style
	expndblebton.get_expandable_icon_button().visible = show_expandable
