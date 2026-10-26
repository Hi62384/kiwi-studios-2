extends SceneTree
var failed:=0
func check(condition:bool,label:String)->void:
 if not condition:failed+=1;push_error(label)
 print("PASS " if condition else "FAIL ",label)
func _initialize()->void:
 call_deferred("test")
func wait_jobs(workspace:KiwiAudioWorkspace)->void:
 while workspace.jobs.busy():await process_frame
 await process_frame
func test()->void:
 root.size=Vector2i(1440,1000);root.gui_embed_subwindows=true
 var workspace:=KiwiAudioWorkspace.new();root.add_child(workspace)
 await process_frame
 check(workspace.library.entries.size()>=80,"actual library populated")
 var first:=KiwiAudioDocument.from_source(null,"First composition");workspace.open_source(first)
 var samples:=PackedVector2Array();samples.resize(4410)
 for i in samples.size():samples[i]=Vector2(sin(TAU*440*i/44100.0)*0.1,sin(TAU*660*i/44100.0)*0.08)
 var stream:=KiwiAudioSourceCache.to_wav(samples)
 var clip:=workspace.session.insert_source(stream,0,workspace.session.selected_track,"Stereo test")
 await process_frame
 var first_state:=workspace.capture_state();var first_session:=workspace.session
 workspace.open_source(KiwiAudioDocument.from_source(null,"Second composition"))
 check(first_session.document.title=="First composition" and first_session.document.clips.size()==1,"tab documents independent")
 workspace.open_source(first,first_state)
 check(workspace.session==first_session,"tab history restored")
 workspace.session.select(clip.id)
 workspace.edit_clip(clip.id)
 workspace.waveform.selection=Vector2i(100,1000)
 workspace._perform_wave_edit("reverse",0)
 await wait_jobs(workspace)
 var fade_reported:=false
 for child in workspace.get_children():
  if child is AcceptDialog and child.dialog_text.contains("fade"):fade_reported=true
 check(workspace.session.document.clips.size()==1 and workspace.session.primary_actor().values[&"audio"]==stream and fade_reported,"selection crossing an existing fade is refused without mutation")
 for child in workspace.get_children():
  if child is AcceptDialog:child.queue_free()
 await process_frame
 workspace.waveform.selection=Vector2i(400,2000)
 workspace._perform_wave_edit("reverse",0)
 await wait_jobs(workspace)
 var edited:=workspace.session.primary_actor()
 check(edited!=null and edited.values[&"audio"]!=stream,"waveform edit uses new immutable source")
 if edited==null or edited.values[&"audio"]==stream:
  workspace.queue_free();await process_frame;quit(failed);return
 workspace.undo();await process_frame
 check(workspace.session.primary_actor().values[&"audio"]==stream,"waveform undo restores original source")
 workspace._refresh_all()
 for method in ["command_palette","customize_shortcuts","add_track_dialog","add_effect_dialog","effect_chain_dialog","music_dialog","automation_dialog","send_dialog","recording_options","take_dialog","ducking_dialog","export_dialog"]:
  print("DIALOG ",method);workspace.call(method);await process_frame
  for child in workspace.get_children():
   if child is Window:child.queue_free()
  await process_frame
 workspace.new_pattern(false);await wait_jobs(workspace)
 var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=Vector2(100,60);workspace.piano._gui_input(event)
 await wait_jobs(workspace)
 check(not workspace.session.primary_actor().values.get(&"notes",[]).is_empty(),"new editable instrument pattern")
 workspace.humanize_notes();workspace.arpeggiate_notes();await wait_jobs(workspace)
 workspace.analyze_clip();await wait_jobs(workspace)
 check(not workspace._analysis_result.is_empty(),"analysis background result")
 var saved:=KiwiAudioWorkspace.save_document(workspace.session.document,"user://functional.audio.tres")
 check(saved==OK,"native composition atomic save")
 var loaded:=load("user://functional.audio.tres") as KiwiAudioDocument
 check(loaded!=null and loaded.clips.size()==workspace.session.document.clips.size(),"native composition reopen")
 workspace.stop();workspace.queue_free();await process_frame;await create_timer(.1).timeout
 print("AUDIO_UI_FUNCTIONAL failures=",failed);quit(failed)
