class_name KiwiAudioTemplates
extends RefCounted
static func names()->PackedStringArray:
 return PackedStringArray(["Sound Effect Design","Voice Editing","YouTube Commentary","Podcast","Music Production","Cinematic Soundtrack","Cartoon Sound Design","Game Audio","Ambient Soundscape"])
static func create(label:String)->KiwiAudioDocument:
 var document:=KiwiAudioDocument.new();document.title=label
 var tracks:Array=[]
 match label:
  "Sound Effect Design":tracks=[["Transient","audio"],["Body","audio"],["Texture","audio"],["Tail","audio"]]
  "Voice Editing":tracks=[["Dialogue","audio"],["Alternate Takes","audio"]]
  "YouTube Commentary":tracks=[["Commentary","audio"],["Music","audio"],["Sound Effects","audio"]]
  "Podcast":tracks=[["Host","audio"],["Guest","audio"],["Theme","audio"]]
  "Music Production":tracks=[["Drums","instrument"],["Bass","instrument"],["Chords","instrument"],["Lead","instrument"]]
  "Cinematic Soundtrack":tracks=[["Low Strings","instrument"],["Pads","instrument"],["Percussion","instrument"],["Impacts","audio"]];document.tempo=84
  "Cartoon Sound Design":tracks=[["Foley","audio"],["Cartoon Effects","audio"],["Music Cues","instrument"],["Dialogue","audio"]]
  "Game Audio":tracks=[["UI","audio"],["Movement","audio"],["Impacts","audio"],["Ambience","audio"]]
  "Ambient Soundscape":tracks=[["Texture","audio"],["Environment","audio"],["Pad","instrument"],["Details","audio"]];document.tempo=72
 for entry in tracks:
  var track:=document.add_track(entry[0],entry[1])
  if entry[0] in ["Dialogue","Commentary","Host","Guest"]:
   track.effects=chain("Voice cleanup")
  elif entry[0] in ["Music","Theme","Pad","Pads"]:track.volume_db=-9.0
  if entry[0]=="Drums":track.instrument={"id":"drums"}
  elif entry[0]=="Bass":track.instrument={"id":"bass"}
  elif entry[1]=="instrument":track.instrument={"id":"pad" if entry[0] in ["Pads","Pad"] else "piano"}
 # Real buses/sends rather than a cosmetic collection of differently named
 # tracks. Dry tracks remain editable; the master is never a feedback target.
 var source_tracks:=document.tracks.duplicate()
 var bus:=document.add_track("Voice bus" if label in ["Voice Editing","Podcast","YouTube Commentary"] else ("Design bus" if label in ["Sound Effect Design","Cartoon Sound Design","Game Audio"] else "Music bus"),"group")
 bus.effects=[_fx("compressor",{"threshold":-18,"ratio":2}),_fx("limiter",{"ceiling":-2})]
 for track in source_tracks:
  if str(track.name) in ["Alternate Takes"]:track.mute=true
  if label in ["Podcast","YouTube Commentary"] and str(track.name) in ["Theme","Music","Sound Effects"]:continue
  track.output=str(bus.id);track.group=str(bus.id)
 if label in ["Music Production","Cinematic Soundtrack","Ambient Soundscape","Sound Effect Design","Cartoon Sound Design"]:
  var space:=document.add_track("Space return","group");space.effects=[_fx("reverb",{"size":.8 if label=="Ambient Soundscape" else .5,"mix":1.})];space.volume_db=-9
  for track in source_tracks:
   if str(track.name) not in ["Bass","Drums","Dialogue","Foley","Transient"]:track.sends=[{"target":str(space.id),"volume_db":-15.}]
 if label=="Music Production":
  var drums:=document.add_track("Drum bus","group");drums.output=str(bus.id);drums.effects=[_fx("compressor",{"threshold":-16,"ratio":3})]
  source_tracks[0].output=str(drums.id);source_tracks[0].group=str(drums.id)
 document.master.effects=[_fx("highpass",{"frequency":25}),_fx("limiter",{"ceiling":-1})]
 document.workspace_state={"bottom_open":true,"bottom_tab":2 if label=="Music Production" else 0}
 return document
static func chain_names()->PackedStringArray:
 return PackedStringArray(["Voice cleanup","Telephone voice","Radio voice","Robot voice","Monster voice","Underwater voice","Distant voice","Warm tape-style","Bright master"])
static func chain(name:String)->Array:
 var result:Array=[]
 match name:
  "Voice cleanup":result=[_fx("highpass",{"frequency":75}),_fx("hum_remove",{"frequency":60,"harmonics":3}),_fx("noise_reduce",{"reduction":8,"floor":-50}),_fx("compressor",{"threshold":-20,"ratio":3}),_fx("deesser",{"intensity":0.4,"amount":0.3})]
  "Telephone voice":result=[_fx("telephone",{}),_fx("saturate",{"drive":0.18,"output":-2})]
  "Radio voice":result=[_fx("highpass",{"frequency":180}),_fx("lowpass",{"frequency":5000}),_fx("compressor",{"threshold":-24,"ratio":6}),_fx("bitcrusher",{"bits":12,"reduction":1})]
  "Robot voice":result=[_fx("ring",{"frequency":80,"mix":0.9}),_fx("delay",{"time":0.05,"mix":0.15,"feedback":0.25})]
  "Monster voice":result=[_fx("pitch",{"semitones":-7}),_fx("saturate",{"drive":0.25,"output":-5}),_fx("reverb",{"size":0.7,"mix":0.2})]
  "Underwater voice":result=[_fx("lowpass",{"frequency":700,"q":0.8}),_fx("chorus",{"rate":0.3,"depth":3,"mix":0.3})]
  "Distant voice":result=[_fx("highpass",{"frequency":200}),_fx("lowpass",{"frequency":3500}),_fx("gain",{"db":-9}),_fx("reverb",{"size":0.8,"mix":0.45})]
  "Warm tape-style":result=[_fx("saturate",{"drive":0.15,"output":-3}),_fx("lowpass",{"frequency":12000}),_fx("vibrato",{"rate":0.4,"depth":0.04})]
  "Bright master":result=[_fx("highpass",{"frequency":30}),_fx("high_shelf",{"frequency":7000,"db":1.5}),_fx("compressor",{"threshold":-15,"ratio":2}),_fx("limiter",{"ceiling":-1})]
 return result
static func _fx(type:String,values:Dictionary)->Dictionary:
 var effect:=KiwiAudioEffects.create(type)
 for key in values:effect.parameters[key]=values[key]
 return effect
static func export_presets()->Dictionary:
 return {"YouTube Video":{"sample_rate":48000,"target_lufs":-14,"normalize":false},"Podcast / Voice":{"sample_rate":48000,"target_lufs":-16,"normalize":false},"Music":{"sample_rate":44100,"target_lufs":-14,"normalize":false},"Game SFX":{"sample_rate":48000,"target_lufs":-18,"normalize":false},"Animation Dialogue":{"sample_rate":48000,"target_lufs":-18,"normalize":false},"High Quality":{"sample_rate":48000,"bit_depth":24,"normalize":false}}
