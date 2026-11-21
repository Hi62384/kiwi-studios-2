class_name KiwiStructure
extends RefCounted
const TYPES:=["Weld / fixed","Hinge","Slider","Cable / distance","Spring"]
const ROLES:=["Dynamic element","Fixed foundation","Animated support"]
static func extend_actor(d: ActorDefinition) -> void:
	_native_structure().extend_actor(d)

static func connection(target: String,pivot: Vector3=Vector3.ZERO,target_pivot: Vector3=Vector3.ZERO,kind: int=0) -> Dictionary:
	return _native_structure().connection(target,pivot,target_pivot,kind)

static func assign(reference: WeakRef,entries: Array) -> void:
	_native_structure().assign(reference,entries)

static func commit(model: ActorTimeline,actors: Array[ActorData],updates: Array[Dictionary],label: String) -> void:
	_native_structure().commit(model,actors,updates,label)

static func set_value(model: ActorTimeline,actor: ActorData,id: String,key: String,value: Variant,preview: bool=false) -> void:
	_native_structure().set_value(model,actor,id,key,value,preview)

static func connect_actors(model: ActorTimeline,a: ActorData,b: ActorData,point: Vector3,pose_a: Transform3D,pose_b: Transform3D,kind: int=0) -> String:
	return _native_structure().connect_actors(model,a,b,point,pose_a,pose_b,kind)

static func remap_actor(actor: ActorData,ids: Dictionary,clear_external: bool=true) -> void:
	_native_structure().remap_actor(actor,ids,clear_external)

static func candidates(actors: Array[ActorData],bounds: Dictionary,tolerance: float) -> Array[Dictionary]:
	return _native_structure().candidates(actors,bounds,tolerance)

static func _native_structure() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","structure_definition")
