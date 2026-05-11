extends FocusableKeyInput

const FileSystemExtraUi = preload("uid://btkxwby3ldicm")
const FileSystemCallableActions = preload("uid://b5gm21p0e2sbv")
@onready var file_system_extra_ui: FileSystemExtraUi = $"../FileSystemExtraUI"
@onready var file_system_callable_actions: FileSystemCallableActions = $"../FileSystemCallableActions"

func _focused_input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("redo"):
		file_system_callable_actions.redo()
	elif Input.is_action_just_pressed("undo"):
		file_system_callable_actions.undo()
	elif Input.is_action_just_pressed("alternate_copy"):
		file_system_extra_ui.copy_absolute_file_path()
	elif Input.is_action_just_pressed("copy"):
		file_system_extra_ui.copy_file_path()
	elif Input.is_action_just_pressed("delete"):
		file_system_extra_ui.show_delete_options()
	elif Input.is_action_just_pressed("duplicate"):
		file_system_extra_ui.duplicate_files()
	elif Input.is_action_just_pressed("rename"):
		file_system_extra_ui.rename_file()
	
