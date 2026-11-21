extends RefCounted
## Native scatter sources, not a second tree renderer or one node per tree.
const Natural=preload("res://Workspaces/ModelWorkspace/natural_generator.gd")
const DataHash=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd")
const PROFILES=["Temperate Forest","Conifer Forest","Tropical Jungle","Alpine Forest","Sparse Woodland","Swamp Forest","Dry Woodland","Custom Forest"]
const SPECIES={
	"Temperate Forest":[["Tree / Oak","Tree / Birch"],["Tree / Maple"],["Plant / Bush","Plant / Fern"],["Plant / Grass","Plant / Mushroom"]],
	"Conifer Forest":[["Tree / Pine","Tree / Spruce"],["Tree / Fir"],["Plant / Fern"],["Plant / Grass","Prop / Log"]],
	"Tropical Jungle":[["Tree / Tropical","Tree / Palm"],["Tree / Tropical"],["Plant / Fern","Plant / Bush"],["Plant / Grass","Prop / Root"]],
	"Alpine Forest":[["Tree / Fir","Tree / Pine"],["Tree / Spruce"],["Plant / Bush"],["Plant / Grass","Rock / Granite"]],
	"Sparse Woodland":[["Tree / Oak","Tree / Birch"],["Tree / Maple"],["Plant / Bush"],["Plant / Grass","Plant / Flower"]],
	"Swamp Forest":[["Tree / Mangrove","Tree / Willow"],["Tree / Willow"],["Plant / Reed","Plant / Fern"],["Plant / Mushroom","Prop / Log"]],
	"Dry Woodland":[["Tree / Acacia","Tree / Desert"],["Tree / Acacia"],["Plant / Succulent"],["Rock / Sandstone","Prop / Stump"]],
	"Custom Forest":[["Tree / Oak"],["Tree / Birch"],["Plant / Bush"],["Plant / Grass"]]}
const LAYERS=["Canopy","Subcanopy","Understory","Ground"]
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","world_forests")
static func _cancel_requested(state: Dictionary) -> bool: return bool(state.enabled) and bool(state.callback.call())
static func create(source: Resource,center: Vector3,profile: String="Temperate Forest") -> Resource:
	return _native().call("create",source,center,profile,SPECIES)
static func build(document: KiwiModelDocument,source: Resource,layout: Dictionary,graph: Dictionary,cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("build",document,source,layout,graph,state)
	state.clear(); return result
static func _component(source: Resource,key: String,title: String,parent: String) -> KiwiModelComponent:
	return _native().call("component",source,key,title,parent)
static func baseline(rules: KiwiEnvironmentScatter) -> Dictionary: return _native().call("baseline",rules)
static func preserve(old: KiwiEnvironmentScatter,rules: KiwiEnvironmentScatter,defaults: Dictionary) -> void: _native().call("preserve",old,rules,defaults)
static func _rectangle(bounds: Rect2,pose: Transform3D) -> PackedVector2Array: return _native().call("rectangle",bounds,pose)
static func _polygon(polygon: PackedVector2Array,pose: Transform3D) -> PackedVector2Array: return _native().call("polygon",polygon,pose)
static func _development(source: Resource,layout: Dictionary,graph: Dictionary,pose: Transform3D,sidewalks: bool=false) -> Array[PackedVector2Array]:
	return _native().call("development",source,layout,graph,pose,sidewalks)
