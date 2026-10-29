extends "res://scripts/actors/tests/destruction_timeline_test.gd"
const Solver=preload("res://scripts/actors/fog/fog_transport_solver.gd")
const Motion=preload("res://scripts/actors/fog/fog_motion_definition.gd")
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(600,400); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var source:=editor.registry.get_object_definition(&"fog_emitter").create_object(); source.values.merge({&"shape":0,&"position":Vector3(-1,0,0),&"rate":.3,&"velocity":Vector3.RIGHT},true)
	var fog:=add(&"fog_volume",{&"shape":3,&"volume_size":Vector3.ONE*4.,&"fog_motion_mode":2,&"fog_initial":1,&"fog_wind":Vector3.RIGHT,&"fog_velocity_damping":0.,&"fog_obstacles":false,&"fog_source_0":ActorObjectReference.from_object(source)})
	check(KiwiPhysicsSettings.authored(fog).enabled and int(KiwiPhysicsSettings.authored(fog).type)==9,"Simulated fog automatically uses the shared timeline controller")
	check(editor.registry.get_definition(&"global_fog").find_property(&"fog_motion_mode").options.choices.size()==2,"Global atmosphere exposes only static and procedural motion")
	await seek(.5); var before: Dictionary=editor.physics._snapshot({"fog":state(fog)}).fog
	check(absf(Solver.total_mass(before)+float(before.fog_lost)-.15)<.0001 and float(before.fog_emitted)>.14,"Continuous sources inject represented density at the fixed source time")
	var runtime: Node=editor.physics._runtime(fog.id); var material: ShaderMaterial=runtime.content.material
	check(material.get_shader_parameter("has_simulation")==true and material.get_shader_parameter("simulation_density") is ImageTexture3D,"Concentration is uploaded into the native volumetric fog material")
	var steps:=editor.physics.steps_taken; await seek(.5)
	check(editor.physics.steps_taken==steps,"Paused fog never advances its solver")
	await seek(.1); await seek(.5)
	check(state(fog).fog_density==before.fog_density and state(fog).fog_velocity==before.fog_velocity,"Backward seeking replays identical density and velocity")
	var signature:=KiwiPhysicsSettings.fingerprint(editor.model); fog.values[&"albedo"]=Color.RED; fog.values[&"density"]=.1
	check(signature==KiwiPhysicsSettings.fingerprint(editor.model),"Appearance and optical density edits preserve the physical simulation signature")
	var owned:=ActorAnimation.resolve_reference(fog.values[&"fog_source_0"]); owned.values[&"rate"]=.6
	check(signature!=KiwiPhysicsSettings.fingerprint(editor.model),"Nested source changes invalidate physical caches")
	owned.values[&"rate"]=.3; editor.physics.mark_dirty(); await seek(.5)
	var error:=await editor.physics.bake_group(editor,0,.6,30)
	check(error.is_empty(),"Fog uses the normal persistent physics bake transaction: "+error)
	await seek(.5)
	check(state(fog).fog_density==before.fog_density,"Baked density reproduces the live fixed-step sample")
	var scene:=editor.capture_scene_data(); var path:="user://fog-motion.tres"; ResourceSaver.save(scene,path); var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	check(reopened!=null and reopened.actors[-1].values.physics.bake.cache is KiwiPhysicsBakeCache,"Scene resources preserve fog motion sources and baked grids")
	DirAccess.remove_absolute(path); editor.physics.dispose(); editor.queue_free(); view.queue_free(); await process_frame
	print("FOG MOTION TIMELINE: %d checks, %d failures"%[checks,failures]); quit(failures)
