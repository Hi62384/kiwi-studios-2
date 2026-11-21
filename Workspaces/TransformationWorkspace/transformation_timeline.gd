class_name KiwiTransformationTimeline
extends Control
signal selection_changed
signal seek(time: float)
signal gesture_finished
var session: KiwiTransformationSession
var pixels_per_second := 150.
var offset := 0.
var vertical := 0
var drag := ""
var start := Vector2.ZERO
var original: Dictionary={}
var label_width := 140.
const ROW := 26.
func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_timeline")
func _ready() -> void: _native().call("ready", self)
func x(time: float) -> float: return _native().call("x", self, time)
func time_at(value: float) -> float: return _native().call("time_at", self, value)
func row_y(index: int) -> float: return _native().call("row_y", self, index)
func hit(point: Vector2) -> Dictionary: return _native().call("hit", self, point)
func _draw() -> void: _native().call("draw", self)
func _gui_input(event: InputEvent) -> void: _native().call("input", self, event)
