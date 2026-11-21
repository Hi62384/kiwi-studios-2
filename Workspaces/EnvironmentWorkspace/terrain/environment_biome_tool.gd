extends RefCounted
## Native authored-mask brush and sparse suitability previews.
var canvas: Control
var biome_id:=""
var _stroke: Dictionary={}
var _preview_revision:=0
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_biome_tool")
func target() -> Dictionary: return _native().call("target",self)
func input(event: InputEvent) -> bool: return _native().call("input",self,event)
func _dab(point: Vector3,invert: bool,first: bool=false) -> void: _native().call("dab",self,point,invert,first)
func cancel() -> void: _native().call("cancel",self)
