class_name KiwiPowderSettings
extends RefCounted
## Simple flow controls derive contact coefficients; Advanced uses explicit values.
static func number(values: Dictionary,key: String,fallback: float,low: float,high: float) -> float:
	return _native_settings().number(values,key,fallback,low,high)

static func effective(values: Dictionary) -> Dictionary:
	return _native_settings().effective(values)

static func switch_mode(model: ActorTimeline,actors: Array[ActorData],advanced: bool) -> void:
	_native_settings().switch_mode(model,actors,advanced)

static func assign(reference: Variant,entries: Array) -> void:
	_native_settings().assign(reference,entries)


static func _native_settings() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","powder_settings")
