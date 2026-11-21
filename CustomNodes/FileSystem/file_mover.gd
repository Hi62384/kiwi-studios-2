extends Node

const ExpandableButton = preload("res://scripts/Extra/ExpandableButtonControl.cs")
const FileSystem = preload("uid://k2xqavmy8y6v")
@onready var file_system: FileSystem = $".."
@onready var folder_mover_icon: TextureRect = $FolderMoverIcon

var _hovered_expandable_button: ExpandableButton

var _moving_selected_files: bool = false


func set_hovered_expandable_button(button: ExpandableButton) -> void:
	_native_mover().set_hovered(self,button)

func start_moving_selected_files() -> void:
	_native_mover().start(self)

func stop_moving_selected_files() -> void:
	_native_mover().stop(self)

func _move_selected_files_to_hovered_expandable_button() -> void:
	_native_mover().move_to_hovered(self)

func _properly_position_folder_mover_icon() -> void:
	_native_mover().position_icon(self)

func _process(_delta: float) -> void:
	_native_mover().process(self)


static func _native_mover() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("project_file_mover")
