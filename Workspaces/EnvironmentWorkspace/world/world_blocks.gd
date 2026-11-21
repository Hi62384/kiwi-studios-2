extends RefCounted
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service","world_blocks")
static func _cancel_requested(state: Dictionary) -> bool: return bool(state.enabled) and bool(state.callback.call())
static func extract(graph: Dictionary,cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("extract",graph,state)
	state.clear(); return result
static func _cycle_edges(graph: Dictionary) -> Array: return _native().call("cycle_edges",graph)
static func plots(block: Dictionary,settlement: Dictionary,budget: int,cancel: Callable=Callable()) -> Array[Dictionary]:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Array[Dictionary]=_native().call("plots",block,settlement,budget,state)
	state.clear(); return result
static func fit(polygon: PackedVector2Array,boundary: Array,cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("fit",polygon,boundary,state)
	state.clear(); return result
static func contains_rectangle(polygon: PackedVector2Array,pose: Transform3D,width: float,depth: float) -> bool: return _native().call("contains_rectangle",polygon,pose,width,depth)
static func _frontage(point: Vector2,boundary: Array) -> Dictionary: return _native().call("frontage",point,boundary)
static func _bounds(polygon: PackedVector2Array) -> Rect2: return _native().call("bounds",polygon)
static func _area(polygon: PackedVector2Array) -> float: return _native().call("area",polygon)
static func _simplify(polygon: PackedVector2Array) -> PackedVector2Array: return _native().call("simplify",polygon)
