#FOR OPERATIONS AND GETTING DATA IN THE LOCAL FILESYSTEM
class_name LocalProjectFilesystem
extends Node

signal file_tree_recreated


static var node: LocalProjectFilesystem

const _TIME_BETWEEN_SCANS = 3
func _ready() -> void:
	node = self
	await get_tree().process_frame
	_update_root_folder()
	
	#constantly scan filesystem for change
	while true:
		var files_remaining = _all_files_paths.duplicate()
		files_remaining.remove_at(0)
		var result = _scan_folder_for_change(get_project_root_directory(), files_remaining, 0)
		if result != files_remaining.size():
			_file_system_altered()
		await get_tree().create_timer(_TIME_BETWEEN_SCANS).timeout



func _scan_folder_for_change(folder_path: String, files_remaining: Array[String], index: int) -> int:
	for child_folder_path in DirAccess.get_directories_at(folder_path):
		var effective_path := folder_path.path_join(child_folder_path)
		if index >= files_remaining.size() or effective_path != files_remaining[index]:
			_file_system_altered()
			return -1  # Early exit
		index += 1
		index = _scan_folder_for_change(effective_path, files_remaining, index)
		if index == -1:
			return -1
	for child_file_path in DirAccess.get_files_at(folder_path):
		var effective_path := folder_path.path_join(child_file_path)
		if index >= files_remaining.size() or effective_path != files_remaining[index]:
			_file_system_altered()
			return -1  # Early exit
		index += 1
	return index
		


func _file_system_altered() -> void:
	_update_root_folder()



static func get_ordered_array_of_project_file_paths() -> Array[String]:
	return _all_files_paths


static func get_current_project() -> Project:
	return StaticData.loaded_project


static func get_project_root_directory() -> String:
	return get_current_project().resource_path.get_base_dir().get_base_dir()   


static func local_to_global_path(local_path) -> String:
	return get_project_root_directory() + "/" + local_path


static var root_folder: Folder



static func _update_root_folder() -> void:
	root_folder = _create_file_tree(get_project_root_directory())
	node.file_tree_recreated.emit()



static func _create_file_tree(folder_path: String) -> Folder:
	_all_files_paths = [folder_path]
	var folder: Folder = Folder.new(folder_path)
	_recursive_add_files_in_folder(folder)
	return folder



static var _all_files_paths: Array[String]
static func _recursive_add_files_in_folder(folder: Folder) -> void:
	for folder_path: String in DirAccess.get_directories_at(folder.path):
		var effective_path: String = folder.path + "/" + folder_path
		var new_folder: Folder = Folder.new(effective_path)
		folder.contains.append(new_folder)
		_all_files_paths.append(effective_path)
		_recursive_add_files_in_folder(new_folder)
	for file_path: String in DirAccess.get_files_at(folder.path):
		var effective_path: String = folder.path + "/" + file_path
		var new_file: File = File.new(effective_path)
		_all_files_paths.append(effective_path)
		folder.contains.append(new_file)








class File extends RefCounted:
	var path: String
	
	func _init(_local_path: String) -> void:
		path = _local_path


class Folder extends File:
	var contains: Array[File]
