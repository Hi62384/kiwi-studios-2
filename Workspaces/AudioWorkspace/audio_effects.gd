class_name KiwiAudioEffects
extends RefCounted
## One catalog. Native previews are explicitly distinct from offline processors.
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "audio_effects")
static func parameter(id: String, label: String, value: float, minimum: float, maximum: float, step: float=.01) -> Dictionary: return _native().call("parameter", id, label, value, minimum, maximum, step)

static func catalog() -> Array[Dictionary]: return _native().call("catalog")

static func _entry(id: String, label: String, category: String, realtime: bool, parameters: Array) -> Dictionary: return _native().call("entry", id, label, category, realtime, parameters)

static func definition(id: String) -> Dictionary: return _native().call("definition", id)

static func create(id: String) -> Dictionary: return _native().call("create", id)

static func native(effect: Dictionary) -> AudioEffect: return _native().call("native_effect", effect)

static func offline_filter(effect: Dictionary, rate: int=44100) -> String: return _native().call("offline_filter", effect, rate)

static func number(value: Variant) -> String: return _native().call("number", value)

static func tempo_filter(speed: float) -> String: return _native().call("tempo_filter", speed)

static func pan_filter(pan: float) -> String: return _native().call("pan_filter", pan)

static func chain(effects: Array, rate: int=44100, context: String="effect") -> String: return _native().call("chain", effects, rate, context)

static func tail_seconds(effects: Array) -> float: return _native().call("tail_seconds", effects)

static func update_native_properties(target: AudioEffect, source: AudioEffect) -> void: _native().call("update_native_properties", target, source)

static func automation_commands(type: String) -> Dictionary: return _native().call("automation_commands", type)

static func evaluated_stack(stack: Array, time: float) -> Array: return _native().call("evaluated_stack", stack, time)

static func rendered_filter(effect: Dictionary, rate: int, context: String) -> String: return _native().call("rendered_filter", effect, rate, context)

static func automated_filter(effect: Dictionary, rate: int, filter: String, context: String) -> String: return _native().call("automated_filter", effect, rate, filter, context)

