extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
 print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
 var rate:=48000;var data:=PackedVector2Array();var clean:=PackedVector2Array();data.resize(rate*3);clean.resize(data.size())
 var random:=RandomNumberGenerator.new();random.seed=728
 var noise:=Vector2.ZERO
 for i in data.size():
  noise=noise.lerp(Vector2(random.randf_range(-1,1),random.randf_range(-1,1)),0.4)
  var tone:=0.0 if i<rate/2 else 0.12*sin(TAU*997*i/rate)+0.04*sin(TAU*1994*i/rate)
  clean[i]=Vector2.ONE*tone;data[i]=clean[i]+noise*0.08
 var source:=KiwiAudioSourceCache.to_wav(data,rate)
 var profile:=KiwiAudioAnalysis.noise_profile(source,0,0.45)
 check(str(profile.get("error","")).is_empty(),"learn noise-only region through actual FFT backend")
 if not profile.has("noise_profile"):print(profile);quit(1);return
 check(profile.noise_profile.size()==15,"learned 15-band spectral profile")
 var lowest:=INF;var highest:=-INF
 for value in profile.noise_profile:lowest=minf(lowest,float(value));highest=maxf(highest,float(value))
 check(highest-lowest>3,"colored profile is frequency dependent")
 var doc:=KiwiAudioDocument.from_source(source);doc.master.volume_db=0;doc.actors[0].values[&"fade_in"]=0;doc.actors[0].values[&"fade_out"]=0
 var effect:=KiwiAudioEffects.create("noise_reduce");effect.parameters.noise_profile=profile.noise_profile;effect.parameters.floor=profile.floor;effect.parameters.reduction=12;doc.actors[0].values[&"effects"]=[effect]
 var dir:=ProjectSettings.globalize_path("user://noise_profile_test/"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(dir)
 var result:=KiwiAudioRenderer.render(doc,dir.path_join("denoised.wav"),{"sample_rate":rate,"bit_depth":16,"include_tail":false})
 check(result.get("success",false),"profile applies in the ordered render chain")
 if result.get("success",false):
  var out:PackedVector2Array=KiwiAudioSourceCache.decode(AudioStreamWAV.load_from_file(result.path),rate).samples
  var before:=0.0;var after:=0.0;var energy:=0.0
  for i in range(rate,rate*2):before+=(data[i]-clean[i]).length_squared();after+=(out[i]-clean[i]).length_squared();energy+=clean[i].length_squared()
  var before_snr:=10*log(energy/before)/log(10);var after_snr:=10*log(energy/after)/log(10)
  print("NOISE_PROFILE_SNR ",before_snr," -> ",after_snr," floor ",profile.floor)
  check(after_snr>before_snr,"learned profile improves suitable synthetic signal SNR")
 check(not str(KiwiAudioAnalysis.noise_profile(source,0,0.01).get("error","")).is_empty(),"too-short noise selection rejected")
 var silence:=PackedVector2Array();silence.resize(4800)
 check(not str(KiwiAudioAnalysis.noise_profile(KiwiAudioSourceCache.to_wav(silence,rate),0,0.1).get("error","")).is_empty(),"silent noise selection rejected")
 print("NOISE_PROFILE failures=",failures);quit(failures)
