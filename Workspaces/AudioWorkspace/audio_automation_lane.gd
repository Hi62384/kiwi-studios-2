class_name KiwiAudioAutomationLane
extends RefCounted
## A lane is a persistent view of an existing owner's curve. It never owns a
## second curve or changes playback routing; preview and export read the same data.
static var _definitions: Dictionary = {}

static func _effect_definition(type: String) -> Dictionary:
	return _native().call("effect_definition", type)

static func is_lane(track: Dictionary) -> bool:
	return _native().call("is_lane", track)

static func key(target: Dictionary) -> String:
	return _native().call("key", target)

static func resolve(document: KiwiAudioDocument, target: Dictionary) -> Dictionary:
	return _native().call("resolve", document, target)

static func lane_info(document: KiwiAudioDocument, lane_id: String) -> Dictionary:
	return _native().call("lane_info", document, lane_id)

static func editable(document: KiwiAudioDocument, lane_id: String) -> bool:
	return _native().call("editable", document, lane_id)

static func points(info: Dictionary) -> Array:
	return _native().call("points", info)

static func options(document: KiwiAudioDocument) -> Array[Dictionary]:
	return _native().call("options", document)

static func value(points_value: Array, time: float, fallback: float) -> float:
	return _native().call("value", points_value, time, fallback)

static func binding_error(document: KiwiAudioDocument, lane_id: String) -> String:
	return _native().call("binding_error", document, lane_id)

static func _native() -> RefCounted:
	return Engine.get_singleton("KiwiNativeServices").call("service", "audio_automation_lane")
