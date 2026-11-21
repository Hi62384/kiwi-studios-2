extends RefCounted
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","road_structures")
static func _ground_sample(state: Dictionary,point: Vector2) -> Dictionary: return state.callback.call(point)
static func bridge(points: PackedVector3Array,width: float,pier_height: float=8.,ground: Callable=Callable(),sections: Dictionary={}) -> Dictionary:
	var state:={"enabled":ground.is_valid(),"callback":ground}
	var result: Dictionary=_native().call("bridge",points,width,pier_height,state,sections)
	state.clear(); return result
static func portals(points: PackedVector3Array,width: float,start: bool=true,end: bool=true,frames: Array=[]) -> KiwiModelMesh:
	return _native().call("portals",points,width,start,end,frames)
