extends RefCounted
## Exact renderer path, then bounded streaming PCM analysis. This measures an
## isolated clip with its routing/processing, not a nonlinear contribution to
## the simultaneous full mix. A gain correction may need another measurement.
const MAX_SECONDS := 300.
const MAX_CACHE_ENTRIES := 32
static var _cache: Dictionary = {}
static var _mutex := Mutex.new()

static func rms(document: KiwiAudioDocument, id: String, job: RefCounted = null) -> Dictionary:
	var clip := document.clip_for_id(id)
	if clip == null: return {"error":"A selected clip no longer exists."}
	if clip.duration > MAX_SECONDS: return {"error":"Processed RMS analysis supports clips up to five minutes. Analyze a shorter split; raw-source analysis still supports longer PCM windows."}
	var signature := KiwiAudioRecordingPrepare.signature(document)
	var key := signature + ":" + id
	_mutex.lock(); var cached: Dictionary = _cache.get(key,{}).duplicate(); _mutex.unlock()
	if not cached.is_empty(): return cached
	if job != null and job.is_cancelled(): return {"error":"Cancelled."}
	var directory := ProjectSettings.globalize_path("user://audio_workspace/jobs/"+ActorData.new_id())
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return {"error":"Could not create the analysis folder."}
	var output := directory.path_join("processed.wav")
	var rendered := KiwiAudioRenderer.render(document,output,{"sample_rate":48000,"bit_depth":16,"clip_ids":[id],"start":clip.start_time,"duration":clip.duration,"include_tail":false},job)
	var result: Dictionary
	if not bool(rendered.get("success",false)):
		result={"error":str(rendered.get("error","Processed clip render failed."))}
	else:
		var data := KiwiAudioAnalysis.analyze_source(output,-42,.25,job)
		result={"error":str(data.get("error","")),"rms_db":float(data.get("rms_db",-120.)),"peak_db":float(data.get("peak_db",-120.)),"processed":true}
	if not bool(rendered.get("cleanup_pending",false)): KiwiAudioRenderer._remove_owned(directory)
	if job != null and job.is_cancelled(): return {"error":"Cancelled."}
	if signature != KiwiAudioRecordingPrepare.signature(document): return {"error":"A source changed during processed analysis. Repeat the measurement."}
	if str(result.get("error","")).is_empty():
		_mutex.lock()
		if _cache.size()>=MAX_CACHE_ENTRIES: _cache.erase(_cache.keys()[0])
		_cache[key]=result.duplicate(); _mutex.unlock()
	return result

static func alignment(document:KiwiAudioDocument,ids:Array,job:RefCounted=null)->Dictionary:
	if ids.size()!=2:return {"error":"Select two clips for processed alignment."}
	var signature:=KiwiAudioRecordingPrepare.signature(document);var samples:Array=[]
	for id in ids:
		var clip:=document.clip_for_id(str(id))
		if clip==null or clip.duration>MAX_SECONDS:return {"error":"Processed alignment supports clips up to five minutes; compares their first twenty audible seconds."}
		if job!=null and job.is_cancelled():return {"error":"Cancelled."}
		var directory:=ProjectSettings.globalize_path("user://audio_workspace/jobs/"+ActorData.new_id())
		if DirAccess.make_dir_recursive_absolute(directory)!=OK:return {"error":"Could not create the alignment folder."}
		var output:=directory.path_join("alignment.wav")
		var rendered:=KiwiAudioRenderer.render(document,output,{"sample_rate":12000,"bit_depth":16,"clip_ids":[id],"start":clip.start_time,"duration":minf(20.,clip.duration),"include_tail":false},job)
		if not bool(rendered.get("success",false)):
			if not bool(rendered.get("cleanup_pending",false)):KiwiAudioRenderer._remove_owned(directory)
			return {"error":str(rendered.get("error","Could not render processed alignment."))}
		var info:=KiwiAudioPCMFile.inspect(output);var file:=FileAccess.open(output,FileAccess.READ)
		if file==null or not str(info.get("error","")).is_empty():
			KiwiAudioRenderer._remove_owned(directory);return {"error":"Could not read the processed alignment PCM."}
		samples.append(KiwiAudioPCMFile.read_frames(file,info,0,mini(240000,int(info.frames))));file.close();KiwiAudioRenderer._remove_owned(directory)
	if signature!=KiwiAudioRecordingPrepare.signature(document):return {"error":"A source changed during alignment. Repeat the analysis."}
	var result:=KiwiAudioAnalysis.alignment(samples[0],samples[1],12000)
	result.error="";result.processed=true
	return result
