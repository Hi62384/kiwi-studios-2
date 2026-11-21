class_name ActorValueCurve
extends Control
## Normalized outgoing interpolation curve. Interior points can be added,
## dragged, or removed; endpoints keep progress anchored at zero and one.

signal edit_started
signal preview_changed(curve: Curve)
signal edit_committed
signal edit_cancelled

var curve: Curve
var editable := false
var stepped := false
var _drag_point := -1
var _before: Curve
var selected_point := 0
var _drag_handle := 0

static func preset(name: String) -> Curve:
	return _native_curve().preset(name)

static func for_key(key: ActorKeyframe) -> Curve:
	return _native_curve().for_key(key)

static func template_value(name: String, adjustment: float, x: float) -> float:
	return _native_curve().template_value(name,adjustment,x)

static func template(name: String, adjustment: float) -> Curve:
	return _native_curve().template(name,adjustment)

func graph_rect() -> Rect2:
	return _native_curve().graph_rect(self)

func reset_tangents() -> void:
	_native_curve().reset_tangents(self)

func graph_point(point: Vector2) -> Vector2:
	return _native_curve().graph_point(self,point)

func tangent_position(index: int, side: int) -> Vector2:
	return _native_curve().tangent_position(self,index,side)

func _draw() -> void:
	_native_curve().draw(self)

func _style() -> StyleBoxFlat:
	return _native_curve().style()

func _gui_input(event: InputEvent) -> void:
	_native_curve().gui_input(self,event)

func _normalized(position: Vector2) -> Vector2:
	return _native_curve().normalized(self,position)

func cancel_edit() -> void:
	_native_curve().cancel_edit(self)

func _input(event: InputEvent) -> void:
	_native_curve().input(self,event)

static func _native_curve() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("value_curve")
