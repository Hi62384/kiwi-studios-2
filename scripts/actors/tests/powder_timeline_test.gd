extends SceneTree
var checks:=0
var failures:=0
var editor: ActorTimelineEditor
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func seek(time: float) -> void:
	editor.canvas.playhead=time; editor._evaluate_runtimes()
	while editor.physics.pending: await process_frame; editor._evaluate_runtimes()
func add(type: StringName,values: Dictionary={}) -> ActorData:
	var clip:=editor.model.create_actor(editor.registry.get_definition(type),0,values); clip.start_time=0; clip.duration=6; clip.layer=editor.model.clips.size()-1
	var actor:=editor.model.selected_actor()
	if type==&"powder": actor.values[&"powder_simulate"]=false
	editor.model.changed.emit(); return actor
func key(actor: ActorData,path: String,time: float,value: Variant) -> void:
	var track:=actor.animation_track(PackedStringArray([path]))
	if track==null: track=ActorAnimationTrack.new(); track.path=PackedStringArray([path]); actor.animation_tracks.append(track)
	var frame:=ActorKeyframe.new(); frame.time=time; frame.value=value; track.keys.append(frame); track.sort_keys()
func state(actor: ActorData) -> Dictionary: return editor.physics.display_states[actor.id]
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor)
	var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); root.add_child(viewport); editor.runtime_holder=Node3D.new(); viewport.add_child(editor.runtime_holder)
	check(editor.registry.get_definition(&"powder")!=null,"Normal Scene actor registry creates Powder")
	var volume:=add(&"powder"); await seek(0)
	var runtime:=editor._runtime_for_clip(editor.model.clip_for_actor_id(volume.id).id) as KiwiPowderRuntime
	check(state(volume).points.size()==216 and runtime.instance_count()==216,"Actual packed grain state drives batched geometry variants")
	check(state(volume).powder_ids.size()==216 and state(volume).powder_masses[0]>0 and state(volume).powder_radii[0]>0,"IDs, mass, radius, velocity and birth data exist for every grain")
	var generation:=editor.physics.powder.generation_count; var updates:=runtime.preview_updates; await seek(.8); await seek(0); await seek(.8)
	check(editor.physics.powder.generation_count==generation,"Finite source is cached across rewind and replay")
	check(runtime.preview_updates==updates,"Unchanged stationary source does not rebuild the preview")
	editor.model.edit_property(volume,editor.registry.get_definition(&"powder"),&"powder_dimensions",Vector3(.5,.5,.5)); await seek(0)
	check(state(volume).points.size()<216,"Editing source dimensions regenerates the grain set")
	editor.model.undo(); await seek(0); check(state(volume).points.size()==216,"Undo restores source dimensions and generation")
	editor.model.redo(); await seek(0); check(state(volume).points.size()<216,"Redo reapplies source dimensions")
	var parent:=add(&"point_3d"); key(parent,"position",0,Vector3.ZERO); key(parent,"position",3,Vector3(6,0,0))
	var emitter:=add(&"powder",{&"powder_source_mode":1,&"powder_emit_rate":12.0,&"powder_emit_shape":0}); emitter.parent_id=parent.id; editor._recreate_runtimes(); editor.model.changed.emit()
	await seek(0); check(state(emitter).points.is_empty(),"Emitter starts empty at source zero")
	await seek(1); var snapshot: Dictionary=editor.physics._snapshot({emitter.id:state(emitter)})[emitter.id]
	check(snapshot.points.size()==12 and snapshot.powder_ids==PackedInt32Array(range(12)),"Known emission rate produces exact counts and stable IDs")
	check(absf(snapshot.points[0].x-1.0/6)<.001 and absf(snapshot.points[-1].x-2)<.001,"Moving parent is sampled at each grain's actual birth time")
	await seek(2); check(state(emitter).points.size()==24 and state(emitter).points[0]==snapshot.points[0],"Previously emitted grains do not follow the moving parent")
	var steps:=editor.physics.steps_taken; await seek(2); check(steps==editor.physics.steps_taken,"Paused evaluation emits no additional grains")
	await seek(.1); await seek(1); check(state(emitter).points==snapshot.points and state(emitter).velocities==snapshot.velocities and state(emitter).powder_ids==snapshot.powder_ids,"Rewind restores positions, velocities and stable identities")
	await seek(.087); check(state(emitter).points.size()==1,"Fractional display times do not hide grains after their birth")
	key(emitter,"powder_emit_rate",0,0.0); key(emitter,"powder_emit_rate",2,24.0); editor.model.changed.emit(); await seek(2)
	check(state(emitter).points.size()==24,"Animated rate integrates through existing actor keyframes")
	emitter.animation_tracks.clear(); emitter.values.powder_continuous=false; emitter.values.powder_supply=5; editor.model.changed.emit(); await seek(2)
	check(state(emitter).points.size()==5,"Finite emitter supply caps generated grains")
	var source:=add(&"basic_shape",{&"position":Vector3(4,2,0),&"rotation":Vector3(0,30,0),&"scale":Vector3(2,1,1)})
	var mesh_powder:=add(&"powder",{&"powder_shape":3,&"powder_mesh_actor":source.id}); await seek(0)
	var mesh_state:=state(mesh_powder); check(mesh_state.points.size()>10 and mesh_state.powder_error.is_empty(),"Existing scene mesh fills through the ordinary actor-reference field")
	var before: PackedVector3Array=mesh_state.points.duplicate(); source.values.position.x+=1; editor.model.changed.emit(); await seek(0)
	check(absf(state(mesh_powder).points[0].x-before[0].x-1)<.001,"Source mesh transform edits invalidate and regenerate world-space filling")
	var scene:=editor.capture_scene_data()
	var path:="user://Powder source roundtrip.tres"; check(ResourceSaver.save(scene,path)==OK,"Normal scene saving preserves powder configuration")
	var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	var saved_actor: ActorData=loaded.actors.filter(func(a: ActorData): return a.id==mesh_powder.id)[0]
	check(saved_actor.values.powder_mesh_actor==source.id and saved_actor.animation_tracks.size()==mesh_powder.animation_tracks.size(),"Scene reload preserves references and tracks without storing generated arrays")
	check(not FileAccess.get_file_as_string(path).contains("powder_birth_positions"),"Ordinary saves reconstruct runtime grains rather than duplicating massive arrays")
	var saved_points: PackedVector3Array=state(mesh_powder).points.duplicate(); var saved_ids: PackedInt32Array=state(mesh_powder).powder_ids.duplicate()
	editor.restore_scene_data(loaded); await seek(0)
	check(editor.physics.display_states[mesh_powder.id].points==saved_points and editor.physics.display_states[mesh_powder.id].powder_ids==saved_ids,"Reopening an unbaked scene deterministically regenerates matching grains and identities")
	source=editor.model.actor_for_id(source.id); mesh_powder=editor.model.actor_for_id(mesh_powder.id)
	var trimmed:=add(&"powder",{&"powder_source_mode":1,&"powder_emit_rate":10.0}); var trimmed_clip:=editor.model.clip_for_actor_id(trimmed.id)
	trimmed_clip.start_time=1; trimmed_clip.source_offset=.5; trimmed_clip.playback_speed=2; editor.model.changed.emit(); await seek(1)
	check(state(trimmed).points.size()==5,"Trimmed source offsets replay emission history at the clip's playback speed")
	trimmed.values.physics.activation=.25; editor.model.changed.emit(); await seek(1)
	check(state(trimmed).points.size()==2,"Emission respects source-time physics activation")
	var snapshots: Array[Dictionary]=[]
	for actor in [source,mesh_powder]:
		var clip:=editor.model.clip_for_actor_id(actor.id)
		snapshots.append({"actor":actor,"source_id":actor.id,"source_parent":actor.parent_id,"start":clip.start_time,"duration":clip.duration,"offset":clip.source_offset,"speed":clip.playback_speed,"layer":clip.layer})
	var copies:=editor.model.paste_snapshots(snapshots,0,20); var copied_mesh: ActorData; var copied_powder: ActorData
	for clip in copies:
		var actor:=editor.model.actor_for_id(clip.actor_id)
		if actor.type_id==&"powder": copied_powder=actor
		else: copied_mesh=actor
	check(copied_mesh!=null and copied_powder!=null and copied_powder.values.powder_mesh_actor==copied_mesh.id,"Duplicating a mesh and powder remaps the source to the copied mesh")
	editor.model.undo()
	var instance:=ActorSceneData.new(); instance.actors.assign([source,mesh_powder]); instance.clips.assign([editor.model.clip_for_actor_id(source.id),editor.model.clip_for_actor_id(mesh_powder.id)]); instance.sections.assign(editor.model.sections)
	var root_clip:=editor.model.instantiate_scene(instance,editor.registry.get_definition(&"point_3d"),0,20)
	var remapped:=false
	for actor in editor.model.actors:
		if actor.id!=mesh_powder.id and actor.type_id==&"powder" and actor.parent_id==root_clip.actor_id: remapped=actor.values.powder_mesh_actor!=source.id and editor.model.actor_for_id(str(actor.values.powder_mesh_actor))!=null
	check(remapped,"Instantiating a scene preserves its internal powder source reference")
	var toggled:=add(&"powder",{&"powder_source_mode":1,&"powder_emit_rate":30.0})
	key(toggled,"powder_enabled",0,true); key(toggled,"powder_enabled",.2,false); key(toggled,"powder_enabled",.4,true); editor.model.changed.emit()
	await seek(.399); await seek(.5)
	check(state(toggled).points.size()==3 and state(toggled).powder_birth_times[0]>=.4,"Keyframed disabling/re-enabling resets births safely across fractional seeks")
	var delayed:=add(&"powder"); delayed.values.physics.activation=1.0; editor.model.changed.emit(); await seek(.999)
	var delayed_runtime:=editor._runtime_for_clip(editor.model.clip_for_actor_id(delayed.id).id) as KiwiPowderRuntime
	check(delayed_runtime.instance_count()==0,"Fractional interpolation never exposes a finite source before activation")
	await seek(1); check(state(delayed).points.size()==216,"Finite volume appears at its configured activation time")
	var group:=add(&"point_3d"); var nested_mesh:=add(&"basic_shape",{&"box_size":Vector3(.4,.4,.4)}); nested_mesh.parent_id=group.id; editor._recreate_runtimes(); editor.model.changed.emit()
	var grouped:=add(&"powder",{&"powder_shape":3,&"powder_mesh_actor":group.id}); await seek(0); var original_count: int=state(grouped).points.size()
	nested_mesh.values.box_size=Vector3(.8,.4,.4); editor.model.changed.emit(); await seek(0)
	check(state(grouped).points.size()>original_count and state(grouped).powder_error.is_empty(),"Nested model mesh edits invalidate a group-referenced finite source")
	DirAccess.remove_absolute(path); editor.queue_free(); viewport.queue_free(); await process_frame
	print("POWDER TIMELINE: %d checks, %d failures"%[checks,failures]); quit(failures)
