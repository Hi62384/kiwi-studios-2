extends RefCounted
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/BuildingSource.cs")
const PRESETS={
	"Modern":[0,15.,.15,5,"stone/concrete","metal/brushed_steel"],
	"Traditional":[1,35.,.2,0,"stone/brick","wood/oak"],
	"Cottage":[1,50.,.25,1,"stone/limestone","wood/dark_aged_wood"],
	"Cabin":[1,35.,.24,2,"wood/rough_timber","wood/pine"],
	"Industrial":[2,12.,.18,6,"stone/rough_concrete","metal/rough_iron"],
	"Medieval":[3,48.,.35,1,"stone/stone_bricks","wood/dark_aged_wood"],
	"Gothic-Inspired":[1,65.,.4,3,"stone/limestone","stone/limestone"],
	"Classical-Inspired":[0,15.,.3,4,"stone/marble","stone/marble"],
	"Minimalist":[0,10.,.12,0,"stone/concrete","metal/aluminum"],
	"Stylized/Cartoon":[3,45.,.3,2,"stone/brick","wood/painted_wood"],
	"Fantasy":[3,65.,.3,7,"stone/sandstone","metal/copper"],
	"Futuristic":[2,18.,.16,5,"metal/brushed_steel","metal/aluminum"]}
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","building_styles")
static func apply(authored: Resource,name: String) -> Resource:
	return _native().call("apply",authored,name,PRESETS)
static func facade(source: Resource,floor: Dictionary,wall: Dictionary) -> KiwiModelMesh:
	return _native().call("facade",source,floor,wall)
static func _beam(mesh: KiwiModelMesh,a: Vector3,b: Vector3,width: float) -> void:
	_native().call("beam",mesh,a,b,width)
