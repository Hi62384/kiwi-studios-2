extends SceneTree
var failed:=0
func check(condition:bool,label:String)->void:
 if not condition:failed+=1;push_error(label)
 print("PASS " if condition else "FAIL ",label)
func _initialize()->void:call_deferred("test")
func settle(workspace:KiwiAudioWorkspace)->void:
 for cycle in 5:
  await process_frame
  while workspace.jobs.busy():await process_frame
func test()->void:
 root.size=Vector2i(1440,1000);root.gui_embed_subwindows=true
 var w:=KiwiAudioWorkspace.new();root.add_child(w);await process_frame
 var original_samples:=PackedVector2Array();original_samples.resize(4410)
 for i in original_samples.size():original_samples[i]=Vector2.ONE*.1*sin(TAU*440*i/44100.0)
 var original_stream:=KiwiAudioSourceCache.to_wav(original_samples)
 w.open_source(KiwiAudioDocument.from_source(original_stream,"Imported waveform"));await settle(w)
 check(w.session.document.actors[0].values[&"audio"]==original_stream,"empty note metadata never resynthesizes imported audio")
 w.session.change_tempo(60);await settle(w)
 check(w.session.document.actors[0].values[&"audio"]==original_stream and is_equal_approx(w.session.document.clips[0].duration,.1),"changing tempo does not alter ordinary imported audio")
 w.open_source(KiwiAudioDocument.from_source(null,"Pattern test"))
 w.new_pattern(false);await settle(w)
 var c:=w.session.primary_clip();var a:=w.session.primary_actor();var original_id:=c.id
 a.values[&"notes"]=[KiwiAudioComposer.new_note(60,0,1,.5),KiwiAudioComposer.new_note(64,2,1,.5)];a.values[&"notes_dirty"]=true
 w._render_dirty_notes();await settle(w)
 check(is_equal_approx(c.duration,2.0),"initial four-beat pattern renders two seconds")
 w.session.split_selected(1.0);await settle(w)
 var right_id:String=w.session.selected_ids.back();w.session.select(right_id);c=w.session.primary_clip();a=w.session.primary_actor()
 check(is_equal_approx(c.source_offset,1.0) and is_equal_approx(c.duration,1.0),"split keeps source-relative right window")
 w.session.action("Transpose split",func():a.values[&"notes"][1].pitch=67;a.values[&"notes_dirty"]=true);w._render_dirty_notes();await settle(w)
 check(is_equal_approx(c.source_offset,1.0) and is_equal_approx(c.duration,1.0) and is_equal_approx(c.start_time,1.0),"editing split notes preserves offset, duration and position")
 check(w.session.document.actor_for_clip(original_id).values[&"notes"][1].pitch==64,"split note changes do not mutate left source events")
 w.session.action("Stretch right",func():c.playback_speed=.5;c.duration=2.0)
 a.values[&"notes_dirty"]=true;w._render_dirty_notes();await settle(w)
 check(is_equal_approx(c.playback_speed,.5) and is_equal_approx(c.duration,2.0) and is_equal_approx(c.source_offset,1.0),"rerender preserves stretched clip geometry")
 # Initial conductor edits now explicitly preserve source/absolute timing;
 # musical window scaling belongs to the separate uniform-retime action.
 w.session.retime_note_sources(60);w._render_dirty_notes();await settle(w)
 c=w.session.document.clip_for_id(right_id);a=w.session.document.actor_for_clip(right_id)
 check(is_equal_approx(c.start_time,2.0) and is_equal_approx(c.source_offset,2.0) and is_equal_approx(c.duration,4.0) and is_equal_approx(c.playback_speed,.5),"tempo change scales musical window without destroying stretch")
 w.session.undo();await settle(w);c=w.session.document.clip_for_id(right_id)
 check(is_equal_approx(w.session.document.tempo,120) and is_equal_approx(c.source_offset,1.0) and is_equal_approx(c.duration,2.0) and is_equal_approx(c.playback_speed,.5),"tempo undo restores exact source window")
 w.session.redo();await settle(w);c=w.session.document.clip_for_id(right_id)
 check(is_equal_approx(c.source_offset,2.0) and is_equal_approx(c.duration,4.0),"tempo redo rebuilds scaled source window")
 w.open_source(KiwiAudioDocument.from_source(null,"Undo note length"));w.new_pattern(false);await settle(w)
 w.piano.scroll_beat=4.0
 var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=Vector2(90,60);w.piano._gui_input(event);await settle(w)
 var clip_id:=w.session.primary_clip().id
 check(is_equal_approx(float(w.session.primary_actor().values[&"pattern_beats"]),5.0) and is_equal_approx(w.session.primary_clip().duration,2.5),"note insertion expands full pattern and audible duration")
 w.session.undo();await settle(w)
 check(w.session.document.actor_for_clip(clip_id).values[&"notes"].is_empty() and is_equal_approx(w.session.document.clip_for_id(clip_id).duration,2.0),"undo restores empty pattern and original length")
 w.session.redo();await settle(w)
 check(w.session.document.actor_for_clip(clip_id).values[&"notes"].size()==1 and is_equal_approx(w.session.document.clip_for_id(clip_id).duration,2.5),"redo retains extended length inside one note-edit action")
 w.session.select(clip_id);w.piano.selected.assign([str(w.session.primary_actor().values[&"notes"][0].id)]);w.piano.copy()
 var before:=var_to_str(w.session.primary_actor().values[&"notes"]);w.session.document.track_for_clip(clip_id).locked=true
 w.piano.delete_selected();w.piano.paste(8);w.piano.quantize();w.humanize_notes();w.arpeggiate_notes();w.harmonize_notes()
 check(var_to_str(w.session.primary_actor().values[&"notes"])==before,"locked track blocks all note toolbar and keyboard mutations")
 w.session.document.track_for_clip(clip_id).locked=false;w.piano.delete_selected();await settle(w)
 check(w.session.primary_actor().values[&"notes"].is_empty(),"delete last note regenerates silence")
 var samples:PackedVector2Array=KiwiAudioSourceCache.decode(w.session.primary_actor().values[&"audio"]).get("samples",PackedVector2Array());var peak:=0.0
 for sample in samples:peak=maxf(peak,maxf(absf(sample.x),absf(sample.y)))
 check(samples.size()>0 and is_zero_approx(peak),"empty pattern audio is actually silent")
 w.session.undo();await settle(w);w.session.redo();await settle(w)
 check(w.session.primary_actor().values[&"notes"].is_empty(),"empty-note redo refreshes rendered signature")
 check(w.session.document.validate().is_empty(),"edited pattern document remains valid")
 w.session.primary_actor().values[&"notes"]=[KiwiAudioComposer.new_note(60,.5,.25,.8),KiwiAudioComposer.new_note(64,1.5,.25,.8)]
 w.piano.selected.clear();w.piano._original.clear()
 for note in w.piano.notes():w.piano.selected.append(str(note.id));w.piano._original[note.id]=note.duplicate(true)
 w.piano._drag="move";w.piano._origin=Vector2.ZERO;w.piano._gesture.begin(w.session,"Move note group");w.piano._drag_clip=w.session.primary_clip().id
 var motion:=InputEventMouseMotion.new();motion.position=Vector2(-1000,10000);w.piano._gui_input(motion)
 check(is_zero_approx(float(w.piano.notes()[0].start)) and is_equal_approx(float(w.piano.notes()[1].start),1.0),"dragging notes past zero preserves their time spacing")
 check(int(w.piano.notes()[0].pitch)==0 and int(w.piano.notes()[1].pitch)==4,"dragging chords beyond pitch bounds preserves intervals")
 w.piano._drag="";w.session.cancel();await settle(w)
 w.library.remember_effect("compressor");w.library.remember_effect("lowpass")
 var ranked:=w.library.ranked_effects()
 check(str(ranked[0].id)=="lowpass" and str(ranked[1].id)=="compressor","recently used effects rank first in add-effect browser")
 var config:=ConfigFile.new();config.load("user://audio_workspace/library.cfg")
 check((config.get_value("library","recent",[]) as Array).has("effect_lowpass"),"recent effect ranking persists through library settings")
 w.session.document.track_for_clip(clip_id).locked=true;var child_count:=w.get_child_count();w.add_effect_dialog();w.effect_chain_dialog()
 check(w.get_child_count()==child_count,"locked track blocks effect and chain editor creation")
 w.session.document.track_for_clip(clip_id).locked=false;w.session.add_track("audio","Other track");var other_id:=w.session.selected_track;w.session.select(clip_id)
 var track_index:=w.session.document.tracks.find(w.session.document.track_for_id(other_id));var select_track:=InputEventMouseButton.new();select_track.button_index=MOUSE_BUTTON_LEFT;select_track.pressed=true;select_track.position=Vector2(35,KiwiAudioTimelineCanvas.RULER+track_index*w.canvas.track_height+15)
 w.canvas._gui_input(select_track)
 check(w.session.selected_ids.is_empty() and w.session.selected_track==other_id and w._effect_owner()==w.session.document.track_for_id(other_id),"clicking a track header changes inspector and effects to that track")
 w.stop();w.queue_free();await process_frame;await create_timer(.1).timeout
 print("AUDIO_PATTERN_GEOMETRY failures=",failed);quit(failed)
