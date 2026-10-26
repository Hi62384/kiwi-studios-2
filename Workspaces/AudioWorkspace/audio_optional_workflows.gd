extends Node
## UI/main-thread ownership for optional tools; background work never mutates UI.
const Transcription=preload("res://Workspaces/AudioWorkspace/audio_transcription.gd")
const Vault=preload("res://Workspaces/AudioWorkspace/audio_credential_vault.gd")
const Provider=preload("res://Workspaces/AudioWorkspace/audio_elevenlabs_provider.gd")
const CONFIG="user://audio_workspace/optional_tools.cfg"
var jobs:=KiwiAudioJobs.new()
var settings:Dictionary={"whisper":"","model":"","voice_id":""}
var contexts:Dictionary={}
var service:=KiwiAudioProviderService.new()
func _remember(kind:String,context:Dictionary)->String:
	for token in contexts.keys():
		if str(contexts[token].get("kind",""))==kind:contexts.erase(token)
	var token:=ActorData.new_id();context.kind=kind;contexts[token]=context;return token
func _ready()->void:
	add_child(jobs);jobs.completed.connect(_completed)
	jobs.progress_changed.connect(func(value:float,message:String):
		var w:Variant=get_parent();w.progress.value=value*100;w.status.text=message)
	service.register(Provider.new());service.credential_reader=Vault.read
	var config:=ConfigFile.new()
	if config.load(CONFIG)==OK:
		for key in settings:settings[key]=str(config.get_value("tools",key,settings[key]))
func _context()->Dictionary:
	var w:Variant=get_parent()
	return {"owner":w.session,"document":w.session.document,"revision":w.session.revision,"signature":KiwiAudioRecordingPrepare.signature(w.session.document),"time":w.playback.position,"track":w.session.selected_track}
func _current(context:Dictionary)->bool:
	var w:Variant=get_parent()
	return w.session==context.owner and w.session.document==context.document and w.session.revision==context.revision and KiwiAudioRecordingPrepare.signature(w.session.document)==str(context.signature) and not w.recorder.recording and not w._record_busy and w.session._before==null and not w.automation_recording.active and not w.automation_recording.has_pending()
func _field(parent:Node,label:String,text:String,secret:bool=false)->LineEdit:
	var w:Variant=get_parent();w._label(parent,label)
	var field:=LineEdit.new();field.text=text;field.secret=secret;field.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(field);return field
func _path(parent:Node,label:String,key:String,filters:PackedStringArray)->LineEdit:
	var w:Variant=get_parent();w._label(parent,label)
	var row:=HBoxContainer.new();parent.add_child(row);var field:=LineEdit.new();field.text=settings[key];field.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(field)
	w._button(row,"Browse…",func():
		var picker:=FileDialog.new();picker.access=FileDialog.ACCESS_FILESYSTEM;picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE;picker.filters=filters;picker.use_native_dialog=true;add_child(picker)
		picker.file_selected.connect(func(path:String):
			if is_instance_valid(field):field.text=path
			picker.queue_free())
		picker.canceled.connect(picker.queue_free);picker.popup_centered_ratio(.7))
	return field
func configure()->void:
	var w:Variant=get_parent();var dialog:Dictionary=w._window("Optional local speech & cloud setup",Vector2i(700,560))
	w._label(dialog.host,"Local transcription: install whisper.cpp and a compatible GGML model separately. Audio stays on this computer. Nothing downloads or runs until you choose Transcribe selected clip.")
	var cli:=_path(dialog.host,"whisper.cpp CLI", "whisper",PackedStringArray(["*.exe ; Executable"]))
	var model:=_path(dialog.host,"GGML model", "model",PackedStringArray(["*.bin ; GGML model"]))
	w._label(dialog.host,"Optional ElevenLabs speech: requires your own account, quota and authorized voice ID. Every generation requires separate send/cost/voice confirmations. No account or paid request is created here.")
	var voice:=_field(dialog.host,"Voice ID",str(settings.voice_id))
	var password:=_field(dialog.host,"API key (stored only in Windows Credential Manager)","",true)
	var actions:=HFlowContainer.new();dialog.host.add_child(actions)
	var save_button:Button=w._button(actions,"Store key securely",func():
		if password.text.strip_edges().is_empty():w.notice("Enter a key to store.");return
		var secret:=password.text.strip_edges();password.clear()
		jobs.request("vault",func(job:RefCounted):return Vault.request("write","elevenlabs",secret,job),0))
	save_button.disabled=not Vault.available()
	var remove_button:Button=w._button(actions,"Remove stored key",func():
		var confirmation:=ConfirmationDialog.new();confirmation.dialog_text="Remove only the Kiwi Studios ElevenLabs credential from Windows Credential Manager?";add_child(confirmation)
		confirmation.confirmed.connect(func():jobs.request("vault",func(job:RefCounted):return Vault.request("delete","elevenlabs","",job));confirmation.queue_free())
		confirmation.canceled.connect(confirmation.queue_free);confirmation.popup_centered())
	remove_button.disabled=not Vault.available()
	w._button(dialog.host,"Save tool paths & voice ID",func():
		settings={"whisper":cli.text.strip_edges(),"model":model.text.strip_edges(),"voice_id":voice.text.strip_edges()}
		var config:=ConfigFile.new()
		for key in settings:config.set_value("tools",key,settings[key])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONFIG.get_base_dir()))
		if config.save(CONFIG)!=OK:w.notice("Could not save optional-tool settings.")
		else:dialog.window.queue_free())
func transcribe()->void:
	var w:Variant=get_parent();var clip:ActorClip=w.session.primary_clip()
	if clip==null:w.notice("Select one dialogue clip to transcribe.");return
	if not w.session.can_edit(clip.id) or w.recorder.recording or w._record_busy or w.session._before!=null:w.notice("Finish recording/editing and select an unlocked clip first.");return
	if str(settings.whisper).is_empty() or str(settings.model).is_empty():configure();return
	var context:=_context();context.clip_id=clip.id;var token:=_remember("transcribe",context)
	var snapshot:KiwiAudioDocument=w.session.document.snapshot();var id:=clip.id;var executable:=str(settings.whisper);var model:=str(settings.model)
	jobs.request("transcribe",func(job:RefCounted):
		var result:=Transcription.run(snapshot,id,executable,model,job);result.token=token;return result)
	w.status.text="Preparing selected clip for local transcription…"
func review_saved_transcript()->void:
	var w:Variant=get_parent();var actor:ActorData=w.session.primary_actor();var clip:ActorClip=w.session.primary_clip()
	if actor==null or clip==null or not actor.values.get(&"transcript") is Dictionary:w.notice("The selected clip has no saved transcript.");return
	var result:Dictionary=actor.values[&"transcript"].duplicate(true);var context:=_context();context.clip_id=clip.id
	if not _current(context):w.notice("Finish the current edit/recording before reviewing a transcript.");return
	_review(context,result)
func speech()->void:
	var w:Variant=get_parent();var context:=_context();var dialog:Dictionary=w._window("Optional cloud speech · review before sending",Vector2i(690,580))
	w._label(dialog.host,"Provider: ElevenLabs · Model: eleven_multilingual_v2 · Text only. No selected clip audio is uploaded. Pricing depends on your provider plan; Kiwi cannot quote or cap the charge. The request may use paid quota. Maximum 3000 characters; results limited to three minutes.")
	var prompt:=TextEdit.new();prompt.custom_minimum_size.y=150;prompt.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(prompt)
	var voice:=_field(dialog.host,"Authorized voice ID",str(settings.voice_id))
	var send:CheckBox=w._check(dialog.host,"I approve sending this text to ElevenLabs",false,func(_value:bool):pass)
	var cost:CheckBox=w._check(dialog.host,"I approve unknown cost / use of my provider quota",false,func(_value:bool):pass)
	var authorized:CheckBox=w._check(dialog.host,"I am authorized to use this voice",false,func(_value:bool):pass)
	w._button(dialog.host,"Generate approved request",func():
		if not _current(context):w.notice("The composition changed. Reopen the speech dialog.");return
		if not send.button_pressed or not cost.button_pressed or not authorized.button_pressed:w.notice("All three confirmations are required before any provider request.");return
		var request:Dictionary={"task":"speech","model":"eleven_multilingual_v2","prompt":prompt.text,"voice_id":voice.text.strip_edges()};var consent:Dictionary={"send_request":true,"unknown_cost":true,"voice_authorized":true}
		var token:=_remember("speech",context)
		jobs.request("speech",func(job:RefCounted):var result:=service.run("elevenlabs",request,consent,job);result.token=token;return result)
		dialog.window.queue_free();w.status.text="Generating approved cloud speech…")
	w._button(dialog.host,"Configure provider credential",configure)
func _completed(kind:String,_generation:int,result:Variant)->void:
	var w:Variant=get_parent()
	if not result is Dictionary:return
	if kind=="vault":w.notice("Credential operation completed. No key is stored in the composition." if bool(result.get("success",false)) else str(result.get("error","Credential operation failed.")));return
	var token:=str(result.get("token",""));var context:Dictionary=contexts.get(token,{})
	contexts.erase(token)
	if context.is_empty() or not _current(context):w.status.text="Optional audio job discarded because its original composition changed.";return
	if not str(result.get("error","")).is_empty():w.notice(str(result.error));return
	if kind=="transcribe":_review(context,result)
	elif kind=="speech":
		var dialog:Dictionary=w._window("Review generated speech",Vector2i(560,280));var stream:AudioStream=result.stream
		w._label(dialog.host,"Review before inserting. This result stays local. Insert preserves the generated-audio provenance and supports Undo.")
		w._button(dialog.host,"Audition",func():w.preview_player.stream=stream;w.preview_player.play())
		w._button(dialog.host,"Insert at original playhead · one Undo",func():
			if not _current(context):w.notice("The composition changed. Generate again in the intended composition.");return
			var track:Dictionary=w.session.document.track_for_id(str(context.track))
			if track.is_empty() or bool(track.get("locked",false)):w.notice("The original destination track is unavailable or locked.");return
			w.session.action("Insert generated speech",func():
				var clip:ActorClip=w.session.insert_source(stream,float(context.time),str(context.track),"Generated speech")
				var actor:ActorData=w.session.document.actor_for_clip(clip.id);actor.values[&"provider_origin"]=result.metadata.duplicate(true))
			dialog.window.queue_free())
func _review(context:Dictionary,result:Dictionary)->void:
	var w:Variant=get_parent();var dialog:Dictionary=w._window("Review local transcript",Vector2i(780,600))
	w._label(dialog.host,"Recognition can be wrong. Edit the text before saving; source audio is untouched. Segment timing follows the rendered clip, including its playback transforms.")
	var text:=TextEdit.new();text.text=str(result.text);text.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(text)
	var rows:=ItemList.new();rows.custom_minimum_size.y=140;dialog.host.add_child(rows)
	for segment in result.segments:rows.add_item("%.2f–%.2f  %s"%[float(segment.start),float(segment.end),str(segment.text)])
	rows.item_activated.connect(func(index:int):
		if _current(context):w.playback.seek(float(context.document.clip_for_id(str(context.clip_id)).start_time)+float(result.segments[index].start)))
	var markers:CheckBox=w._check(dialog.host,"Also add segment cue markers (original recognized text)",false,func(_value:bool):pass)
	w._button(dialog.host,"Save reviewed transcript · one Undo",func():
		if not _current(context):w.notice("The composition changed. Transcribe again to preserve timing.");return
		var error:=Transcription.apply(w.session,str(context.clip_id),result,text.text,markers.button_pressed)
		if not error.is_empty():w.notice(error)
		else:dialog.window.queue_free())
func cancel()->void:
	jobs.cancel_all();contexts.clear()
