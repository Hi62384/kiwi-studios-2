extends RefCounted
## Native path handles, picking, snapping and transactional source edits.
var canvas: Control
var river_index:=0
var point_index:=0
var _drag: Dictionary={}
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_water_tool")
func target() -> Dictionary: return _native().call("target",self)
func path_points(info: Dictionary,index: int) -> PackedVector3Array: return _native().call("path_points",info,index)
func draw() -> void: _native().call("draw",self)
func input(event: InputEvent) -> bool: return _native().call("input",self,event)
func _remove(info: Dictionary) -> bool: return _native().call("remove",self,info)
func cancel() -> void: _native().call("cancel",self)
