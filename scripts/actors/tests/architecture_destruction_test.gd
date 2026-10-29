extends "res://scripts/actors/tests/destruction_timeline_test.gd"
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
func run() -> void:
	var source: Resource=Source.rectangular(6,8,1); source.physics_enabled=true; var generated:=Builder.generate(source); var path:="user://destructible_architecture.res"; ResourceSaver.save(generated.document,path)
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); view.size=Vector2i(400,300); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder); editor.model.instantiate_model(generated.document,path,0.)
	var wall: ActorData; var door: ActorData
	for actor: ActorData in editor.model.actors:
		if actor.values.get(&"model_component_id","")==source.source_id+":floor0:wall:wall0": wall=actor
		if actor.values.get(&"model_component_id","")==source.source_id+":floor0:opening:door0:leaf": door=actor
	check(wall!=null and door!=null,"Generated structural components remain individually addressable actors")
	if wall==null or door==null: editor.queue_free(); view.queue_free(); quit(1); return
	var wall_id:=wall.id; var connection: Dictionary=door.values[&"structure_connections"].duplicate(true); wall.values[&"destruction_enabled"]=true; wall.values.physics={"enabled":true,"gravity":0.,"collision":false}; var operation:=KiwiDestructionDefinition.operation(0,.2); operation.position=Vector3(1.,1.2,0.); operation.direction=Vector3.RIGHT; operation.impulse=0.; KiwiDestructionDefinition.edit(editor.model,wall,{"cut":operation})
	await seek(.1); check(not state(wall).get("destruction_detached",false),"Architecture fracture respects its authored timeline time")
	var polygon: KiwiModelMesh=editor.physics.destruction.source(editor.physics,wall.id,state(wall)).get("mesh"); var cells:=KiwiDestructionGeometry._solid_islands(polygon)
	print("WALL CELLS ",cells.map(func(cell: KiwiModelMesh): return [cell.vertices.size(),KiwiDestructionGeometry.closed(cell),KiwiModelGeometry.convex(cell)])," capture ",editor.physics.prototypes[wall.id].geometry.meshes.map(func(item: Dictionary): return item.has("polygon")))
	await seek(.35); var fragments: Array=state(wall).get("destruction_fragments",[]); var valid:=fragments.size()>=2
	print("ARCHITECTURE FRACTURE ",state(wall).get("destruction_error","")," fragments=",fragments.size()," source=",editor.physics.destruction.source(editor.physics,wall.id,state(wall)).get("error",""))
	for fragment: Dictionary in fragments: valid=valid and fragment.mesh is KiwiModelMesh and not fragment.mesh.vertices.is_empty() and (fragment.pose as Transform3D).origin.is_finite()
	check(valid,"Existing destruction engine fractures actual generated wall geometry")
	var source_data:=editor.physics.destruction.source(editor.physics,wall.id,state(wall)); var cut_result:=KiwiDestructionGeometry.evaluate(source_data.mesh,{"cut":operation},source_data.materials.size()); var doorway_clear: bool=str(cut_result.get("error","")).is_empty()
	for section: KiwiModelMesh in cut_result.get("parts",[]):
		var contains:=true
		for face in section.faces.size():
			var normal:=section.normal(face)
			if normal.dot(Vector3(3.,1.,0.)-section.center(face))>.0001: contains=false; break
		if contains: doorway_clear=false
	check(doorway_clear,"Fracturing wall sections preserves the real doorway opening")
	check(wall.id==wall_id and door.values[&"structure_connections"]==connection and door.parent_id==wall.id,"Fracture preserves source component identity and linked hinge metadata")
	var poses: Array=[]
	for fragment: Dictionary in fragments: poses.append(fragment.pose)
	await seek(0.); await seek(.35); var replay: Array=state(wall).get("destruction_fragments",[]); var same:=replay.size()==poses.size()
	for index in mini(replay.size(),poses.size()): same=same and (replay[index].pose as Transform3D).is_equal_approx(poses[index])
	check(same,"Generated architecture fracture rewinds deterministically")
	var scene:=editor.capture_scene_data(); var saved:=ResourceSaver.save(scene,"user://architecture_destruction_scene.res"); var loaded:=ResourceLoader.load("user://architecture_destruction_scene.res","",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData; var restored:=false
	for actor: ActorData in loaded.actors: if actor.id==wall_id: restored=actor.values.get(&"destruction_operations",{}).has("cut") and actor.values.get(&"mesh_path","")==path
	check(saved==OK and restored,"Scene save/reload preserves linked architectural source and editable destruction setup")
	editor.physics.dispose(); editor.model.history.clear_history(); editor.queue_free(); view.queue_free(); await process_frame; print("ARCHITECTURE DESTRUCTION: %d checks, %d failures"%[checks,failures]); quit(failures)
