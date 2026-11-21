extends RefCounted
## Editable multi-part native models, shared by ordinary scatter palettes.
const NAMES=["Park bench","Street lamp","Bollard","Direction sign","Wood fence","Stone boundary","Supply crates","Rock cluster"]
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","world_prop_library")
static func model(kind: String) -> KiwiModelDocument: return _native().call("model",kind)
static func _material(color: Color) -> StandardMaterial3D: return _native().call("material",color)
static func _part(document: KiwiModelDocument,title: String,shape: String,settings: Dictionary,position: Vector3,material: Material) -> void:
	_native().call("part",document,title,shape,settings,position,material)
static func add(source: Resource,kind: String) -> Resource: return _native().call("add",source,kind)
