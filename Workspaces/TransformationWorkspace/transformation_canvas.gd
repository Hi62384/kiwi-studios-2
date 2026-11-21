class_name KiwiTransformationCanvas
extends KiwiImageCanvas
signal pivot_changed(value: Vector2)
signal reveal_point(value: Vector2)
var previewing := false
var pivot_uv := Vector2(.5,.5)
var show_grid := false
var onion: KiwiImageLayer
var pivot_before := Vector2.ZERO
func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_canvas")
func _ready() -> void:
	super._ready()
	_native().call("ready", self)
func _draw() -> void:
	var saved_tool := tool
	if previewing: tool="animation_preview"
	super._draw()
	tool=saved_tool
	_native().call("draw", self)
func _input_canvas(event: InputEvent) -> void:
	if not _native().call("input", self, event): super._input_canvas(event)
func _transform(point: Vector2, constrained: bool, control: bool=false) -> void:
	if not _native().call("transform", self, point, constrained, control): super._transform(point, constrained, control)
