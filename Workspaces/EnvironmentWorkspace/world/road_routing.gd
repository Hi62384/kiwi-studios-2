extends AStar3D
## Native A* construction/search. Surface and cancellation callables retain a typed bridge.
var slope_weight:=40.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","road_routing")
func _compute_cost(from_id: int,to_id: int) -> float:
	return _native().call("cost",self,from_id,to_id,slope_weight)
func _estimate_cost(from_id: int,to_id: int) -> float:
	return _native().call("estimate",self,from_id,to_id)
static func _surface_sample(state: Dictionary,point: Vector2) -> Dictionary:
	return state.surface.call(point)
static func _cancel_requested(state: Dictionary) -> bool:
	return bool(state.enabled) and bool(state.callback.call())
static func route(start: Vector3,end: Vector3,bounds: Rect2,surface: Callable,restricted: Array=[],resolution: int=49,cancel: Callable=Callable(),allow_water: bool=false) -> Dictionary:
	var state:={"surface":surface,"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("route",start,end,bounds,state,restricted,resolution,allow_water)
	state.clear(); return result
static func route_field(start: Vector3,end: Vector3,bounds: Rect2,field: RefCounted,restricted: Array=[],resolution: int=49,cancel: Callable=Callable(),allow_water: bool=false) -> Dictionary:
	var state:={"field":field,"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("route",start,end,bounds,state,restricted,resolution,allow_water)
	state.clear(); return result
static func _reachable(graph: AStar3D,enabled: Dictionary,point: Vector3,surface: Callable,restricted: Array,allow_water: bool,cancel: Callable) -> int:
	var state:={"surface":surface,"enabled":cancel.is_valid(),"callback":cancel}
	var result: int=_native().call("reachable",graph,enabled,point,state,restricted,allow_water)
	state.clear(); return result
static func _legal(a: Vector3,b: Vector3,surface: Callable,restricted: Array,allow_water: bool,cancel: Callable) -> bool:
	var state:={"surface":surface,"enabled":cancel.is_valid(),"callback":cancel}
	var result: bool=_native().call("legal",a,b,state,restricted,allow_water)
	state.clear(); return result
