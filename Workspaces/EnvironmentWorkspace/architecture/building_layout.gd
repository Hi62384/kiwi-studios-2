extends RefCounted
## Authored compatibility API; layout and navigation algorithms run in C#.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","building_layout")
static func generate(authored: Resource,room_count: int=5,corridor_width: float=1.2,types: PackedStringArray=PackedStringArray(),weights: PackedFloat32Array=PackedFloat32Array()) -> Dictionary:
	return _native().call("generate",authored,room_count,corridor_width,types,weights)
static func _rectangle(polygon: PackedVector2Array,bounds: Rect2) -> bool:
	return _native().call("rectangle",polygon,bounds)
static func _polygon(rect: Rect2) -> PackedVector2Array:
	return _native().call("polygon",rect)
static func connectivity(source: Resource) -> Dictionary:
	return _native().call("connectivity",source)
static func stair_endpoints(stair: Dictionary) -> PackedVector2Array:
	return _native().call("stair_endpoints",stair)
static func _region(floor: Dictionary,point: Vector2,source: Resource) -> String:
	return _native().call("region",floor,point,source)
