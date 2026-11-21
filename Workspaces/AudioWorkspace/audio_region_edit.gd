class_name KiwiAudioRegionEdit
extends RefCounted
## Selection-sized PCM edits. Never decodes, rewrites or replaces the untouched
## source regions. Source references remain shared by document undo snapshots.
const MAX_WORKING_BYTES := 32 * 1024 * 1024
const OPERATIONS := ["copy", "cut", "paste", "trim", "silence", "amplify", "normalize", "reverse", "fade_in", "fade_out", "repair", "invert", "mono", "time_stretch", "pitch_shift", "set_amplitude"]
const EPSILON := 0.000000001

static func prepare(clip: ActorClip, actor: ActorData, stream: AudioStream, operation: String, selection: Vector2i, rate: int, amount: float = 0.0, channel: int = -1, clipboard: PackedVector2Array = PackedVector2Array(), clipboard_rate: int = 0, job: RefCounted = null) -> Dictionary:
	return _native().call("prepare", clip, actor, stream, operation, selection, rate, amount, channel, clipboard, clipboard_rate, job)

static func unsupported_reason(clip: ActorClip, actor: ActorData, operation: String) -> String:
	return _native().call("unsupported_reason", clip, actor, operation)

static func apply(session: KiwiAudioEditSession, result: Dictionary) -> Dictionary:
	return _native().call("apply", session, result)

static func _piece(actor: ActorData, clip: ActorClip, at: float, offset: float, duration: float) -> Dictionary:
	return _native().call("piece", actor, clip, at, offset, duration)

static func _resample(samples: PackedVector2Array, from_rate: int, to_rate: int, count: int) -> PackedVector2Array:
	return _native().call("resample", samples, from_rate, to_rate, count)

static func _cancelled(job: RefCounted) -> bool:
	return job != null and job.is_cancelled()

static func _failure(message: String) -> Dictionary:
	return {"error": message}
static func _native() -> RefCounted:
	return Engine.get_singleton("KiwiNativeServices").call("service", "audio_region_edit")
