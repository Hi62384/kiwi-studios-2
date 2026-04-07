extends Node


signal saved_projects_updated

var _saved_projects: ProjectManagerSavedProjects


#find the locally stored resource that contains all saved projects paths
func _ready() -> void:
	#if in editor, make base directory project directory, else make it exe directory
	var base_dir: String
	if OS.has_feature("editor"):
		base_dir = ProjectSettings.globalize_path("res://")
	else:
		base_dir = OS.get_executable_path().get_base_dir()
	
	var saved_projects_path: String = base_dir + "_SavedProjects.tres"
	_saved_projects = ResourceLoader.load(saved_projects_path)



func add_project_to_listing(path: String) -> void:
	_saved_projects.project_paths.append(path)
	FileOperations.save_resource(_saved_projects)
	saved_projects_updated.emit()


func create_project(path: String, project_name: String) -> void:
	if _saved_projects.project_paths.has(path): return
	
	var proj_path: String = path + "/.proj/"
	var proj_trash_path: String = proj_path + ".trash/"
	DirAccess.make_dir_recursive_absolute(proj_path)
	DirAccess.make_dir_absolute(proj_trash_path)
	var project: Project = Project.new(project_name)
	ResourceSaver.save(project, proj_path + "Project.tres")
	add_project_to_listing(path)
	


func duplicate_project(path_to_duplicate: String, new_path: String, project_name: String) -> void:
	if !DirAccess.dir_exists_absolute(path_to_duplicate): return
	
	FileOperations.duplicate_directory(path_to_duplicate, new_path)
	var project: Project = ResourceLoader.load(get_project_file_path_in_project_dir(new_path))
	project.project_name = project_name
	FileOperations.save_resource(project)
	add_project_to_listing(new_path)


func remove_project_from_listing(path: String) -> void:
	if _saved_projects.project_paths.has(path):
		_saved_projects.project_paths.erase(path)
	FileOperations.save_resource(_saved_projects)
	saved_projects_updated.emit()


func unalive_project_directory(path: String, to_recycle_bin: bool) -> void:
	if !DirAccess.dir_exists_absolute(path): return
	
	if to_recycle_bin:
		FileOperations.move_to_trash(path)
	else:
		FileOperations.delete_directory(path)
	remove_project_from_listing(path)


func rename_project(project_path: String, new_name: String) -> void:
	if !DirAccess.dir_exists_absolute(project_path): return
	
	var project: Project = ResourceLoader.load(get_project_file_path_in_project_dir(project_path))
	project.project_name = new_name
	FileOperations.save_resource(project)
	saved_projects_updated.emit()
	


func get_saved_projects() -> ProjectManagerSavedProjects:
	return _saved_projects



func get_project_file_path_in_project_dir(project_path: String) -> String:
	var project_file_path: String = project_path + "/.proj/" + "Project.tres"
	
	if FileAccess.file_exists(project_file_path):
		return project_file_path
	return ""
