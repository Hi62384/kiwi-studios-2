extends RefCounted
## Native editor-only path/chamber handles and private signed-distance brush strokes.
var canvas: Control
var cave_id:=""
var path_index:=0
var point_index:=0
var strength:=1.
var _drag: Dictionary={}
var _stroke: Dictionary={}
var _hit: Dictionary={}
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_cave_tool")
func target() -> Dictionary: return _native().call("target",self)
func points(info: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	result.assign(_native().call("points",info))
	return result
func draw() -> void: _native().call("draw",self)
func input(event: InputEvent) -> bool: return _native().call("input",self,event)
func _stroke_dab(point: Vector3,invert: bool,first: bool=false) -> void: _native().call("stroke_dab",self,point,invert,first)
func _path_input(event: InputEvent,info: Dictionary) -> bool: return _native().call("path_input",self,event,info)
func _set_point(cave: KiwiTerrainCave,path_index: int,point_index: int,point: Vector3) -> void:
	_native().call("set_point",cave,path_index,point_index,point)
func cancel() -> void: _native().call("cancel",self)
