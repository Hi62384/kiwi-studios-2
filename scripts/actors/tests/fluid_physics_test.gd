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
	var clip:=editor.model.create_actor(editor.registry.get_definition(type),0,values); clip.start_time=0; clip.layer=editor.model.clips.size()-1; clip.duration=5
	var actor:=editor.model.selected_actor(); editor.model.changed.emit(); return actor
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor)
	var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); root.add_child(viewport); editor.runtime_holder=Node3D.new(); viewport.add_child(editor.runtime_holder)
	check(editor.registry.get_definition(&"fluid")!=null,"Fluid is registered in the normal actor catalog")
	var floor_actor:=add(&"basic_shape",{&"position":Vector3(0,-.25,0),&"box_size":Vector3(8,.5,8)})
	floor_actor.values[&"physics"]={"enabled":true,"body_mode":1}; editor.model.changed.emit()
	var liquid:=add(&"fluid",{&"position":Vector3(0,1,0),&"fluid_dimensions":Vector3(.88,1.144,.88),&"fluid_quality":0})
	await seek(0)
	var state: Dictionary=editor.physics.display_states[liquid.id]; var count: int=state.points.size(); var start: PackedVector3Array=state.points.duplicate()
	check(count>15 and count<200,"Initial volume generates a bounded internal particle set")
	var runtime:=editor._runtime_for_clip(editor.model.clip_for_actor_id(liquid.id).id) as KiwiFluidRuntime
	check(runtime.surface.mesh.get_surface_count()==1 and runtime.surface.get_child_count()==0,"Liquid is a reconstructed mesh, not particle actor instances")
	await seek(.7); state=editor.physics.display_states[liquid.id]
	var minimum:=INF; var spread:=0.0
	for p: Vector3 in state.points: minimum=minf(minimum,p.y); spread=maxf(spread,Vector2(p.x,p.z).length())
	print("LIQUID particles=",count," minimum_y=",minimum," spread=",spread)
	check(state.points.size()==count and minimum>.04,"Liquid falls and its particles collide with the floor without disappearing")
	check(spread>.4,"An uncontained volume collapses and spreads rather than remaining a rigid block")
	var saved: PackedVector3Array=state.points.duplicate(); var steps:=editor.physics.steps_taken
	await seek(.7); check(editor.physics.steps_taken==steps,"Paused fluid does not integrate again")
	await seek(.2); await seek(.7); check(editor.physics.display_states[liquid.id].points==saved,"Rewind and replay reproduce particle positions exactly")
	var generation:=editor.physics.generation
	editor.model.edit_property(liquid,editor.registry.get_definition(&"fluid"),&"fluid_color",Color.RED)
	await seek(.7); check(editor.physics.generation==generation,"Appearance edits reuse the physical cache")
	KiwiFluidSettings.preset(editor.model,liquid,2); await seek(.2)
	check(float(liquid.values.fluid_viscosity)>50 and editor.physics.generation>generation,"Honey preset changes real viscosity and invalidates physics")
	editor.model.undo(); await seek(.7); check(editor.physics.display_states[liquid.id].points==saved,"Liquid preset is undoable as one transaction")
	var emitter:=add(&"fluid",{&"position":Vector3(2,2,0),&"fluid_source_mode":1,&"fluid_emit_rate":30.0,&"fluid_supply":9,&"fluid_quality":0})
	await seek(.4); var emitted: Dictionary=editor.physics.display_states[emitter.id]; check(emitted.points.size()==9 and emitted.fluid_ids.size()==9,"Emitter enforces finite supply with stable particle IDs")
	var emitted_saved: PackedVector3Array=emitted.points.duplicate(); await seek(.1); await seek(.4)
	check(editor.physics.display_states[emitter.id].points==emitted_saved,"Emitter births and velocities reproduce on rewind")
	var error: String=await editor.physics.bake(editor,liquid,0,.4)
	check(error.is_empty(),"Fluid state bakes through shared timeline physics")
	await seek(.2)
	var scene:=ActorSceneData.new(); scene.actors.assign(editor.model.actors); scene.clips.assign(editor.model.clips)
	var path:="user://fluid_test_"+ActorData.new_id()+".tres"
	check(ResourceSaver.save(scene,path)==OK,"Scene saves fluid settings and baked particle state")
	var restored:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	check(restored!=null and restored.actors.any(func(a: ActorData): return a.type_id==&"fluid" and not KiwiPhysicsSettings.authored(a).bake.is_empty()),"Baked fluid survives a native resource round trip")
	DirAccess.remove_absolute(path)
	var config:=KiwiFluidSettings.effective(liquid.values); config.fluid_dimensions=Vector3(10,10,10); config.budget=16
	check(not KiwiFluidVolume.generate(config,Transform3D.IDENTITY).error.is_empty(),"Over-budget volumes fail clearly rather than truncating silently")
	editor.queue_free(); viewport.queue_free(); await process_frame
	print("FLUID PHYSICS: %d checks, %d failures"%[checks,failures]); quit(0 if failures==0 else 1)
