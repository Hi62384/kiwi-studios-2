class_name KiwiPhysicsSettings
extends RefCounted
const TYPES := ["Rigid Body", "Soft Body", "Ragdoll / Jiggle", "Skeleton Ragdoll / Jiggle", "Cloth", "Rope"]
const MODES := ["Animated", "Simulated", "Guided", "Frozen", "Baked"]
const DEFAULTS := {
	"enabled": false, "type": 0, "mode": 1, "body_mode": 0,
	"gravity": 9.8, "gravity_direction": Vector3.DOWN, "mass": 1.0,
	"damping": 0.4, "angular_damping": 0.6, "friction": 0.5, "bounce": 0.25,
	"water_interaction":true,"water_drag":1.0,"water_buoyancy":1.0,
	"velocity": Vector3.ZERO, "angular_velocity": Vector3.ZERO, "inherit_velocity": true,
	"collision": true, "layer": 1, "mask": 1, "shape": 0, "collision_only": false,
	"activation": 0.0, "end": -1.0, "influence": 1.0, "steps": 60,
	"stiffness": 35.0, "recovery": 8.0, "stretch": 0.95, "bend": 0.2,
	"radius": 0.04, "limit": 80.0, "position_limit": 2.0, "ragdoll": false,
	"attachment": "", "attachment_bone": "", "pivot": Vector3.ZERO,
	"constraint": 0, "axis": Vector3.UP, "distance": 1.0, "body_pivot": Vector3.ZERO,
	"bones": [], "bone_settings": {}, "pins": [], "pin_region": 0,
	"particles": 128, "iterations": 8, "wind": Vector3.ZERO,
	"rope_points": 20, "rope_length": 3.0, "rope_radius": 0.035,
	"rope_start": true, "rope_end": false, "end_actor": "", "end_bone": "",
	"end_offset": Vector3.ZERO, "forces": [], "frozen": {}, "bake": {},
	"powder_accumulation":true,"powder_adhesion":0.0,"powder_max_coating":1.0
}
static func compatible(actor: ActorData) -> bool:
	return _native_settings().compatible(actor)

static func authored(actor: ActorData) -> Dictionary:
	return _native_settings().authored(actor)

static func sample(actor: ActorData, time: float) -> Dictionary:
	return _native_settings().sample(actor,time)

static func get_nested(values: Dictionary, path: PackedStringArray) -> Variant:
	return _native_settings().get_nested(values,path)

static func set_nested(values: Dictionary, path: PackedStringArray, value: Variant) -> void:
	_native_settings().set_nested(values,path,value)

static func configured(actor: ActorData) -> bool:
	return _native_settings().configured(actor)

static func edit(model: RefCounted, actor: ActorData, key: String, value: Variant) -> void:
	_native_settings().edit(model,actor,key,value)

static func assign(model: RefCounted, actor: ActorData, values: Dictionary) -> void:
	_native_settings().assign(model,actor,values)

static func remap(values: Dictionary, ids: Dictionary) -> Dictionary:
	return _native_settings().remap(values,ids)

static func pin(editor: Control, actor: ActorData, index: int, position: Vector3, remove: bool=false) -> void:
	_native_settings().pin(editor,actor,index,position,remove)

static func canonical(value: Variant) -> Variant:
	return _native_settings().canonical(value)

static func physical_groom(edits: Dictionary) -> Dictionary:
	return _native_settings().physical_groom(edits)

static func fingerprint(model: RefCounted) -> String:
	return _native_settings().fingerprint(model)

static func _native_settings() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","physics_settings")
