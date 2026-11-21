extends RefCounted
static func create(base: ActorDefinition) -> ActorDefinition:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_actor_definition").call("create",base)
