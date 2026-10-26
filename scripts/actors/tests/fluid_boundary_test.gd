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
func add(type: StringName,values: Dictionary) -> ActorData:
	var clip:=editor.model.create_actor(editor.registry.get_definition(type),0,values); clip.start_time=0; clip.duration=3; clip.layer=editor.model.clips.size()-1
	return editor.model.selected_actor()
func key(actor: ActorData,path: PackedStringArray,time: float,value: Variant) -> void:
	var track:=actor.animation_track(path)
	if track==null: track=ActorAnimationTrack.new(); track.path=path; actor.animation_tracks.append(track)
	var frame:=ActorKeyframe.new(); frame.time=time; frame.value=value; track.keys.append(frame); track.sort_keys()
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var viewport:=SubViewport.new(); viewport.size=Vector2i(320,240); root.add_child(viewport); editor.runtime_holder=Node3D.new(); viewport.add_child(editor.runtime_holder)
	for shape: Array in [[Vector3(0,-.15,0),Vector3(2.4,.3,2.4)],[Vector3(-1.1,.6,0),Vector3(.2,1.5,2.4)],[Vector3(1.1,.6,0),Vector3(.2,1.5,2.4)],[Vector3(0,.6,-1.1),Vector3(2.4,1.5,.2)],[Vector3(0,.6,1.1),Vector3(2.4,1.5,.2)]]:
		var wall:=add(&"basic_shape",{&"position":shape[0],&"box_size":shape[1]}); wall.values[&"physics"]={"enabled":true,"body_mode":1}
	var liquid:=add(&"fluid",{&"position":Vector3(0,.8,0),&"fluid_dimensions":Vector3(.88,1.144,.88),&"fluid_quality":0})
	editor.model.changed.emit(); await seek(1)
	var contained:=true
	for p: Vector3 in editor.physics.display_states[liquid.id].points:
		if absf(p.x)>1.01 or absf(p.z)>1.01 or p.y<.04: contained=false
	check(contained,"Liquid fills and remains inside a five-wall 3D container")
	var mover:=add(&"basic_shape",{&"position":Vector3(-.8,.3,0),&"box_size":Vector3(.3,.7,1.7)})
	mover.values[&"physics"]={"enabled":true,"body_mode":2}
	key(mover,PackedStringArray(["position"]),0,Vector3(-.8,.3,0)); key(mover,PackedStringArray(["position"]),1,Vector3(.7,.3,0)); editor.model.changed.emit(); await seek(.8)
	var hit:=false
	for contact: Dictionary in editor.physics.display_states[liquid.id].fluid_contacts:
		if str(contact.actor)==mover.id: hit=true
	var cube_pose: Transform3D=editor.physics.display_states[mover.id].pose
	var penetrating:=0
	for p: Vector3 in editor.physics.display_states[liquid.id].points:
		if absf(p.x-cube_pose.origin.x)<.15 and absf(p.z)<.85 and p.y<.65: penetrating+=1
	check(penetrating==0,"An animated cube displaces liquid instead of leaving particles inside it")
	var parent:=add(&"point_3d",{&"position":Vector3(5,2,0)}); key(parent,PackedStringArray(["position"]),0,Vector3(5,2,0)); key(parent,PackedStringArray(["position"]),1,Vector3(7,2,0))
	var emitter:=add(&"fluid",{&"fluid_source_mode":1,&"fluid_emit_rate":10.0,&"fluid_emit_speed":0.0,&"fluid_emit_radius":.01,&"fluid_quality":0}); emitter.parent_id=parent.id; emitter.values.physics={"enabled":true,"type":6,"gravity":0.0,"inherit_velocity":false,"collision":false}
	editor._recreate_runtimes(); editor.model.changed.emit(); await seek(.3)
	var old_x: float=editor.physics.display_states[emitter.id].points[0].x; await seek(.8)
	check(absf(editor.physics.display_states[emitter.id].points[0].x-old_x)<.03,"Previously released liquid stays in world space when the emitter's parent moves")
	var latest: Vector3=editor.physics.display_states[emitter.id].points[-1]
	check(latest.x>6.4,"New particles follow the animated source's current world position")
	var original: PackedVector3Array=editor.physics.display_states[emitter.id].points.duplicate(); editor.physics.signature=""; editor.physics.mark_dirty(); await seek(.8)
	check(editor.physics.display_states[emitter.id].points==original,"A fresh GPU replay reproduces emission and density projection")
	editor.physics.dispose(); editor.queue_free(); viewport.queue_free(); await process_frame
	print("FLUID BOUNDARIES: %d checks, %d failures"%[checks,failures]); quit(failures)
