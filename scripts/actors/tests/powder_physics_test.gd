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
	var clip:=editor.model.create_actor(editor.registry.get_definition(type),0,values); clip.start_time=0; clip.duration=5; clip.layer=editor.model.clips.size()-1
	var actor:=editor.model.selected_actor(); editor.model.changed.emit(); return actor
func state(actor: ActorData) -> Dictionary: return editor.physics.display_states[actor.id]
func key(actor: ActorData,path: PackedStringArray,time: float,value: Variant) -> void:
	var track:=actor.animation_track(path)
	if track==null: track=ActorAnimationTrack.new(); track.path=path; actor.animation_tracks.append(track)
	var frame:=ActorKeyframe.new(); frame.time=time; frame.value=value; track.keys.append(frame); track.sort_keys()
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor)
	var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); root.add_child(viewport); editor.runtime_holder=Node3D.new(); viewport.add_child(editor.runtime_holder)
	var floor_actor:=add(&"basic_shape",{&"position":Vector3(0,-.1,0),&"box_size":Vector3(30,.2,15)})
	floor_actor.values.physics={"enabled":true,"body_mode":1,"friction":.8,"bounce":.1}
	for wall_data: Array in [[Vector3(-.32,.7,0),Vector3(.1,1.4,.7)],[Vector3(.32,.7,0),Vector3(.1,1.4,.7)],[Vector3(0,.7,-.32),Vector3(.7,1.4,.1)],[Vector3(0,.7,.32),Vector3(.7,1.4,.1)]]:
		var wall:=add(&"basic_shape",{&"position":wall_data[0],&"box_size":wall_data[1]}); wall.values.physics={"enabled":true,"body_mode":1,"friction":.8}
	var sand:=add(&"powder",{&"position":Vector3(0,1,0),&"powder_dimensions":Vector3(.44,.44,.44),&"powder_spacing":.11,&"powder_radius":.045})
	editor.model.changed.emit(); await seek(1.2)
	var minimum:=INF; var highest:=-INF
	for p: Vector3 in state(sand).points: minimum=minf(minimum,p.y); highest=maxf(highest,p.y)
	check(state(sand).points.size()==64 and minimum>.04 and highest<.8,"Real native query colliders catch falling grains and build a pile")
	var snapshot:=editor.physics._snapshot({sand.id:state(sand)}); var steps:=editor.physics.steps_taken
	await seek(1.2); check(editor.physics.steps_taken==steps,"Paused granular simulation performs no hidden steps")
	await seek(.3); await seek(1.2)
	check(state(sand).points==snapshot[sand.id].points and state(sand).velocities==snapshot[sand.id].velocities and state(sand).powder_sleep==snapshot[sand.id].powder_sleep,"Backward/forward seeking reproduces complete granular state exactly")
	var generation:=editor.physics.generation
	editor.model.edit_property(sand,editor.registry.get_definition(&"powder"),&"powder_color",Color.RED); await seek(1.2)
	check(editor.physics.generation==generation,"Color-only changes preserve physics caches")
	editor.model.edit_property(sand,editor.registry.get_definition(&"powder"),&"powder_friction",.15); await seek(1.2)
	check(editor.physics.generation>generation,"Physical material changes invalidate later simulation")
	editor.model.undo(); await seek(1.2); check(state(sand).points==snapshot[sand.id].points,"Undo restores both material settings and deterministic simulation")
	key(sand,PackedStringArray(["powder_cohesion"]),0,0.0); key(sand,PackedStringArray(["powder_cohesion"]),1,2.0); editor.model.changed.emit(); await seek(.5)
	check(absf(KiwiPowderBridge.values(editor.physics,sand.id,.5).powder_cohesion-1.0)<.001,"Physical properties sample ordinary animation tracks at source time")
	sand.animation_tracks.clear(); editor.model.changed.emit()
	var emitter:=add(&"powder",{&"position":Vector3(2,.8,0),&"powder_source_mode":1,&"powder_emit_rate":36.0,&"powder_emit_radius":.12,&"powder_emit_end":1.0,&"powder_radius":.045})
	await seek(1.8); var pile: PackedVector3Array=state(emitter).points.duplicate(); var height:=-INF
	for p in pile: height=maxf(height,p.y)
	check(pile.size()==36 and height>.13,"Emitter grains accumulate on earlier grains instead of passing through")
	await seek(2.3); var drift:=0.0
	for i in pile.size(): drift=maxf(drift,pile[i].distance_to(state(emitter).points[i]))
	print("NATIVE PILE height=",height," half_second_drift=",drift)
	check(drift<.15,"A stopped emitted pile remains approximately settled")
	var mover:=add(&"basic_shape",{&"box_size":Vector3(.22,.8,.8)}); mover.values.physics={"enabled":true,"body_mode":2,"friction":.8}
	key(mover,PackedStringArray(["position"]),0,Vector3(1.2,.4,0)); key(mover,PackedStringArray(["position"]),1.5,Vector3(1.2,.4,0)); key(mover,PackedStringArray(["position"]),2.3,Vector3(2.6,.4,0)); editor.model.changed.emit(); await seek(2.3)
	var displaced:=0.0
	for i in pile.size(): displaced=maxf(displaced,pile[i].distance_to(state(emitter).points[i]))
	check(displaced>.15,"Timeline-animated solid colliders physically displace grains")
	var block:=add(&"basic_shape",{&"position":Vector3(0,1.8,0),&"box_size":Vector3(.5,.3,.5)})
	block.values.physics={"enabled":true,"mass":2.0,"inherit_velocity":false,"friction":.8,"damping":.1}; editor.model.changed.emit()
	for at in [.6,.8,1.0,1.5]:
		await seek(at); print("RIGID sample=",at," y=",state(block).pose.origin.y," v=",state(block).v)
	print("RIGID on grains y=",state(block).pose.origin.y," v=",state(block).v)
	check(state(block).pose.origin.y>.21 and state(block).pose.origin.y<1.1 and state(block).v.length()<2,"Dynamic rigid body receives stable aggregate grain reaction and is supported above the floor")
	var light_height: float=state(block).pose.origin.y; block.values.physics.mass=20.0; editor.model.changed.emit(); await seek(1.5)
	print("HEAVY BLOCK y=",state(block).pose.origin.y," v=",state(block).v)
	check(state(block).pose.origin.y>.21 and state(block).pose.origin.y<=light_height+.03 and state(block).v.length()<2,"A ten-times-heavier block compacts the confined bed instead of falling through it")
	var unchanged_radii:=true; var compaction:=0.0
	for i in state(sand).points.size(): unchanged_radii=unchanged_radii and absf(float(state(sand).powder_radii[i])-.045)<.00001; compaction=maxf(compaction,float(state(sand).powder_compaction[i]))
	check(unchanged_radii and compaction>.1,"Compressed grains retain their physical radii and record packing history")
	var before_bake: PackedVector3Array
	await seek(.2); before_bake=state(sand).points.duplicate()
	var error: String=await editor.physics.bake(editor,sand,0,.3); check(error.is_empty(),"Shared physics baking stores complete powder states")
	await seek(.2); check(state(sand).points==before_bake,"Baked playback matches the live granular timeline")
	editor.physics.freeze(editor.model,emitter); await seek(2.5); var frozen: PackedVector3Array=state(emitter).points.duplicate(); await seek(3)
	check(state(emitter).points==frozen,"Freeze holds every grain, not just its actor transform")
	editor.model.undo(); await seek(.2)
	var scene:=editor.capture_scene_data(); var path:="user://Powder physics roundtrip.tres"
	check(ResourceSaver.save(scene,path)==OK,"Granular settings and bake data save as a normal Kiwi scene")
	var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	check(loaded!=null and loaded.actors.any(func(a: ActorData): return a.id==sand.id and not KiwiPhysicsSettings.authored(a).bake.is_empty()),"Native scene reload preserves material controls and baked packed state")
	DirAccess.remove_absolute(path)
	check(editor.physics.world.bodies.size()<16,"Grains share reusable native query probes rather than owning individual server bodies")
	editor.queue_free(); viewport.queue_free(); await process_frame
	print("POWDER PHYSICS: %d checks, %d failures"%[checks,failures]); quit(failures)
