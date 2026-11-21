extends Panel

signal file_resource_opened(path: String)
signal shader_file_opened(path: String)


const EXPANDABLE_BUTTON = preload("uid://basy0qkxblg2m")
const ExpandableButton = preload("res://scripts/Extra/ExpandableButtonControl.cs")
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
	_native_browser().ready(self)

func _recursive_check_for_files_to_filter(file: LocalProjectFilesystem.File) -> void:
	_native_browser().collect_filtered(self,file)

func _should_display_file(file_path: String) -> bool:
	return _native_browser().should_display(self,file_path)

func _should_filter_files() -> bool:
	return _native_browser().should_filter(self)

func update_filesystem_display() -> void:
	_native_browser().update_display(self)

func update_folder_display(folder: LocalProjectFilesystem.Folder, expandable_button: ExpandableButton) -> void:
	_native_browser().update_folder(self,folder,expandable_button)

func _load_button_thumbnail(path: String, button: Variant, generation: int) -> void:
	var thumbnail: Texture2D = await FileOperations.get_file_thumbnail(path)
	_apply_button_thumbnail(button, thumbnail, generation)

func _apply_button_thumbnail(button: Variant, thumbnail: Texture2D, generation: int) -> void:
	_native_browser().apply_thumbnail(self,button,thumbnail,generation)

func _setup_folder_expandable_button(folder: LocalProjectFilesystem.Folder, button: ExpandableButton) -> void:
	_native_browser().setup_folder(self,folder,button)

func _setup_file_expandable_button(file: LocalProjectFilesystem.File, button: ExpandableButton) -> void:
	_native_browser().setup_file(self,file,button)

func _connect_expandable_button_right_click(event, callable: Callable, expandable_button: ExpandableButton) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			callable.call(expandable_button)



func file_pressed(expandable_button: ExpandableButton) -> void:
	var selected: bool = _native_browser().begin_press(self,expandable_button)
	await get_tree().create_timer(0.2).timeout
	_native_browser().finish_press(self,expandable_button,selected)

func _dragged_file_paths(button: ExpandableButton) -> PackedStringArray:
	return _native_browser().dragged_paths(self,button)

func _paths_from_drag(data: Variant) -> Array[String]:
	return _native_browser().paths_from_drag(data)

func _can_drop_files_on_folder(data: Variant, folder_path: String) -> bool:
	return _native_browser().can_drop(self,data,folder_path)

func _drop_files_on_folder(data: Variant, folder_path: String) -> void:
	_native_browser().drop(self,data,folder_path)

func file_right_clicked(expandable_button: ExpandableButton) -> void:
	_native_browser().right_clicked(self,expandable_button)

func _expandable_button_toggled(file_path: String, on: bool) -> void:
	_native_browser().toggled(self,file_path,on)

func _style_expandable_button(expndblebton: ExpandableButton, text: String, icon: Texture2D, show_expandable: bool = true) -> void:
	_native_browser().style(self,expndblebton,text,icon,show_expandable)

func expandable_button_arr_to_path_arr(buttons: Array[ExpandableButton]) -> Array[String]:
	return _native_browser().button_paths(buttons)


func _search_changed(_text: String) -> void:
	update_filesystem_display()

func _folder_toggled(on: bool,path: String) -> void:
	_native_browser().toggled(self,path,on)

func _file_button_input(event: InputEvent,button: Control,path: String,folder: bool) -> void:
	_native_browser().button_input(self,event,button,path,folder)

static func _native_browser() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("project_file_browser")
