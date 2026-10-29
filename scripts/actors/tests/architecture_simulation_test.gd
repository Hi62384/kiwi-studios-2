extends "res://scripts/actors/tests/surface_growth_test.gd"
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
var editor: ActorTimelineEditor
func seek(time: float) -> void:
	editor.canvas.playhead=time; editor._evaluate_runtimes()
	while editor.physics.pending: await process_frame; editor._evaluate_runtimes()
func run() -> void:
	var source: Resource=Source.rectangular(6,8,2); source.physics_enabled=true; source.stairs.append({"id":"main","from":"floor0","to":"floor1","type":0,"position":Vector2(-1,-2),"width":1.,"length":4.,"steps":18}); var output:=Builder.generate(source); check(output.errors.is_empty(),"Physics-ready building and its connected staircase keep valid authored geometry")
	var path:="user://physics_building.res"; ResourceSaver.save(output.document,path); editor=ActorTimelineEditor.new(); root.add_child(editor); var viewport:=SubViewport.new(); viewport.size=Vector2i(400,300); root.add_child(viewport); editor.runtime_holder=Node3D.new(); viewport.add_child(editor.runtime_holder)
	var clip:=editor.model.instantiate_model(output.document,path,0.); check(clip!=null,"Physics-ready building instantiates through normal scene hierarchy")
	await seek(0.); var compounds:=0; var containers:=0
	for actor: ActorData in editor.model.actors:
		if editor.physics.world.bodies.has(actor.id) and editor.physics.world.bodies[actor.id].has("compound"): compounds+=1
		if actor.type_id==&"point_3d" and editor.physics.prototypes.has(actor.id): containers+=1
	check(compounds>5 and containers==0,"Actual timeline setup uses compound bodies and excludes empty hierarchy containers")
	await seek(.5); var states: Dictionary={}; var finite:=true; var stable:=true
	for id: String in editor.physics.display_states:
		var pose: Transform3D=editor.physics.display_states[id].pose; states[id]=pose; finite=finite and pose.origin.is_finite() and pose.basis.is_finite(); stable=stable and pose.origin.distance_to(editor.physics.animated_world(id,.5).origin)<.4
	check(finite and stable,"Supported building remains finite and near its authored assembly under gravity")
	await seek(0.); await seek(.5); var same:=true
	for id: String in states: same=same and (editor.physics.display_states[id].pose as Transform3D).is_equal_approx(states[id])
	check(same,"Compound structure simulation rewinds deterministically")
	editor.physics.dispose(); editor.model.history.clear_history(); editor.queue_free(); viewport.queue_free(); await process_frame; print("ARCHITECTURE SIMULATION: %d checks, %d failures"%[checks,failures]); quit(failures)
