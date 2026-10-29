extends "res://scripts/actors/tests/destruction_timeline_test.gd"
const Solver=preload("res://scripts/actors/fog/fog_transport_solver.gd")
const Motion=preload("res://scripts/actors/fog/fog_motion_definition.gd")
func right_mass(fog: ActorData) -> float:
	var rho: PackedFloat32Array=state(fog).fog_density; var total:=0.; var n:=int(state(fog).fog_n)
	for i in rho.size():
		if i%n>=n/2+1: total+=rho[i]
	return total
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(400,300); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var source:=editor.registry.get_object_definition(&"fog_emitter").create_object(); source.values.merge({&"shape":0,&"position":Vector3(-1,0,0),&"mode":1,&"burst":.2,&"velocity":Vector3.RIGHT*2.},true)
	var wall:=add(&"basic_shape",{&"box_size":Vector3(.2,6,6)}); wall.values.physics={"enabled":true,"body_mode":1}
	var fog:=add(&"fog_volume",{&"shape":3,&"volume_size":Vector3.ONE*4.,&"fog_motion_mode":2,&"fog_initial":1,&"fog_wind":Vector3.RIGHT*2.,&"fog_boundaries":1,&"fog_pressure_iterations":0,&"fog_character_proxies":false,&"fog_velocity_damping":0.,&"fog_source_0":ActorObjectReference.from_object(source)})
	editor.model.changed.emit() # Commit the fixture's direct clip timing changes.
	await seek(.6); check(right_mass(fog)<.000001,"Configured static scene colliders stop density from passing through a complete wall")
	var count:=0
	for value: int in state(fog).fog_solid: count+=value
	print("FOG WALL sealed occupied=",count," mass=",Solver.total_mass(state(fog))," emitted=",state(fog).fog_emitted," lost=",state(fog).fog_lost," origin=",editor.physics.origin)
	check(count>0 and absf(Solver.total_mass(state(fog))-.2)<.0001,"Scene obstacle occupancy preserves injected mass in a sealed domain")
	wall.values[&"position"]=Vector3(0,5,0); editor.model.changed.emit(); await seek(.6)
	print("FOG WALL transport right_mass=",right_mass(fog)," occupied=",state(fog).fog_solid.count(1))
	check(right_mass(fog)>.01,"Moving the wall out of the domain opens the actual transport path")
	var sampled: PackedFloat32Array=state(fog).fog_density.duplicate(); var stable:=true
	for fps in [24,30,60]:
		await seek(0.)
		for frame in fps/2+1: await seek(float(frame)/fps)
		await seek(.6); stable=stable and state(fog).fog_density==sampled
	check(stable,"Matching scene times reproduce concentration across 24, 30 and 60 fps sampling schedules")
	var linked:=ActorAnimation.resolve_reference(fog.values[&"fog_source_0"]); linked.values[&"source_actor"]=wall.id
	var copy:=fog.copy_actor(); Motion.remap_actor(copy,{wall.id:"new-wall"})
	check(Motion.dependencies(copy)==["new-wall"] and str(linked.values[&"source_actor"])==wall.id,"Copied source attachments remap without changing shared authoring resources")
	Motion.remap_actor(copy,{},true); check(Motion.dependencies(copy).is_empty(),"Instantiating a scene safely releases missing external source attachments")
	editor.physics.freeze(editor.model,fog); await seek(.6); var held: PackedFloat32Array=state(fog).fog_density.duplicate(); await seek(.8)
	check(state(fog).fog_density==held,"Freeze holds the transported concentration without advancing motion")
	editor.model.undo(); await seek(.6); check(int(KiwiPhysicsSettings.authored(fog).mode)==1,"Fog freeze uses the shared undo history")
	editor.physics.dispose(); editor.queue_free(); view.queue_free(); await process_frame; print("FOG MOTION OBSTACLES: %d checks, %d failures"%[checks,failures]); quit(failures)
