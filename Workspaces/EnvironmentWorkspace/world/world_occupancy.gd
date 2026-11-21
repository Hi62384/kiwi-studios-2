extends RefCounted
## Native footprint capture and transform override detection.
static func capture(session: KiwiEnvironmentSession,id: String,source: Resource) -> String:
	return Engine.get_singleton("KiwiNativeServices").call("service","world_placement").call("capture",session,id,source)
static func _moved(item: KiwiModelComponent,pose: Transform3D) -> bool:
	return Engine.get_singleton("KiwiNativeServices").call("service","world_placement").call("moved",item,pose)
