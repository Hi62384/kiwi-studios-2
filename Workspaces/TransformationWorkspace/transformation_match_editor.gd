class_name KiwiTransformationMatchEditor
extends PopupPanel
var workspace: KiwiTransformationWorkspace
var component_id := ""
var key_id := ""
var next_state_id := ""
var surface: MatchSurface
var overlays := true
class MatchSurface extends Control:
	var host: KiwiTransformationMatchEditor
	var pending: Variant=null
	var drag := -1
	var side := 0
	var selected_pair := -1
	func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_match")
	func rect(index: int) -> Rect2: return _native().call("rect", self, index)
	func _draw() -> void: _native().call("draw", self)
	func _gui_input(event: InputEvent) -> void: _native().call("input", self, event)

func _create_surface() -> MatchSurface: return MatchSurface.new()
func key() -> KiwiTransformationKey: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_match").call("key", self)
func open() -> void: Engine.get_singleton("KiwiNativeServices").call("service", "transformation_match").call("open", self)
