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
	var clip:=editor.model.create_actor(editor.registry.get_definition(type),0,values); clip.start_time=0; clip.duration=5; clip.layer=editor.model.clips.size()-1; return editor.model.selected_actor()
func state(actor: ActorData) -> Dictionary: return editor.physics.display_states[actor.id]
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); view.size=Vector2i(600,400); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var floor_actor:=add(&"basic_shape",{&"box_size":Vector3(20,.2,20),&"position":Vector3(0,-.1,0)}); floor_actor.values.physics={"enabled":true,"body_mode":1,"friction":.8}
	var cube:=add(&"basic_shape",{&"position":Vector3(0,2,0),&"destruction_enabled":true}); cube.values.physics={"enabled":true,"mass":2.0,"bounce":.05}
	var op:=KiwiDestructionDefinition.operation(0,.3); KiwiDestructionDefinition.edit(editor.model,cube,{"cut":op}); await seek(.2)
	check(not state(cube).get("destruction_detached",false),"Fracture does not occur before its authored source time")
	await seek(.301)
	check(state(cube).get("destruction_detached",false) and state(cube).destruction_fragments.size()==2,"Fracture events create independently identified fragment inventories")
	await seek(1.0)
	var fragments: Array=state(cube).get("destruction_fragments",[]); var valid:=fragments.size()==2; var total:=0.0
	for fragment: Dictionary in fragments:
		total+=float(fragment.mass); valid=valid and fragment.pose.origin.y>.1 and editor.physics.world.bodies.has(fragment.id)
	print("FRAGMENTS ",fragments.map(func(f: Dictionary): return [f.pose.origin,f.mass]))
	check(valid and absf(total-2)<.00001 and fragments[0].pose.origin.distance_to(fragments[1].pose.origin)>.7,"Real convex fragments inherit mass, separate, fall and collide with the floor")
	var snapshot: Dictionary=editor.physics._snapshot({cube.id:state(cube)})[cube.id]; var steps:=editor.physics.steps_taken
	await seek(1.0); check(steps==editor.physics.steps_taken,"Paused fragment physics does not advance")
	await seek(.1); check(not state(cube).get("destruction_detached",false),"Rewind restores the unbroken source geometry")
	await seek(1.0); check(state(cube).destruction_fragments[0].pose==snapshot.destruction_fragments[0].pose,"Seeking reconstructs identical fragment geometry, identities and transforms")
	KiwiDestructionDefinition.edit(editor.model,cube,{}); await seek(0)
	check(not state(cube).has("destruction_geometry"),"Removing operations restores the original mesh and collider")
	editor.model.undo(); await seek(1.)
	check(state(cube).get("destruction_detached",false),"Destruction edits participate in the normal undo history")
	var error:=await editor.physics.bake(editor,cube,0,1.1); check(error.is_empty(),"Existing physics baking stores topology and fragment state")
	await seek(1.); check(state(cube).destruction_fragments.size()==2,"Baked states reconstruct fragment topology")
	var scene:=editor.capture_scene_data(); var path:="user://destruction_"+ActorData.new_id()+".tres"; ResourceSaver.save(scene,path); var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	check(reopened.actors[-1].values.destruction_operations.has("cut") and reopened.actors[-1].values.physics.bake.frames[-1].destruction_fragments[0].mesh is KiwiModelMesh,"Scene serialization preserves editable operations and baked real mesh fragments")
	DirAccess.remove_absolute(path)
	# A static manually carved surface must have an actual collision opening.
	var panel:=add(&"basic_shape",{&"position":Vector3(4,1,0),&"box_size":Vector3(.2,2,2),&"destruction_enabled":true}); panel.values.physics={"enabled":true,"body_mode":1}
	var carve:=KiwiDestructionDefinition.operation(7); carve.position=Vector3.ZERO; carve.radius=.3; carve.amount=2.; carve.direction=Vector3.RIGHT; KiwiDestructionDefinition.edit(editor.model,panel,{"hole":carve}); await seek(0)
	var excluded: Array[String]=[floor_actor.id,cube.id]
	var hit:=editor.physics.world.point_motion("probe",Vector3(3,1,0),Vector3(5,1,0),.04,1,1,excluded)
	check(hit.position.x>4.8,"Carved geometry updates compound collision so objects can pass through the hole")
	var rim:=editor.physics.world.point_motion("probe",Vector3(3,1,.7),Vector3(5,1,.7),.04,1,1,excluded)
	check(rim.position.x<4.2,"The remaining material still blocks objects outside the carved opening")
	print("DESTRUCTION PREPARE ms=",editor.physics.destruction.elapsed_usec/1000.," builds=",editor.physics.destruction.builds)
	editor.physics.dispose(); editor.queue_free(); view.queue_free(); await process_frame
	print("DESTRUCTION TIMELINE: %d checks, %d failures"%[checks,failures]); quit(failures)
