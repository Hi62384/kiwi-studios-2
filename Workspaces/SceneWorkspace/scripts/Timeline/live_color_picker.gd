class_name LiveColorPickerButton
extends ColorPickerButton
## Color changes preview immediately; each pointer gesture creates one undo step.

signal interaction_started
signal interaction_ended
signal preview_changed(value: Color)
signal drag_committed(original: Color, value: Color)
signal drag_cancelled(original: Color)

var dragging: bool = false
var _origin: Color
var _pending_origin: Color
var _session_active: bool = false
var _suppress_preview: bool = false
var _swatch: ColorRect


func _ready() -> void:
	_swatch = ColorRect.new()
	_swatch.name = "ColorSwatch"
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_swatch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_swatch.offset_left = 7
	_swatch.offset_top = 6
	_swatch.offset_right = -7
	_swatch.offset_bottom = -6
	_swatch.color = color
	add_child(_swatch)
	move_child(_swatch, 0)
	color_changed.connect(_on_color_changed)
	popup_closed.connect(_on_popup_closed)
	pressed.connect(begin_session)
	tooltip_text = "Changes preview live. Each drag is one undo step."


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and dragging:
		cancel_drag()


func _process(_delta: float) -> void:
	# ColorPicker can live in an embedded popup viewport, so polling the global
	# button state is more reliable than waiting for its release event here.
	if dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		finish_drag()


func begin_session() -> void:
	_session_active = true
	_pending_origin = color


func begin_drag() -> void:
	if dragging:
		return
	dragging = true
	_origin = _pending_origin if _session_active else color
	interaction_started.emit()


func _on_color_changed(value: Color) -> void:
	_update_swatch(value)
	if _suppress_preview or not get_popup().visible:
		return
	if not dragging:
		begin_drag()
	preview_changed.emit(value)


func _on_popup_closed() -> void:
	if dragging:
		finish_drag()
	# Defensive cleanup for popup/window event routing on every close path.
	interaction_ended.emit()
	_session_active = false


func finish_drag() -> void:
	if not dragging:
		return
	var original := _origin
	var final_value := color
	dragging = false
	_pending_origin = final_value
	interaction_ended.emit()
	if original != final_value:
		drag_committed.emit(original, final_value)


func cancel_drag() -> void:
	if not dragging:
		return
	var original := _origin
	dragging = false
	set_color_silent(original)
	_pending_origin = original
	interaction_ended.emit()
	drag_cancelled.emit(original)


func set_color_silent(value: Color) -> void:
	_suppress_preview = true
	color = value
	_update_swatch(value)
	_suppress_preview = false
	if not dragging:
		_pending_origin = value


func _update_swatch(value: Color) -> void:
	if is_instance_valid(_swatch):
		_swatch.color = value


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		cancel_drag()
