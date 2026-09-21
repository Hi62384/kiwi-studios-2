extends SceneTree

var failures: int = 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var registry := ActorRegistry.new()
	check(BasicActors.register_all(registry), "Register example actor")
	check(not BasicActors.register_all(registry), "Reject duplicate type")
	var definition := registry.get_definition(&"point_3d")
	var actor := definition.create_actor()
	check(not actor.id.is_empty(), "Assign actor ID")
	check(not definition.set_property_value(actor, &"position", 3), "Reject wrong value type")
	check(definition.set_property_value(actor, &"position", Vector3(2, 0, 0)), "Set typed value")
	var material_type := ActorObjectDefinition.new()
	material_type.type_id = &"material"
	material_type.properties = [ActorProperty.create(&"color", "Color", Color.WHITE)]
	var material := material_type.create_object()
	actor.set_value(&"material", ActorObjectReference.from_object(material))
	actor.set_value(&"shared", ActorObjectReference.from_asset("asset-1", &"material"))
	var copied := actor.copy_actor()
	check(copied.id != actor.id, "Independent copy gets new ID")
	var copied_material: ActorObjectData = copied.values[&"material"].resolve()
	copied_material.set_value(&"color", Color.RED)
	check(material.values[&"color"] == Color.WHITE, "Embedded copy is independent")
	var shared: ActorObjectReference = copied.values[&"shared"]
	check(shared.asset_id == "asset-1", "Copy retains asset identity")
	check(shared.resolve() == null, "Missing resolver keeps missing reference")
	var resolver := func(_id: String) -> ActorObjectData: return material
	check(shared.resolve(resolver) == material, "Resolve shared object")
	check(shared.make_unique(resolver).embedded != material, "Make unique copies shared object")
	var save_path := "user://actor_smoke_" + ActorData.new_id() + ".tres"
	check(ResourceSaver.save(actor, save_path) == OK, "Save actor")
	var loaded := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorData
	check(loaded != null and loaded.id == actor.id, "Load actor identity")
	if loaded != null:
		check(loaded.values[&"material"].embedded.values[&"color"] == Color.WHITE, "Load embedded data")
	DirAccess.remove_absolute(save_path)
	var clip := ActorClip.create(actor, 10.0, 5.0)
	clip.source_offset = 2.0
	clip.playback_speed = 2.0
	check(clip.local_time(11.0) == 4.0, "Map absolute time to source time")
	check(clip.contains_time(10.0) and not clip.contains_time(15.0), "Half-open clip interval")
	var runtime := definition.create_runtime(actor)
	root.add_child(runtime)
	runtime.evaluate_clip(clip, 11.0, {&"position": Vector3(8, 0, 0)})
	check(runtime.get_node("Transform").position == Vector3(8, 0, 0), "Apply evaluated override")
	check(actor.values[&"position"] == Vector3(2, 0, 0), "Evaluation preserves saved values")
	runtime.evaluate_clip(clip, 10.0)
	check(runtime.get_node("Transform").position == Vector3(2, 0, 0), "Backward seek resets sampled value")
	runtime.evaluate_clip(clip, 15.0)
	check(not runtime.get_node("Transform").visible, "Deactivate outside clip")
	runtime.free()
	print("Actor smoke check: ", failures, " failures")
	quit(1 if failures else 0)
