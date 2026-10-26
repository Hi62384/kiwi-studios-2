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
  var root := ProjectSettings.globalize_path("user://audio_workspace/recording_previews").replace("\\", "/").simplify_path()
  var normalized := directory.replace("\\", "/").simplify_path()
  if not directory.is_empty() and normalized.get_base_dir() == root:
   _directory = normalized; path = normalized.path_join("mix.wav")
 func valid() -> bool:
  if _directory.is_empty() or not str(info.get("error", "invalid")).is_empty(): return false
  var current := KiwiAudioPCMFile.inspect(path)
  return str(current.get("error", "invalid")).is_empty() and current == info
 func _notification(what: int) -> void:
  if what == NOTIFICATION_PREDELETE and not _directory.is_empty():
   var remaining := KiwiAudioRenderer._remove_owned(_directory)
   if not remaining.is_empty(): push_warning("Could not remove released recording backing: " + "; ".join(remaining))


static func signature(document: KiwiAudioDocument) -> String:
 var parts:Array=[document.tempo,document.time_signature,document.tempo_points,document.meter_points,document.note_base_tempo,document.note_base_meter,document.master,document.tracks,document.loop_start,document.loop_end]
 for index in mini(document.clips.size(),document.actors.size()):
  var clip:=document.clips[index];var actor:=document.actors[index]
  if bool(actor.values.get(&"muted",false)):continue
  var values:=actor.values.duplicate(true)
  for key in [&"notes_dirty",&"rendered_signature",&"transients",&"transients_source_identity",&"original_audio"]:values.erase(key)
  # A completed preview job may replace derived note PCM without changing the
  # editable notes. Its new resource identity must not cancel an otherwise
  # unchanged recording preparation. The renderer materializes current notes.
  if KiwiAudioEditSession.is_note_source(actor):values.erase(&"audio");values.erase(&"source_duration")
  parts.append([clip.id,clip.actor_id,clip.start_time,clip.source_offset,clip.duration,clip.playback_speed,clip.layer,values])
 return var_to_str(_stable_value(parts,0)).sha256_text()

static func _stable_value(value:Variant,depth:int)->Variant:
 if depth>24:return "depth_limit"
 if value is Resource:return {"resource_id":value.get_instance_id(),"resource_path":value.resource_path}
 if value is Dictionary:
  var output:Dictionary={}
  for key in value:output[key]=_stable_value(value[key],depth+1)
  return output
 if value is Array:
  var output:Array=[]
  for item in value:output.append(_stable_value(item,depth+1))
  return output
 if value is String and value.get_extension().to_lower() in ["wav","mp3","ogg","flac"]:
  var file:=FileAccess.open(value,FileAccess.READ)
  var length:=file.get_length() if file!=null else -1
  if file!=null:file.close()
  return {"source_path":value,"modified":FileAccess.get_modified_time(value) if length>=0 else -1,"bytes":length}
 return value

static func prepare(document:KiwiAudioDocument,start:float,end:float=-1,job:RefCounted=null)->Dictionary:
 if job!=null and job.is_cancelled():return {"error":"Cancelled."}
 var seconds:=(end if end>start else document.duration())-start
 if not is_finite(seconds) or seconds<=0:return {"error":"There is no timeline audio after the recording start. Move the playhead or select a loop range."}
 var estimated_tail:=0.0
 if end<=start:
  estimated_tail=KiwiAudioEffects.tail_seconds(document.master.get("effects",[]))
  # Sum track tails as a conservative bound on any acyclic routed path.
  for track in document.tracks:estimated_tail+=KiwiAudioEffects.tail_seconds(track.get("effects",[]))
  var clip_tail:=0.0
  for actor in document.actors:clip_tail=maxf(clip_tail,KiwiAudioEffects.tail_seconds(actor.values.get(&"effects",[])))
  estimated_tail+=clip_tail
 if not is_finite(estimated_tail) or (seconds+estimated_tail)*RATE*4>MAX_PREPARED_FILE_BYTES-4096:
  return {"error":"This processed recording range exceeds the 512 MiB disk-backing limit (about 50 minutes at stereo 44.1 kHz). Use a shorter loop range."}
 var directory:=ProjectSettings.globalize_path("user://audio_workspace/recording_previews/"+ActorData.new_id())
 if DirAccess.make_dir_recursive_absolute(directory)!=OK:return {"error":"Could not create the private recording preparation folder."}
 var backing:=Backing.new(directory)
 var destination:=backing.path
 var options:Dictionary={"sample_rate":RATE,"bit_depth":16,"start":start,"include_tail":true}
 if end>start:options.duration=end-start;options.include_tail=false
 if job!=null:job.update(0,"Preparing processed timeline for recording")
 var rendered:=KiwiAudioRenderer.render(document,destination,options,job)
 var error:=str(rendered.get("error",""))
 if job!=null and job.is_cancelled():error="Cancelled."
 elif not bool(rendered.get("success",false)):
  if error.is_empty():error="The processed timeline could not be prepared."
 else:
  backing.info=KiwiAudioPCMFile.inspect(destination)
  if not str(backing.info.get("error","invalid")).is_empty():error=str(backing.info.get("error","The prepared recording audio is unreadable."))
  elif int(backing.info.get("file_bytes",0))>MAX_PREPARED_FILE_BYTES:error="Effect tails exceeded the 512 MiB disk-backing limit. Use a shorter loop range."
  elif not is_finite(float(backing.info.get("duration",0.0))) or float(backing.info.get("duration",0.0))<=0:error="The prepared recording audio is empty."
 if not error.is_empty():return {"error":error}
 if job!=null and job.is_cancelled():return {"error":"Cancelled."}
 # No AudioStreamWAV load or PCM-size allocation. The lease survives the job,
 # loop reuse and outstanding reader shutdown; the last holder removes it.
 return {"error":"","backing":backing,"start":start}
