extends SceneTree
const Transcript=preload("res://Workspaces/AudioWorkspace/audio_transcription.gd")
const Provider=preload("res://Workspaces/AudioWorkspace/audio_elevenlabs_provider.gd")
const Vault=preload("res://Workspaces/AudioWorkspace/audio_credential_vault.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)
func worker(operation:Callable)->Variant:
	var thread:=Thread.new();thread.start(operation)
	while thread.is_alive():await process_frame
	return thread.wait_to_finish()
func screenshot(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://.godot/verification");DirAccess.make_dir_recursive_absolute(folder)
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"Optional workflow native UI screenshot saves")
func run()->void:
	root.size=Vector2i(1440,1000);root.gui_embed_subwindows=true
	var parsed:=Transcript.parse({"transcription":[{"offsets":{"from":0,"to":1000},"text":"hello"},{"offsets":{"from":1000,"to":2000},"text":"world"}]},3)
	check(parsed.error.is_empty() and parsed.text=="hello world" and parsed.segments.size()==2,"Whisper JSON preserves timestamps and editable text")
	check(not Transcript.parse({"transcription":[{"offsets":{"from":-1,"to":0}}]},3).error.is_empty(),"Invalid transcript timing is rejected")
	check(not Transcript.parse({"transcription":[{"offsets":{"from":4000,"to":5000}}]},3).error.is_empty(),"Out-of-clip transcript timing is rejected")
	check(not Transcript.parse({"transcription":"invalid"},3).error.is_empty(),"Malformed recognizer output is rejected")
	var samples:=PackedVector2Array();samples.resize(48000);samples.fill(Vector2(.05,.05));var stream:=KiwiAudioSourceCache.to_wav(samples,16000)
	var session:=KiwiAudioEditSession.new();session.open(KiwiAudioDocument.from_source(stream));var id:=session.document.clips[0].id
	check(Transcript.apply(session,id,parsed,"Reviewed wording",true).is_empty(),"Reviewed transcript and cue markers apply")
	check(session.document.markers.size()==2 and session.document.actor_for_clip(id).values[&"transcript"].text=="Reviewed wording","Transcript is editable metadata, not destructive audio edits")
	session.undo();check(session.document.markers.is_empty() and not session.document.actor_for_clip(id).values.has(&"transcript"),"Transcript and markers undo together")
	session.redo();check(session.document.markers.size()==2,"Transcript and markers redo together")
	var saved:="user://transcript_"+ActorData.new_id()+".tres"
	check(ResourceSaver.save(session.document,saved)==OK,"Transcript composition saves")
	var reopened:KiwiAudioDocument=ResourceLoader.load(saved,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.actor_for_clip(id).values[&"transcript"].segments.size()==2,"Transcript segments survive save/reopen")
	var service:=KiwiAudioProviderService.new();var provider:=Provider.new();var counts:Dictionary={"read":0,"send":0}
	check(service.register(provider)==OK and service.register(provider)==ERR_INVALID_PARAMETER,"Production adapter registers once")
	service.credential_reader=func(_id:String):counts.read+=1;return "fixture-secret"
	provider.transport=func(_voice:String,_body:PackedByteArray,_key:String,_job:RefCounted):counts.send+=1;return {"success":false,"error":"Fixture refusal"}
	var request:Dictionary={"task":"speech","model":"eleven_multilingual_v2","voice_id":"test-voice","prompt":"Fixture"}
	check(not service.run("elevenlabs",request,{}).success and counts.read==0 and counts.send==0,"No consent means no credential read or network request")
	check(not service.run("elevenlabs",request,{"send_request":true,"voice_authorized":true}).success and counts.read==0,"Unknown cost approval is required before credential access")
	check(not service.run("elevenlabs",request,{"send_request":true,"unknown_cost":true}).success and counts.read==0,"Voice authorization is required")
	var consent:Dictionary={"send_request":true,"unknown_cost":true,"voice_authorized":true}
	check(not service.run("elevenlabs",request,consent).success and counts.send==1,"Approved request reaches adapter with explicit credentials")
	var invalid:=request.duplicate();invalid.voice_id="../bad"
	check(not service.run("elevenlabs",invalid,consent).success and counts.send==1,"Voice path injection is rejected before network")
	var cancelled:=KiwiAudioJobs.Work.new();cancelled.cancel();var before:=int(counts.read)
	check(not service.run("elevenlabs",request,consent,cancelled).success and counts.read==before,"Cancelled jobs do not read credentials")
	check(Vault.valid_id("elevenlabs") and not Vault.valid_id("../other-service") and not Vault.valid_id("UPPERCASE"),"Credential IDs are strictly namespaced")
	var directory:=ProjectSettings.globalize_path("user://optional_tool_fixture_"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(directory)
	if not ActorVideo.executable("ffmpeg").is_empty():
		var mp3:=directory.path_join("fixture.mp3");var doc:=KiwiAudioDocument.from_source(stream)
		var rendered:Dictionary=await worker(func():return KiwiAudioRenderer.render(doc,mp3,{"include_tail":false}))
		check(bool(rendered.get("success",false)),"Synthetic provider response fixture renders")
		if rendered.get("success",false):
			var bytes:=FileAccess.get_file_as_bytes(mp3)
			provider.transport=func(_voice:String,_body:PackedByteArray,_key:String,_job:RefCounted):return {"success":true,"data":bytes}
			var result:=service.run("elevenlabs",request,consent)
			check(result.success and result.stream.get_length()>0,"Production adapter decodes real provider-format MP3 response")
			check(result.metadata.provider=="elevenlabs" and not JSON.stringify(result.metadata).contains("fixture-secret"),"Only safe origin metadata is retained")
	var root_path:=ProjectSettings.globalize_path("res://.godot/optional_speech_test")
	var executable:=root_path.path_join("bin/Release/whisper-cli.exe");var model:=root_path.path_join("ggml-tiny.en.bin");var input:=root_path.path_join("jfk.wav")
	if FileAccess.file_exists(executable) and FileAccess.file_exists(model) and FileAccess.file_exists(input):
		var document:=KiwiAudioDocument.from_source(input)
		var result:Dictionary=await worker(func():return Transcript.run(document,document.clips[0].id,executable,model))
		check(str(result.get("error","")).is_empty(),"Real local whisper.cpp CLI completes")
		check(str(result.get("text","")).to_lower().contains("country"),"Real public speech sample yields recognized words")
		print("LOCAL_TRANSCRIPTION_RESULT ",str(result.get("text",result.get("error",""))))
	else:print("SKIP optional real recognizer: install test executable/model/sample to .godot/optional_speech_test")
	if OS.get_environment("KIWI_TEST_VAULT")=="1" and Vault.available():
		var target:="test-"+ActorData.new_id();var secret:="synthetic-test-é-"+ActorData.new_id()
		var stored:Dictionary=await worker(func():return Vault.request("write",target,secret))
		check(bool(stored.get("success",false)),"Windows vault stores a uniquely named synthetic test credential")
		var read:Dictionary=await worker(func():return Vault.request("read",target))
		check(bool(read.get("success",false)) and str(read.get("secret",""))==secret,"Windows vault returns only the matching test credential")
		var removed:Dictionary=await worker(func():return Vault.request("delete",target))
		check(bool(removed.get("success",false)),"Only the synthetic test credential is removed")
		var empty:Dictionary=await worker(func():return Vault.request("read",target))
		check(str(empty.get("secret","")).is_empty(),"Deleted synthetic credential is unavailable")
	var workspace:=KiwiAudioWorkspace.new();root.add_child(workspace);await process_frame
	check(workspace._commands.has("Transcribe Selected Clip Locally") and workspace._commands.has("Generate Cloud Speech (Opt-in)"),"Optional workflows are reachable through Commands")
	workspace._optional_tools.configure();await process_frame;await screenshot("optional_tool_setup")
	for child in workspace.get_children():
		if child is Window:child.queue_free()
	await process_frame;workspace._optional_tools.speech();await process_frame;await screenshot("optional_speech_consent")
	check(workspace._optional_tools.contexts.is_empty(),"Opening settings and speech review never sends a request")
	workspace.queue_free();await process_frame;session.history.clear_history()
	print("AUDIO_OPTIONAL_TOOLS checks=%d failures=%d"%[checks,failures]);quit(failures)
