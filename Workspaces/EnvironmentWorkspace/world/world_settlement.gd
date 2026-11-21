extends RefCounted
## Settlement sources derive streets and frontage plots before any buildings.
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/BuildingSource.cs")
const Districts=preload("res://Workspaces/EnvironmentWorkspace/world/world_districts.gd")
const Spatial=preload("res://Workspaces/EnvironmentWorkspace/world/world_spatial_index.gd")
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service","world_settlement")
static func create(source: Resource,center: Vector3,profile: String="Town") -> Resource:
	return _native().call("create",source,center,profile,preload("res://Workspaces/EnvironmentWorkspace/architecture/building_styles.gd").PRESETS)
static func layout(source: Resource,cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("layout",source,state)
	state.clear(); return result
static func _overlaps_road(polygon: PackedVector2Array,road: Dictionary,points: PackedVector3Array=PackedVector3Array()) -> bool: return _native().call("overlaps_road",polygon,road,points)
static func _road_access(door: Vector3,road: Dictionary) -> Dictionary: return _native().call("road_access",door,road)
static func _cancel_requested(state: Dictionary) -> bool: return bool(state.enabled) and bool(state.callback.call())
static func build(document: KiwiModelDocument,source: Resource,generated: Dictionary,cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("build",document,source,generated,state)
	state.clear(); return result
static func _entry(authored: Resource,plot: Dictionary,road: Dictionary,world_id: String) -> KiwiModelComponent: return _native().call("entry",authored,plot,road,world_id)
static func _group(document: KiwiModelDocument,id: String,title: String,parent: String,owner: String) -> KiwiModelComponent: return _native().call("group",document,id,title,parent,owner)
static func _road(id: String,from: String,to: String,points: PackedVector3Array,width: float,settlement: String) -> Dictionary: return _native().call("road",id,from,to,points,width,settlement)
static func _rectangle(pose: Transform3D,width: float,depth: float) -> PackedVector2Array: return _native().call("rectangle",pose,width,depth)
