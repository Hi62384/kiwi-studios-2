#FOR OPERATIONS AND GETTING DATA IN THE LOCAL FILESYSTEM
class_name LocalProjectFilesystem
extends Node

signal file_tree_recreated


static var node: LocalProjectFilesystem

const _TIME_BETWEEN_SCANS = 3
func _ready() -> void:
	_native_filesystem().begin_ready(self)
	await get_tree().process_frame
	_native_filesystem().finish_ready(self)

func _scan_changes() -> void:
	_native_filesystem().scan_changes()

func _exit_tree() -> void:
	_native_filesystem().exit_tree(self)

func _scan_folder_for_change(folder_path: String, files_remaining: Array[String], index: int) -> int:
	return _native_filesystem().scan_folder_for_change(folder_path,files_remaining,index)

static func get_ordered_array_of_project_file_paths() -> Array[String]:
	return _native_filesystem().get_ordered_array_of_project_file_paths()

static func get_current_project() -> Project:
	return _native_filesystem().get_current_project()

static func get_project_root_directory() -> String:
	return _native_filesystem().get_project_root_directory()

static func get_project_trash_directory() -> String:
	return _native_filesystem().get_project_trash_directory()

static func local_to_global_path(local_path) -> String:
	return _native_filesystem().local_to_global_path(local_path)

static func file_exists_in_project_directory(file_absolute_path: String) -> bool:
	return _native_filesystem().file_exists_in_project_directory(file_absolute_path)

static func global_to_local_path(global_path: String) -> String:
	return _native_filesystem().global_to_local_path(global_path)

static func get_sensetive_file_paths() -> Array[String]:
	return _native_filesystem().get_sensetive_file_paths()

static var root_folder: Folder



static func update_root_folder() -> void:
	_native_filesystem().update_root_folder()

static func _create_file_tree(folder_path: String) -> Folder:
	return _native_filesystem().create_file_tree(folder_path)

static var _all_files_paths: Array[String]
static func _recursive_add_files_in_folder(folder: Folder) -> void:
	_native_filesystem().recursive_add_files_in_folder(folder)

class File extends RefCounted:
	var path: String
	
	func _init(_local_path: String) -> void:
		path = _local_path


class Folder extends File:
	var contains: Array[File]

static func _new_native_file(path: String,folder: bool) -> File:
	return Folder.new(path) if folder else File.new(path)

static func _native_filesystem() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("local_project_filesystem")
