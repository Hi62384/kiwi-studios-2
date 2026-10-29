extends "res://scripts/actors/tests/structure_physics_test.gd"
func fractured(point: Vector3,mass: float=2,material: int=5,secondary: bool=false) -> ActorData:
	var data:=add(point,0,mass,Vector3.ONE*.8); data.values.structure_enabled=false; data.values.physics.enabled=true; data.values.physics.angular_velocity=Vector3(0,45,10); data.values.destruction_enabled=true; data.values.destruction_material=ActorObjectReference.from_object(KiwiDestructionMaterial.preset(material)); data.values.debris_secondary=secondary; data.values.debris_secondary_energy=1.0; data.values.debris_depth=1; data.values.debris_budget=32
	var op:=KiwiDestructionDefinition.operation(1,.1); op.pieces=3; op.impulse=.15; KiwiDestructionDefinition.edit(editor.model,data,{"fracture":op}); return data
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); view.size=Vector2i(800,600); view.own_world_3d=true; view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var camera:=Camera3D.new(); camera.position=Vector3(4,4,7); view.add_child(camera); camera.look_at(Vector3(0,1,0)); camera.make_current(); var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-55,-25,0); view.add_child(sun)
	var floor_actor:=add(Vector3(0,-.2,0),1,1,Vector3(20,.4,20)); var actor:=fractured(Vector3(0,2,0),8)
	await seek(.3); var initial: Array=state(actor).destruction_fragments.duplicate(true); check(initial.size()==3 and initial[0].id!=initial[1].id,"Fracture produces real uniquely identified geometry, not decorative particles")
	var total:=0.0; var distinct:={}
	for fragment: Dictionary in initial: total+=float(fragment.mass); distinct[fragment.v]=true
	check(absf(total-8)<.00001 and distinct.size()>1,"Fragment volume masses conserve the source mass and inherit position-dependent angular motion")
	await seek(1.6); var fragments: Array=state(actor).destruction_fragments; var physical:=true
	for fragment: Dictionary in fragments: physical=physical and fragment.pose.origin.y>-.1 and fragment.pose.origin.y<1.1 and editor.physics.world.bodies.has(fragment.id)
	check(physical,"Independent fragments tumble, collide and remain above the actual floor")
	var pairs:=0
	for a in fragments:
		for b in fragments:
			if a.id!=b.id and a.pose.origin.distance_to(b.pose.origin)>.15: pairs+=1
	check(pairs>=4,"Fracture pieces separate through physical contacts instead of occupying one shared transform")
	check(state(actor).destruction_events.any(func(event: Dictionary): return event.type=="impact"),"Actual debris impacts produce timestamped physical VFX events")
	var saved: Dictionary=editor.physics._snapshot({actor.id:state(actor)})[actor.id]; var particle_count:=editor.physics.vfx.particle_count; var steps:=editor.physics.steps_taken
	await seek(1.6); check(steps==editor.physics.steps_taken and particle_count==editor.physics.vfx.particle_count,"Paused debris and effects do not advance or emit duplicate bursts")
	await seek(.05); check(not state(actor).has("destruction_fragments") and editor.physics.vfx.particle_count==0,"Rewinding before fracture restores the intact actor and removes its effects")
	await seek(1.6); check(state(actor).destruction_fragments[0].pose==saved.destruction_fragments[0].pose and state(actor).destruction_events==saved.destruction_events,"Debris identities, secondary contacts and effect seeds replay deterministically")
	var fingerprint:=KiwiPhysicsSettings.fingerprint(editor.model); actor.values.debris_intensity=2.0; check(fingerprint==KiwiPhysicsSettings.fingerprint(editor.model),"Effect appearance changes do not invalidate physical trajectories")
	var event: Dictionary=state(actor).destruction_events[0]; var counts:=[]; var style_set:={}
	for index in [0,1,3,5]:
		var values:=actor.values.duplicate(true); values.destruction_material=ActorObjectReference.from_object(KiwiDestructionMaterial.preset(index)); var rules:=KiwiDestructionVFX.rules(values); var kinds:=[]
		for rule in rules: kinds.append(rule.style)
		style_set[str(kinds)]=true
	check(style_set.size()==4,"Glass, metal, wood and concrete choose distinct chips, sparks, splinters and dust rules")
	var metal:=actor.values.duplicate(true); metal.destruction_material=ActorObjectReference.from_object(KiwiDestructionMaterial.preset(1)); var spark:=KiwiDestructionVFX.rules(metal)[0]; var scrape:=event.duplicate(); scrape.type="scrape"; scrape.energy=30.0
	check(KiwiDestructionVFX.particles(event,spark,metal,event.time+.1).is_empty() and not KiwiDestructionVFX.particles(scrape,spark,metal,event.time+.1).is_empty(),"Cold metal splitting does not spark; energetic contact or scraping can")
	var preset:=editor.registry.get_object_definition(&"debris_vfx").create_object(); preset.values.color=Color.MAGENTA; preset.values.style=1; actor.values.debris_vfx_preset=ActorObjectReference.from_object(preset)
	check(KiwiDestructionVFX.rules(actor.values).size()==1 and KiwiDestructionVFX.rules(actor.values)[0].color==Color.MAGENTA,"A reusable custom effect resource replaces automatic rules")
	var path:="user://debris_scene_"+ActorData.new_id()+".tres"; ResourceSaver.save(editor.capture_scene_data(),path); var scene:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	check(ActorAnimation.resolve_reference(scene.actors[-1].values.debris_vfx_preset).values.color==Color.MAGENTA,"Scene saving retains the custom VFX resource and physical settings"); DirAccess.remove_absolute(path)
	actor.values.debris_vfx_preset=null; await seek(1.2); await RenderingServer.frame_post_draw
	check(view.get_texture().get_image().save_png("res://.godot/verification/debris_effects.png")==OK,"Native debris/effect rendering is captured for visual inspection")
	var original_count:=editor.model.actors.size(); KiwiDebris.copy_fragments(editor,actor)
	check(editor.model.actors.size()>original_count,"Current debris can be copied to independently editable mesh actors")
	editor.model.undo(); check(editor.model.actors.size()==original_count,"Copying debris as actors is a single undoable authoring action")
	var error:=await editor.physics.bake(editor,actor,0,1.7); check(error.is_empty(),"Physics baking stores fragment motion and deterministic effect events")
	await seek(1.6); check(state(actor).destruction_events==saved.destruction_events,"Baked event timing matches live fixed-step simulation")
	reset(); floor_actor=add(Vector3(0,-.2,0),1,1,Vector3(20,.4,20)); actor=fractured(Vector3(0,3,0),10,0,true); await seek(1.5)
	var maximum_depth:=0; total=0
	for fragment: Dictionary in state(actor).destruction_fragments: maximum_depth=maxi(maximum_depth,int(fragment.get("depth",0))); total+=float(fragment.mass)
	check(maximum_depth==1 and state(actor).destruction_fragments.size()>3 and state(actor).destruction_fragments.size()<=32 and absf(total-10)<.0001,"Energetic brittle chunks fracture again with bounded recursion and conserved mass")
	reset(); floor_actor=add(Vector3(0,-.2,0),1,1,Vector3(20,.4,20)); var target:=add(Vector3(0,.5,0),0,1,Vector3(3,.4,3)); target.values.structure_enabled=false; target.values.physics={"enabled":true,"body_mode":1}; target.values.destruction_enabled=true; target.values.destruction_mode=1; target.values.destruction_material=ActorObjectReference.from_object(KiwiDestructionMaterial.preset(0)); actor=fractured(Vector3(0,3,0),12); await seek(1.5)
	check(state(target).get("destruction_detached",false) or not state(target).get("destruction_damage_cells",{}).is_empty(),"Falling debris transfers impact energy into another actor's existing material damage system")
	print("DEBRIS BENCH last_step_us=",editor.physics.debris.elapsed_usec," particles=",editor.physics.vfx.particle_count)
	editor.physics.dispose(); editor.model.history.clear_history(); editor.queue_free(); view.queue_free(); await process_frame
	print("DEBRIS / VFX: %d checks, %d failures"%[checks,failures]); quit(failures)
