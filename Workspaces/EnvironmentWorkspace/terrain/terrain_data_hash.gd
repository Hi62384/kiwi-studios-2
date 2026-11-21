extends RefCounted
## Preserve historical generated-data signatures with native canonical traversal.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_data_hash")
static func value(data: Variant) -> int: return _native().call("value",data)
static func _ordered(data: Variant,seen: Dictionary,depth: int) -> Variant:
	return _native().call("ordered",data,seen,depth)
