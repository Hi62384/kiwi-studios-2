extends RefCounted
const TYPES=["Wall segment","Wall corner","Column","Pillar","Beam","Door","Window","Stairs","Railing","Floor","Roof section","Arch","Balcony","Porch","Foundation","Decorative trim"]
## Native architectural geometry and authored transactions.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","architectural_component")
static func kinds() -> Array:
	return _native().call("kinds")
static func accepts(kind: String) -> bool:
	return _native().call("accepts",kind)
static func defaults(kind: String) -> Dictionary:
	return _native().call("defaults",kind)
static func _box(mesh: KiwiModelMesh,size: Vector3,center: Vector3,material: int=0) -> void:
	_native().call("box",mesh,size,center,material)
static func normalize(parameters: Dictionary) -> Dictionary:
	return _native().call("normalize",parameters)
static func generate(kind: String,p: Dictionary) -> KiwiModelMesh:
	return _native().call("generate",kind,p)
static func _railing(mesh: KiwiModelMesh,length: float,height: float,depth: float,spacing: float,rails: int) -> void:
	_native().call("railing",mesh,length,height,depth,spacing,rails)
static func add(session: KiwiModelSession,kind: String,parameters: Dictionary,position: Vector3) -> KiwiModelComponent:
	return _native().call("add",session,kind,parameters,position)
static func _door_leaf(session: KiwiModelSession,item: KiwiModelComponent) -> void:
	_native().call("door_leaf",session,item)
static func _window_glass(session: KiwiModelSession,item: KiwiModelComponent) -> void:
	_native().call("window_glass",session,item)
static func set_parameter(session: KiwiModelSession,id: String,key: String,value: Variant) -> void:
	_native().call("set_parameter",session,id,key,value)
