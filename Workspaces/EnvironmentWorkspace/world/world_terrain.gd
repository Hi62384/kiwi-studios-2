extends RefCounted
## Native world/terrain coordinate fitting, grading and excavation planning.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","world_terrain")
static func context(session: KiwiEnvironmentSession,id: String,source: Resource) -> Dictionary: return _native().call("context",session,id,source)
static func sample(info: Dictionary,point: Vector2) -> Dictionary: return _native().call("sample",info,point)
static func fit(session: KiwiEnvironmentSession,id: String,source: Resource,index: int,automatic: bool=false) -> Dictionary:
	return _native().call("fit",session,id,source,index,automatic)
static func grade(session: KiwiEnvironmentSession,id: String,source: Resource,remove: bool=false) -> String:
	return _native().call("grade",session,id,source,remove)
static func grading_plan(session: KiwiEnvironmentSession,id: String,source: Resource,remove: bool=false) -> Dictionary:
	return _native().call("grading_plan",session,id,source,remove)
static func tunnels_plan(session: KiwiEnvironmentSession,id: String,source: Resource) -> Dictionary:
	return _native().call("tunnels_plan",session,id,source)
