extends "res://scripts/actors/tests/destruction_timeline_test.gd"
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var viewport:=SubViewport.new(); viewport.size=Vector2i(600,400); root.add_child(viewport); editor.runtime_holder=Node3D.new(); viewport.add_child(editor.runtime_holder)
	var actor:=add(&"basic_shape",{&"position":Vector3(0,2,0),&"destruction_enabled":true}); actor.values.physics={"enabled":true,"gravity":1.,"collision":false}
	var operation:=KiwiDestructionDefinition.operation(0,.2); operation.impulse=1.; KiwiDestructionDefinition.edit(editor.model,actor,{"cut":operation})
	var error:=await editor.physics.bake_group(editor,0,1,30); check(error.is_empty(),"Source group bake completes")
	await seek(.5); var original: Dictionary=editor.physics._snapshot({actor.id:state(actor)})[actor.id]; var captured:=KiwiBakeEditing.portable_scene(editor)
	check(str(captured.error).is_empty(),"Complete baked rigid assembly captures with authored source data")
	if not str(captured.error).is_empty(): quit(1); return
	var path:="user://baked assembly.tres"; ResourceSaver.save(captured.scene,path); var scene:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	var root_clip:=editor.model.instantiate_scene(scene,editor.registry.get_definition(&"point_3d"),2,3,"Reusable break")
	check(root_clip!=null and is_equal_approx(root_clip.duration,1.),"Reusable assembly length matches its verified baked interval")
	var root_actor:=editor.model.actor_for_id(root_clip.actor_id); root_actor.values.position=Vector3(5,0,0); root_actor.values.rotation=Vector3(0,30,0); editor.physics.mark_dirty()
	await seek(2.5); var child: ActorData
	for candidate: ActorData in editor.model.actors:
		if candidate.parent_id==root_actor.id: child=candidate; break
	check(child!=null and state(child).get("destruction_detached",false),"Instantiated bake replays fracture topology at the remapped scene time")
	if child==null: quit(1); return
	var offset:=editor.physics.animated_world(root_actor.id,2.5); var result: Dictionary=state(child)
	check(result.destruction_fragments[0].pose.is_equal_approx(offset*original.destruction_fragments[0].pose),"Parent translation and rotation transform actual baked fragment poses")
	check(str(result.destruction_fragments[0].id).begins_with(child.id+":fragment:"),"Baked fragment ownership remaps to the independent copied actor")
	var steps:=editor.physics.steps_taken; await seek(2.5); check(steps==editor.physics.steps_taken,"Paused portable playback does not advance simulation")
	check(child.values.physics.bake.cache==scene.actors[0].values.physics.bake.cache,"Reusable assembly shares its loaded immutable compressed motion data")
	var prior:=editor.physics._baked(child.values.physics.bake,2.5); child.values.physics.gravity=2.; editor.physics.mark_dirty(); await seek(2.5)
	check(not prior.is_empty() and editor.physics._baked(child.values.physics.bake,2.5).is_empty(),"Physical edits invalidate portable playback and require recalculation")
	DirAccess.remove_absolute(path); editor.physics.dispose(); editor.queue_free(); viewport.queue_free(); await process_frame
	print("BAKED ASSEMBLY: %d checks, %d failures"%[checks,failures]); quit(failures)
