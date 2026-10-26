extends SceneTree
var checks:=0
var failures:=0
func expect(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1;print("FAIL: "+label)
func state(session:KiwiAudioEditSession)->String:
 var items:Array=[]
 for i in session.document.clips.size():
  var c:=session.document.clips[i];var a:=session.document.actors[i]
  items.append([c.id,c.actor_id,c.start_time,c.duration,c.source_offset,c.playback_speed,c.layer,a.id,a.parent_id,a.section_id,a.values])
 return var_to_str([items,session.document.tracks,session.document.markers,session.document.master])
func _initialize()->void:call_deferred("run")
func run()->void:
 var stream:=AudioStreamWAV.new();stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=12000;stream.stereo=true
 var bytes:=PackedByteArray();bytes.resize(8*12000*4);stream.data=bytes
 var original:="user://cross_original.wav";var replacement:="user://cross_replacement.wav"
 expect(stream.save_to_wav(original)==OK and stream.save_to_wav(replacement)==OK,"synthetic original and replacement saved")
 var source_hash:=FileAccess.get_sha256(original);var replacement_hash:=FileAccess.get_sha256(replacement)
 var session:=KiwiAudioEditSession.new();session.open(KiwiAudioDocument.new());var track:=session.document.tracks[0]
 var clip:=session.document.insert_source(original,track.id,2,"Dialogue");clip.source_offset=0.25;clip.duration=3;clip.playback_speed=2
 var actor:=session.document.actor_for_clip(clip.id);actor.values.fade_in=0;actor.values.fade_out=0;actor.parent_id="preserved"
 var later:=session.document.insert_source(original,track.id,8,"Following");later.duration=0.5
 session.selected_ids.assign([clip.id]);var id:=clip.id;var before:=state(session);var first_signature:=RecordingSignature.signature(session.document)
 var old_plan:KiwiAudioEditSession.SilencePlan=session.create_silence_plan(id,[{"start":1.0,"end":2.0}],8,0,session.silence_source_identity(actor)).plan
 var probe:=session.probe_audio_relink(replacement)
 expect(str(probe.error).is_empty(),"batch5 probe validates actual replacement WAV")
 expect(session.relink_audio_sources([id],original,probe).is_empty(),"batch5 relink applies before cleanup")
 expect(not old_plan.current(session),"batch5 relink invalidates earlier batch7 review")
 expect(RecordingSignature.signature(session.document)!=first_signature,"batch5 relink invalidates batch6 backing signature")
 var relinked:=state(session);var relink_signature:=RecordingSignature.signature(session.document)
 actor=session.document.actor_for_clip(id)
 var analyzed:=KiwiAudioAnalysis.analyze(ActorAudio.source(actor.values.audio),-42,0.25)
 expect(str(analyzed.error).is_empty() and state(session)==relinked,"batch7 analysis remains read-only after batch5 relink")
 expect(RecordingSignature.signature(session.document)==relink_signature,"read-only analysis does not invalidate batch6 backing")
 var plan:KiwiAudioEditSession.SilencePlan=session.create_silence_plan(id,[{"start":1.0,"end":2.0}],8,0.2,session.silence_source_identity(actor)).plan
 var gesture:=KiwiAudioEditSession.Gesture.new();gesture.begin(session,"Live mixer adjustment")
 var refused:=session.apply_silence_plan(plan,[0],"track_following")
 expect(not str(refused.error).is_empty() and session.history.get_history_count()==1,"batch4 gesture blocks batch7 nested cleanup")
 gesture.finish(session,false)
 expect(not plan.current(session),"batch4 cancelled gesture invalidates plan revision")
 actor=session.document.actor_for_clip(id)
 plan=session.create_silence_plan(id,[{"start":1.0,"end":2.0}],8,0.2,session.silence_source_identity(actor)).plan
 var applied:=session.apply_silence_plan(plan,[0],"track_following")
 expect(str(applied.error).is_empty() and bool(applied.changed),"batch7 cleanup follows relink with explicit ripple")
 expect(session.history.get_history_count()==2,"relink and cleanup remain two separate undo actions")
 expect(RecordingSignature.signature(session.document)!=relink_signature,"batch7 cleanup invalidates batch6 backing signature")
 var cleaned:=state(session);var clean_signature:=RecordingSignature.signature(session.document)
 expect(absf(session.document.clip_for_id(later.id).start_time-7.7)<0.000001,"retained pause and speed control ripple amount")
 var ids:=session.audio_source_clips(id)
 expect(ids.size()==2,"batch7 fragments are discoverable by batch5 shared-source relink")
 var follow_probe:=session.probe_audio_relink(original)
 expect(session.relink_audio_sources(ids,replacement,follow_probe).is_empty(),"batch5 can relink every resulting dialogue fragment")
 expect(session.history.get_history_count()==3,"fragment-group relink remains one extra Undo")
 session.undo();expect(state(session)==cleaned,"Undo group relink restores exact cleaned pieces")
 session.undo();expect(state(session)==relinked,"Undo cleanup restores exact prior relink state")
 session.undo();expect(state(session)==before,"Undo original relink restores original paths and geometry")
 session.redo();expect(state(session)==relinked,"Redo relink restores first result")
 session.redo();expect(state(session)==cleaned and RecordingSignature.signature(session.document)==clean_signature,"Redo cleanup restores IDs and backing signature")
 expect(FileAccess.get_sha256(original)==source_hash and FileAccess.get_sha256(replacement)==replacement_hash,"all three workflows preserve original/replacement source bytes")
 # Save the actual resource and reopen without a cache; newer pieces are normal
 # actors/clips compatible with the existing batch1 save resource representation.
 var saved:="user://cross_cleanup.audio.tres"
 expect(ResourceSaver.save(session.document,saved)==OK,"composed result serializes with existing document resource")
 var reopened:=ResourceLoader.load(saved,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiAudioDocument
 expect(reopened!=null,"composed result reopens as actual document")
 if reopened!=null:
  var next:=KiwiAudioEditSession.new();next.open(reopened)
  expect(state(next)==cleaned,"save/reopen preserves every reference, ID and edit in composed result")
  expect(RecordingSignature.signature(next.document)==clean_signature,"file-backed saved state preserves recording signature")
  var issue:=next.document.validate();expect(issue.is_empty(),"composed result passes existing document validation")

 # Recovery preserves the fully composed edit chain without changing its live
 # revision/Undo/recording signature, and restores into an independent owner.
 var store:=KiwiAudioDocument.Recovery.new();store.directory="user://cross_recovery_"+ActorData.new_id()
 var retained_revision:=session.revision;var retained_history:=session.history.get_history_count()
 var frozen:=KiwiAudioDocument.Recovery.freeze(session.document)
 expect(str(frozen.error).is_empty(),"batch8 freezes composed relink/cleanup metadata")
 var checkpoint:=store.checkpoint(frozen.document,"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",session.revision,saved)
 expect(str(checkpoint.error).is_empty(),"batch8 checkpoints composed result")
 expect(state(session)==cleaned and session.revision==retained_revision and session.history.get_history_count()==retained_history,"checkpoint preserves earlier Undo/Redo and revision")
 expect(RecordingSignature.signature(session.document)==clean_signature,"checkpoint does not invalidate prepared backing signature")
 var recovered:=store.restore(str(checkpoint.id))
 expect(str(recovered.error).is_empty(),"composed checkpoint restores")
 if str(recovered.error).is_empty():
  var restored:=KiwiAudioEditSession.new();restored.open(recovered.document)
  expect(state(restored)==cleaned,"recovery retains every relink/cleanup window and metadata")
  expect(restored.history.get_history_count()==0,"recovery creates independent Undo history")
  expect(RecordingSignature.signature(restored.document)==clean_signature,"file-backed recovery retains recording preparation identity")
  expect(not plan.current(restored),"old dialogue plan cannot apply to recovered owner")
  var restored_ids:=restored.audio_source_clips(id)
  expect(restored_ids.size()==2,"recovered split clips remain shared-source relinkable")
  expect(restored.relink_audio_sources(restored_ids,replacement,follow_probe).is_empty(),"relink works after recovery")
  restored.undo();expect(state(restored)==cleaned,"post-recovery relink Undo preserves recovered edits")
  var restored_actor:=restored.document.actor_for_clip(id);var restored_clip:=restored.document.clip_for_id(id)
  var cut_start:=restored_clip.source_offset+0.1
  var next_plan:=restored.create_silence_plan(id,[{"start":cut_start,"end":cut_start+0.1}],8,0,restored.silence_source_identity(restored_actor))
  expect(str(next_plan.error).is_empty(),"new dialogue plan can be reviewed after recovery")
  if str(next_plan.error).is_empty():
   var next_apply:=restored.apply_silence_plan(next_plan.plan,[0],"clip")
   expect(str(next_apply.error).is_empty() and bool(next_apply.changed),"dialogue cleanup can apply after recovery: "+str(next_apply.error))
   restored.undo();expect(state(restored)==cleaned,"post-recovery cleanup Undo preserves recovered result")
 expect(FileAccess.get_sha256(original)==source_hash and FileAccess.get_sha256(replacement)==replacement_hash,"recovery and subsequent edits preserve source bytes")
 print("CROSS_FLOW_CHECKS=%d FAILURES=%d"%[checks,failures]);quit(0 if failures==0 else 1)
