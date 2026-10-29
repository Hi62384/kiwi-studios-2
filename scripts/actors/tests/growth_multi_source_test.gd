extends "res://scripts/actors/tests/destruction_timeline_test.gd"
func run() -> void:
	var session:=KiwiModelSession.new(); session.add("Plane",{"size":Vector3.ONE}); KiwiSurfaceGrowth.add(session,0); session.primary().title="Hair test"; session.primary().growth.settings.density=12.
	var feather:=session.primary().copy_component(true); feather.id=ActorData.new_id(); feather.title="Feather test"; feather.growth.settings.type=2; feather.growth.settings.length=.5; feather.growth.settings.width=.12; feather.growth.revision+=1; session.document.components.append(feather); session.document.prepare_growth()
	var path:="user://growth multi-source.tres"; ResourceSaver.save(session.document,path)
	editor=ActorTimelineEditor.new(); root.add_child(editor); var viewport:=SubViewport.new(); viewport.own_world_3d=true; viewport.size=Vector2i(640,400); root.add_child(viewport); editor.runtime_holder=Node3D.new(); viewport.add_child(editor.runtime_holder)
	editor.model.create_actor(editor.registry.get_definition(&"basic_mesh"),0,{&"mesh_path":path}); editor.model.create_actor(editor.registry.get_definition(&"basic_mesh"),0,{&"mesh_path":path}); await process_frame; await process_frame
	var growth: Array[ActorData]=[]
	for actor: ActorData in editor.model.actors:
		if actor.values.get(&"is_surface_growth",false): growth.append(actor)
	check(growth.size()==4,"Two imported models retain separate hair and feather actor ownership")
	if growth.size()!=4: quit(1); return
	for index in growth.size():
		var actor:=growth[index]; actor.values.physics={"enabled":true,"gravity":1.,"wind":Vector3(float(index),0,0),"collision":false,"particles":4,"recovery":5.,"radius":.01}
		var parent_actor:=editor.model.actor_for_id(actor.parent_id); var key:=PackedStringArray(["position"]); editor.model.playhead_time=0.; editor.model.add_keyframe(parent_actor,key,"Source position",Vector3(index*2,0,0)); editor.model.playhead_time=1.; editor.model.add_keyframe(parent_actor,key,"Source position",Vector3(index*2,0,1.+index))
	editor.physics.mark_dirty(); await seek(.5); var sampled: Dictionary={}; var attached:=true; var independent:=true
	for actor in growth:
		sampled[actor.id]=state(actor).points.duplicate(); var pins:=KiwiGrowthPhysics.pins(editor.physics,actor.id,.5)
		for index: int in pins: attached=attached and state(actor).points[index].is_equal_approx(pins[index])
	for i in range(1,growth.size()): independent=independent and sampled[growth[i].id]!=sampled[growth[0].id]
	check(attached,"All hair and feather guide roots follow their own animated source")
	check(independent,"Separate source animation and forces produce independent guide states")
	var error:=await editor.physics.bake_group(editor,0,1,30); check(error.is_empty(),"Multiple hair and feather actors bake as one deterministic scene group")
	var same:=true
	for actor in growth: same=same and actor.values.physics.bake.cache.frame(15)[actor.id].points==sampled[actor.id]
	check(same,"Baked hair and feather guide samples reproduce their corresponding live source motion")
	await seek(.1); await seek(.5); same=true
	for actor in growth: same=same and state(actor).points==sampled[actor.id]
	check(same,"Backward seeks do not cross-contaminate separate models or feather simulations")
	editor.physics.dispose(); editor.queue_free(); viewport.queue_free(); await process_frame; DirAccess.remove_absolute(path); print("MULTI-SOURCE GROWTH: %d checks, %d failures"%[checks,failures]); quit(failures)
