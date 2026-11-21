extends RefCounted
## Called through the existing bounded job queue. Never loads an entire take.
const ROOT := "user://audio_workspace/takes"
const MAX_BYTES := 2 * 1024 * 1024 * 1024 - 44

static func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_take_finalize")
static func finalize(capture:Dictionary,job:RefCounted=null)->Dictionary:return _native().finalize(capture,job)
static func recoverable()->Array[Dictionary]:return _native().recoverable(ActorAudioRecorder.active_directories())
