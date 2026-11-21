class_name KiwiAudioWorkspace
extends Control
## Native composition UI; all audio sources, transport and recorder APIs are shared with Scene Workspace.
signal document_changed
signal background_document_changed(changed_session: KiwiAudioEditSession)
signal audio_saved(source: Variant)
signal use_in_scene(stream: AudioStream, label: String)
const AUDIO_EXTENSIONS := ["wav","mp3","ogg","flac"]
const RECORDING_OPTIONS_PATH := "user://audio_workspace_recording.cfg"
var session := KiwiAudioEditSession.new()
var source: Variant
var path := ""
var document_path := ""
var _dirty: bool:
 get: return session.dirty
var cache := KiwiAudioSourceCache.new()
var jobs := KiwiAudioJobs.new()
var playback := KiwiAudioPlayback.new()
var automation_recording := KiwiAudioAutomationRecording.new()
var _automation_mode: OptionButton
var _automation_target_label := Label.new()
var _automation_status := Label.new()
var _automation_fader := HSlider.new()
var _automation_release_timer := Timer.new()
var _automation_gesture_held := false
var _automation_mixer_controls: Array[Dictionary] = []
var recorder := ActorAudioRecorder.new()
var _record_finalize_context:Dictionary={}
var preview_player := AudioStreamPlayer.new()
var asset_file_preview := KiwiAudioFilePreview.new()
var library := KiwiAudioLibrary.new()
var canvas := KiwiAudioTimelineCanvas.new()
var waveform := KiwiAudioWaveformCanvas.new()
var piano := KiwiAudioPatternCanvas.new()
var steps := KiwiAudioPatternCanvas.new()
var inspector := VBoxContainer.new()
var effects_panel := VBoxContainer.new()
var mixer_panel := HBoxContainer.new()
var analysis_panel := VBoxContainer.new()
var bottom := TabContainer.new()
var _pattern_lengths: Dictionary = {}
var step_controls := KiwiAudioStepControls.new()
var main_split := HSplitContainer.new()
var right_split := HSplitContainer.new()
var vertical_split := VSplitContainer.new()
var title_label := Label.new()
var status := Label.new()
var time_label := Label.new()
var progress := ProgressBar.new()
var play_button: Button
var record_button: Button
var send_scene_button: Button
var loop_button: CheckButton
var meter_input: OptionButton
var snap_button: CheckButton
var tempo_input: SpinBox
var _edit_timer := Timer.new()
var _parameter_gesture := KiwiAudioEditGesture.new()
var _parameter_control_id := 0
var _edit_control_id := 0
var _mixer_gestures: Array[Dictionary] = []
var _interaction_epoch := 0
var _controls_generation := 0
var _preview_timer := Timer.new()
var _refresh_pending := false
var _syncing := false
var _library_entry: Dictionary = {}
var _generator_settings: Dictionary = {}
var _generator_seed: int = 1
var _preview_stream: AudioStreamWAV
var _variations: Array[Dictionary] = []
var _preview_payload:Dictionary = {}
var _generation: int = 0
var _preview_cache: Dictionary = {}
var _wave_clip_id := ""
var _relink_generation := 0
var _wave_clipboard := PackedVector2Array()
var _wave_clipboard_rate: int = 44100
var _analysis_result: Dictionary = {}
var _silence_threshold := -42.0
var _silence_minimum := 0.25
var _silence_keep := 0.12
var _silence_generation := 0
var _silence_review: Dictionary = {}
var _silence_check_at := 0
var _record_start: float = 0
var _record_track := ""
var _record_elapsed: float = 0
var _record_busy := false
var _record_session: KiwiAudioEditSession
var _record_cancel_requested := false
var _countdown: int = 0
var _latency_ms: float = 0
var _last_command := ""
var _shortcuts: Dictionary = {}
var _commands: Dictionary = {}
var _meter_controls: Dictionary = {}
var _export_options := {"sample_rate":44100,"bit_depth":24,"bitrate":192,"quality":6,"include_tail":true,"normalize":false,"mono":false}
var _pending_export_action := ""
var _render_generation: int = 0
var _record_loop := false
var _record_generation:=0
var _record_phase:="idle"
var _record_preferences:Dictionary={}
var _record_document:KiwiAudioDocument
var _record_owner_document:KiwiAudioDocument
var _record_signature:=""
var _record_processed_capture:=false # Prepared backing may be heard without being printed.
var _record_previous_loop_enabled:=false
var _record_cycle_duration:=0.0
var _record_loop_preview:KiwiAudioRecordingPrepare.Backing
var _record_prepared:KiwiAudioRecordingPrepare.Backing
var _record_failure:=""
var _record_loop_signature:=""
var _portable_jobs := KiwiAudioJobs.new()
var _portable_generation := 0
var _portable_context: Dictionary = {}
var _recovery_jobs := KiwiAudioJobs.new()
var _recovery_store := KiwiAudioRecovery.new()
var _recovery_status := Label.new()
var _recovery_seen_session: KiwiAudioEditSession
var _recovery_seen_document: KiwiAudioDocument
var _recovery_seen_revision := -1
var _recovery_quiet_since := 0
var _recovery_last_at := -15000
var _recovery_attempts: Dictionary = {}
var _recovery_checkpoint_context: Dictionary = {}
var _recovery_review_generation := 0
var _recovery_window: Window
var _transport_token := 0
var _transport_requested := false
var _optional_tools:=preload("res://Workspaces/AudioWorkspace/audio_optional_workflows.gd").new()
var _layout:=preload("res://Workspaces/AudioWorkspace/audio_workspace_layout.gd").new()
func _ready()->void:
 _native_audio_workspace().ready(self)
func _theme()->void:
 _native_audio_workspace().theme(self)
func _box(fill:Color,border:Color,radius:int=5)->StyleBoxFlat:
 return _native_audio_workspace().box(fill,border,radius)
func _button(parent:Node,text:String,callback:Callable,tooltip:String="")->Button:
 return _native_audio_workspace().button(self,parent,text,callback,tooltip)
func _label(parent:Node,text:String)->Label:
 return _native_audio_workspace().label(parent,text)
func _clear(parent:Node)->void:
 _native_audio_workspace().clear(parent)
func _heading(parent:Node,text:String)->void:
 _native_audio_workspace().heading(parent,text)
func _number(parent:Node,label:String,value:float,minimum:float,maximum:float,step:float,callback:Callable,live_context:bool=false)->SpinBox:
 return _native_audio_workspace().number(self,parent,label,value,minimum,maximum,step,callback,live_context)
func _check(parent:Node,label:String,value:bool,callback:Callable)->CheckBox:
 return _native_audio_workspace().check(self,parent,label,value,callback)
func _choice(parent:Node,label:String,items:Array,current:String,callback:Callable)->OptionButton:
 return _native_audio_workspace().choice(self,parent,label,items,current,callback)
func _edit(label:String,callback:Callable)->void:
 _native_audio_workspace().edit(self,label,callback)
func _commit_parameter_edit()->void:
 _native_audio_workspace().commit_parameter_edit(self)
func _discard_parameter_handle()->void:
 _native_audio_workspace().discard_parameter_handle(self)
func _finish_control_edits()->void:
 _native_audio_workspace().finish_control_edits(self)
func _mixer_context_current(control:Control,owner:KiwiAudioEditSession,document:KiwiAudioDocument)->bool:
 return _native_audio_workspace().mixer_context_current(self,control,owner,document)
func _finish_mixer_gesture(state:Dictionary,keep:bool)->void:
 _native_audio_workspace().finish_mixer_gesture(self,state,keep)
func _bind_mixer_slider(slider:Slider,target:Dictionary,track:Dictionary)->void:
 _native_audio_workspace().bind_mixer_slider(self,slider,target,track)
func _build_ui()->void:
 _native_audio_workspace().build_ui(self)
func _pattern_tab(pattern:KiwiAudioPatternCanvas,label:String,sequencer:bool)->void:
 _native_audio_workspace().pattern_tab(self,pattern,label,sequencer)
func _session_changed()->void:
 _native_audio_workspace().session_changed(self)
func _refresh_all()->void:
 _native_audio_workspace().refresh_all(self)
func _sync_pattern_lengths()->void:
 _native_audio_workspace().sync_pattern_lengths(self)
func _selection_changed()->void:
 _native_audio_workspace().selection_changed(self)
static func resolve_document(value:Variant)->Dictionary:
 return _native_audio_workspace().resolve_document(value,value is KiwiAudioDocument)
func open_source(value:Variant,state:Dictionary={})->void:
 _native_audio_workspace().open_source(self,value,state,value is KiwiAudioDocument,state.get("session") is KiwiAudioEditSession)
func capture_state()->Dictionary:
 return _native_audio_workspace().capture_state(self)
func _notification(what:int)->void:
 _native_audio_workspace().workspace_notification(self,what)
func toggle_playback()->void:
 _native_audio_workspace().toggle_playback(self)
func stop()->void:
 _native_audio_workspace().stop(self)
func notice(message:String)->void:
 _native_audio_workspace().notice(self,message)
func _refresh_inspector()->void:
 _native_audio_workspace().refresh_inspector(self)
func _instrument_inspector(actor:ActorData,track:Dictionary)->void:
 _native_audio_workspace().instrument_inspector(self,actor,track)
func _effect_owner()->Dictionary:
 return _native_audio_workspace().effect_owner(self)
func _effect_editable()->bool:
 return _native_audio_workspace().effect_editable(self)
func _refresh_effects()->void:
 _native_audio_workspace().refresh_effects(self)
func batch_effects()->void:
 _native_audio_workspace().batch_effects(self)
func choose_effect_impulse(effect:Dictionary)->void:
 var context:Dictionary=_native_audio_workspace().picker_context(self)
 var chosen:=await ActorProjectFilePicker.pick(self,_audio_property(),"Choose convolution impulse response")
 _native_audio_workspace().complete_effect_impulse(self,context,effect,chosen,chosen==ActorProjectFilePicker.EMPTY_RESOURCE)
func add_effect_dialog()->void:
 _native_audio_workspace().add_effect_dialog(self)
func effect_chain_dialog()->void:
 _native_audio_workspace().effect_chain_dialog(self)
func _refresh_mixer()->void:
 _native_audio_workspace().refresh_mixer(self)
func _process(delta:float)->void:
 _native_audio_workspace().process(self,delta)
func _window(title:String,dimensions:Vector2i=Vector2i(520,400))->Dictionary:
 return _native_audio_workspace().window(self,title,dimensions)
func _name_dialog(title:String,suggested:String,callback:Callable,allow_empty:bool=false)->void:
 _native_audio_workspace().name_dialog(self,title,suggested,callback,allow_empty)
func _library_selected(entry:Dictionary)->void:
 _native_audio_workspace().library_selected(self,entry)
func _generator_inspector()->void:
 _native_audio_workspace().generator_inspector(self)
func _edit_preset_tags(entry:Dictionary)->void:
 _native_audio_workspace().edit_preset_tags(self,entry)
func _save_preset_tags(location:String,digest:String,identity:String,tags:PackedStringArray)->String:
 return _native_audio_workspace().save_preset_tags(location,digest,identity,tags)
func _library_preview(entry:Dictionary)->void:
 _native_audio_workspace().library_preview(self,entry)
func _library_add(entry:Dictionary)->void:
 _native_audio_workspace().library_add(self,entry)
func _generate_preview()->void:
 _native_audio_workspace().generate_preview(self)
func _set_preview(stream:AudioStreamWAV,payload:Dictionary={})->void:
 _native_audio_workspace().set_preview(self,stream,payload)
func _add_preview()->void:
 _native_audio_workspace().add_preview(self)
func _asset_dropped(data:Variant,seconds:float,track_id:String)->void:
 _native_audio_workspace().asset_dropped(self,data,seconds,track_id)
func add_track_dialog()->void:
 _native_audio_workspace().add_track_dialog(self)
func new_pattern(drums:bool=false)->void:
 _native_audio_workspace().new_pattern(self,drums)
func audition_note(pitch:int,patch:Dictionary={})->void:
 _native_audio_workspace().audition_note(self,pitch,patch)
func _render_dirty_notes()->void:
 _native_audio_workspace().render_dirty_notes(self)
func linked_drums_dialog()->void:
 _native_audio_workspace().linked_drums_dialog(self)

func music_dialog()->void:
 _native_audio_workspace().music_dialog(self)

func _compose(settings:Dictionary,role:String="",section_id:String="")->void:
 _native_audio_workspace().compose(self,settings,role,section_id)

func chord_dialog()->void:
 _native_audio_workspace().chord_dialog(self)

func humanize_notes()->void:
 _native_audio_workspace().humanize_notes(self)
func arpeggiate_notes()->void:
 _native_audio_workspace().arpeggiate_notes(self)
func _audio_property()->ActorProperty:
 return _native_audio_workspace().audio_property()
func import_audio()->void:
 var context:Dictionary=_native_audio_workspace().picker_context(self)
 var chosen:=await ActorProjectFilePicker.pick(self,_audio_property(),"Import project audio")
 _native_audio_workspace().complete_import(self,context,chosen,chosen==ActorProjectFilePicker.EMPTY_RESOURCE)
func _queue_import(chosen:String,at:float,track_id:String)->void:
 _native_audio_workspace().queue_import(self,chosen,at,track_id)
func open_dialog()->void:
 var property:ActorProperty=_native_audio_workspace().file_property(PackedStringArray(["tres","res","wav","mp3","ogg","flac"]))
 var chosen:=await ActorProjectFilePicker.pick(self,property,"Open audio composition or source")
 _native_audio_workspace().complete_open(self,chosen,chosen==ActorProjectFilePicker.EMPTY_RESOURCE)
func relink_source()->void:
 _native_audio_workspace().relink_source(self)

func _relink_context_current(context:Dictionary)->bool:
 return _native_audio_workspace().relink_context_current(self,context)

func _pick_audio_relink(context:Dictionary,ids:Array)->void:
 if not _relink_context_current(context):notice("The composition or selection changed. Start relinking again.");return
 var chosen:=await ActorProjectFilePicker.pick(self,_audio_property(),"Choose replacement audio (preserve source windows)")
 if chosen==ActorProjectFilePicker.EMPTY_RESOURCE:return
 _native_audio_workspace().complete_relink_pick(self,context,ids,chosen)

func _review_audio_relink(data:Dictionary)->void:
 _native_audio_workspace().review_audio_relink(self,data)

func _complete_audio_relink(data:Dictionary)->bool:
 return _native_audio_workspace().complete_audio_relink(self,data)

func missing_media_dialog()->void:
 _native_audio_workspace().missing_media_dialog(self)

func _media_context_current(data:Dictionary)->bool:
 return _native_audio_workspace().media_context_current(self,data)

func _show_media_review(data:Dictionary)->void:
 _native_audio_workspace().show_media_review(self,data)

func _confirm_media_repair(data:Dictionary)->void:
 _native_audio_workspace().confirm_media_repair(self,data)

func save()->void:
 var request:Dictionary=_native_audio_workspace().prepare_save(self)
 var target:Dictionary={}
 if bool(request.pick):
  var extension:String=request.extension
  target=await ActorProjectResourceSaveDialog.pick(self,"Save editable audio composition",str(request.title)+".audio",extension,false,PackedStringArray([extension]),_save_snapshot)
 _native_audio_workspace().complete_save(self,request,target)
static func save_document(document:KiwiAudioDocument,destination:String)->Error:
 return _native_audio_workspace().save_document(document,destination)
func export_dialog()->void:
 _native_audio_workspace().export_dialog(self)
func _choose_export(options:Dictionary)->void:
 var request:Dictionary=_native_audio_workspace().prepare_export(self,options)
 if request.is_empty():return
 var target:=await ActorProjectResourceSaveDialog.pick(self,"Export audio",str(request.title),"wav",false,PackedStringArray(["wav","mp3","ogg","flac"]))
 _native_audio_workspace().complete_export(self,request,target,options)
func _start_render(destination:String,options:Dictionary,action:String)->void:
 _native_audio_workspace().start_render(self,destination,options,action)
func _temporary_audio(label:String)->String:
 return _native_audio_workspace().temporary_audio(label)
func render_preview()->void:
 _native_audio_workspace().render_preview(self)
func play_selection()->void:
 _native_audio_workspace().play_selection(self)
func render_in_place()->void:
 _native_audio_workspace().render_in_place(self)
func bounce_track()->void:
 _native_audio_workspace().bounce_track(self)
func freeze_track()->void:
 _native_audio_workspace().freeze_track(self)
func unfreeze_track()->void:
 _native_audio_workspace().unfreeze_track(self)
func send_to_scene()->void:
 _native_audio_workspace().send_to_scene(self)
func save_preview_audio()->void:
 var request:Dictionary=_native_audio_workspace().prepare_preview_save(self)
 if request.is_empty():return
 var target:=await ActorProjectResourceSaveDialog.pick(self,"Save generated audio",str(request.payload.label),"wav",false,PackedStringArray(["wav","mp3","ogg","flac"]))
 _native_audio_workspace().complete_preview_save(self,request,target)
func save_preset(kind:String)->void:
 _native_audio_workspace().save_preset(self,kind)
func export_native_preset(preset:KiwiAudioPreset)->void:
 var copy:KiwiAudioPreset=_native_audio_workspace().prepare_native_preset_export(preset)
 if copy==null:return
 var target:=await ActorProjectResourceSaveDialog.pick(self,"Export native audio preset",copy.label,"tres",false,PackedStringArray(["tres"]))
 _native_audio_workspace().complete_native_preset_export(self,copy,target)
func import_native_preset()->void:
 _native_audio_workspace().import_native_preset(self)
func preset_recovery_dialog()->void:
 _native_audio_workspace().preset_recovery_dialog(self)
func save_layer_bundle()->void:
 _native_audio_workspace().save_layer_bundle(self)
func _audition_native_preset(preset:KiwiAudioPreset)->void:
 _native_audio_workspace().audition_native_preset(self,preset)
func _persist_preset(preset:KiwiAudioPreset)->void:
 _native_audio_workspace().persist_preset(self,preset)
func choose_instrument_sample()->void:
 var context:Dictionary=_native_audio_workspace().prepare_instrument_sample(self)
 if context.is_empty():return
 var chosen:=await ActorProjectFilePicker.pick(self,_audio_property(),"Choose sampler source")
 _native_audio_workspace().complete_instrument_sample(self,context,chosen,chosen==ActorProjectFilePicker.EMPTY_RESOURCE)
func import_midi()->void:
 var context:Dictionary={"session":session,"revision":session.revision}
 var property:=ActorProperty.new();property.options={"extensions":PackedStringArray(["mid","midi"])}
 var chosen:=await ActorProjectFilePicker.pick(self,property,"Import MIDI")
 _native_audio_workspace().complete_midi_import(self,context,chosen)

func export_midi()->void:
 # This exports editable source patterns, not the audio timeline. Different
 # source maps cannot share a single SMF conductor without rewriting beats.
 var midi:=_midi_source_export()
 _save_midi_export(midi,false)

func export_timeline_midi()->void:
 _native_audio_workspace().export_timeline_midi(self)

func _save_midi_export(midi:Dictionary,timeline_notes:bool)->void:
 if not str(midi.get("error","")).is_empty():notice(str(midi.error));return
 var context:Dictionary={"session":session,"revision":session.revision}
 var target:=await ActorProjectResourceSaveDialog.pick(self,"Export timeline notes MIDI" if timeline_notes else "Export source patterns MIDI",session.document.title,"mid",false,PackedStringArray(["mid"]))
 _native_audio_workspace().complete_midi_export(self,context,target,midi,timeline_notes)

func _midi_source_export()->Dictionary:
 return _native_audio_workspace().midi_source_export(self)

func edit_clip(id:String)->void:
 _native_audio_workspace().edit_clip(self,id)

func _wave_detail(start:float,duration:float)->void:
 _native_audio_workspace().wave_detail(self,start,duration)

func _wave_action(operation:String)->void:
 _native_audio_workspace().wave_action(self,operation)

func _perform_wave_edit(operation:String,amount:float)->void:
 _native_audio_workspace().perform_wave_edit(self,operation,amount)

func set_sample_value_dialog()->void:
 _native_audio_workspace().set_sample_value_dialog(self)

func _spectrogram()->void:
 _native_audio_workspace().spectrogram(self)

func sample_noise_profile()->void:
 _native_audio_workspace().sample_noise_profile(self)

func analyze_clip()->void:
 _native_audio_workspace().analyze_clip(self)

func _refresh_analysis()->void:
 _native_audio_workspace().refresh_analysis(self)

func _apply_silences(keep:float)->void:
 _native_audio_workspace().apply_silences(self,keep)

func review_breaths()->void:
 _native_audio_workspace().review_breaths(self)

func _breath_review_ready(result:Dictionary)->void:
 _native_audio_workspace().breath_review_ready(self,result)

func review_dialogue_batch()->void:
 _native_audio_workspace().review_dialogue_batch(self)

func _dialogue_batch_ready(result:Dictionary)->void:
 _native_audio_workspace().dialogue_batch_ready(self,result)

func _silence_review_current(token:int)->bool:
 return _native_audio_workspace().silence_review_current(self,token)

func _silence_choices()->Array:
 return _native_audio_workspace().silence_choices(self)

func _set_silence_choices(token:int,value:bool)->void:
 _native_audio_workspace().set_silence_choices(self,token,value)

func _refresh_silence_review(token:int)->void:
 _native_audio_workspace().refresh_silence_review(self,token)

func _apply_silence_review(token:int)->void:
 _native_audio_workspace().apply_silence_review(self,token)

func _audition_silence_review(token:int)->void:
 _native_audio_workspace().audition_silence_review(self,token)

func _silence_audition_completed(token:int,result:Dictionary)->void:
 _native_audio_workspace().silence_audition_completed(self,token,result)

func _stop_silence_audition(token:int)->void:
 _native_audio_workspace().stop_silence_audition(self,token)

func _close_silence_review(token:int=-1)->void:
 _native_audio_workspace().close_silence_review(self,token)

func _smart_track_problem(track_id:String)->String:
 return _native_audio_workspace().smart_track_problem(self,track_id)

func _alignment_problem(ids:Array)->String:
 return _native_audio_workspace().alignment_problem(self,ids)

func align_selected()->void:
 _native_audio_workspace().align_selected(self)

func match_levels()->void:
 _native_audio_workspace().match_levels(self)

func ducking_dialog()->void:
 _native_audio_workspace().ducking_dialog(self)

func automation_dialog()->void:
 _native_audio_workspace().automation_dialog(self)

func send_dialog()->void:
 _native_audio_workspace().send_dialog(self)

func loop_selection()->void:
 _native_audio_workspace().loop_selection(self)

func add_marker()->void:
 _native_audio_workspace().add_marker(self)

func fit_timeline()->void:
 _native_audio_workspace().fit_timeline(self)

func _requested_recording_preferences()->Dictionary:
 return _native_audio_workspace().requested_recording_preferences(self)

func _save_recording_backing(override_shared:bool,monitor:bool,include:bool)->bool:
 return _native_audio_workspace().save_recording_backing(self,override_shared,monitor,include)

func recording_options()->void:
 _native_audio_workspace().recording_options(self)

func toggle_recording(restart_next:bool=false)->void:
 _native_audio_workspace().toggle_recording(self,restart_next)

func _record_request_owned(token:int)->bool:
 return _native_audio_workspace().record_request_owned(self,token)

func _record_request_current(token:int)->bool:
 return _native_audio_workspace().record_request_current(self,token)

func _abort_record_preparation(token:int,message:String="")->void:
 _native_audio_workspace().abort_record_preparation(self,token,message)

func _cancel_record_preparation()->void:
 _native_audio_workspace().cancel_record_preparation(self)

func _record_preparation_finished(token:int,data:Dictionary)->void:
 _native_audio_workspace().record_preparation_finished(self,token,data)

func _begin_record_capture(token:int,prepared:KiwiAudioRecordingPrepare.Backing)->void:
 _native_audio_workspace().begin_record_capture(self,token,prepared)

func _begin_record_capture_owned(token:int,prepared_id:int)->void:
 var context:Dictionary=_native_audio_workspace().begin_record_startup(self,token,prepared_id)
 if context.is_empty():return
 var state:int=_native_audio_workspace().poll_record_priming(self,context)
 while state==0:
  await get_tree().process_frame
  state=_native_audio_workspace().poll_record_priming(self,context)
 if state<0 or not _native_audio_workspace().begin_record_countdown(self,context):return
 state=_native_audio_workspace().poll_record_countdown(self,context)
 while state==0:
  await get_tree().process_frame
  state=_native_audio_workspace().poll_record_countdown(self,context)
 if state<0 or not _native_audio_workspace().prepare_record_device(self,context):return
 var error:String=await recorder.start()
 var result:Dictionary=_native_audio_workspace().complete_record_device(self,context,error)
 if result.has("abort"):
  if bool(result.get("stop",false)):await recorder.stop()
  _native_audio_workspace().abort_record_device(self,context,result)

func _record_backing_ready(id:int)->bool:
 return _native_audio_workspace().record_backing_ready(self,id)

func _finish_recorded_take(restart_next:bool)->void:
 var context:Dictionary=_native_audio_workspace().prepare_take_stop(self,restart_next)
 var capture:Dictionary=await recorder.stop_to_files()
 _native_audio_workspace().complete_take_stop(self,context,capture)

func _record_finalized(token:int,data:Dictionary)->void:
 _native_audio_workspace().record_finalized(self,token,data)

func _restart_record_loop(owner:WeakRef,generation:int,document:WeakRef)->void:
 _native_audio_workspace().restart_record_loop(self,owner,generation,document)

func finish_recording()->void:
 stop()
 while _record_busy or recorder.recording:
  await get_tree().process_frame

func take_dialog()->void:
 _native_audio_workspace().take_dialog(self)

func recover_disk_takes()->void:
 _native_audio_workspace().recover_disk_takes(self)

func _apply_midi(result:Dictionary)->void:
 _native_audio_workspace().apply_midi(self,result)

func _job_completed(kind:String,generation:int,result:Variant)->void:
 _native_audio_workspace().job_completed(self,kind,generation,result)

func _apply_composer(data:Dictionary)->void:
 _native_audio_workspace().apply_composer(self,data)

func _render_finished(data:Dictionary,generation:int)->void:
 _native_audio_workspace().render_finished(self,data,generation)

func undo()->void:
 _native_audio_workspace().undo(self)

func redo()->void:
 _native_audio_workspace().redo(self)

func _register_commands()->void:
 _native_audio_workspace().register_commands(self)

func _run_command(name:String)->void:
 _native_audio_workspace().run_command(self,name)

func command_palette()->void:
 _native_audio_workspace().command_palette(self)

func customize_shortcuts()->void:
 _native_audio_workspace().customize_shortcuts(self)

func _context_menu(at:Vector2)->void:
 _native_audio_workspace().context_menu(self,at)

func _unhandled_key_input(event:InputEvent)->void:
 _native_audio_workspace().unhandled_key_input(self,event)

func provider_status()->void:
 _optional_tools.configure()

func _requires_exact_preview()->bool:
 return _native_audio_workspace().requires_exact_preview(self)
func _workspace_source(value:Variant)->AudioStream:
 return _native_audio_workspace().workspace_source(value)
func _note_render_key(actor:ActorData)->String:
 return _native_audio_workspace().note_render_key(self,actor)
func harmonize_notes()->void:
 _native_audio_workspace().harmonize_notes(self)
func arrangement_dialog()->void:
 _native_audio_workspace().arrangement_dialog(self)

func _transform_section(id:String,start:float,duration:float)->void:
 _native_audio_workspace().transform_section(self,id,start,duration)

func sample_map_dialog()->void:
 _native_audio_workspace().sample_map_dialog(self)

func choose_generator_sample()->void:
 var chosen:=await ActorProjectFilePicker.pick(self,_audio_property(),"Choose source for granular synthesis")
 _native_audio_workspace().complete_generator_sample(self,chosen,chosen==ActorProjectFilePicker.EMPTY_RESOURCE)
func fit_notes_to_conductor_dialog()->void:
 _native_audio_workspace().fit_notes_to_conductor_dialog(self)

func modulation_matrix_dialog()->void:
 _native_audio_workspace().modulation_matrix_dialog(self)

func modulator_dialog(generator:bool)->void:
 _native_audio_workspace().modulator_dialog(self,generator)

func set_scene_binding(bound:bool)->void:
 _native_audio_workspace().set_scene_binding(self,bound)

func _remove_preview_file(file:String)->void:
 _native_audio_workspace().remove_preview_file(file)
func measure_loudness()->void:
 _native_audio_workspace().measure_loudness(self)

func effect_automation_dialog(index:int)->void:
 _native_audio_workspace().effect_automation_dialog(self,index)

func _toggle_loop_transport(enabled:bool)->void:
 _native_audio_workspace().toggle_loop_transport(self,enabled)
func _set_record_loop(enabled:bool)->void:
 _native_audio_workspace().set_record_loop(self,enabled)
func _preview_failed(message:String)->void:
 _native_audio_workspace().preview_failed(self,message)
func _exact_requested(_seconds:float)->void:
 _native_audio_workspace().exact_requested(self)
func _cancel_exact_playback()->void:
 _native_audio_workspace().cancel_exact_playback(self)
func cancel_background_jobs()->void:
 _native_audio_workspace().cancel_background_jobs(self)
func _generator_payload(entry:Dictionary,settings:Dictionary,seed_value:int)->Dictionary:
 return _native_audio_workspace().generator_payload(entry,settings,seed_value)
func _preview_matches_controls()->bool:
 return _native_audio_workspace().preview_matches_controls(self)
func _select_variation(payload:Dictionary)->void:
 _native_audio_workspace().select_variation(self,payload)
func _insert_generator_payload(payload:Dictionary,seconds:float,track_id:String)->void:
 _native_audio_workspace().insert_generator_payload(self,payload,seconds,track_id)
func _queue_generator_drop(entry:Dictionary,settings:Dictionary,seed_value:int,seconds:float,track_id:String)->void:
 _native_audio_workspace().queue_generator_drop(self,entry,settings,seed_value,seconds,track_id)
func _generator_drag_payload(entry:Dictionary)->Dictionary:
 return _native_audio_workspace().generator_drag_payload(self,entry)
func _capture_pattern_view(pattern:KiwiAudioPatternCanvas)->Dictionary:
 return _native_audio_workspace().capture_pattern_view(pattern)
func _restore_pattern_view(pattern:KiwiAudioPatternCanvas,state:Dictionary)->void:
 _native_audio_workspace().restore_pattern_view(self,pattern,state)
func _toggle_effect_bypass()->void:
 _native_audio_workspace().toggle_effect_bypass(self)

func _analysis_identity(actor:ActorData)->String:
 return _native_audio_workspace().analysis_identity(actor)

func _analysis_provenance_current(data:Dictionary,generation:int)->bool:
 return _native_audio_workspace().analysis_provenance_current(self,data,generation)

func _accept_analysis_result(data:Dictionary,generation:int,loudness:bool=false)->void:
 _native_audio_workspace().accept_analysis_result(self,data,generation,loudness)

func _analysis_current()->bool:
 return _native_audio_workspace().analysis_current(self)

func _add_attack_markers()->void:
 _native_audio_workspace().add_attack_markers(self)

func pattern_tags_dialog()->void:
 _native_audio_workspace().pattern_tags_dialog(self)
func import_pattern_json()->void:
 _native_audio_workspace().import_pattern_json(self)
func export_pattern_json()->void:
 _native_audio_workspace().export_pattern_json(self)
func _build_automation_controls(parent:Node)->void:
 _native_audio_workspace().build_automation_controls(self,parent)
func _bind_automation_fader(fader:Slider)->void:
 _native_audio_workspace().bind_automation_fader(self,fader)
func _arm_automation_mode(mode:String,owner_session:KiwiAudioEditSession,epoch:int)->void:
 _native_audio_workspace().arm_automation_mode(self,mode,owner_session,epoch)
func _automation_status_changed(message:String)->void:
 _native_audio_workspace().automation_status_changed(self,message)
func _refresh_automation_controls()->void:
 _native_audio_workspace().refresh_automation_controls(self)
func _mixer_target_editable(target:Dictionary)->bool:
 return _native_audio_workspace().mixer_target_editable(self,target)
func _automation_consumes(target:Dictionary)->bool:
 return _native_audio_workspace().automation_consumes(self,target)
func _automation_gesture_start()->void:
 _native_audio_workspace().automation_gesture_start(self)
func _automation_control_changed(value:float)->void:
 _native_audio_workspace().automation_control_changed(self,value)
func _automation_gesture_end()->void:
 _native_audio_workspace().automation_gesture_end(self)
func _finish_automation_pass(reason:String)->void:
 _native_audio_workspace().finish_automation_pass(self,reason)
func _automation_seek(seconds:float,scrub:bool=false)->void:
 _native_audio_workspace().automation_seek(self,seconds,scrub)
func _choose_automation_record_target(target:Dictionary,lane_id:String="")->void:
 _native_audio_workspace().choose_automation_record_target(self,target,lane_id)
func automation_record_target_dialog()->void:
 _native_audio_workspace().automation_record_target_dialog(self)
func _update_automation_readouts()->void:
 _native_audio_workspace().update_automation_readouts(self)
func _exit_tree()->void:
 _native_audio_workspace().exit_tree(self)
func _automation_lane_inspector(track:Dictionary)->void:
 _native_audio_workspace().automation_lane_inspector(self,track)
func automation_lane_target_dialog(lane_id:String="",initial:Dictionary={})->void:
 _native_audio_workspace().automation_lane_target_dialog(self,lane_id,initial)
func _show_automation_editor_in_lane(editor:KiwiAudioAutomationCanvas)->void:
 _native_audio_workspace().show_automation_editor_in_lane(self,editor)
func automation_lane_editor(lane_id:String)->void:
 _native_audio_workspace().automation_lane_editor(self,lane_id)
func conductor_dialog()->void:
 _native_audio_workspace().conductor_dialog(self)
func retime_notes_dialog()->void:
 _native_audio_workspace().retime_notes_dialog(self)
static func _stem_destination(destination:String,track:Dictionary,used:Dictionary)->String:
 return _native_audio_workspace().stem_destination(destination,track,used)
func _recovery_id()->String:
 return _native_audio_workspace().recovery_id(self)

func _recovery_safe()->bool:
 return _native_audio_workspace().recovery_safe(self)

func _recovery_tick()->void:
 _native_audio_workspace().recovery_tick(self)

func _queue_recovery_checkpoint(manual:bool=false)->void:
 _native_audio_workspace().queue_recovery_checkpoint(self,manual)

func _recovery_completed(kind:String,_generation:int,result:Variant)->void:
 _native_audio_workspace().recovery_completed(self,kind,_generation,result)

func _recovery_context_current(context:Dictionary)->bool:
 return _native_audio_workspace().recovery_context_current(self,context)

func _close_recovery_review()->void:
 _native_audio_workspace().close_recovery_review(self)

func review_recovery()->void:
 _native_audio_workspace().review_recovery(self)

func _show_recovery_entries(context:Dictionary,entries:Array)->void:
 _native_audio_workspace().show_recovery_entries(self,context,entries)

func _request_recovery_restore(context:Dictionary,entry:Dictionary)->void:
 _native_audio_workspace().request_recovery_restore(self,context,entry)

func _portable_current(token:int)->bool:
 return _native_audio_workspace().portable_current(self,token)

func _close_portable_review(token:int=-1)->void:
 _native_audio_workspace().close_portable_review(self,token)

func review_portable_copy()->void:
 _native_audio_workspace().review_portable_copy(self)

func _portable_completed(kind:String,token:int,result:Variant)->void:
 _native_audio_workspace().portable_completed(self,kind,token,result)

func _show_portable_inventory(token:int)->void:
 _native_audio_workspace().show_portable_inventory(self,token)

func _choose_portable_parent(token:int)->void:
 _native_audio_workspace().choose_portable_parent(self,token)

func _prepare_portable_copy(token:int)->void:
 _native_audio_workspace().prepare_portable_copy(self,token)

func open_collected_copy()->void:
 _native_audio_workspace().open_collected_copy(self)

static func _native_audio_workspace()->Object:
 return Engine.get_singleton("KiwiNativeServices").service("audio_workspace")
func _connect_control(control:Control,signal_name:String,callback:Callable)->void:
 control.connect(signal_name,callback)
func _invoke_value(callback:Callable,value:Variant)->void:callback.call(value)
func _invoke_action(callback:Callable)->void:callback.call()

func _new_parameter_gesture()->RefCounted:return KiwiAudioEditGesture.new()

func _new_audio_session()->KiwiAudioEditSession:return KiwiAudioEditSession.new()

func _save_snapshot()->KiwiAudioDocument:return _native_audio_workspace().save_snapshot(self)
func _refresh_project_filesystem()->void:
 if LocalProjectFilesystem.node!=null:LocalProjectFilesystem.update_root_folder()

func _pick_media_replacement(data:Dictionary,source_path:String,dialog_window:Window)->void:
 if not _media_context_current(data):notice("The composition changed. Reopen Missing media.");return
 var chosen:=await ActorProjectFilePicker.pick(dialog_window,_audio_property(),"Repair linked media")
 _native_audio_workspace().complete_media_pick(self,data,source_path,chosen,dialog_window)
