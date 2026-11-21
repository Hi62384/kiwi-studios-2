extends RefCounted
## Continuous strip, junction and curve topology runs in C#.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","road_geometry")
static func sample(points: PackedVector3Array,spacing: float=2.) -> PackedVector3Array:
	return _native().call("sample",points,spacing)
static func trim(points: PackedVector3Array,start: float,end: float) -> PackedVector3Array:
	return _native().call("trim",points,start,end)
static func strip(points: PackedVector3Array,width: float,offset: float=0.,sections: Dictionary={}) -> KiwiModelMesh:
	return _native().call("strip",points,width,offset,sections)
static func junction(center: Vector3,ends: Array) -> KiwiModelMesh:
	return _native().call("junction",center,ends)
