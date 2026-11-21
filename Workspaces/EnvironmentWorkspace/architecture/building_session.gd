extends RefCounted
## Typed compatibility API; regeneration and history integration execute in C#.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","building_session")
static func source(item: KiwiModelComponent) -> Resource:
	return _native().call("source",item)
static func owner(session: KiwiModelSession,item: KiwiModelComponent) -> KiwiModelComponent:
	return _native().call("owner",session,item)
static func add(session: KiwiModelSession,position:=Vector3.ZERO,levels: int=1) -> KiwiModelComponent:
	return _native().call("add",session,position,levels)
static func update(session: KiwiModelSession,id: String,authored: Resource,label: String="Edit building",preview: bool=false,force: bool=false,prepared: Dictionary={}) -> Dictionary:
	return _native().call("update",session,id,authored,label,preview,force,prepared)
static func _source_key(value: Resource) -> int:
	return _native().call("source_key",value)
static func _mark(item: KiwiModelComponent) -> void:
	_native().call("mark",item)
static func _environment_settings(session: KiwiModelSession,item: KiwiModelComponent) -> void:
	_native().call("environment_settings",session,item)
static func set_material(session: KiwiModelSession,id: String,slot: int,material: Material) -> void:
	_native().call("set_material",session,id,slot,material)
static func reset_overrides(session: KiwiModelSession,id: String,component_id: String) -> Dictionary:
	return _native().call("reset_overrides",session,id,component_id)
