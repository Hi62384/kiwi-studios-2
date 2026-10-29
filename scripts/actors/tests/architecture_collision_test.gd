extends "res://scripts/actors/tests/surface_growth_test.gd"
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
func runtime_for(document: KiwiModelDocument,id: String,registry: ActorRegistry) -> ActorRuntime:
	var actor:=registry.get_definition(&"basic_mesh").create_actor(); actor.set_value(&"mesh_path",document); actor.values[&"model_component_id"]=id; var runtime:=registry.get_definition(&"basic_mesh").create_runtime(actor); root.add_child(runtime); runtime.evaluate_clip(ActorClip.create(actor),0.); return runtime
func run() -> void:
	var source: Resource=Source.rectangular(6,8,2); source.floors[1].cuts=[Rect2(-.6,-1.,1.2,2.)]; var result:=Builder.generate(source); var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var wall_id: String=source.source_id+":floor0:wall:wall0"; var runtime:=runtime_for(result.document,wall_id,registry); var geometry:=KiwiPhysicsGeometry.capture(runtime,{}); var settings:=KiwiPhysicsSettings.DEFAULTS.duplicate(true); var collider:=KiwiPhysicsGeometry.collider(geometry,settings)
	check(collider.has("compound") and collider.compound.size()>1,"Automatic architectural collision uses existing compound shapes instead of a filled bounding box")
	var world:=KiwiPhysicsCollisionWorld.new(); world.add_compound("wall",collider.compound,1,1); world.place("wall",Transform3D.IDENTITY)
	var through:=world.point_motion("probe",Vector3(3,1,-1),Vector3(3,1,1),.12,1,1,[]); var blocked:=world.point_motion("probe",Vector3(1,1,-1),Vector3(1,1,1),.12,1,1,[])
	check(through.hits.is_empty() and through.position.distance_to(Vector3(3,1,-1))>1.9,"Native collision sweep passes through the door opening")
	check(not blocked.hits.is_empty() and blocked.position.distance_to(Vector3(1,1,-1))<1.1,"Native collision sweep is blocked by adjacent solid wall")
	var pose:=Transform3D(Basis(Vector3.UP,.7),Vector3(2,0,3)); world.place("wall",pose); var moved:=world.point_motion("probe",pose*Vector3(3,1,-1),pose*Vector3(3,1,1),.12,1,1,[])
	check(moved.hits.is_empty(),"Compound openings remain correct after rotating and moving the building")
	var slab_runtime:=runtime_for(result.document,source.source_id+":floor1:slab",registry); var slab:=KiwiPhysicsGeometry.collider(KiwiPhysicsGeometry.capture(slab_runtime,{}),settings); world.add_compound("slab",slab.compound,1,1); world.place("slab",Transform3D.IDENTITY); var shaft:=world.point_motion("probe",Vector3(0,1,0),Vector3(0,-1,0),.1,1,1,[]); var floor:=world.point_motion("probe",Vector3(2,1,0),Vector3(2,-1,0),.1,1,1,[])
	check(shaft.hits.is_empty() and not floor.hits.is_empty(),"Convex floor cells preserve actual stairwell shafts in native collision")
	world.reset(); runtime.queue_free(); slab_runtime.queue_free(); await process_frame; print("ARCHITECTURE COLLISION: %d checks, %d failures"%[checks,failures]); quit(failures)
