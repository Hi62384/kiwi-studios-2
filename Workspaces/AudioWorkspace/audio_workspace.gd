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
var _parameter_gesture := KiwiAudioEditSession.Gesture.new()
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
var _recovery_store := KiwiAudioDocument.Recovery.new()
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
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 _theme()
 recorder.disk_backed=true
 add_child(cache);add_child(jobs);add_child(playback);add_child(recorder);add_child(preview_player);add_child(asset_file_preview)
 add_child(_optional_tools)
 add_child(_layout)
 add_child(_portable_jobs);_portable_jobs.completed.connect(_portable_completed)
 _portable_jobs.progress_changed.connect(func(value:float,message:String):
  if not _portable_context.is_empty():progress.value=value*100;status.text=message)
 add_child(_recovery_jobs);_recovery_jobs.completed.connect(_recovery_completed)
 playback.preview_file_released.connect(_remove_preview_file)
 asset_file_preview.released.connect(_remove_preview_file)
 playback.preview_failed.connect(_preview_failed)
 asset_file_preview.failed.connect(func(message:String):status.text=message)
 asset_file_preview.player.volume_db=-6
 preview_player.volume_db=-6
 _edit_timer.one_shot=true;_edit_timer.wait_time=0.3;add_child(_edit_timer);_edit_timer.timeout.connect(_commit_parameter_edit)
 _automation_release_timer.one_shot=true;_automation_release_timer.wait_time=0.25;add_child(_automation_release_timer)
 _automation_release_timer.timeout.connect(func():
  if not _automation_gesture_held:automation_recording.release(playback.position))
 automation_recording.status_changed.connect(_automation_status_changed)
 automation_recording.bind(session,playback)
 _preview_timer.one_shot=true;_preview_timer.wait_time=0.18;add_child(_preview_timer);_preview_timer.timeout.connect(_generate_preview)
 session.changed.connect(_session_changed);session.selection_changed.connect(_selection_changed)
 jobs.completed.connect(_job_completed);jobs.progress_changed.connect(func(value:float,message:String):progress.value=value*100;status.text=message)
 playback.exact_requested.connect(_exact_requested)
 playback.position_changed.connect(func(seconds:float):canvas.playhead=seconds;canvas.queue_redraw();time_label.text="%02d:%06.3f  ·  %s"%[int(seconds)/60,fmod(seconds,60),playback.musical_position(seconds)])
 playback.state_changed.connect(func():
  if play_button!=null:play_button.text="Ⅱ" if playback.playing else "▶"
  automation_recording.transport_changed(playback.playing,playback.position))
 _build_ui();_register_commands()
 var config:=ConfigFile.new()
 if config.load("user://audio_workspace/shortcuts.cfg")==OK:_shortcuts=config.get_value("keys","commands",{})
 if session.document.tracks.is_empty():session.open(KiwiAudioDocument.from_source(null))
 _refresh_all()
func _theme()->void:
 var ui:=Theme.new();ui.default_font_size=12;theme=ui
 for type in ["Button","OptionButton","MenuButton"]:
  ui.set_stylebox("normal",type,_box(Color("20303c"),Color("3c5668"),5))
  ui.set_stylebox("hover",type,_box(Color("2b4c4b"),Color("6cdcc0"),5))
  ui.set_stylebox("pressed",type,_box(Color("2c6254"),Color("77e4c3"),5))
 ui.set_stylebox("panel","PanelContainer",_box(Color("14202b"),Color("334a5c"),5))
 ui.set_stylebox("normal","LineEdit",_box(Color("111c26"),Color("405b70"),4))
 ui.set_stylebox("panel","TabContainer",_box(Color("14212d"),Color("3e5669"),5))
 ui.set_color("font_color","Label",Color("dbe7f0"))
func _box(fill:Color,border:Color,radius:int=5)->StyleBoxFlat:
 var style:=StyleBoxFlat.new();style.bg_color=fill;style.border_color=border;style.set_corner_radius_all(radius);style.set_border_width_all(1)
 style.content_margin_left=8;style.content_margin_right=8;style.content_margin_top=5;style.content_margin_bottom=5;return style
func _button(parent:Node,text:String,callback:Callable,tooltip:String="")->Button:
 var button:=Button.new();button.text=text;button.tooltip_text=tooltip;button.pressed.connect(callback);parent.add_child(button);return button
func _label(parent:Node,text:String)->Label:
 var label:=Label.new();label.text=text
 # Flow/row containers need the label's natural width. Wrapping a zero-width
 # minimum there makes each character a line and stretches every row control.
 label.autowrap_mode=TextServer.AUTOWRAP_OFF if parent is HFlowContainer or parent is HBoxContainer else TextServer.AUTOWRAP_WORD_SMART
 parent.add_child(label);return label
func _clear(parent:Node)->void:
 for child in parent.get_children():parent.remove_child(child);child.queue_free()
func _heading(parent:Node,text:String)->void:
 var label:=_label(parent,text.to_upper());label.add_theme_color_override("font_color",Color("7bdfc6"));label.add_theme_font_size_override("font_size",11)
func _number(parent:Node,label:String,value:float,minimum:float,maximum:float,step:float,callback:Callable,live_context:bool=false)->SpinBox:
 var row:=HBoxContainer.new();parent.add_child(row)
 var caption:=Label.new();caption.text=label;caption.custom_minimum_size.x=104;row.add_child(caption)
 var number:=SpinBox.new();number.min_value=minimum;number.max_value=maximum;number.step=step;number.value=value;number.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(number)
 var owner:=session;var document:=session.document;var generation:=_controls_generation
 number.value_changed.connect(func(next:float):
  if not number.is_inside_tree() or number.is_queued_for_deletion():return
  if not live_context and (session!=owner or session.document!=document or generation!=_controls_generation):return
  var previous:=_edit_control_id;_edit_control_id=number.get_instance_id()
  callback.call(next)
  _edit_control_id=previous)
 return number
func _check(parent:Node,label:String,value:bool,callback:Callable)->CheckBox:
 var button:=CheckBox.new();button.text=label;button.button_pressed=value;button.toggled.connect(callback);parent.add_child(button);return button
func _choice(parent:Node,label:String,items:Array,current:String,callback:Callable)->OptionButton:
 var row:=HBoxContainer.new();parent.add_child(row)
 if not label.is_empty():var caption:=Label.new();caption.text=label;caption.custom_minimum_size.x=86;row.add_child(caption)
 var choice:=OptionButton.new();choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(choice)
 for item in items:
  choice.add_item(str(item))
  if str(item)==current:choice.select(choice.item_count-1)
 choice.item_selected.connect(func(index:int):callback.call(str(items[index])))
 return choice
func _edit(label:String,callback:Callable)->void:
 if _syncing:return
 _finish_automation_pass("Another parameter edit ended the pass")
 if not _parameter_gesture.valid(session) or _parameter_control_id!=_edit_control_id:
  _commit_parameter_edit()
  _parameter_gesture.begin(session,label);_parameter_control_id=_edit_control_id
 callback.call();session.preview();_edit_timer.start()
func _commit_parameter_edit()->void:
 _edit_timer.stop();_parameter_control_id=0
 _parameter_gesture.finish(session)
func _discard_parameter_handle()->void:
 _edit_timer.stop();_parameter_control_id=0;_parameter_gesture.clear()
func _finish_control_edits()->void:
 _commit_parameter_edit()
 for state in _mixer_gestures:_finish_mixer_gesture(state,true)
 canvas.finish_edit();piano.finish_edit();steps.finish_edit();canvas.finish_automation_edit()
 _interaction_epoch+=1
func _mixer_context_current(control:Control,owner:KiwiAudioEditSession,document:KiwiAudioDocument)->bool:
 return control.is_inside_tree() and not control.is_queued_for_deletion() and session==owner and session.document==document
func _finish_mixer_gesture(state:Dictionary,keep:bool)->void:
 var held:bool=state.held;state.held=false
 if held:state.blocked=true
 if not held:return
 if state.automation:
  if int(state.epoch)==_interaction_epoch:
   if keep:_automation_gesture_end()
   else:
    _interaction_epoch+=1;automation_recording.discard("Read: gesture cancelled.")
 else:state.gesture.finish(session,keep and bool(state.changed))
func _bind_mixer_slider(slider:Slider,target:Dictionary,track:Dictionary)->void:
 var owner:=session;var document:=session.document
 var state:Dictionary={"held":false,"blocked":false,"automation":false,"epoch":0,"changed":false,"gesture":KiwiAudioEditSession.Gesture.new()}
 _mixer_gestures.append(state)
 slider.drag_started.connect(func():
  if not _mixer_context_current(slider,owner,document) or not _mixer_target_editable(target):return
  _finish_mixer_gesture(state,true)
  state.blocked=false;state.automation=_automation_consumes(target);state.changed=false
  if state.automation:
   _commit_parameter_edit();_automation_gesture_start()
  else:
   _finish_automation_pass("Mixer edit ended the pass")
   # Range can emit the initial click value before drag_started. Adopt that
   # same control's pending numeric edit instead of splitting one drag.
   if _parameter_gesture.valid(session) and _parameter_control_id==slider.get_instance_id():
    state.gesture=_parameter_gesture;state.changed=true
    _parameter_gesture=KiwiAudioEditSession.Gesture.new();_edit_timer.stop();_parameter_control_id=0
   else:
    _commit_parameter_edit();state.gesture.begin(session,"Mix volume")
  state.epoch=_interaction_epoch;state.held=true)
 slider.value_changed.connect(func(value:float):
  if state.blocked:return
  if not _mixer_context_current(slider,owner,document) or not _mixer_target_editable(target):return
  if state.held:
   if int(state.epoch)!=_interaction_epoch:return
   if state.automation:
    if _automation_consumes(target):_automation_control_changed(value)
    return # Never reinterpret an interrupted automation drag as a static edit.
   if not state.gesture.valid(session):return
   if is_equal_approx(float(track.get("volume_db",0)),value):return
   track.volume_db=value;state.changed=true;session.preview()
  else:
   if _automation_consumes(target):_automation_control_changed(value);return
   var previous:=_edit_control_id;_edit_control_id=slider.get_instance_id()
   _edit("Mix volume",func():track.volume_db=value)
   _edit_control_id=previous
  playback.synchronize())
 slider.drag_ended.connect(func(_changed:bool):_finish_mixer_gesture(state,true);state.blocked=false)
 slider.focus_exited.connect(func():_finish_mixer_gesture(state,true))
 slider.focus_entered.connect(func():
  if not state.held:state.blocked=false)
 slider.tree_exiting.connect(func():_finish_mixer_gesture(state,true))
 slider.gui_input.connect(func(event:InputEvent):
  if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
   _finish_mixer_gesture(state,false);slider.accept_event())

func _build_ui()->void:
 var background:=Panel.new();background.add_theme_stylebox_override("panel",_box(Color("101923"),Color("101923"),0));background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
 var root:=VBoxContainer.new();root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.offset_left=10;root.offset_top=8;root.offset_right=-10;root.offset_bottom=-8;root.add_theme_constant_override("separation",8);add_child(root)
 _layout.header(root)
 var toolbar:=HFlowContainer.new();root.add_child(toolbar)
 var transport:=_layout.group(toolbar)
 play_button=_button(transport,"▶",toggle_playback,"Play / Pause (Space)");_button(transport,"■",stop,"Stop (Home)")
 time_label.text="00:00.000";time_label.custom_minimum_size.x=150;time_label.tooltip_text="Elapsed minutes:seconds · musical position (bar.beat.tick)";time_label.add_theme_color_override("font_color",Color("a7dcd3"));transport.add_child(time_label)
 record_button=_button(transport,"● Record",toggle_recording,"Record selected sources (R)")
 var options:=Button.new();options.set_script(load("res://scripts/Extra/editor_settings_button.gd"));options.text="▾";options.tooltip_text="Choose microphone, system and timeline recording sources";transport.add_child(options)
 loop_button=CheckButton.new();loop_button.text="Loop";loop_button.toggled.connect(_toggle_loop_transport);transport.add_child(loop_button)
 var grid:=_layout.group(toolbar)
 var tempo_row:=HBoxContainer.new();grid.add_child(tempo_row);_label(tempo_row,"BPM")
 tempo_input=SpinBox.new();tempo_input.min_value=20;tempo_input.max_value=400;tempo_input.step=1;tempo_input.value=120;tempo_input.custom_minimum_size.x=72;tempo_row.add_child(tempo_input)
 tempo_input.tooltip_text="Initial project conductor BPM. Existing clip positions, audio and source-relative note timing are preserved. Conductor opens tempo/meter points; Uniform retime is a separate action."
 tempo_input.value_changed.connect(func(value:float):
  if _syncing:return
  _finish_automation_pass("Initial grid tempo edited")
  var problem:=session.set_conductor(value,session.document.time_signature,session.document.tempo_points,session.document.meter_points)
  if not problem.is_empty():tempo_input.set_value_no_signal(session.document.tempo);status.text=problem)
 meter_input=OptionButton.new();for item in ["4/4","3/4","6/8","5/4","7/8"]:meter_input.add_item(item)
 grid.add_child(meter_input);meter_input.item_selected.connect(func(index:int):
  _finish_automation_pass("Initial grid meter edited")
  var parts:=meter_input.get_item_text(index).split("/")
  var problem:=session.set_conductor(session.document.tempo,Vector2i(int(parts[0]),int(parts[1])),session.document.tempo_points,session.document.meter_points)
  if not problem.is_empty():
   status.text=problem
   var original:="%d/%d"%[session.document.time_signature.x,session.document.time_signature.y]
   for item in meter_input.item_count:
    if meter_input.get_item_text(item)==original:meter_input.select(item);break)
 var click:=CheckButton.new();click.text="Metronome";click.toggled.connect(func(enabled:bool):playback.metronome=enabled);grid.add_child(click)
 var edit_tools:=_layout.group(toolbar)
 snap_button=CheckButton.new();snap_button.text="Snap";snap_button.button_pressed=true;snap_button.toggled.connect(func(enabled:bool):canvas.snap=enabled);edit_tools.add_child(snap_button)
 _button(edit_tools,"↶",undo,"Undo · Ctrl+Z");_button(edit_tools,"↷",redo,"Redo · Ctrl+Shift+Z")
 _layout.automation_panel=VBoxContainer.new();root.add_child(_layout.automation_panel);_build_automation_controls(_layout.automation_panel);_layout.automation_panel.hide()
 main_split.size_flags_vertical=Control.SIZE_EXPAND_FILL;main_split.size_flags_horizontal=Control.SIZE_EXPAND_FILL;main_split.split_offset=220;root.add_child(main_split)
 main_split.add_child(library);library.generator_drag_payload=_generator_drag_payload;library.selected.connect(_library_selected);library.preview_requested.connect(_library_preview);library.add_requested.connect(_library_add)
 var right:=right_split;right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right.split_offset=800;main_split.add_child(right)
 vertical_split.size_flags_horizontal=Control.SIZE_EXPAND_FILL;vertical_split.size_flags_vertical=Control.SIZE_EXPAND_FILL;vertical_split.split_offset=340;right.add_child(vertical_split)
 var timeline_column:=VBoxContainer.new();vertical_split.add_child(timeline_column)
 _layout.detail_controls(timeline_column)
 canvas.session=session;canvas.cache=cache;canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL;canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL;timeline_column.add_child(canvas)
 canvas.seek_requested.connect(_automation_seek);canvas.edit_requested.connect(edit_clip);canvas.context_requested.connect(_context_menu);canvas.asset_dropped.connect(_asset_dropped)
 canvas.range_changed.connect(func(selection:Vector2):status.text="Selected %.6f–%.6f s"%[selection.x,selection.y])
 canvas.automation_requested.connect(func(id:String,retarget:bool):
  if retarget:automation_lane_target_dialog(id)
  else:automation_lane_editor(id))
 _layout.install_empty_state()
 var timeline_tools:=HFlowContainer.new();timeline_column.add_child(timeline_tools);_layout.clip_actions=timeline_tools
 for entry in [["Split",func():session.split_selected(playback.position)],["Duplicate",func():session.duplicate_selected()],["Delete",func():session.delete_selected()]]:_button(timeline_tools,entry[0],entry[1])
 _layout.menu(timeline_tools,"Clip actions",[["Crossfade selected clips",func():session.crossfade_selected()],["Loop selection",loop_selection],["Render in place",render_in_place],["Analyze selected clip",analyze_clip],["Relink source…",relink_source]])
 var scroll:=HScrollBar.new();scroll.max_value=3600;scroll.step=0.01;scroll.page=10;timeline_column.add_child(scroll);scroll.value_changed.connect(func(value:float):canvas.scroll_time=value;canvas.queue_redraw())
 bottom.custom_minimum_size.y=200;bottom.size_flags_vertical=Control.SIZE_EXPAND_FILL;vertical_split.add_child(bottom);bottom.hide()
 var wave_tab:=VBoxContainer.new();wave_tab.name="Waveform";bottom.add_child(wave_tab)
 var wave_tools:=HFlowContainer.new();wave_tab.add_child(wave_tools)
 for op in ["Cut","Copy","Paste"]:_button(wave_tools,op,_wave_action.bind(op.to_lower()))
 var wave_operations:Array=[]
 for op in ["Silence","Amplify","Normalize","Reverse","Fade In","Fade Out","Trim","Repair","Time Stretch","Pitch Shift"]:wave_operations.append([op,_wave_action.bind(op.to_lower().replace(" ","_"))])
 _layout.menu(wave_tools,"Process selection",wave_operations)
 _button(wave_tools,"▶ Selection",play_selection)
 _layout.menu(wave_tools,"Inspect",[["Spectrum",_spectrogram],["Learn noise profile",sample_noise_profile],["Set sample amplitude…",set_sample_value_dialog]])
 _choice(wave_tools,"",["Stereo","Left","Right"],"Stereo",func(value:String):waveform.channel={"Stereo":-1,"Left":0,"Right":1}[value];waveform.queue_redraw())
 waveform.cache=cache;waveform.size_flags_vertical=Control.SIZE_EXPAND_FILL;wave_tab.add_child(waveform)
 waveform.detail_requested.connect(_wave_detail);waveform.seek_requested.connect(func(seconds:float):var clip:=session.document.clip_for_id(_wave_clip_id);if clip!=null:_automation_seek(clip.start_time+(seconds-clip.source_offset)/clip.playback_speed,true))
 waveform.selection_changed.connect(func(first:int,last:int):status.text="%d samples selected (%.6f s)"%[last-first,float(last-first)/waveform.rate])
 _pattern_tab(piano,"Notes",false);_pattern_tab(steps,"Drums",true)
 var effect_scroll:=ScrollContainer.new();effect_scroll.name="Effects";bottom.add_child(effect_scroll);effects_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;effect_scroll.add_child(effects_panel)
 var mixer_scroll:=ScrollContainer.new();mixer_scroll.name="Mixer";bottom.add_child(mixer_scroll);mixer_scroll.add_child(mixer_panel)
 var analyze_scroll:=ScrollContainer.new();analyze_scroll.name="Cleanup";bottom.add_child(analyze_scroll);analysis_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL;analyze_scroll.add_child(analysis_panel)
 var inspector_scroll:=ScrollContainer.new();inspector_scroll.custom_minimum_size.x=265;inspector_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;right.add_child(inspector_scroll);_layout.inspector_scroll=inspector_scroll;inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL;inspector_scroll.add_child(inspector)
 var footer:=HBoxContainer.new();root.add_child(footer);status.text="Import audio, choose a sound, or create an instrument pattern.";status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;footer.add_child(status)
 progress.custom_minimum_size.x=120;progress.show_percentage=false;progress.max_value=100;footer.add_child(progress)
 _layout.busy_button=_button(footer,"Cancel Job",cancel_background_jobs)
 _layout.sync()
func _pattern_tab(pattern:KiwiAudioPatternCanvas,label:String,sequencer:bool)->void:
 var tab:=VBoxContainer.new();tab.name=label;bottom.add_child(tab)
 var row:=HFlowContainer.new();tab.add_child(row)
 _button(row,"New pattern",new_pattern.bind(sequencer));_button(row,"Quantize",pattern.quantize)
 _layout.menu(row,"Edit notes",[["Copy",pattern.copy],["Paste",pattern.paste],["Humanize…",humanize_notes],["Add chord…",chord_dialog],["Arpeggiate",arpeggiate_notes],["Harmonize",harmonize_notes],["Arrangement…",arrangement_dialog]])
 _pattern_lengths[pattern] = _number(row,"Beats",4,1,128,1,func(value:float):pattern.pattern_beats=value;var actor:=session.primary_actor();if actor!=null and session.can_edit(session.primary_clip().id):session.action("Pattern length",func():actor.values[&"pattern_beats"]=value;actor.values[&"notes_dirty"]=true);_render_dirty_notes(),true)
 _layout.menu(row,"Pattern",[["Save preset…",save_preset.bind("pattern")],["Import JSON…",import_pattern_json],["Export JSON…",export_pattern_json],["Edit tags…",pattern_tags_dialog],["Linked drum patterns…",linked_drums_dialog]])
 if sequencer:tab.add_child(step_controls);step_controls.setup(session,pattern);step_controls.changed.connect(_render_dirty_notes)
 pattern.session=session;pattern.mode="steps" if sequencer else "piano";pattern.row_height=23 if sequencer else 16;pattern.size_flags_vertical=Control.SIZE_EXPAND_FILL;tab.add_child(pattern)
 pattern.notes_changed.connect(_render_dirty_notes);pattern.audition.connect(audition_note)
func _session_changed()->void:
 _close_portable_review()
 _close_recovery_review();_recovery_tick()
 _close_silence_review()
 if not _parameter_gesture.valid(session):_discard_parameter_handle()
 automation_recording.document_changed()
 canvas.queue_redraw();piano.queue_redraw();steps.queue_redraw()
 if session._before!=null:playback.synchronize();return
 document_changed.emit()
 if not _refresh_pending:_refresh_pending=true;call_deferred("_refresh_all")
func _refresh_all()->void:
 _refresh_pending=false
 if not is_inside_tree():return
 # A refresh queued by the previous edit must not destroy a new live control.
 if session._before!=null:return
 if automation_recording.active:_finish_automation_pass("Document refresh ended the pass")
 _syncing=true;tempo_input.set_value_no_signal(session.document.tempo);title_label.text=session.document.title+(" •" if session.dirty else "");_syncing=false
 if not _record_processed_capture and _record_prepared==null:
  playback.exact_required=_requires_exact_preview() or playback.exact_pending or playback.exact_preview_active
  playback.set_document(session.document)
 loop_button.set_pressed_no_signal(session.document.loop_enabled);snap_button.set_pressed_no_signal(canvas.snap)
 var meter_text:="%d/%d"%[session.document.time_signature.x,session.document.time_signature.y];var meter_index:=-1
 for i in meter_input.item_count:
  if meter_input.get_item_text(i)==meter_text:meter_index=i;break
 if meter_index<0:meter_input.add_item(meter_text);meter_index=meter_input.item_count-1
 meter_input.select(meter_index)
 time_label.text="%02d:%06.3f  ·  %s"%[int(playback.position)/60,fmod(playback.position,60),playback.musical_position(playback.position)]
 _sync_pattern_lengths();_refresh_inspector();_refresh_effects();_refresh_mixer();_refresh_analysis();_refresh_automation_controls()
 canvas.queue_redraw();piano.queue_redraw();steps.queue_redraw()
 var stale:=false
 for actor in session.document.actors:
  var track:=session.document.track_for_id(str(actor.values.get(&"track_id","")))
  if not track.has("frozen_track") and KiwiAudioEditSession.is_note_source(actor) and str(actor.values.get(&"rendered_signature",""))!=_note_render_key(actor):actor.values[&"notes_dirty"]=true;stale=true
 if stale:_render_dirty_notes()
func _sync_pattern_lengths()->void:
 if step_controls.step_count!=null:step_controls.setup(session,steps)
 var actor:=session.primary_actor()
 var beats:=float(actor.values.get(&"pattern_beats",4.0)) if actor!=null else 4.0
 for pattern in [piano,steps]:
  pattern.pattern_beats=beats
  if _pattern_lengths.has(pattern):(_pattern_lengths[pattern] as SpinBox).set_value_no_signal(beats)
func _selection_changed()->void:
 _layout.selected()
 _close_silence_review()
 _refresh_analysis()
 _finish_control_edits()
 _finish_automation_pass("Selection changed")
 _sync_pattern_lengths()
 _library_entry={}
 _commit_parameter_edit()
 _refresh_inspector();_refresh_effects();piano.queue_redraw();steps.queue_redraw();canvas.queue_redraw()
static func resolve_document(value:Variant)->Dictionary:
 var document:KiwiAudioDocument
 var composition_path:String=str(value) if value is String else (value.resource_path if value is KiwiAudioDocument else "")
 var missing:=PackedStringArray();var warnings:=PackedStringArray()
 if value is KiwiAudioDocument:document=value
 elif value is String and str(value).get_extension().to_lower() in ["tres","res"]:
  if not FileAccess.file_exists(str(value)):return {"error":"The audio composition file is missing."}
  document=ResourceLoader.load(value,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiAudioDocument
 else:document=KiwiAudioDocument.from_source(value,str(value).get_file() if value is String else "Untitled Audio")
 if document==null:return {"error":"This file is not a valid audio composition."}
 if not document.portable_media.is_empty():
  if value is KiwiAudioDocument:
   var frozen:=KiwiAudioDocument.PortableCopy.freeze(document)
   if not str(frozen.get("error","")).is_empty():return frozen
   document=frozen.document
  var portable:=KiwiAudioDocument.PortableCopy.resolve(document,composition_path,value is KiwiAudioDocument)
  if not str(portable.get("error","")).is_empty():return portable
  missing=portable.get("missing_assets",PackedStringArray());warnings=portable.get("warnings",PackedStringArray())
 var errors:=document.validate()
 if not errors.is_empty():return {"error":"Could not open composition: "+"; ".join(errors)}
 return {"error":"","document":document,"missing_assets":missing,"warnings":warnings}

func open_source(value:Variant,state:Dictionary={})->void:
 # Validate before replacing the session or adopting a save destination.
 # An invalid resource must never become a blank composition over that path.
 var document:KiwiAudioDocument
 var missing:=PackedStringArray();var warnings:=PackedStringArray()
 if not state.get("session") is KiwiAudioEditSession:
  var resolved:=resolve_document(value)
  if not str(resolved.get("error","")).is_empty():notice(str(resolved.error));return
  document=resolved.document;missing=resolved.get("missing_assets",PackedStringArray());warnings=resolved.get("warnings",PackedStringArray())
 _close_silence_review();_close_recovery_review();_close_portable_review()
 _finish_control_edits();_controls_generation+=1
 _finish_automation_pass("Composition changed")
 canvas.finish_automation_edit()
 for child in get_children():
  if child is Window and (child.has_meta("audio_lane_window") or child.has_meta("audio_conductor_window") or child.has_meta("audio_relink_window")):child.queue_free()
 stop();jobs.cancel_all();_optional_tools.cancel();_generation+=1;source=value
 if state.get("session") is KiwiAudioEditSession:
  session.changed.disconnect(_session_changed);session.selection_changed.disconnect(_selection_changed)
  session=state.session;session.changed.connect(_session_changed);session.selection_changed.connect(_selection_changed)
  canvas.session=session;piano.session=session;steps.session=session
 else:
  session.changed.disconnect(_session_changed);session.selection_changed.disconnect(_selection_changed)
  session=KiwiAudioEditSession.new();session.changed.connect(_session_changed);session.selection_changed.connect(_selection_changed)
  canvas.session=session;piano.session=session;steps.session=session
  session.open(document)
 automation_recording.bind(session,playback)
 path=str(state.get("path",str(value) if value is String else ""));document_path=str(state.get("document_path",path if path.get_extension() in ["tres","res"] else ""))
 var ui:Dictionary=state.get("ui",session.document.workspace_state)
 canvas.zoom=float(ui.get("zoom",100));canvas.scroll_time=float(ui.get("scroll_time",0));canvas.track_scroll=float(ui.get("track_scroll",0));canvas.snap=bool(ui.get("snap",true))
 main_split.split_offset=int(ui.get("main_split",220));right_split.split_offset=int(ui.get("right_split",800));vertical_split.split_offset=int(ui.get("vertical_split",340));bottom.visible=bool(ui.get("bottom_open",false)) if int(ui.get("layout_version",0))>=2 else false;bottom.current_tab=clampi(int(ui.get("bottom_tab",0)),0,bottom.get_tab_count()-1)
 _layout.inspector_view=str(ui.get("inspector_view",""));_layout.folds=ui.get("inspector_folds",{}).duplicate();_layout.automation_panel.visible=bool(ui.get("automation_open",false));library.visible=bool(ui.get("library_open",true));_layout.inspector_scroll.visible=bool(ui.get("inspector_open",true))
 playback.loop_enabled=session.document.loop_enabled;playback.position=float(ui.get("playhead",0));_wave_clip_id="";_library_entry={};_analysis_result={}
 waveform.open(null);waveform.selection=Vector2i.ZERO
 _restore_pattern_view(piano,ui.get("piano",{}));_restore_pattern_view(steps,ui.get("steps",{}))
 var wave:Dictionary=ui.get("wave",{});var wave_id:=str(wave.get("clip_id",""));var actor:=session.document.actor_for_clip(wave_id)
 if actor!=null:
  _wave_clip_id=wave_id;waveform.open(_workspace_source(actor.values.get(&"audio")),float(wave.get("view_start",0)),float(wave.get("view_duration",5)))
  waveform.selection=wave.get("selection",Vector2i.ZERO);waveform.channel=int(wave.get("channel",-1));waveform.zero_crossing=bool(wave.get("zero_crossing",true))
 _refresh_all()
 if not missing.is_empty():notice("This collected composition opened with %d missing media file(s). Clip edits are intact. Restore its complete media folder or use Relink Source.\n%s\n%s"%[missing.size(),"\n".join(missing),"\n".join(warnings)])
 elif not warnings.is_empty():notice("\n".join(warnings))
func capture_state()->Dictionary:
 _finish_control_edits()
 _finish_automation_pass("Composition saved or switched")
 if session._before!=null:session.commit()
 var ui:Dictionary={"zoom":canvas.zoom,"scroll_time":canvas.scroll_time,"track_scroll":canvas.track_scroll,"snap":canvas.snap,"main_split":main_split.split_offset,"right_split":right_split.split_offset,"vertical_split":vertical_split.split_offset,"bottom_open":bottom.visible,"bottom_tab":bottom.current_tab,"playhead":playback.position,"selected_ids":session.selected_ids,"selected_track":session.selected_track}
 ui.layout_version=2;ui.inspector_view=_layout.inspector_view;ui.inspector_folds=_layout.folds.duplicate();ui.automation_open=_layout.automation_panel.visible;ui.library_open=library.visible;ui.inspector_open=_layout.inspector_scroll.visible
 ui.piano=_capture_pattern_view(piano);ui.steps=_capture_pattern_view(steps)
 ui.wave={"clip_id":_wave_clip_id,"view_start":waveform.view_start,"view_duration":waveform.view_duration,"selection":waveform.selection,"channel":waveform.channel,"zero_crossing":waveform.zero_crossing}
 session.document.workspace_state=ui
 _queue_recovery_checkpoint(false) # Tab capture has already finished edits above.
 return {"session":session,"source":source,"path":path,"document_path":document_path,"ui":ui}
func _notification(what:int)->void:
 if what==NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and not is_visible_in_tree():
  _close_silence_review();_close_recovery_review();_close_portable_review()
  _relink_generation+=1;jobs.cancel_kind("relink_probe")
  for child in get_children():
   if child is Window and child.has_meta("audio_relink_window"):child.queue_free()
  stop()
func toggle_playback()->void:
 if _record_busy:_cancel_record_preparation();return
 if recorder.recording:toggle_recording();return
 if playback.playing or playback.exact_pending or _transport_requested:
  _cancel_exact_playback();playback.stop(false);return
 playback.exact_required=_requires_exact_preview()
 if playback.exact_required:render_preview();return
 playback.play()

func stop()->void:
 if not _silence_review.is_empty():_stop_silence_audition(int(_silence_review.token))
 _finish_automation_pass("Transport stopped")
 _record_cancel_requested=true
 _record_loop_preview=null;_record_loop_signature=""
 if _record_busy:_cancel_record_preparation()
 _cancel_exact_playback()
 playback.stop();preview_player.stop();preview_player.stream=null;asset_file_preview.close_file()
 if recorder.recording and not _record_busy:toggle_recording()
func notice(message:String)->void:
 status.text=message
 for child in get_children():
  if child is AcceptDialog and child.has_meta("audio_notice") and not child.is_queued_for_deletion():
   child.dialog_text=message;child.popup_centered(Vector2i(520,160));return
 var dialog:=AcceptDialog.new();dialog.title="Audio Workspace";dialog.dialog_text=message;add_child(dialog);dialog.popup_centered(Vector2i(520,160));dialog.confirmed.connect(dialog.queue_free);dialog.canceled.connect(dialog.queue_free)
 dialog.set_meta("audio_notice",true)
func _refresh_inspector()->void:
 _clear(inspector)
 if not _library_entry.is_empty():_generator_inspector();return
 var actor:=session.primary_actor();var clip:=session.primary_clip()
 var track:=session.document.track_for_id(session.selected_track)
 if actor==null and KiwiAudioAutomationLane.is_lane(track):_automation_lane_inspector(track);return
 if bool(track.get("locked",false)):
  if track.has("frozen_track") or track.has("frozen_source"):
   _heading(inspector,"Frozen track");_label(inspector,"The source notes and processing remain recoverable. Unfreeze to edit them.");_button(inspector,"Unfreeze track",unfreeze_track)
  else:
   _heading(inspector,"Track locked");_label(inspector,"Unlock this track to edit its clips and instrument data.");_button(inspector,"Unlock",func():session.action("Unlock track",func():track.locked=false))
  return
 if actor!=null and clip!=null:
  _heading(inspector,"Clip · "+actor.display_name)
  var name_input:=LineEdit.new();name_input.text=actor.display_name;inspector.add_child(name_input);name_input.text_submitted.connect(func(value:String):session.action("Rename clip",func():actor.display_name=value))
  _number(inspector,"Start (s)",clip.start_time,0,86400,0.00001,func(value:float):_edit("Move clips",func():session.move_selected(value-clip.start_time)))
  _number(inspector,"Duration (s)",clip.duration,0.00001,86400,0.00001,func(value:float):_edit("Trim clip",func():session.edit_clip(clip.id,{"duration":value})))
  _number(inspector,"Source offset",clip.source_offset,0,86400,0.00001,func(value:float):_edit("Slip clip",func():session.edit_clip(clip.id,{"source_offset":value})))
  _number(inspector,"Gain (dB)",float(actor.values.get(&"volume_db",0)),-60,24,0.1,func(value:float):_edit("Clip gain",func():session.set_clip_value(&"volume_db",value)))
  _number(inspector,"Pan",float(actor.values.get(&"pan",0)),-1,1,0.01,func(value:float):_edit("Clip pan",func():session.set_clip_value(&"pan",value)))
  _number(inspector,"Speed",clip.playback_speed,0.05,16,0.01,func(value:float):_edit("Stretch clip",func():session.edit_clip(clip.id,{"playback_speed":value,"duration":clip.duration*clip.playback_speed/value})))
  _number(inspector,"Pitch (semi)",12*log(maxf(0.01,float(actor.values.get(&"pitch",1))))/log(2.0),-36,36,0.1,func(value:float):_edit("Clip pitch",func():session.set_clip_value(&"pitch",pow(2.0,value/12))))
  for key in ["fade_in","fade_out"]:
   _number(inspector,key.capitalize()+" (s)",float(actor.values.get(StringName(key),0)),0,clip.duration,0.001,func(value:float):_edit("Clip fade",func():session.set_clip_value(StringName(key),value)))
  _check(inspector,"Loop source",bool(actor.values.get(&"loop",false)),func(value:bool):session.set_clip_value(&"loop",value))
  _check(inspector,"Reverse (rendered)",bool(actor.values.get(&"reverse",false)),func(value:bool):session.set_clip_value(&"reverse",value))
  _button(inspector,"Open waveform",edit_clip.bind(clip.id))
  _button(inspector,"Analyze / smart edits",analyze_clip)
  var stream:=_workspace_source(actor.values.get(&"audio"))
  if stream==null:
   if ActorAudio.needs_file_preview(actor.values.get(&"audio")):_label(inspector,"File-backed source: timeline playback prepares a streaming rendered preview. Whole-resource waveform/analysis edits require a shorter source or rendered selection; the original file is preserved.")
   else:_label(inspector,"Source missing. Relink to an existing project audio asset.");_button(inspector,"Relink source",relink_source)
  if not (actor.values.get(&"notes",[]) as Array).is_empty() or str(track.get("kind",""))=="instrument":_instrument_inspector(actor,track)
 if not track.is_empty():
  _heading(inspector,"Track · "+str(track.name))
  var track_name:=LineEdit.new();track_name.text=str(track.name);inspector.add_child(track_name);track_name.text_submitted.connect(func(value:String):session.action("Rename track",func():track.name=value))
  var color:=ColorPickerButton.new();color.color=track.get("color",Color("63d9bc"));color.custom_minimum_size.y=24;color.tooltip_text="Track color";inspector.add_child(color);var color_session:=session;var color_document:=session.document
  color.color_changed.connect(func(value:Color):
   if not _mixer_context_current(color,color_session,color_document):return
   var previous:=_edit_control_id;_edit_control_id=color.get_instance_id()
   _edit("Track color",func():track.color=value);_edit_control_id=previous)
  _number(inspector,"Volume (dB)",float(track.get("volume_db",0)),-60,12,0.1,func(value:float):_edit("Track volume",func():track.volume_db=value))
  _number(inspector,"Pan",float(track.get("pan",0)),-1,1,0.01,func(value:float):_edit("Track pan",func():track.pan=value))
  var destinations:Array=["Master"];var ids:Array=[""]
  for other in session.document.tracks:
   if str(other.id)!=str(track.id) and not KiwiAudioAutomationLane.is_lane(other):destinations.append(str(other.name));ids.append(str(other.id))
  var current:=ids.find(str(track.get("output","")))
  _choice(inspector,"Output",destinations,str(destinations[maxi(0,current)]),func(value:String):session.action("Route track",func():if not session.set_track_value(track.id,"output",ids[destinations.find(value)]):notice("That routing would create a feedback loop.")))
  _button(inspector,"Add send…",send_dialog)
  _button(inspector,"Add automation point…",automation_dialog)
  _button(inspector,"Track takes…",take_dialog)
  _button(inspector,"Freeze track",freeze_track);_button(inspector,"Bounce track",bounce_track)
  _button(inspector,"Delete track",func():session.delete_track(str(track.id)))
 _heading(inspector,"Project")
 var keys:Array=["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
 _choice(inspector,"Key",keys,keys[posmod(session.document.key,12)],func(value:String):session.action("Change key",func():session.document.key=keys.find(value)))
 _choice(inspector,"Scale",KiwiAudioComposer.scales().keys(),session.document.scale,func(value:String):session.action("Change scale",func():session.document.scale=value))
 _number(inspector,"Loop start",session.document.loop_start,0,86400,0.001,func(value:float):_edit("Loop range",func():session.document.loop_start=value))
 _number(inspector,"Loop end",session.document.loop_end,0.001,86400,0.001,func(value:float):_edit("Loop range",func():session.document.loop_end=value))
 _layout.organize_inspector()
func _instrument_inspector(actor:ActorData,track:Dictionary)->void:
 _heading(inspector,"Instrument")
 if actor.values.has(&"midi_tempos"):_label(inspector,"MIDI source tempo map active. Conductor edits preserve this source timing. Uniform retime explicitly scales it; the timeline grid and metronome use the project conductor.")
 elif actor.values.has(&"midi_events"):_label(inspector,"This older MIDI source uses the saved source BPM. Reimport the original MIDI to restore its source tempo-map playback.")
 if not actor.values.has(&"midi_tempos"):_label(inspector,"Source timing: %.2f BPM. Conductor edits leave these source-relative note beats unchanged."%KiwiAudioEditSession.note_source_tempo(actor,session.document))
 if actor.values.has(&"midi_events"):
  var sustain_toggle:=_check(inspector,"Render MIDI sustain pedal (CC64)",bool(actor.values.get(&"midi_sustain",false)),func(value:bool):
   if bool(track.get("locked",false)) or track.has("frozen_track"):return
   session.action("MIDI sustain rendering",func():actor.values[&"midi_sustain"]=value;actor.values[&"notes_dirty"]=true);_render_dirty_notes())
  sustain_toggle.disabled=bool(track.get("locked",false)) or track.has("frozen_track")
  _label(inspector,"Optional CC64 sustain extends rendered note gates until pedal-up or the source pattern end. Same-beat controller state is applied before note-off. Source notes and MIDI export stay unchanged; one-shot/drum or monophonic patches may ignore/restrict long gates. Half-pedaling and other MIDI controllers are not performed.")
 var patch:Dictionary=actor.values.get(&"instrument",track.get("instrument",{"id":"poly"}))
 if patch.size()<3:patch=KiwiAudioInstruments.default_instrument(str(patch.get("id","poly")))
 var ids:Array=[];var labels:Array=[]
 for preset in KiwiAudioInstruments.presets():ids.append(preset.id);labels.append(preset.label)
 var index:=ids.find(str(patch.id))
 _choice(inspector,"Patch",labels,str(labels[maxi(0,index)]),func(value:String):session.action("Change instrument",func():actor.values[&"instrument"]=KiwiAudioInstruments.default_instrument(str(ids[labels.find(value)]));actor.values[&"notes_dirty"]=true);_render_dirty_notes())
 for info in [["attack",0.0005,10,0.001],["decay",0.001,10,0.01],["sustain",0,1,0.01],["release",0.003,10,0.01],["filter",20,20000,1],["resonance",0,0.95,0.01],["detune",0,40,0.1],["modulation",0,8,0.01],["vibrato",0,1,0.01],["width",0,1,0.01]]:
  var key:=str(info[0]);_number(inspector,key.capitalize(),float(patch.get(key,0)),info[1],info[2],info[3],func(value:float):_edit("Instrument settings",func():patch[key]=value;actor.values[&"instrument"]=patch;actor.values[&"notes_dirty"]=true);_preview_timer.stop())
 _button(inspector,"Render instrument changes",_render_dirty_notes);_button(inspector,"Instrument modulation",modulator_dialog.bind(false))
 if str(patch.get("kind","")) in ["sampler","multisample"]:
  _button(inspector,"Choose sample",choose_instrument_sample)
  _number(inspector,"Root MIDI note",float(patch.get("root_pitch",60)),0,127,1,func(value:float):_edit("Sampler root",func():patch.root_pitch=int(value);actor.values[&"instrument"]=patch;actor.values[&"notes_dirty"]=true))
  _check(inspector,"Loop sample",bool(patch.get("loop",false)),func(value:bool):session.action("Sample looping",func():patch.loop=value;actor.values[&"instrument"]=patch;actor.values[&"notes_dirty"]=true))
  for field in ["loop_start","loop_end"]:
   var key:=str(field);_number(inspector,key,float(patch.get(key,0 if key=="loop_start" else -1)),-1,300,0.001,func(value:float):_edit("Sample loop points",func():patch[key]=value;actor.values[&"instrument"]=patch;actor.values[&"notes_dirty"]=true))
  _label(inspector,"Loop end −1 uses the sample end. Sampler presets preserve their sample reference and stereo channels.")
  if str(patch.get("kind",""))=="multisample":_button(inspector,"Edit sample map",sample_map_dialog)
 _button(inspector,"Save instrument preset",save_preset.bind("instrument"))
 var note:Dictionary={}
 for candidate in actor.values.get(&"notes",[]):
  if piano.selected.has(str(candidate.id)) or steps.selected.has(str(candidate.id)):note=candidate;break
 if not note.is_empty():
  _heading(inspector,"Selected Note")
  for info in [["velocity",0.01,1,0.01],["probability",0,1,0.01],["ratchets",1,8,1],["pan",-1,1,0.01]]:
   var key:=str(info[0]);_number(inspector,key.capitalize(),float(note.get(key,1)),info[1],info[2],info[3],func(value:float):_edit("Edit note",func():note[key]=value;actor.values[&"notes_dirty"]=true))
  _check(inspector,"Accent",bool(note.get("accent",false)),func(value:bool):session.action("Note accent",func():note.accent=value;actor.values[&"notes_dirty"]=true))
  _check(inspector,"Mute note",bool(note.get("mute",false)),func(value:bool):session.action("Mute note",func():note.mute=value;actor.values[&"notes_dirty"]=true))
func _effect_owner()->Dictionary:
 var actor:=session.primary_actor()
 if actor!=null:return actor.values
 var track:=session.document.track_for_id(session.selected_track)
 return track if not track.is_empty() else session.document.master
func _effect_editable()->bool:
 var track:=session.document.track_for_clip(session.primary_clip().id) if session.primary_clip()!=null else session.document.track_for_id(session.selected_track)
 return not bool(track.get("locked",false)) and not (session.primary_actor()==null and KiwiAudioAutomationLane.is_lane(track))
func _refresh_effects()->void:
 _clear(effects_panel)
 if session.primary_actor()==null and KiwiAudioAutomationLane.is_lane(session.document.track_for_id(session.selected_track)):
  _label(effects_panel,"This lane edits a linked parameter. Open its curve, or select the source track/clip to change the effect stack.")
  _button(effects_panel,"Edit lane curve",automation_lane_editor.bind(session.selected_track));return
 if not _effect_editable():
  _label(effects_panel,"This track is locked. Unlock or unfreeze it before changing its processing.")
  _button(effects_panel,"Render exact preview",render_preview)
  return
 var owner:=_effect_owner();var stack:Array=owner.get("effects",owner.get(&"effects",[]))
 var row:=HFlowContainer.new();effects_panel.add_child(row)
 _button(row,"+ Effect",add_effect_dialog);_button(row,"Chain preset",effect_chain_dialog);_button(row,"Copy",func():session.copy_effects(stack));_button(row,"Paste",func():session.action("Paste effects",func():owner["effects"]=session.pasted_effects()))
 _button(row,"A/B bypass",_toggle_effect_bypass)
 _button(row,"Render exact preview",render_preview);_button(row,"Bake selection",render_in_place);_button(row,"Save chain",save_preset.bind("effects"));_button(row,"Apply to selected clips",batch_effects)
 _label(effects_panel,"Native effects preview live. Offline processors, reverse and restoration use Render exact preview; export always uses the offline render chain. Native and offline room/pitch/dynamics algorithms can sound different.")
 for index in stack.size():
  var effect:Dictionary=stack[index];var definition:=KiwiAudioEffects.definition(str(effect.type))
  var card:=VBoxContainer.new();effects_panel.add_child(card)
  var heading:=HFlowContainer.new();card.add_child(heading)
  _check(heading,str(definition.get("label",effect.type)),bool(effect.get("enabled",true)),func(value:bool):session.action("Effect bypass",func():effect.enabled=value))
  _label(heading,"LIVE" if bool(definition.get("realtime",false)) else "OFFLINE")
  if not KiwiAudioEffects.automation_commands(str(effect.type)).is_empty():_button(heading,"Automation",effect_automation_dialog.bind(index))
  _button(heading,"↑",func():if index>0:session.action("Reorder effect",func():stack.remove_at(index);stack.insert(index-1,effect)))
  _button(heading,"↓",func():if index<stack.size()-1:session.action("Reorder effect",func():stack.remove_at(index);stack.insert(index+1,effect)))
  _button(heading,"×",func():session.action("Remove effect",func():stack.erase(effect)))
  if str(effect.type)=="noise_reduce" and effect.parameters.has("noise_profile"):
   _label(card,"Learned 15-band noise profile");_button(card,"Clear learned profile",func():session.action("Clear noise profile",func():effect.parameters.erase("noise_profile")))
  if str(effect.type)=="convolution":
   _button(card,"Choose impulse response…",choose_effect_impulse.bind(effect));_label(card,str(effect.parameters.get("impulse","No impulse selected")))
  var fields:=HFlowContainer.new();card.add_child(fields)
  for info in definition.get("parameters",[]):
   var key:=str(info.id);_number(fields,str(info.label),float(effect.parameters.get(key,info.default)),info.min,info.max,float(info.get("step",0.01)),func(value:float):_edit("Effect parameter",func():effect.parameters[key]=value))
func batch_effects()->void:
 if session.selected_ids.is_empty():return
 var effects:Array=_effect_owner().get("effects",[]).duplicate(true)
 session.action("Apply effect chain to selected clips",func():
  for id in session.selected_ids:
   if not session.can_edit(id):continue
   var copied:=effects.duplicate(true)
   for effect in copied:effect.id=ActorData.new_id()
   session.document.actor_for_clip(id).values[&"effects"]=copied)
func choose_effect_impulse(effect:Dictionary)->void:
 var target_session:=session;var target_revision:=session.revision
 var chosen:=await ActorProjectFilePicker.pick(self,_audio_property(),"Choose convolution impulse response")
 if chosen.is_empty() or chosen==ActorProjectFilePicker.EMPTY_RESOURCE:return
 if session!=target_session or session.revision!=target_revision:notice("The composition changed while choosing the impulse. Choose it again.");return
 session.action("Choose convolution impulse",func():effect.parameters.impulse=chosen)
 _refresh_effects()
func add_effect_dialog()->void:
 if not _effect_editable():return
 var dialog:=_window("Add effect",Vector2i(620,520));var host:VBoxContainer=dialog.host
 var search:=LineEdit.new();search.placeholder_text="Search effects…";host.add_child(search)
 var scroller:=ScrollContainer.new();scroller.size_flags_vertical=Control.SIZE_EXPAND_FILL;host.add_child(scroller)
 var choices:=VBoxContainer.new();choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroller.add_child(choices)
 var rebuild:=func():
  _clear(choices)
  for definition in library.ranked_effects():
   if not search.text.is_empty() and not (str(definition.label)+" "+str(definition.category)).to_lower().contains(search.text.to_lower()):continue
   _button(choices,str(definition.label)+" · "+str(definition.category)+( "  [live]" if definition.realtime else "  [offline]"),func():
    if not _effect_editable():return
    library.remember_effect(str(definition.id))
    var owner:=_effect_owner();session.action("Add effect",func():var stack:Array=owner.get("effects",[]);stack.append(KiwiAudioEffects.create(str(definition.id)));owner["effects"]=stack)
    dialog.window.queue_free())
 search.text_changed.connect(func(_value:String):rebuild.call());rebuild.call()
func effect_chain_dialog()->void:
 if not _effect_editable():return
 var dialog:=_window("Effect chain",Vector2i(400,430))
 for name in KiwiAudioTemplates.chain_names():_button(dialog.host,name,func():var owner:=_effect_owner();session.action("Apply effect chain",func():owner["effects"]=KiwiAudioTemplates.chain(name));dialog.window.queue_free())
func _refresh_mixer()->void:
 var focused:=get_viewport().gui_get_focus_owner();var focus_id:=str(focused.get_meta("audio_mixer_id","")) if focused!=null else ""
 _clear(mixer_panel);_mixer_gestures.clear();_meter_controls.clear();_automation_mixer_controls.clear()
 var entries:Array=session.document.tracks.filter(func(track:Dictionary):return not KiwiAudioAutomationLane.is_lane(track) or not KiwiAudioAutomationLane.binding_error(session.document,str(track.id)).is_empty());entries.append(session.document.master)
 for index in entries.size():
  var track:Dictionary=entries[index];var master:=index==entries.size()-1;var strip:=VBoxContainer.new();strip.custom_minimum_size.x=100;mixer_panel.add_child(strip)
  var locked:=not master and bool(track.get("locked",false))
  var target:Dictionary={"owner_kind":"master" if master else "track","owner_id":"" if master else str(track.id),"effect_id":"","parameter":"volume_db"}
  _heading(strip,"MASTER" if master else str(track.get("name","Track")))
  var meter:=ProgressBar.new();meter.min_value=-60;meter.max_value=0;meter.show_percentage=false;meter.custom_minimum_size=Vector2(90,10);strip.add_child(meter);_meter_controls["" if master else str(track.id)]=meter
  var slider:=VSlider.new();slider.min_value=-60;slider.max_value=12;slider.step=0.1;slider.value=float(track.get("volume_db",0));slider.editable=not locked;slider.custom_minimum_size=Vector2(40,100);slider.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;strip.add_child(slider)
  var mixer_id:="master" if master else str(track.id);slider.set_meta("audio_mixer_id",mixer_id)
  slider.tooltip_text="Choose Automate, then Write/Touch/Latch to record this gain. Read follows the existing curve during playback."
  _bind_mixer_slider(slider,target,track)
  _automation_mixer_controls.append({"control":slider,"target":target})
  if focus_id==mixer_id:slider.grab_focus()
  var gain:=_number(strip,"dB",float(track.get("volume_db",0)),-60,12,0.1,func(value:float):
   if _automation_consumes(target):_automation_control_changed(value)
   elif _mixer_target_editable(target):_edit("Mix volume",func():track.volume_db=value))
  gain.editable=not locked;_automation_mixer_controls.append({"control":gain,"target":target})
  _button(strip,"Automate gain",func():_choose_automation_record_target(target)).disabled=locked
  if not master:
   var pan_target:=target.duplicate(true);pan_target.parameter="pan"
   var pan:=_number(strip,"Pan",float(track.get("pan",0)),-1,1,0.01,func(value:float):
    if _automation_consumes(pan_target):_automation_control_changed(value)
    elif _mixer_target_editable(pan_target):_edit("Mix pan",func():track.pan=value))
   pan.editable=not locked;_automation_mixer_controls.append({"control":pan,"target":pan_target})
   _button(strip,"Automate pan",func():_choose_automation_record_target(pan_target)).disabled=locked
   _check(strip,"Mute",bool(track.get("mute",false)),func(value:bool):_finish_automation_pass("Mixer mute changed");session.action("Mute track",func():track.mute=value)).disabled=locked
   _check(strip,"Solo",bool(track.get("solo",false)),func(value:bool):_finish_automation_pass("Mixer solo changed");session.action("Solo track",func():track.solo=value)).disabled=locked
  _button(strip,"Effects",func():_finish_automation_pass("Effects selected");session.selected_ids.clear();session.selected_track="" if master else str(track.id);bottom.current_tab=3;_refresh_effects())
func _process(delta:float)->void:
 if not _portable_context.is_empty() and not _portable_current(int(_portable_context.token)):_close_portable_review()
 _recovery_tick()
 if not _silence_review.is_empty() and Time.get_ticks_msec()>=_silence_check_at:
  _silence_check_at=Time.get_ticks_msec()+250
  if not _silence_review_current(int(_silence_review.token)):_close_silence_review()
 if not is_visible_in_tree():return
 _layout.sync()
 automation_recording.tick(playback.position,playback.playing)
 _update_automation_readouts()
 for id in _meter_controls:
  var supported:=playback.meter_supported(str(id));var levels:=playback.meter(str(id));_meter_controls[id].value=maxf(levels.x,levels.y)
  _meter_controls[id].modulate=Color.WHITE if supported else Color(1,1,1,.3)
  _meter_controls[id].tooltip_text=("Rendered post-fader route peak · 20 Hz (dBFS)" if playback.exact_preview_active else "Native route peak (dBFS)") if supported else "Route meter unavailable for this render. Meter preparation supports up to 32 routes and 10 minutes; master remains live."
 if recorder.recording:
  if not recorder.capture_error().is_empty() and not _record_busy:
   _record_failure=recorder.capture_error();_finish_recorded_take(false);return
  _record_elapsed+=delta
  var recording_label:="Recording dry overdub" if recorder.monitor_timeline and not recorder.record_timeline else "Recording take"
  status.text=recording_label+(" · streamed backing" if _record_processed_capture else "")+" · %.1f s"%_record_elapsed
  # Let direct or prepared backing own its transport clock while playing.
  # A longer microphone take continues advancing after the backing has ended.
  if not playback.playing:playback.position=_record_start+_record_elapsed;canvas.playhead=playback.position;canvas.queue_redraw()
  if _record_loop and _record_cycle_duration>0 and not _record_busy:
   # A prepared pass ends when buffered audio drains, not on the UI clock.
   if (not playback.playing) if _record_processed_capture else (_record_elapsed>=_record_cycle_duration):toggle_recording(true)
func _window(title:String,dimensions:Vector2i=Vector2i(520,400))->Dictionary:
 var window:=Window.new();window.title=title;window.size=dimensions;window.min_size=Vector2i(360,180);add_child(window)
 var margin:=MarginContainer.new();margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,12)
 window.add_child(margin);var host:=VBoxContainer.new();host.add_theme_constant_override("separation",8);margin.add_child(host)
 window.close_requested.connect(window.queue_free);window.popup_centered();return {"window":window,"host":host}
func _name_dialog(title:String,suggested:String,callback:Callable,allow_empty:bool=false)->void:
 var dialog:=_window(title,Vector2i(430,150));var edit:=LineEdit.new();edit.text=suggested;dialog.host.add_child(edit)
 _button(dialog.host,"Save",func():if allow_empty or not edit.text.strip_edges().is_empty():callback.call(edit.text.strip_edges());dialog.window.queue_free())
 edit.grab_focus();edit.select_all()
func _library_selected(entry:Dictionary)->void:
 _library_entry=entry.duplicate(true)
 if str(entry.get("kind",""))=="generator":
  _generator_settings=entry.get("settings",KiwiAudioSynthesis.default_settings(str(entry.id))).duplicate(true);_generate_preview()
 _refresh_inspector()
func _generator_inspector()->void:
 var entry:=_library_entry;var kind:=str(entry.get("kind",""))
 _heading(inspector,str(entry.get("label","Library")))
 _label(inspector,str(entry.get("description",entry.get("category",""))))
 if kind=="generator":
  var actions:=HFlowContainer.new();inspector.add_child(actions)
  _button(actions,"▶ Preview",_generate_preview);_button(actions,"+ Add to timeline",_add_preview)
  if str(entry.id)=="sample_grains":_button(inspector,"Choose grain source…",choose_generator_sample)
  var settings:=_layout.fold(inspector,"sound_settings","Customize sound")
  for info in entry.get("parameters",[]):
   var key:=str(info.id)
   _number(settings,str(info.label),float(_generator_settings.get(key,info.get("default",0))),float(info.get("min",0)),float(info.get("max",1)),float(info.get("step",0.01)),func(value:float):_generator_settings[key]=value;_preview_timer.start())
  _button(settings,"Modulation…",modulator_dialog.bind(true))
  _number(settings,"Random seed",_generator_seed,0,2147483647,1,func(value:float):_generator_seed=int(value);_preview_timer.start())
  var variation_actions:=HFlowContainer.new();inspector.add_child(variation_actions)
  _button(variation_actions,"New variation",func():_generator_seed+=1;_generate_preview());_button(variation_actions,"Randomize",func():_generator_seed=randi()%2147483647;_generate_preview())
  _layout.menu(variation_actions,"Save",[["Save sound preset…",save_preset.bind("generator")],["Save audio file…",save_preview_audio]])
  if not _variations.is_empty():
   var variations:=_layout.fold(inspector,"sound_variations","Compare recent variations")
   for i in _variations.size():
    var variation:Dictionary=_variations[i]
    _button(variations,"▶ Variation %d · %.2fs"%[i+1,(variation.stream as AudioStreamWAV).get_length()],_select_variation.bind(variation))
 elif kind=="instrument":
  _button(inspector,"Audition C4",func():audition_note(60,KiwiAudioInstruments.default_instrument(str(entry.id))))
  _button(inspector,"Create instrument track",_library_add.bind(entry))
 elif kind=="template":_button(inspector,"Create from template",_library_add.bind(entry))
 elif kind=="asset":_button(inspector,"Preview",_library_preview.bind(entry));_button(inspector,"Add to timeline",_library_add.bind(entry))
 elif kind=="preset":
  var tags:=KiwiAudioLibrary.preset_tags(entry.preset)
  _label(inspector,"Tags: "+(", ".join(tags) if not tags.is_empty() else "Untagged"))
  _button(inspector,"Edit preset tags",_edit_preset_tags.bind(entry))
  _button(inspector,"Audition preset",_library_preview.bind(entry))
  _button(inspector,"Export native preset…",export_native_preset.bind(entry.preset))
  _button(inspector,"Apply editable preset",_library_add.bind(entry))
  var digest:=FileAccess.get_sha256(str(entry.path))
  _button(inspector,"Organize in folder…",func():_name_dialog("Preset folder (searchable, slash-separated)",str(entry.preset.folder),func(folder:String):
   var problem:=preload("res://Workspaces/AudioWorkspace/audio_preset_store.gd").rename(str(entry.path),digest,str(entry.label),folder)
   if not problem.is_empty():notice(problem)
   else:library.reload(),true))
  _button(inspector,"Rename preset",func():_name_dialog("Rename preset",str(entry.label),func(label:String):
   var problem:=preload("res://Workspaces/AudioWorkspace/audio_preset_store.gd").rename(str(entry.path),digest,label)
   if not problem.is_empty():notice(problem)
   else:library.reload()))
  _button(inspector,"Duplicate preset",func():var preset:KiwiAudioPreset=(entry.preset as KiwiAudioPreset).duplicate(true);preset.id=ActorData.new_id();preset.label+=" copy";_persist_preset(preset))
  _button(inspector,"Move preset to recovery",func():
   var problem:=preload("res://Workspaces/AudioWorkspace/audio_preset_store.gd").remove(str(entry.path),digest)
   if not problem.is_empty():notice(problem);return
   library.reload();_library_entry={};_refresh_inspector())
 if kind=="preset":
  var options:=_layout.fold(inspector,"preset_options","Preset options")
  for child in inspector.get_children():
   if child is Button and child.text not in ["Audition preset","Apply editable preset"]:child.reparent(options)
func _edit_preset_tags(entry:Dictionary)->void:
 var location:=str(entry.get("path",""));var preset:KiwiAudioPreset=entry.get("preset")
 if preset==null or location.is_empty():notice("Choose a saved preset before editing tags.");return
 var digest:=FileAccess.get_sha256(location)
 if digest.is_empty():notice("The preset file is missing or unreadable. Refresh the library first.");return
 # Seed the editor from the same current disk version protected by the digest.
 var current:=ResourceLoader.load(location,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiAudioPreset
 if current==null or current.id!=preset.id or FileAccess.get_sha256(location)!=digest:notice("The preset changed or is unreadable. Refresh the library before editing tags.");return
 var owner:=session;var identity:=current.id
 _name_dialog("Preset tags (comma separated, up to 32)",", ".join(KiwiAudioLibrary.preset_tags(current)),func(text:String):
  if not is_inside_tree() or not is_visible_in_tree() or session!=owner:return
  var tags:=PackedStringArray();var seen:Dictionary={}
  for value in text.split(",",false):
   var tag:=value.strip_edges()
   if tag.is_empty():continue
   if tag.length()>128:notice("Each preset tag may contain at most 128 characters.");return
   var key:=tag.to_lower()
   if seen.has(key):continue
   if tags.size()>=32:notice("Use at most 32 distinct tags per preset.");return
   tags.append(tag);seen[key]=true
  var problem:=_save_preset_tags(location,digest,identity,tags)
  if not problem.is_empty():notice(problem);return
  library.reload();_library_entry=library.current.duplicate();_refresh_inspector()
  status.text="Saved preset tags. Use library search or the tag/type filters to find it.",true)

func _save_preset_tags(location:String,digest:String,identity:String,tags:PackedStringArray)->String:
 var root:=ProjectSettings.globalize_path("user://audio_workspace/presets").simplify_path()
 var absolute:=ProjectSettings.globalize_path(location).simplify_path()
 var access:=DirAccess.open(root)
 if access==null or absolute.get_base_dir()!=root or absolute.get_extension().to_lower()!="tres" or access.is_link(absolute.get_file()):return "Only native presets inside the library folder can be tagged."
 if digest.is_empty() or FileAccess.get_sha256(absolute)!=digest:return "The preset changed after the tag editor opened. Refresh and edit its current version."
 var original:=ResourceLoader.load(absolute,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiAudioPreset
 if original==null or original.id!=identity:return "The selected preset was replaced or is unreadable. Nothing was saved."
 # Shallow metadata copy: preserve the composition, embedded sources and all
 # unknown data. Native saving may serialize audio; do not mutate loaded assets.
 var copy:=original.duplicate(false) as KiwiAudioPreset
 if copy==null:return "Could not copy the preset metadata. Nothing was saved."
 copy.resource_path="";copy.tags=tags.duplicate()
 if copy.kind=="pattern" or copy.data.has("tags"):
  copy.data=copy.data.duplicate(false);copy.data["tags"]=Array(tags)
 var token:=ActorData.new_id()
 var temporary:=absolute.get_basename()+".tags-writing-"+token+".tres"
 var backup:=absolute+".tags-backup-"+token
 if FileAccess.file_exists(temporary) or FileAccess.file_exists(backup):return "Could not reserve a new preset save name. Try again."
 var error:=ResourceSaver.save(copy,temporary)
 if error!=OK:
  if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
  return "The preset tags could not be saved (%s). The original is intact."%error
 if access.is_link(absolute.get_file()) or FileAccess.get_sha256(absolute)!=digest:
  DirAccess.remove_absolute(temporary);return "The preset changed while saving. Its newer version was left intact."
 error=DirAccess.rename_absolute(absolute,backup)
 if error!=OK:
  DirAccess.remove_absolute(temporary);return "Could not preserve the previous preset. Tags were not changed."
 error=DirAccess.rename_absolute(temporary,absolute)
 if error!=OK:
  var restored:=DirAccess.rename_absolute(backup,absolute)
  if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
  return "Could not publish preset tags. "+("The previous preset was restored." if restored==OK else "The previous preset is retained at "+backup)
 return ""

func _library_preview(entry:Dictionary)->void:
 if bool(entry.get("project_indexed",false)) and not KiwiAudioLibrary.valid_entry(entry):status.text="Project asset is missing, unreadable, or outside the indexed scope. Refresh its folder.";return
 match str(entry.get("kind","")):
  "generator":_library_selected(entry)
  "instrument":audition_note(60,KiwiAudioInstruments.default_instrument(str(entry.id)))
  "asset":
   asset_file_preview.close_file();preview_player.stop()
   if ActorAudio.needs_file_preview(entry.source):
    if str(entry.source).get_extension().to_lower()=="wav":
     var error:=asset_file_preview.open_file(str(entry.source))
     if not error.is_empty():status.text=error
    else:status.text="Add this large/compressed source to the timeline to prepare a file-backed rendered preview."
    return
   var stream:=_workspace_source(entry.source)
   if stream!=null:preview_player.stream=stream;preview_player.play()
  "preset":
   var preset:KiwiAudioPreset=entry.preset
   if preset.kind=="generator":_library_entry=KiwiAudioSynthesis.preset(str(preset.data.get("id","laser")));_library_entry.kind="generator";_generator_settings=preset.data.get("settings",{}).duplicate(true);_generator_seed=int(preset.data.get("seed",1));_generate_preview();_refresh_inspector()
   else:_audition_native_preset(preset)
func _library_add(entry:Dictionary)->void:
 if not KiwiAudioLibrary.valid_entry(entry):status.text="Unsupported or invalid library entry.";return
 match str(entry.get("kind","")):
  "generator":
   if str(_library_entry.get("id",""))!=str(entry.id):_library_selected(entry);status.text="Generating the sound. Use Add to timeline when the preview is ready."
   else:_add_preview()
  "instrument":
   session.begin("Create instrument track");session.add_track("instrument",str(entry.label));var track:=session.document.track_for_id(session.selected_track);track.instrument=KiwiAudioInstruments.default_instrument(str(entry.id));new_pattern(false)
  "asset":
   if KiwiAudioAutomationLane.is_lane(session.document.track_for_id(session.selected_track)):notice("Select an audio or instrument track before adding this asset.");return
   session.insert_source(entry.source,playback.position,session.selected_track,str(entry.label))
  "template":
   var next:=KiwiAudioTemplates.create(str(entry.label));var tabs:=get_tree().get_first_node_in_group("actor_scene_tabs")
   if tabs!=null and tabs.has_method("open_audio"):tabs.call("open_audio",next)
   else:session.open(next);source=next;path="";document_path=""
  "preset":
   var preset:KiwiAudioPreset=entry.preset
   match preset.kind:
    "generator":
     var generator:=KiwiAudioSynthesis.preset(str(preset.data.get("id","")));generator.kind="generator"
     _queue_generator_drop(generator,preset.data.get("settings",{}),int(preset.data.get("seed",1)),playback.position,session.selected_track)
    "effects":
     if not _effect_editable():notice("Select an unlocked clip, audio track or master to apply effects.");return
     var owner:=_effect_owner();session.action("Apply effect preset",func():owner["effects"]=preset.data.get("effects",[]).duplicate(true))
    "instrument":
     if session.primary_actor()==null:
      var pattern:=KiwiAudioPreset.new();pattern.kind="pattern";pattern.label=preset.label;pattern.data={"notes":[],"instrument":preset.data.duplicate(true),"pattern_beats":4.0}
      var error:=KiwiAudioPreset.apply_pattern(session,pattern,playback.position,session.selected_track,true)
      if not error.is_empty():notice(error);return
     else:
      var actor:=session.primary_actor()
      if not session.can_edit(session.primary_clip().id):return
      session.action("Apply instrument preset",func():actor.values[&"instrument"]=preset.data.duplicate(true);actor.values[&"notes_dirty"]=true)
     _render_dirty_notes()
    "pattern":
     var error:=KiwiAudioPreset.apply_pattern(session,preset,playback.position,session.selected_track)
     if not error.is_empty():notice(error)
     else:_render_dirty_notes()
    "bundle":
     var problem:=preload("res://Workspaces/AudioWorkspace/audio_layer_bundle.gd").insert(session,preset.composition,playback.position)
     if not problem.is_empty():notice(problem)
     else:_render_dirty_notes()
    "composition":
     if preset.composition!=null:
      var timing_error:=preset.composition.midi_timing_error()
      if not timing_error.is_empty():notice(timing_error);return
      var tabs:=get_tree().get_first_node_in_group("actor_scene_tabs");if tabs!=null:tabs.call("open_audio",preset.composition.snapshot())
func _generate_preview()->void:
 if str(_library_entry.get("kind",""))!="generator":return
 var payload:=_generator_payload(_library_entry,_generator_settings,_generator_seed)
 _generation+=1
 if _preview_cache.has(payload.key):_set_preview(_preview_cache[payload.key],payload);return
 status.text="Generating "+str(payload.label)
 jobs.request("preview",func(job:RefCounted):
  job.update(0.1,"Generating sound")
  var stream:=KiwiAudioSynthesis.generate(str(payload.id),payload.settings,int(payload.seed),44100,job)
  return {"stream":stream,"cache_key":payload.key,"payload":payload},_generation)

func _set_preview(stream:AudioStreamWAV,payload:Dictionary={})->void:
 if stream==null:notice("The generator needs a valid source sample or its settings could not be rendered.");return
 _preview_payload=payload.duplicate(true);_preview_payload.stream=stream
 _preview_stream=stream;preview_player.stream=stream;preview_player.play()
 if not payload.is_empty():
  for previous in _variations.duplicate():
   if str(previous.get("key",""))==str(payload.get("key","")):_variations.erase(previous)
  _variations.push_front(_preview_payload.duplicate(true))
  if _variations.size()>5:_variations.resize(5)
 status.text="Preview ready · %.2f s · %d Hz"%[stream.get_length(),stream.mix_rate]
 _refresh_inspector()

func _add_preview()->void:
 if not _preview_matches_controls():status.text="Wait for the preview of these exact settings before adding it.";return
 _insert_generator_payload(_preview_payload.duplicate(true),playback.position,session.selected_track)

func _asset_dropped(data:Variant,seconds:float,track_id:String)->void:
 if KiwiAudioAutomationLane.is_lane(session.document.track_for_id(track_id)):notice("Drop audio or patterns onto an audio or instrument track. Automation lanes link existing parameters.");return
 if data is Dictionary:
  if data.has("audio_generator_payload"):_insert_generator_payload(data.audio_generator_payload.duplicate(true),seconds,track_id)
  elif data.has("audio_source"):session.insert_source(data.audio_source,seconds,track_id,str(data.get("label","Audio")))
  elif data.has("generator"):
   var entry:Dictionary=data.generator
   _queue_generator_drop(entry,entry.get("settings",KiwiAudioSynthesis.default_settings(str(entry.get("id","")))),int(data.get("seed",1)),seconds,track_id)
  elif data.has("audio_library") and KiwiAudioLibrary.valid_entry(data.audio_library):
   var entry:Dictionary=data.audio_library
   if str(entry.get("kind",""))=="preset" and entry.get("preset") is KiwiAudioPreset and entry.preset.kind=="pattern":
    var error:=KiwiAudioPreset.apply_pattern(session,entry.preset,seconds,track_id,true)
    if not error.is_empty():notice(error)
    else:_render_dirty_notes()
   else:session.selected_track=track_id;playback.position=seconds;_library_add(entry)
  elif data.has("files"):_asset_dropped(data.files,seconds,track_id)
 elif data is PackedStringArray or data is Array:
  for file in data:
   if str(file).get_extension().to_lower() in AUDIO_EXTENSIONS:_queue_import(str(file),seconds,track_id)
 elif data is String and str(data).get_extension().to_lower() in AUDIO_EXTENSIONS:_queue_import(data,seconds,track_id)

func add_track_dialog()->void:
 var dialog:=_window("Add track",Vector2i(380,260))
 for kind in ["audio","instrument","group"]:_button(dialog.host,kind.capitalize(),func():session.add_track(kind);dialog.window.queue_free())
 _button(dialog.host,"Automation lane...",func():dialog.window.queue_free();automation_lane_target_dialog())
func new_pattern(drums:bool=false)->void:
 session.begin("Create instrument pattern")
 var track:=session.document.track_for_id(session.selected_track)
 if track.is_empty() or str(track.get("kind",""))!="instrument":session.add_track("instrument","Drums" if drums else "Instrument");track=session.document.track_for_id(session.selected_track)
 if drums:track.instrument=KiwiAudioInstruments.default_instrument("drums")
 var source_bpm:=session.document.conductor().tempo_at(playback.position)
 var samples:=PackedVector2Array();samples.resize(int(4*60/source_bpm*44100))
 var clip:=session.insert_source(KiwiAudioSourceCache.to_wav(samples),playback.position,session.selected_track,"Drum pattern" if drums else "Note pattern")
 if clip==null:session.cancel();return
 var actor:=session.document.actor_for_clip(clip.id);actor.values[&"notes"]=[];actor.values[&"instrument"]=track.get("instrument",KiwiAudioInstruments.default_instrument("poly")).duplicate(true);actor.values[&"pattern_beats"]=4.0;actor.values[&"source_bpm"]=source_bpm
 var source_meter:=session.document.conductor().beat_info(session.document.conductor().seconds_to_beat(playback.position))
 actor.values[&"source_meter"]=[int(source_meter.numerator),int(source_meter.denominator)]
 session.commit();bottom.visible=true;bottom.current_tab=2 if drums else 1;_refresh_all()
func audition_note(pitch:int,patch:Dictionary={})->void:
 if patch.is_empty():
  var actor:=session.primary_actor();var track:=session.document.track_for_id(session.selected_track)
  patch=actor.values.get(&"instrument",track.get("instrument",{"id":"piano"})) if actor!=null else KiwiAudioInstruments.default_instrument("piano")
 var instrument:=patch.duplicate(true)
 jobs.request("audition",func(job:RefCounted):job.update(0,"Auditioning note");return {"stream":KiwiAudioInstruments.render_notes([{"pitch":pitch,"start":0,"duration":0.5,"velocity":0.8}],instrument,120,22050)},0)
func _render_dirty_notes()->void:
 var timing_error:=session.document.midi_timing_error()
 if not timing_error.is_empty():status.text=timing_error;return
 var pending:Array=[]
 for i in session.document.actors.size():
  var actor:=session.document.actors[i]
  if not bool(actor.values.get(&"notes_dirty",false)):continue
  var track:=session.document.track_for_clip(session.document.clips[i].id)
  if track.has("frozen_track"):continue
  if actor.values.has(&"drum_instances"):
   var linked_error:=preload("res://Workspaces/AudioWorkspace/audio_linked_patterns.gd").validate(actor.values.get(&"drum_patterns",{}),actor.values.drum_instances)
   if not linked_error.is_empty():status.text=linked_error;return
  preload("res://Workspaces/AudioWorkspace/audio_linked_patterns.gd").sync(actor)
  pending.append({"bpm":KiwiAudioEditSession.note_source_tempo(actor,session.document),"step_settings":(actor.values.get(&"step_settings",{}) as Dictionary).duplicate(true),"pattern_beats":float(actor.values.get(&"pattern_beats",0)),"tempos":(actor.values.get(&"midi_tempos",[]) as Array).duplicate(true),"tempo_scale":float(actor.values.get(&"midi_tempo_scale",1.0)),"sustain_events":(actor.values.get(&"midi_events",[]) as Array).duplicate(true) if bool(actor.values.get(&"midi_sustain",false)) else [],"signature":_note_render_key(actor),"clip_id":session.document.clips[i].id,"notes":(actor.values.get(&"notes",[]) as Array).duplicate(true),"instrument":actor.values.get(&"instrument",track.get("instrument",{"id":"poly"})).duplicate(true)})
 if pending.is_empty():return
 jobs.request("notes",func(job:RefCounted):
  var outputs:Array=[]
  for i in pending.size():
   if job.is_cancelled():return {"error":"Cancelled"}
   job.update(float(i)/pending.size(),"Rendering instrument patterns")
   var entry:Dictionary=pending[i];var stream:=KiwiAudioEditSession.render_note_source(entry.notes,entry.instrument,float(entry.bpm),entry.step_settings,float(entry.pattern_beats),entry.tempos,float(entry.tempo_scale),job,entry.sustain_events)
   outputs.append({"signature":entry.signature,"clip_id":entry.clip_id,"stream":stream})
  return {"outputs":outputs},session.revision)
func linked_drums_dialog()->void:
 var clip:=session.primary_clip();var actor:=session.primary_actor()
 if clip==null or actor==null or not actor.values.has(&"drum_instances"):notice("Select a generated drum part. Linked drums retain reusable definitions and per-bar instances. Free piano/step edits detach that part to notes, with Undo.");return
 if not session.can_edit(clip.id):notice("Unlock the drum part first.");return
 var owner:=session;var document:=session.document;var clip_id:=clip.id
 var dialog:=_window("Linked drum patterns",Vector2i(920,610));var host:VBoxContainer=dialog.host
 _label(host,"Edit a pattern once to update every linked instance. Make unique disconnects only the chosen instance. Free note editing detaches the entire part; Undo restores links.")
 var chooser:=OptionButton.new();host.add_child(chooser)
 for instance in actor.values.drum_instances:
  chooser.add_item("Beat %.2f · pattern %s"%[float(instance.start),str(instance.pattern_id).left(6)]);chooser.set_item_metadata(chooser.item_count-1,str(instance.id))
 var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;host.add_child(scroll);var editor:=VBoxContainer.new();editor.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(editor)
 var resolve:=func()->Dictionary:
  if session!=owner or session.document!=document or session._before!=null or not session.can_edit(clip_id) or chooser.selected<0:return {}
  var current:=session.document.actor_for_clip(clip_id)
  if current==null:return {}
  for instance in current.values.get(&"drum_instances",[]):
   if str(instance.id)==str(chooser.get_selected_metadata()):return {"actor":current,"instance":instance,"pattern":current.values.get(&"drum_patterns",{}).get(str(instance.pattern_id),{})}
  return {}
 var refresh:=func():
  _clear(editor);var current:Dictionary=resolve.call()
  if current.is_empty() or current.pattern.is_empty():_label(editor,"This instance changed. Reopen Linked drums.");return
  var pattern:Dictionary=current.pattern;var instance:Dictionary=current.instance
  _number(editor,"Instance beat",float(instance.start),0,2048,.25,func(value:float):
   var target:Dictionary=resolve.call()
   if target.is_empty():return
   session.action("Move linked drum instance",func():target.instance.start=value;preload("res://Workspaces/AudioWorkspace/audio_linked_patterns.gd").sync(target.actor);target.actor.values[&"notes_dirty"]=true);_render_dirty_notes())
  for lane_index in pattern.get("lanes",[]).size():
   var row:=HFlowContainer.new();editor.add_child(row);var lane:Dictionary=pattern.lanes[lane_index];_label(row,"MIDI %d"%int(lane.get("pitch",36)))
   for cell_index in mini(64,lane.get("values",[]).size()):
    var cell:Variant=lane.values[cell_index];var toggle:=CheckButton.new();toggle.text=str(cell_index+1);toggle.button_pressed=bool(cell.get("enabled",true)) and float(cell.get("velocity",0))>0 if cell is Dictionary else float(cell)>0;row.add_child(toggle)
    toggle.toggled.connect(func(enabled:bool):
     var target:Dictionary=resolve.call()
     if target.is_empty():return
     session.action("Edit linked drum step",func():
      var value:Variant=target.pattern.lanes[lane_index].values[cell_index]
      if value is Dictionary:
       value.enabled=enabled
       if enabled and float(value.get("velocity",0))<=0:value.velocity=.8
      else:target.pattern.lanes[lane_index].values[cell_index]=.8 if enabled else 0.
      preload("res://Workspaces/AudioWorkspace/audio_linked_patterns.gd").sync(target.actor);target.actor.values[&"notes_dirty"]=true)
     _render_dirty_notes())
 var actions:=HFlowContainer.new();host.add_child(actions)
 _button(actions,"Make selected instance unique",func():
  var target:Dictionary=resolve.call()
  if target.is_empty():return
  if target.actor.values.drum_patterns.size()>=256:notice("The linked definition limit is 256. Detach or remove unused definitions first.");return
  session.action("Unlink drum instance",func():var id:=ActorData.new_id();target.actor.values.drum_patterns[id]=target.pattern.duplicate(true);target.instance.pattern_id=id;target.actor.values[&"notes_dirty"]=true)
  dialog.window.queue_free();linked_drums_dialog();_render_dirty_notes())
 _button(actions,"Duplicate linked instance",func():
  var target:Dictionary=resolve.call()
  if target.is_empty():return
  var proposed:Array=target.actor.values.drum_instances.duplicate(true);var added:Dictionary=target.instance.duplicate(true);added.id=ActorData.new_id();added.start=float(added.start)+float(added.length);proposed.append(added)
  var problem:=preload("res://Workspaces/AudioWorkspace/audio_linked_patterns.gd").validate(target.actor.values.drum_patterns,proposed)
  if not problem.is_empty():notice(problem);return
  session.action("Duplicate linked drum instance",func():
   var copy:Dictionary=target.instance.duplicate(true);copy.id=ActorData.new_id();copy.start=float(copy.start)+float(copy.length);target.actor.values.drum_instances.append(copy);target.actor.values[&"pattern_beats"]=maxf(float(target.actor.values.get(&"pattern_beats",4)),float(copy.start)+float(copy.length));preload("res://Workspaces/AudioWorkspace/audio_linked_patterns.gd").sync(target.actor);target.actor.values[&"notes_dirty"]=true)
  dialog.window.queue_free();linked_drums_dialog();_render_dirty_notes())
 _button(actions,"Detach part to editable notes",func():
  var target:Dictionary=resolve.call()
  if target.is_empty():return
  session.action("Detach linked drums",func():preload("res://Workspaces/AudioWorkspace/audio_linked_patterns.gd").detach(target.actor));dialog.window.queue_free())
 chooser.item_selected.connect(func(_index:int):refresh.call());refresh.call()

func music_dialog()->void:
 var dialog:=_window("Procedural Music Composer",Vector2i(800,720))
 var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(scroll)
 var host:=VBoxContainer.new();host.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(host)
 var settings:=session.document.composer_settings.duplicate(true)
 if settings.is_empty():settings={"style":"Ambient","mood":"Calm","tempo":session.document.tempo,"key":session.document.key,"scale":session.document.scale,"duration":24.0,"energy":0.5,"complexity":0.4,"repetition":0.7,"variation":0.35,"seed":1}
 _choice(host,"Style",KiwiAudioComposer.styles(),str(settings.get("style","Ambient")),func(value:String):settings.style=value)
 _choice(host,"Mood",["Calm","Bright","Playful","Dark","Sad","Neutral"],str(settings.get("mood","Calm")),func(value:String):settings.mood=value)
 _choice(host,"Scale",KiwiAudioComposer.scales().keys(),str(settings.get("scale","minor")),func(value:String):settings.scale=value)
 var keys:Array=["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
 _choice(host,"Key",keys,str(keys[clampi(int(settings.get("key",0)),0,11)]),func(value:String):settings.key=keys.find(value))
 for info in [["tempo",20,300,1],["duration",2,240,1],["energy",0,1,0.01],["complexity",0,1,0.01],["repetition",0,1,0.01],["variation",0,1,0.01],["seed",0,2147483647,1]]:
  var key:=str(info[0]);_number(host,key.capitalize(),float(settings.get(key,1)),info[1],info[2],info[3],func(value:float):settings[key]=value)
 var extra:=KiwiAudioComposerControls.new();host.add_child(extra);extra.setup(settings,session.document.sections)
 var role_choice:=_choice(host,"Regenerate",["Entire arrangement","melody","chords","bass","drums","pad"],"Entire arrangement",func(_value:String):pass)
 var sections:Array=["All sections"];var section_ids:Array=[""]
 for section in session.document.sections:sections.append(str(section.name));section_ids.append(str(section.id))
 var section_choice:=_choice(host,"Section",sections,"All sections",func(_value:String):pass)
 _label(host,"Editable, rule-based musical sketches. Composer tempo is saved with its source patterns; existing project conductor points are preserved. Generation does not follow variable project tempo or meter. Acoustic-like patches are synthesis; use your own samples for recorded acoustic instruments.")
 _button(dialog.host,"Generate editable music",func():
  var role:="" if role_choice.selected==0 else role_choice.get_item_text(role_choice.selected)
  var section_id:=str(section_ids[section_choice.selected]);settings.erase("section_layout");settings.merge(extra.settings_copy(),true);_compose(settings,role,section_id);dialog.window.queue_free())

func _compose(settings:Dictionary,role:String="",section_id:String="")->void:
 var previous:=KiwiAudioComposerControls.snapshot_arrangement(session.document)
 var config:=settings.duplicate(true)
 config.time_signature=[session.document.time_signature.x,session.document.time_signature.y]
 if not role.is_empty() or not section_id.is_empty():config.tempo=session.document.arrangement_tempo();config.time_signature=session.document.composer_settings.get("time_signature",config.time_signature);config.key=session.document.key;config.scale=session.document.scale
 jobs.request("composer",func(job:RefCounted):return KiwiAudioComposerControls.render_arrangement(config,previous,role,section_id,job),session.revision)

func chord_dialog()->void:
 if session.primary_actor()==null:new_pattern()
 var dialog:=_window("Insert chord",Vector2i(400,240));var state:Dictionary={"degree":0,"inversion":0}
 _number(dialog.host,"Scale degree",1,1,7,1,func(value:float):state.degree=int(value)-1);_number(dialog.host,"Inversion",0,0,2,1,func(value:float):state.inversion=int(value))
 _button(dialog.host,"Insert editable notes",func():
  var actor:=session.primary_actor();if actor==null or not session.can_edit(session.primary_clip().id):return
  session.action("Insert chord",func():
   var notes:Array=actor.values.get(&"notes",[])
   for pitch in KiwiAudioComposer.chord(60+session.document.key,session.document.scale,state.degree,state.inversion):notes.append(KiwiAudioComposer.new_note(pitch,piano.scroll_beat,1,0.75))
   actor.values[&"notes"]=notes;actor.values[&"notes_dirty"]=true;piano._mark_changed())
  _render_dirty_notes();dialog.window.queue_free())
func humanize_notes()->void:
 var actor:=session.primary_actor();if actor==null or not session.can_edit(session.primary_clip().id):return
 var rng:=RandomNumberGenerator.new();rng.seed=1
 session.action("Humanize notes",func():
  for note in actor.values.get(&"notes",[]):note.start=maxf(0,float(note.start)+rng.randf_range(-0.025,0.025));note.velocity=clampf(float(note.get("velocity",0.8))+rng.randf_range(-0.07,0.07),0.05,1)
  actor.values[&"notes_dirty"]=true;piano._mark_changed())
 _render_dirty_notes()
func arpeggiate_notes()->void:
 var actor:=session.primary_actor();if actor==null or not session.can_edit(session.primary_clip().id):return
 session.action("Arpeggiate notes",func():
  var notes:Array=actor.values.get(&"notes",[]);notes.sort_custom(func(a:Dictionary,b:Dictionary):return int(a.pitch)<int(b.pitch))
  for i in notes.size():notes[i].start=piano.scroll_beat+i*0.25;notes[i].duration=0.22
  actor.values[&"notes_dirty"]=true;piano._mark_changed())
 _render_dirty_notes()
func _audio_property()->ActorProperty:
 var property:=ActorProperty.new();property.options={"extensions":PackedStringArray(AUDIO_EXTENSIONS)};return property
func import_audio()->void:
 var picker_session:=session;var picker_revision:=session.revision
 var chosen:=await ActorProjectFilePicker.pick(self,_audio_property(),"Import project audio")
 if session!=picker_session or session.revision!=picker_revision:notice("The composition changed while choosing a file. Repeat this action in the intended document.");return
 if chosen.is_empty() or chosen==ActorProjectFilePicker.EMPTY_RESOURCE:return
 _queue_import(chosen,playback.position,session.selected_track)
func _queue_import(chosen:String,at:float,track_id:String)->void:
 if KiwiAudioAutomationLane.is_lane(session.document.track_for_id(track_id)):notice("Select an audio or instrument track before importing audio.");return
 jobs.request("import",func(job:RefCounted):job.update(0,"Reading audio duration");return {"path":chosen,"seconds":ActorAudio.file_duration(chosen,job),"at":at,"track":track_id},int(session.document.get_instance_id()),false)
func open_dialog()->void:
 var property:=ActorProperty.new();property.options={"extensions":PackedStringArray(["tres","res","wav","mp3","ogg","flac"])}
 var chosen:=await ActorProjectFilePicker.pick(self,property,"Open audio composition or source")
 if chosen.is_empty() or chosen==ActorProjectFilePicker.EMPTY_RESOURCE:return
 var tabs:=get_tree().get_first_node_in_group("actor_scene_tabs")
 if tabs!=null and tabs.has_method("open_audio"):tabs.call("open_audio",chosen)
 else:open_source(chosen)
func relink_source()->void:
 if recorder.recording or _record_busy:notice("Finish or cancel the take before relinking audio.");return
 if session._before!=null:notice("Finish the current edit before relinking audio.");return
 var clip:=session.primary_clip();var actor:=session.primary_actor()
 if clip==null or actor==null:return
 var source_value:Variant=actor.values.get(&"audio")
 if not source_value is String or source_value.is_empty():notice("Only file-backed audio clips can be relinked here. Embedded edits and sampler sources are preserved.");return
 if KiwiAudioEditSession.is_note_source(actor):notice("Restore this pattern's instrument samples instead of replacing its generated audio.");return
 if not session.can_edit(clip.id):notice("Unlock the clip before relinking its source.");return
 _finish_automation_pass("Audio relink started")
 _relink_generation+=1
 var context:Dictionary={"owner":session,"document":session.document,"revision":session.revision,"focus_id":clip.id,"source":source_value,"token":_relink_generation}
 var shared:=session.audio_source_clips(clip.id)
 if shared.size()<=1:
  _pick_audio_relink(context,[clip.id]);return
 var dialog:=_window("Relink shared audio source",Vector2i(600,270));dialog.window.set_meta("audio_relink_window",true)
 _label(dialog.host,"%d clips reference this source: %s"%[shared.size(),str(source_value).get_file()])
 _label(dialog.host,"Choose the scope explicitly. Every source window is checked before any clip changes. Timeline positions, trims, speed, reverse/loop state, effects and automation stay intact. Locked or incompatible clips reject the whole chosen group.")
 _button(dialog.host,"Relink this clip only",func():_pick_audio_relink(context,[str(context.focus_id)]);dialog.window.queue_free())
 _button(dialog.host,"Relink all %d referencing clips"%shared.size(),func():_pick_audio_relink(context,shared);dialog.window.queue_free())
 _button(dialog.host,"Cancel",dialog.window.queue_free)

func _relink_context_current(context:Dictionary)->bool:
 return is_inside_tree() and is_visible_in_tree() and not recorder.recording and not _record_busy and context.get("owner")==session and context.get("document")==session.document and int(context.get("revision",-1))==session.revision and int(context.get("token",-1))==_relink_generation and session._before==null and session.primary_clip()!=null and session.primary_clip().id==str(context.get("focus_id",""))

func _pick_audio_relink(context:Dictionary,ids:Array)->void:
 if not _relink_context_current(context):notice("The composition or selection changed. Start relinking again.");return
 var chosen:=await ActorProjectFilePicker.pick(self,_audio_property(),"Choose replacement audio (preserve source windows)")
 if not _relink_context_current(context):notice("The composition or selection changed while choosing a source. Start relinking again.");return
 if chosen.is_empty() or chosen==ActorProjectFilePicker.EMPTY_RESOURCE:return
 var request:=context.duplicate();request.ids=ids.duplicate()
 jobs.request("relink_probe",func(job:RefCounted):
  var result:=KiwiAudioEditSession.probe_audio_relink(chosen,job)
  return {"context":request,"replacement":result},int(request.token))
 status.text="Checking replacement source; the composition is unchanged."

func _review_audio_relink(data:Dictionary)->void:
 if not str(data.get("error","")).is_empty():notice(str(data.error));return
 var context:Dictionary=data.get("context",{})
 if not _relink_context_current(context):return
 var replacement:Dictionary=data.get("replacement",{})
 var problem:=session.audio_relink_problem(context.get("ids",[]),str(context.get("source","")),replacement)
 if not problem.is_empty():notice(problem);return
 var dialog:=_window("Confirm audio relink",Vector2i(620,310));dialog.window.set_meta("audio_relink_window",true)
 _label(dialog.host,"Replace %s with %s (%.6f seconds) in %d clip(s)."%[str(context.source).get_file(),str(replacement.path).get_file(),float(replacement.seconds),(context.ids as Array).size()])
 _label(dialog.host,"The replacement fits every selected source window. Apply changes only the active file reference and source-duration metadata; clip geometry and processing stay unchanged. Original sources, embedded edits, sampler mappings and original_audio provenance are not copied or rewritten. Loop periods must match exactly. Changes form one Undo action. Reusing the same path also refreshes its cache and clears any stale transient analysis.")
 _button(dialog.host,"Apply relink",func():
  if _complete_audio_relink(data):dialog.window.queue_free())
 _button(dialog.host,"Cancel",dialog.window.queue_free)

func _complete_audio_relink(data:Dictionary)->bool:
 if recorder.recording or _record_busy:notice("Finish or cancel the take before relinking audio.");return false
 var context:Dictionary=data.get("context",{})
 if not _relink_context_current(context):notice("The composition or selection changed. Start relinking again.");return false
 if automation_recording.has_pending():notice("Finish or discard the pending automation pass before relinking.");return false
 var ids:Array=context.get("ids",[])
 var prior_revision:=session.revision
 var replacement:Dictionary=data.get("replacement",{})
 var problem:=session.audio_relink_problem(ids,str(context.get("source","")),replacement)
 if not problem.is_empty():notice(problem);return false
 # stop()/set_document() synchronize the OLD runtime model too. A source
 # restored at the same path may have become too large for native decoding.
 var previous_overrides:Dictionary=playback.system.clip_stream_overrides.duplicate()
 ActorAudio.invalidate(str(replacement.path))
 var key:=KiwiAudioEditSession.audio_source_key(replacement.path)
 # Alias references have separate metadata-cache keys, even on Windows.
 for actor in session.document.actors:
  if KiwiAudioEditSession.audio_source_key(actor.values.get(&"audio"))==key:ActorAudio.invalidate(str(actor.values.audio))
 if ActorAudio.needs_file_preview(replacement.path):
  for i in mini(playback.model.actors.size(),playback.model.clips.size()):
   if KiwiAudioEditSession.audio_source_key(playback.model.actors[i].values.get(&"audio"))==key:playback.system.clip_stream_overrides[playback.model.clips[i].id]=null
 problem=session.relink_audio_sources(ids,str(context.get("source","")),replacement)
 if not problem.is_empty():playback.system.clip_stream_overrides=previous_overrides;notice(problem);return false
 _relink_generation+=1
 _cancel_exact_playback();playback.stop(false)
 _analysis_result={};cache.invalidate()
 if session.revision==prior_revision:_refresh_all() # A same-path refresh emits no session.changed.
 if ids.has(_wave_clip_id):_wave_clip_id="";waveform.open(null);waveform.selection=Vector2i.ZERO
 status.text=("Relinked %d clip(s) without changing their windows or processing."%ids.size()) if session.revision!=prior_revision else "Source refreshed. No document changes or Undo action were needed."
 return true

func missing_media_dialog()->void:
 if recorder.recording or _record_busy:notice("Finish the take before reviewing missing media.");return
 _finish_control_edits();session.commit()
 var snapshot:=session.document.snapshot();var owner_id:=session.get_instance_id();var document_id:=session.document.get_instance_id();var revision:=session.revision
 jobs.request("media_scan",func(_job:RefCounted):return {"scan":preload("res://Workspaces/AudioWorkspace/audio_media_repair.gd").scan(snapshot),"owner_id":owner_id,"document_id":document_id,"revision":revision},revision)
 status.text="Reviewing clip, instrument and effect media references..."

func _media_context_current(data:Dictionary)->bool:
 return session.get_instance_id()==int(data.get("owner_id",0)) and session.document.get_instance_id()==int(data.get("document_id",0)) and session.revision==int(data.get("revision",-1)) and session._before==null and not recorder.recording and not _record_busy and not automation_recording.has_pending()

func _show_media_review(data:Dictionary)->void:
 if not _media_context_current(data):return
 var scan:Dictionary=data.get("scan",{})
 if not str(scan.get("error","")).is_empty():notice("Media review stopped: "+str(scan.error));return
 var dialog:=_window("Linked media · missing source repair",Vector2i(780,560))
 _label(dialog.host,"One replacement updates matching active clip, sampler and effect references together. Clip windows and sampler loop bounds must fit; locked/frozen owners block the change. Original-source provenance remains untouched. Recollect portable media after relinking. Sampler loops with an automatic end follow the replacement's length.")
 var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(scroll);var host:=VBoxContainer.new();host.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(host)
 var count:=0
 for entry in scan.get("entries",[]):
  if not bool(entry.missing):continue
  count+=1;var row:=VBoxContainer.new();host.add_child(row)
  _label(row,str(entry.source)+" · %d reference(s)"%int(entry.count))
  var details:=Label.new();details.text="\n".join(entry.labels);details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;row.add_child(details)
  _button(row,"Choose replacement...",func():
   if not _media_context_current(data):notice("The composition changed. Reopen Missing media.");return
   var chosen:=await ActorProjectFilePicker.pick(dialog.window,_audio_property(),"Repair linked media")
   if chosen.is_empty() or chosen==ActorProjectFilePicker.EMPTY_RESOURCE:return
   if not _media_context_current(data):notice("The composition changed while choosing media.");return
   var context:=data.duplicate();context.source=str(entry.source)
   jobs.request("media_probe",func(job:RefCounted):return {"context":context,"replacement":KiwiAudioEditSession.probe_audio_relink(chosen,job)},session.revision)
   dialog.window.queue_free())
 if count==0:_label(host,"No missing or empty files were found in the supported media fields. Existing files are not exhaustively decoded by this scan.")

func _confirm_media_repair(data:Dictionary)->void:
 var context:Dictionary=data.get("context",{})
 if not _media_context_current(context):return
 var replacement:Dictionary=data.get("replacement",{})
 if not str(replacement.get("error","")).is_empty():notice(str(replacement.error));return
 var owner:=session.document;var revision:=session.revision
 var dialog:=_window("Confirm linked media replacement",Vector2i(650,260))
 _label(dialog.host,str(context.source)+"\n→ "+str(replacement.path)+"\nAll matching active references are checked before one undoable edit. Source files are never overwritten.")
 _button(dialog.host,"Apply replacement",func():
  if not _media_context_current(context):notice("The composition changed. Reopen Missing media.");return
  var problem:=preload("res://Workspaces/AudioWorkspace/audio_media_repair.gd").apply(session,owner,revision,str(context.source),replacement)
  if not problem.is_empty():notice(problem);return
  dialog.window.queue_free();_render_dirty_notes();missing_media_dialog())
 _button(dialog.host,"Cancel",dialog.window.queue_free)

func save()->void:
 var picker_session:=session;var picker_document:=session.document
 var destination:=document_path
 if destination.is_empty():
  var extension:="res" if not session.document.portable_media.is_empty() else "tres"
  var target:=await ActorProjectResourceSaveDialog.pick(self,"Save editable audio composition",session.document.title+".audio",extension,false,PackedStringArray([extension]),func(): capture_state(); return session.document.snapshot())
  if session!=picker_session or session.document!=picker_document:notice("The active composition changed while choosing a save path. Save again in the intended document.");return
  if target.is_empty():return
  var chosen:=str(target.get("path",""));if chosen.is_empty():return
  destination=chosen
 capture_state()
 var timing_error:=session.document.midi_timing_error()
 if not timing_error.is_empty():notice(timing_error);return
 var snapshot:=session.document.snapshot()
 var portable_save:=KiwiAudioDocument.PortableCopy.for_save(snapshot,destination)
 if not str(portable_save.get("error","")).is_empty():notice(str(portable_save.error));return
 snapshot=portable_save.document
 var error:=save_document(snapshot,destination)
 if error!=OK:notice("Audio composition could not be saved (%s)."%error);return
 document_path=destination;source=document_path;path=document_path;session.dirty=false;audio_saved.emit(document_path);_refresh_all();status.text="Saved editable audio composition."
 if LocalProjectFilesystem.node!=null:LocalProjectFilesystem.update_root_folder()
static func save_document(document:KiwiAudioDocument,destination:String)->Error:
 if document==null or not document.validate().is_empty():return ERR_INVALID_DATA
 var portable_save:=KiwiAudioDocument.PortableCopy.for_save(document,destination)
 if not str(portable_save.get("error","")).is_empty():return ERR_INVALID_DATA
 document=portable_save.document
 var extension:=destination.get_extension().to_lower()
 if extension not in ["tres","res"]:return ERR_FILE_UNRECOGNIZED
 var absolute:=ProjectSettings.globalize_path(destination)
 var error:=DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
 if error!=OK:return error
 # ResourceSaver selects its encoding from the temporary extension. Renaming
 # text .tres bytes to an existing binary .res destination makes it unreadable.
 # Use an owned sibling so a previous interrupted save is never truncated.
 var temporary:=absolute.get_basename()+".kiwi-saving-"+ActorData.new_id()+"."+extension
 error=ResourceSaver.save(document,temporary)
 if error!=OK:
  if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
  return error
 var backup:=absolute+".bak"
 if FileAccess.file_exists(absolute):
  if FileAccess.file_exists(backup):
   var previous:=backup+"."+str(Time.get_unix_time_from_system()).replace(".","_");var move_error:=DirAccess.rename_absolute(backup,previous)
   if move_error!=OK:return move_error
  error=DirAccess.rename_absolute(absolute,backup)
  if error!=OK:return error
 error=DirAccess.rename_absolute(temporary,absolute)
 if error!=OK and FileAccess.file_exists(backup):DirAccess.rename_absolute(backup,absolute)
 return error
func export_dialog()->void:
 var dialog:=_window("Export audio",Vector2i(550,500));var host:VBoxContainer=dialog.host;var options:=_export_options.duplicate(true)
 var presets:=KiwiAudioTemplates.export_presets()
 _choice(host,"Preset",presets.keys(),"High Quality",func(value:String):options.merge(presets[value],true))
 _choice(host,"Sample rate",["44100","48000","96000"],str(options.sample_rate),func(value:String):options.sample_rate=int(value))
 _choice(host,"Bit depth",["16","24","32"],str(options.bit_depth),func(value:String):options.bit_depth=int(value))
 _number(host,"Bitrate (kbps)",options.bitrate,64,320,1,func(value:float):options.bitrate=int(value))
 _check(host,"Mono",bool(options.mono),func(value:bool):options.mono=value)
 _check(host,"Include effect tails",bool(options.include_tail),func(value:bool):options.include_tail=value)
 _check(host,"Normalize loudness",bool(options.normalize),func(value:bool):options.normalize=value)
 _number(host,"Target LUFS",float(options.get("target_lufs",-16)),-30,-8,0.1,func(value:float):options.target_lufs=value)
 var scope:=_choice(host,"Range",["Entire mix","Time selection","Selected clips","Selected track","Stems"],"Entire mix",func(_value:String):pass)
 _label(host,"Real WAV / MP3 / Ogg Vorbis / FLAC encoders. A safety limiter protects the output; loudness targets are optional. Effect tails are retained unless disabled.")
 _button(host,"Choose destination",func():
  _export_options=options.duplicate(true)
  match scope.selected:
   1:
    if canvas.time_selection.y<=canvas.time_selection.x:notice("Select a time range first.");return
    options.start=canvas.time_selection.x;options.duration=canvas.time_selection.y-canvas.time_selection.x
   2:options.clip_ids=session.selected_ids.duplicate()
   3:options.track_id=session.selected_track
   4:options.stems=true
  dialog.window.queue_free();_choose_export(options))
func _choose_export(options:Dictionary)->void:
 var scope_error:=KiwiAudioRenderer.selection_error(session.document,options)
 if not scope_error.is_empty():notice(scope_error);return
 var picker_session:=session;var picker_revision:=session.revision
 var target:=await ActorProjectResourceSaveDialog.pick(self,"Export audio",session.document.title,"wav",false,PackedStringArray(["wav","mp3","ogg","flac"]))
 if session!=picker_session or session.revision!=picker_revision:notice("The composition changed while choosing a file. Repeat this action in the intended document.");return
 if target.is_empty():return
 var destination:=str(target.get("path",""));if destination.is_empty():return
 var timing_error:=session.document.midi_timing_error()
 if not timing_error.is_empty():notice(timing_error);return
 if bool(options.get("stems",false)):
  var snapshot:=session.document.snapshot()
  jobs.request("export_stems",func(job:RefCounted):
   var results:Array=[];var stem_names:Dictionary={}
   for track in snapshot.tracks:
    if str(track.get("kind",""))=="group" or (KiwiAudioAutomationLane.is_lane(track) and KiwiAudioAutomationLane.binding_error(snapshot,str(track.id)).is_empty()):continue
    if job.is_cancelled():break
    var stem_options:=options.duplicate(true);stem_options.track_id=track.id
    var name:=_stem_destination(destination,track,stem_names)
    results.append(KiwiAudioRenderer.render(snapshot,name,stem_options,job))
   return {"results":results},session.revision)
 else:_start_render(destination,options,"export")
func _start_render(destination:String,options:Dictionary,action:String)->void:
 if automation_recording.active:_finish_automation_pass("Render requested")
 var timing_error:=session.document.midi_timing_error()
 if not timing_error.is_empty():
  if action=="preview":_cancel_exact_playback()
  notice(timing_error);return
 if KiwiAudioAutomationLane.is_lane(session.document.track_for_id(str(options.get("track_id","")))):notice("Select the linked audio track for a stem or bounce; automation lanes contain no audio clips.");return
 if action=="preview" and (recorder.recording or _record_busy):notice("Finish or cancel the take before starting another preview.");return
 var snapshot:=session.document.snapshot();var settings:=options.duplicate(true);var selection:=session.selected_ids.duplicate();var target_track:=str(options.get("track_id",session.selected_track));var at:=playback.position
 if action=="preview":settings.route_meters=true
 var owner_id:=session.get_instance_id();var token:=_transport_token
 _render_generation=session.revision
 if action=="preview":
  _transport_requested=true;playback.exact_pending=true;playback.playing=false
 elif _transport_requested:_cancel_exact_playback()
 jobs.request("render",func(job:RefCounted):
  var result:=KiwiAudioRenderer.render(snapshot,destination,settings,job);result.action=action;result.selection=selection;result.track_id=target_track;result.at=float(settings.get("start",at));result.monitor_from=float(settings.get("monitor_from",result.at));result.owner_id=owner_id;result.transport_token=token
  if bool(result.get("success",false)) and action=="preview":
   result.file_preview=true;result.pcm_info=KiwiAudioPCMFile.inspect(destination)
  elif bool(result.get("success",false)) and action!="export":result.stream=_workspace_source(destination)
  return result,_render_generation)

func _temporary_audio(label:String)->String:
 var directory:=ProjectSettings.globalize_path("user://audio_workspace/rendered")
 DirAccess.make_dir_recursive_absolute(directory)
 return directory.path_join(label+"_"+ActorData.new_id()+".wav")
func render_preview()->void:
 if automation_recording.active:_finish_automation_pass("Exact preview requested")
 if recorder.recording or _record_busy:notice("Finish or cancel the take before starting another preview.");return
 _cancel_exact_playback();playback.stop(false);preview_player.stop()
 _transport_requested=true;playback.exact_pending=true;playback.exact_required=true
 var options:Dictionary={"sample_rate":44100,"bit_depth":16,"start":playback.position}
 if playback.loop_enabled and session.document.loop_end>session.document.loop_start:
  # Prepare the whole loop and seek into it for the first pass. Rendering
  # only the playhead-to-end suffix would repeat that suffix on every wrap.
  options.monitor_from=clampf(playback.position,session.document.loop_start,session.document.loop_end)
  if float(options.monitor_from)>=session.document.loop_end:options.monitor_from=session.document.loop_start
  options.start=session.document.loop_start
  options.duration=session.document.loop_end-session.document.loop_start;options.include_tail=false
 _start_render(_temporary_audio("preview"),options,"preview")

func play_selection()->void:
 if not _wave_clip_id.is_empty() and waveform.selection.y>waveform.selection.x:
  var clip:=session.document.clip_for_id(_wave_clip_id)
  if clip==null:return
  var start:=clip.start_time+(float(waveform.selection.x)/waveform.rate-clip.source_offset)/clip.playback_speed
  var duration:=float(waveform.selection.y-waveform.selection.x)/waveform.rate/clip.playback_speed
  _start_render(_temporary_audio("selection"),{"sample_rate":44100,"bit_depth":16,"start":maxf(0,start),"duration":duration,"clip_ids":[clip.id],"include_tail":false},"preview")
 elif canvas.time_selection.y>canvas.time_selection.x:_start_render(_temporary_audio("selection"),{"sample_rate":44100,"bit_depth":16,"start":canvas.time_selection.x,"duration":canvas.time_selection.y-canvas.time_selection.x,"include_tail":false},"preview")
func render_in_place()->void:
 if session.selected_ids.is_empty():return
 if session._before!=null:notice("Finish the current adjustment before rendering clips in place.");return
 var target_track:=""
 for id in session.selected_ids:
  if not session.can_edit(id):notice("Unlock selected tracks before rendering in place.");return
  var source_track:=str(session.document.track_for_clip(id).get("id",""))
  if not target_track.is_empty() and source_track!=target_track:notice("Render clips in place one track at a time to preserve each track's processing and routing.");return
  target_track=source_track
 var first:=INF;var last:=0.0
 for id in session.selected_ids:
  var clip:=session.document.clip_for_id(id);first=minf(first,clip.start_time);last=maxf(last,clip.start_time+clip.duration)
 _start_render(_temporary_audio("bounce"),{"sample_rate":44100,"bit_depth":16,"clip_ids":session.selected_ids.duplicate(),"track_id":target_track,"start":first,"duration":last-first,"bypass_track_processing":true,"bypass_master_processing":true},"replace")
func bounce_track()->void:
 var track:=session.document.track_for_id(session.selected_track)
 if track.is_empty():notice("Select a track before bouncing audio.");return
 if bool(track.get("locked",false)):notice("Unlock the selected track before bouncing it.");return
 _start_render(_temporary_audio("track"),{"sample_rate":44100,"bit_depth":16,"track_id":session.selected_track,"bypass_master_processing":true},"bounce_track")
func freeze_track()->void:
 var track:=session.document.track_for_id(session.selected_track)
 if track.is_empty() or bool(track.get("locked",false)):return
 var prepared:=preload("res://Workspaces/AudioWorkspace/audio_group_freeze.gd").members(session.document,str(track.id))
 if not str(prepared.get("error","")).is_empty():notice(prepared.error);return
 _start_render(_temporary_audio("freeze"),{"sample_rate":44100,"bit_depth":16,"track_id":session.selected_track,"bypass_master_processing":true},"freeze_track")
func unfreeze_track()->void:
 var selected:=session.document.track_for_id(session.selected_track)
 var original:=session.document.track_for_id(str(selected.get("frozen_source",selected.get("id",""))))
 if original.is_empty() or not original.has("frozen_track"):return
 var frozen_id:=str(original.frozen_track)
 session.action("Unfreeze track",func():
  for i in range(session.document.clips.size()-1,-1,-1):
   if str(session.document.actors[i].values.get(&"track_id",""))==frozen_id:session.document.clips.remove_at(i);session.document.actors.remove_at(i)
  session.document.tracks.erase(session.document.track_for_id(frozen_id))
  if original.has("freeze_members"):preload("res://Workspaces/AudioWorkspace/audio_group_freeze.gd").restore_members(session.document,original)
  else:original.mute=bool(original.get("freeze_previous_mute",false));original.locked=bool(original.get("freeze_previous_locked",false));original.solo=bool(original.get("freeze_previous_solo",false))
  for track in session.document.tracks:
   if str(track.get("output",""))==frozen_id:track.output=str(original.id)
   for send in track.get("sends",[]):
    if str(send.get("target",""))==frozen_id:send.target=str(original.id)
  original.erase("frozen_track");original.erase("freeze_previous_mute");original.erase("freeze_previous_locked");original.erase("freeze_previous_solo");session.selected_track=str(original.id);session.selected_ids.clear())
 _render_dirty_notes()
func send_to_scene()->void:
 _start_render(_temporary_audio("scene_audio"),{"sample_rate":48000,"bit_depth":16},"scene")
func save_preview_audio()->void:
 if not _preview_matches_controls():status.text="Wait for the current generator preview before saving audio.";return
 var payload:=_preview_payload.duplicate(true);var picker_session:=session
 var target:=await ActorProjectResourceSaveDialog.pick(self,"Save generated audio",str(payload.label),"wav",false,PackedStringArray(["wav","mp3","ogg","flac"]))
 if session!=picker_session:notice("The document changed while choosing a file. Repeat this action in the intended document.");return
 if target.is_empty():return
 var destination:=str(target.get("path",""));var value:AudioStreamWAV=payload.stream
 jobs.request("save_preview",func(_job:RefCounted):
  var property:=ActorProperty.new();property.options={"extensions":PackedStringArray(AUDIO_EXTENSIONS)}
  return {"success":ActorMediaExport.write(value,destination,property),"path":destination,"duration":value.get_length()},0)

func save_preset(kind:String)->void:
 var timing_error:=session.document.midi_timing_error()
 if not timing_error.is_empty():notice(timing_error);return
 var captured_generator:=_preview_payload.duplicate(true)
 var captured_document:=session.document.snapshot();var captured_actor:=session.primary_actor()
 var captured_effects:Array=(_effect_owner().get("effects",[]) as Array).duplicate(true)
 var captured_instrument:Dictionary=captured_actor.values.get(&"instrument",{}).duplicate(true) if captured_actor!=null else {}
 var captured_pattern:Dictionary=KiwiAudioPreset.pattern_data(captured_actor,session.document) if captured_actor!=null else {}
 if kind=="generator" and not _preview_matches_controls():status.text="Wait for the current generator preview before saving its preset.";return
 _name_dialog("Save "+kind+" preset",str(_library_entry.get("label",session.document.title)),func(label:String):
  var preset:=KiwiAudioPreset.new();preset.id=ActorData.new_id();preset.label=label;preset.kind=kind
  match kind:
   "generator":preset.data={"id":captured_generator.id,"settings":captured_generator.settings.duplicate(true),"seed":captured_generator.seed}
   "effects":preset.data={"effects":captured_effects}
   "instrument":preset.data=captured_instrument
   "pattern":
    if captured_pattern.is_empty():notice("Select a note pattern first.");return
    preset.data=captured_pattern;preset.tags=PackedStringArray(preset.data.get("tags",[]))
   "composition":preset.composition=captured_document
  _persist_preset(preset))
func export_native_preset(preset:KiwiAudioPreset)->void:
 if preset==null:return
 var copy:=preset.duplicate(true) as KiwiAudioPreset
 var target:=await ActorProjectResourceSaveDialog.pick(self,"Export native audio preset",copy.label,"tres",false,PackedStringArray(["tres"]))
 if target.is_empty():return
 var destination:=str(target.get("path",""))
 if destination.is_empty():return
 if FileAccess.file_exists(destination):notice("Choose a new filename; existing presets are never overwritten by Export.");return
 copy.resource_path=""
 var error:=ResourceSaver.save(copy,destination)
 if error!=OK:notice("Could not export native preset: "+error_string(error))
 else:status.text="Exported native preset. External sample/IR references stay linked; use Collect Portable for compositions."

func import_native_preset()->void:
 var picker:=FileDialog.new();picker.title="Import trusted Kiwi audio preset";picker.access=FileDialog.ACCESS_FILESYSTEM;picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE;picker.filters=PackedStringArray(["*.tres ; Trusted native audio presets"]);add_child(picker)
 picker.file_selected.connect(func(location:String):
  picker.queue_free()
  var file:=FileAccess.open(location,FileAccess.READ)
  if file==null or file.get_length()>128*1024*1024:notice("Choose a readable native preset up to 128 MiB.");return
  file.close()
  var preset:=ResourceLoader.load(location,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiAudioPreset
  if preset==null or not KiwiAudioLibrary.valid_entry({"kind":"preset","preset":preset}):notice("This is not a supported Kiwi audio preset.");return
  preset=preset.duplicate(true);preset.id=ActorData.new_id();preset.resource_path="";_persist_preset(preset))
 picker.canceled.connect(picker.queue_free);picker.popup_centered_ratio(.7)

func preset_recovery_dialog()->void:
 var entries:=preload("res://Workspaces/AudioWorkspace/audio_preset_store.gd").recoverable()
 var dialog:=_window("Recover removed presets and earlier versions",Vector2i(720,470));var list:=ItemList.new();list.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(list)
 for entry in entries:list.add_item(str(entry.label))
 _label(dialog.host,"Restore creates an independent library copy. The recovery original and any current preset are preserved.")
 _button(dialog.host,"Restore selected as new preset",func():
  if list.get_selected_items().is_empty():return
  var error:=preload("res://Workspaces/AudioWorkspace/audio_preset_store.gd").restore(entries[list.get_selected_items()[0]])
  if not error.is_empty():notice(error)
  else:library.reload();dialog.window.queue_free();status.text="Restored preset as an independent copy.")

func save_layer_bundle()->void:
 var result:=preload("res://Workspaces/AudioWorkspace/audio_layer_bundle.gd").selected(session.document,session.selected_ids)
 if not str(result.get("error","")).is_empty():notice(result.error);return
 var captured:KiwiAudioDocument=result.document
 _name_dialog("Save selected layer bundle","Layer bundle",func(label:String):
  var preset:=KiwiAudioPreset.new();preset.id=ActorData.new_id();preset.kind="bundle";preset.label=label;preset.composition=captured;_persist_preset(preset))

func _audition_native_preset(preset:KiwiAudioPreset)->void:
 var document:=KiwiAudioDocument.new();var render_options:Dictionary={"sample_rate":44100,"bit_depth":16,"start":0.,"duration":8.,"include_tail":false}
 match preset.kind:
  "composition","bundle":
   if preset.composition==null:return
   document=preset.composition.snapshot();render_options.duration=minf(15.,document.duration())
  "pattern","instrument":
   var preview_session:=KiwiAudioEditSession.new();preview_session.document=document
   var pattern:=preset
   if preset.kind=="instrument":
    pattern=KiwiAudioPreset.new();pattern.kind="pattern";pattern.label=preset.label;pattern.data={"notes":[{"pitch":60,"start":0.,"duration":1.,"velocity":.7},{"pitch":64,"start":1.,"duration":1.,"velocity":.7},{"pitch":67,"start":2.,"duration":1.,"velocity":.7}],"instrument":preset.data.duplicate(true),"pattern_beats":4.}
   var problem:=KiwiAudioPreset.apply_pattern(preview_session,pattern,0,"",true)
   if not problem.is_empty():notice(problem);return
   document=preview_session.document;render_options.duration=minf(15.,document.duration())
  "effects":
   if session.primary_clip()==null:notice("Select a clip to audition this effect chain without applying it.");return
   document=session.document.snapshot();var actor:=document.actor_for_clip(session.primary_clip().id);actor.values[&"effects"]=preset.data.get("effects",[]).duplicate(true)
   render_options.clip_ids=[session.primary_clip().id];render_options.start=session.primary_clip().start_time;render_options.duration=minf(8.,session.primary_clip().duration)
  _:return
 var destination:=_temporary_audio("preview_preset");var token:=session.get_instance_id()
 jobs.request("preset_audition",func(job:RefCounted):
  var result:=KiwiAudioRenderer.render(document,destination,render_options,job);result.owner=token
  return result,0)

func _persist_preset(preset:KiwiAudioPreset)->void:
 if preset.kind=="pattern":
  var problem:=KiwiAudioPreset.validate_pattern(preset.data)
  if not problem.is_empty():notice(problem);return
 var directory:=ProjectSettings.globalize_path("user://audio_workspace/presets");DirAccess.make_dir_recursive_absolute(directory)
 var error:=ResourceSaver.save(preset,directory.path_join(preset.id+".tres"))
 if error!=OK:notice("Could not save preset.")
 else:library.reload();status.text="Saved editable preset: "+preset.label
func choose_instrument_sample()->void:
 var picker_session:=session;var picker_revision:=session.revision
 var actor:=session.primary_actor();if actor==null:return
 var chosen:=await ActorProjectFilePicker.pick(self,_audio_property(),"Choose sampler source")
 if session!=picker_session or session.revision!=picker_revision:notice("The composition changed while choosing a file. Repeat this action in the intended document.");return
 if chosen.is_empty() or chosen==ActorProjectFilePicker.EMPTY_RESOURCE:return
 session.action("Assign sample",func():
  var patch:Dictionary=actor.values.get(&"instrument",KiwiAudioInstruments.default_instrument("sampler"))
  if str(patch.get("kind",""))=="multisample":var maps:Array=patch.get("multisamples",[]);maps.append({"sample":chosen,"root_pitch":60,"low":0,"high":127,"velocity_low":0,"velocity_high":1});patch.multisamples=maps
  else:patch.sample=chosen
  actor.values[&"instrument"]=patch;actor.values[&"notes_dirty"]=true)
 _render_dirty_notes()
func import_midi()->void:
 var picker_session:=session;var picker_revision:=session.revision
 var property:=ActorProperty.new();property.options={"extensions":PackedStringArray(["mid","midi"])}
 var chosen:=await ActorProjectFilePicker.pick(self,property,"Import MIDI")
 if session!=picker_session or session.revision!=picker_revision:notice("The composition changed while choosing a file. Repeat this action in the intended document.");return
 if chosen.is_empty() or chosen==ActorProjectFilePicker.EMPTY_RESOURCE:return
 var result:=KiwiAudioMIDI.read(chosen)
 if not str(result.get("error","")).is_empty():notice(str(result.error));return
 _apply_midi(result)
func export_midi()->void:
 # This exports editable source patterns, not the audio timeline. Different
 # source maps cannot share a single SMF conductor without rewriting beats.
 var midi:=_midi_source_export()
 _save_midi_export(midi,false)

func export_timeline_midi()->void:
 var owner:=session;var revision:=session.revision
 var dialog:=_window("Export timeline notes as MIDI",Vector2i(690,380))
 _label(dialog.host,"This separate note-only export maps editable notes through timeline placement, source trims, speed, reverse and clip loops into the project conductor. Enabled sustain, step swing/probability/accent/ratchets are projected; raw controllers are omitted. Clipped held notes retrigger at the window edge. Whole-semitone static clip pitch is supported; pitch automation and frozen note tracks are refused.")
 _label(dialog.host,"Audio clips, sample/voice/envelope behavior, effects, fades, mix gain/pan, other automation and routing/sends are not encoded. Direct clip/track mute and routing-aware solo select included notes. MIDI programs are approximations. Up to 15 melodic track/program parts plus shared channel-10 percussion; output is 480 PPQ. Source-pattern export remains available separately.")
 _button(dialog.host,"Prepare timeline notes MIDI",func():
  dialog.window.queue_free()
  if session!=owner or session.revision!=revision:notice("The composition changed. Open timeline MIDI export again.");return
  var problem:=KiwiAudioMIDITimeline.preflight(session.document)
  if not problem.is_empty():notice(problem);return
  var snapshot:=session.document.snapshot()
  jobs.request("timeline_midi",func(job:RefCounted):return {"midi":KiwiAudioMIDITimeline.build(snapshot,job),"owner_session":owner,"revision":revision},revision))

func _save_midi_export(midi:Dictionary,timeline_notes:bool)->void:
 if not str(midi.get("error","")).is_empty():notice(str(midi.error));return
 var picker_session:=session;var picker_revision:=session.revision
 var target:=await ActorProjectResourceSaveDialog.pick(self,"Export timeline notes MIDI" if timeline_notes else "Export source patterns MIDI",session.document.title,"mid",false,PackedStringArray(["mid"]))
 if session!=picker_session or session.revision!=picker_revision:notice("The composition changed while choosing a file. Repeat this action in the intended document.");return
 if target.is_empty():return
 var error:=KiwiAudioMIDI.write(str(target.get("path","")),midi.parts,midi.tempos,midi.meters)
 status.text=("Timeline note placements and conductor saved. Audio processing/routing and raw controllers are excluded." if timeline_notes else "MIDI source notes saved. Project conductor, clip placement, trims, speed and loops are not included.") if error==OK else ("MIDI destination already exists; choose a new filename. Existing contents were preserved." if error==ERR_ALREADY_EXISTS else "MIDI could not be saved: "+error_string(error))

func _midi_source_export()->Dictionary:
 var timing_error:=session.document.midi_timing_error()
 if not timing_error.is_empty():return {"error":timing_error}
 var parts:Array=[];var tempos:Array=[];var meters:Array=[];var timing_key:="";var meter_key:=""
 for actor in session.document.actors:
  var notes:Array=actor.values.get(&"notes",[]);var events:Array=actor.values.get(&"midi_events",[])
  if notes.is_empty() and events.is_empty():continue
  var source_tempos:Array=actor.values.get(&"midi_tempos",[])
  var signature_fallback:=KiwiAudioEditSession.note_source_meter(actor,session.document)
  var source_meters:Array=actor.values.get(&"midi_time_signatures",[{"beat":0.0,"numerator":signature_fallback.x,"denominator":signature_fallback.y}])
  # Preserve the original export behavior for legacy imports. Their missing
  # per-source map cannot safely be reconstructed after several MIDI imports.
  if not actor.values.has(&"midi_tempos") and actor.values.has(&"midi_events"):
   source_tempos=session.document.composer_settings.get("midi_tempos",[])
   source_meters=session.document.composer_settings.get("midi_time_signatures",source_meters)
  var effective:=KiwiAudioTempoMap.scaled_events(source_tempos,KiwiAudioEditSession.note_source_tempo(actor,session.document),float(actor.values.get(&"midi_tempo_scale",1.0)))
  for point:Dictionary in effective:
   if float(point.microseconds)<1.0 or float(point.microseconds)>0xffffff:return {"error":"A scaled MIDI tempo is outside the SMF microsecond range. Use Uniform retime or export audio instead."}
  var meter_events:Array=[]
  for point:Dictionary in source_meters:meter_events.append({"beat":float(point.get("beat",0.0)),"numerator":int(point.get("numerator",4)),"denominator":int(point.get("denominator",4)),"clocks_per_click":int(point.get("clocks_per_click",24)),"thirty_seconds":int(point.get("thirty_seconds",8))})
  var key:=var_to_str(KiwiAudioTempoMap.canonical(effective));var signature:=var_to_str(meter_events)
  if not parts.is_empty() and (key!=timing_key or signature!=meter_key):return {"error":"These source patterns use different tempo or meter maps. Export compatible patterns from separate compositions, or export audio to preserve the timeline timing."}
  timing_key=key;meter_key=signature;tempos=effective;meters=source_meters
  parts.append({"label":actor.display_name,"notes":notes,"instrument":actor.values.get(&"instrument",{}),"events":events,"duration":float(actor.values.get(&"pattern_beats",0.0))})
 if parts.is_empty():return {"error":"There are no MIDI notes or channel events to export."}
 return {"error":"","parts":parts,"tempos":tempos,"meters":meters}
func edit_clip(id:String)->void:
 session.select(id);var clip:=session.document.clip_for_id(id);var actor:=session.document.actor_for_clip(id)
 if clip==null or actor==null:return
 var stream:=_workspace_source(actor.values.get(&"audio"));_wave_clip_id=id
 waveform.open(stream,clip.source_offset,clip.duration*clip.playback_speed)
 bottom.visible=true;bottom.current_tab=0
func _wave_detail(start:float,duration:float)->void:
 if waveform.stream==null:return
 var stream:=waveform.stream;var rate:=waveform.rate;var id:=stream.get_instance_id()
 jobs.request("wave_detail",func(_job:RefCounted):var result:=KiwiAudioSourceCache.decode(stream,rate,start,duration,3);result.start=start;result.source_id=id;return result,0)
func _wave_action(operation:String)->void:
 var actor:=session.document.actor_for_clip(_wave_clip_id)
 if actor==null:notice("Double-click a clip to open its waveform first.");return
 if waveform.selection.y<=waveform.selection.x and operation!="paste":return
 if waveform.channel>=0 and operation in ["cut","paste","trim","time_stretch"]:notice("Choose Stereo for duration-changing edits so both channels stay aligned. Pitch, gain, fades, silence, reverse and repair can edit one channel independently.");return
 if operation in ["time_stretch","pitch_shift"]:
  var dialog:=_window(operation.capitalize().replace("_"," ")+" selection",Vector2i(420,210));var setting:Dictionary={"amount":1.25 if operation=="time_stretch" else 0.0}
  _number(dialog.host,"Duration ratio" if operation=="time_stretch" else "Semitones",setting.amount,0.25 if operation=="time_stretch" else -24,4 if operation=="time_stretch" else 24,0.01 if operation=="time_stretch" else 0.1,func(value:float):setting.amount=value)
  _label(dialog.host,"Processes only the selected samples and preserves the untouched audio as adjacent source clips. Undo restores the original clip. Time stretching changes only this clip's length.")
  _button(dialog.host,"Apply",func():_perform_wave_edit(operation,float(setting.amount));dialog.window.queue_free());return
 if operation in ["amplify","normalize"]:
  var dialog:=_window(operation.capitalize()+" selection",Vector2i(380,170));var setting:Dictionary={"amount":3.0 if operation=="amplify" else -1.0}
  _number(dialog.host,"dB",setting.amount,-60,24,0.1,func(value:float):setting.amount=value)
  _button(dialog.host,"Apply",func():_perform_wave_edit(operation,float(setting.amount));dialog.window.queue_free());return
 _perform_wave_edit(operation,0)
func _perform_wave_edit(operation:String,amount:float)->void:
 if not session.can_edit(_wave_clip_id):notice("The clip's track is locked or unavailable.");return
 var actor:=session.document.actor_for_clip(_wave_clip_id);var clip:=session.document.clip_for_id(_wave_clip_id)
 if actor==null or clip==null:return
 # Keep the selection edit a separate undo transaction from a pending knob drag.
 _finish_control_edits();session.commit()
 var source_stream:=_workspace_source(actor.values.get(&"audio"))
 if source_stream==null:notice("The selected audio source is missing.");return
 var reason:=KiwiAudioRegionEdit.unsupported_reason(clip,actor,operation)
 if not reason.is_empty():notice(reason);return
 var captured_clip:ActorClip=clip.duplicate(false)
 var captured_actor:=ActorData.new();captured_actor.id=actor.id;captured_actor.type_id=actor.type_id;captured_actor.values=actor.values.duplicate(true)
 for animation in actor.animation_tracks:captured_actor.animation_tracks.append(animation.copy_track())
 var rate:=waveform.rate;var selection:=waveform.selection;var channel:=waveform.channel;var clipboard:=_wave_clipboard;var clipboard_rate:=_wave_clipboard_rate
 var owner_id:=session.get_instance_id()
 jobs.request("wave_edit",func(job:RefCounted):
  var result:=KiwiAudioRegionEdit.prepare(captured_clip,captured_actor,source_stream,operation,selection,rate,amount,channel,clipboard,clipboard_rate,job)
  result.owner_id=owner_id
  return result,session.revision)
func set_sample_value_dialog()->void:
 if recorder.recording or _record_busy or waveform.stream==null:notice("Open a waveform and finish recording first.");return
 var owner:=session;var document:=session.document;var revision:=session.revision;var id:=_wave_clip_id
 var frames:=waveform.selection
 if frames.y<=frames.x:frames.y=frames.x+1
 var channel:=waveform.channel;var settings:Dictionary={"value":0.}
 var dialog:=_window("Set sample amplitude",Vector2i(460,230))
 _label(dialog.host,"Set source frames %d–%d on %s. This writes an exact constant value, not a gain adjustment. Untouched source regions remain shared; the edit is undoable."%[frames.x,frames.y,"both channels" if channel<0 else ("left" if channel==0 else "right")])
 _number(dialog.host,"Amplitude",0,-1,1,.0001,func(value:float):settings.value=value)
 _button(dialog.host,"Apply sample value",func():
  if session!=owner or session.document!=document or session.revision!=revision or _wave_clip_id!=id or recorder.recording or _record_busy:notice("The waveform owner changed. Reopen Set sample value.");return
  waveform.selection=frames;waveform.channel=channel;_perform_wave_edit("set_amplitude",float(settings.value));dialog.window.queue_free())

func _spectrogram()->void:
 if waveform.stream==null:return
 if waveform.spectrogram!=null:waveform.show_spectrogram=not waveform.show_spectrogram;waveform.queue_redraw();return
 var stream:=waveform.stream;var start:=waveform.view_start;var duration:=waveform.view_duration
 jobs.request("spectrogram",func(job:RefCounted):return KiwiAudioAnalysis.spectrogram(stream,start,duration,256,128,job),int(stream.get_instance_id()))
func sample_noise_profile()->void:
 if waveform.stream==null or waveform.selection.y<=waveform.selection.x:notice("Open a waveform and select a short noise-only region without speech or music, then choose Sample Noise.");return
 if not session.can_edit(_wave_clip_id):return
 var stream:=waveform.stream;var start:=float(waveform.selection.x)/waveform.rate;var seconds:=float(waveform.selection.y-waveform.selection.x)/waveform.rate;var clip_id:=_wave_clip_id
 jobs.request("noise_profile",func(job:RefCounted):var result:=KiwiAudioAnalysis.noise_profile(stream,start,seconds,job);result.clip_id=clip_id;return result,session.revision)
func analyze_clip()->void:
 if recorder.recording or _record_busy:notice("Stop recording before analyzing dialogue.");return
 var actor:=session.primary_actor();if actor==null:return
 _close_silence_review()
 var problem:=KiwiAudioAnalysis.silence_source_error(actor.values.get(&"audio"))
 if not problem.is_empty():notice(problem);return
 var identity:=_analysis_identity(actor);var value:Variant=actor.values.get(&"audio")
 if value is String:ActorAudio.invalidate(value)
 var clip:=session.primary_clip();var clip_id:=clip.id
 var source_start:=clip.source_offset;var source_seconds:=clip.duration*clip.playback_speed
 if bool(actor.values.get(&"loop",false)):source_start=0.0;source_seconds=-1.0
 if identity.is_empty() or identity!=_analysis_identity(actor):notice("The source changed while opening it. Analyze again.");return
 var owner_id:=session.get_instance_id();var document_id:=session.document.get_instance_id();var revision:=session.revision
 var threshold:=_silence_threshold;var minimum:=_silence_minimum
 jobs.request("analysis",func(job:RefCounted):
  var result:=KiwiAudioAnalysis.analyze_source(value,threshold,minimum,job,source_start,source_seconds)
  result.analysis_method=str(result.get("method","Analysis"))
  result.clip_id=clip_id;result.source_identity=identity;result.owner_id=owner_id;result.document_id=document_id;result.revision=revision;result.threshold=threshold;result.minimum=minimum
  return result,revision)
 bottom.visible=true;bottom.current_tab=5
func _refresh_analysis()->void:
 if not _analysis_result.is_empty() and not _analysis_current():_analysis_result={}
 _clear(analysis_panel)
 var row:=HFlowContainer.new();analysis_panel.add_child(row)
 _button(row,"Analyze selected clip",analyze_clip)
 _button(row,"Review dialogue cleanup…",review_dialogue_batch)
 _layout.menu(row,"More tools",["LEVELS & TIMING",["Measure loudness (LUFS)",measure_loudness],["Align two clips",align_selected],["Match clip levels",match_levels],["Dialogue ducking…",ducking_dialog],"RESTORATION",["Review possible breaths…",review_breaths],["Learn noise profile",sample_noise_profile],"TRANSCRIPT",["Transcribe locally",_optional_tools.transcribe],["Review saved transcript",_optional_tools.review_saved_transcript]])
 var settings:=_layout.fold(analysis_panel,"cleanup_settings","Silence detection settings")
 _number(settings,"Quiet threshold (dBFS)",_silence_threshold,-90,-6,1,func(value:float):_silence_threshold=value;_close_silence_review())
 _number(settings,"Minimum quiet (source s)",_silence_minimum,0.05,10,0.05,func(value:float):_silence_minimum=value;_close_silence_review())
 _number(settings,"Retained pause (timeline s)",_silence_keep,0,10,0.01,func(value:float):_silence_keep=value;_close_silence_review())
 _label(settings,"PCM WAV analysis streams up to 2 hours from a source up to 24 hours. Other formats decode up to 600 seconds / 64 MiB. At most 2048 quiet regions. Quiet detection is not speech or breath recognition.")
 if _analysis_result.has("integrated_lufs"):
  _label(analysis_panel,"Integrated %.1f LUFS · True peak %.1f dBTP · Loudness range %.1f LU (%s)"%[float(_analysis_result.integrated_lufs),float(_analysis_result.true_peak_db),float(_analysis_result.loudness_range),str(_analysis_result.get("method",""))])
 if _analysis_result.is_empty():_label(analysis_panel,"Analyze audio to review transient and silence detections, an estimated tempo, peak level and RMS level. Automatic edits remain undoable.");return
 if not str(_analysis_result.get("error","")).is_empty():_label(analysis_panel,str(_analysis_result.error));return
 var analyzed:=session.document.actor_for_clip(str(_analysis_result.get("clip_id","")))
 _label(analysis_panel,"Analyzed clip: "+(analyzed.display_name if analyzed!=null else "Unavailable"))
 _label(analysis_panel,"Peak %.1f dBFS  ·  RMS %.1f dBFS  ·  Tempo estimate %.1f BPM (confidence %.0f%%)"%[float(_analysis_result.get("peak_db",-120)),float(_analysis_result.get("rms_db",-120)),float(_analysis_result.get("tempo",0)),float(_analysis_result.get("confidence",0))*100])
 if _analysis_result.has("analyzed_start"):
  _label(analysis_panel,"%s · source %.3f–%.3f s. Peak/RMS describe this analyzed range."%[str(_analysis_result.get("analysis_method","Analysis")),float(_analysis_result.analyzed_start),float(_analysis_result.analyzed_end)])
 if bool(_analysis_result.get("tempo_limited",false)):_label(analysis_panel,"Tempo estimation is unavailable for PCM windows longer than 60 seconds; silence and attack detection still cover the displayed range.")
 _label(analysis_panel,"RMS is not integrated LUFS. Tempo estimates may have half/double-time ambiguity; review before applying.")
 _label(analysis_panel,"%d attacks · %d quiet regions"%[(_analysis_result.get("transients",[]) as Array).size(),(_analysis_result.get("silences",[]) as Array).size()])
 var actions:=HFlowContainer.new();analysis_panel.add_child(actions)
 _button(actions,"Add attack markers",_add_attack_markers)
 _button(actions,"Use estimated tempo",func():if float(_analysis_result.get("tempo",0))>0:session.change_tempo(float(_analysis_result.tempo)))
 _button(actions,"Review silence cleanup",func():_apply_silences(_silence_keep))
 _button(actions,"Learn selected noise profile",sample_noise_profile)
 _label(analysis_panel,"Open Review to keep/remove individual quiet regions and choose ripple scope. No edits happen during analysis.")
func _apply_silences(keep:float)->void:
 if automation_recording.active or automation_recording.has_pending():notice("Stop and save or cancel the automation pass before reviewing silence cleanup.");return
 if recorder.recording or _record_busy:notice("Stop recording before reviewing silence cleanup.");return
 if not _analysis_current() or not _analysis_result.has("silences"):notice("Analyze this source before reviewing quiet regions.");return
 if float(_analysis_result.get("threshold",INF))!=_silence_threshold or float(_analysis_result.get("minimum",INF))!=_silence_minimum:notice("Detection settings changed. Analyze again before reviewing.");return
 var prepared:=session.create_silence_plan(str(_analysis_result.clip_id),_analysis_result.silences,float(_analysis_result.get("duration",0)),keep,str(_analysis_result.source_identity))
 if not str(prepared.get("error","")).is_empty():notice(str(prepared.error));return
 var plan:KiwiAudioEditSession.SilencePlan=prepared.plan
 if plan.regions().is_empty():notice("No quiet regions overlap the selected source window.");return
 _close_silence_review()
 _silence_generation+=1;var token:=_silence_generation
 var dialog:=_window("Review dialogue silence cleanup",Vector2i(820,620));var window:Window=dialog.window;var host:VBoxContainer=dialog.host
 window.set_meta("audio_silence_window",true)
 var player:=AudioStreamPlayer.new();window.add_child(player);player.volume_db=-6
 var reviewed_actor:=session.document.actor_for_clip(plan.clip_id());var reviewed_track:=session.document.track_for_clip(plan.clip_id())
 _label(host,"Clip: %s · Track: %s"%[reviewed_actor.display_name,str(reviewed_track.get("name",""))])
 _label(host,"Source quiet threshold %.1f dBFS · minimum %.2f source s · retained pause %.2f timeline s (half on each side)."%[_silence_threshold,_silence_minimum,keep])
 _label(host,"Checked = remove/shorten; unchecked = keep unchanged. Source files stay intact. New interior boundaries receive up to 3 ms fade-in / 5 ms fade-out; existing outer fades remain.")
 var tree:=Tree.new();tree.columns=2;tree.hide_root=true;tree.column_titles_visible=true;tree.set_column_title(0,"Remove");tree.set_column_title(1,"Quiet source interval / time removed");tree.set_column_expand(0,false);tree.set_column_custom_minimum_width(0,80);tree.size_flags_vertical=Control.SIZE_EXPAND_FILL;host.add_child(tree)
 var root:=tree.create_item();var regions:=plan.regions();var cuts:=plan.cuts();var clip:=session.document.clip_for_id(plan.clip_id())
 for i in regions.size():
  var item:=tree.create_item(root);item.set_cell_mode(0,TreeItem.CELL_MODE_CHECK);item.set_editable(0,true);item.set_checked(0,true);item.set_metadata(0,i)
  item.set_text(1,"%d. %.3f–%.3f s / %.3f timeline s"%[i+1,regions[i].start,regions[i].end,(float(cuts[i].end)-float(cuts[i].start))/clip.playback_speed])
 var scope:=OptionButton.new();scope.add_item("Selected clip only; following clips stay fixed");scope.add_item("Ripple following clips on this track after the original end");host.add_child(scope)
 _label(host,"Other tracks, markers, loop ranges, conductor, sections and absolute automation stay fixed in both scopes. Overlapping clips block track ripple.")
 var summary:=_label(host,"");var row:=HFlowContainer.new();host.add_child(row)
 var apply:=_button(row,"Apply reviewed cleanup",_apply_silence_review.bind(token))
 _button(row,"Audition selected raw join",_audition_silence_review.bind(token))
 _button(row,"Stop audition",_stop_silence_audition.bind(token))
 _button(row,"Keep all",func():_set_silence_choices(token,false))
 _button(row,"Remove all",func():_set_silence_choices(token,true))
 _button(row,"Cancel",_close_silence_review.bind(token))
 _label(host,"Audition is an isolated, up-to-0.7-second source join at clip speed, bypassing clip gain/pan, track/master effects and pitch correction. It is not an exact mix preview.")
 _silence_review={"token":token,"plan":plan,"window":window,"tree":tree,"scope":scope,"summary":summary,"apply":apply,"player":player,"audition":0}
 tree.item_edited.connect(_refresh_silence_review.bind(token));scope.item_selected.connect(func(_index:int):_refresh_silence_review(token))
 window.tree_exiting.connect(_close_silence_review.bind(token))
 window.window_input.connect(func(event:InputEvent):if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:_close_silence_review(token))
 _refresh_silence_review(token)

func review_breaths()->void:
 if recorder.recording or _record_busy or session._before!=null or automation_recording.active or automation_recording.has_pending():notice("Finish the current recording/edit first.");return
 var clip:=session.primary_clip();var actor:=session.primary_actor()
 if clip==null or actor==null:return
 if not session.can_edit(clip.id) or bool(actor.values.get(&"reverse",false)) or bool(actor.values.get(&"loop",false)):notice("Choose an unlocked forward, non-looped dialogue clip.");return
 if not (actor.values.get(&"automation",{}).get("volume_db",[]) as Array).is_empty():notice("Breath review creates clip gain automation. Bake or remove the existing gain curve first so its interpolation is not changed.");return
 var source_value:Variant=actor.values.get(&"audio");var start:=clip.source_offset;var seconds:=clip.duration*clip.playback_speed;var owner:=session.get_instance_id();var document:=session.document.get_instance_id();var id:=clip.id;var identity:=_analysis_identity(actor)
 jobs.request("breath_review",func(job:RefCounted):
  var result:=preload("res://Workspaces/AudioWorkspace/audio_restoration.gd").breath_candidates(source_value,start,seconds,job)
  result.owner=owner;result.document=document;result.clip_id=id;result.identity=identity;return result,session.revision)

func _breath_review_ready(result:Dictionary)->void:
 if int(result.owner)!=session.get_instance_id() or int(result.document)!=session.document.get_instance_id():return
 var clip:=session.document.clip_for_id(str(result.clip_id));var actor:=session.document.actor_for_clip(str(result.clip_id))
 if clip==null or actor==null or _analysis_identity(actor)!=str(result.identity):return
 var owner:=session;var document:=session.document;var revision:=session.revision
 var dialog:=_window("Review possible breath/noise regions",Vector2i(720,540));var settings:Dictionary={"reduction":9.}
 _label(dialog.host,"Heuristic candidates: short, low-level, noise-like passages—not speech recognition. Sibilants and room noise can also match. Nothing is selected automatically. Audition each candidate and check only breaths you want reduced. Source files are untouched; gain automation remains editable.")
 _number(dialog.host,"Reduction (dB)",9,0,30,.5,func(value:float):settings.reduction=value)
 var tree:=Tree.new();tree.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(tree);tree.hide_root=true;var root:=tree.create_item();var rows:Array=[]
 for region in result.regions:
  var item:=tree.create_item(root);item.set_cell_mode(0,TreeItem.CELL_MODE_CHECK);item.set_editable(0,true);item.set_checked(0,false);item.set_text(0,"%.3f–%.3f source seconds"%[float(region.start),float(region.end)]);rows.append(item)
 if rows.is_empty():_label(dialog.host,"No candidates matched the conservative detector. Use waveform gain automation to edit other breaths manually.")
 var actions:=HFlowContainer.new();dialog.host.add_child(actions)
 _button(actions,"Audition selected source region",func():
  if session!=owner or session.document!=document or session.revision!=revision:return
  var index:=rows.find(tree.get_selected())
  if index<0:return
  var region:Dictionary=result.regions[index];var source_stream:=_workspace_source(actor.values.get(&"audio"))
  jobs.request("audition",func(_job:RefCounted):
   var decoded:=KiwiAudioSourceCache.decode(source_stream,24000,float(region.start),float(region.end)-float(region.start),1.)
   if not str(decoded.get("error","")).is_empty():return decoded
   return {"stream":KiwiAudioSourceCache.to_wav(decoded.samples,24000)},0))
 _button(actions,"Reduce checked regions · one Undo",func():
  if session!=owner or session.document!=document or session.revision!=revision or not session.can_edit(clip.id) or _analysis_identity(actor)!=str(result.identity):notice("The dialogue changed. Review it again.");return
  var regions:Array=[]
  for i in rows.size():
   if rows[i].is_checked(0):regions.append(Vector2((float(result.regions[i].start)-clip.source_offset)/clip.playback_speed,(float(result.regions[i].end)-clip.source_offset)/clip.playback_speed))
  if regions.is_empty():return
  var original:Array=actor.values.get(&"automation",{}).get("volume_db",[]).duplicate(true);var times:Dictionary={0.:true,clip.duration:true}
  for point in original:times[float(point.time)]=true
  for region in regions:
   var edge:=minf(.025,(region.y-region.x)*.25)
   for time in [region.x,region.x+edge,region.y-edge,region.y]:times[time]=true
  if times.size()>10000:notice("The combined automation curve would exceed 10,000 points.");return
  var sorted:=times.keys();sorted.sort();var points:Array=[]
  for time in sorted:
   var amount:=0.
   for region in regions:
    var edge:=minf(.025,(region.y-region.x)*.25);amount=maxf(amount,minf(clampf((time-region.x)/edge,0,1),clampf((region.y-time)/edge,0,1)))
   points.append({"time":time,"value":KiwiAudioEditSession.automation_value(original,time,float(actor.values.get(&"volume_db",0)))-float(settings.reduction)*amount,"curve":"linear"})
  session.action("Reviewed breath reduction",func():var curves:Dictionary=actor.values.get(&"automation",{}).duplicate(true);curves.volume_db=points;actor.values[&"automation"]=curves)
  preview_player.stop();dialog.window.queue_free())

func review_dialogue_batch()->void:
 if recorder.recording or _record_busy or automation_recording.active or automation_recording.has_pending() or session._before!=null:notice("Finish recording or the current adjustment before dialogue review.");return
 var ids:=session.selected_ids.duplicate()
 for id in ids:
  var reason:=session._silence_reason(id)
  if not reason.is_empty():notice(reason);return
 var snapshot:=session.document.snapshot();var owner:=session.get_instance_id();var document:=session.document.get_instance_id();var revision:=session.revision
 var threshold:=_silence_threshold;var minimum:=_silence_minimum
 jobs.request("dialogue_batch",func(job:RefCounted):
  var result:=preload("res://Workspaces/AudioWorkspace/audio_dialogue_batch.gd").analyze(snapshot,ids,threshold,minimum,job)
  result.owner=owner;result.document=document;return result,revision)

func _dialogue_batch_ready(result:Dictionary)->void:
 if int(result.get("owner",0))!=session.get_instance_id() or int(result.get("document",0))!=session.document.get_instance_id():return
 var prepared:=preload("res://Workspaces/AudioWorkspace/audio_dialogue_batch.gd").prepare(session,result.entries,_silence_keep)
 if not str(prepared.get("error","")).is_empty():notice(prepared.error);return
 var plans:Array=prepared.plans;var owner:=session;var document:=session.document;var revision:=session.revision
 var dialog:=_window("Dialogue review queue",Vector2i(840,640));var host:VBoxContainer=dialog.host
 _label(host,"Review every removal before applying. Sources stay intact. Crossfades overlap real quiet handles (up to 100 ms); processed clips must be rendered first.")
 var settings:Dictionary={"scope":"clip","overlap":.01}
 _choice(host,"Ripple policy",["Selected clips only","Following clips on the same tracks"],"Selected clips only",func(value:String):settings.scope="track_following" if value.begins_with("Following") else "clip")
 _number(host,"Overlap crossfade (ms)",10,0,100,1,func(value:float):settings.overlap=value/1000.)
 var tree:=Tree.new();tree.columns=3;tree.set_column_titles_visible(true);tree.set_column_title(0,"Remove / clip");tree.set_column_title(1,"Source start");tree.set_column_title(2,"Source end");tree.size_flags_vertical=Control.SIZE_EXPAND_FILL;host.add_child(tree)
 var root:=tree.create_item();tree.hide_root=true;var rows:Array=[]
 for i in plans.size():
  var parent:=tree.create_item(root);parent.set_text(0,str(result.entries[i].label));var group:Array=[]
  for region in plans[i].regions():
   var item:=tree.create_item(parent);item.set_cell_mode(0,TreeItem.CELL_MODE_CHECK);item.set_editable(0,true);item.set_checked(0,true);item.set_text(0,"Remove quiet region");item.set_text(1,"%.3f"%float(region.start));item.set_text(2,"%.3f"%float(region.end));group.append(item)
  rows.append(group)
 var summary:=Label.new();summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;host.add_child(summary)
 _button(host,"Apply reviewed queue · one Undo",func():
  if session!=owner or session.document!=document or session.revision!=revision or recorder.recording or _record_busy or automation_recording.active or automation_recording.has_pending():summary.text="The document changed. Close and review again.";return
  var choices:Array=[]
  for group in rows:
   var chosen:Array=[]
   for i in group.size():
    if group[i].is_checked(0):chosen.append(i)
   choices.append(chosen)
  var applied:=preload("res://Workspaces/AudioWorkspace/audio_dialogue_batch.gd").apply(session,plans,choices,str(settings.scope),float(settings.overlap))
  if not str(applied.get("error","")).is_empty():summary.text=applied.error;return
  status.text="Dialogue queue removed %.3f seconds with overlapping joins."%float(applied.get("removed",0));dialog.window.queue_free())

func _silence_review_current(token:int)->bool:
 return not _silence_review.is_empty() and int(_silence_review.get("token",-1))==token and is_inside_tree() and is_visible_in_tree() and not recorder.recording and not _record_busy and not automation_recording.active and not automation_recording.has_pending() and session.primary_clip()!=null and session.primary_clip().id==_silence_review.plan.clip_id() and is_instance_valid(_silence_review.window) and not _silence_review.window.is_queued_for_deletion() and _silence_review.plan.current(session)

func _silence_choices()->Array:
 var result:Array=[]
 if _silence_review.is_empty():return result
 var row:TreeItem=_silence_review.tree.get_root().get_first_child()
 while row!=null:
  if row.is_checked(0):result.append(int(row.get_metadata(0)))
  row=row.get_next()
 return result

func _set_silence_choices(token:int,value:bool)->void:
 if not _silence_review_current(token):_close_silence_review(token);return
 var row:TreeItem=_silence_review.tree.get_root().get_first_child()
 while row!=null:row.set_checked(0,value);row=row.get_next()
 _refresh_silence_review(token)

func _refresh_silence_review(token:int)->void:
 if not _silence_review_current(token):_close_silence_review(token);return
 _stop_silence_audition(token)
 var scope:="track_following" if _silence_review.scope.selected==1 else "clip"
 var review:=session.preview_silence_plan(_silence_review.plan,_silence_choices(),scope)
 var error:=str(review.get("error",""));_silence_review.apply.disabled=not error.is_empty() or float(review.get("removed",0))<=0.000001
 _silence_review.summary.text=error if not error.is_empty() else "Remove %.3f s · keep %.3f s · move %d following clip(s). Apply creates one Undo action."%[float(review.removed),float(review.remaining),(review.moved_ids as Array).size()]

func _apply_silence_review(token:int)->void:
 if not _silence_review_current(token):_close_silence_review(token);notice("The cleanup plan changed or was cancelled. Review again.");return
 var scope:="track_following" if _silence_review.scope.selected==1 else "clip"
 var result:=session.apply_silence_plan(_silence_review.plan,_silence_choices(),scope)
 if not str(result.get("error","")).is_empty():_silence_review.summary.text=str(result.error);return
 _close_silence_review(token)
 if bool(result.get("changed",false)):_analysis_result={};status.text="Removed %.3f seconds with one Undo action; original sources are preserved."%float(result.removed)

func _audition_silence_review(token:int)->void:
 if not _silence_review_current(token):_close_silence_review(token);return
 var row:TreeItem=_silence_review.tree.get_selected()
 if row==null:_silence_review.summary.text="Select a checked region to audition its proposed join.";return
 var boundary:=session.silence_boundary(_silence_review.plan,_silence_choices(),int(row.get_metadata(0)))
 if not str(boundary.get("error","")).is_empty():_silence_review.summary.text=str(boundary.error);return
 _silence_review.audition=int(_silence_review.audition)+1;var audition:=int(_silence_review.audition)
 _silence_review.player.stop();_silence_review.player.stream=null
 _cancel_exact_playback();playback.stop(false);preview_player.stop();asset_file_preview.close_file()
 if not _silence_review_current(token):return
 jobs.request("silence_audition",func(job:RefCounted):
  var problem:=KiwiAudioAnalysis.silence_source_error(boundary.source)
  if not problem.is_empty():return {"error":problem,"audition":audition}
  if boundary.source is String:ActorAudio.invalidate(boundary.source)
  var result:=KiwiAudioAnalysis.silence_boundary_audio(boundary.source,boundary,job);result.audition=audition;return result,token)

func _silence_audition_completed(token:int,result:Dictionary)->void:
 if not _silence_review_current(token) or int(result.get("audition",-1))!=int(_silence_review.get("audition",-2)):return
 if not str(result.get("error","")).is_empty():_silence_review.summary.text=str(result.error);return
 var player:AudioStreamPlayer=_silence_review.player;player.stream=result.get("stream");player.pitch_scale=float(result.get("speed",1));player.play()

func _stop_silence_audition(token:int)->void:
 if _silence_review.is_empty() or int(_silence_review.get("token",-1))!=token:return
 _silence_review.audition=int(_silence_review.audition)+1;jobs.cancel_kind("silence_audition")
 _silence_review.player.stop();_silence_review.player.stream=null

func _close_silence_review(token:int=-1)->void:
 if _silence_review.is_empty() or token>=0 and int(_silence_review.get("token",-1))!=token:return
 var context:=_silence_review;_silence_review={};_silence_generation+=1
 context.plan.cancel();jobs.cancel_kind("silence_audition")
 if is_instance_valid(context.player):context.player.stop();context.player.stream=null
 if is_instance_valid(context.window) and not context.window.is_queued_for_deletion():context.window.queue_free()

func _smart_track_problem(track_id:String)->String:
 var track:=session.document.track_for_id(track_id)
 if track.is_empty():return "The target track is no longer available. No edits were applied."
 if bool(track.get("locked",false)) or track.has("frozen_track") or track.has("frozen_source"):return "Unlock or unfreeze the target track before this edit. No edits were applied."
 if KiwiAudioAutomationLane.is_lane(track):return "Choose an audio or instrument track as the edit target."
 return ""
func _alignment_problem(ids:Array)->String:
 if ids.size()!=2:return "Select two clips. The second will be aligned to the first."
 for id in ids:
  var clip:=session.document.clip_for_id(str(id));var actor:=session.document.actor_for_clip(str(id))
  if clip==null or actor==null:return "An alignment source is no longer available."
  if clip.duration>300:return "Split clips longer than five minutes before processed alignment."
 return _smart_track_problem(str(session.document.track_for_clip(str(ids[1])).get("id","")))
func align_selected()->void:
 var ids:=session.selected_ids.duplicate();var problem:=_alignment_problem(ids)
 if not problem.is_empty():notice(problem);return
 var owner_id:=session.get_instance_id()
 if recorder.recording or _record_busy:notice("Finish recording before processed alignment.");return
 var snapshot:=session.document.snapshot();var first:=snapshot.clip_for_id(ids[0]);var second:=snapshot.clip_for_id(ids[1])
 jobs.request("alignment",func(job:RefCounted):
  var result:=preload("res://Workspaces/AudioWorkspace/audio_processed_analysis.gd").alignment(snapshot,ids,job)
  result.clip_id=second.id;result.base=first.start_time;result.ids=ids;result.owner_id=owner_id;return result,session.revision)
func match_levels()->void:
 if recorder.recording or _record_busy:notice("Finish recording before processed RMS matching.");return
 _finish_control_edits();session.commit()
 var ids:=session.selected_ids.duplicate();var owner_id:=session.get_instance_id()
 for id in ids:
  var problem:=_smart_track_problem(str(session.document.track_for_clip(id).get("id","")))
  if not problem.is_empty():notice(problem);return
  var actor:=session.document.actor_for_clip(id)
  if not (actor.values.get(&"automation",{}).get("volume_db",[]) as Array).is_empty():notice("Render or remove clip gain automation before matching its base gain.");return
 if ids.is_empty():return
 var snapshot:=session.document.snapshot()
 jobs.request("match_levels",func(job:RefCounted):
  var result:Array=[]
  for id in ids:
   var analysis:=preload("res://Workspaces/AudioWorkspace/audio_processed_analysis.gd").rms(snapshot,id,job)
   if not str(analysis.get("error","")).is_empty():return {"error":str(analysis.error)}
   result.append({"id":id,"db":float(analysis.get("rms_db",-120)),"base_db":float(snapshot.actor_for_clip(id).values.get(&"volume_db",0))})
  return {"clips":result,"owner_id":owner_id,"processed":true},session.revision)
 status.text="Matching isolated processed clips to -20 dBFS RMS, including routing/effects (up to five minutes each). Nonlinear chains may require remeasurement."
func ducking_dialog()->void:
 var owner:=session;var document:=session.document;var revision:=session.revision
 var dialog:=_window("Dialogue ducking",Vector2i(480,340));var labels:Array=[];var ids:Array=[]
 for track in session.document.tracks:labels.append(str(track.name));ids.append(str(track.id))
 if labels.size()<2:dialog.window.queue_free();notice("Create dialogue and background tracks first.");return
 var speech:=_choice(dialog.host,"Dialogue",labels,str(labels[0]),func(_value:String):pass);var music:=_choice(dialog.host,"Background",labels,str(labels[1]),func(_value:String):pass)
 var settings:Dictionary={"amount":12.0,"threshold":-35.0,"attack":0.08,"release":0.35}
 for info in [["amount",0,30,0.1],["threshold",-70,-10,0.1],["attack",0.01,2,0.01],["release",0.02,4,0.01]]:
  var key:=str(info[0]);_number(dialog.host,key.capitalize(),settings[key],info[1],info[2],info[3],func(value:float):settings[key]=value)
 _button(dialog.host,"Create editable volume automation",func():
  if session!=owner or session.document!=document or session.revision!=revision:notice("The composition changed. Reopen Dialogue Ducking in the intended document.");return
  var speech_id:=str(ids[speech.selected]);var background_id:=str(ids[music.selected])
  if speech_id==background_id:notice("Choose two different tracks.");return
  var problem:=_smart_track_problem(background_id)
  if not problem.is_empty():notice(problem);return
  var owner_id:=session.get_instance_id()
  var captures:Array=[]
  for i in session.document.clips.size():
   if str(session.document.actors[i].values.get(&"track_id",""))==speech_id:captures.append({"clip":session.document.clips[i].duplicate(false),"stream":_workspace_source(session.document.actors[i].values.get(&"audio"))})
  var base:=float(session.document.track_for_id(background_id).get("volume_db",0))
  jobs.request("ducking",func(job:RefCounted):
   var points:Array=[]
   for capture in captures:
    var analysis:=KiwiAudioAnalysis.analyze(capture.stream,settings.threshold,0.1,job);var envelope:PackedFloat32Array=analysis.get("envelope",PackedFloat32Array());var active:=false
    for frame in envelope.size():
     var local:=frame*0.01
     if local<capture.clip.source_offset or local>capture.clip.source_offset+capture.clip.duration*capture.clip.playback_speed:continue
     var now:=envelope[frame]>db_to_linear(settings.threshold);var time:float=capture.clip.start_time+(local-capture.clip.source_offset)/capture.clip.playback_speed
     if now and not active:
      points.append({"time":maxf(0,time-settings.attack),"value":base});points.append({"time":time,"value":base-settings.amount})
     if not now and active:
      points.append({"time":time,"value":base-settings.amount});points.append({"time":time+settings.release,"value":base})
     active=now
    if active:
     points.append({"time":capture.clip.start_time+capture.clip.duration,"value":base-settings.amount});points.append({"time":capture.clip.start_time+capture.clip.duration+settings.release,"value":base})
   points.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.time)<float(b.time))
   return {"track":background_id,"points":points,"owner_id":owner_id},session.revision)
  dialog.window.queue_free())
func automation_dialog()->void:
 if session.primary_clip()==null and KiwiAudioAutomationLane.is_lane(session.document.track_for_id(session.selected_track)):automation_lane_editor(session.selected_track);return
 var dialog:=_window("Automation and modulation",Vector2i(720,580))
 var editor:=KiwiAudioAutomationCanvas.new();editor.session=session
 var actor:=session.primary_actor();var clip:=session.primary_clip()
 editor.owner_kind="clip" if actor!=null else ("track" if not session.selected_track.is_empty() else "master")
 editor.owner_id=clip.id if clip!=null else session.selected_track;editor.duration=maxf(1,clip.duration if clip!=null else session.document.duration())
 _label(dialog.host,"Click to add a point; drag to move; right-click to remove. Clip time is relative to its start. Track/master time is absolute. Modulation becomes editable points shared by preview and export.")
 var row:=HFlowContainer.new();dialog.host.add_child(row)
 var parameters:Array=["volume_db"] if editor.owner_kind=="master" else (["volume_db","pan","pitch"] if editor.owner_kind=="clip" else ["volume_db","pan"])
 _choice(row,"Parameter",parameters,"volume_db",func(value:String):editor.parameter=value;editor.minimum=0.25 if value=="pitch" else (-1 if value=="pan" else -60);editor.maximum=4 if value=="pitch" else (1 if value=="pan" else 12);editor.queue_redraw())
 _choice(row,"Curve",["linear","smooth","hold"],"linear",editor.set_curve)
 _number(row,"View seconds",editor.duration,0.1,3600,0.1,func(value:float):editor.duration=value;editor.queue_redraw())
 editor.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(editor)
 var settings:Dictionary={"shape":"sine","sync":true,"beats":1.0,"rate":1.0,"center":0.0,"depth":0.5,"seed":1}
 var modulation:=HFlowContainer.new();dialog.host.add_child(modulation)
 _choice(modulation,"Modulator",["sine","triangle","saw","square","random step","envelope"],"sine",func(value:String):settings.shape=value)
 _check(modulation,"Beat sync",true,func(value:bool):settings.sync=value)
 _number(modulation,"Beats/cycle",1,0.0625,32,0.0625,func(value:float):settings.beats=value)
 _number(modulation,"Rate (Hz)",1,0.01,20,0.01,func(value:float):settings.rate=value)
 _number(modulation,"Center",0,-60,12,0.1,func(value:float):settings.center=value)
 _number(modulation,"Depth",0.5,0,60,0.1,func(value:float):settings.depth=value)
 _number(modulation,"Seed",1,0,2147483647,1,func(value:float):settings.seed=int(value))
 var actions:=HFlowContainer.new();dialog.host.add_child(actions)
 _button(actions,"Generate curve",func():editor.modulate(settings));_button(actions,"Clear curve",editor.clear_points)
 _button(actions,"Show in timeline lane",func():_show_automation_editor_in_lane(editor);dialog.window.queue_free())
 _label(dialog.host,"Gain and pan curves are sample-evaluated at export. Clip pitch is a ratio (1 = unchanged), requiring FFmpeg with Rubber Band for exact rendering. Open an effect’s Automation button for its supported parameter curves. Instrument modulation is baked with its note pattern.")
func send_dialog()->void:
 if KiwiAudioAutomationLane.is_lane(session.document.track_for_id(session.selected_track)):notice("Automation lanes do not carry audio sends. Select an audio or group track.");return
 var track:=session.document.track_for_id(session.selected_track);if track.is_empty():return
 if bool(track.get("locked",false)):notice("Unlock this track to edit its sends.");return
 var dialog:=_window("Post-fader sends",Vector2i(540,420));var labels:Array=[];var ids:Array=[]
 for other in session.document.tracks:
  if str(other.id)!=str(track.id) and not KiwiAudioAutomationLane.is_lane(other):labels.append(str(other.name));ids.append(str(other.id))
 for index in (track.get("sends",[]) as Array).size():
  var send:Dictionary=track.sends[index];var row:=HFlowContainer.new();dialog.host.add_child(row)
  var destination:=session.document.track_for_id(str(send.get("target","")));_label(row,str(destination.get("name","Missing track")))
  _number(row,"dB",float(send.get("volume_db",-12)),-60,6,0.1,func(db:float):_edit("Adjust send",func():send.volume_db=db))
  _button(row,"Remove",func():session.action("Remove send",func():track.sends.remove_at(index));dialog.window.queue_free();send_dialog())
 if not labels.is_empty():
  var choice:=_choice(dialog.host,"Destination",labels,str(labels[0]),func(_value:String):pass);var value:Dictionary={"gain":-12.0}
  _number(dialog.host,"Send (dB)",value.gain,-60,6,0.1,func(db:float):value.gain=db)
  _button(dialog.host,"Add send",func():
   var sends:Array=(track.get("sends",[]) as Array).duplicate(true);sends.append({"target":ids[choice.selected],"volume_db":value.gain})
   if not session.set_track_value(track.id,"sends",sends):notice("Routing would create feedback.")
   dialog.window.queue_free();send_dialog())
 else:_label(dialog.host,"Add a group or destination track before creating a send.")
 _label(dialog.host,"Post-fader sends are included in exact rendered preview and export. Native live monitoring uses the main output route.")
func loop_selection()->void:
 if recorder.recording or _record_busy:notice("Stop the take before changing its transport loop.");return
 var start:=canvas.time_selection.x;var end:=canvas.time_selection.y
 if end<=start:
  start=INF;end=0
  for id in session.selected_ids:
   var clip:=session.document.clip_for_id(id);start=minf(start,clip.start_time);end=maxf(end,clip.start_time+clip.duration)
 if not is_finite(start) or end<=start:return
 session.action("Loop selection",func():session.document.loop_start=start;session.document.loop_end=end;session.document.loop_enabled=true)
 playback.loop_enabled=true;_automation_seek(start,false)
func add_marker()->void:
 _name_dialog("Add cue marker","Cue",func(label:String):session.action("Add marker",func():session.document.markers.append({"id":ActorData.new_id(),"time":playback.position,"name":label})))
func fit_timeline()->void:
 canvas.scroll_time=0;canvas.zoom=clampf((canvas.size.x-KiwiAudioTimelineCanvas.LABEL_WIDTH)/maxf(1,session.document.duration()+0.5),8,1000);canvas.queue_redraw()
func _requested_recording_preferences()->Dictionary:
 var preferences:=recorder.requested_preferences()
 var config:=ConfigFile.new()
 if config.load(RECORDING_OPTIONS_PATH)==OK and bool(config.get_value("backing","override",false)):
  preferences.monitor_timeline=bool(config.get_value("backing","monitor",false))
  preferences.record_timeline=bool(config.get_value("backing","include",false))
 return preferences

func _save_recording_backing(override_shared:bool,monitor:bool,include:bool)->bool:
 # Workspace-only preference: the shared Scene/screen recorder settings stay intact.
 var config:=ConfigFile.new()
 config.set_value("backing","override",override_shared)
 config.set_value("backing","monitor",monitor);config.set_value("backing","include",include)
 var error:=config.save(RECORDING_OPTIONS_PATH)
 if error!=OK:notice("Could not save backing preferences: "+error_string(error));return false
 return true

func recording_options()->void:
 var dialog:=_window("Recording and takes",Vector2i(640,620))
 var preferences:=_requested_recording_preferences()
 var route:Dictionary={"monitor":ActorAudioRecorder.monitors_timeline(preferences),"include":bool(preferences.get("record_timeline",false))}
 _heading(dialog.host,"Backing for the next take")
 _check(dialog.host,"Hear backing while recording",bool(route.monitor),func(enabled:bool):route.monitor=enabled;_save_recording_backing(true,bool(route.monitor),bool(route.include)))
 _check(dialog.host,"Include backing in take",bool(route.include),func(enabled:bool):route.include=enabled;_save_recording_backing(true,bool(route.monitor),bool(route.include)))
 _button(dialog.host,"Follow shared recording dropdown",func():
  if _save_recording_backing(false,false,false):dialog.window.queue_free();recording_options())
 _label(dialog.host,"Dry overdub: select Microphone and turn off System in the shared dropdown, then enable Hear backing and disable Include backing. Use headphones to avoid acoustic bleed. Microphone monitoring stays muted. Changes apply to the next take.")
 _number(dialog.host,"Countdown (s)",_countdown,0,10,1,func(value:float):_countdown=int(value))
 _number(dialog.host,"Latency (ms)",_latency_ms,-1000,1000,1,func(value:float):_latency_ms=value)
 _check(dialog.host,"Loop recording into takes",_record_loop,_set_record_loop)
 _label(dialog.host,"Microphone, System, input device/gain and mono/stereo still use the shared recording dropdown. Until you change the backing controls, its Timeline selection both plays and records backing as before. Backing controls here are saved separately for Audio Workspace.")
 _label(dialog.host,"Backing streams from a private PCM file (512 MiB limit). Capture writes checkpointed WAVs with a 2 MiB queue and 2 GiB limit per source; Stop mixes files on the background worker without loading whole takes. Separate inputs remain available under Takes → Recover disk takes. FFmpeg is needed to combine sources. Edits during preparation cancel startup; capture uses the prepared arrangement. Timeline mixes and monitored loop takes start muted to avoid double playback. Microphone monitoring stays muted; loop device restarts are not gapless. Disk usage is not a process-wide or all-takes quota.")
 _button(dialog.host,"Show takes",func():dialog.window.queue_free();take_dialog())
func toggle_recording(restart_next:bool=false)->void:
 _close_silence_review()
 _finish_automation_pass("Audio recording requested")
 if _record_busy:
  _cancel_record_preparation()
  return
 if recorder.recording:
  _finish_recorded_take(restart_next)
  return
 var track:=session.document.track_for_id(session.selected_track)
 if track.is_empty() or bool(track.get("locked",false)) or KiwiAudioAutomationLane.is_lane(track):notice("Select an unlocked audio or instrument track before recording.");return
 _record_preferences=_requested_recording_preferences()
 var routing_error:=ActorAudioRecorder.preference_error(_record_preferences)
 if not routing_error.is_empty():notice(routing_error);return
 _finish_control_edits();session.commit()
 _record_generation+=1
 var token:=_record_generation
 _record_cancel_requested=false;_record_failure="";_record_busy=true;_record_phase="countdown"
 _record_session=session;_record_track=session.selected_track;_record_elapsed=0
 _record_owner_document=session.document;_record_document=session.document.snapshot()
 _record_signature=KiwiAudioRecordingPrepare.signature(session.document)
 _record_start=playback.position
 _record_cycle_duration=0.0
 if _record_loop and session.document.loop_end>session.document.loop_start:
  _record_start=session.document.loop_start
  _record_cycle_duration=session.document.loop_end-session.document.loop_start
 _cancel_exact_playback();playback.stop(false);preview_player.stop()
 if ActorAudioRecorder.backing_requested(_record_preferences) and _requires_exact_preview():
  if _record_cycle_duration>0 and _record_loop_preview!=null and _record_loop_signature==_record_signature and _record_loop_preview.valid():
   _begin_record_capture(token,_record_loop_preview);return
  _record_loop_preview=null;_record_loop_signature=""
  _record_phase="preparing";record_button.text="Cancel preparation";status.text="Preparing processed timeline before recording..."
  var snapshot:=_record_document;var at:=_record_start;var until:=at+_record_cycle_duration if _record_cycle_duration>0 else -1.0
  jobs.request("record_prepare",func(job:RefCounted):return KiwiAudioRecordingPrepare.prepare(snapshot,at,until,job),token)
 else:
  _record_loop_preview=null;_record_loop_signature=""
  _begin_record_capture(token,null)

func _record_request_owned(token:int)->bool:
 return token==_record_generation and _record_session==session and _record_owner_document==session.document and not _record_cancel_requested and is_inside_tree() and is_visible_in_tree()

func _record_request_current(token:int)->bool:
 return _record_request_owned(token) and KiwiAudioRecordingPrepare.signature(session.document)==_record_signature

func _abort_record_preparation(token:int,message:String="")->void:
 if token!=_record_generation:return
 playback._track_effects.clear()
 if _record_prepared!=null:playback.stop(false)
 _record_prepared=null
 _record_loop_preview=null;_record_loop_signature=""
 _record_busy=false;_record_phase="idle";_record_session=null;_record_document=null;_record_owner_document=null;_record_preferences={};_record_signature=""
 record_button.text="● Record"
 if is_inside_tree():playback.exact_required=_requires_exact_preview();playback.set_document(session.document)
 if not message.is_empty() and not _record_cancel_requested:notice(message)

func _cancel_record_preparation()->void:
 _record_cancel_requested=true
 if _record_prepared!=null:playback.stop(false)
 _record_prepared=null
 _record_loop_preview=null;_record_loop_signature=""
 if _record_phase in ["preparing","priming","countdown"]:
  jobs.cancel_kind("record_prepare")
  _record_generation+=1
  _record_busy=false;_record_phase="idle";_record_session=null;_record_document=null;_record_owner_document=null;_record_preferences={};_record_signature=""
  record_button.text="● Record";status.text="Recording preparation cancelled."
  if is_inside_tree():playback.exact_required=_requires_exact_preview();playback.set_document(session.document)
 elif _record_phase=="starting":
  # Keep startup owned/busy until the asynchronous device operation returns.
  # A cancelled startup is stopped and discarded before accepting another take.
  status.text="Cancelling recording device startup..."

func _record_preparation_finished(token:int,data:Dictionary)->void:
 # A stale/discarded result releases its backing when the result goes away.
 if token!=_record_generation or _record_phase!="preparing":return
 if not _record_request_current(token):_abort_record_preparation(token,"The arrangement changed while preparing recording. Start the take again.");return
 var error:=str(data.get("error",""));var backing:=data.get("backing") as KiwiAudioRecordingPrepare.Backing
 if not error.is_empty() or backing==null or not backing.valid():
  _abort_record_preparation(token,error if not error.is_empty() else "No valid processed timeline backing was prepared.");return
 if _record_cycle_duration>0:_record_loop_preview=backing;_record_loop_signature=_record_signature
 _begin_record_capture(token,backing)

func _begin_record_capture(token:int,prepared:KiwiAudioRecordingPrepare.Backing)->void:
 if token!=_record_generation:return
 _record_prepared=prepared
 # A suspended coroutine must not retain the lease after its workspace is
 # destroyed. Keep the strong owner in the workspace/reader, pass only its ID.
 _begin_record_capture_owned(token,prepared.get_instance_id() if prepared!=null else 0)

func _begin_record_capture_owned(token:int,prepared_id:int)->void:
 if not _record_request_current(token):_abort_record_preparation(token);return
 var preferences:=_record_preferences.duplicate(true)
 if prepared_id!=0:
  if (_record_prepared==null or _record_prepared.get_instance_id()!=prepared_id or not _record_prepared.valid()):_abort_record_preparation(token,"The prepared backing changed or disappeared. Prepare the take again.");return
  _record_phase="priming";record_button.text="Cancel buffering"
  playback.exact_required=true;playback.set_document(_record_document)
  var prime_error:=playback.prepare_recording_file(_record_prepared.path,_record_start,_record_prepared.info,_record_prepared)
  if not prime_error.is_empty():_abort_record_preparation(token,prime_error);return
  var signature_check_at:=0
  while not playback.recording_file_ready(_record_prepared):
   var check_signature:=Time.get_ticks_msec()>=signature_check_at
   if not _record_request_owned(token) or not playback.file_preview.active or (check_signature and not _record_request_current(token)):
    _abort_record_preparation(token,"Recording preparation changed or stopped before the PCM buffer was ready.");return
   if check_signature:signature_check_at=Time.get_ticks_msec()+250
   await get_tree().process_frame
 if not _record_request_current(token):_abort_record_preparation(token,"The arrangement changed before recording. Start the take again.");return
 _record_phase="countdown"
 for count in range(_countdown,0,-1):
  if not _record_request_current(token) or not _record_backing_ready(prepared_id):
   _abort_record_preparation(token,"The arrangement or prepared playback changed before recording. Start the take again.");return
  record_button.text=str(count)
  var until:=Time.get_ticks_msec()+1000
  # No detached countdown timer retains suspended state after tab teardown.
  while Time.get_ticks_msec()<until:
   if not _record_request_owned(token):_abort_record_preparation(token);return
   await get_tree().process_frame
 if not _record_request_current(token) or not _record_backing_ready(prepared_id):
  _abort_record_preparation(token,"The arrangement or prepared playback changed before recording. Start the take again.");return
 if ActorAudioRecorder.backing_requested(preferences) and _requires_exact_preview() and prepared_id==0:
  _abort_record_preparation(token,"The arrangement now needs processed playback. Start recording again to prepare it.");return
 var target:=session.document.track_for_id(_record_track)
 if target.is_empty() or bool(target.get("locked",false)):_abort_record_preparation(token,"The recording track was removed or locked.");return
 var previous_preferences:=recorder.preferences_override
 recorder.preferences_override=preferences
 _record_phase="starting";record_button.text="Starting..."
 var error:String=await recorder.start()
 # Inserting/removing the capture destination shifts bus indices, not names.
 playback._track_effects.clear()
 recorder.preferences_override=previous_preferences
 if not error.is_empty():_abort_record_preparation(token,error);return
 if not _record_request_current(token) or (prepared_id!=0 and not (recorder.record_timeline or recorder.monitor_timeline)) or not _record_backing_ready(prepared_id):
  if recorder.recording:await recorder.stop()
  _abort_record_preparation(token,"The arrangement or prepared playback changed during device startup. No take was saved.");return
 _record_previous_loop_enabled=playback.loop_enabled;playback.loop_enabled=false
 _record_processed_capture=prepared_id!=0
 if recorder.record_timeline or recorder.monitor_timeline:
  if not _record_processed_capture:playback.set_document(session.document)
  playback.set_output_bus(recorder.timeline_bus_name if not recorder.timeline_bus_name.is_empty() else "Master")
  if _record_processed_capture:
   var start_error:=playback.start_recording_file(_record_prepared)
   if not start_error.is_empty():
    if recorder.recording:await recorder.stop()
    playback.set_output_bus("Master");playback.loop_enabled=_record_previous_loop_enabled if _record_session==session else session.document.loop_enabled
    _record_processed_capture=false;_abort_record_preparation(token,start_error);return
  else:
   playback.exact_required=false;playback.position=_record_start;playback.playing=true;playback.synchronize();playback.state_changed.emit()
 _record_elapsed=0;_record_busy=false;_record_phase="recording";record_button.text="■ Stop take"
 status.text=("Recording dry overdub" if recorder.monitor_timeline and not recorder.record_timeline else "Recording take")+(" · streamed processed backing" if _record_processed_capture else "")

func _record_backing_ready(id:int)->bool:
 if id==0:return _record_prepared==null
 return _record_prepared!=null and _record_prepared.get_instance_id()==id and _record_prepared.valid() and playback.recording_file_ready(_record_prepared)

func _finish_recorded_take(restart_next:bool)->void:
 _record_busy=true;_record_phase="stopping"
 playback.stop(false)
 var take_session:KiwiAudioEditSession=_record_session if _record_session!=null else session
 var context:Dictionary={"session":take_session,"document":_record_owner_document if _record_owner_document!=null else take_session.document,"track":_record_track,"start":_record_start,"latency":_latency_ms,"timeline":recorder.record_timeline,"monitored":recorder.monitor_timeline,"processed":_record_processed_capture,"failure":_record_failure,"restart":restart_next,"generation":_record_generation}
 context.muted_loop=bool(context.monitored) and not bool(context.timeline) and _record_loop and _record_cycle_duration>0
 var capture:Dictionary=await recorder.stop_to_files()
 playback._track_effects.clear();playback.set_output_bus("Master")
 playback.loop_enabled=_record_previous_loop_enabled if take_session==session else session.document.loop_enabled
 _record_prepared=null;_record_processed_capture=false
 _record_finalize_context=context;_record_phase="finalizing";record_button.text="Finalizing take..."
 var token:=_record_generation
 jobs.request("record_finalize",func(job:RefCounted):return preload("res://Workspaces/AudioWorkspace/audio_take_finalize.gd").finalize(capture,job),token)

func _record_finalized(token:int,data:Dictionary)->void:
 if _record_finalize_context.is_empty() or token!=int(_record_finalize_context.generation):return
 var context:=_record_finalize_context;_record_finalize_context={}
 var take_session:KiwiAudioEditSession=context.session
 var timeline_mix:=bool(context.timeline);var monitored:=bool(context.monitored);var muted_loop_take:=bool(context.muted_loop)
 var backing_failure:=str(context.failure);var warning:=str(data.get("warning",""))
 if not warning.is_empty():backing_failure+=(" " if not backing_failure.is_empty() else "")+warning
 var source_path:=str(data.get("path",""))
 _record_busy=false;_record_phase="idle";_record_session=null;_record_document=null;_record_owner_document=null;_record_preferences={};_record_signature=""
 record_button.text="● Record"
 if take_session.document!=context.document:
  notice("The recording document changed during finalization. The take files were preserved; use Takes → Recover disk takes.")
 elif not source_path.is_empty():
  var label:="Take %d"%(take_session.document.takes.size()+1)+(" (partial)" if not backing_failure.is_empty() else "")
  take_session.action("Record take",func():
   var target:=take_session.document.track_for_id(str(context.track))
   if target.is_empty() or bool(target.get("locked",false)):target=take_session.document.add_track("Recovered takes")
   var clip:=take_session.insert_source(source_path,maxf(0,float(context.start)-float(context.latency)/1000),str(target.id),label)
   if clip!=null:
    var actor:=take_session.document.actor_for_clip(clip.id);actor.values[&"muted"]=timeline_mix or muted_loop_take
    var captures:Array=[]
    for captured_path in data.get("sources",[]):captures.append({"audio":str(captured_path),"role":str(captured_path).get_file().get_basename()})
    take_session.document.takes.append({"id":ActorData.new_id(),"clip_id":clip.id,"track_id":str(target.id),"name":label,"status":"partial capture" if not backing_failure.is_empty() else ("muted mix" if timeline_mix else ("muted loop take" if muted_loop_take else "kept")),"backing_error":backing_failure,"timeline_mix":timeline_mix,"monitor_backing":monitored,"muted_loop_take":muted_loop_take,"processed":bool(context.processed),"capture_sources":captures,"capture_id":str(data.get("directory","")).get_file(),"timestamp":Time.get_unix_time_from_system()}))
  if take_session!=session:background_document_changed.emit(take_session)
  status.text="Recorded "+label+(". Timeline mix is muted to avoid double playback." if timeline_mix else (". Dry loop take is muted so the next pass hears only backing." if muted_loop_take else "."))
 else:notice(str(data.get("error","No audio was captured."))+" Use Takes → Recover disk takes to inspect preserved source files.")
 if not backing_failure.is_empty():notice("Recording warning: "+backing_failure+" Captured source files were retained; automatic restart was cancelled.")
 playback.exact_required=_requires_exact_preview();playback.set_document(session.document)
 if bool(context.restart) and backing_failure.is_empty() and not source_path.is_empty() and _record_loop and not _record_cancel_requested and take_session==session and take_session.document==context.document and is_visible_in_tree():
  playback.position=session.document.loop_start
  call_deferred("_restart_record_loop",weakref(take_session),_record_generation,weakref(take_session.document))
 else:_record_loop_preview=null;_record_loop_signature=""

func _restart_record_loop(owner:WeakRef,generation:int,document:WeakRef)->void:
 if owner.get_ref()!=session or document.get_ref()!=session.document or generation!=_record_generation or _record_cancel_requested or not _record_loop or _record_phase!="idle" or not is_visible_in_tree():
  if _record_phase=="idle":_record_loop_preview=null;_record_loop_signature=""
  return
 toggle_recording()

func finish_recording()->void:
 stop()
 while _record_busy or recorder.recording:
  await get_tree().process_frame

func take_dialog()->void:
 var dialog:=_window("Recording takes",Vector2i(580,420));var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(scroll);var host:=VBoxContainer.new();host.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(host)
 _button(dialog.host,"Recover disk takes",recover_disk_takes)
 for take in session.document.takes:
  var clip:=session.document.clip_for_id(str(take.clip_id));var actor:=session.document.actor_for_clip(str(take.clip_id))
  if clip==null or actor==null:continue
  var row:=HFlowContainer.new();host.add_child(row);_label(row,str(take.name)+" · "+str(take.get("status","kept")))
  _button(row,"▶",func():preview_player.stream=_workspace_source(actor.values.get(&"audio"));preview_player.play())
  _button(row,"Keep / choose",func():session.action("Choose take",func():
   for other in session.document.takes:
    if str(other.track_id)==str(take.track_id):
     var other_actor:=session.document.actor_for_clip(str(other.clip_id))
     if other_actor!=null:other_actor.values[&"muted"]=str(other.id)!=str(take.id)
   take.status="chosen"))
  _button(row,"Reject (undoable)",func():session.action("Reject take",func():actor.values[&"muted"]=true;take.status="rejected"))
 _label(dialog.host,"Rejected takes remain in the composition and undo history. Split and arrange kept takes on the main timeline to combine them.")

func recover_disk_takes()->void:
 var dialog:=_window("Recover retained disk takes",Vector2i(720,520))
 var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(scroll)
 var host:=VBoxContainer.new();host.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(host)
 _label(dialog.host,"Capture sources and checkpointed prefixes are kept independently of Undo. Import a mix OR its separate inputs to avoid doubling audio. Files are never deleted here; collect media for a portable composition.")
 var entries:Array=preload("res://Workspaces/AudioWorkspace/audio_take_finalize.gd").recoverable()
 var owner:=session;var document:=session.document
 for entry in entries:
  _heading(host,str(entry.state)+" · "+str(entry.directory).get_file())
  for path_value in entry.paths:
   var source_path:=str(path_value);var row:=HFlowContainer.new();host.add_child(row)
   _label(row,source_path.get_file())
   _button(row,"Preview",func():
    playback.stop(false);preview_player.stop();var problem:=asset_file_preview.open_file(source_path)
    if not problem.is_empty():notice(problem))
   _button(row,"Insert source",func():
    if session!=owner or session.document!=document or recorder.recording or _record_busy:notice("Return to the original document and finish recording first.");return
    var info:=KiwiAudioPCMFile.inspect(source_path)
    if not str(info.get("error","invalid")).is_empty():notice(str(info.get("error","Take is unavailable.")));return
    session.action("Recover disk take",func():
     var track:=session.document.track_for_id(session.selected_track)
     if track.is_empty() or bool(track.get("locked",false)) or KiwiAudioAutomationLane.is_lane(track):track=session.document.add_track("Recovered takes")
     session.insert_source(source_path,playback.position,str(track.id),"Recovered "+source_path.get_file())))
 if entries.is_empty():_label(host,"No checkpointed disk takes were found.")

func _apply_midi(result:Dictionary)->void:
 var tempos:Array=result.get("tempos",[])
 var timing:=KiwiAudioTempoMap.new(tempos)
 if not timing.error.is_empty():notice(timing.error);return
 var incoming:Array=[]
 for part:Dictionary in result.get("parts",[]):incoming.append({"notes":part.get("notes",[]),"midi_tempos":tempos,"midi_tempo_scale":1.0,"midi_time_signatures":result.get("time_signatures",[]),"midi_events":part.get("events",[])})
 var budget_error:=session.document.midi_timing_error(incoming,"",{"midi_tempos":tempos,"midi_time_signatures":result.get("time_signatures",[])})
 if not budget_error.is_empty():notice(budget_error);return
 for part:Dictionary in result.get("parts",[]):
  if (part.get("notes",[]) as Array).size()>KiwiAudioInstruments.MAX_NOTES or timing.beat_to_seconds(float(part.get("duration",result.get("duration",0.0))))>KiwiAudioInstruments.MAX_SECONDS:
   notice("This MIDI exceeds the editable instrument limit of 8192 notes or 300 seconds per source. Split it into shorter MIDI files before importing.");return
 session.action("Import MIDI",func():
  # Do not retime an existing composition just by importing another source.
  if session.document.clips.is_empty() and session.document.tempo_points.is_empty() and session.document.meter_points.is_empty() and session.document.note_base_tempo==0.0:
   session.document.tempo=clampf(float(result.get("tempo",120)),20.0,400.0)
   var signature:Array=result.get("time_signature",[4,4]);session.document.time_signature=Vector2i(clampi(int(signature[0]),1,32),int(signature[1]) if int(signature[1]) in [1,2,4,8,16,32] else 4)
  for part in result.get("parts",[]):
   var track:=session.document.add_track(str(part.get("label","MIDI")),"instrument");track.instrument=KiwiAudioInstruments.default_instrument(str(part.get("instrument",{}).get("id","piano")));track.instrument.merge(part.get("instrument",{}),true)
   var silent:=KiwiAudioSourceCache.to_wav(PackedVector2Array([Vector2.ZERO,Vector2.ZERO]))
   var clip:=session.document.insert_source(silent,track.id,0,str(part.get("label","MIDI")))
   if clip!=null:
    var actor:=session.document.actor_for_clip(clip.id);actor.values[&"notes"]=part.get("notes",[]).duplicate(true);actor.values[&"instrument"]=track.instrument.duplicate(true);actor.values[&"midi_events"]=part.get("events",[]).duplicate(true);actor.values[&"notes_dirty"]=true
    actor.values[&"midi_tempos"]=tempos.duplicate(true);actor.values[&"midi_tempo_scale"]=1.0;actor.values[&"midi_time_signatures"]=result.get("time_signatures",[]).duplicate(true)
    actor.values[&"pattern_beats"]=maxf(1.0/float(result.get("ppq",480)),float(part.get("duration",result.get("duration",0.0))))
  session.document.composer_settings["midi_tempos"]=result.get("tempos",[]);session.document.composer_settings["midi_time_signatures"]=result.get("time_signatures",[]))
 var import_notes:=PackedStringArray(result.get("warnings",[]))
 if tempos.size()>1:import_notes.append("MIDI tempo changes are used for source playback and audio export. Notes stay editable in source beats. The project conductor is independent; its edits preserve MIDI source timing. Uniform retime is available separately.")
 if not import_notes.is_empty():notice("MIDI import notes:\n\n"+"\n\n".join(import_notes))
 _render_dirty_notes()
func _job_completed(kind:String,generation:int,result:Variant)->void:
 if not result is Dictionary:return
 var data:Dictionary=result
 if kind=="media_scan":_show_media_review(data);return
 if kind=="media_probe":_confirm_media_repair(data);return
 if kind=="record_finalize":_record_finalized(generation,data);return
 if kind=="relink_probe":_review_audio_relink(data);return
 if kind=="timeline_midi":
  if session!=data.get("owner_session") or session.revision!=int(data.get("revision",-1)):notice("The composition changed while mapping MIDI. Repeat this action in the intended document.");return
  _save_midi_export(data.get("midi",{}),true);return
 if kind=="record_prepare":_record_preparation_finished(generation,data);return
 if kind=="silence_audition":_silence_audition_completed(generation,data);return
 if kind in ["analysis","loudness"] and not _analysis_provenance_current(data,generation):return
 if kind=="wave_edit" and int(data.get("owner_id",0))!=session.get_instance_id():return
 if kind=="render" and str(data.get("action",""))=="preview":
  if int(data.get("transport_token",-1))!=_transport_token or int(data.get("owner_id",0))!=session.get_instance_id() or not _transport_requested:
   _remove_preview_file(str(data.get("path","")));return
 if not str(data.get("error","")).is_empty():
  status.text=str(data.error)
  if kind=="render" and str(data.get("action",""))=="preview":_cancel_exact_playback();playback.stop(false)
  if kind not in ["wave_detail","preview"]:notice(str(data.error))
  return
 match kind:
  "breath_review":
   if generation==session.revision:_breath_review_ready(data)
  "preset_audition":
   if int(data.get("owner",0))!=session.get_instance_id():_remove_preview_file(str(data.get("path","")));return
   preview_player.stop();asset_file_preview.close_file()
   var problem:=asset_file_preview.open_file(str(data.path),"Master",{},true)
   if not problem.is_empty():notice(problem);_remove_preview_file(str(data.path))
  "dialogue_batch":
   if generation==session.revision:_dialogue_batch_ready(data)
  "preview":
   if generation!=_generation:return
   if data.get("stream")!=null:
    _preview_cache[data.cache_key]=data.stream
    var cache_bytes:=0
    for cached in _preview_cache.values():cache_bytes+=(cached as AudioStreamWAV).data.size()
    while (_preview_cache.size()>12 or cache_bytes>48*1024*1024) and _preview_cache.size()>1:
     var oldest:Variant=_preview_cache.keys()[0];cache_bytes-=(_preview_cache[oldest] as AudioStreamWAV).data.size();_preview_cache.erase(oldest)
   _set_preview(data.get("stream"),data.get("payload",{}))
  "audition":
   if data.get("stream")!=null:preview_player.stream=data.stream;preview_player.play()
  "import":
   if generation!=int(session.document.get_instance_id()):return
   if float(data.get("seconds",0))<=0:notice("Unsupported, empty or unknown-duration source: "+str(data.path));return
   var clip:=session.insert_source(data.path,float(data.at),str(data.track),str(data.path).get_file())
   if clip!=null:library.add_asset(data.path,str(data.path).get_file(),float(data.seconds));fit_timeline()
  "drop_generator":
   if generation!=session.revision:return
   if data.get("stream")!=null:
    var payload:Dictionary=data.payload;payload.stream=data.stream
    _insert_generator_payload(payload,float(data.at),str(data.track))
  "notes":
   if generation!=session.revision:_render_dirty_notes();return
   var modified:=false
   for entry in data.get("outputs",[]):
    var actor:=session.document.actor_for_clip(str(entry.clip_id));var clip:=session.document.clip_for_id(str(entry.clip_id))
    if actor==null or clip==null:continue
    if entry.get("stream")==null:status.text="Instrument render needs valid samples and a source below 300 seconds, including note releases.";continue
    KiwiAudioEditSession.apply_note_render(clip,actor,entry.stream,str(entry.get("signature","")));modified=true
   if modified:session.revision+=1;session.dirty=true;session.changed.emit()
  "composer":
   if generation!=session.revision:notice("The composition changed during music generation. Generate again to preserve those edits.");return
   _apply_composer(data)
  "wave_detail":
   if waveform.stream==null or int(data.get("source_id",0))!=waveform.stream.get_instance_id():return
   waveform.detail=data.samples;waveform.detail_start=float(data.start);waveform.queue_redraw()
  "spectrogram":
   if waveform.stream==null or generation!=int(waveform.stream.get_instance_id()):return
   waveform.spectrogram=ImageTexture.create_from_image(data.image);waveform.spectrogram_start=float(data.start);waveform.spectrogram_duration=float(data.duration);waveform.show_spectrogram=true;waveform.queue_redraw()
  "wave_edit":
   if int(data.get("owner_id",0))!=session.get_instance_id():return
   if generation!=session.revision:notice("The clip changed during processing. Apply the selection edit again.");return
   var applied:=KiwiAudioRegionEdit.apply(session,data)
   if not str(applied.get("error","")).is_empty():notice(str(applied.error));return
   if str(data.operation) in ["copy","cut"]:
    _wave_clipboard=data.clipboard;_wave_clipboard_rate=int(data.rate)
   if str(data.operation)=="copy":status.text="Copied sample selection.";return
   var focus_id:=str(applied.get("focus_clip_id",""))
   if not focus_id.is_empty():edit_clip(focus_id)
   else:_wave_clip_id="";waveform.open(null)
   status.text="Edited selection; untouched source audio is preserved. Undo restores the original clip."
  "noise_profile":
   if generation!=session.revision:return
   var actor:=session.document.actor_for_clip(str(data.get("clip_id","")))
   if actor==null:return
   session.action("Learn spectral noise profile",func():
    var effect:=KiwiAudioEffects.create("noise_reduce");effect.parameters.noise_profile=data.noise_profile;effect.parameters.floor=data.floor
    var stack:Array=actor.values.get(&"effects",[]);stack.append(effect);actor.values[&"effects"]=stack)
   status.text="Learned a 15-band spectral profile from %.3f seconds. Render preview and adjust reduction/floor; noise overlapping speech cannot be perfectly removed."%float(data.seconds)
  "loudness":_accept_analysis_result(data,generation,true)
  "analysis":_accept_analysis_result(data,generation)
  "alignment":
   if generation!=session.revision or int(data.get("owner_id",0))!=session.get_instance_id():return
   var problem:=_alignment_problem(data.get("ids",[]))
   if not problem.is_empty():notice(problem);return
   if float(data.get("confidence",0))<0.25:notice("No confident alignment was found. Adjust manually.");return
   session.action("Align audio",func():session.edit_clip(str(data.clip_id),{"start_time":maxf(0,float(data.base)+float(data.offset))}))
   status.text="Aligned using normalized correlation (%.0f%%)."%(float(data.confidence)*100)
  "match_levels":
   if generation!=session.revision or int(data.get("owner_id",0))!=session.get_instance_id():return
   for entry in data.clips:
    var problem:=_smart_track_problem(str(session.document.track_for_clip(str(entry.id)).get("id","")))
    if not problem.is_empty():notice(problem);return
   session.action("Match RMS levels",func():
    for entry in data.clips:
     var actor:=session.document.actor_for_clip(str(entry.id))
     if actor!=null and float(entry.db)>-100:actor.values[&"volume_db"]=clampf(float(entry.get("base_db",0))-20.0-float(entry.db),-30,18))
  "ducking":
   if generation!=session.revision or int(data.get("owner_id",0))!=session.get_instance_id():return
   var problem:=_smart_track_problem(str(data.track))
   if not problem.is_empty():notice(problem);return
   var track:=session.document.track_for_id(str(data.track))
   if not track.is_empty():session.action("Dialogue ducking",func():var curves:Dictionary=track.get("automation",{});curves.volume_db=data.points;track.automation=curves)
  "render":_render_finished(data,generation)
  "export_stems":
   var failures:Array=[];var count:=0
   for entry in data.results:
    if bool(entry.get("success",false)):count+=1
    else:failures.append(str(entry.get("error","Failed")))
   status.text="Exported %d stems."%count
   if not failures.is_empty():notice("\n".join(failures))
  "save_preview":
   if bool(data.get("success",false)):library.add_asset(data.path,str(data.path).get_file(),float(data.get("duration",0)));status.text="Saved generated audio."
   else:notice("Audio export failed. Check the encoder and destination.")
func _apply_composer(data:Dictionary)->void:
 var error:=KiwiAudioComposerControls.apply_rendered(session,data)
 if not error.is_empty():notice(error);return
 for id in data.get("applied_clip_ids",[]):
  var actor:=session.document.actor_for_clip(str(id))
  if actor!=null:actor.values[&"rendered_signature"]=_note_render_key(actor)
 fit_timeline();status.text="Generated editable notes, harmony and arrangement sections."

func _render_finished(data:Dictionary,generation:int)->void:
 if not bool(data.get("success",false)):notice(str(data.get("error","Audio render failed.")));return
 var action:=str(data.action)
 if action=="export":status.text="Exported "+str(data.path);return
 if int(data.get("owner_id",0))!=session.get_instance_id():
  _remove_preview_file(str(data.path));status.text="Discarded a render for a different composition."
  return
 if generation!=session.revision:
  _remove_preview_file(str(data.path));status.text="Discarded a stale preview; newer edits were preserved."
  if action=="preview" and _transport_requested:call_deferred("render_preview")
  return
 if action=="preview" and bool(data.get("file_preview",false)):
  if not _transport_requested or int(data.get("transport_token",-1))!=_transport_token:_remove_preview_file(str(data.path));return
  var pcm_info:Dictionary=data.get("pcm_info",{})
  if not str(pcm_info.get("error","Invalid PCM preview.")).is_empty():
   _remove_preview_file(str(data.path));_cancel_exact_playback();notice(str(pcm_info.get("error","Invalid PCM preview.")));return
  _transport_requested=false
  var error:=playback.play_file(str(data.path),float(data.at),pcm_info)
  if not error.is_empty():_remove_preview_file(str(data.path));notice(error)
  else:
   playback.rendered_route_meters=data.get("route_meters",{});playback.rendered_meter_start=float(data.get("meter_start",data.at));playback.rendered_meter_hz=int(data.get("meter_hz",20))
   var monitor_from:=float(data.get("monitor_from",data.at))
   if monitor_from>float(data.at) and monitor_from<float(data.at)+float(pcm_info.get("duration",0.0)):playback.seek(monitor_from)
   status.text="Playing prepared PCM from disk; original sources remain unchanged."
  return
 var stream:AudioStream=data.get("stream")
 if stream==null:notice("Render completed but could not be loaded.");return
 match action:
  "preview":
   if not _transport_requested or int(data.get("transport_token",-1))!=_transport_token:return
   _transport_requested=false;playback.play_exact(stream,float(data.at))
   var monitor_from:=float(data.get("monitor_from",data.at))
   if monitor_from>float(data.at) and monitor_from<float(data.at)+stream.get_length():playback.seek(monitor_from)
   _remove_preview_file(str(data.path))
  "scene":use_in_scene.emit(stream,session.document.title);status.text="Rendered audio is ready in Scene Workspace."
  "replace":
   var problem:=session.replace_rendered_clips(data.selection,str(data.track_id),stream)
   if not problem.is_empty():notice(problem);return
  "freeze_track":
   var problem:=preload("res://Workspaces/AudioWorkspace/audio_group_freeze.gd").apply(session,str(data.track_id),stream)
   if not problem.is_empty():notice(problem)
  "bounce_track":
   session.action("Bounce track",func():
    var track:=session.document.add_track("Bounced "+str(session.document.track_for_id(str(data.track_id)).get("name","Track")),"audio")
    session.document.insert_source(stream,track.id,0,"Track bounce")
    var original:=session.document.track_for_id(str(data.track_id));original.mute=true;original.locked=true)
 if action!="preview":library.add_asset(str(data.path),str(data.path).get_file(),stream.get_length())

func undo()->void:
 if recorder.recording or _record_busy:notice("Stop or cancel the take before Undo.");return
 _interaction_epoch+=1;_controls_generation+=1;_discard_parameter_handle()
 # Undo discards a pending pass first, without undoing an unrelated older edit.
 var pending:=automation_recording.has_pending()
 automation_recording.discard("Read: pending automation discarded by Undo." if pending else "Read: Undo requested.")
 _automation_release_timer.stop();_automation_gesture_held=false
 if pending:playback.stop(false);call_deferred("_refresh_all");return
 session.undo();call_deferred("_refresh_all")
func redo()->void:
 if recorder.recording or _record_busy:notice("Stop or cancel the take before Redo.");return
 _interaction_epoch+=1;_controls_generation+=1;_discard_parameter_handle()
 automation_recording.discard("Read: pending automation discarded before Redo.")
 _automation_release_timer.stop();_automation_gesture_held=false
 playback.stop(false);session.redo();call_deferred("_refresh_all")
func _register_commands()->void:
 _commands={
  "Play / Pause":toggle_playback,"Stop":stop,"Import Audio":import_audio,"Save Composition":save,"Collect Portable Copy":review_portable_copy,"Open Collected Copy":open_collected_copy,"Export Audio":export_dialog,"Review Recovery":review_recovery,"Checkpoint Now":func():_queue_recovery_checkpoint(true),
  "Undo":undo,"Redo":redo,"Copy Clips":func():session.copy(),"Paste Clips":func():session.paste(playback.position,session.selected_track),
  "Duplicate Clips":func():session.duplicate_selected(),"Delete Clips":func():session.delete_selected(),"Ripple Delete":func():session.delete_selected(true),
  "Split At Playhead":func():session.split_selected(playback.position),"Crossfade Clips":func():session.crossfade_selected(),
  "Add Track":add_track_dialog,"New Instrument Pattern":new_pattern,"New Drum Pattern":new_pattern.bind(true),
  "Project Conductor":conductor_dialog,"Uniformly Retime Notes":retime_notes_dialog,"Generate Music":music_dialog,"Arrangement Sections":arrangement_dialog,"Harmonize Melody":harmonize_notes,"Render Exact Preview":render_preview,"Render In Place":render_in_place,"Join Selected Clips":render_in_place,"Batch Apply Effects":batch_effects,"Bounce Track":bounce_track,"Freeze Track":freeze_track,"Unfreeze Track":unfreeze_track,
  "Loop Selection":loop_selection,"Fit Timeline":fit_timeline,"Add Marker":add_marker,"Add Effect":add_effect_dialog,"Effect Chain Presets":effect_chain_dialog,
  "Analyze Clip":analyze_clip,"Learn Noise Profile":sample_noise_profile,"Align Selected Clips":align_selected,"Match RMS Levels":match_levels,"Dialogue Ducking":ducking_dialog,
  "Record Automation":automation_record_target_dialog,"Automation":automation_dialog,"Sends":send_dialog,"Relink Source":relink_source,"Record":toggle_recording,
  "Recording Options":recording_options,"Recording Takes":take_dialog,"Import MIDI":import_midi,"Export MIDI":export_midi,"Export Timeline Notes MIDI":export_timeline_midi,
  "Save Composition Preset":save_preset.bind("composition"),"Save Selected Layer Bundle":save_layer_bundle,"Import Native Preset":import_native_preset,"Recover Presets":preset_recovery_dialog,"Review Selected Dialogue":review_dialogue_batch,"Modulation Matrix":modulation_matrix_dialog,"Fit Selected Notes to Conductor":fit_notes_to_conductor_dialog,"Customize Shortcuts":customize_shortcuts,"Provider Status":provider_status}
 _shortcuts={"Play / Pause":KEY_SPACE,"Stop":KEY_HOME,"Save Composition":KEY_MASK_CTRL|KEY_S,"Undo":KEY_MASK_CTRL|KEY_Z,"Redo":KEY_MASK_CTRL|KEY_MASK_SHIFT|KEY_Z,"Copy Clips":KEY_MASK_CTRL|KEY_C,"Paste Clips":KEY_MASK_CTRL|KEY_V,"Duplicate Clips":KEY_MASK_CTRL|KEY_D,"Delete Clips":KEY_DELETE,"Split At Playhead":KEY_S,"Record":KEY_R,"Loop Selection":KEY_L,"Fit Timeline":KEY_F}
 _commands["Transcribe Selected Clip Locally"]=_optional_tools.transcribe
 _commands["Review Saved Transcript"]=_optional_tools.review_saved_transcript
 _commands["Generate Cloud Speech (Opt-in)"]=_optional_tools.speech
 _commands["Optional Speech Tool Setup"]=_optional_tools.configure
func _run_command(name:String)->void:
 if not _commands.has(name):return
 if name!="Customize Shortcuts":_last_command=name
 _commands[name].call()
func command_palette()->void:
 var ui:=_window("Audio Commands",Vector2i(540,480))
 var search:=LineEdit.new();search.placeholder_text="Search actions…";ui.host.add_child(search)
 var list:=ItemList.new();list.size_flags_vertical=Control.SIZE_EXPAND_FILL;ui.host.add_child(list)
 var refill:=func(query:String):
  list.clear()
  for name in _commands:
   if query.is_empty() or str(name).to_lower().contains(query.to_lower()):
    var key:=int(_shortcuts.get(name,0));list.add_item(str(name)+( "   "+OS.get_keycode_string(key) if key else ""));list.set_item_metadata(list.item_count-1,name)
 search.text_changed.connect(refill);refill.call("")
 list.item_activated.connect(func(index:int):var action:=str(list.get_item_metadata(index));ui.window.queue_free();_run_command(action))
 search.text_submitted.connect(func(_query:String):if list.item_count>0:var action:=str(list.get_item_metadata(0));ui.window.queue_free();_run_command(action))
 search.grab_focus()
func customize_shortcuts()->void:
 var ui:=_window("Keyboard Shortcuts",Vector2i(550,500))
 _label(ui.host,"Choose an action, then press its shortcut. Text fields keep normal typing shortcuts. Escape cancels capture.")
 var list:=ItemList.new();list.size_flags_vertical=Control.SIZE_EXPAND_FILL;ui.host.add_child(list)
 for name in _commands:
  list.add_item(str(name)+"   "+OS.get_keycode_string(int(_shortcuts.get(name,0))));list.set_item_metadata(list.item_count-1,name)
 var capture:Dictionary={"action":""}
 list.item_activated.connect(func(index:int):capture.action=str(list.get_item_metadata(index));status.text="Press a shortcut for "+capture.action)
 list.gui_input.connect(func(event:InputEvent):
  if not event is InputEventKey or not event.pressed or event.echo or str(capture.action).is_empty():return
  list.accept_event()
  if event.keycode==KEY_ESCAPE:capture.action="";return
  var key:int=event.get_keycode_with_modifiers()
  for name in _shortcuts.keys():
   if int(_shortcuts[name])==key:_shortcuts.erase(name)
  _shortcuts[capture.action]=key;capture.action=""
  var config:=ConfigFile.new();config.set_value("keys","commands",_shortcuts);DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://audio_workspace"));config.save("user://audio_workspace/shortcuts.cfg")
  for index in list.item_count:list.set_item_text(index,str(list.get_item_metadata(index))+"   "+OS.get_keycode_string(int(_shortcuts.get(list.get_item_metadata(index),0)))))
func _context_menu(at:Vector2)->void:
 var menu:=PopupMenu.new();add_child(menu)
 var actions:PackedStringArray=["Copy Clips","Paste Clips","Duplicate Clips","Delete Clips","Ripple Delete","Split At Playhead","Crossfade Clips","Render In Place","Analyze Clip","Relink Source","Add Effect"]
 for name in actions:menu.add_item(name)
 menu.id_pressed.connect(func(index:int):_run_command(actions[index]))
 menu.popup_hide.connect(menu.queue_free);menu.position=Vector2i(at);menu.popup()
func _unhandled_key_input(event:InputEvent)->void:
 if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:return
 var focused:=get_viewport().gui_get_focus_owner()
 if focused is LineEdit or focused is TextEdit:return
 var key:int=event.get_keycode_with_modifiers()
 if key==(KEY_MASK_CTRL|KEY_K):command_palette();get_viewport().set_input_as_handled();return
 if key==(KEY_MASK_CTRL|KEY_MASK_SHIFT|KEY_R) and not _last_command.is_empty():_run_command(_last_command);get_viewport().set_input_as_handled();return
 for name in _shortcuts:
  if int(_shortcuts[name])==key:_run_command(name);get_viewport().set_input_as_handled();return
func provider_status()->void:
 _optional_tools.configure()

func _requires_exact_preview()->bool:
 for actor in session.document.actors:
  if ActorAudio.needs_file_preview(actor.values.get(&"audio")):return true
  if KiwiAudioEditSession.is_note_source(actor) and (bool(actor.values.get(&"notes_dirty",false)) or str(actor.values.get(&"rendered_signature",""))!=_note_render_key(actor)):return true
 var stacks:Array=[session.document.master.get("effects",[])]
 for track in session.document.tracks:
  if not track.get("sends",[]).is_empty() or bool(track.get("solo",false)):return true
  stacks.append(track.get("effects",[]))
 for actor in session.document.actors:
  if not actor.values.get(&"automation",{}).get("pitch",[]).is_empty():return true
  if bool(actor.values.get(&"reverse",false)):return true
  stacks.append(actor.values.get(&"effects",[]))
 for stack in stacks:
  for effect in stack:
   if bool(effect.get("enabled",true)) and (not bool(KiwiAudioEffects.definition(str(effect.get("type",""))).get("realtime",false)) or not effect.get("automation",{}).is_empty()):return true
 return false

func _workspace_source(value:Variant)->AudioStream:
 if ActorAudio.needs_file_preview(value):return null
 return ActorAudio.source(value)

func _note_render_key(actor:ActorData)->String:
 return KiwiAudioEditSession.note_signature(actor,session.document)

func harmonize_notes()->void:
 var actor:=session.primary_actor()
 if actor==null or not session.can_edit(session.primary_clip().id):return
 session.action("Harmonize melody",func():
  var harmony:=KiwiAudioComposer.harmonize(actor.values.get(&"notes",[]),session.document.key,session.document.scale,2)
  var notes:Array=actor.values.get(&"notes",[])
  for note in harmony:note.id=ActorData.new_id();note.velocity=float(note.get("velocity",0.8))*0.75;notes.append(note)
  actor.values[&"notes"]=notes;actor.values[&"notes_dirty"]=true;piano._mark_changed())
 _render_dirty_notes()
func arrangement_dialog()->void:
 var dialog:=_window("Arrangement sections",Vector2i(740,530))
 _label(dialog.host,"Move or resize a section to move/stretch its generated notes and chord events. Other sections stay put. Times are source-relative quarter-note beats at the generated arrangement tempo; they do not follow project conductor points.")
 var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(scroll)
 var host:=VBoxContainer.new();host.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(host)
 for section in session.document.sections:
  var row:=HFlowContainer.new();host.add_child(row)
  var label:=LineEdit.new();label.text=str(section.name);label.custom_minimum_size.x=120;row.add_child(label)
  label.text_submitted.connect(func(value:String):session.action("Rename section",func():section.name=value))
  var state:Dictionary={"start":float(section.start),"duration":float(section.duration)}
  _number(row,"Start",state.start,0,2048,0.25,func(value:float):state.start=value)
  _number(row,"Length",state.duration,0.25,1024,0.25,func(value:float):state.duration=value)
  _button(row,"Apply",func():_transform_section(str(section.id),state.start,state.duration))
  _button(row,"Regenerate",func():var settings:=session.document.composer_settings.duplicate(true);settings.seed=int(settings.get("seed",1))+1;_compose(settings,"",str(section.id));dialog.window.queue_free())
 _button(dialog.host,"Add section marker",func():
  session.action("Add arrangement section",func():session.document.sections.append({"id":ActorData.new_id(),"name":"New section","start":playback.position*session.document.arrangement_tempo()/60,"duration":4.0}))
  dialog.window.queue_free();arrangement_dialog())
 _label(dialog.host,"Moving generated sections can create overlaps deliberately. Imported audio clips remain under direct timeline control.")
func _transform_section(id:String,start:float,duration:float)->void:
 var section:Dictionary={}
 for entry in session.document.sections:
  if str(entry.id)==id:section=entry;break
 if section.is_empty():return
 var previous:=float(section.start);var length:=maxf(0.001,float(section.duration));var ratio:=duration/length
 session.action("Transform arrangement section",func():
  for actor in session.document.actors:
   for note in actor.values.get(&"notes",[]):
    if str(note.get("section_id",""))==id:note.start=start+(float(note.start)-previous)*ratio;note.duration=float(note.duration)*ratio;actor.values[&"notes_dirty"]=true
  for chord in session.document.chords:
   if str(chord.get("section_id",""))==id:chord.start=start+(float(chord.start)-previous)*ratio;chord.duration=float(chord.get("duration",1))*ratio
  section.start=start;section.duration=duration)
 _render_dirty_notes()
func sample_map_dialog()->void:
 var actor:=session.primary_actor()
 if actor==null:return
 var patch:Dictionary=actor.values.get(&"instrument",{})
 var dialog:=_window("Multisample mapping",Vector2i(750,520));var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(scroll);var host:=VBoxContainer.new();host.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(host)
 var mappings:Array=patch.get("multisamples",[])
 for mapping in mappings:
  var row:=HFlowContainer.new();host.add_child(row);_label(row,str(mapping.get("sample","")).get_file())
  for info in [["root_pitch",0,127,1],["low",0,127,1],["high",0,127,1],["velocity_low",0,1,0.01],["velocity_high",0,1,0.01]]:
   var key:=str(info[0]);_number(row,key,float(mapping.get(key,60 if key=="root_pitch" else (127 if key=="high" else (1 if key=="velocity_high" else 0)))),info[1],info[2],info[3],func(value:float):_edit("Sample map",func():mapping[key]=value;actor.values[&"notes_dirty"]=true))
  _button(row,"Remove",func():session.action("Remove sample mapping",func():mappings.erase(mapping);patch.multisamples=mappings;actor.values[&"notes_dirty"]=true);dialog.window.queue_free();sample_map_dialog())
 _button(dialog.host,"Add sample",func():dialog.window.queue_free();choose_instrument_sample())
 _button(dialog.host,"Render mapping",func():_render_dirty_notes();dialog.window.queue_free())
func choose_generator_sample()->void:
 var chosen:=await ActorProjectFilePicker.pick(self,_audio_property(),"Choose source for granular synthesis")
 if chosen.is_empty() or chosen==ActorProjectFilePicker.EMPTY_RESOURCE:return
 _generator_settings.sample=chosen;_generate_preview()
func fit_notes_to_conductor_dialog()->void:
 if recorder.recording or _record_busy or automation_recording.active or automation_recording.has_pending():notice("Finish recording before fitting note timing.");return
 var ids:=session.selected_ids.duplicate();var owner:=session;var document:=session.document;var revision:=session.revision
 var prepared:=preload("res://Workspaces/AudioWorkspace/audio_conductor_fit.gd").prepare(session,ids)
 if not str(prepared.get("error","")).is_empty():notice(prepared.error);return
 var dialog:=_window("Fit selected note sources to conductor",Vector2i(660,440))
 _label(dialog.host,"One-time re-map to the current step-tempo conductor. Clip starts remain at their absolute seconds; note pitches, source beat positions and linked patterns remain editable. Full clip lengths change. Existing local automation/fades stay in seconds. Trimmed, reversed, looped and stretched sources are refused. Future conductor edits still preserve source timing until you explicitly fit again.")
 for operation in prepared.operations:_label(dialog.host,"%s: %.3f → %.3f seconds"%[operation.actor.display_name,operation.clip.duration,float(operation.duration)])
 _button(dialog.host,"Apply timing policy · one Undo",func():
  if session!=owner or session.document!=document or session.revision!=revision:notice("The document changed. Review timing again.");return
  var error:=preload("res://Workspaces/AudioWorkspace/audio_conductor_fit.gd").apply(session,ids)
  if not error.is_empty():notice(error)
  else:_render_dirty_notes();dialog.window.queue_free())

func modulation_matrix_dialog()->void:
 if recorder.recording or _record_busy or automation_recording.active or automation_recording.has_pending():notice("Finish recording or automation before replacing curves.");return
 var owner:=session;var document:=session.document
 var rows:Array=session.document.presets.get("modulation_matrix",[]).duplicate(true);var options:=KiwiAudioAutomationLane.options(document)
 var dialog:=_window("Modulation matrix · editable automation",Vector2i(960,640));var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(scroll);var host:=VBoxContainer.new();host.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(host)
 var refresh:=func():
  _clear(host)
  for row in rows:
   var panel:=VBoxContainer.new();host.add_child(panel);var chooser:=OptionButton.new();chooser.fit_to_longest_item=false;chooser.clip_text=true;panel.add_child(chooser)
   for option in options:
    chooser.add_item(str(option.label));chooser.set_item_metadata(chooser.item_count-1,option.target)
    if KiwiAudioAutomationLane.key(option.target)==KiwiAudioAutomationLane.key(row.get("target",{})):chooser.select(chooser.item_count-1)
   chooser.item_selected.connect(func(index:int):row.target=chooser.get_item_metadata(index).duplicate(true);var info:=KiwiAudioAutomationLane.resolve(document,row.target);row.center=float(info.get("fallback",0)))
   var controls:=HFlowContainer.new();panel.add_child(controls)
   _choice(controls,"Source",["sine","triangle","saw","square","random step","envelope"],str(row.get("shape","sine")),func(value:String):row.shape=value)
   _number(controls,"Center",float(row.get("center",0)),-100000,100000,.1,func(value:float):row.center=value)
   _number(controls,"Depth",float(row.get("depth",1)),-100000,100000,.1,func(value:float):row.depth=value)
   _number(controls,"Rate Hz",float(row.get("rate",1)),.01,20,.01,func(value:float):row.rate=value)
   _number(controls,"Period beats",float(row.get("beats",1)),.0625,64,.0625,func(value:float):row.beats=value)
   _check(controls,"Sync to initial BPM",bool(row.get("sync",false)),func(value:bool):row.sync=value)
   _button(controls,"Remove",func():rows.erase(row);panel.queue_free())
 _label(dialog.host,"Applies to clip/track/group/master gain/pan, clip pitch and supported effect parameters. Replaces each chosen curve in one Undo action; curves remain individually editable. BPM sync uses the initial conductor tempo, not variable-tempo following. Render exact preview for offline-only targets.")
 _button(dialog.host,"Add target",func():
  if rows.size()>=32:return
  var target:Dictionary=options[0].target if not options.is_empty() else {};rows.append({"target":target.duplicate(true),"center":float(options[0].fallback) if not options.is_empty() else 0.,"depth":1.,"rate":1.,"sync":false,"shape":"sine","beats":1.});refresh.call())
 _button(dialog.host,"Replace chosen curves · one Undo",func():
  if session!=owner or session.document!=document:notice("The document changed. Reopen the modulation matrix.");return
  var error:=preload("res://Workspaces/AudioWorkspace/audio_modulation_matrix.gd").apply(session,rows)
  if not error.is_empty():notice(error)
  else:dialog.window.queue_free())
 refresh.call()

func modulator_dialog(generator:bool)->void:
 var actor:=session.primary_actor()
 if not generator and actor==null:return
 var owner:Dictionary=_generator_settings if generator else actor.values.get(&"instrument",{})
 var owner_session:=session;var owner_document:=session.document
 var dialog:=_window("Synthesis modulation",Vector2i(700,540));var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(scroll);var host:=VBoxContainer.new();host.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(host)
 var modulators:Array=owner.get("modulators",[]).duplicate(true)
 var refresh:=func():
  _clear(host)
  for modulator in modulators:
   var row:=HFlowContainer.new();host.add_child(row)
   _choice(row,"Target",["pitch","cutoff","amplitude","pan"],str(modulator.get("target","pitch")),func(value:String):modulator.target=value)
   _choice(row,"Source",["lfo","envelope","random","step","velocity"],str(modulator.get("kind","lfo")),func(value:String):modulator.kind=value)
   _number(row,"Rate (Hz)",float(modulator.get("rate",1)),0.01,30,0.01,func(value:float):modulator.rate=value)
   _number(row,"Depth",float(modulator.get("amount",1)),-24,24,0.1,func(value:float):modulator.amount=value)
   var values:=LineEdit.new();values.placeholder_text="Step values: 0,1,0,-1";values.text=",".join(PackedStringArray((modulator.get("values",[0,1,0,-1]) as Array).map(func(v:Variant):return str(v))));row.add_child(values)
   values.text_changed.connect(func(value:String):var steps:Array=[];for part in value.split(","):steps.append(clampf(float(part),-24,24));modulator.values=steps)
   _check(row,"Enabled",bool(modulator.get("enabled",true)),func(value:bool):modulator.enabled=value)
 refresh.call()
 _button(dialog.host,"Add modulation",func():modulators.append({"kind":"lfo","target":"pitch","rate":2.0,"amount":0.5,"enabled":true,"values":[0,1,0,-1]});refresh.call())
 _label(dialog.host,"Pitch depth is semitones; cutoff depth is octaves; amplitude depth is relative gain. Modulation is baked by synthesis. Seeded random and step sources are deterministic. Velocity uses each instrument note's velocity.")
 _button(dialog.host,"Apply and preview",func():
  if session!=owner_session or session.document!=owner_document:notice("The document changed. Reopen modulation.");return
  if not generator and (session.primary_actor()!=actor or not session.can_edit(session.primary_clip().id)):notice("Select the original unlocked instrument before applying modulation.");return
  if generator:owner.modulators=modulators;_generate_preview()
  else:session.action("Instrument modulation",func():owner.modulators=modulators;actor.values[&"instrument"]=owner;actor.values[&"notes_dirty"]=true);_render_dirty_notes()
  dialog.window.queue_free())

func set_scene_binding(bound:bool)->void:
 if send_scene_button!=null:send_scene_button.text="Update Scene Actor" if bound else "To Scene"
func _remove_preview_file(file:String)->void:
 var directory:=ProjectSettings.globalize_path("user://audio_workspace/rendered").replace("\\","/").simplify_path()+"/"
 var normalized:=ProjectSettings.globalize_path(file).replace("\\","/").simplify_path()
 if normalized.begins_with(directory) and normalized.get_file().begins_with("preview_") or normalized.begins_with(directory) and normalized.get_file().begins_with("selection_"):
  ActorAudio.invalidate(file);DirAccess.remove_absolute(normalized)

func measure_loudness()->void:
 var actor:=session.primary_actor()
 if actor==null:return
 var value:Variant=actor.values.get(&"audio")
 var identity:=_analysis_identity(actor);var clip_id:=session.primary_clip().id
 var owner_id:=session.get_instance_id();var document_id:=session.document.get_instance_id();var revision:=session.revision
 jobs.request("loudness",func(job:RefCounted):
  var result:=KiwiAudioAnalysis.loudness(value,job);result.source_identity=identity;result.clip_id=clip_id;result.owner_id=owner_id;result.document_id=document_id;result.revision=revision
  return result,revision)
 bottom.visible=true;bottom.current_tab=5

func effect_automation_dialog(index:int)->void:
 var owner:=_effect_owner();var stack:Array=owner.get("effects",[])
 if index<0 or index>=stack.size():return
 var effect:Dictionary=stack[index];var supported:=KiwiAudioEffects.automation_commands(str(effect.type))
 var definitions:Dictionary={};var names:Array=[]
 for field in KiwiAudioEffects.definition(str(effect.type)).parameters:
  if supported.has(field.id):definitions[field.id]=field;names.append(field.id)
 if names.is_empty():return
 var dialog:=_window("Effect parameter automation",Vector2i(720,430));var editor:=KiwiAudioAutomationCanvas.new();editor.session=session;editor.effect_id=str(effect.id)
 var clip:=session.primary_clip();editor.owner_kind="clip" if clip!=null else ("track" if not session.selected_track.is_empty() else "master");editor.owner_id=clip.id if clip!=null else session.selected_track
 editor.duration=maxf(1,clip.duration if clip!=null else session.document.duration());editor.parameter=str(names[0]);editor.minimum=float(definitions[names[0]].min);editor.maximum=float(definitions[names[0]].max)
 _label(dialog.host,"Drag curve points to automate this processor. Realtime uses the native approximation; offline commands update at up to 50 Hz (decoder frame boundaries). Long curves use an adaptive interval to bound render work.")
 var row:=HFlowContainer.new();dialog.host.add_child(row)
 _choice(row,"Parameter",names,str(names[0]),func(value:String):editor.parameter=value;editor.minimum=float(definitions[value].min);editor.maximum=float(definitions[value].max);editor.queue_redraw())
 _choice(row,"Interpolation",["linear","smooth","hold"],"linear",editor.set_curve)
 _number(row,"View seconds",editor.duration,0.1,86400,0.1,func(value:float):editor.duration=value;editor.queue_redraw())
 editor.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(editor)
 _button(dialog.host,"Clear selected curve",editor.clear_points)
 _button(dialog.host,"Show in timeline lane",func():_show_automation_editor_in_lane(editor);dialog.window.queue_free())

func _toggle_loop_transport(enabled:bool)->void:
 if recorder.recording or _record_busy:
  loop_button.set_pressed_no_signal(session.document.loop_enabled);notice("Stop or cancel the take before changing its transport loop.");return
 session.action("Toggle loop",func():session.document.loop_enabled=enabled);playback.loop_enabled=enabled

func _set_record_loop(enabled:bool)->void:
 if recorder.recording or _record_busy:notice("Stop or cancel the take before changing loop-recording mode.");return
 _record_loop=enabled

func _preview_failed(message:String)->void:
 _cancel_exact_playback()
 if _record_processed_capture and recorder.recording:
  _record_failure=message;_record_cancel_requested=true
  _record_loop_preview=null;_record_loop_signature=""
  if not _record_busy:_finish_recorded_take(false)
 elif _record_busy and _record_prepared!=null:
  _record_failure=message;_cancel_record_preparation();notice("Prepared recording backing failed: "+message)
 else:notice(message)

func _exact_requested(_seconds:float)->void:
 if _record_processed_capture and recorder.recording:
  status.text="Seek left the prepared recording range; stopping the take."
  if not _record_busy:toggle_recording()
  return
 render_preview()

func _cancel_exact_playback()->void:
 _transport_token+=1
 if _transport_requested:jobs.cancel_kind("render")
 _transport_requested=false;playback.exact_pending=false

func cancel_background_jobs()->void:
 _optional_tools.cancel()
 _close_portable_review()
 if _record_busy:_cancel_record_preparation()
 elif recorder.recording:toggle_recording()
 _cancel_exact_playback();jobs.cancel_all();playback.stop(false)
 if not _record_finalize_context.is_empty():_record_finalized(int(_record_finalize_context.generation),{"error":"Finalization cancelled. Captured WAVs remain on disk."})
 status.text="Background processing cancelled."

func _generator_payload(entry:Dictionary,settings:Dictionary,seed_value:int)->Dictionary:
 var identity:=""
 if settings.get("sample") is String:
  var sample_path:String=settings.sample
  identity=str(FileAccess.get_modified_time(sample_path))
  var file:=FileAccess.open(sample_path,FileAccess.READ)
  if file!=null:identity+=":"+str(file.get_length());file.close()
 var id:=str(entry.get("id",""))
 return {"id":id,"entry":entry.duplicate(true),"label":str(entry.get("label","Generated sound")),"settings":settings.duplicate(true),"seed":seed_value,"key":(id+var_to_str(settings)+str(seed_value)+identity).sha256_text()}

func _preview_matches_controls()->bool:
 if _preview_stream==null or _preview_payload.is_empty() or str(_library_entry.get("kind",""))!="generator":return false
 return str(_preview_payload.get("key",""))==str(_generator_payload(_library_entry,_generator_settings,_generator_seed).key)

func _select_variation(payload:Dictionary)->void:
 if not payload.get("stream") is AudioStreamWAV:return
 _generation+=1;jobs.cancel_kind("preview");_preview_timer.stop()
 _library_entry=payload.entry.duplicate(true);_generator_settings=payload.settings.duplicate(true);_generator_seed=int(payload.seed)
 _set_preview(payload.stream,payload)

func _insert_generator_payload(payload:Dictionary,seconds:float,track_id:String)->void:
 if KiwiAudioAutomationLane.is_lane(session.document.track_for_id(track_id)):notice("Select an audio or instrument track before adding generated audio.");return
 if not payload.get("stream") is AudioStreamWAV or str(payload.get("id","" )).is_empty():return
 var captured:=payload.duplicate(true)
 session.begin("Add generated sound")
 var clip:=session.insert_source(captured.stream,seconds,track_id,str(captured.label))
 if clip!=null:
  var actor:=session.document.actor_for_clip(clip.id)
  actor.values[&"generator"]={"id":captured.id,"settings":captured.settings.duplicate(true),"seed":captured.seed}
  actor.values[&"origin"]="procedural"
 session.commit()
 if clip!=null:fit_timeline()

func _queue_generator_drop(entry:Dictionary,settings:Dictionary,seed_value:int,seconds:float,track_id:String)->void:
 if KiwiAudioAutomationLane.is_lane(session.document.track_for_id(track_id)):notice("Choose an audio or instrument destination for generated audio.");return
 var payload:=_generator_payload(entry,settings,seed_value)
 jobs.request("drop_generator",func(job:RefCounted):
  var stream:=KiwiAudioSynthesis.generate(str(payload.id),payload.settings,int(payload.seed),44100,job)
  return {"stream":stream,"payload":payload,"track":track_id,"at":seconds},session.revision)

func _generator_drag_payload(entry:Dictionary)->Dictionary:
 if str(entry.get("id",""))==str(_library_entry.get("id","")) and _preview_matches_controls():
  return {"audio_generator_payload":_preview_payload.duplicate(true)}
 return {"generator":entry.duplicate(true),"seed":1}

func _capture_pattern_view(pattern:KiwiAudioPatternCanvas)->Dictionary:
 return {"zoom":pattern.pixels_per_beat,"row_height":pattern.row_height,"start_pitch":pattern.start_pitch,"scroll_beat":pattern.scroll_beat,"snap_beat":pattern.snap_beat,"selected":pattern.selected.duplicate()}

func _restore_pattern_view(pattern:KiwiAudioPatternCanvas,state:Dictionary)->void:
 pattern.pixels_per_beat=float(state.get("zoom",90));pattern.row_height=float(state.get("row_height",23 if pattern==steps else 16));pattern.start_pitch=int(state.get("start_pitch",84));pattern.scroll_beat=float(state.get("scroll_beat",0));pattern.snap_beat=float(state.get("snap_beat",.25));pattern.selected.assign(state.get("selected",[]));pattern.queue_redraw()

func _toggle_effect_bypass()->void:
 var owner:=_effect_owner();var stack:Array=owner.get("effects",[])
 session.action("A/B effects",func():
  if owner.has("ab_enabled_mask"):
   var mask:Array=owner.ab_enabled_mask
   for i in stack.size():stack[i].enabled=bool(mask[i]) if i<mask.size() else bool(stack[i].get("enabled",true))
   owner.erase("ab_enabled_mask")
  else:
   var mask:Array=[]
   for effect in stack:mask.append(bool(effect.get("enabled",true)));effect.enabled=false
   owner.ab_enabled_mask=mask)

func _analysis_identity(actor:ActorData)->String:
 return KiwiAudioEditSession.silence_source_identity(actor)

func _analysis_provenance_current(data:Dictionary,generation:int)->bool:
 var actor:=session.document.actor_for_clip(str(data.get("clip_id","")))
 return generation==session.revision and int(data.get("revision",-1))==session.revision and int(data.get("owner_id",0))==session.get_instance_id() and int(data.get("document_id",0))==session.document.get_instance_id() and session._before==null and session.primary_clip()!=null and session.primary_clip().id==str(data.get("clip_id","")) and actor!=null and not str(data.get("source_identity","")).is_empty() and str(data.get("source_identity",""))==_analysis_identity(actor)

func _accept_analysis_result(data:Dictionary,generation:int,loudness:bool=false)->void:
 if not _analysis_provenance_current(data,generation):return
 if loudness and _analysis_current() and str(_analysis_result.get("clip_id",""))==str(data.get("clip_id","")):
  _analysis_result.merge(data,true)
 else:_analysis_result=data.duplicate(true)
 # Detection caches stay outside the composition until an explicit edit.
 _refresh_analysis()

func _analysis_current()->bool:
 return _analysis_provenance_current(_analysis_result,int(_analysis_result.get("revision",-1)))

func _add_attack_markers()->void:
 if not _analysis_current():status.text="The analyzed source changed. Analyze it again.";return
 var id:=str(_analysis_result.clip_id);var clip:=session.document.clip_for_id(id);var actor:=session.document.actor_for_clip(id)
 var source_length:=float(_analysis_result.get("duration",0.0))
 var looping:=bool(actor.values.get(&"loop",false));var reverse:=bool(actor.values.get(&"reverse",false));var times:Array=[]
 var end:=clip.source_offset+clip.duration*clip.playback_speed
 for attack in _analysis_result.get("transients",[]):
  var time:=float(attack)
  var first:=int(ceil((clip.source_offset-time)/source_length)) if looping and source_length>0 else 0
  var last:=int(floor((end-time)/source_length)) if looping and source_length>0 else 0
  if last-first>4096:notice("Too many looped markers. Select a shorter clip.");return
  for cycle in range(first,last+1):
   var occurrence:=time+cycle*source_length
   if occurrence<clip.source_offset or occurrence>=end:continue
   var local:=(occurrence-clip.source_offset)/clip.playback_speed
   if reverse:local=clip.duration-local
   times.append(clip.start_time+local)
   if times.size()>4096:notice("Too many markers. Select a shorter clip.");return
 session.action("Add transient markers",func():
  for time in times:session.document.markers.append({"id":ActorData.new_id(),"time":time,"name":"Attack"}))

func pattern_tags_dialog()->void:
 var actor:=session.primary_actor();var clip:=session.primary_clip()
 if actor==null or clip==null or not session.can_edit(clip.id):return
 var target_session:=session;var target_id:=clip.id
 _name_dialog("Pattern tags (comma separated)",", ".join(PackedStringArray(actor.values.get(&"pattern_tags",[]))),func(text:String):
  if session!=target_session:return
  var current:=session.document.actor_for_clip(target_id)
  if current==null or not session.can_edit(target_id):return
  var tags:Array=[]
  for value in text.split(",",false):
   var tag:=value.strip_edges().substr(0,128)
   if not tag.is_empty() and not tags.has(tag) and tags.size()<32:tags.append(tag)
  session.action("Edit pattern tags",func():current.values[&"pattern_tags"]=tags))

func import_pattern_json()->void:
 var picker:=FileDialog.new();picker.title="Import data-only pattern JSON";picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE;picker.access=FileDialog.ACCESS_FILESYSTEM;picker.filters=PackedStringArray(["*.json ; Pattern JSON"]);add_child(picker)
 var target_session:=session;var target_revision:=session.revision
 picker.file_selected.connect(func(file:String):
  picker.queue_free()
  if session!=target_session or session.revision!=target_revision:notice("The document changed while choosing a pattern. Import it again.");return
  var result:=KiwiAudioPreset.import_pattern_json(file)
  if not str(result.get("error","")).is_empty():notice(str(result.error));return
  var error:=KiwiAudioPreset.apply_pattern(session,result.preset,playback.position,session.selected_track)
  if not error.is_empty():notice(error)
  else:_render_dirty_notes();status.text="Imported editable pattern: "+result.preset.label)
 picker.canceled.connect(picker.queue_free);picker.popup_centered_ratio(0.7)

func export_pattern_json()->void:
 var actor:=session.primary_actor()
 if actor==null or not KiwiAudioEditSession.is_note_source(actor):notice("Select a note pattern first.");return
 var preset:=KiwiAudioPreset.new();preset.kind="pattern";preset.label=actor.display_name;preset.data=KiwiAudioPreset.pattern_data(actor,session.document);preset.tags=PackedStringArray(preset.data.get("tags",[]))
 var encoded:=KiwiAudioPreset.to_json_text(preset)
 if not str(encoded.get("error","")).is_empty():notice(str(encoded.error));return
 var picker:=FileDialog.new();picker.title="Export data-only pattern JSON";picker.file_mode=FileDialog.FILE_MODE_SAVE_FILE;picker.access=FileDialog.ACCESS_FILESYSTEM;picker.filters=PackedStringArray(["*.json ; Pattern JSON"]);picker.current_file="pattern.json";add_child(picker)
 picker.file_selected.connect(func(file:String):
  picker.queue_free();var error:=KiwiAudioPreset.export_pattern_json(file,preset)
  if not error.is_empty():notice(error)
  else:status.text="Exported editable pattern JSON.")
 picker.canceled.connect(picker.queue_free);picker.popup_centered_ratio(0.7)

func _build_automation_controls(parent:Node)->void:
 var row:=HFlowContainer.new();parent.add_child(row)
 _label(row,"Automation")
 _automation_mode=OptionButton.new()
 for item in KiwiAudioAutomationRecording.MODES:_automation_mode.add_item(item)
 row.add_child(_automation_mode)
 _automation_mode.tooltip_text="One armed parameter. Write overwrites while playing; Touch punches only while held; Latch holds after release until Stop. Stop saves one undo action and returns to Read."
 _automation_mode.item_selected.connect(func(index:int):
  if recorder.recording or _record_busy:automation_recording.discard("Read: finish the audio take before recording automation.");return
  _finish_automation_pass("Mode changed")
  _finish_control_edits();session.commit();canvas.finish_automation_edit()
  call_deferred("_arm_automation_mode",str(KiwiAudioAutomationRecording.MODES[index]),session,_interaction_epoch))
 _button(row,"Target...",automation_record_target_dialog)
 _automation_target_label.custom_minimum_size.x=180;row.add_child(_automation_target_label)
 _automation_fader.custom_minimum_size=Vector2(180,24);_automation_fader.step=0.001;row.add_child(_automation_fader)
 _bind_automation_fader(_automation_fader)
 _button(row,"Finish pass",func():_finish_automation_pass("Pass finished"))
 _button(row,"Discard pass",func():automation_recording.discard("Read: pending automation discarded.");_refresh_automation_controls())
 _automation_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(_automation_status)
 _automation_status.add_theme_font_size_override("font_size",10)
 _refresh_automation_controls()

func _bind_automation_fader(fader:Slider)->void:
 var state:Dictionary={"held":false,"epoch":0,"blocked":false}
 fader.drag_started.connect(func():
  state.blocked=false;state.held=true;_automation_gesture_start();state.epoch=_interaction_epoch)
 fader.value_changed.connect(func(value:float):
  if state.blocked or (state.held and int(state.epoch)!=_interaction_epoch):return
  if automation_recording.mode!="Read":_automation_control_changed(value))
 var finish:=func(keep:bool):
  var valid:bool=state.held and int(state.epoch)==_interaction_epoch
  if state.held:state.blocked=true
  state.held=false
  if valid:
   if keep:_automation_gesture_end()
   else:
    _interaction_epoch+=1;automation_recording.discard("Read: gesture cancelled.")
 fader.drag_ended.connect(func(_changed:bool):finish.call(true);state.blocked=false)
 fader.focus_exited.connect(func():finish.call(true))
 fader.focus_entered.connect(func():
  if not state.held:state.blocked=false)
 fader.tree_exiting.connect(func():finish.call(true))
 fader.gui_input.connect(func(event:InputEvent):
  if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:finish.call(false);fader.accept_event())

func _arm_automation_mode(mode:String,owner_session:KiwiAudioEditSession,epoch:int)->void:
 if epoch!=_interaction_epoch or session!=owner_session or recorder.recording or _record_busy:return
 automation_recording.set_mode(mode);_refresh_automation_controls()

func _automation_status_changed(message:String)->void:
 if automation_recording.mode=="Read":
  if _automation_gesture_held:_interaction_epoch+=1
  _automation_gesture_held=false;_automation_release_timer.stop()
 _automation_status.text=message
 if _automation_mode!=null:_automation_mode.select(KiwiAudioAutomationRecording.MODES.find(automation_recording.mode))
 _automation_fader.editable=automation_recording.mode!="Read" and automation_recording.editable()

func _refresh_automation_controls()->void:
 var info:=automation_recording.info()
 _automation_target_label.text=str(info.get("label","Target unavailable"))
 if not info.is_empty():
  _automation_fader.min_value=float(info.minimum);_automation_fader.max_value=float(info.maximum)
  _automation_fader.set_value_no_signal(automation_recording.display_value(playback.position))
 _automation_status_changed(automation_recording.message)
 _automation_fader.tooltip_text="Records the armed owner curve at the playhead. Clip/effect and already-rendered audio are capture-only until Stop and replay. Mouse release ends Touch; keyboard/numeric gestures release after 250 ms idle."

func _mixer_target_editable(target:Dictionary)->bool:
 var info:=KiwiAudioAutomationLane.resolve(session.document,target)
 return not info.is_empty() and not bool(info.locked)

func _automation_consumes(target:Dictionary)->bool:
 return automation_recording.mode!="Read" and automation_recording.matches(target) and automation_recording.editable()

func _automation_gesture_start()->void:
 _interaction_epoch+=1
 _automation_release_timer.stop();_automation_gesture_held=true
 automation_recording.touch(playback.position)

func _automation_control_changed(value:float)->void:
 automation_recording.change(value,playback.position)
 if not _automation_gesture_held:_automation_release_timer.start()

func _automation_gesture_end()->void:
 _interaction_epoch+=1
 _automation_gesture_held=false;_automation_release_timer.stop()
 automation_recording.release(playback.position)

func _finish_automation_pass(reason:String)->void:
 _interaction_epoch+=1
 _automation_release_timer.stop();_automation_gesture_held=false
 automation_recording.finish(reason)
 if _automation_mode!=null:_refresh_automation_controls()

func _automation_seek(seconds:float,scrub:bool=false)->void:
 if recorder.recording or _record_busy:notice("Stop or cancel the take before seeking.");return
 _finish_automation_pass("Seek ended the pass")
 playback.seek(seconds,scrub)

func _choose_automation_record_target(target:Dictionary,lane_id:String="")->void:
 _finish_automation_pass("Target changed")
 _finish_control_edits();session.commit();canvas.finish_automation_edit()
 automation_recording.choose(target,lane_id)
 _layout.automation_panel.show()
 _refresh_automation_controls()

func automation_record_target_dialog()->void:
 _finish_automation_pass("Choosing an automation target")
 var dialog:=_window("Record one automation parameter",Vector2i(680,500));dialog.window.set_meta("audio_lane_window",true)
 var owner_session:=session
 _label(dialog.host,"Choose an unlocked parameter, then Write, Touch or Latch above the timeline. Each pass uses one undo action. Clip points use local clip time. Native mixer gain/pan can be monitored live; clip/effect or exact-rendered audio is heard after replay.")
 var search:=LineEdit.new();search.placeholder_text="Search owner or parameter";dialog.host.add_child(search)
 var scroller:=ScrollContainer.new();scroller.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(scroller)
 var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroller.add_child(list)
 var rebuild:=func():
  _clear(list)
  for info in KiwiAudioAutomationLane.options(session.document):
   if not search.text.is_empty() and not str(info.label).to_lower().contains(search.text.to_lower()):continue
   var button:=_button(list,str(info.label),func():
    if session!=owner_session:dialog.window.queue_free();return
    _choose_automation_record_target(info.target);dialog.window.queue_free())
   button.disabled=bool(info.locked)
 search.text_changed.connect(func(_text:String):rebuild.call());rebuild.call()
 _label(dialog.host,"30 Hz capture, linear decimation, 2,048 retained points, 64 gestures and one hour per pass. A loop wrap ends the pass. Unrelated edits cancel pending capture; Finish pass first to keep it. Offline curves retain the renderer's existing limits.")

func _update_automation_readouts()->void:
 if _automation_mode==null:return
 if not _automation_gesture_held and _automation_release_timer.is_stopped():
  _automation_fader.set_value_no_signal(automation_recording.display_value(playback.position))
 if not playback.playing or session._before!=null:return
 for entry in _automation_mixer_controls:
  if not is_instance_valid(entry.control):continue
  var value:=0.0
  if automation_recording.matches(entry.target):
   if _automation_gesture_held or not _automation_release_timer.is_stopped():continue
   value=automation_recording.display_value(playback.position)
  else:
   var info:=KiwiAudioAutomationLane.resolve(session.document,entry.target)
   if info.is_empty():continue
   value=KiwiAudioAutomationLane.value(KiwiAudioAutomationLane.points(info),playback.position,float(info.fallback))
  entry.control.set_value_no_signal(value)

func _exit_tree()->void:
 _optional_tools.cancel()
 _close_portable_review()
 _close_recovery_review()
 _close_silence_review()
 _record_cancel_requested=true;_record_generation+=1
 _record_prepared=null;_record_loop_preview=null;_record_loop_signature=""
 jobs.cancel_kind("record_prepare")
 _finish_control_edits()
 _finish_automation_pass("Workspace closed")

func _automation_lane_inspector(track:Dictionary)->void:
 _heading(inspector,"Automation lane")
 var id:=str(track.id);var info:=KiwiAudioAutomationLane.lane_info(session.document,id)
 var locked:=bool(track.get("locked",false))
 var name_input:=LineEdit.new();name_input.text=str(track.name);name_input.editable=not locked;inspector.add_child(name_input)
 name_input.text_submitted.connect(func(value:String):session.action("Rename automation lane",func():track.name=value))
 _label(inspector,str(info.get("label","Target missing or not selected. Retarget the lane to reconnect it.")))
 _label(inspector,"The curve belongs to its linked parameter. Retargeting or deleting this view does not erase any automation. Clip points follow the clip start; track and master points use absolute time.")
 _check(inspector,"Lock lane editing",locked,func(value:bool):session.action("Lock automation lane",func():track.locked=value))
 _button(inspector,"Edit curve",automation_lane_editor.bind(id))
 _button(inspector,"Record this parameter",func():_choose_automation_record_target(track.get("automation_target",{}),id)).disabled=not KiwiAudioAutomationLane.editable(session.document,id)
 _button(inspector,"Choose target...",automation_lane_target_dialog.bind(id)).disabled=locked
 var problem:=KiwiAudioAutomationLane.binding_error(session.document,id)
 if not problem.is_empty():
  _label(inspector,problem)
  _button(inspector,"Convert legacy lane to audio",func():session.action("Convert automation track to audio",func():track.kind="audio";track.erase("automation_target"))).disabled=locked
 _button(inspector,"Delete lane (keep curve)",func():session.delete_track(id)).disabled=locked or not problem.is_empty()
 _label(inspector,"On the timeline: Ctrl-click adds a point, drag moves it, right-click removes it, and double-click opens the curve editor. Edits commit when the drag ends.")

func automation_lane_target_dialog(lane_id:String="",initial:Dictionary={})->void:
 var owner_session:=session
 if not lane_id.is_empty():
  var lane:=session.document.track_for_id(lane_id)
  if lane.is_empty() or bool(lane.get("locked",false)):notice("Unlock the lane before changing its target.");return
  var problem:=KiwiAudioAutomationLane.binding_error(session.document,lane_id)
  if not problem.is_empty():notice(problem);return
  if initial.is_empty():initial=lane.get("automation_target",{}).duplicate(true)
 var dialog:=_window("Choose automation lane target",Vector2i(740,510));dialog.window.set_meta("audio_lane_window",true)
 _label(dialog.host,"Link a view to an existing curve. No points are copied, overwritten or moved. Missing targets remain reconnectable after a clip or effect is removed.")
 var search:=LineEdit.new();search.placeholder_text="Search tracks, clips, effects or parameters";dialog.host.add_child(search)
 var list:=ItemList.new();list.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(list)
 var available:=KiwiAudioAutomationLane.options(session.document)
 var chosen:Dictionary={"target":initial.duplicate(true)}
 var refresh:=func():
  list.clear()
  for entry in available:
   var text_value:=str(entry.label)+"  ["+str(entry.target.owner_kind)+" "+str(entry.target.owner_id).right(6)+"]"
   if not search.text.is_empty() and not text_value.to_lower().contains(search.text.to_lower()):continue
   var index:=list.add_item(text_value);list.set_item_metadata(index,entry.target)
   if KiwiAudioAutomationLane.key(entry.target)==KiwiAudioAutomationLane.key(chosen.target):list.select(index)
 list.item_selected.connect(func(index:int):chosen.target=list.get_item_metadata(index).duplicate(true))
 search.text_changed.connect(func(_text:String):refresh.call());refresh.call()
 var apply:=func():
  if session!=owner_session:notice("Return to the original audio document before choosing this target.");dialog.window.queue_free();return
  var target:Dictionary=chosen.target
  var info:=KiwiAudioAutomationLane.resolve(session.document,target)
  if info.is_empty():notice("Choose an available parameter from the list.");return
  if not lane_id.is_empty():
   var current:=session.document.track_for_id(lane_id)
   var problem:=KiwiAudioAutomationLane.binding_error(session.document,lane_id)
   if current.is_empty() or bool(current.get("locked",false)) or not problem.is_empty():notice(problem if not problem.is_empty() else "The lane is missing or locked.");return
  var selected:Dictionary={"id":lane_id}
  session.action("Add automation lane" if lane_id.is_empty() else "Retarget automation lane",func():
   var lane:=session.document.add_track(str(info.label),"automation") if lane_id.is_empty() else session.document.track_for_id(lane_id)
   lane.automation_target=target.duplicate(true);selected.id=str(lane.id)
   session.selected_ids.clear();session.selected_track=str(lane.id))
  session.selection_changed.emit();dialog.window.queue_free();automation_lane_editor(str(selected.id))
 _button(dialog.host,"Create lane" if lane_id.is_empty() else "Retarget (keep both curves)",apply)
 list.item_activated.connect(func(_index:int):apply.call())
 search.grab_focus()

func _show_automation_editor_in_lane(editor:KiwiAudioAutomationCanvas)->void:
 if editor.session!=session:notice("Return to the original document before creating a lane.");return
 var target:Dictionary={"owner_kind":editor.owner_kind,"owner_id":editor.owner_id,"effect_id":editor.effect_id,"parameter":editor.parameter}
 for track in session.document.tracks:
  if KiwiAudioAutomationLane.is_lane(track) and KiwiAudioAutomationLane.key(track.get("automation_target",{}))==KiwiAudioAutomationLane.key(target):
   session.selected_ids.clear();session.selected_track=str(track.id);session.selection_changed.emit();automation_lane_editor(str(track.id));return
 var info:=KiwiAudioAutomationLane.resolve(session.document,target)
 if info.is_empty():notice("The automation target no longer exists.");return
 var selected:Dictionary={"id":""}
 session.action("Show automation in timeline",func():
  var lane:=session.document.add_track(str(info.label),"automation");lane.automation_target=target.duplicate(true);selected.id=str(lane.id)
  session.selected_ids.clear();session.selected_track=str(lane.id))
 session.selection_changed.emit();automation_lane_editor(str(selected.id))

func automation_lane_editor(lane_id:String)->void:
 var lane:=session.document.track_for_id(lane_id)
 if not KiwiAudioAutomationLane.is_lane(lane):return
 var info:=KiwiAudioAutomationLane.lane_info(session.document,lane_id)
 if info.is_empty():automation_lane_target_dialog(lane_id);return
 var editor:=KiwiAudioAutomationCanvas.new();editor.session=session;editor.lane_id=lane_id
 editor.owner_kind=str(info.target.owner_kind);editor.owner_id=str(info.target.owner_id);editor.effect_id=str(info.target.get("effect_id",""));editor.parameter=str(info.parameter)
 editor.minimum=float(info.minimum);editor.maximum=float(info.maximum);editor.duration=maxf(0.1,float(info.duration))
 var dialog:=_window("Automation · "+str(info.label),Vector2i(780,650));dialog.window.set_meta("audio_lane_window",true)
 _label(dialog.host,"Click to add; drag to move; right-click to remove. This edits the linked curve in the shared audio document. No automation is copied onto the lane.")
 if not editor.can_edit():_label(dialog.host,"The lane or its source is locked. The curve is read-only until both are unlocked.")
 var row:=HFlowContainer.new();dialog.host.add_child(row)
 _choice(row,"Interpolation",["linear","smooth","hold"],"linear",editor.set_curve)
 _number(row,"View seconds",editor.duration,0.1,86400,0.1,func(value:float):editor.duration=value;editor.queue_redraw())
 editor.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(editor)
 var settings:Dictionary={"shape":"sine","sync":true,"beats":1.0,"rate":1.0,"center":clampf(float(info.fallback),editor.minimum,editor.maximum),"depth":(editor.maximum-editor.minimum)*0.1,"seed":1}
 var modulation:=HFlowContainer.new();dialog.host.add_child(modulation)
 _choice(modulation,"Shape",["sine","triangle","saw","square","random step","envelope"],"sine",func(value:String):settings.shape=value)
 _check(modulation,"Beat sync",true,func(value:bool):settings.sync=value)
 _number(modulation,"Beats/cycle",1,0.0625,32,0.0625,func(value:float):settings.beats=value)
 _number(modulation,"Rate Hz",1,0.01,20,0.01,func(value:float):settings.rate=value)
 _number(modulation,"Center",settings.center,editor.minimum,editor.maximum,0.01,func(value:float):settings.center=value)
 _number(modulation,"Depth",settings.depth,0,editor.maximum-editor.minimum,0.01,func(value:float):settings.depth=value)
 _number(modulation,"Seed",1,0,2147483647,1,func(value:float):settings.seed=int(value))
 var actions:=HFlowContainer.new();dialog.host.add_child(actions)
 _button(actions,"Generate / replace curve",func():editor.modulate(settings))
 _button(actions,"Clear linked curve",editor.clear_points)
 _button(actions,"Retarget lane...",func():dialog.window.queue_free();automation_lane_target_dialog(lane_id))
 _label(dialog.host,"Clip times are relative to the clip; track/master times are absolute. Gain/pan share the existing playback and export curves. Pitch and effect automation retain their existing offline backend requirements and approximation limits.")


func conductor_dialog()->void:
 _finish_automation_pass("Conductor editor opened")
 canvas.finish_automation_edit()
 _commit_parameter_edit()
 var dialog:=_window("Project conductor / grid",Vector2i(880,670));dialog.window.set_meta("audio_conductor_window",true)
 var owner:=session
 var editor:=KiwiAudioConductorControls.new();editor.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(editor);editor.setup(session,playback.position,func():return session==owner and not dialog.window.is_queued_for_deletion())
 editor.seek_requested.connect(func(seconds:float):if session==owner:_automation_seek(seconds,false))
 editor.applied.connect(func():if session==owner:dialog.window.queue_free())
 _button(dialog.host,"Uniformly retime note sources...",func():dialog.window.queue_free();retime_notes_dialog())

func retime_notes_dialog()->void:
 _finish_automation_pass("Uniform retime editor opened")
 canvas.finish_automation_edit()
 _commit_parameter_edit()
 var dialog:=_window("Uniformly retime note sources",Vector2i(650,380));dialog.window.set_meta("audio_conductor_window",true)
 var owner:=session;var document:=session.document;var revision:=session.revision
 _label(dialog.host,"This explicit retime scales editable note clip positions, durations and complete MIDI source tempo maps by the ratio of initial project BPM to target BPM. Project tempo points scale by the same ratio. It is one undo step.")
 _label(dialog.host,"Recorded audio, locked/frozen note tracks, absolute automation, markers and loop ranges stay unchanged. No audio time-warp is performed. Source beats remain editable. Rendered previews may need to refresh.")
 var state:={"bpm":session.document.tempo}
 _number(dialog.host,"Target initial BPM",state.bpm,20,400,0.01,func(value:float):state.bpm=value)
 var message:=_label(dialog.host,"")
 _button(dialog.host,"Apply uniform retime",func():
  if session!=owner or session.document!=document or session.revision!=revision:message.text="The composition changed. Close and reopen this dialog.";return
  var problem:=session.retime_note_sources(float(state.bpm))
  if not problem.is_empty():message.text=problem;return
  dialog.window.queue_free();_render_dirty_notes())

static func _stem_destination(destination:String,track:Dictionary,used:Dictionary)->String:
 # Preserve ordinary stem names while disambiguating this batch even on
 # case-insensitive filesystems and after filename sanitizing.
 var label:=str(track.get("name","Track")).validate_filename()
 if label.strip_edges().is_empty():label="Track"
 var stem:=destination.get_basename()+"_"+label
 var name:=stem+"."+destination.get_extension()
 var suffix:=2
 while used.has(name.to_lower()):
  name=stem+"_"+str(suffix)+"."+destination.get_extension();suffix+=1
 used[name.to_lower()]=true
 return name

# Recovery owns a separate worker so regular preview cancellation cannot publish
# a result into another tab or starve a queued checkpoint with preview jobs.
func _recovery_id()->String:
 if not session.has_meta("audio_recovery_id"):session.set_meta("audio_recovery_id",ActorData.new_id())
 return str(session.get_meta("audio_recovery_id"))

func _recovery_safe()->bool:
 return session!=null and session.document!=null and session._before==null and not automation_recording.active and not automation_recording.has_pending() and not recorder.recording and not _record_busy and _record_phase=="idle"

func _recovery_tick()->void:
 var now:=Time.get_ticks_msec()
 # Undo/Redo replaces the document but remains dirty. A clean in-place open
 # belongs to a new recovery lineage, even if a host reuses the session object.
 if session==_recovery_seen_session and session.document!=_recovery_seen_document and not session.dirty and session.has_meta("audio_recovery_id"):session.remove_meta("audio_recovery_id")
 if session!=_recovery_seen_session or session.document!=_recovery_seen_document or session.revision!=_recovery_seen_revision:
  _recovery_seen_session=session;_recovery_seen_document=session.document;_recovery_seen_revision=session.revision;_recovery_quiet_since=now
 if not _recovery_safe() or not session.dirty:return
 if now-_recovery_quiet_since<2000 or now-_recovery_last_at<15000:return
 _queue_recovery_checkpoint(false)

func _queue_recovery_checkpoint(manual:bool=false)->void:
 if not _recovery_safe():
  if manual:notice("Finish the current gesture, automation pass or recording before creating a checkpoint.")
  return
 if not session.dirty:
  if manual:notice("There are no unsaved edits to checkpoint.")
  return
 if _recovery_jobs.busy():
  if manual:notice("Recovery is busy. Try again when the current operation finishes.")
  return
 var key:=_recovery_id();var revision:=session.revision
 if not manual and int(_recovery_attempts.get(key,-1))==revision:return
 # Freeze nested editable metadata but share immutable source audio. Never
 # use capture_state() here: it commits live gestures.
 var frozen:=KiwiAudioDocument.Recovery.freeze(session.document)
 if not str(frozen.get("error","")).is_empty():
  _recovery_attempts[key]=revision;_recovery_status.text="Recovery: not saved (review status)";_recovery_status.tooltip_text=str(frozen.error)
  if manual:notice(str(frozen.error))
  return
 var snapshot:KiwiAudioDocument=frozen.document;var original_path:=document_path
 var store:=_recovery_store
 _recovery_attempts[key]=revision;_recovery_last_at=Time.get_ticks_msec()
 _recovery_checkpoint_context={"session":key,"revision":revision}
 _recovery_status.text="Recovery: saving checkpoint…"
 _recovery_jobs.request("checkpoint",func(work:RefCounted):
  var result:=store.checkpoint(snapshot,key,revision,original_path,work);result.session=key;result.revision=revision;return result,revision)

func _recovery_completed(kind:String,_generation:int,result:Variant)->void:
 if not result is Dictionary:return
 if kind=="checkpoint":
  var checkpoint_context:=_recovery_checkpoint_context;_recovery_checkpoint_context={}
  # The checkpoint remains useful for its original session. A late completion
  # cannot mark another document saved, clear dirty, or adopt a save path.
  if str(result.get("session",checkpoint_context.get("session","")))!=_recovery_id():return
  if not str(result.get("error","")).is_empty():
   _recovery_status.text="Recovery: not saved (review status)";_recovery_status.tooltip_text=str(result.error)
  else:_recovery_status.text="Recovery: checkpoint saved";_recovery_status.tooltip_text="Committed revision %d was checkpointed. Newer edits may not yet be included. Original composition files are untouched."%int(result.revision)
 elif kind=="recovery_discover":
  if _recovery_context_current(result.get("context",{})):_show_recovery_entries(result.context,result.get("entries",[]))
 elif kind=="recovery_restore":
  var context:Dictionary=result.get("context",{})
  if not _recovery_context_current(context) or not _recovery_safe() or session.dirty:
   notice("The active composition changed. Recovery was not opened; your work is intact.");return
  if not str(result.get("error","")).is_empty():notice(str(result.error));return
  var recovered:KiwiAudioDocument=result.get("document")
  if recovered==null:notice("The recovery document could not be decoded.");return
  _close_recovery_review()
  var previous_session:=session
  open_source(recovered,{"path":"","document_path":""})
  # A malformed portable manifest can refuse open without replacing this tab.
  if session==previous_session:return
  session.dirty=true;document_changed.emit();_refresh_all()
  _recovery_status.text="Recovery: restored unsaved copy"
  status.text="Recovered as an unsaved composition. Choose Save to create a new file."
  var missing:PackedStringArray=result.get("missing_assets",PackedStringArray())
  if not missing.is_empty():notice("The composition was recovered, but %d external audio source(s) are missing. Their paths and clip edits were preserved. Use Relink Source before playback/export.\n%s"%[missing.size(),"\n".join(missing)])

func _recovery_context_current(context:Dictionary)->bool:
 return is_inside_tree() and is_visible_in_tree() and context.get("owner")==session and context.get("document")==session.document and int(context.get("revision",-1))==session.revision and int(context.get("token",-1))==_recovery_review_generation

func _close_recovery_review()->void:
 _recovery_review_generation+=1
 if is_instance_valid(_recovery_window):_recovery_window.queue_free()
 _recovery_window=null
 _recovery_jobs.cancel_kind("recovery_discover");_recovery_jobs.cancel_kind("recovery_restore")

func review_recovery()->void:
 if _recovery_jobs.busy():notice("Recovery is busy. Try again when the current operation finishes.");return
 _close_recovery_review()
 var context:Dictionary={"owner":session,"document":session.document,"revision":session.revision,"token":_recovery_review_generation}
 var store:=_recovery_store
 _recovery_jobs.request("recovery_discover",func(_work:RefCounted):return {"context":context,"entries":store.discover()},int(context.token))

func _show_recovery_entries(context:Dictionary,entries:Array)->void:
 if not _recovery_context_current(context):return
 var dialog:=_window("Review audio recovery",Vector2i(760,520));_recovery_window=dialog.window
 dialog.window.close_requested.connect(_close_recovery_review)
 _label(dialog.host,"Checkpoints contain committed edits only. In-progress capture and edits since the last checkpoint may be absent. External media stays at its original path; embedded PCM WAV/MP3 audio is shared in recovery storage. Corrupt entries are left intact and cannot be restored.")
 if entries.is_empty():_label(dialog.host,"No recovery checkpoints were found.");_button(dialog.host,"Close",_close_recovery_review);return
 var list:=ItemList.new();list.size_flags_vertical=Control.SIZE_EXPAND_FILL;dialog.host.add_child(list)
 var details:=_label(dialog.host,"");details.custom_minimum_size.y=100
 var restore_button:=_button(dialog.host,"Restore selected as new unsaved composition",func():
  if list.get_selected_items().is_empty():return
  var entry:Dictionary=entries[list.get_selected_items()[0]]
  _request_recovery_restore(context,entry))
 restore_button.disabled=true
 for entry in entries:
  var stamp:=Time.get_datetime_string_from_unix_time(int(entry.get("time",0)))+" UTC"
  list.add_item((str(entry.get("title","Damaged checkpoint"))+" · "+stamp+" · r"+str(entry.get("revision","?"))) if str(entry.get("error","")).is_empty() else "Unavailable: "+str(entry.id))
 list.item_selected.connect(func(index:int):
  var entry:Dictionary=entries[index];var problem:=str(entry.get("error",""));var missing:PackedStringArray=entry.get("missing_assets",PackedStringArray())
  details.text=problem if not problem.is_empty() else "Original: %s\nRevision %d · %d missing external source(s). Metadata, edits and source paths are preserved. Restore does not overwrite or re-save the original. Save or close your current unsaved edits first."%[str(entry.get("source_path","(unsaved composition)")),int(entry.revision),missing.size()]
  restore_button.disabled=not problem.is_empty() or session.dirty or not _recovery_safe())
 _button(dialog.host,"Cancel",_close_recovery_review)

func _request_recovery_restore(context:Dictionary,entry:Dictionary)->void:
 if not _recovery_context_current(context) or not _recovery_safe():notice("Finish the current interaction, then review recovery again.");return
 if session.dirty:notice("Save your current unsaved composition before restoring recovery. No work was replaced.");return
 if _recovery_jobs.busy():return
 if not str(entry.get("error","")).is_empty():notice(str(entry.error));return
 var id:=str(entry.get("id",""));var store:=_recovery_store
 _recovery_jobs.request("recovery_restore",func(_work:RefCounted):
  var result:=store.restore(id);result.context=context;return result,int(context.token))


# Collected copies use a frozen revision, a separate worker and an owned stage.
# Publishing is a short main-thread rename only after the owner is still current.
func _portable_current(token:int)->bool:
 return not _portable_context.is_empty() and int(_portable_context.token)==token and token==_portable_generation and is_inside_tree() and is_visible_in_tree() and _portable_context.owner==session and _portable_context.document==session.document and int(_portable_context.revision)==session.revision and session._before==null and not recorder.recording and not _record_busy and not automation_recording.active and not automation_recording.has_pending()

func _close_portable_review(token:int=-1)->void:
 if token>=0 and (token!=_portable_generation or _portable_context.is_empty()):return
 _portable_generation+=1
 var context:=_portable_context;_portable_context={}
 _portable_jobs.cancel_all()
 if is_instance_valid(context.get("window")):context.window.queue_free()
 if is_instance_valid(context.get("picker")):context.picker.queue_free()

func review_portable_copy()->void:
 if recorder.recording or _record_busy or automation_recording.active or automation_recording.has_pending():notice("Finish the recording or automation pass before collecting media.");return
 _finish_control_edits();session.commit()
 _close_portable_review()
 var frozen:=KiwiAudioDocument.PortableCopy.freeze(session.document)
 if not str(frozen.get("error","")).is_empty():notice(str(frozen.error));return
 var token:=_portable_generation
 var dialog:=_window("Collect portable composition copy",Vector2i(780,580))
 _portable_context={"token":token,"owner":session,"document":session.document,"revision":session.revision,"window":dialog.window,"host":dialog.host,"phase":"inventory"}
 dialog.window.close_requested.connect(_close_portable_review.bind(token))
 dialog.window.tree_exiting.connect(_close_portable_review.bind(token))
 _label(dialog.host,"Reviewing the current composition and its media. Your open composition and original files stay intact. Editing or switching tabs cancels this copy.")
 _button(dialog.host,"Cancel",_close_portable_review.bind(token))
 var snapshot:KiwiAudioDocument=frozen.document;var source_path:=document_path
 _portable_jobs.request("inventory",func(work:RefCounted):return KiwiAudioDocument.PortableCopy.inventory(snapshot,source_path,work),token)

func _portable_completed(kind:String,token:int,result:Variant)->void:
 if not _portable_current(token):return # Unclaimed Stage frees its owned temporary copy.
 if not result is Dictionary:notice("The media collection returned an invalid result.");_close_portable_review(token);return
 if kind!="inventory" and not str(result.get("error","")).is_empty():
  var error:=str(result.error);_close_portable_review(token);notice(error);return
 if kind=="inventory":
  _portable_context.review=result;_portable_context.phase="review"
  _show_portable_inventory(token)
 elif kind=="prepare":
  var staged:Variant=result.get("staged")
  if staged==null:_close_portable_review(token);notice("No complete portable copy was prepared.");return
  # No await between owner/revision validation and atomic publication.
  var published:=KiwiAudioDocument.PortableCopy.publish(staged)
  _close_portable_review(token)
  if not str(published.get("error","")).is_empty():notice(str(published.error));return
  status.text="Collected portable copy: "+str(published.path)
  notice("Saved a new composition copy with its media:\n"+str(published.path)+"\n\nYour current composition remains open. Move or copy the entire collected folder together. Use Open Collected Copy to reopen it; save your current work first.")
  if LocalProjectFilesystem.node!=null:LocalProjectFilesystem.update_root_folder()

func _show_portable_inventory(token:int)->void:
 if not _portable_current(token):return
 var host:VBoxContainer=_portable_context.host;_clear(host)
 var review:Dictionary=_portable_context.review
 _label(host,"A separate editable composition and media folder will be created. Sources are copied byte-for-byte and deduplicated; embedded audio stays embedded. Clip windows, processing and original files stay intact.")
 var external:=float(review.get("external_bytes",0))/1048576.0;var embedded:=float(review.get("embedded_bytes",0))/1048576.0
 _label(host,"%d media reference(s) · %.2f MiB external · %.2f MiB embedded estimate"%[int(review.get("reference_count",0)),external,embedded])
 var list:=ItemList.new();list.size_flags_vertical=Control.SIZE_EXPAND_FILL;list.custom_minimum_size.y=140;host.add_child(list)
 for entry:Dictionary in review.get("entries",[]):
  var source_path:=str(entry.get("source",entry.get("path","Embedded audio")))
  list.add_item(source_path.get_file()+" · %.2f MiB"%(float(entry.get("bytes",0))/1048576.0))
  list.set_item_tooltip(list.item_count-1,source_path)
 for warning in review.get("warnings",[]):_label(host,str(warning))
 if not str(review.get("error","")).is_empty():
  _label(host,str(review.error));_button(host,"Close without copying",_close_portable_review.bind(token));return
 var name:=LineEdit.new();name.text=session.document.title.validate_filename().left(64);name.placeholder_text="Copy name";host.add_child(name)
 var destination:=_label(host,"Choose a parent folder. A unique new subfolder will be created; existing compositions are never selected for replacement.")
 var row:=HFlowContainer.new();host.add_child(row)
 _button(row,"Choose parent folder",_choose_portable_parent.bind(token))
 var collect:=_button(row,"Create reviewed copy",_prepare_portable_copy.bind(token));collect.disabled=true
 _button(row,"Cancel",_close_portable_review.bind(token))
 _portable_context.name=name;_portable_context.destination_label=destination;_portable_context.collect=collect;_portable_context.destination=""
 name.text_changed.connect(func(_text:String):
  if _portable_current(token):_portable_context.destination="";collect.disabled=true;destination.text="Choose the parent folder again to confirm the new copy name.")
 _label(host,"Changing this composition cancels the review. Adding new external media to a collected copy requires collecting a fresh copy before saving it as portable. This does not collect arbitrary project assets, Scene associations or executable resources.")

func _choose_portable_parent(token:int)->void:
 if not _portable_current(token) or str(_portable_context.phase)!="review":return
 if is_instance_valid(_portable_context.get("picker")):return
 var picker:=FileDialog.new();picker.title="Choose a parent folder for the new collected copy";picker.access=FileDialog.ACCESS_FILESYSTEM;picker.file_mode=FileDialog.FILE_MODE_OPEN_DIR
 picker.current_dir=ActorProjectFilePicker.root_directory();add_child(picker);_portable_context.picker=picker
 picker.canceled.connect(func():
  picker.queue_free()
  if _portable_current(token):_portable_context.erase("picker"))
 picker.dir_selected.connect(func(parent:String):
  picker.queue_free()
  if not _portable_current(token):return
  _portable_context.erase("picker")
  var label:=str(_portable_context.name.text).strip_edges().validate_filename().left(64)
  if label.is_empty():label="Audio copy"
  var destination:=parent.path_join(label+"-"+ActorData.new_id())
  _portable_context.destination=destination;_portable_context.destination_label.text="New folder: "+destination
  _portable_context.collect.disabled=false)
 picker.popup_centered(Vector2i(820,560))

func _prepare_portable_copy(token:int)->void:
 if not _portable_current(token) or str(_portable_context.phase)!="review":return
 var destination:=str(_portable_context.get("destination",""))
 if destination.is_empty():return
 _portable_context.phase="preparing";_portable_context.collect.disabled=true
 _portable_context.destination_label.text="Collecting into a private staging folder. Cancel or edit to discard; the final copy appears only when complete."
 var review:Dictionary=_portable_context.review
 _portable_jobs.request("prepare",func(work:RefCounted):return KiwiAudioDocument.PortableCopy.prepare(review,destination,work),token)

func open_collected_copy()->void:
 if session.dirty or session._before!=null:notice("Save your current composition before opening a collected copy. Your unsaved work has not been replaced.");return
 if recorder.recording or _record_busy or automation_recording.active or automation_recording.has_pending():notice("Finish the current recording or automation pass first.");return
 var owner:=session;var document:=session.document;var revision:=session.revision
 var picker:=FileDialog.new();picker.title="Open collected audio composition";picker.access=FileDialog.ACCESS_FILESYSTEM;picker.file_mode=FileDialog.FILE_MODE_OPEN_FILE
 picker.filters=PackedStringArray(["*.res,*.tres ; Editable audio composition"]);picker.current_dir=ActorProjectFilePicker.root_directory();add_child(picker)
 picker.canceled.connect(picker.queue_free)
 picker.file_selected.connect(func(chosen:String):
  picker.queue_free()
  if not is_inside_tree() or not is_visible_in_tree() or session!=owner or session.document!=document or session.revision!=revision or session.dirty or session._before!=null or recorder.recording or _record_busy or automation_recording.active or automation_recording.has_pending():notice("The active composition changed. Open the intended copy again after saving your work.");return
  open_source(chosen))
 picker.popup_centered(Vector2i(820,560))
