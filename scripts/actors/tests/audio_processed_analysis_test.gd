extends SceneTree
const Analysis = preload("res://Workspaces/AudioWorkspace/audio_processed_analysis.gd")
var failures:=0
func check(value:bool,label:String)->void:
	if not value:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	if ActorVideo.executable("ffmpeg").is_empty():push_error("FFmpeg is required for this processed-signal test.");quit(2);return
	var samples:=PackedVector2Array();samples.resize(48000)
	for i in samples.size():samples[i]=Vector2.ONE*.2*sin(TAU*440*i/48000.)
	var source:=KiwiAudioSourceCache.to_wav(samples,48000)
	var document:=KiwiAudioDocument.from_source(source);document.master.volume_db=0.;document.master.effects=[]
	document.tracks[0].volume_db=0.;document.tracks[0].effects=[]
	var clip:=document.clips[0];var actor:=document.actors[0]
	clip.source_offset=.2;clip.duration=.4
	actor.values[&"fade_in"]=0.;actor.values[&"fade_out"]=0.;actor.values[&"volume_db"]=-12.
	var gain:=KiwiAudioEffects.create("gain");gain.parameters.db=-6.;actor.values[&"effects"]=[gain]
	var thread:=Thread.new();thread.start(func():return Analysis.rms(document,clip.id))
	while thread.is_alive():await process_frame
	var result:Dictionary=thread.wait_to_finish()
	check(str(result.get("error","")).is_empty(),"Processed analysis renders the selected source window: "+str(result.get("error","")))
	var raw:=KiwiAudioAnalysis.analyze(source)
	check(absf(float(raw.rms_db)-float(result.get("rms_db",0.))-18.)<.15,"Processed RMS includes clip gain and effect gain, not untouched source audio")
	var first:=float(result.get("rms_db",0.));actor.values[&"volume_db"]=-6.
	thread=Thread.new();thread.start(func():return Analysis.rms(document,clip.id))
	while thread.is_alive():await process_frame
	var changed:Dictionary=thread.wait_to_finish()
	check(absf(float(changed.get("rms_db",0.))-first-6.)<.15,"Cache identity changes when audible clip settings change")
	var directory:=ProjectSettings.globalize_path("user://audio_workspace/jobs/"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(directory)
	thread=Thread.new();thread.start(func():return KiwiAudioRenderer.render(document,directory.path_join("metered.wav"),{"sample_rate":48000,"bit_depth":16,"include_tail":false,"route_meters":true}))
	while thread.is_alive():await process_frame
	var metered:Dictionary=thread.wait_to_finish()
	check(bool(metered.get("success",false)),"Same-render route meter tap compiles: "+str(metered.get("error","")))
	var levels:PackedVector2Array=metered.get("route_meters",{}).get(str(document.tracks[0].id),PackedVector2Array())
	check(not levels.is_empty() and levels[5].x > -30 and levels[5].x < -20,"Rendered route meter reads the actual post-fader signal")
	KiwiAudioRenderer._remove_owned(directory)
	clip.duration=301.
	check(not str(Analysis.rms(document,clip.id).get("error","")).is_empty(),"Processed analysis enforces its five-minute render bound")
	print("AUDIO_PROCESSED_ANALYSIS failures=%d"%failures);quit(failures)
