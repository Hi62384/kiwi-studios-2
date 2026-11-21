extends Node

const ExpandableButton = preload("res://scripts/Extra/ExpandableButtonControl.cs")
const FILE_ACTION_DIALOGUE = preload("uid://cm431qw86wyvs")
const FileActionDialogue = preload("res://scripts/Extra/FileActionDialogueControl.cs")
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
	_native_context().ready(self)

func display_operations(expandable_button: ExpandableButton) -> void:
	_native_context().display_operations(self,expandable_button)

func _arr_of_top_selected_file_paths() -> Array[String]:
	return _native_context().selected_paths(self)

func set_panel_visible(panel: Control, visible: bool) -> void:
	_native_context().set_panel_visible(self,panel,visible)

func _get_clicked_expandable_button_path() -> String:
	return _native_context().clicked_path(self)

func copy_file_path() -> void:
	_native_context().copy_file_path(self)

func copy_absolute_file_path() -> void:
	_native_context().copy_absolute_file_path(self)

func _show_in_file_manager() -> void:
	_native_context().show_in_file_manager(self)

func _open_in_external_program() -> void:
	_native_context().open_in_external_program(self)

func rename_file() -> void:
	var path: String=_native_context().begin_rename(self)
	if path.is_empty(): return
	var result: Dictionary=await rename_file_panel.select_params()
	_native_context().finish_rename(self,path,result)

func create_folder() -> void:
	var path: String=_native_context().begin_create_folder(self)
	if path.is_empty(): return
	var result: Dictionary=await create_folder_panel.select_params()
	_native_context().finish_create_folder(self,path,result)

func duplicate_files() -> void:
	_native_context().duplicate_files(self)

func show_delete_options() -> void:
	_native_context().show_delete_options(self)

func delete_files() -> void:
	_native_context().delete_files(self)

func recycle_files() -> void:
	_native_context().recycle_files(self)

func _for_top_files(fun: Callable) -> void:
	_native_context().for_top_files(self,fun)


func _close_delete_panel() -> void:
	_native_context().close_delete_panel(self)

func _invoke_file_callback(callback: Callable,button: Variant,path: String) -> void:
	if callback.is_valid(): callback.call(button,path)

static func _native_context() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("project_file_context")
