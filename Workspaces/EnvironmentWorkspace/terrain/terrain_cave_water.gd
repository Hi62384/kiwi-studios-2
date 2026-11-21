extends RefCounted
## Native bounded hydrostatic cave connectivity, mesh clipping and queries.
const DRY:=-1.0e20
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","terrain_cave_water")
static func generate(terrain: Resource,cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("generate",terrain,state)
	state.clear()
	return result
static func query(terrain: Resource,point: Vector3) -> Dictionary: return _native().call("query",terrain,point)
static func _void(point: Vector3,sources: Array[KiwiTerrainCave]) -> float: return _native().call("void_distance",point,sources)
static func _clip(points: Array[Vector3],field: PackedFloat32Array) -> Array[Vector3]:
	var result: Array[Vector3]=[]
	result.assign(Array(_native().call("clip",PackedVector3Array(points),field)))
	return result
