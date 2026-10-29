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
	return editor.model.selected_actor()
func state(actor: ActorData) -> Dictionary: return editor.physics.display_states[actor.id]
func key(actor: ActorData,path: PackedStringArray,time: float,value: Variant) -> void:
	var track:=actor.animation_track(path)
	if track==null: track=ActorAnimationTrack.new(); track.path=path; actor.animation_tracks.append(track)
	var frame:=ActorKeyframe.new(); frame.time=time; frame.value=value; track.keys.append(frame); track.sort_keys()
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var floor_actor:=add(&"basic_shape",{&"box_size":Vector3(8,.2,8),&"position":Vector3(0,-.1,0)})
	floor_actor.values.physics={"enabled":true,"body_mode":2,"friction":.8,"bounce":0.0}
	var dust:=add(&"powder",{&"position":Vector3(0,.2,0),&"powder_deposition":true,&"powder_dimensions":Vector3(.44,.1,.44),&"powder_spacing":.11,&"powder_radius":.04,&"powder_density":400.,&"powder_restitution":0.,&"powder_sleep_delay":.15,&"powder_settling":.15})
	editor.model.changed.emit(); await seek(1.0)
	var initial:=KiwiPowderTransport.inventory(state(dust)); var positions: PackedVector3Array=state(dust).points.duplicate()
	print("INITIAL DEPOSITS ",initial," cells=",state(dust).powder_cells.size())
	check(initial.deposited>0 and not state(dust).powder_cells.is_empty(),"Falling grains become persistent surface-local deposits with thickness and coverage")
	var count: int=state(dust).powder_ids.size(); var mass: float=initial.total
	key(floor_actor,PackedStringArray(["position"]),0.,Vector3(0,-.1,0)); key(floor_actor,PackedStringArray(["position"]),1.,Vector3(0,-.1,0)); key(floor_actor,PackedStringArray(["position"]),2.,Vector3(1,-.1,0))
	editor.model.changed.emit(); await seek(2.)
	check(state(dust).points[0].x>positions[0].x+.9,"Deposited powder follows a moving supporting object in local coordinates")
	check(state(dust).powder_ids.size()==count and absf(KiwiPowderTransport.inventory(state(dust)).total-mass)<.000001,"Attaching and moving deposits preserves grain identity and mass")
	key(dust,PackedStringArray(["physics","wind"]),0.,Vector3.ZERO); key(dust,PackedStringArray(["physics","wind"]),2.,Vector3.ZERO); key(dust,PackedStringArray(["physics","wind"]),2.1,Vector3(30,8,0))
	editor.model.changed.emit(); await seek(2.7)
	var windy: Dictionary=editor.physics._snapshot({dust.id:state(dust)})[dust.id]
	check(int(state(dust).powder_releases)>0 and KiwiPowderTransport.inventory(state(dust)).deposited<initial.deposited,"Wind force erodes settled fine material and returns it to moving grains")
	check(KiwiPowderTransport.inventory(state(dust)).airborne>0,"Detached dust becomes airborne under wind without spawning duplicate particles")
	check(absf(KiwiPowderTransport.inventory(state(dust)).total-mass)<.000001,"Mass is conserved across active/deposited/airborne transfers")
	await seek(.3); await seek(2.7)
	check(state(dust).points==windy.points and state(dust).powder_phase==windy.powder_phase and state(dust).powder_deposits==windy.powder_deposits,"Rewind and replay reproduce deposition, erosion and airborne state exactly")
	var steps:=editor.physics.steps_taken; await seek(2.7)
	check(editor.physics.steps_taken==steps,"Paused deposits and dust perform no hidden updates")
	var baked: String=await editor.physics.bake(editor,dust,0,2.8)
	check(baked.is_empty(),"Transport states bake through the existing physics timeline")
	await seek(2.7); check(state(dust).powder_phase==windy.powder_phase,"Baked transport retains phase identity")
	var scene:=editor.capture_scene_data(); var path:="user://transport_"+ActorData.new_id()+".tres"; ResourceSaver.save(scene,path)
	var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	check(reopened.actors[-1].values.powder_deposition and not reopened.actors[-1].values.physics.bake.frames[-1].powder_phase.is_empty(),"Authored transport controls and baked phase/attachment data survive scene serialization")
	DirAccess.remove_absolute(path); editor.physics.dispose(); editor.queue_free(); view.queue_free(); await process_frame
	print("POWDER TRANSPORT: %d checks, %d failures"%[checks,failures]); quit(failures)
