extends RefCounted
## Pure source edits run in C#; world transactions still install geometry/history.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","road_editing")
static func reverse(source: Resource,index: int) -> Dictionary: return _native().call("reverse",source,index)
static func remove_point(source: Resource,index: int,point: int) -> Dictionary: return _native().call("remove_point",source,index,point)
static func split(source: Resource,index: int,point: int=-1) -> Dictionary: return _native().call("split",source,index,point)
static func join(source: Resource,index: int,other: int) -> Dictionary: return _native().call("join",source,index,other)
static func _cleanup(source: Resource) -> void: _native().call("cleanup",source)
static func _result(source: Resource,index: int) -> Dictionary: return _native().call("result",source,index)
static func _error(message: String) -> Dictionary: return _native().call("error",message)
