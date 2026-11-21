extends RefCounted
## Native broad phase with legacy property and static helper compatibility.
var _index:=preload("res://Workspaces/EnvironmentWorkspace/WorldSpatialIndex.cs").new()
var cell_size: float:
	get: return _index.cell_size
	set(value): _index.cell_size=value
var entries: Array[Dictionary]:
	get: return _index.entries
	set(value): _index.entries=value
var bins: Dictionary:
	get: return _index.bins
	set(value): _index.bins=value
var large: Array[int]:
	get: return _index.large
	set(value): _index.large=value
func add(bounds: Rect2,value: Variant) -> void: _index.add(bounds,value)
func query(bounds: Rect2) -> Array: return _index.query(bounds)
static func polygon_bounds(polygon: PackedVector2Array) -> Rect2:
	return Engine.get_singleton("KiwiNativeServices").call("service","world_spatial_index").call("polygon_bounds",polygon)
