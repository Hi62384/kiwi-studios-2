extends RefCounted
## Native connected convex cells preserve door and shaft clearances.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","building_collision")
static func parts(mesh: KiwiModelMesh) -> Array:
	return _native().call("parts",mesh)
static func _root(parents: PackedInt32Array,index: int) -> int:
	return _native().call("root",parents,index)
