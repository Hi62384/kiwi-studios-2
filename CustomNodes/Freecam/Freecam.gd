extends Node3D

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

const SENSITIVITY: float = 0.01
const MAX_SPEED = 1000
var speed: float = 5





func _get_effective_speed(delta: float) -> float:
	var effective_speed: float = speed * delta
	
	if Input.is_action_pressed("shift"):
		effective_speed *= 2
	if Input.is_action_pressed("ctrl"):
		effective_speed /= 2
	
	return effective_speed



func move_forward(delta: float) -> void:
	position -= head.transform.basis.z * _get_effective_speed(delta)



func move_backward(delta: float) -> void:
	position += head.transform.basis.z * _get_effective_speed(delta)



func move_left(delta: float) -> void:
	position -= head.transform.basis.x * _get_effective_speed(delta)



func move_right(delta: float) -> void:
	position += head.transform.basis.x * _get_effective_speed(delta)



func move_up(delta: float) -> void:
	position += camera.global_transform.basis.y * _get_effective_speed(delta)



func move_down(delta: float) -> void:
	position -= camera.global_transform.basis.y * _get_effective_speed(delta)



func look_left(amount: float) -> void:
	head.rotation.y -= amount * SENSITIVITY



func look_up(amount: float) -> void:
	camera.rotation.x = clampf(camera.rotation.x - amount * SENSITIVITY, -PI, PI)


func increase_speed(amount) -> void:
	speed = clampf(speed * (1 + amount), 0, MAX_SPEED)
