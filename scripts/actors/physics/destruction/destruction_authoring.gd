class_name KiwiDestructionAuthoring
extends RefCounted
## Authored source data, simulated guidance, and display-only corrections remain
## separate. A correction never changes the cached collision trajectory.
const NON_GEOMETRY := [12,13,14]
const GEOMETRY_FIELDS := ["type","enabled","position","direction","radius","amount","falloff","pieces","seed","irregularity","anisotropy","grain_direction","branching","path","region_enabled","region_center","region_radius"]
const SETUP_FIELDS := [&"destruction_operations",&"destruction_fragments",&"destruction_material",&"destruction_region",&"destruction_region_2",&"destruction_mode",&"debris_secondary",&"debris_vfx_preset"]
static func extend_actor(d: ActorDefinition) -> void:
	_native_authoring().extend_actor(d)

static func definition() -> ActorObjectDefinition:
	return _native_authoring().definition()

static func edit(model: ActorTimeline,actor: ActorData,field: StringName,value: Variant,label: String) -> void:
	_native_authoring().edit(model,actor,field,value,label)

static func assign(reference: WeakRef,actor: ActorData,field: StringName,value: Variant) -> void:
	_native_authoring().assign(reference,actor,field,value)

static func operation_action(model: ActorTimeline,actor: ActorData,id: String,action: String) -> String:
	return _native_authoring().operation_action(model,actor,id,action)

static func geometry_operations(ops: Dictionary) -> Dictionary:
	return _native_authoring().geometry_operations(ops)

static func resistance(ops: Dictionary,point: Vector3) -> float:
	return _native_authoring().resistance(ops,point)

static func fragment_defaults(position: Vector3=Vector3.ZERO) -> Dictionary:
	return _native_authoring().fragment_defaults(position)

static func fragment_key(owner: String,id: String) -> String:
	return _native_authoring().fragment_key(owner,id)

static func guidance(controller: KiwiTimelinePhysics,owner: String,fragment: Dictionary,values: Dictionary,time: float,h: float) -> bool:
	return _native_authoring().guidance(controller,owner,fragment,values,time,h)

static func apply_overrides(controller: KiwiTimelinePhysics,time: float) -> void:
	_native_authoring().apply_overrides(controller,time)

static func source_signature(controller: KiwiTimelinePhysics,actor: ActorData) -> String:
	return _native_authoring().source_signature(controller,actor)

static func capture_setup(controller: KiwiTimelinePhysics,actor: ActorData) -> ActorObjectData:
	return _native_authoring().capture_setup(controller,actor)

static func apply_setup(model: ActorTimeline,controller: KiwiTimelinePhysics,actor: ActorData,setup: ActorObjectData) -> String:
	return _native_authoring().apply_setup(model,controller,actor,setup)

static func assign_setup(reference: WeakRef,actor: ActorData,values: Dictionary,tracks: Array[ActorAnimationTrack]) -> void:
	_native_authoring().assign_setup(reference,actor,values,tracks)

static func assign_values(reference: WeakRef,actor: ActorData,values: Dictionary) -> void:
	_native_authoring().assign_values(reference,actor,values)

static func edit_fragments(model: ActorTimeline,actor: ActorData,field: StringName,ids: Array,key: String,value: Variant) -> void:
	_native_authoring().edit_fragments(model,actor,field,ids,key,value)

static func restore_fragments(reference: WeakRef,actor: ActorData,field: StringName,values: Dictionary,tracks: Array[ActorAnimationTrack]) -> void:
	_native_authoring().restore_fragments(reference,actor,field,values,tracks)

static func key_fragments(model: ActorTimeline,actor: ActorData,field: StringName,ids: Array,key: String,fallback: Variant) -> void:
	_native_authoring().key_fragments(model,actor,field,ids,key,fallback)

static func _native_authoring() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","destruction_authoring")
