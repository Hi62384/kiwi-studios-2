extends FocusableKeyInput

const Freecam = preload("uid://65nr6lacg13d")
@onready var freecam: Freecam = $"../../../../../../../World/SubViewport/Freecam"
@onready var freecam_speed_bar: ProgressBar = $"../FreecamSpeedBar"
@onready var freecam_speed_label: Label = $"../FreecamSpeedBar/FreecamSpeedLabel"


func _process(delta: float) -> void:
	if !Input.is_action_pressed("right_click") or !is_focused():
		return
	
	if Input.is_action_pressed("move_forward"):
		freecam.move_forward(delta)
	if Input.is_action_pressed("move_backwards"):
		freecam.move_backward(delta)
	if Input.is_action_pressed("move_left"):
		freecam.move_left(delta)
	if Input.is_action_pressed("move_right"):
		freecam.move_right(delta)
	if Input.is_action_pressed("move_up"):
		freecam.move_up(delta)
	if Input.is_action_pressed("move_down"):
		freecam.move_down(delta)



func _focused_input(event: InputEvent) -> void:
	if !Input.is_action_pressed("right_click"):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		# The compact shader CodeEdit can retain GUI focus while the viewport owns
		# free-camera input. Release it so WASD/QE never become shader text.
		get_viewport().gui_release_focus()
	
	if event is InputEventMouseMotion:
		freecam.look_up(event.relative.y)
		freecam.look_left(event.relative.x)
	
	if Input.is_action_just_pressed("scroll_up"):
		freecam.increase_speed(0.1)
		_display_freecam_speed()
	elif Input.is_action_just_pressed("scroll_down"):
		freecam.increase_speed(-0.1)
		_display_freecam_speed()


var _speed_display_id: int = 0
func _display_freecam_speed() -> void:
	_speed_display_id += 1
	var current_id: int = _speed_display_id
	
	freecam_speed_bar.value = freecam.speed / freecam.MAX_SPEED
	freecam_speed_label.text = "Freecam Speed: " + str(snappedf(freecam.speed, 0.1)) + "m/s"
	
	freecam_speed_bar.visible = true
	await get_tree().create_timer(2).timeout
	
	if _speed_display_id != current_id: return
	
	freecam_speed_bar.visible = false
