class_name KiwiDestructionDefinition
extends RefCounted
static func extend_actor(d: ActorDefinition) -> void:
	_native_definition().extend_actor(d)

static func operation(kind: int,time: float=0) -> Dictionary:
	return _native_definition().operation(kind,time)

static func assign(reference: WeakRef,actor: ActorData,values: Dictionary) -> void:
	_native_definition().assign(reference,actor,values)

static func edit(model: ActorTimeline,actor: ActorData,operations: Dictionary,label: String="Edit destruction") -> void:
	_native_definition().edit(model,actor,operations,label)

static func restore_animation(reference: WeakRef,actor: ActorData,values: Dictionary,tracks: Array[ActorAnimationTrack]) -> void:
	_native_definition().restore_animation(reference,actor,values,tracks)

static func _native_definition() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","destruction_definition")
