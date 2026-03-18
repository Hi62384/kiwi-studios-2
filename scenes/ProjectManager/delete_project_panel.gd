extends Panel

const ProjectManagerUi = preload("uid://cimwjbgwqiug0")

@onready var close_button: Button = $VBoxContainer/HBoxContainer/Button
@onready var remove_from_listing_button: Button = $VBoxContainer/RemoveFromListing
@onready var to_recyle_bin_button: Button = $VBoxContainer/ToRecyleBinButton
@onready var delete_button: Button = $VBoxContainer/DeleteButton
@onready var project_name_label: Label = $VBoxContainer/Label

@onready var project_manager_ui: ProjectManagerUi = $".."


signal did_something


func _ready() -> void:
	close_button.pressed.connect(func():
		do_something()
		)
	
	remove_from_listing_button.pressed.connect(func():
		project_manager_ui.project_manager.remove_project_from_listing(project_manager_ui.selected_panel_display.project_path.text)
		do_something()
		)
	
	to_recyle_bin_button.pressed.connect(func():
		project_manager_ui.project_manager.unalive_project_directory(project_manager_ui.selected_panel_display.project_path.text, true)
		do_something()
		)
	
	delete_button.pressed.connect(func():
		project_manager_ui.project_manager.unalive_project_directory(project_manager_ui.selected_panel_display.project_path.text, false)
		do_something()
		)


func display() -> void:
	visible = true
	project_name_label.text = project_manager_ui.selected_panel_display.project_name.text


func do_something() -> void:
	visible = false
	did_something.emit()
