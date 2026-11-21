extends RefCounted
## Native foundation projection and link refresh within existing terrain history.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","building_foundation")
static func set_modifier(session: KiwiEnvironmentSession,id: String,terrain_id: String,feather: float=1.,remove: bool=false) -> String:
	return _native().call("set_modifier",session,id,terrain_id,feather,remove)
static func remove_for_owners(session: KiwiEnvironmentSession,removed: Dictionary) -> void:
	_native().call("remove_for_owners",session,removed)
static func refresh_links(session: KiwiEnvironmentSession) -> void:
	_native().call("refresh_links",session)
