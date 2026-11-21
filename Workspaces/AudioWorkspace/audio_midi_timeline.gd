class_name KiwiAudioMIDITimeline
extends RefCounted
## Bounded note-only SMF projection. No PCM decode/render or document mutation.
## Audio FX, routing, automation and sample/instrument voice behavior are excluded.
const MAX_CLIPS := 128
const MAX_CYCLES := 4096
const MAX_EVALUATIONS := 1000000

static func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_midi_timeline")
static func preflight(document:KiwiAudioDocument)->String:
 return _native().preflight(document)
static func build(document:KiwiAudioDocument,job:RefCounted=null)->Dictionary:
 return _native().build(document,job)
static func _failure(message:String)->Dictionary:
 return {"error":message,"parts":[],"tempos":[],"meters":[]}
