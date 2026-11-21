extends RefCounted
## Native volumetric cave field assembly; shared suitability definitions remain linked.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","terrain_cave_biomes")
static func generate(terrain: Resource,cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("generate",terrain,state)
	state.clear()
	return result
static func query(terrain: Resource,point: Vector3) -> Dictionary: return _native().call("query",terrain,point)
static func _void(point: Vector3,sources: Array[KiwiTerrainCave]) -> float: return _native().call("void_distance",point,sources)
