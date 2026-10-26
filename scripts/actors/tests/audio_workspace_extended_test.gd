extends SceneTree
var failed:=0
class SimulatedRecorder extends ActorAudioRecorder:
 var recorded:AudioStreamWAV
 var starts:=0
 func _process(_delta:float)->void:pass
 func start()->String:
  starts+=1;recording=true;return ""
 func stop()->AudioStreamWAV:
  recording=false
  await get_tree().create_timer(0.03).timeout
  return recorded
 func stop_to_files()->Dictionary:
  recording=false
  await get_tree().create_timer(.03).timeout
  var directory:=ProjectSettings.globalize_path("user://audio_workspace/takes/"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(directory)
  var path:=directory.path_join("microphone.wav");recorded.save_to_wav(path)
  return {"directory":directory,"paths":[path],"mono":false,"error":""}
func check(condition:bool,label:String)->void:
 if not condition:failed+=1;push_error(label)
 print("PASS " if condition else "FAIL ",label)
func _initialize()->void:call_deferred("test")
func wait_jobs(workspace:KiwiAudioWorkspace)->void:
 while workspace.jobs.busy():await process_frame
 await process_frame
func test()->void:
 root.size=Vector2i(1440,1000);root.gui_embed_subwindows=true
 var workspace:=KiwiAudioWorkspace.new();workspace.recorder.free();var recorder:=SimulatedRecorder.new();workspace.recorder=recorder
 var samples:=PackedVector2Array();samples.resize(4410)
 for i in samples.size():samples[i]=Vector2.ONE*sin(TAU*400*i/44100.0)*0.1
 recorder.recorded=KiwiAudioSourceCache.to_wav(samples)
 root.add_child(workspace);await process_frame
 var doc:=KiwiAudioDocument.from_source(null,"Recording target");doc.time_signature=Vector2i(6,8);doc.loop_enabled=true
 workspace.open_source(doc)
 check(workspace.loop_button.button_pressed and workspace.meter_input.get_item_text(workspace.meter_input.selected)=="6/8","toolbar restores document meter and loop")
 var original_count:=workspace.session.document.tracks.size()
 workspace._library_add({"kind":"instrument","id":"piano","label":"Test piano"})
 check(workspace.session.document.tracks.size()==original_count+1 and workspace.session.document.clips.size()==1,"library instrument creates track and pattern")
 workspace.undo();await process_frame
 check(workspace.session.document.tracks.size()==original_count and workspace.session.document.clips.is_empty(),"instrument creation is one undo action")
 workspace.redo();await process_frame
 var clip:=workspace.session.document.clips[0];workspace.session.select(clip.id)
 var effect:=KiwiAudioEffects.create("lowpass");workspace.session.primary_actor().values[&"effects"]=[effect]
 workspace.effect_automation_dialog(0);await process_frame
 var editors:Array=[]
 for child in workspace.find_children("*","KiwiAudioAutomationCanvas",true,false):editors.append(child)
 # A script class does not participate in native find_children type filtering on all Godot versions.
 if editors.is_empty():collect_editors(workspace,editors)
 check(editors.size()==1,"effect automation editor opens for supported parameters")
 if not editors.is_empty():
  var editor:KiwiAudioAutomationCanvas=editors[0];editor.modulate({"center":1000,"depth":500,"rate":1,"sync":false})
  check(not workspace.session.primary_actor().values[&"effects"][0].automation.is_empty(),"effect modulation writes editable parameter points")
  workspace.session.document.track_for_clip(clip.id).locked=true
  var before:=var_to_str(editor.points());editor.clear_points();editor.modulate({"center":500})
  check(var_to_str(editor.points())==before,"locked track blocks automation editing")
 for child in workspace.get_children():
  if child is Window:child.queue_free()
 await process_frame
 workspace.open_source(KiwiAudioDocument.from_source(null,"Recording A"));var target_session:=workspace.session
 var notifications:Array=[];workspace.background_document_changed.connect(func(changed:KiwiAudioEditSession):notifications.append(changed))
 workspace.toggle_recording();check(recorder.recording,"simulated recorder starts")
 workspace.open_source(KiwiAudioDocument.from_source(null,"Recording B"));await create_timer(0.1).timeout
 while workspace._record_busy:await process_frame
 check(target_session.document.clips.size()==1 and target_session.document.takes.size()==1,"asynchronous take stays with starting document")
 check(workspace.session.document.clips.is_empty(),"tab switch does not attach take to new composition")
 check(not notifications.is_empty() and notifications[0]==target_session,"background take marks original tab dirty")
 target_session.undo()
 check(target_session.document.clips.is_empty() and target_session.document.takes.is_empty(),"one undo removes recorded clip and take metadata")
 workspace.open_source(KiwiAudioDocument.from_source(recorder.recorded,"Freeze source"));var freeze_id:=workspace.session.selected_track;var original_source:Variant=workspace.session.document.actors[0].values[&"audio"]
 workspace.session.document.tracks[0].solo=true;workspace.freeze_track();await wait_jobs(workspace)
 var original_track:=workspace.session.document.track_for_id(freeze_id)
 check(original_track.has("frozen_track") and original_track.locked and original_track.mute,"freeze produces a rendered replacement and locks source")
 var frozen:=workspace.session.document.track_for_id(str(original_track.get("frozen_track","")))
 check(bool(frozen.get("solo",false)) and not original_track.solo,"freeze transfers solo state to audible replacement")
 check(workspace.session.document.actors[0].values[&"audio"]==original_source,"freeze preserves original source resource")
 workspace.session.selected_track=str(frozen.get("id",""));workspace.unfreeze_track();await wait_jobs(workspace)
 check(workspace.session.document.tracks.size()==1 and workspace.session.document.clips.size()==1,"unfreeze removes only frozen replacement")
 original_track=workspace.session.document.track_for_id(freeze_id)
 check(not original_track.mute and not original_track.locked and original_track.solo,"unfreeze restores original track state")
 workspace.undo();await process_frame
 check(workspace.session.document.tracks.size()==2,"unfreeze is undoable")
 workspace.redo();await process_frame
 check(workspace.session.document.tracks.size()==1,"unfreeze redo restores editable source")
 workspace._countdown=1;var starts:=recorder.starts;workspace.toggle_recording();workspace.open_source(KiwiAudioDocument.from_source(null,"Cancelled countdown"));await create_timer(1.1).timeout
 check(recorder.starts==starts and not workspace._record_busy,"tab switch cancels recording countdown")
 workspace.queue_free();await process_frame;await create_timer(0.1).timeout
 print("AUDIO_UI_EXTENDED failures=",failed);quit(failed)
func collect_editors(node:Node,output:Array)->void:
 if node is KiwiAudioAutomationCanvas:output.append(node)
 for child in node.get_children():collect_editors(child,output)
