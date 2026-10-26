class_name KiwiAudioImpulse
extends RefCounted
## Offline impulse responses. Generated plate/spring responses are deliberately
## labelled models; user-recorded impulses use the same convolution path.
static func duration(type:String,p:Dictionary)->float:
 if type=="pingpong":return clampf(float(p.get("time",0.25)),0.01,1.5)*8
 if type=="convolution":return clampf(float(p.get("length",3)),0.1,20)
 return clampf(float(p.get("decay",2)),0.1,8)
static func generate(type:String,p:Dictionary,rate:int,job:RefCounted=null)->AudioStreamWAV:
 var seconds:=duration(type,p);var frames:=maxi(2,int(round(seconds*rate)))
 var samples:=PackedVector2Array();samples.resize(frames)
 if type=="pingpong":
  var delay:=maxi(1,int(round(float(p.get("time",0.25))*rate)))
  var feedback:=clampf(float(p.get("feedback",0.45)),0,0.85)
  for i in 8:
   var index:=mini(frames-1,delay*(i+1)-1)
   var gain:=pow(feedback,i)
   samples[index]=Vector2(gain,0) if i%2==0 else Vector2(0,gain)
  return KiwiAudioSourceCache.to_wav(samples,rate)
 var random:=RandomNumberGenerator.new();random.seed=int(p.get("seed",137))
 var damping:=clampf(float(p.get("damping",0.5)),0,1)
 var filtered:=Vector2.ZERO
 if type=="plate":
  # Diffuse broadband decay plus early reflections, with independent channels.
  # Four incommensurate all-pass delays disperse the initial diffusion burst.
  var buffers:Array[PackedVector2Array]=[];var indices:Array[int]=[]
  for delay_ms in [4.3,7.1,11.7,17.3]:
   var buffer:=PackedVector2Array();buffer.resize(maxi(1,int(delay_ms*rate/1000)));buffers.append(buffer);indices.append(0)
  var coefficient:=lerpf(0.85,0.09,damping)
  for i in frames:
   if i%8192==0 and job!=null:
    if job.is_cancelled():return null
    job.update(0.02+0.06*float(i)/frames,"Preparing plate response")
   var t:=float(i)/rate;var envelope:=exp(-6.907755*t/seconds)*(1-exp(-t*120))
   var value:=Vector2(random.randf_range(-1,1),random.randf_range(-1,1))*envelope
   filtered=filtered.lerp(value,coefficient);value=filtered
   for stage in buffers.size():
    var at:=indices[stage];var delayed:=buffers[stage][at];var next:=delayed-value*0.62
    buffers[stage][at]=value+next*0.62;indices[stage]=(at+1)%buffers[stage].size();value=next
   samples[i]=value
  var energy:=0.0
  for value in samples:energy+=value.length_squared()*0.5
  var gain:=0.65/sqrt(maxf(0.000001,energy))
  for i in samples.size():samples[i]*=gain
  for tap in [[0.013,0.28,-0.1],[0.023,-0.12,0.26],[0.037,0.16,0.19]]:
   var i:=int(float(tap[0])*rate)
   if i<frames:samples[i]+=Vector2(tap[1],tap[2])
 elif type=="spring":
  # Dispersive resonant modes: high modes arrive later and decay faster.
  var tension:=clampf(float(p.get("tension",1)),0.5,2)
  for mode in 24:
   if job!=null and job.is_cancelled():return null
   var frequency:=(97+mode*mode*18.7+mode*43.1)*tension
   if frequency>=rate*0.43:continue
   var arrival:=0.009+mode*0.0007
   var decay:=seconds/(1+mode*damping*0.075)
   var amplitude:=1.0/pow(mode+1,0.7)
   var pan:=random.randf_range(-0.7,0.7)
   for i in range(int(arrival*rate),frames):
    var t:=float(i)/rate-arrival
    var phase:=TAU*(frequency*t+25.0*tension*(1-exp(-t*20)))
    var value:=sin(phase)*exp(-6.907755*t/decay)*(1-exp(-t*500))*amplitude
    samples[i]+=Vector2(value*(1-pan*0.4),value*(1+pan*0.4))
  var area:=Vector2.ZERO
  for value in samples:area+=value.abs()
  var divisor:=maxf(1,maxf(area.x,area.y)*0.35)
  for i in samples.size():samples[i]/=divisor
 else:return null
 # End the generated tail smoothly without moving its exact declared length.
 var fade:=mini(frames,maxi(1,int(rate*0.005)))
 for i in fade:samples[frames-1-i]*=float(i)/fade
 return KiwiAudioSourceCache.to_wav(samples,rate)
