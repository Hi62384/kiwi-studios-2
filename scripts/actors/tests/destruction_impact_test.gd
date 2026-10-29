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
func add(values: Dictionary) -> ActorData:
	var clip:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0,values); clip.start_time=0; clip.duration=4; clip.layer=editor.model.clips.size()-1; return editor.model.selected_actor()
func state(actor: ActorData) -> Dictionary: return editor.physics.display_states[actor.id]
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var floor_actor:=add({&"position":Vector3(0,-.1,0),&"box_size":Vector3(20,.2,20)}); floor_actor.values.physics={"enabled":true,"body_mode":1,"bounce":0.0}
	var glass:=add({&"position":Vector3(-1,1.2,0),&"box_size":Vector3.ONE*.4,&"destruction_enabled":true,&"destruction_mode":1,&"destruction_material":ActorObjectReference.from_object(KiwiDestructionMaterial.preset(0))}); glass.values.physics={"enabled":true,"mass":1.0,"bounce":0.0}
	var metal:=add({&"position":Vector3(1,1.2,0),&"box_size":Vector3.ONE*.4,&"destruction_enabled":true,&"destruction_mode":1,&"destruction_material":ActorObjectReference.from_object(KiwiDestructionMaterial.preset(1))}); metal.values.physics={"enabled":true,"mass":1.0,"bounce":0.0}
	editor.model.changed.emit(); await seek(.8)
	print("GLASS damage=",state(glass).get("destruction_damage_cells",{})," error=",state(glass).get("destruction_error","")," fragments=",state(glass).get("destruction_fragments",[]).size())
	print("METAL damage=",state(metal).get("destruction_damage_cells",{})," error=",state(metal).get("destruction_error",""))
	check(state(glass).get("destruction_detached",false) and state(glass).destruction_fragments.size()>2,"An actual rigid-body impact shatters a glass material into real pieces")
	check(not state(metal).get("destruction_detached",false) and state(metal).has("destruction_geometry"),"The same drop dents steel instead of shattering it")
	check(not state(glass).get("destruction_damage_cells",{}).is_empty() and not state(metal).get("destruction_damage_cells",{}).is_empty(),"Collision energy and contact location drive spatially local material damage")
	var saved: Dictionary=editor.physics._snapshot({glass.id:state(glass)})[glass.id]; await seek(.1); await seek(.8)
	check(state(glass).destruction_fragments[0].pose==saved.destruction_fragments[0].pose and state(glass).destruction_damage_cells==saved.destruction_damage_cells,"Material-dependent impact damage and fragments replay deterministically")
	var generation:=editor.physics.generation; var object:=ActorAnimation.resolve_reference(glass.values.destruction_material); object.set_value(&"interior",null); editor.model.changed.emit(); await seek(.8)
	check(editor.physics.generation==generation,"Interior appearance association does not invalidate damage simulation")
	object.set_value(&"strength",1000.); editor.model.changed.emit(); await seek(.8)
	check(editor.physics.generation>generation and not state(glass).get("destruction_detached",false),"Editing material strength recomputes actual collision failure")
	var manual:=add({&"position":Vector3(5,2,0),&"destruction_enabled":true}); var op:=KiwiDestructionDefinition.operation(0,.1); KiwiDestructionDefinition.edit(editor.model,manual,{"cut":op}); await seek(.3)
	check(state(manual).get("destruction_detached",false),"Manual destruction works without enabling an unrelated rigid-body simulation toggle")
	editor.physics.dispose(); editor.model.history.clear_history(); editor.queue_free(); view.queue_free(); await process_frame
	print("DESTRUCTION IMPACTS: %d checks, %d failures"%[checks,failures]); quit(failures)
