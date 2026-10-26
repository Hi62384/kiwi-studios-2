extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1;push_error(label)
 print("PASS " if ok else "FAIL ",label)
func frequency(data:PackedVector2Array,first:int,last:int,channel:int,rate:int)->float:
 var crossings:=0
 for i in range(first+1,last):
  var a:=data[i-1].x if channel==0 else data[i-1].y
  var b:=data[i].x if channel==0 else data[i].y
  if a<0 and b>=0:crossings+=1
 return float(crossings)*rate/(last-first)
func _initialize()->void:
 var rate:=48000;var samples:=PackedVector2Array();samples.resize(rate*2)
 for i in samples.size():samples[i]=Vector2(0.2*sin(TAU*440*i/rate),0.15*sin(TAU*880*i/rate))
 var original:=samples.duplicate()
 var pitched:=KiwiAudioAnalysis.transform_selection(samples,"pitch_shift",12000,84000,12,0,rate)
 check(str(pitched.get("error","")).is_empty(),"selected-channel pitch render succeeds")
 if pitched.has("samples"):
  var output:PackedVector2Array=pitched.samples
  check(output.size()==samples.size(),"pitch keeps exact duration")
  var difference:=0.0
  for i in samples.size():difference=maxf(difference,absf(output[i].y-samples[i].y))
  check(difference<0.000001,"unselected right channel unchanged")
  check(absf(frequency(output,24000,72000,0,rate)-880)<4,"left pitch shifts one octave")
  check(output.slice(0,12000)==samples.slice(0,12000) and output.slice(84000)==samples.slice(84000),"pitch preserves samples outside selection")
 var stretched:=KiwiAudioAnalysis.transform_selection(samples,"time_stretch",12000,84000,1.5,-1,rate)
 check(str(stretched.get("error","")).is_empty(),"selection time stretch succeeds")
 if stretched.has("samples"):
  var output:PackedVector2Array=stretched.samples
  check(output.size()==132000 and stretched.inserted_frames==108000,"stretch has exact requested frame count")
  check(absf(frequency(output,24000,96000,0,rate)-440)<4,"time stretch preserves pitch")
  check(output.slice(0,12000)==samples.slice(0,12000) and output.slice(120000)==samples.slice(84000),"stretch preserves samples outside selection")
 check(samples==original,"time and pitch edits never mutate original samples")
 check(not str(KiwiAudioAnalysis.transform_selection(samples,"time_stretch",1,10,2,0,rate).get("error","")).is_empty(),"single-channel duration changes rejected explicitly")
 var token:=KiwiAudioJobs.Work.new();token.cancel()
 var cancelled:=KiwiAudioAnalysis.transform_selection(samples,"pitch_shift",0,48000,12,-1,rate,token)
 check(not str(cancelled.get("error","")).is_empty() or not cancelled.get("success",true),"selection processor honors cancellation")
 print("AUDIO_WAVE_TRANSFORM failures=",failures);quit(failures)
