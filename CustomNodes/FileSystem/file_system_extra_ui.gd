extends Node

const ExpandableButton = preload("uid://dk22ixmn3cmrb")
const FILE_ACTION_DIALOGUE = preload("uid://cm431qw86wyvs")
const FileActionDialogue = preload("uid://c0ohimns5kdk7")
const FileSystem = preload("uid://k2xqavmy8y6v")
const FileSystemCallableActions = preload("uid://b5gm21p0e2sbv")

@onready var file_system_callable_actions: FileSystemCallableActions = $"../FileSystemCallableActions"

@onready var file_system: FileSystem = $".."
@onready var screen_cover: ColorRect = $ScreenCover
@onready var rename_file_panel: DialogParamChooser = $RenameFilePanel
@onready var create_folder_panel: DialogParamChooser = $CreateFolderPanel

@onready var delete_file_panel: Panel = $DeleteFilePanel
@onready var delete_file_panel_close_button: Button = $DeleteFilePanel/VBoxContainer/HBoxContainer/Button
@onready var delete_file_panel_delete_button: Button = $DeleteFilePanel/VBoxContainer/DeleteFileButton
@onready var delete_file_panel_to_recycle_bin_button: Button = $DeleteFilePanel/VBoxContainer/ToRecycleBinButton

@onready var rename_file_panel_line_edit: LineEdit = $RenameFilePanel/VBoxContainer/LineEdit

var _clicked_expandable_button: ExpandableButton
var _current_dialouge: FileActionDialogue



func _ready() -> void:
	delete_file_panel_close_button.pressed.connect(func():
		set_panel_visible(delete_file_panel, false)
		)
	delete_file_panel_delete_button.pressed.connect(delete_files)
	delete_file_panel_to_recycle_bin_button.pressed.connect(recycle_files)



func display_operations(expandable_button: ExpandableButton) -> void:
	_clicked_expandable_button = expandable_button
	_current_dialouge = FILE_ACTION_DIALOGUE.instantiate()
	_current_dialouge.position = file_system.get_global_mouse_position()
	add_child(_current_dialouge)
	
	_current_dialouge.copy_path_button.pressed.connect(copy_file_path)
	_current_dialouge.copy_absolute_path_button.pressed.connect(copy_absolute_file_path)
	_current_dialouge.show_in_file_manager_button.pressed.connect(_show_in_file_manager)
	_current_dialouge.open_in_external_program_button.pressed.connect(_open_in_external_program)
	_current_dialouge.rename_button.pressed.connect(rename_file)
	_current_dialouge.create_new_folder_button.pressed.connect(create_folder)
	_current_dialouge.delete_button.pressed.connect(show_delete_options)
	_current_dialouge.duplicate_button.pressed.connect(duplicate_files)
	var clipboard:=Button.new(); clipboard.text="Copy to Super Clipboard"; _current_dialouge.duplicate_button.get_parent().add_child(clipboard)
	clipboard.pressed.connect(func():
		for path: String in _arr_of_top_selected_file_paths():
			if FileAccess.file_exists(path): KiwiSuperClipboardService.instance.quick_save(path,path.get_file().get_basename())
		if is_instance_valid(_current_dialouge): _current_dialouge.queue_free())



func _arr_of_top_selected_file_paths() -> Array[String]:
	var top_level_files: Array[ExpandableButton] = file_system.files_selector.get_expandable_buttons_top_selected_files()
	return file_system.expandable_button_arr_to_path_arr(top_level_files)



func set_panel_visible(panel: Control, visible: bool) -> void:
	panel.visible = visible
	screen_cover.visible = visible



func _get_clicked_expandable_button_path() -> String:
	return _clicked_expandable_button.get_meta("path")


func copy_file_path() -> void:
	DisplayServer.clipboard_set(LocalProjectFilesystem.global_to_local_path(_get_clicked_expandable_button_path()))


func copy_absolute_file_path() -> void:
	DisplayServer.clipboard_set(_get_clicked_expandable_button_path())


func _show_in_file_manager() -> void:
	var dir: String = FileOperations.get_lowest_directory(_get_clicked_expandable_button_path())
	FileOperations.open_file(dir)


func _open_in_external_program() -> void:
	FileOperations.open_file(_get_clicked_expandable_button_path())


func rename_file() -> void:
	screen_cover.visible = true
	rename_file_panel_line_edit.text = _get_clicked_expandable_button_path().get_basename().get_file()
	var result: Dictionary = await rename_file_panel.select_params()
	screen_cover.visible = false
	if result.is_empty(): return
	file_system_callable_actions.rename_file(_get_clicked_expandable_button_path(), result.NewFileName)


func create_folder() -> void:
	screen_cover.visible = true
	var result: Dictionary = await create_folder_panel.select_params()
	screen_cover.visible = false
	if result.is_empty(): return
	var base_path: String = FileOperations.get_lowest_directory(_get_clicked_expandable_button_path())
	var folder_path: String = base_path + "/" + result.FolderName
	file_system_callable_actions.create_folder(folder_path)



func duplicate_files() -> void:
	file_system_callable_actions.duplicate_files(_arr_of_top_selected_file_paths())


func show_delete_options() -> void:
	set_panel_visible(delete_file_panel, true)



func delete_files() -> void:
	set_panel_visible(delete_file_panel, false)
	file_system_callable_actions.delete_files(_arr_of_top_selected_file_paths())



func recycle_files() -> void:
	set_panel_visible(delete_file_panel, false)
	file_system_callable_actions.send_files_to_recycle_bin(_arr_of_top_selected_file_paths())



func _for_top_files(fun: Callable) -> void:
	var top_level_files: Array[ExpandableButton] = file_system.files_selector.get_expandable_buttons_top_selected_files()
	for expandable_button: ExpandableButton in top_level_files:
		var expandable_button_path: String = expandable_button.get_meta("path")
		fun.call(expandable_button, expandable_button_path)
