extends DialogParamChooser

@onready var file_access_button: Button = $VBoxContainer/HBoxContainer3/Button
@onready var file_dialog: FileDialog = $"../FileDialog"
@onready var create_new_folder: CheckButton = $VBoxContainer/HBoxContainer2/CheckButton
@onready var directory_save_path_line_edit: LineEdit = $VBoxContainer/HBoxContainer3/LineEdit2
@onready var project_name_line_edit: LineEdit = $VBoxContainer/LineEdit

func _ready() -> void:
	super()
	file_access_button.pressed.connect(func():
		var path: String = await FileOperations.get_file_dialog_path(file_dialog)
		if path == "": return
		directory_save_path_line_edit.text = path
		)
	create_new_folder.toggled.connect(func(toggled_on: bool):
		if toggled_on:
			#spaghetti code to add a '\' at end of path if doent already have one
			if directory_save_path_line_edit.text[directory_save_path_line_edit.text.length()-1] != '/': directory_save_path_line_edit.text += "/"
			directory_save_path_line_edit.text = directory_save_path_line_edit.text + project_name_line_edit.text  
		else:
			directory_save_path_line_edit.text = directory_save_path_line_edit.text.get_base_dir()
		)
