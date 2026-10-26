class_name KiwiAudioPreset
extends Resource
@export var version: int = 1
@export var id: String = ""
@export var label: String = "Preset"
@export var kind: String = "generator"
@export var tags: PackedStringArray = []
@export var folder: String = ""
@export var data: Dictionary = {}
@export var composition: KiwiAudioDocument

const MAX_JSON_BYTES := 1024 * 1024
const MAX_PATTERN_NOTES := 8192

static func pattern_data(actor:ActorData,document:KiwiAudioDocument=null) -> Dictionary:
 if actor==null:return {}
 var timing_error:=KiwiAudioTempoMap.validate_source(actor.values)
 if not timing_error.is_empty():return {"_pattern_error":timing_error}
 var notes:Variant=actor.values.get(&"notes",[])
 if not notes is Array or notes.size()>MAX_PATTERN_NOTES:return {"_pattern_error":"Pattern notes must be an array of at most 8192 notes."}
 var result:={"notes":notes.duplicate(true),"instrument":actor.values.get(&"instrument",{}).duplicate(true),"pattern_beats":float(actor.values.get(&"pattern_beats",4)),"step_settings":actor.values.get(&"step_settings",{}).duplicate(true),"tags":Array(actor.values.get(&"pattern_tags",[]))}
 if actor.values.has(&"drum_instances"):
  result.drum_patterns=actor.values.get(&"drum_patterns",{}).duplicate(true);result.drum_instances=actor.values.drum_instances.duplicate(true)
 for key in ["midi_tempos","midi_time_signatures","midi_events"]:
  if actor.values.has(key):result[key]=(actor.values[key] as Array).duplicate(true)
 if document!=null:
  result["source_bpm"]=KiwiAudioEditSession.note_source_tempo(actor,document)
  var source_meter:=KiwiAudioEditSession.note_source_meter(actor,document)
  result["source_meter"]=[source_meter.x,source_meter.y]
 else:
  if actor.values.has(&"source_bpm"):result["source_bpm"]=float(actor.values[&"source_bpm"])
  if actor.values.has(&"source_meter"):result["source_meter"]=(actor.values[&"source_meter"] as Array).duplicate()
 if actor.values.has(&"midi_tempos"):result["midi_tempo_scale"]=float(actor.values.get(&"midi_tempo_scale",1.0))
 if actor.values.has(&"midi_sustain"):result["midi_sustain"]=bool(actor.values.midi_sustain)
 return result

static func apply_pattern(session:KiwiAudioEditSession,preset:KiwiAudioPreset,at:float=0,track_id:String="",create_clip:bool=false) -> String:
 if preset==null or preset.kind!="pattern":return "Choose a pattern preset."
 var problem:=validate_pattern(preset.data)
 if not problem.is_empty():return problem
 var actor:=session.primary_actor();var clip:=session.primary_clip()
 if not create_clip and (actor==null or clip==null):create_clip=true
 if not create_clip and not session.can_edit(clip.id):return "The selected clip is locked or frozen."
 var track:=session.document.track_for_id(track_id if not track_id.is_empty() else session.selected_track)
 if create_clip and not track.is_empty() and (bool(track.get("locked",false)) or track.has("frozen_track")):return "The destination track is locked or frozen."
 problem=session.document.midi_timing_error([preset.data],actor.id if not create_clip else "")
 if not problem.is_empty():return problem
 var source_bpm:=float(preset.data.get("source_bpm",session.document.conductor().tempo_at(at if create_clip else clip.start_time)))
 var timing:=KiwiAudioTempoMap.new(preset.data.get("midi_tempos",[]),source_bpm,float(preset.data.get("midi_tempo_scale",1.0)))
 if not timing.error.is_empty():return timing.error
 var seconds:=timing.beat_to_seconds(float(preset.data.get("pattern_beats",4)))
 if seconds>300:return "The pattern exceeds the 300-second render limit at this tempo."
 var empty:AudioStreamWAV
 if create_clip:
  var silence:=PackedVector2Array();silence.resize(maxi(2,ceili(seconds*8000)));empty=KiwiAudioSourceCache.to_wav(silence,8000)
 session.begin("Apply note pattern")
 if create_clip:
  if track.is_empty() or str(track.get("kind",""))!="instrument":track=session.document.add_track(preset.label,"instrument")
  clip=session.document.insert_source(empty,str(track.id),maxf(0,at),preset.label)
  if clip==null:session.cancel();return "Could not create the pattern clip."
  actor=session.document.actor_for_clip(clip.id);session.selected_ids.assign([clip.id]);session.selected_track=str(track.id)
 # Replacement patterns own their source metadata. A normal preset must
 # never inherit an earlier MIDI map or its unrelated channel events.
 # Leave notes_source_scale intact: it describes a pending window remap
 # from an earlier BPM edit, not metadata belonging to the new pattern.
 for key in [&"midi_tempos",&"midi_tempo_scale",&"midi_time_signatures",&"midi_events",&"midi_sustain"]:actor.values.erase(key)
 actor.values.erase(&"drum_patterns");actor.values.erase(&"drum_instances")
 if preset.data.has("drum_instances"):
  actor.values[&"drum_patterns"]=preset.data.get("drum_patterns",{}).duplicate(true);actor.values[&"drum_instances"]=preset.data.drum_instances.duplicate(true)
 for key in ["midi_tempos","midi_time_signatures","midi_events"]:
  if preset.data.has(key):actor.values[key]=(preset.data[key] as Array).duplicate(true)
 if preset.data.has("midi_tempos"):actor.values[&"midi_tempo_scale"]=float(preset.data.get("midi_tempo_scale",1.0))
 if preset.data.has("midi_sustain"):actor.values[&"midi_sustain"]=bool(preset.data.midi_sustain)
 actor.values[&"source_bpm"]=source_bpm
 var conductor:=session.document.conductor();var meter:=conductor.beat_info(conductor.seconds_to_beat(clip.start_time))
 actor.values[&"source_meter"]=preset.data.get("source_meter",[int(meter.numerator),int(meter.denominator)]).duplicate()
 actor.values[&"notes"]=preset.data.get("notes",[]).duplicate(true)
 if preset.data.has("instrument"):actor.values[&"instrument"]=preset.data.instrument.duplicate(true)
 elif not actor.values.has(&"instrument"):actor.values[&"instrument"]=KiwiAudioInstruments.default_instrument("poly")
 actor.values[&"pattern_beats"]=float(preset.data.get("pattern_beats",4));actor.values[&"step_settings"]=preset.data.get("step_settings",{}).duplicate(true)
 actor.values[&"pattern_tags"]=preset.data.get("tags",Array(preset.tags)).duplicate();actor.values[&"notes_dirty"]=true
 session.commit();session.selection_changed.emit()
 return ""

static func validate_pattern(value:Dictionary) -> String:
 if value.has("_pattern_error"):return str(value._pattern_error)
 if value.has("drum_instances") or value.has("drum_patterns"):
  var linked_error:=preload("res://Workspaces/AudioWorkspace/audio_linked_patterns.gd").validate(value.get("drum_patterns",{}),value.get("drum_instances",[]))
  if not linked_error.is_empty():return linked_error
 var timing_error:=KiwiAudioTempoMap.validate_source(value)
 if not timing_error.is_empty():return timing_error
 var notes:Variant=value.get("notes",[])
 if not notes is Array or notes.size()>MAX_PATTERN_NOTES:return "Pattern notes must be an array of at most 8192 notes."
 var mapped:=value.has("midi_tempos")
 if not _number_in(value.get("pattern_beats",4),0.000001 if mapped else 1.0/12.0,KiwiAudioTempoMap.MAX_BEAT if mapped else 256):return "Invalid pattern length (ordinary patterns: 1/12 to 256 beats; MIDI patterns: 0.000001 to 10000000 beats)."
 if not value.get("instrument",{}) is Dictionary or not value.get("step_settings",{}) is Dictionary:return "Invalid instrument or step settings."
 var instrument:Dictionary=value.get("instrument",{})
 for key in ["seed","root_pitch"]:
  if instrument.has(key) and not _number_in(instrument[key],-2147483648,2147483647):return "Invalid instrument "+key+"."
 for key in ["harmonics","wavetable","modulators","multisamples","effects"]:
  if instrument.has(key) and not instrument[key] is Array:return "Invalid instrument "+key+"."
 for key in ["harmonics","wavetable"]:
  for item in instrument.get(key,[]):
   if not _number_in(item,-1000000,1000000):return "Invalid instrument "+key+" value."
 for mapping in instrument.get("multisamples",[]):
  if not mapping is Dictionary:return "Invalid multisample mapping."
  for key in ["low","high","root_pitch","velocity_low","velocity_high"]:
   if mapping.has(key) and not _number_in(mapping[key],0,127):return "Invalid sample mapping "+key+"."
 for modulator in instrument.get("modulators",[]):
  if not modulator is Dictionary or not modulator.get("values",[]) is Array or not modulator.get("points",[]) is Array:return "Invalid instrument modulator."
  for point in modulator.get("points",[]):
   if not point is Dictionary:return "Invalid modulator automation point."
 for note in notes:
  if not note is Dictionary:return "Invalid pattern note."
  if not note.get("pitch_bend",[]) is Array:return "Invalid pitch-bend points."
  for point in note.get("pitch_bend",[]):
   if not point is Dictionary:return "Invalid pitch-bend point."
  var beat_limit:=KiwiAudioTempoMap.MAX_BEAT if mapped else 2048.0
  for rule in [["pitch",60,0,127],["start",0,0,beat_limit],["duration",0.25,0.000001 if mapped else 0.001,beat_limit],["velocity",0.8,0,1],["pan",0,-1,1],["probability",1,0,1],["ratchets",1,1,8]]:
   if not _number_in(note.get(rule[0],rule[1]),rule[2],rule[3]):return "Invalid note "+str(rule[0])+"."
 var settings:Dictionary=value.get("step_settings",{})
 for rule in [["steps",16,1,256],["division",0.25,1.0/12.0,1],["swing",0,-0.45,0.45],["accent_variation",0,0,1],["seed",1,0,2147483647]]:
  if not _number_in(settings.get(rule[0],rule[1]),rule[2],rule[3]):return "Invalid step "+str(rule[0])+"."
 var lanes:Variant=settings.get("lanes",{})
 if not lanes is Dictionary or lanes.size()>128:return "Invalid step lanes."
 for pitch in lanes:
  if not str(pitch).is_valid_int() or int(pitch)<0 or int(pitch)>127 or not lanes[pitch] is Dictionary:return "Invalid step lane."
  for flag in ["mute","solo"]:
   if lanes[pitch].has(flag) and not lanes[pitch][flag] is bool:return "Invalid lane "+flag+"."
 var tags:Variant=value.get("tags",[])
 if not tags is Array or tags.size()>32:return "Pattern tags must be an array of at most 32 strings."
 for tag in tags:
  if not tag is String or tag.length()>128:return "Invalid pattern tag."
 return ""

static func _number_in(value:Variant,low:float,high:float) -> bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)>=low and float(value)<=high

static func _data_only(value:Variant,depth:int=0,budget:Array=[0]) -> bool:
 budget[0]+=1
 if depth>16 or int(budget[0])>100000:return false
 if value==null or value is bool or value is int:return true
 if value is float:return is_finite(value)
 if value is String or value is StringName:return str(value).length()<=8192
 if value is Array:
  if value.size()>MAX_PATTERN_NOTES:return false
  for item in value:
   if not _data_only(item,depth+1,budget):return false
  return true
 if value is Dictionary:
  if value.size()>1024:return false
  for key in value:
   if not (key is String or key is StringName) or str(key).length()>128 or not _data_only(value[key],depth+1,budget):return false
  return true
 return false

static func to_json_text(preset:KiwiAudioPreset) -> Dictionary:
 if preset==null or preset.kind!="pattern":return {"error":"Only data-only pattern presets can be exported as JSON."}
 var source_problem:=validate_pattern(preset.data)
 if not source_problem.is_empty():return {"error":source_problem}
 var data:=preset.data.duplicate(true);data["tags"]=Array(preset.tags) if not data.has("tags") else data.tags
 var problem:=validate_pattern(data)
 if not problem.is_empty():return {"error":problem}
 var payload:={"format":"kiwi_audio_pattern","version":1,"label":preset.label,"tags":Array(preset.tags),"data":data}
 if not _data_only(payload,0,[0]):return {"error":"JSON export needs bounded data-only settings. Embedded sample resources cannot be exported; save a native preset instead."}
 if not _json_audio_paths(payload):return {"error":"JSON sample references must be ordinary WAV, MP3, Ogg or FLAC paths, never script-bearing resources."}
 var encoded:=JSON.stringify(payload,"  ")
 if encoded.to_utf8_buffer().size()>MAX_JSON_BYTES:return {"error":"Pattern JSON exceeds 1 MiB."}
 return {"error":"","json":encoded}

static func from_json_text(text:String) -> Dictionary:
 if text.to_utf8_buffer().size()>MAX_JSON_BYTES:return {"error":"Pattern JSON exceeds 1 MiB."}
 if not _json_depth_allowed(text):return {"error":"Pattern JSON nesting exceeds the safe limit."}
 var parser:=JSON.new()
 if parser.parse(text)!=OK:return {"error":"Invalid JSON: "+parser.get_error_message()}
 var value:Variant=parser.data
 if not value is Dictionary or not _data_only(value,0,[0]):return {"error":"Pattern JSON must contain bounded data only."}
 if str(value.get("format",""))!="kiwi_audio_pattern" or value.get("version")!=1:return {"error":"Unsupported pattern JSON format or version."}
 if not value.get("data") is Dictionary:return {"error":"Missing pattern data."}
 if not _json_audio_paths(value):return {"error":"JSON sample references must be ordinary WAV, MP3, Ogg or FLAC paths, never script-bearing resources."}
 var data:Dictionary=value.data
 var problem:=validate_pattern(data)
 if not problem.is_empty():return {"error":problem}
 var tags:Variant=value.get("tags",data.get("tags",[]))
 if not tags is Array or tags.size()>32:return {"error":"Invalid pattern tags."}
 for tag in tags:
  if not tag is String or tag.length()>128:return {"error":"Invalid pattern tag."}
 var preset:=KiwiAudioPreset.new();preset.id=ActorData.new_id();preset.kind="pattern";preset.label=str(value.get("label","Imported pattern")).substr(0,128);preset.tags=PackedStringArray(tags);preset.data=data.duplicate(true)
 return {"error":"","preset":preset}

static func import_pattern_json(path:String) -> Dictionary:
 var file:=FileAccess.open(path,FileAccess.READ)
 if file==null:return {"error":"Could not read the pattern JSON file."}
 if file.get_length()>MAX_JSON_BYTES:return {"error":"Pattern JSON exceeds 1 MiB."}
 return from_json_text(file.get_as_text())

static func export_pattern_json(path:String,preset:KiwiAudioPreset) -> String:
 var encoded:=to_json_text(preset)
 if not str(encoded.get("error","")).is_empty():return str(encoded.error)
 if FileAccess.file_exists(path):return "Choose a new filename; an existing file will not be overwritten."
 var file:=FileAccess.open(path,FileAccess.WRITE)
 if file==null:return "Could not write the pattern JSON file."
 file.store_string(str(encoded.json));file.close()
 return ""

static func _json_audio_paths(value:Variant) -> bool:
 if value is Array:
  for item in value:
   if not _json_audio_paths(item):return false
 elif value is Dictionary:
  for key in value:
   if str(key)=="sample":
    var path:Variant=value[key]
    if not path is String:return false
    if not path.is_empty() and path.get_extension().to_lower() not in ["wav","mp3","ogg","flac"]:return false
   elif not _json_audio_paths(value[key]):return false
 return true

static func _json_depth_allowed(text:String) -> bool:
 var depth:=0;var quoted:=false;var escaped:=false
 for character in text:
  if quoted:
   if escaped:escaped=false
   elif character=="\\":escaped=true
   elif character=='"':quoted=false
  elif character=='"':quoted=true
  elif character in ["{","["]:
   depth+=1
   if depth>16:return false
  elif character in ["}","]"]:depth-=1
 return true
