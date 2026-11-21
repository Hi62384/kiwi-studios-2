class_name KiwiAudioRecordingPrepare
extends RefCounted
## Materialize the existing renderer before opening any recording device. This
## is a preparation stage, not another mixer or a second capture implementation.
const MAX_PREPARED_FILE_BYTES := 512 * 1024 * 1024
const RATE := 44100

# A returned backing owns only its private folder. Jobs may discard cancelled
# results without emitting completed; reference lifetime still cleans them up.
# File-preview readers retain this object until their handles have closed.
class Backing extends RefCounted:
 var path := ""
 var info: Dictionary = {}
 var _directory := ""
 func _init(directory: String = "") -> void:
  KiwiAudioRecordingPrepare._native().call("initialize_backing", self, directory)
 func valid() -> bool:
  return KiwiAudioRecordingPrepare._native().call("backing_valid", self)
 func _notification(what: int) -> void:
  if what == NOTIFICATION_PREDELETE and not _directory.is_empty():
   KiwiAudioRecordingPrepare._native().call("release_directory", _directory)



static func signature(document: KiwiAudioDocument) -> String:
 return _native().call("signature", document)

static func _stable_value(value:Variant,depth:int)->Variant:
 return _native().call("stable_value", value, depth)

static func prepare(document:KiwiAudioDocument,start:float,end:float=-1,job:RefCounted=null)->Dictionary:
 return _native().call("prepare", document, start, end, job)

static func _new_backing(directory: String) -> Backing:
 return Backing.new(directory)

static func _native() -> RefCounted:
 return Engine.get_singleton("KiwiNativeServices").call("service", "audio_recording_prepare")
