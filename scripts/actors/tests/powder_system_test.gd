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
	var clip:=editor.model.create_actor(editor.registry.get_definition(type),0,values); clip.start_time=0; clip.duration=3; clip.layer=editor.model.clips.size()-1
	var actor:=editor.model.selected_actor(); editor.model.changed.emit(); return actor
func key(actor: ActorData,path: PackedStringArray,time: float,value: Variant) -> void:
	var track:=actor.animation_track(path)
	if track==null: track=ActorAnimationTrack.new(); track.path=path; actor.animation_tracks.append(track)
	var frame:=ActorKeyframe.new(); frame.time=time; frame.value=value; track.keys.append(frame); track.sort_keys()
func state(actor: ActorData) -> Dictionary: return editor.physics.display_states[actor.id]
func average_y(actor: ActorData) -> float:
	var total:=0.0
	for p: Vector3 in state(actor).points: total+=p.y
	return total/maxi(1,state(actor).points.size())
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor)
	var viewport:=SubViewport.new(); viewport.size=Vector2i(320,240); root.add_child(viewport); editor.runtime_holder=Node3D.new(); viewport.add_child(editor.runtime_holder)
	var powders: Array[ActorData]=[]; var liquids: Array[ActorData]=[]
	for index in 2:
		var center:=Vector3(index*2.5,0,0)
		for shape: Array in [[Vector3(0,-.1,0),Vector3(1.5,.2,1.5)],[Vector3(-.7,.7,0),Vector3(.1,1.4,1.5)],[Vector3(.7,.7,0),Vector3(.1,1.4,1.5)],[Vector3(0,.7,-.7),Vector3(1.5,1.4,.1)],[Vector3(0,.7,.7),Vector3(1.5,1.4,.1)]]:
			var wall:=add(&"basic_shape",{&"position":center+shape[0],&"box_size":shape[1]}); wall.values.physics={"enabled":true,"body_mode":1}
		liquids.append(add(&"fluid",{&"position":center+Vector3(0,.5,0),&"fluid_dimensions":Vector3.ONE*.858,&"fluid_quality":0}))
		powders.append(add(&"powder",{&"position":center+Vector3(0,1.1,0),&"powder_source_mode":1,&"powder_emit_rate":6.0,&"powder_emit_radius":.02,&"powder_radius":.045,&"powder_continuous":false,&"powder_supply":3,&"powder_fluid":1.0 if index==0 else 0.0}))
	editor.model.changed.emit(); await seek(.7)
	check(state(powders[0]).points.size()==3 and state(powders[1]).points.size()==3,"Real timeline runs granular and existing fluid sources together")
	var wet:=average_y(powders[0]); var dry:=average_y(powders[1]); print("SAND/WATER coupled_y=",wet," uncoupled_y=",dry)
	check(wet>dry+.02,"Coupled grains settle more slowly through actual liquid than uncoupled grains")
	var liquid_difference:=0.0
	for i in mini(state(liquids[0]).points.size(),state(liquids[1]).points.size()): liquid_difference+=(state(liquids[0]).points[i]-(state(liquids[1]).points[i]-Vector3(2.5,0,0))).length()
	check(liquid_difference>.00001,"Actual fluid trajectory changes in response to the grains")
	var grain_snapshot: PackedVector3Array=state(powders[0]).points.duplicate(); var fluid_snapshot: PackedVector3Array=state(liquids[0]).points.duplicate()
	await seek(.2); await seek(.7)
	check(state(powders[0]).points==grain_snapshot and state(liquids[0]).points==fluid_snapshot,"Coupled liquid/granular replay is deterministic on the shared timeline")
	var parent:=add(&"point_3d",{&"position":Vector3(6,2,0)})
	key(parent,PackedStringArray(["position"]),0,Vector3(6,2,0)); key(parent,PackedStringArray(["position"]),1.5,Vector3(7.5,2,0))
	var emitter:=add(&"powder",{&"powder_source_mode":1,&"powder_emit_shape":0,&"powder_emit_rate":10.0,&"powder_characters":false,&"powder_deformables":false}); emitter.parent_id=parent.id; editor._recreate_runtimes(); editor.model.changed.emit()
	await seek(.4); var early: Vector3=state(emitter).points[0]; await seek(.7)
	check(absf(state(emitter).points[0].x-early.x)<.005 and state(emitter).points[0].y<early.y-.1 and state(emitter).points[-1].x>6.5,"Released grains follow their own simulated trajectories while new births follow the parent")
	var bone:={"name":"Nozzle","parent":-1,"rest":Transform3D(Basis.IDENTITY,Vector3(0,1,0)),"position":Vector3(0,1,0),"rotation":Vector3.ZERO,"scale":Vector3.ONE}
	var rig:=add(&"skeleton_rig",{&"position":Vector3(9,1,0),&"rig_bones":[bone]})
	rig.values[&"rig_bones"]=[bone]; editor._recreate_runtimes(); editor.model.changed.emit()
	var attached:=add(&"powder",{&"powder_simulate":false,&"powder_source_mode":1,&"powder_emit_shape":0,&"powder_emit_rate":10.0})
	attached.values.physics={"enabled":true,"type":7,"attachment":rig.id,"attachment_bone":"Nozzle","inherit_velocity":false}; editor.model.changed.emit(); await seek(.2)
	check(state(attached).points.size()==2 and state(attached).points[0].distance_to(Vector3(9,2,0))<.001,"Powder source follows the existing skeleton bone attachment system")
	editor.queue_free(); viewport.queue_free(); await process_frame
	print("POWDER SYSTEM: %d checks, %d failures"%[checks,failures]); quit(failures)
