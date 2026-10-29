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
	editor.physics.mark_dirty() # Tests also author raw fixture dictionaries between seeks.
	editor.canvas.playhead=time; editor._evaluate_runtimes()
	while editor.physics.pending: await process_frame; editor._evaluate_runtimes()
func add(point: Vector3,role: int=0,mass: float=1,box: Vector3=Vector3.ONE) -> ActorData:
	var clip:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0,{&"position":point,&"box_size":box,&"structure_enabled":true,&"structure_role":role})
	clip.start_time=0; clip.duration=8; clip.layer=editor.model.clips.size()-1
	var actor:=editor.model.selected_actor(); actor.values.physics={"mass":mass,"damping":.1,"angular_damping":.3,"bounce":0.0}; return actor
func joint(a: ActorData,b: ActorData,point: Vector3,strength: float=10000,kind: int=0) -> String:
	var id:=KiwiStructure.connect_actors(editor.model,a,b,point,Transform3D(Basis.IDENTITY,a.values.position),Transform3D(Basis.IDENTITY,b.values.position),kind)
	a.values.structure_connections[id].breaking_force=strength; a.values.structure_connections[id].breaking_torque=strength*10; a.values.structure_connections[id].damage_rate=0.0
	return id
func state(actor: ActorData) -> Dictionary: return editor.physics.display_states[actor.id]
func reset() -> void:
	editor.physics.dispose(); editor.model.history.clear_history(); editor.model.actors.clear(); editor.model.clips.clear(); editor.model.selected_ids.clear(); editor.model.selected_id=""; editor.model.changed.emit()
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); view.size=Vector2i(800,600); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var anchor:=add(Vector3(0,3,0),1); var body:=add(Vector3(0,1,0)); var id:=joint(anchor,body,Vector3(0,2,0),40)
	await seek(.5); print("JOINT ",state(anchor).structural.links[id]," BODY ",state(body).pose.origin)
	check(not state(anchor).structural.links[id].broken and state(body).pose.origin.y>.98,"A weld holds an actual gravity-loaded rigid element below its force threshold")
	body.values.physics.forces=[{"time":.5,"duration":.3,"force":Vector3(0,-100,0)}]; editor.model.changed.emit(); await seek(1.1)
	check(state(anchor).structural.links[id].broken and state(body).pose.origin.y<.8,"Increasing applied force breaks the joint and releases independent motion")
	reset()
	var platform:=add(Vector3(0,3,0),0,12,Vector3(4,.3,2)); var supports: Array[ActorData]=[]; var joints: Array[String]=[]
	for x in [-1.5,1.5]:
		var support:=add(Vector3(x,1.5,0),1,1,Vector3(.3,2.5,.3)); supports.append(support); joints.append(joint(support,platform,Vector3(x,2.8,0),70))
		support.values.physics.collision=false # Isolate joint load paths; loose compressive contact is tested separately.
	await seek(.5); var first_load:=float(state(supports[0]).structural.links[joints[0]].load); var second_load:=float(state(supports[1]).structural.links[joints[1]].load)
	print("PLATFORM loads ",first_load," ",second_load," y ",state(platform).pose.origin.y)
	check(state(platform).pose.origin.y>2.95 and first_load>20 and second_load>20,"Multiple supports carry and share a platform's actual weight")
	supports[0].values.structure_connections[joints[0]].break_at=.6; editor.model.changed.emit(); await seek(.62)
	var increased:=float(state(supports[1]).structural.links[joints[1]].load)
	check(increased>second_load*1.15,"Removing a support redistributes measured reaction load onto remaining supports")
	await seek(1.4); check(state(supports[1]).structural.links[joints[1]].broken and state(platform).pose.origin.y<2.5,"Redistributed overload produces a progressive collapse, not a blanket gravity toggle")
	var snapshot: Transform3D=state(platform).pose; var integrity: Dictionary=state(supports[1]).structural.links.duplicate(true); var steps:=editor.physics.steps_taken
	await seek(1.4); check(steps==editor.physics.steps_taken,"Paused structural simulation takes no hidden steps")
	await seek(.4); check(not state(supports[0]).structural.links[joints[0]].broken and state(platform).pose.origin.y>2.95,"Rewind restores joint integrity and the supported platform")
	await seek(1.4); check(state(platform).pose.is_equal_approx(snapshot) and state(supports[1]).structural.links==integrity,"Seeking reconstructs identical transforms, loads and damage")
	var other_anchor:=add(Vector3(8,3,0),1); var other:=add(Vector3(8,1,0)); var other_id:=joint(other_anchor,other,Vector3(8,2,0),1000); await seek(1.4)
	check(not state(other_anchor).structural.links[other_id].broken and state(other).pose.origin.y>.98 and state(platform).pose.origin.y<2.5,"An independently supported section stays standing during partial collapse")
	var source:=KiwiPhysicsSettings.fingerprint(editor.model); other.values.color=Color.RED; check(source==KiwiPhysicsSettings.fingerprint(editor.model),"Appearance-only edits do not invalidate structural physics")
	var scene:=editor.capture_scene_data(); var path:="user://structure_"+ActorData.new_id()+".tres"; ResourceSaver.save(scene,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	check(loaded.actors[1].values.structure_connections[joints[0]].target==platform.id and loaded.actors[1].values.structure_connections[joints[0]].break_at==.6,"Scene saving preserves stable structural targets and authored failures")
	DirAccess.remove_absolute(path)
	var error:=await editor.physics.bake(editor,platform,0,1.5); check(error.is_empty(),"Existing physics baking records structural collapse state")
	await seek(1.4); check(state(platform).pose.is_equal_approx(snapshot),"Baked collapse reproduces the same element transform")
	editor.physics.dispose(); editor.model.history.clear_history(); editor.queue_free(); view.queue_free(); await process_frame
	print("STRUCTURAL PHYSICS: %d checks, %d failures"%[checks,failures]); quit(failures)
