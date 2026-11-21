extends RefCounted
static func procedural(runtime: Node,values: Dictionary,time: float) -> void:
	_native().procedural(runtime,values,time)
static func clear(runtime: Node) -> void:
	_native().clear(runtime)
static func apply(runtime: Node,state: Dictionary,values: Dictionary) -> Dictionary:
	return _native().apply(runtime,state,values)
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_motion_render")
