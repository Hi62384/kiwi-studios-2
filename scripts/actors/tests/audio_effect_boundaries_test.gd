extends SceneTree
var failures:=0
func _initialize()->void:call_deferred("test")
func test()->void:
 var samples:=PackedVector2Array();samples.resize(48000)
 for i in samples.size():
  var t:=float(i)/48000;var gate:=0.1 if t<0.3 else 0.45
  samples[i]=Vector2((sin(TAU*220*t)+sin(TAU*1400*t)*0.5+sin(TAU*6000*t)*0.2)*gate,sin(TAU*700*t)*gate)
 var source:=KiwiAudioSourceCache.to_wav(samples,48000)
 var directory:=ProjectSettings.globalize_path("user://extra_dsp/"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(directory)
 var results:Array=[]
 for id in ["multiband","graphic_eq","early_reflections","stereo_delay","frequency_shift","tube","tape"]:
  var effect:=KiwiAudioEffects.create(id)
  var variants:Array=[effect]
  for field in KiwiAudioEffects.definition(id).parameters:
   for limit in ["min","max"]:
    var variant:=effect.duplicate(true);variant.parameters[field.id]=field[limit];variants.append(variant)
  for index in variants.size():
   var doc:=KiwiAudioDocument.from_source(source);doc.master.volume_db=0;doc.actors[0].values[&"effects"]=[variants[index]]
   var result:=KiwiAudioRenderer.render(doc,directory.path_join(id+"_"+str(index)+".wav"),{"sample_rate":48000,"bit_depth":16})
   if not result.get("success",false):failures+=1;push_error(id+": "+str(result.get("error","")))
   result.effect=id;result.variant=index;results.append(result)
 var doc:=KiwiAudioDocument.from_source(source);doc.master.volume_db=0
 doc.tracks[0].automation={"volume_db":KiwiAudioAutomationCanvas.modulation_points({"shape":"sine","sync":false,"rate":2,"center":-12,"depth":6},1,120,-60,12)}
 var automated:=KiwiAudioRenderer.render(doc,directory.path_join("modulation.wav"),{"sample_rate":48000,"bit_depth":16,"include_tail":false})
 if not automated.get("success",false):failures+=1;push_error(str(automated))
 results.append(automated)
 var file:=FileAccess.open("user://extra_effects_results.json",FileAccess.WRITE);file.store_string(JSON.stringify(results," "));file.close()
 print("EXTRA_DSP cases=",results.size()," failures=",failures," directory=",directory)
 quit(failures)
