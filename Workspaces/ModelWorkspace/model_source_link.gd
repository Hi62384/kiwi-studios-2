extends RefCounted
## Type/default interfaces and environment-revision bridge during migration.
static func _native() -> RefCounted:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_source_link")
static var _resources: Dictionary:
	get: return _native().get("_resources")
	set(value): _native().set("_resources",value)
static var _instances: Dictionary:
	get: return _native().get("_instances")
	set(value): _native().set("_instances",value)
static var _revisions: Dictionary:
	get: return _native().get("_revisions")
	set(value): _native().set("_revisions",value)
static var _resolved: Dictionary:
	get: return _native().get("_resolved")
	set(value): _native().set("_resolved",value)
static func _asset_revision(path: String) -> int: return int(KiwiEnvironmentAssets.revisions.get(path,0))
static func _asset_generation() -> int: return KiwiEnvironmentAssets.generation
static func _path(path: String) -> String: return _native()._path(path)
static func invalidate(path: String) -> void: _native().invalidate(path)
static func load_resource(path: String) -> Resource: return _native().load_resource(path)
static func resolved_resource(path: String) -> Resource: return _native().resolved_resource(path)
static func register_actor(actor: ActorData,runtime: Node=null) -> bool: return _native().register_actor(actor,runtime)
static func _actor(entry: Dictionary) -> ActorData: return _native()._actor(entry)
static func refresh(actor: ActorData,path: String) -> bool: return _native().refresh(actor,path)
static func _mapped_structure(settings: Dictionary,mapping: Dictionary) -> Dictionary: return _native()._mapped_structure(settings,mapping)
static func _reconcile(actor: ActorData,old: Variant,next: Variant,current: Variant,path: PackedStringArray) -> Variant: return _native()._reconcile(actor,old,next,current,path)
static func _same(one: Variant,two: Variant) -> bool: return _native()._same(one,two)
