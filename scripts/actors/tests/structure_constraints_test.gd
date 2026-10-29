extends "res://scripts/actors/tests/structure_physics_test.gd"
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); view.size=Vector2i(600,400); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	for kind in 5:
		reset(); var support:=add(Vector3(0,3,0),1); var body:=add(Vector3(0,1,0)); var id:=joint(support,body,Vector3(0,2,0),10000,kind)
		var link: Dictionary=support.values.structure_connections[id]
		body.values.physics.collision=false
		if kind==1: body.values.physics.angular_velocity=Vector3(0,90,0)
		if kind==2: body.values.physics.forces=[{"time":0,"duration":1,"force":Vector3(100,0,0)}]
		if kind in [3,4]: link.pivot=Vector3.ZERO; link.target_pivot=Vector3.ZERO; link.length=2
		if kind==4: link.stiffness=30
		await seek(.6)
		print("KIND ",kind," pose ",state(body).pose," load ",state(support).structural.links[id].load)
		if kind==0: check(state(body).pose.origin.y>.99,"Fixed joints constrain translation and orientation")
		if kind==1: check(absf(state(body).pose.basis.get_euler().y)>.2 and state(body).pose.origin.y>.98,"Hinges retain pivot support while allowing rotation about their axis")
		if kind==2: check(absf(state(body).pose.origin.x)<.05 and state(body).pose.origin.y<.9,"Sliders allow axial travel but resist transverse forces")
		if kind==3: check(state(body).pose.origin.distance_to(state(support).pose.origin)<2.01,"Tension cables hold their maximum length without fixing orientation")
		if kind==4: check(state(body).pose.origin.y<.95 and state(body).pose.origin.y>-.5,"Flexible springs stretch under weight instead of behaving as rigid welds")
	reset(); var a:=add(Vector3(0,4,0)); var b:=add(Vector3(0,2,0)); joint(a,b,Vector3(0,3,0)); await seek(.6)
	check(state(a).pose.origin.y<3 and state(b).pose.origin.y<1 and not state(a).structural.supported,"An unanchored connected island falls; connectivity alone never makes it float")
	reset(); var ground:=add(Vector3(0,-.5,0),1,1,Vector3(10,1,10)); var loose:=add(Vector3(0,1.1,0)); loose.parent_id=ground.id; await seek(.6)
	check(loose.values.structure_connections.is_empty() and state(loose).pose.origin.y>.4 and state(loose).pose.origin.y<.6,"Loose blocks carry compressive contact without parenting creating a weld")
	reset(); var weak:=add(Vector3(-3,3,0),1); var weak_body:=add(Vector3(-3,1,0),0,3); var weak_id:=joint(weak,weak_body,Vector3(-3,2,0),10)
	var strong:=add(Vector3(3,3,0),1); var strong_body:=add(Vector3(3,1,0),0,3); var strong_id:=joint(strong,strong_body,Vector3(3,2,0),500)
	await seek(.6); check(state(weak).structural.links[weak_id].broken and not state(strong).structural.links[strong_id].broken,"Identical gravity loads break weak connections but not strong ones")
	var before: String=editor.physics.signature; KiwiStructure.set_value(editor.model,strong,strong_id,"strength",.001); await seek(.6)
	check(before!=editor.physics.signature and state(strong).structural.links[strong_id].broken,"Editing joint strength invalidates subsequent cached physics")
	editor.model.undo(); await seek(.6); check(not state(strong).structural.links[strong_id].broken,"Undo restores the stronger connection and reconstructs its intact simulation")
	reset(); var support:=add(Vector3(0,3,0),1); var beam:=add(Vector3(2,3,0),0,3); var id:=joint(support,beam,Vector3(0,3,0),100000); support.values.structure_connections[id].breaking_torque=2
	await seek(.3); check(state(support).structural.links[id].broken and state(support).structural.links[id].reason=="Force / torque overload","Lever-arm torque can break a connection even with a very high direct-force threshold")
	for material_index in [0,1]:
		reset(); support=add(Vector3(0,3,0),1); beam=add(Vector3(0,1,0),0,8); id=joint(support,beam,Vector3(0,2,0),100000)
		support.values.structure_connections[id].stiffness=100; beam.values.destruction_enabled=true; beam.values.destruction_mode=2; beam.values.destruction_material=ActorObjectReference.from_object(KiwiDestructionMaterial.preset(material_index)); beam.values.physics.collision=false
		await seek(1.2)
		print("MATERIAL ",material_index," load ",state(support).get("structural",{})," damage ",state(beam).get("destruction_damage_cells",{})," error ",state(beam).get("destruction_error",""))
		if material_index==0: check(state(beam).get("destruction_detached",false),"Structural strain energy drives real brittle material fracture through the existing damage engine")
		else: check(not state(beam).get("destruction_detached",false),"Ductile material withstands the same structural loading without brittle fragmentation")
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var document:=KiwiModelDocument.new(); var first:=KiwiModelComponent.new(); first.id="a"; first.mesh=KiwiModelPrimitives.box(Vector3.ONE); var second:=first.copy_component(); second.id="b"; second.transform.origin=Vector3.RIGHT*2; document.components.assign([first,second]); first.structural={&"structure_enabled":true,&"structure_role":1,&"structure_connections":{"joint":KiwiStructure.connection("b")}}; second.structural={&"structure_enabled":true}
	var scene:=document.actor_scene(registry,""); check(scene.actors.size()==2 and scene.actors[0].values.structure_connections.joint.target=="b","Model components retain stable structural relationships when instantiated as scene actors")
	var session:=KiwiModelSession.new(); session.document=document; session.selected.assign(["a","b"]); session.duplicate_selected(); var copy:=session.document.components[2]
	check(copy.structural.structure_connections.joint.target==session.document.components[3].id,"Duplicating model assemblies remaps internal component targets")
	var actor:=registry.get_definition(&"basic_shape").create_actor({&"structure_connections":{"joint":KiwiStructure.connection("old")}}); KiwiStructure.remap_actor(actor,{"old":"new"})
	check(actor.values.structure_connections.joint.target=="new","Scene assembly remapping never links a copy back to its original target")
	reset(); support=add(Vector3(0,3,0),1); beam=add(Vector3(0,1,0)); id=joint(support,beam,Vector3(0,2,0),1000)
	editor.canvas.playhead=0; editor.model.playhead_time=0; editor.model.add_keyframe(support,PackedStringArray(["structure_enabled"]),"Support active",true,true); editor.canvas.playhead=.2; editor.model.playhead_time=.2; editor.model.add_keyframe(support,PackedStringArray(["structure_enabled"]),"Support active",false,true); await seek(.5)
	check(not state(support).active and state(beam).pose.origin.y<.9,"Animated support deactivation removes its physics support at the authored timeline time")
	reset(); support=add(Vector3(0,3,0),1); beam=add(Vector3(0,1,0)); id=joint(support,beam,Vector3(0,2,0),16); support.values.structure_connections[id].damage_rate=20
	await seek(.1); var intact: bool=not state(support).structural.links[id].broken; await seek(1.8)
	check(intact and state(support).structural.links[id].broken and state(support).structural.links[id].damage>0,"Repeated sub-threshold load accumulates joint damage before progressive failure")
	reset(); support=add(Vector3(0,3,0),1); beam=add(Vector3(0,1,0)); id=joint(support,beam,Vector3(.25,1,0),100000); beam.values.destruction_enabled=true
	var split:=KiwiDestructionDefinition.operation(0,.3); split.impulse=0; KiwiDestructionDefinition.edit(editor.model,beam,{"split":split}); await seek(.6)
	check(editor.physics.structure.edges.size()==1 and str(editor.physics.structure.edges[0].b.id).contains(":fragment:"),"A valid material attachment is remapped onto its surviving fractured piece")
	var bounds:={support.id:AABB(Vector3.ZERO,Vector3.ONE),beam.id:AABB(Vector3(1.04,0,0),Vector3.ONE)}; var proposals:=KiwiStructure.candidates([support,beam],bounds,.05)
	check(proposals.size()==1,"Nearby-boundary generation produces reviewable candidates at the chosen tolerance")
	reset(); var first_floor:=add(Vector3(0,2.5,0),0,8,Vector3(4,.3,2)); var upper_column:=add(Vector3(0,3.5,0),0,1,Vector3(.3,2,.3)); var upper_floor:=add(Vector3(0,4.6,0),0,5,Vector3(4,.3,2)); joint(first_floor,upper_column,Vector3(0,2.8,0)); joint(upper_column,upper_floor,Vector3(0,4.3,0))
	var left:=add(Vector3(-1.5,1.2,0),1); var right:=add(Vector3(1.5,1.2,0),1); left.values.physics.collision=false; right.values.physics.collision=false
	var left_id:=joint(left,first_floor,Vector3(-1.5,2.4,0),80); var right_id:=joint(right,first_floor,Vector3(1.5,2.4,0),80); left.values.structure_connections[left_id].break_at=.5
	await seek(.4); var standing: bool=state(first_floor).pose.origin.y>2.45 and state(upper_floor).pose.origin.y>4.5; print("BUILDING before ",state(first_floor).pose.origin," ",state(upper_floor).pose.origin," joints ",state(left).structural.links[left_id]," ",state(right).structural.links[right_id]); await seek(1.5); print("BUILDING after ",state(first_floor).pose.origin," ",state(upper_floor).pose.origin," joints ",state(right).structural.links[right_id])
	check(standing and state(right).structural.links[right_id].broken and state(first_floor).pose.origin.y<2 and state(upper_floor).pose.origin.y<4,"A two-floor assembly stays supported, then progressively falls as a directed support break overloads its other support")
	editor.physics.dispose(); editor.model.history.clear_history(); editor.queue_free(); view.queue_free(); await process_frame
	print("STRUCTURAL CONSTRAINTS: %d checks, %d failures"%[checks,failures]); quit(failures)
