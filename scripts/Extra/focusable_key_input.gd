class_name FocusableKeyInput
##when control is clicked, instance gains focus globally amongst-
## all FocusableKeyInput instances, allows key inputs to be passed
extends Control

static var current_focused_instance: FocusableKeyInput



func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _is_mouse_inside_self() -> bool:
	var mouse_pos = get_viewport().get_mouse_position()
	var rect = Rect2(global_position, size)
	return rect.has_point(mouse_pos)


func _input(_event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if _event is InputEventMouseButton and _event.button_index == MOUSE_BUTTON_RIGHT \
			and _event.pressed and _is_mouse_inside_self():
		FocusableKeyInput.current_focused_instance = self
		get_viewport().gui_release_focus()
	if (Input.is_action_just_pressed("left_click") or Input.is_action_just_pressed("right_click")) and _is_mouse_inside_self():
		FocusableKeyInput.current_focused_instance = self
	
	if FocusableKeyInput.current_focused_instance == self:
		_focused_input(_event)


func is_focused() -> bool:
	return current_focused_instance == self


##OVERRRIDE FUNCTION
func _focused_input(event: InputEvent) -> void:
	pass
