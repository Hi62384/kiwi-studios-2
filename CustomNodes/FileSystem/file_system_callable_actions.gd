extends Node

const ExpandableButton = preload("uid://dk22ixmn3cmrb")
const FileSystem = preload("uid://k2xqavmy8y6v")
@onready var file_system: FileSystem = $".."

var undo_redo: UndoRedo = UndoRedo.new()



func move_files(dir_to_move_to: String, files_to_move: Array[String]) -> void:
	# Store original directories for each file
	var original_dirs: Array[String] = []
	
	for path in files_to_move:
		original_dirs.append(path.get_base_dir())
	
	undo_redo.create_action("Move Files")
	
	# DO: move all files to target_dir
	undo_redo.add_do_method(func():
		FileOperations.move_files(dir_to_move_to, files_to_move))
	
	# UNDO: move each file back to its original directory
	for i in files_to_move.size():
		var new_file_path: String = dir_to_move_to.path_join(files_to_move[i].get_file())
		undo_redo.add_undo_method(func():
			if !FileOperations.path_exists(new_file_path):
				return
			FileOperations.move_absolute(new_file_path, original_dirs[i])
		)
	
	undo_redo.commit_action()



func delete_files(file_paths: Array[String]) -> void:
	for path: String in file_paths:
		FileOperations.delete_directory(path)



func send_files_to_recycle_bin(file_paths: Array[String]) -> void:
	var trash_dir: String = LocalProjectFilesystem.get_project_trash_directory()
	
	# Store original directories for each file
	var original_dirs: Array[String] = []
	
	for path in file_paths:
		original_dirs.append(path.get_base_dir())
	
	undo_redo.create_action("Move Files")
	
	# DO: move all files to target_dir
	undo_redo.add_do_method(func():
		FileOperations.move_files(trash_dir, file_paths))
	
	# UNDO: move each file back to its original directory
	for i in file_paths.size():
		var new_file_path: String = trash_dir.path_join(file_paths[i].get_file())
		undo_redo.add_undo_method(func():
			if !FileOperations.path_exists(new_file_path):
				return
			FileOperations.move_absolute(new_file_path, original_dirs[i])
		)
	
	undo_redo.commit_action()



func duplicate_files(file_paths: Array[String]) -> void:
	undo_redo.create_action("Duplicate Files")
	undo_redo.add_do_method(func():
		for path: String in file_paths:
			FileOperations.duplicate_path_absolute(path, path)
		)
	for i in file_paths.size():
		var new_file_path: String = FileOperations.get_unique_name(file_paths[i])
		undo_redo.add_undo_method(func():
			if !FileOperations.path_exists(new_file_path):
				return
			FileOperations.delete_directory(new_file_path)
		)
	undo_redo.commit_action()



func create_folder() -> void:
	pass



func rename_file() -> void:
	pass
