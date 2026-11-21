extends RefCounted
## Native source resolution, override tracking and transactional linked updates.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","module_links")
static func _parameters(item: KiwiModelComponent) -> Dictionary:
	return _native().call("parameters",item)
static func bind(item: KiwiModelComponent,owner: String,source_id: String) -> void:
	_native().call("bind",item,owner,source_id)
static func growth_key(growth: KiwiSurfaceGrowthData) -> int:
	return _native().call("growth_key",growth)
static func _load(path: String,chain: PackedStringArray,cache: Dictionary) -> Dictionary:
	return _native().call("load",path,chain,cache)
static func _replace(document: KiwiModelDocument,id: String,source: KiwiModelDocument,reset: bool) -> String:
	return _native().call("replace",document,id,source,reset)
static func refresh(session: KiwiModelSession,id: String,reset: bool=false) -> String:
	return _native().call("refresh",session,id,reset)
static func resolve(document: KiwiModelDocument) -> Dictionary:
	return _native().call("resolve",document)
static func depends_on(path: String,target: String) -> bool:
	return _native().call("depends_on",path,target)
static func _depends_on(path: String,target: String,visited: Dictionary) -> bool:
	return _native().call("depends_on_visited",path,target,visited)
static func refresh_changed(session: KiwiModelSession,path: String) -> String:
	return _native().call("refresh_changed",session,path)
static func make_unique(session: KiwiModelSession,id: String) -> void:
	_native().call("make_unique",session,id)
