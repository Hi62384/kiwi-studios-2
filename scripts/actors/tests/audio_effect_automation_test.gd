extends SceneTree
var failures:=0
func _initialize()->void:call_deferred("test")
func test()->void:
 var data:=PackedVector2Array();data.resize(96000)
 for i in data.size():data[i]=Vector2.ONE*sin(TAU*1000*i/48000.0)*0.2
 var source:=KiwiAudioSourceCache.to_wav(data,48000)
 var directory:=ProjectSettings.globalize_path("user://effect_automation/"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(directory)
 var results:Array=[]
 for id in ["gain","lowpass","highpass","bandpass","notch","eq","low_shelf","high_shelf","compressor","gate","frequency_shift","bitcrusher","noise_reduce"]:
  var doc:=KiwiAudioDocument.from_source(source);doc.master.volume_db=0
  var effect:=KiwiAudioEffects.create(id)
  if id=="gate":effect.parameters.threshold=-9
  var keys:=KiwiAudioEffects.automation_commands(id)
  for field in KiwiAudioEffects.definition(id).parameters:
   if keys.has(field.id):effect.automation[field.id]=[{"time":0,"value":field.min,"curve":"hold"},{"time":1.0,"value":field.max,"curve":"hold"}]
  doc.actors[0].values[&"effects"]=[effect]
  var result:=KiwiAudioRenderer.render(doc,directory.path_join(id+".wav"),{"sample_rate":48000,"bit_depth":16,"include_tail":false});result.id=id;results.append(result)
  if not result.get("success",false):failures+=1;push_error(str(result))
 var file:=FileAccess.open("user://effect_automation_results.json",FileAccess.WRITE);file.store_string(JSON.stringify(results," "));file.close()
 print("EFFECT_AUTOMATION ",JSON.stringify(results));print("EFFECT_AUTOMATION failures=",failures);quit(failures)
