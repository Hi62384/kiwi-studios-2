extends RefCounted
## Definitions and instances are authoritative; the notes array is a derived
## compatibility view for the existing piano roll, MIDI and synthesis engines.
static func validate(definitions:Variant,instances:Variant)->String:
	return _native().call("validate", definitions, instances)

static func from_part(part:Dictionary,meter:Array)->Dictionary:
	return _native().call("from_part", part, meter)

static func notes(actor:ActorData)->Array:
	return _native().call("notes", actor)

static func sync(actor:ActorData)->void:
	_native().call("sync", actor)

static func detach(actor:ActorData)->void:
	_native().call("detach", actor)

static func _native() -> RefCounted:
	return Engine.get_singleton("KiwiNativeServices").call("service", "audio_linked_patterns")
