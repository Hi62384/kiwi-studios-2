class_name KiwiPowderSource
extends RefCounted
## Pure generation; no integration, collisions, liquid pressure or renderer dependency.
const APPEARANCE := ["powder_color","powder_roughness","powder_show_source"]
const ARRAYS := ["powder_ids","powder_radii","powder_masses","powder_birth_times","powder_birth_positions","powder_sources","powder_compaction","powder_sleep","powder_contacts","powder_phase","powder_settle"]
static func validate(values: Dictionary) -> String:
	return _native_source().validate(values)

static func volume(values: Dictionary,pose: Transform3D,geometry: Dictionary={}) -> Dictionary:
	return _native_source().volume(values,pose,geometry)

static func initialize(state: Dictionary) -> void:
	_native_source().initialize(state)

static func append(state: Dictionary,point: Vector3,velocity: Vector3,values: Dictionary,pose: Transform3D,birth: float,source: int) -> void:
	_native_source().append(state,point,velocity,values,pose,birth,source)

static func rng_for(seed: int,id: int) -> RandomNumberGenerator:
	return _native_source().rng_for(seed,id)

static func spawn(state: Dictionary,values: Dictionary,pose: Transform3D,velocity: Vector3,birth: float) -> void:
	_native_source().spawn(state,values,pose,velocity,birth)

static func _native_source() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","powder_source")
