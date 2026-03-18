extends Panel


const EXPANDABLE_BUTTON = preload("uid://basy0qkxblg2m")
const ExpandableButton = preload("uid://dk22ixmn3cmrb")

@export var text_settings: LabelSettings
@export var panel_style: StyleBox

@onready var container: VBoxContainer = $VBoxContainer/Panel/ScrollContainer/VBoxContainer

var _expanded_folders: Array[String]
var _selected_expandable_buttons: Array[ExpandableButton]


func _ready() -> void:
	LocalProjectFilesystem.node.file_tree_recreated.connect(update_filesystem_display)



func update_filesystem_display() -> void:
	NodeOperations.delete_children(container)
	
	var expanded_folders_before: Array[String] = _expanded_folders.duplicate()
	
	var root_folder: LocalProjectFilesystem.Folder = LocalProjectFilesystem.root_folder
	var expandable_button: ExpandableButton = EXPANDABLE_BUTTON.instantiate()
	
	container.add_child(expandable_button)
	
	style_expandable_button(
		expandable_button,
		root_folder.path.get_file(),
		FileOperations.get_file_thumbnail(root_folder.path)
	)
	
	if _expanded_folders.has(root_folder.path):
		expandable_button.expanded = true
		_expanded_folders.erase(root_folder.path)
	
	update_folder_display(root_folder, expandable_button)
	
	#remove missing folders from _expanded_folders
	var new_expanded_folders: Array[String]
	for folder_before: String in expanded_folders_before:
		if !_expanded_folders.has(folder_before):
			new_expanded_folders.append(folder_before)
	_expanded_folders = new_expanded_folders



func update_folder_display(folder: LocalProjectFilesystem.Folder, expandable_button: ExpandableButton) -> void:
	for file: LocalProjectFilesystem.File in folder.contains:
		print(file.path)
		var child_expandable_button: ExpandableButton = EXPANDABLE_BUTTON.instantiate()
		
		expandable_button.add_child_in_expand(child_expandable_button)
		
		expandable_button.set_meta("path", file.path)
		
		style_expandable_button(
			child_expandable_button,
			file.path.get_file(),
			FileOperations.get_file_thumbnail(file.path),
			file is LocalProjectFilesystem.Folder
		)
		
		if file is LocalProjectFilesystem.Folder:
			if _expanded_folders.has(file.path):
				expandable_button.expanded = true
				_expanded_folders.erase(file.path)
			update_folder_display(file, child_expandable_button)
			
			expandable_button.toggled.connect(func(on: bool):
				_expandable_button_toggled(file.path, on))
			
			expandable_button.get_main_button().pressed.connect(folder_pressed.bind(expandable_button))
			expandable_button.get_main_button().gui_input.connect(func(event):
				_connect_expandable_button_right_click(event, folder_right_clicked, expandable_button)
				)
		else:
			pass
			#expandable_button.get_main_button().pressed.connect(file_pressed.bind(expandable_button))
			#expandable_button.get_main_button().gui_input.connect(func(event):
			#	_connect_expandable_button_right_click(event, file_right_clicked, expandable_button)
			#	)



func _connect_expandable_button_right_click(event, callable: Callable, expandable_button: ExpandableButton) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			callable.call(expandable_button)


func _toggle_select_expandable_buttons(expandable_buttons: Array[ExpandableButton]) -> void:
	for expandable_button: ExpandableButton in expandable_buttons:
		if _expandable_button_is_selected(expandable_button):
			_deselect_expandable_buttons([expandable_button])
		else:
			_select_expandable_buttons([expandable_button])


func _expandable_button_is_selected(expandable_button: ExpandableButton) -> bool:
	return _selected_expandable_buttons.has(expandable_button)


func _deselect_all_expandable_buttons() -> void:
	_deselect_expandable_buttons(_selected_expandable_buttons)


func _deselect_expandable_buttons(expandable_buttons: Array[ExpandableButton]) -> void:
	for expandable_button: ExpandableButton in expandable_buttons:
		expandable_button.get_cover_color_rect().visible = false
		_selected_expandable_buttons.erase(expandable_button)


func _select_expandable_buttons(expandable_buttons: Array[ExpandableButton]) -> void:
	for expandable_button: ExpandableButton in expandable_buttons:
		expandable_button.get_cover_color_rect().visible = true
		_selected_expandable_buttons.append(expandable_button)



func _handle_input_for_clicked_file(expandable_button: ExpandableButton) -> void:
	if !Input.is_action_pressed("shift"):
		_deselect_all_expandable_buttons()
		_select_expandable_buttons([expandable_button])
		return
	
	if Input.is_action_pressed("ctrl"):
		_toggle_select_expandable_buttons([expandable_button])
		return
	
	
	



func folder_pressed(expandable_button: ExpandableButton) -> void:
	_handle_input_for_clicked_file(expandable_button)



func folder_right_clicked(expandable_button: ExpandableButton) -> void:
	print("Hoog")



func file_pressed(expandable_button: ExpandableButton) -> void:
	_handle_input_for_clicked_file(expandable_button)



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
