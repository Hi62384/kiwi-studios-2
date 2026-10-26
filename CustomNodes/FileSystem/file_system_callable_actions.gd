extends Node

const ExpandableButton = preload("uid://dk22ixmn3cmrb")
const FileSystem = preload("uid://k2xqavmy8y6v")
@onready var file_system: FileSystem = $".."

var _undo_redo: UndoRedo = UndoRedo.new()

func _exit_tree() -> void:
	# UndoRedo is not reference counted; release captured file actions and owner.
	if is_instance_valid(_undo_redo):
		_undo_redo.clear_history()
		_undo_redo.free()



func undo() -> void:
	_undo_redo.undo()


func redo() -> void:
	_undo_redo.redo()



func move_files(dir_to_move_to: String, files_to_move: Array[String]) -> void:
	# Store original directories for each file
	var original_dirs: Array[String] = []
	
	for path in files_to_move:
		original_dirs.append(path.get_base_dir())
	
	_undo_redo.create_action("Move Files")
	
	# DO: move all files to target_dir
	_undo_redo.add_do_method(func():
		FileOperations.move_files(dir_to_move_to, files_to_move))
	
	# UNDO: move each file back to its original directory
	for i in files_to_move.size():
		var new_file_path: String = dir_to_move_to.path_join(files_to_move[i].get_file())
		_undo_redo.add_undo_method(func():
			if !FileOperations.path_exists(new_file_path):
				return
			FileOperations.move_absolute(new_file_path, original_dirs[i])
		)
	
	_undo_redo.commit_action()



func delete_files(file_paths: Array[String]) -> void:
	for path: String in file_paths:
		FileOperations.delete_directory(path)



func send_files_to_recycle_bin(file_paths: Array[String]) -> void:
	var trash_dir: String = LocalProjectFilesystem.get_project_trash_directory()
	
	# Store original directories for each file
	var original_dirs: Array[String] = []
	
	for path in file_paths:
		original_dirs.append(path.get_base_dir())
	
	_undo_redo.create_action("Move Files")
	
	# DO: move all files to target_dir
	_undo_redo.add_do_method(func():
		for file_path: String in file_paths:
			FileOperations.move_to_project_trash(file_path)
		)
	
	# UNDO: move each file back to its original directory
	for i in file_paths.size():
		var new_file_path: String = trash_dir.path_join(file_paths[i].get_file())
		_undo_redo.add_undo_method(func():
			if !FileOperations.path_exists(new_file_path):
				return
			FileOperations.move_absolute(new_file_path, original_dirs[i])
		)
	
	_undo_redo.commit_action()



func duplicate_files(file_paths: Array[String]) -> void:
	_undo_redo.create_action("Duplicate Files")
	_undo_redo.add_do_method(func():
		for path: String in file_paths:
			FileOperations.duplicate_path_absolute(path, path)
		)
	for i in file_paths.size():
		var new_file_path: String = FileOperations.get_unique_name(file_paths[i])
		_undo_redo.add_undo_method(func():
			if !FileOperations.path_exists(new_file_path):
				return
			FileOperations.delete_directory(new_file_path)
		)
	_undo_redo.commit_action()



func create_folder(folder_path: String) -> void:
	_undo_redo.create_action("Create Folder")
	_undo_redo.add_do_method(func():
		FileOperations.create_folder_at(folder_path)
		)
	_undo_redo.add_undo_method(func():
		if FileOperations.path_exists(folder_path):
			FileOperations.delete_directory(folder_path)
		)
	_undo_redo.commit_action()




func rename_file(file_path_to_change: String, new_name: String) -> void:
	_undo_redo.create_action("Change Filename")
	_undo_redo.add_do_method(func():
		FileOperations.rename_absolute(file_path_to_change, new_name)
		)
	var new_path: String = FileOperations.get_changed_name_path(file_path_to_change, new_name)
	var old_file_path_name: String = file_path_to_change.get_basename().get_file()
	_undo_redo.add_undo_method(func():
		if FileOperations.path_exists(new_path):
			FileOperations.rename_absolute(new_path, old_file_path_name)
		)
	_undo_redo.commit_action()
	
