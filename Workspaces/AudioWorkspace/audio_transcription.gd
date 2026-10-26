extends RefCounted
## Optional local whisper.cpp CLI, never sends source audio over the network.
## https://github.com/ggml-org/whisper.cpp/tree/master/examples/cli
const Process=preload("res://Workspaces/AudioWorkspace/audio_optional_process.gd")
static func parse(data:Variant,duration:float)->Dictionary:
	if not data is Dictionary or not data.get("transcription") is Array:return {"error":"The recognizer did not produce whisper.cpp JSON segments."}
	if data.transcription.size()>8192:return {"error":"Transcript exceeds the 8192-segment limit."}
	var segments:Array=[];var text:=PackedStringArray();var previous:=0.;var characters:=0
	for item in data.transcription:
		if not item is Dictionary or not item.get("offsets") is Dictionary:return {"error":"Invalid transcript timestamps."}
		if not KiwiAudioConductor._number(item.offsets.get("from"),0,300100) or not KiwiAudioConductor._number(item.offsets.get("to"),0,310000) or not item.get("text","") is String:return {"error":"Invalid transcript segment values."}
		var start:=float(item.offsets.get("from",-1))/1000.;var end:=float(item.offsets.get("to",-1))/1000.;var words:=str(item.get("text","")).strip_edges()
		if not is_finite(start) or not is_finite(end) or start<previous or end<start or start>duration+.1:return {"error":"Transcript timestamps are outside the selected clip."}
		end=minf(end,duration);previous=start;characters+=words.length()
		if characters>262144:return {"error":"Transcript exceeds the text limit."}
		if not words.is_empty():segments.append({"start":start,"end":end,"text":words});text.append(words)
	return {"error":"","segments":segments,"text":" ".join(text),"engine":"whisper.cpp","local":true}
static func run(document:KiwiAudioDocument,id:String,executable:String,model:String,job:RefCounted=null)->Dictionary:
	var clip:=document.clip_for_id(id)
	if clip==null or clip.duration>300:return {"error":"Select a clip up to five minutes for local transcription."}
	if not FileAccess.file_exists(executable) or not FileAccess.file_exists(model):return {"error":"Choose an installed whisper.cpp CLI executable and GGML model first. No model is downloaded automatically."}
	var model_file:=FileAccess.open(model,FileAccess.READ)
	if model_file==null:return {"error":"Could not read the configured model."}
	var model_bytes:=model_file.get_length();model_file.close()
	if model_bytes>4*1024*1024*1024:return {"error":"Model exceeds the 4 GiB optional-model limit."}
	var directory:=ProjectSettings.globalize_path("user://audio_workspace/jobs/"+ActorData.new_id())
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:return {"error":"Could not prepare the transcription folder."}
	var input:=directory.path_join("input.wav")
	var render:=KiwiAudioRenderer.render(document,input,{"sample_rate":16000,"bit_depth":16,"mono":true,"clip_ids":[id],"start":clip.start_time,"duration":clip.duration,"include_tail":false},job)
	if not bool(render.get("success",false)):
		if not bool(render.get("cleanup_pending",false)):KiwiAudioRenderer._remove_owned(directory)
		return {"error":str(render.get("error","Could not prepare the selected audio."))}
	if job!=null:job.update(.5,"Recognizing speech locally")
	var output:=directory.path_join("transcript")
	var result:=Process.run(executable,PackedStringArray(["-m",model,"-f",input,"-oj","-of",output,"-l","auto","-t",str(mini(4,OS.get_processor_count()))]),"",job,600)
	var parsed:Dictionary={"error":str(result.get("error","")) if not bool(result.get("success",false)) else "Recognizer produced no JSON transcript."}
	var json_path:=output+".json"
	if bool(result.get("success",false)) and FileAccess.file_exists(json_path):
		var file:=FileAccess.open(json_path,FileAccess.READ)
		if file!=null and file.get_length()<=2*1024*1024:parsed=parse(JSON.parse_string(file.get_as_text()),clip.duration)
		else:parsed={"error":"Transcript output is unavailable or exceeds 2 MiB."}
		if file!=null:file.close()
	if bool(result.get("process_exited",false)):KiwiAudioRenderer._remove_owned(directory)
	return parsed
static func apply(session:KiwiAudioEditSession,id:String,result:Dictionary,text:String,markers:bool)->String:
	var clip:=session.document.clip_for_id(id);var actor:=session.document.actor_for_clip(id)
	if clip==null or actor==null or not session.can_edit(id) or session._before!=null:return "The selected clip is no longer editable."
	if not str(result.get("error","")).is_empty() or text.length()>262144:return "Invalid reviewed transcript."
	session.action("Save reviewed transcript",func():
		actor.values[&"transcript"]={"text":text,"segments":result.get("segments",[]).duplicate(true),"engine":"whisper.cpp","local":true}
		if markers:
			for segment in result.get("segments",[]):session.document.markers.append({"id":ActorData.new_id(),"time":clip.start_time+float(segment.start),"name":str(segment.text).left(120)}))
	return ""
