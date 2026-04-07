extends Node

const ExpandableButton = preload("uid://dk22ixmn3cmrb")
const FileSystem = preload("uid://k2xqavmy8y6v")
@onready var file_system: FileSystem = $".."
@onready var folder_mover_icon: TextureRect = $FolderMoverIcon

var _hovered_expandable_button: ExpandableButton

var _moving_selected_files: bool = false


func set_hovered_expandable_button(button: ExpandableButton) -> void:
	_hovered_expandable_button = button



func start_moving_selected_files() -> void:
	_moving_selected_files = true
	_properly_position_folder_mover_icon()
	folder_mover_icon.visible = true



func stop_moving_selected_files() -> void:
	_moving_selected_files = false
	folder_mover_icon.visible = false
	if _hovered_expandable_button != null:
		_move_selected_files_to_hovered_expandable_button()


func _move_selected_files_to_hovered_expandable_button() -> void:
	var path_to_move_to: String = FileOperations.get_lowest_directory(_hovered_expandable_button.get_meta("path"))
	var top_level_files: Array[ExpandableButton] = file_system.files_selector.get_expandable_buttons_top_selected_files()
	var top_level_file_paths: Array[String] = file_system.expandable_button_arr_to_path_arr(top_level_files)
	file_system.file_system_actions.move_files(path_to_move_to, top_level_file_paths)


func _properly_position_folder_mover_icon() -> void:
	folder_mover_icon.position = file_system.get_global_mouse_position()



func _process(_delta: float) -> void:
	if !_moving_selected_files: return
	
	_properly_position_folder_mover_icon()
	if Input.is_action_just_released("left_click"):
		stop_moving_selected_files()
