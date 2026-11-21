extends RefCounted
## Rigid closed-mesh occupancy, with bounded native sampling and cache.
static var cache: Dictionary={}
static var revisions: Dictionary={}
static var stamps: Dictionary={}
static func prepare(path: String) -> Dictionary:
	return Engine.get_singleton("KiwiNativeServices").service("fog_mesh").prepare(path)
