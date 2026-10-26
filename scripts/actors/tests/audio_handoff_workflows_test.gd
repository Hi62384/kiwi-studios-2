extends SceneTree
const Batch=preload("res://Workspaces/AudioWorkspace/audio_dialogue_batch.gd")
const Bundle=preload("res://Workspaces/AudioWorkspace/audio_layer_bundle.gd")
const Store=preload("res://Workspaces/AudioWorkspace/audio_preset_store.gd")
const Linked=preload("res://Workspaces/AudioWorkspace/audio_linked_patterns.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func run()->void:
	var samples:=PackedVector2Array();samples.resize(32000)
	for i in samples.size():samples[i]=Vector2(.1,.1)
	var stream:=KiwiAudioSourceCache.to_wav(samples,8000)
	var session:=KiwiAudioEditSession.new();session.document=KiwiAudioDocument.new()
	var track:=session.document.add_track("Dialogue");var a:=session.document.insert_source(stream,track.id,0,"One");var b:=session.document.insert_source(stream,track.id,5,"Two")
	for actor in session.document.actors:actor.values[&"fade_in"]=0.;actor.values[&"fade_out"]=0.
	var entries:Array=[]
	for clip in session.document.clips:entries.append({"id":clip.id,"data":{"duration":4.,"silences":[{"start":1.,"end":2.}]},"identity":KiwiAudioEditSession.silence_source_identity(session.document.actor_for_clip(clip.id))})
	var prepared:=Batch.prepare(session,entries,0.)
	check(str(prepared.get("error","")).is_empty(),"Multi-clip plans preserve one revision")
	var preview:=Batch.review(session,prepared.plans,[[0],[0]],"track_following",.02)
	check(str(preview.get("error","")).is_empty() and is_equal_approx(float(preview.get("removed",0)),2.),"Batch review computes explicit ripple before mutation")
	var operation:Dictionary=preview.operations[0]
	check(operation.parts[0].clip.start_time+operation.parts[0].clip.duration>operation.parts[1].clip.start_time,"Cleanup creates genuine overlap, not adjacent fades")
	var applied:=Batch.apply(session,prepared.plans,[[0],[0]],"track_following",.02)
	check(str(applied.get("error","")).is_empty() and session.document.clips.size()==4,"Two dialogue clips apply atomically")
	check(is_equal_approx(session.document.clip_for_id(b.id).start_time,4.),"Ripple moves later selected clips exactly once")
	session.undo();check(session.document.clips.size()==2 and is_equal_approx(session.document.clip_for_id(b.id).start_time,5.),"One undo restores complete queue")
	check(not str(Batch.apply(session,prepared.plans,[[0],[0]],"clip",.01).get("error","")).is_empty(),"Cancelled/stale queue cannot apply again")
	var selected:=Bundle.selected(session.document,[a.id,b.id]);check(str(selected.get("error","")).is_empty(),"Selected clips form native layer bundle")
	var target:=KiwiAudioEditSession.new();target.document=KiwiAudioDocument.new();target.document.add_track("Existing")
	var error:=Bundle.insert(target,selected.document,2.)
	check(error.is_empty() and target.document.clips.size()==2 and target.document.clips[0].id!=a.id,"Bundle inserts independent IDs and shared sources")
	check(is_equal_approx(target.document.clips[1].start_time,7.) and target.document.validate().is_empty(),"Bundle preserves relative placement and valid routes")
	target.undo();check(target.document.clips.is_empty(),"Bundle insertion is one undo")
	var pattern:=KiwiAudioComposer.drum_pattern("electronic",.6,.4,false,7)
	pattern.start=0.;pattern.section_id="verse";pattern.id="bar0"
	var second:Dictionary=pattern.duplicate(true);second.start=4.;second.id="bar1"
	var linked:=Linked.from_part({"patterns":[pattern,second],"pattern_beats":8.},[4,4])
	check(linked.definitions.size()==1 and linked.instances.size()==2,"Identical generated bars share one retained definition")
	var actor:=ActorData.new();actor.values[&"drum_patterns"]=linked.definitions;actor.values[&"drum_instances"]=linked.instances
	actor.values[&"notes"]=Linked.notes(actor);actor.values[&"pattern_beats"]=8.
	var pattern_data:=KiwiAudioPreset.pattern_data(actor)
	check(KiwiAudioPreset.validate_pattern(pattern_data).is_empty() and pattern_data.has("drum_instances"),"Pattern presets preserve canonical linked drum definitions and instances")
	var invalid:Dictionary=linked.instances[0].duplicate(true);invalid.id="bad";invalid.length=INF
	check(not Linked.validate(linked.definitions,[invalid]).is_empty(),"Non-finite linked pattern timing is rejected before expansion")
	var before:=Linked.notes(actor);linked.definitions.values()[0].lanes[0].values.fill(0.);var after:=Linked.notes(actor)
	check(after.size()<before.size() and not after.any(func(note:Dictionary):return int(note.pitch)==36),"Editing one linked pattern updates every instance")
	Linked.detach(actor);check(not actor.values.has(&"drum_instances") and actor.values.notes==after,"Detach preserves editable derived notes")
	var group:=session.document.add_track("Bus","group");session.document.tracks[0].output=str(group.id)
	var freeze:=preload("res://Workspaces/AudioWorkspace/audio_group_freeze.gd")
	check(str(freeze.members(session.document,str(group.id)).get("error","")).is_empty(),"Closed routed group can be frozen")
	check(freeze.apply(session,str(group.id),stream).is_empty() and session.document.tracks[0].locked and group.has("freeze_members"),"Group freeze preserves and locks every source route")
	session.undo();check(not session.document.tracks[0].locked and session.document.tracks.size()==2,"One undo restores every frozen group member")
	var row:={"target":{"owner_kind":"track","owner_id":str(session.document.tracks[0].id),"parameter":"pan","effect_id":""},"shape":"triangle","rate":2.,"center":0.,"depth":.7,"sync":false}
	var matrix:=preload("res://Workspaces/AudioWorkspace/audio_modulation_matrix.gd")
	check(matrix.apply(session,[row]).is_empty() and not session.document.tracks[0].automation.pan.is_empty(),"Generalized matrix generates existing route automation")
	session.undo();check(session.document.tracks[0].automation.is_empty(),"Modulation matrix undo restores original curves")
	var instrument:=KiwiAudioInstruments.default_instrument("poly");instrument.modulators=[{"kind":"step","target":"pan","rate":1.,"amount":1.,"values":[1.]}]
	var pan_stream:=KiwiAudioInstruments.render_notes([{"pitch":60,"start":0.,"duration":.1,"velocity":.5}],instrument,120,8000)
	var pan_samples:PackedVector2Array=KiwiAudioSourceCache.decode(pan_stream,8000).samples;var left:=0.;var right:=0.
	for value in pan_samples:left+=value.x*value.x;right+=value.y*value.y
	check(right>0 and left<right*.001,"Instrument pan modulation changes rendered stereo channel energy")
	var timing_session:=KiwiAudioEditSession.new();timing_session.document=KiwiAudioDocument.from_source(stream)
	var timed_actor:=timing_session.document.actors[0];var timed_clip:=timing_session.document.clips[0]
	timed_actor.values[&"pattern_beats"]=8.;timed_actor.values[&"source_bpm"]=120.;timed_actor.values[&"source_duration"]=4.;timed_actor.values[&"notes"]=[KiwiAudioComposer.new_note(60,0,1,.7)]
	timing_session.document.tempo_points=[{"beat":4.,"bpm":60.}]
	var fit:=preload("res://Workspaces/AudioWorkspace/audio_conductor_fit.gd")
	check(fit.apply(timing_session,[timed_clip.id]).is_empty() and is_equal_approx(timed_clip.duration,6.),"Explicit conductor policy follows variable step tempos and preserves beats")
	check(is_zero_approx(timed_clip.start_time) and timed_actor.values.notes.size()==1,"Conductor fit preserves absolute clip start and editable note identity")
	timing_session.undo();check(is_equal_approx(timing_session.document.clips[0].duration,4.),"Conductor fit is one undo action")
	var restoration:=preload("res://Workspaces/AudioWorkspace/audio_restoration.gd")
	var directory:=ProjectSettings.globalize_path("user://audio_workspace/jobs/"+ActorData.new_id());DirAccess.make_dir_recursive_absolute(directory)
	var raw:=PackedByteArray();raw.resize(8000*8)
	for i in 8000:
		var value:=.3*sin(TAU*900.*i/8000.)*exp(-float(i)/800.)
		raw.encode_float(i*8,value);raw.encode_float(i*8+4,value)
	var file:=FileAccess.open(directory.path_join("input.f32"),FileAccess.WRITE);file.store_buffer(raw);file.close()
	var effect:=KiwiAudioEffects.create("dereverb");effect.parameters.decay=2.;effect.parameters.strength=1.
	var processed:=restoration.process_f32(directory.path_join("input.f32"),directory.path_join("output.f32"),effect,8000)
	check(bool(processed.get("success",false)),"Offline multiband decay suppression completes")
	var output:=FileAccess.get_file_as_bytes(directory.path_join("output.f32"));var wet_energy:=0.;var dry_energy:=0.
	if output.size()==raw.size():
		for i in range(2400,6000):wet_energy+=pow(output.decode_float(i*8),2);dry_energy+=pow(raw.decode_float(i*8),2)
	check(output.size()==raw.size() and wet_energy<dry_energy*.8,"Decay suppression preserves timing and reduces a falling tail")
	if not ActorVideo.executable("ffmpeg").is_empty():
		var rendered:=KiwiAudioRenderer.render(KiwiAudioDocument.from_source(stream),directory.path_join("source.wav"),{"sample_rate":8000,"bit_depth":16,"include_tail":false})
		check(bool(rendered.get("success",false)),"Restoration fixture renders")
		var document:=KiwiAudioDocument.from_source(stream);document.actors[0].values[&"effects"]=[effect]
		var restored:=KiwiAudioRenderer.render(document,directory.path_join("restored.wav"),{"sample_rate":8000,"bit_depth":16,"include_tail":false})
		check(bool(restored.get("success",false)),"Decay suppression participates in the ordered render/export stack: "+str(restored.get("error","")))
	KiwiAudioRenderer._remove_owned(directory)
	for label in KiwiAudioTemplates.names():
		var document:=KiwiAudioTemplates.create(label)
		check(document.validate().is_empty() and document.tracks.any(func(item:Dictionary):return str(item.kind)=="group"),"Template has valid real routing: "+label)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Store.ROOT))
	var path:=Store.ROOT.path_join(ActorData.new_id()+".tres");var preset:=KiwiAudioPreset.new();preset.id=ActorData.new_id();preset.label="Restore test";ResourceSaver.save(preset,path)
	var digest:=FileAccess.get_sha256(path)
	check(Store.rename(path,digest,"Renamed").is_empty(),"Preset rename retains original backup")
	digest=FileAccess.get_sha256(path);check(Store.remove(path,digest).is_empty() and not FileAccess.file_exists(path),"Preset removal moves exact file into recovery")
	var recovery:=Store.recoverable();check(not recovery.is_empty(),"Recovery exposes removed and earlier preset versions")
	check(Store.restore(recovery.back()).is_empty(),"Restore creates a new independent library preset")
	print("AUDIO_HANDOFF_WORKFLOWS checks=%d failures=%d"%[checks,failures]);quit(failures)
