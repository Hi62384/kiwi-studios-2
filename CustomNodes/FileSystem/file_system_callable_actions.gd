extends Node

const ExpandableButton = preload("res://scripts/Extra/ExpandableButtonControl.cs")
const FileSystem = preload("uid://k2xqavmy8y6v")
@onready var file_system: FileSystem = $".."

var _undo_redo: UndoRedo = UndoRedo.new()

func _exit_tree() -> void:
	_native_actions().exit_tree(self)

func undo() -> void:
	_native_actions().undo(self)

func redo() -> void:
	_native_actions().redo(self)

func move_files(dir_to_move_to: String, files_to_move: Array[String]) -> void:
	_native_actions().move_files(self,dir_to_move_to,files_to_move)

func delete_files(file_paths: Array[String]) -> void:
	_native_actions().delete_files(file_paths)

func send_files_to_recycle_bin(file_paths: Array[String]) -> void:
	_native_actions().send_files_to_recycle_bin(self,file_paths)

func duplicate_files(file_paths: Array[String]) -> void:
	_native_actions().duplicate_files(self,file_paths)

func create_folder(folder_path: String) -> void:
	_native_actions().create_folder(self,folder_path)

func rename_file(file_path_to_change: String, new_name: String) -> void:
	_native_actions().rename_file(self,file_path_to_change,new_name)


static func _native_actions() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("project_file_actions")
