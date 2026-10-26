extends SceneTree
## Scene assignment, serialization and undo checks. GPU appearance is exercised
## separately by natural_material_scene_render_test.gd.

const NaturalEngine = preload("res://scripts/materials/natural_material_engine.gd")
var failures := 0
var checks := 0


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var registry := ActorRegistry.new()
	check(BasicActors.register_all(registry), "Catalog registers with Natural Material")
	var definition := registry.get_object_definition(&"natural_material")
	check(definition != null and definition.base_type == &"material", "Natural Material extends surface material compatibility")
	check(registry.object_definitions_for(&"material").size() == 3, "Surface slots offer all three material types")
	var object := definition.create_object()
	var original := NaturalEngine.defaults("wood/oak")
	original.parameters.seed = 631
	original.rotation = 23.0
	original.texture_size = 77.0
	original.relief = 0.4
	object.set_value(&"material_settings", original)
	var reference := ActorObjectReference.from_object(object)
	for type_id: StringName in [&"basic_shape", &"basic_mesh", &"image_3d"]:
		var actor_definition := registry.get_definition(type_id)
		check(actor_definition.find_property(&"material").accepts(reference), str(type_id) + " accepts Natural Material")
		var actor := actor_definition.create_actor()
		if type_id == &"basic_mesh":
			actor.set_value(&"mesh_path", BoxMesh.new())
		actor.set_value(&"material", reference)
		var runtime := actor_definition.create_runtime(actor)
		root.add_child(runtime)
		runtime.evaluate_clip(ActorClip.create(actor), 0.0)
		var mesh: MeshInstance3D
		for candidate in runtime.find_children("*", "MeshInstance3D", true, false):
			mesh = candidate
			break
		check(mesh != null and mesh.material_override is ShaderMaterial, str(type_id) + " renders Natural Material")
		if mesh != null:
			var material := mesh.material_override as ShaderMaterial
			check(material.shader != null, "Natural Material has its actual spatial shader")
			check(is_equal_approx(float(material.get_shader_parameter("texture_size")), 77.0), "Texture size reaches the spatial renderer independently of actor geometry")
			check(is_equal_approx(float(material.get_shader_parameter("angle")), deg_to_rad(23.0)), "Texture rotation reaches the spatial renderer")
			check(is_equal_approx(float(material.get_shader_parameter("relief")), 0.4), "Height-derived relief is configured on the spatial renderer")
			runtime.evaluate_clip(ActorClip.create(actor), 0.2)
			check(mesh.material_override == material, "Unchanged frames reuse the material allocation")
			var updated := original.duplicate(true)
			updated.parameters.primary = Color("2b4d66")
			updated.parameters.roughness = 0.27
			updated.mapping = "triplanar"
			updated.metallic = 0.6
			object.set_value(&"material_settings", updated)
			runtime.evaluate_clip(ActorClip.create(actor), 0.4)
			check(mesh.material_override == material, "Parameter edits update the reusable GPU material in place")
			check(runtime.get("_natural_settings") == updated, "Runtime consumes current shared parameters")
			check(material.get_shader_parameter("primary") == updated.parameters.primary, "Edited color reaches the actual shared shader")
			check(material.get_shader_parameter("triplanar") == true, "Triplanar projection can be changed live")
			check(is_equal_approx(float(material.get_shader_parameter("roughness")), 0.27), "Surface roughness updates live")
			check(is_equal_approx(float(material.get_shader_parameter("metallic_override")), 0.6), "Metallic override updates live")
			object.set_value(&"material_settings", original)
			actor.set_value(&"material", ActorObjectReference.from_object(registry.get_object_definition(&"material").create_object()))
			runtime.evaluate_clip(ActorClip.create(actor), 0.6)
			check(mesh.material_override is StandardMaterial3D, "Switching back preserves standard Material behavior")
			actor.set_value(&"material", ActorObjectReference.from_object(registry.get_object_definition(&"shader_material").create_object()))
			runtime.evaluate_clip(ActorClip.create(actor), 0.8)
			check(mesh.material_override is ShaderMaterial and mesh.material_override != material, "ShaderMaterial remains independently available")
		runtime.free()
	for type_id: StringName in [&"camera_3d", &"fog_volume"]:
		check(not registry.get_definition(type_id).find_property(&"material").accepts(reference), str(type_id) + " rejects incompatible surface materials")
	check(not registry.get_object_definition(&"environment").find_property(&"sky_material").accepts(reference), "Sky slot rejects Natural Material")
	var copied := reference.make_unique()
	var changed := NaturalEngine.defaults("fabric/denim")
	copied.embedded.set_value(&"material_settings", changed)
	check(object.get_value(&"material_settings") == original, "Unique material instances do not mutate the source")
	check(NaturalEngine.settings_from_material(NaturalEngine.material_from_settings(original)) == NaturalEngine.normalize(original), "Image and scene settings round trip through one shared resource")
	var path := "user://natural_material_scene_test.tres"
	var scene := ActorSceneData.new()
	var saved_actor := registry.get_definition(&"basic_shape").create_actor()
	saved_actor.set_value(&"material", reference)
	scene.actors.append(saved_actor)
	check(ResourceSaver.save(scene, path) == OK, "Save scene with embedded Natural Material")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	check(loaded != null, "Reload scene with Natural Material")
	if loaded != null:
		var saved_ref := loaded.actors[0].get_value(&"material") as ActorObjectReference
		check(saved_ref.resolve().get_value(&"material_settings") == original, "Seed, colors, mapping and structure survive scene reload")
	DirAccess.remove_absolute(path)
	var material_path := "user://natural_material_asset_test.tres"
	check(ResourceSaver.save(object, material_path) == OK, "Natural Material can be saved as reusable actor resource")
	var linked := ActorObjectReference.from_asset(material_path, &"natural_material")
	check(linked.resolve(func(id: String): return load(id)) != null, "Asset references resolve Natural Material correctly")
	DirAccess.remove_absolute(material_path)
	var model := ActorTimeline.new()
	var actor_definition := registry.get_definition(&"basic_shape")
	model.create_actor(actor_definition, 0.0)
	var active := model.selected_actor()
	model.edit_property(active, actor_definition, &"material", reference)
	# edit_property makes an owned copy of the reference.
	var active_object := (active.get_value(&"material") as ActorObjectReference).embedded
	model.edit_object_property(active, active_object, definition, &"material_settings", changed)
	check(active_object.get_value(&"material_settings") == changed, "Material parameter edits commit to the active actor")
	model.undo()
	check(active_object.get_value(&"material_settings") == original, "Undo restores exact material settings")
	model.redo()
	check(active_object.get_value(&"material_settings") == changed, "Redo restores the edited material")
	var inspector := ActorInspector.new()
	root.add_child(inspector)
	inspector.setup(model, registry)
	var editor := inspector.find_child("NaturalMaterialEditor", true, false)
	check(editor != null, "Inspector exposes the shared Natural Material editor")
	if editor != null:
		check(editor.find_child("natural_material_browse", true, false) != null, "Shared material browser is directly accessible")
		var preview := editor.find_child("NaturalMaterialPreview", true, false) as ColorRect
		check(preview != null and preview.material is ShaderMaterial, "Inspector swatch evaluates the real procedural shader")
		editor._change("mapping", "triplanar")
		check(active_object.get_value(&"material_settings").mapping == "triplanar", "Surface changes preview immediately")
		editor._finish_edit()
		model.undo()
		check(active_object.get_value(&"material_settings").get("mapping", "uv") == "uv", "Continuous material preview commits one undoable edit")
		model.redo()
		check(active_object.get_value(&"material_settings").mapping == "triplanar", "Redo restores live surface settings")
	inspector.free()
	model.history.clear_history()
	print("NATURAL_MATERIAL_SCENE_TEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
