extends RefCounted
## Native bounded, synchronized geometry cache; callback invocation stays in GD
## until all callback-producing architecture callers have native implementations.
const LIMIT=64*1024*1024
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","building_mesh_cache")
static func mesh(kind: String,fields: Array,build: Callable) -> KiwiModelMesh:
	var found: Dictionary=_native().call("lookup",kind,fields)
	if found.mesh!=null: return found.mesh
	var result: KiwiModelMesh=build.call()
	if result!=null: _native().call("store",str(found.key),result)
	return result
static func clear() -> void: _native().call("clear")
static func statistics() -> Dictionary: return _native().call("statistics")
