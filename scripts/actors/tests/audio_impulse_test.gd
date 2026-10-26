extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
 var rate:=48000;var samples:=PackedVector2Array();samples.resize(9600);samples[2400]=Vector2.ONE*0.4
 var source:=KiwiAudioSourceCache.to_wav(samples,rate)
 var ir:=PackedVector2Array();ir.resize(9600);ir[0]=Vector2.ONE*0.5;ir[4800]=Vector2(0.25,0.1)
 var directory:=ProjectSettings.globalize_path("user://impulse_test/"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(directory)
 for type in ["convolution","plate","spring","pingpong"]:
  var doc:=KiwiAudioDocument.from_source(source);doc.master.volume_db=0;doc.actors[0].values[&"fade_in"]=0;doc.actors[0].values[&"fade_out"]=0
  var effect:=KiwiAudioEffects.create(type);effect.parameters.mix=0.5
  if type=="convolution":effect.parameters.impulse=KiwiAudioSourceCache.to_wav(ir,rate);effect.parameters.length=0.2
  if type in ["plate","spring"]:effect.parameters.decay=0.5
  if type=="pingpong":effect.parameters.time=0.1;effect.parameters.feedback=0.5
  doc.actors[0].values[&"effects"]=[effect]
  var path:=directory.path_join(type+".wav");var result:=KiwiAudioRenderer.render(doc,path,{"sample_rate":rate,"bit_depth":16})
  check(result.get("success",false),"render "+type+" "+str(result.get("error","")))
  if not result.get("success",false):continue
  var output:PackedVector2Array=KiwiAudioSourceCache.decode(AudioStreamWAV.load_from_file(path),rate).samples
  var tail:=0.0
  for i in range(9600,output.size()):tail+=output[i].length_squared()
  check(output.size()==roundi((0.2+KiwiAudioEffects.tail_seconds([effect]))*rate),"exact declared tail duration "+type)
  if type=="convolution":
   print("FIR_MEASURE ",output[2400]," ",output[7200])
   check(absf(output[7200].x-0.05)<0.001 and absf(output[7200].y-0.02)<0.001,"known FIR tap amplitude/channel response")
  else:check(tail>0.00000001,"nonzero modeled tail "+type)
  if type=="pingpong":
   print("PINGPONG ",output[7199]," ",output[11999])
   check(absf(output[7199].x)>0.05 and absf(output[7199].y)<0.0001,"first echo left only")
   check(absf(output[11999].y)>0.01 and absf(output[11999].x)<0.0001,"second echo right only")
 var cancelled:=KiwiAudioJobs.Work.new();cancelled.cancel()
 check(KiwiAudioImpulse.generate("plate",{},rate,cancelled)==null,"impulse model cancellation")
 print("IMPULSE_TEST directory=",directory," failures=",failures);quit(failures)
