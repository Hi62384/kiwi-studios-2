class_name DragNumber
extends SpinBox
## Drag the text horizontally. Click without moving to enter a number normally.
signal interaction_started
signal interaction_ended
signal preview_changed(value: float)
signal drag_committed(value: float)
signal drag_cancelled
var dragging: bool = false
var _pressed: bool = false
var _origin: float
var _press_x: float
var _last_x: float
var _remainder: float = 0.0


func _ready() -> void:
	get_line_edit().mouse_default_cursor_shape = Control.CURSOR_HSIZE
	tooltip_text = "Drag: 0.1 • Ctrl: 1 • Shift: 0.01. Click to type."
	get_line_edit().gui_input.connect(_line_edit_input)

func _line_edit_input(event: InputEvent) -> void:
	# Begin only through GUI hit testing, which respects frontmost controls and
	# ScrollContainer clipping. Global input is reserved for an existing gesture.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and editable:
		_begin_drag(get_line_edit().get_global_transform_with_canvas() * event.position)
		get_line_edit().accept_event()

func _begin_drag(position: Vector2) -> void:
	_pressed = true
	_origin = value
	_press_x = position.x
	_last_x = _press_x
	_remainder = 0.0


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and _pressed:
			if dragging:
				finish_drag()
			else:
				_pressed = false
				get_line_edit().grab_focus()
				get_line_edit().select_all()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _pressed:
		if not dragging and absf(event.position.x - _press_x) >= 4.0:
			dragging = true
			interaction_started.emit()
		if dragging:
			drag_pixels(event.position.x - _last_x, event.ctrl_pressed, event.shift_pressed)
			_last_x = event.position.x
			_wrap_pointer(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and _pressed:
		if event.keycode == KEY_ESCAPE:
			cancel_drag()
		# Do not let undo/redo/delete execute in the middle of a value gesture.
		get_viewport().set_input_as_handled()


func drag_pixels(pixels: float, ctrl: bool, shift: bool) -> void:
	_remainder += pixels
	var ticks := int(_remainder / 4.0)
	_remainder -= ticks * 4.0
	# Integer editors use a whole-number tick. Previously their 0.1 preview was
	# truncated by the property setter, making slow drags appear unresponsive.
	var integer_step:=step>=1.0 and is_equal_approx(step,round(step))
	var increment := step if integer_step else (0.01 if shift else (1.0 if ctrl else 0.1))
	set_value_no_signal(value + ticks * increment)
	if ticks != 0:
		preview_changed.emit(value)


## Wrap inside the editor viewport, including when the editor is windowed.
## Rebase the drag before warping so the jump never changes the numeric value.
func _wrap_pointer(position: Vector2) -> void:
	var target := wrap_target(position, get_viewport().get_visible_rect())
	if target == position:
		return
	_last_x = target.x
	if DisplayServer.get_name() != "headless":
		get_viewport().warp_mouse(target)


static func wrap_target(position: Vector2, bounds: Rect2) -> Vector2:
	if bounds.size.x < 12 or bounds.size.y < 12:
		return position
	var target := position
	if position.x >= bounds.end.x - 2:
		target.x = bounds.position.x + 4
	elif position.x <= bounds.position.x + 2:
		target.x = bounds.end.x - 4
	if position.y >= bounds.end.y - 2:
		target.y = bounds.position.y + 4
	elif position.y <= bounds.position.y + 2:
		target.y = bounds.end.y - 4
	return target


func finish_drag() -> void:
	var final_value := value
	_pressed = false
	dragging = false
	interaction_ended.emit()
	if not is_equal_approx(_origin, final_value):
		drag_committed.emit(final_value)


func cancel_drag() -> void:
	var was_dragging := dragging
	if _pressed:
		set_value_no_signal(_origin)
	_pressed = false
	dragging = false
	interaction_ended.emit()
	if was_dragging:
		drag_cancelled.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		cancel_drag()
