extends RefCounted
const TYPES=["Highway","Major Road","Secondary Road","Residential Street","Rural Road","Dirt Road","Forest Track","Pedestrian Path","Mountain Road","Custom Road"]
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","road_section")
static func defaults(type: String="Residential Street") -> Dictionary: return _native().call("defaults",type)
static func prepare(source: Resource) -> void: _native().call("prepare",source)
static func outer_half(road: Dictionary) -> float: return _native().call("outer_half",road)
static func material(source: Resource,road: Dictionary,part: String="surface") -> Material: return _native().call("material",source,road,part)
static func validate(road: Dictionary) -> PackedStringArray: return _native().call("validate",road)
static func _cancel_requested(state: Dictionary) -> bool: return bool(state.enabled) and bool(state.callback.call())
static func build(points: PackedVector3Array,road: Dictionary,cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("build",points,road,state)
	state.clear(); return result
static func _band(points: PackedVector3Array,width: float,offset: float,height: float,depth: float,sections: Dictionary={}) -> KiwiModelMesh:
	return _native().call("band",points,width,offset,height,depth,sections)
static func _solid(mesh: KiwiModelMesh,depth: float) -> KiwiModelMesh: return _native().call("solid",mesh,depth)
static func junction_details(ends: Array) -> Dictionary: return _native().call("junction_details",ends)
static func _append(result: Dictionary,key: String,mesh: KiwiModelMesh) -> void: _native().call("append",result,key,mesh)
static func _slice(points: PackedVector3Array,cumulative: PackedFloat32Array,start: float,end: float) -> PackedVector3Array:
	return _native().call("slice",points,cumulative,start,end)
