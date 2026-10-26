extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
 print("PASS " if ok else "FAIL ",label)
func frequency(samples:PackedVector2Array,start:int,length:int,rate:int)->float:
 var values:=KiwiAudioAnalysis.spectrum(samples,start,length);var best:=0
 for i in range(1,values.size()):
  if values[i]>values[best]:best=i
 return float(best)*rate/(values.size()*2)
func spectral_center(samples:PackedVector2Array,start:int,rate:int,low:float,high:float)->float:
 var values:=KiwiAudioAnalysis.spectrum(samples,start,8192);var weighted:=0.0;var energy:=0.0
 for i in values.size():
  var hz:=float(i)*rate/(values.size()*2)
  if hz>=low and hz<=high:weighted+=hz*values[i]*values[i];energy+=values[i]*values[i]
 return weighted/maxf(0.00000001,energy)
func _initialize()->void:
 var rate:=48000;var samples:=PackedVector2Array();samples.resize(rate*3)
 for i in samples.size():samples[i]=Vector2.ONE*sin(TAU*440*i/rate)*0.2
 var source:=KiwiAudioSourceCache.to_wav(samples,rate)
 var dir:=ProjectSettings.globalize_path("user://pitch_automation_test/"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(dir)
 var results:Array=[]
 for type in ["hq_pitch","formant","time_warp","audio_fm","distance"]:
  var effect:=KiwiAudioEffects.create(type)
  var variants:Array=[effect]
  for field in KiwiAudioEffects.definition(type).parameters:
   for limit in ["min","max"]:
    var copy:=effect.duplicate(true);copy.parameters[field.id]=field[limit];variants.append(copy)
  for i in variants.size():
   var doc:=KiwiAudioDocument.from_source(source);doc.master.volume_db=0;doc.actors[0].values[&"effects"]=[variants[i]]
   var result:=KiwiAudioRenderer.render(doc,dir.path_join(type+"_"+str(i)+".wav"),{"sample_rate":rate,"bit_depth":16,"include_tail":false})
   check(result.get("success",false),type+" variant "+str(i)+": "+str(result.get("error","")));results.append(result)
 var doc:=KiwiAudioDocument.from_source(source);doc.master.volume_db=0
 doc.actors[0].values[&"automation"]={"pitch":[{"time":0,"value":1,"curve":"hold"},{"time":1.5,"value":2,"curve":"hold"}]}
 var result:=KiwiAudioRenderer.render(doc,dir.path_join("bend.wav"),{"sample_rate":rate,"bit_depth":16,"include_tail":false})
 check(result.get("success",false),"clip pitch automation render")
 if result.get("success",false):
  var data:PackedVector2Array=KiwiAudioSourceCache.decode(AudioStreamWAV.load_from_file(result.path),rate).samples
  var first:=frequency(data,24000,8192,rate);var second:=frequency(data,108000,8192,rate)
  print("PITCH_BEND ",first," -> ",second)
  check(absf(spectral_center(data,24000,rate,380,500)-440)<3 and absf(spectral_center(data,108000,rate,810,950)-880)<3,"pitch ratio automation changes actual frequency")
  check(data.size()==samples.size(),"pitch bend preserves exact duration")
 var effect:=KiwiAudioEffects.create("hq_pitch");effect.automation.semitones=[{"time":0,"value":0,"curve":"hold"},{"time":1.5,"value":12,"curve":"hold"}]
 doc.actors[0].values[&"automation"]={};doc.actors[0].values[&"effects"]=[effect]
 result=KiwiAudioRenderer.render(doc,dir.path_join("effect_bend.wav"),{"sample_rate":rate,"bit_depth":16,"include_tail":false})
 check(result.get("success",false),"effect pitch automation render")
 if result.get("success",false):
  var data:PackedVector2Array=KiwiAudioSourceCache.decode(AudioStreamWAV.load_from_file(result.path),rate).samples
  check(absf(spectral_center(data,108000,rate,810,950)-880)<3,"effect automation command reaches Rubber Band")
 var file:=FileAccess.open("user://pitch_automation_results.json",FileAccess.WRITE);file.store_string(JSON.stringify(results," "));file.close()
 print("PITCH_AUTOMATION directory=",dir," failures=",failures);quit(failures)
