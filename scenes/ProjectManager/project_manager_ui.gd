extends Control

const PROJECT_MANAGER_PROJECT_DISPLAY: PackedScene = preload("uid://b7urpcwnd0d7e")
const PROGRAM_ICON = preload("uid://bops5bhht8eq3")

const ProjectManagerProjectDisplay = preload("uid://bjcilpgjrcr")
const ProjectManager = preload("uid://d3wgvbquosu7f")


@onready var create_project_button: Button = %CreateProjectButton
@onready var open_project_button: Button = %OpenProjectButton
@onready var filter_project_line_edit: LineEdit = %FilterProjectLineEdit
@onready var project_display_container: VBoxContainer = %ProjectDisplayContainer
@onready var rename_project_button: Button = %RenameProjectButton
@onready var duplicate_project_button: Button = %DuplicateProjectButton
@onready var remove_project_button: Button = %RemoveProjectButton
@onready var open_in_file_manager_button: Button = %OpenInFileManagerButton
@onready var screen_cover: ColorRect = %ScreenCover
@onready var project_manager: ProjectManager = %ProjectManager
@onready var file_dialog: FileDialog = $FileDialog
@onready var rename_project_panel_line_edit: LineEdit = $RenameProjectPanel/VBoxContainer/LineEdit

@onready var create_project_panel: DialogParamChooser = $CreateProjectPanel
@onready var rename_project_panel: DialogParamChooser = $RenameProjectPanel
@onready var duplicate_project_panel: Panel = $DuplicateProjectPanel
@onready var delete_project_panel: Panel = $DeleteProjectPanel


var selected_panel_display: ProjectManagerProjectDisplay

func selected_panel_display_is_invalid() -> bool:
	if selected_panel_display == null: return true
	return selected_panel_display.error_cover.visible


func _ready() -> void:
	project_manager.saved_projects_updated.connect(update_displayed_projects)
	filter_project_line_edit.text_changed.connect(func(_text):
		update_displayed_projects()
		)
	
	open_project_button.pressed.connect(open_project_button_pressed)
	create_project_button.pressed.connect(create_project_button_pressed)
	open_in_file_manager_button.pressed.connect(open_location_pressed)
	remove_project_button.pressed.connect(remove_project_pressed)
	duplicate_project_button.pressed.connect(duplicate_project_pressed)
	rename_project_button.pressed.connect(rename_project_pressed)
	
	update_displayed_projects()


func create_project_button_pressed() -> void:
	screen_cover.visible = true
	create_project_panel.create_new_folder.button_pressed = false
	var params: Dictionary = await create_project_panel.select_params()
	screen_cover.visible = false
	if params.is_empty(): return
	var save_path: String = params.DirectorySavePath
	var project_name: String = params.ProjectName
	if !FileOperations.dir_path_string_is_valid(save_path): return
	project_manager.create_project(save_path, project_name)


func open_project_button_pressed() -> void:
	screen_cover.visible = true
	
	var path: String = await FileOperations.get_file_dialog_path(file_dialog)
	screen_cover.visible = false
	if path == "": return
	
	if project_manager.get_project_file_path_in_project_dir(path) != "":
		project_manager.add_project_to_listing(path)
	


func update_displayed_projects() -> void:
	NodeOperations.delete_children(project_display_container)
	
	for project_path: String in project_manager.get_saved_projects().project_paths:
		var project: Project = ResourceLoader.load(project_manager.get_project_file_path_in_project_dir(project_path))
		
		if (project == null and filter_project_line_edit.text != "") or !(filter_project_line_edit.text == "" or project.project_name.contains(filter_project_line_edit.text)):
			continue
		
		var project_display: ProjectManagerProjectDisplay = PROJECT_MANAGER_PROJECT_DISPLAY.instantiate()
		project_display_container.add_child(project_display)
		
		project_display.project_path.text = project_path
		project_display.texture_rect.texture = PROGRAM_ICON
		project_display.button.pressed.connect(func():
			if selected_panel_display == project_display and project != null:
				#LOAD MAIN SCENE
				StaticData.loaded_project = project
				get_tree().change_scene_to_file("res://scenes/Main.tscn")
			
			if selected_panel_display != null:
				selected_panel_display.selected_cover.visible = false
			selected_panel_display = project_display
			selected_panel_display.selected_cover.visible = true
			)
		if project == null:
			project_display.error_cover.visible = true
			project_display.project_name.text = "MISSING PROJECT"
		else:
			project_display.project_name.text = project.project_name


func rename_project_pressed() -> void:
	if selected_panel_display_is_invalid(): return
	
	screen_cover.visible = true
	rename_project_panel_line_edit.text = selected_panel_display.project_name.text
	var params: Dictionary = await rename_project_panel.select_params()
	screen_cover.visible = false
	if params.is_empty(): return
	var new_name: String = params.NewProjectName
	project_manager.rename_project(selected_panel_display.project_path.text, new_name)


func duplicate_project_pressed() -> void:
	if selected_panel_display_is_invalid(): return
	
	screen_cover.visible = true
	duplicate_project_panel.create_new_folder.button_pressed = false
	var params: Dictionary = await duplicate_project_panel.select_params()
	screen_cover.visible = false
	if params.is_empty(): return
	var save_path: String = params.SavePath
	var project_name: String = params.ProjectName
	if !FileOperations.dir_path_string_is_valid(save_path): return
	project_manager.duplicate_project(selected_panel_display.project_path.text, save_path, project_name)


func remove_project_pressed() -> void:
	if selected_panel_display == null: return
	
	screen_cover.visible = true
	delete_project_panel.display()
	await delete_project_panel.did_something
	screen_cover.visible = false


func open_location_pressed() -> void:
	if selected_panel_display_is_invalid(): return
	FileOperations.open_file(selected_panel_display.project_path.text)
