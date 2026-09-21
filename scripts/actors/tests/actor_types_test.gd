extends SceneTree

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var registry := ActorRegistry.new()
	BasicActors.register_all(registry)
	check(registry.get_definition(&"cube") == null and registry.get_definition(&"sphere") == null,
		"Standalone Cube and Sphere actors are removed")
	var shape_definition := registry.get_definition(&"basic_shape")
	var mesh_definition := registry.get_definition(&"basic_mesh")
	var light_definition := registry.get_definition(&"light_3d")
	var world_definition := registry.get_definition(&"world_environment")
	var environment_definition := registry.get_object_definition(&"environment")
	check(shape_definition != null and mesh_definition != null and light_definition != null and world_definition != null,
		"Shape, mesh, light, and world actor definitions are registered")
	check(environment_definition != null and world_definition.properties.size() == 1
		and world_definition.find_property(&"environment").object_type == &"environment",
		"World Environment stores its settings in one Environment object")
	var environment_groups: Array[String] = []
	for property: ActorProperty in environment_definition.properties:
		var group := str(property.options.get("group", ""))
		if not environment_groups.has(group):
			environment_groups.append(group)
	for required_group in ["Background", "Ambient Light", "Reflected Light", "Tonemap", "SSR", "SSIL", "SDFGI", "Glow", "Fog", "Volumetric Fog", "Adjustments"]:
		check(environment_groups.has(required_group), "Environment includes " + required_group + " settings")
	check(shape_definition.find_property(&"shape").options.choices.size() == 8,
		"Basic Shape exposes all supported primitive choices")

	var shape_actor := shape_definition.create_actor()
	var material_definition := registry.get_object_definition(&"material")
	var red_material := material_definition.create_object()
	red_material.set_value(&"tint", Color.RED)
	var noise_albedo := registry.get_object_definition(&"noise_image").create_object()
	red_material.set_value(&"albedo_map", ActorObjectReference.from_object(noise_albedo))
	red_material.set_value(&"uv_triplanar", true)
	red_material.set_value(&"uv_world_triplanar", true)
	shape_actor.set_value(&"material", ActorObjectReference.from_object(red_material))
	var shape_runtime := shape_definition.create_runtime(shape_actor)
	root.add_child(shape_runtime)
	var shape_clip := ActorClip.create(shape_actor)
	shape_runtime.evaluate_clip(shape_clip, 0.0)
	var shape_mesh := shape_runtime.content as MeshInstance3D
	check(shape_mesh.mesh is BoxMesh and (shape_mesh.material_override as StandardMaterial3D).albedo_color == Color.RED
		and (shape_mesh.material_override as StandardMaterial3D).albedo_texture != null,
		"Basic Shape applies Material tint and procedural Albedo map")
	var shape_material := shape_mesh.material_override as StandardMaterial3D
	check(shape_material.uv1_triplanar and shape_material.uv1_world_triplanar,
		"Material applies triplanar and world-triplanar UV settings")
	check(shape_material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED
		and shape_material.cull_mode == BaseMaterial3D.CULL_BACK
		and shape_material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL,
		"Solid primitives use opaque front-face rendering with normal lighting")
	shape_actor.set_value(&"shape", 1)
	shape_runtime.evaluate_clip(shape_clip, 0.0)
	check(shape_mesh.mesh is SphereMesh, "Basic Shape switches primitive meshes")
	shape_actor.set_value(&"shape", 2)
	shape_actor.set_value(&"cylinder_radial_segments", 12)
	shape_actor.set_value(&"cylinder_rings", 3)
	shape_actor.set_value(&"cylinder_cap_top", false)
	shape_actor.set_value(&"cylinder_cap_bottom", true)
	shape_runtime.evaluate_clip(shape_clip, 0.0)
	var cylinder := shape_mesh.mesh as CylinderMesh
	check(cylinder != null and cylinder.radial_segments == 12 and cylinder.rings == 3
		and not cylinder.cap_top and cylinder.cap_bottom,
		"Basic Shape applies native per-shape segment and cap properties")

	var mesh_actor := mesh_definition.create_actor({&"mesh_path": BoxMesh.new()})
	var mesh_runtime := mesh_definition.create_runtime(mesh_actor)
	root.add_child(mesh_runtime)
	mesh_runtime.evaluate_clip(ActorClip.create(mesh_actor), 0.0)
	check(mesh_runtime.content.find_children("*", "MeshInstance3D", true, false).size() == 1,
		"Basic Mesh displays an embedded Mesh resource")
	var saved_mesh_path := "user://basic_mesh_actor_test.tres"
	ResourceSaver.save(SphereMesh.new(), saved_mesh_path)
	mesh_actor.set_value(&"mesh_path", ProjectSettings.globalize_path(saved_mesh_path))
	mesh_runtime.evaluate_clip(ActorClip.create(mesh_actor), 0.0)
	var loaded_meshes: Array[Node] = mesh_runtime.content.find_children("*", "MeshInstance3D", true, false)
	check(loaded_meshes.size() == 1 and (loaded_meshes[0] as MeshInstance3D).mesh is SphereMesh,
		"Basic Mesh loads a project filesystem Mesh resource")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved_mesh_path))
	var extensions := PackedStringArray(mesh_definition.find_property(&"mesh_path").options.extensions)
	check(extensions.has("glb") and extensions.has("fbx") and extensions.has("gltf"),
		"Basic Mesh accepts common imported 3D formats")
	var glb_source := Node3D.new()
	var glb_mesh := MeshInstance3D.new()
	glb_mesh.mesh = BoxMesh.new()
	glb_source.add_child(glb_mesh)
	var glb_document := GLTFDocument.new()
	var glb_state := GLTFState.new()
	var glb_path := "user://basic_mesh_actor_test.glb"
	var glb_written := glb_document.append_from_scene(glb_source, glb_state) == OK \
		and glb_document.write_to_filesystem(glb_state, glb_path) == OK
	check(glb_written, "GLB fixture is generated")
	if glb_written:
		mesh_actor.set_value(&"mesh_path", ProjectSettings.globalize_path(glb_path))
		mesh_runtime.evaluate_clip(ActorClip.create(mesh_actor), 0.0)
		check(mesh_runtime.content.find_children("*", "MeshInstance3D", true, false).size() == 1,
			"Basic Mesh loads an absolute GLB model path")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(glb_path))
	glb_source.free()
	var inspector := ActorInspector.new()
	var mesh_property := mesh_definition.find_property(&"mesh_path")
	check(inspector._file_path_allowed(ProjectSettings.globalize_path("res://new_array_mesh.tres"), mesh_property),
		"Mesh picker accepts a Mesh .tres")
	check(not inspector._file_path_allowed(ProjectSettings.globalize_path("res://resources/environments/DefaultEnvironment.tres"), mesh_property)
		and not inspector._file_path_allowed(ProjectSettings.globalize_path("res://resources/StyleBoxes/Default.tres"), mesh_property),
		"Mesh picker rejects non-Mesh .tres resources")
	inspector.free()
	var shape_model := ActorTimeline.new()
	shape_model.create_actor(shape_definition, 0.0)
	var shape_inspector := ActorInspector.new()
	root.add_child(shape_inspector)
	shape_inspector.setup(shape_model, registry, ActorInspectorState.new())
	check(shape_inspector.find_child("box_size_0", true, false) != null
		and shape_inspector.find_child("sphere_radius", true, false) == null,
		"Basic Shape only displays controls for its selected primitive")
	var shape_choice := shape_inspector.find_child("shape_choice", true, false) as OptionButton
	if shape_choice != null:
		shape_choice.item_selected.emit(1)
	await process_frame
	await process_frame
	check(shape_inspector.find_child("box_size_0", true, false) == null
		and shape_inspector.find_child("sphere_radius", true, false) != null,
		"Changing Basic Shape rebuilds the inspector with only the new primitive section")
	shape_inspector.free()

	var light_actor := light_definition.create_actor()
	light_actor.set_value(&"light_type", 1)
	var light_runtime := light_definition.create_runtime(light_actor)
	root.add_child(light_runtime)
	light_runtime.evaluate_clip(ActorClip.create(light_actor), 0.0)
	check(light_runtime.content is OmniLight3D, "3D Light switches between concrete light types")
	var directional_definition := registry.get_definition(&"directional_light")
	var directional_actor := directional_definition.create_actor()
	directional_actor.set_value(&"angular_distance", 1.5)
	directional_actor.set_value(&"shadow_mode", 1)
	directional_actor.set_value(&"shadow_max_distance", 250.0)
	var directional_runtime := directional_definition.create_runtime(directional_actor)
	root.add_child(directional_runtime)
	directional_runtime.evaluate_clip(ActorClip.create(directional_actor), 0.0)
	var directional := directional_runtime.content as DirectionalLight3D
	check(directional != null and is_equal_approx(directional.light_angular_distance, 1.5)
		and directional.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		and is_equal_approx(directional.directional_shadow_max_distance, 250.0),
		"Directional Light applies native angular and cascaded-shadow properties")
	var camera_definition := registry.get_definition(&"camera_3d")
	var canvas_definition := registry.get_object_definition(&"canvas_shader_material")
	check(camera_definition.find_property(&"material").object_type == &"canvas_shader_material",
		"Camera exposes an editable Canvas ShaderMaterial post-process slot")
	var camera_actor := camera_definition.create_actor()
	var camera_material := canvas_definition.create_object()
	var camera_shader := Shader.new()
	camera_shader.code = "shader_type canvas_item;\nuniform vec4 tint : source_color = vec4(1.0);\nvoid fragment() { COLOR = texture(TEXTURE, UV) * tint; }\n"
	camera_material.set_value(&"shader_path", camera_shader)
	camera_material.set_value(&"uniforms", {&"tint": Color.RED})
	camera_actor.set_value(&"material", ActorObjectReference.from_object(camera_material))
	var camera_runtime := camera_definition.create_runtime(camera_actor)
	root.add_child(camera_runtime)
	camera_runtime.evaluate_clip(ActorClip.create(camera_actor), 0.0)
	check(camera_runtime.camera_shader_material != null
		and camera_runtime.camera_shader_material.shader.code.contains("hint_screen_texture")
		and camera_runtime.camera_shader_material.get_shader_parameter(&"tint") == Color.RED
		and camera_runtime.camera_overlay.material == camera_runtime.camera_shader_material,
		"Camera shader samples its rendered frame and applies linked uniforms")
	(camera_runtime.content as Camera3D).make_current()
	camera_runtime.update_camera_overlay()
	check(camera_runtime.camera_overlay.visible, "Camera post-process is shown only for its active camera")
	camera_runtime.set_active(false)
	check(not camera_runtime.camera_overlay.visible, "Inactive camera hides its post-process overlay")
	var fog_definition := registry.get_definition(&"fog_volume")
	var fog_shader_definition := registry.get_object_definition(&"fog_shader_material")
	check(fog_definition.find_property(&"material").object_type == &"fog_shader_material"
		and fog_shader_definition.base_type == &"shader_material"
		and str(fog_shader_definition.find_property(&"shader_path").options.new_file_template).begins_with("shader_type fog;"),
		"Fog Volume exposes a dedicated editable Fog ShaderMaterial")
	var fog_actor := fog_definition.create_actor()
	var fog_object := fog_shader_definition.create_object()
	var fog_shader := Shader.new()
	fog_shader.code = "shader_type fog;\nuniform float density = 0.6;\nvoid fog() { DENSITY = density; ALBEDO = vec3(0.7); }\n"
	fog_object.set_value(&"shader_path", fog_shader)
	fog_object.set_value(&"uniforms", {&"density": 0.8})
	fog_actor.set_value(&"material", ActorObjectReference.from_object(fog_object))
	var fog_runtime := fog_definition.create_runtime(fog_actor)
	root.add_child(fog_runtime)
	fog_runtime.evaluate_clip(ActorClip.create(fog_actor), 0.0)
	check((fog_runtime.content as FogVolume).material is ShaderMaterial
		and is_equal_approx(float(fog_runtime.fog_shader_material.get_shader_parameter(&"density")), 0.8),
		"Fog Volume evaluates a fog shader and its uniform values")
	var fog_inspector := ActorInspector.new()
	fog_inspector.registry = registry
	check(not fog_inspector._property_is_visible(fog_definition.find_property(&"density"), fog_actor),
		"Fog shader hides built-in fog controls that no longer affect the volume")
	fog_actor.set_value(&"material", null)
	fog_runtime.evaluate_clip(ActorClip.create(fog_actor), 0.0)
	check((fog_runtime.content as FogVolume).material is FogMaterial
		and fog_inspector._property_is_visible(fog_definition.find_property(&"density"), fog_actor),
		"Clearing the fog shader restores the built-in FogMaterial")
	fog_inspector.free()

	var baseline_environment := Environment.new()
	root.world_3d.environment = baseline_environment
	var world_actor := world_definition.create_actor()
	var environment_object := environment_definition.create_object()
	environment_object.set_value(&"background_color", Color("345678"))
	world_actor.set_value(&"environment", ActorObjectReference.from_object(environment_object))
	var world_runtime := world_definition.create_runtime(world_actor)
	root.add_child(world_runtime)
	world_runtime.evaluate_clip(ActorClip.create(world_actor), 0.0)
	check(root.world_3d.environment.background_color == Color("345678"),
		"World Environment controls the viewport Environment")
	environment_object.set_value(&"background_mode", 2)
	environment_object.set_value(&"sky_top_color", Color.RED)
	world_runtime.evaluate_clip(ActorClip.create(world_actor), 0.0)
	check(root.world_3d.environment.background_mode == Environment.BG_SKY
		and root.world_3d.environment.sky.sky_material is ProceduralSkyMaterial
		and (root.world_3d.environment.sky.sky_material as ProceduralSkyMaterial).sky_top_color == Color.RED,
		"Procedural background mode builds a native ProceduralSkyMaterial")
	var environment_model := ActorTimeline.new()
	environment_model.create_actor(world_definition, 0.0)
	environment_model.selected_actor().set_value(&"environment", ActorObjectReference.from_object(environment_object))
	var environment_inspector := ActorInspector.new()
	root.add_child(environment_inspector)
	environment_inspector.setup(environment_model, registry, ActorInspectorState.new())
	var environment_slot := environment_inspector.find_child("environment_resource", true, false) as ActorResourceSlot
	check(environment_slot != null and environment_slot.text.contains("Environment")
		and environment_inspector.find_child("sky_top_color", true, false) is LiveColorPickerButton
		and environment_inspector.find_child("background_color", true, false) == null,
		"Environment settings appear inside the actor's expandable resource slot")
	var background_mode_reset := environment_inspector.find_child("background_mode_reset", true, false) as Button
	check(background_mode_reset != null, "Changed Background Mode exposes its reset action")
	if background_mode_reset != null:
		background_mode_reset.pressed.emit()
		await process_frame
		await process_frame
		check(environment_inspector.find_child("background_color", true, false) is LiveColorPickerButton
			and environment_inspector.find_child("sky_top_color", true, false) == null,
			"Resetting Background Mode immediately restores Color-mode inspector fields")
	var sky_shader := Shader.new()
	sky_shader.code = "shader_type sky;\nvoid sky() { COLOR = vec3(0.1, 0.2, 0.3); }\n"
	var shader_material_definition := registry.get_object_definition(&"shader_material")
	var sky_material_object := shader_material_definition.create_object()
	sky_material_object.set_value(&"shader_path", sky_shader)
	environment_object.set_value(&"background_mode", 3)
	environment_object.set_value(&"sky_material", ActorObjectReference.from_object(sky_material_object))
	world_runtime.evaluate_clip(ActorClip.create(world_actor), 0.0)
	check(root.world_3d.environment.sky.sky_material is ShaderMaterial
		and (root.world_3d.environment.sky.sky_material as ShaderMaterial).shader.code == sky_shader.code,
		"Shader Sky consumes a ShaderMaterial resource instead of a raw Shader property")
	environment_inspector._rebuild_selected()
	await process_frame
	await process_frame
	var sky_material_slot := environment_inspector.find_child("sky_material_resource", true, false) as ActorResourceSlot
	check(sky_material_slot != null and sky_material_slot.text.contains("ShaderMaterial")
		and environment_inspector.find_child("sky_shader_file", true, false) == null,
		"Shader Sky displays an editable ShaderMaterial slot rather than a raw Shader slot")
	environment_inspector.free()
	world_runtime.free()
	check(root.world_3d.environment == baseline_environment,
		"Deleting a World Environment actor restores the previous viewport environment")
	shape_runtime.free()
	mesh_runtime.free()
	light_runtime.free()
	directional_runtime.free()
	camera_runtime.free()
	fog_runtime.free()
	print("Actor type checks: ", failures, " failures")
	quit(1 if failures else 0)
