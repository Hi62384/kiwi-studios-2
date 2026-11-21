extends RefCounted
## Material/distance snapshot reuse runs natively without regenerating topology.
static func snapshot(session: KiwiEnvironmentSession,id: String,desired: Resource) -> Dictionary:
	return Engine.get_singleton("KiwiNativeServices").call("service","world_visual_edit").call("snapshot",session,id,desired)
