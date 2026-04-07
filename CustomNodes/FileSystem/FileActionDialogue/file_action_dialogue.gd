extends Panel

const FileSystem = preload("uid://k2xqavmy8y6v")
const FileActionPanel = preload("uid://b7rja2mjbms6m")



@onready var copy_path_button: FileActionPanel = $VBoxContainer/Button2
@onready var copy_absolute_path_button: FileActionPanel = $VBoxContainer/Button9
@onready var rename_button: FileActionPanel = $VBoxContainer/Button10
@onready var duplicate_button: FileActionPanel = $VBoxContainer/Button11
@onready var delete_button: FileActionPanel = $VBoxContainer/Button12
@onready var show_in_file_manager_button: FileActionPanel = $VBoxContainer/Button13
@onready var open_in_external_program_button: Button = $VBoxContainer/Button14

@onready var _create_new_button: FileActionPanel = $VBoxContainer/Button8
@onready var _create_new_panel: Panel = $CreateNewPanel
@onready var create_new_folder_button: FileActionPanel = $CreateNewPanel/VBoxContainer/Button8

@onready var _buttons_to_hide_external_panels: Array[FileActionPanel] = [
	copy_path_button,
	copy_absolute_path_button,
	rename_button,
	duplicate_button,
	delete_button,
	show_in_file_manager_button,
	open_in_external_program_button,
]

var _file_system: FileSystem



func _ready() -> void:
	_create_new_button.mouse_entered.connect(func():
		_create_new_panel.visible = true
		)
	
	for button: FileActionPanel in _buttons_to_hide_external_panels:
		button.mouse_entered.connect(func():
			_hide_external_panels()
			)
	
	_make_fully_visible_on_screen()



func _hide_external_panels() -> void:
	_create_new_panel.visible = false



#if is sticking out of screen, clamp it to the screens edge
func _make_fully_visible_on_screen() -> void:
	var screen_size = get_viewport_rect().size
	var pos = global_position

	# Clamp X
	if pos.x < 0:
		pos.x = 0
	elif pos.x + size.x > screen_size.x:
		pos.x = screen_size.x - size.x

	# Clamp Y
	if pos.y < 0:
		pos.y = 0
	elif pos.y + size.y > screen_size.y:
		pos.y = screen_size.y - size.y

	global_position = pos



func _input(event: InputEvent) -> void:
	if Input.is_action_just_released("left_click") or Input.is_action_just_pressed("right_click"):
		await get_tree().process_frame
		queue_free()
