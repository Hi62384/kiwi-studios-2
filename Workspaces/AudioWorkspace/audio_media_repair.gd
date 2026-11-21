extends RefCounted
## Schema-aware source repair; no arbitrary path-string replacement.
static func _native()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_media_repair")
static func scan(document:KiwiAudioDocument)->Dictionary:return _native().scan(document)
static func _actor_index(label:String)->int:return _native().actor_index(label)
static func apply(session:KiwiAudioEditSession,owner:KiwiAudioDocument,revision:int,source:String,replacement:Dictionary)->String:
 return _native().apply(session,owner,revision,source,replacement)
