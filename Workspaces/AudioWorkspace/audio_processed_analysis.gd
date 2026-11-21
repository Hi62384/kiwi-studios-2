extends RefCounted
## Exact renderer path, then bounded streaming PCM analysis. This measures an
## isolated clip with its routing/processing, not a nonlinear contribution to
## the simultaneous full mix. A gain correction may need another measurement.
const MAX_SECONDS := 300.
const MAX_CACHE_ENTRIES := 32
static var _cache: Dictionary = {}
static var _mutex := Mutex.new()

static func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_processed_analysis")
static func rms(document:KiwiAudioDocument,id:String,job:RefCounted=null)->Dictionary:return _native().rms(document,id,job,_cache,_mutex)
static func alignment(document:KiwiAudioDocument,ids:Array,job:RefCounted=null)->Dictionary:return _native().alignment(document,ids,job)
