extends RefCounted
## Reviewed, all-or-nothing source edits. Crossfades overlap real source handles
## inside removed quiet regions; they are not merely adjacent anti-click fades.
const MAX_CLIPS := 64

static func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_dialogue_batch")
static func analyze(document:KiwiAudioDocument,ids:Array,threshold:float,minimum:float,job:RefCounted=null)->Dictionary:
 return _native().analyze(document,ids,threshold,minimum,job)
static func prepare(session:KiwiAudioEditSession,entries:Array,keep:float)->Dictionary:return _native().prepare(session,entries,keep)
static func review(session:KiwiAudioEditSession,plans:Array,choices:Array,scope:String,overlap:float)->Dictionary:return _native().review(session,plans,choices,scope,overlap)
static func apply(session:KiwiAudioEditSession,plans:Array,choices:Array,scope:String,overlap:float)->Dictionary:return _native().apply(session,plans,choices,scope,overlap)
