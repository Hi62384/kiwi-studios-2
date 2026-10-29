extends "res://scripts/actors/tests/surface_growth_test.gd"
const Field=preload("res://scripts/actors/fog/fog_field.gd")
const Boundary=preload("res://scripts/actors/fog/fog_mesh.gd")
func run() -> void:
	var box:=BoxMesh.new(); var path:="user://fog-boundary.tres"; ResourceSaver.save(box,path)
	var result:=Boundary.prepare(path); check(str(result.error).is_empty() and result.texture!=null,"Closed triangle mesh prepares a real interior volume")
	if result.get("texture")!=null:
		var slices: Array[Image]=result.slices; check(slices.size()==32 and slices[16].get_pixel(16,16).r>.9,"Interior sampling fills the closed mesh rather than only its surface")
		check(Boundary.prepare(path).texture==result.texture,"Unchanged mesh boundary reuses cached occupancy")
	print("FOG MESH prepare_ms=",result.get("milliseconds",0.)); DirAccess.remove_absolute(path)
	var plane:=PlaneMesh.new(); ResourceSaver.save(plane,path); result=Boundary.prepare(path)
	check(not str(result.error).is_empty() and result.get("texture")==null,"Open or degenerate mesh gives an actionable validation error and no misleading fog shell"); DirAccess.remove_absolute(path)
	var valid_shapes:=true
	for kind in 6: valid_shapes=valid_shapes and Field.shape_distance(Vector3.ZERO,Vector3.ONE,kind)<0. and Field.shape_distance(Vector3.ONE*2.,Vector3.ONE,kind)>0.
	check(valid_shapes,"All six primitive masks have valid interior and exterior distance values")
	check(Field.combine(0.,1.,2,1.)==1. and Field.combine(1.,0.,3,1.)==0. and Field.combine(1.,1.,4,1.)==0.,"Maximum, minimum and subtraction compose field occupancy predictably")
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var definition:=registry.get_definition(&"fog_volume"); var model:=ActorTimeline.new(); var clip:=model.create_actor(definition,0.); var actor:=model.actor_for_id(clip.actor_id)
	var object:=Field.definition().create_object(); actor.values[&"field"]=ActorObjectReference.from_object(object)
	var host:=ActorInspector.new(); host.model=model; host.registry=registry; root.add_child(host)
	var painter:=preload("res://scripts/actors/fog/fog_painter.gd").new(); root.add_child(painter); painter.setup(host,actor,object,Field.definition()); painter.size=Vector2i(620,620); painter.show(); await process_frame
	painter.painting=true; painter.before={}; painter.dab(painter.view.size*.5); painter.commit(); var voxels: Dictionary=object.get_value(&"paint",{}); var count:=voxels.size()
	check(count>10,"A brush dab changes a three-dimensional sphere of voxel density")
	model.history.undo(); check((object.get_value(&"paint",{}) as Dictionary).is_empty(),"One complete density stroke undoes atomically")
	model.history.redo(); check((object.get_value(&"paint",{}) as Dictionary).size()==count,"Density stroke redoes")
	painter.painting=true; painter.before=voxels.duplicate(); painter.last=Vector2.INF; painter.dab(painter.view.size*.25); var event:=InputEventKey.new(); event.pressed=true; event.keycode=KEY_ESCAPE; painter._unhandled_key_input(event)
	check(object.get_value(&"paint",{})==voxels,"Escape cancels a density stroke without committing it")
	painter.queue_free(); host.queue_free(); model.history.clear_history(); await process_frame; print("FOG FIELDS: %d checks, %d failures"%[checks,failures]); quit(failures)
