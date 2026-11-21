class_name KiwiBakeEditing
extends RefCounted
static func prefix_signature(model: ActorTimeline,time: float) -> String:
	return _native_editing().prefix_signature(model,time)

static func group_cache(actor: ActorData) -> Dictionary:
	return _native_editing().group_cache(actor)

static func remap_frame(frame: Dictionary,ids: Dictionary,offset: Transform3D) -> Dictionary:
	return _native_editing().remap_frame(frame,ids,offset)

static func remap_id(id: String,ids: Dictionary) -> String:
	return _native_editing().remap_id(id,ids)

static func portable_signature(actor: ActorData) -> String:
	return _native_editing().portable_signature(actor)

static func portable_scene(editor: ActorTimelineEditor) -> Dictionary:
	return _native_editing().portable_scene(editor)

static func portable_time(bake: Dictionary,clip: ActorClip,time: float) -> float:
	return _native_editing().portable_time(bake,clip,time)

static func current_time(bake: Dictionary,clip: ActorClip,time: float) -> float:
	return _native_editing().current_time(bake,clip,time)

static func portable_state(state: Dictionary,bake: Dictionary,clip: ActorClip,offset: Transform3D) -> Dictionary:
	return _native_editing().portable_state(state,bake,clip,offset)


static func _native_editing() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","bake_editing")
