extends SceneTree
## Run with a graphics renderer (not --headless). The comparison uses the real
## actor adapter above and the real image material renderer below each sphere.

const NaturalEngine = preload("res://scripts/materials/natural_material_engine.gd")
const Render = preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1200, 600)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("18212e")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d5e3ff")
	environment.environment.ambient_light_energy = 0.55
	viewport.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -35, 0)
	key.light_energy = 1.1
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(25, 160, 0)
	fill.light_energy = 0.6
	viewport.add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 5.0
	camera.position = Vector3(0, 0.25, 8)
	viewport.add_child(camera)
	var registry := ActorRegistry.new()
	BasicActors.register_all(registry)
	var materials := ["wood/oak", "fabric/denim", "metal/hammered_metal", "stone/marble"]
	var names := ["Oak • grain & knots", "Denim • diagonal weave", "Hammered metal • relief", "Marble • mineral veins"]
	var panel := Control.new()
	viewport.add_child(panel)
	var heading := Label.new()
	heading.text = "NATURAL MATERIAL  /  shared 3D surface and 2D artwork patterns"
	heading.position = Vector2(20, 16)
	heading.add_theme_font_size_override("font_size", 22)
	panel.add_child(heading)
	for index in materials.size():
		var settings := NaturalEngine.defaults(materials[index])
		settings.relief = 0.4
		settings.parameters.seed = 31
		settings.texture_size = 96.0
		var object := registry.get_object_definition(&"natural_material").create_object()
		object.set_value(&"material_settings", settings)
		var definition := registry.get_definition(&"basic_shape")
		var actor := definition.create_actor()
		actor.set_value(&"shape", 1)
		actor.set_value(&"sphere_radius", 0.95)
		actor.set_value(&"sphere_height", 1.9)
		actor.set_value(&"material", ActorObjectReference.from_object(object))
		actor.set_value(&"position", Vector3((index - 1.5) * 2.5, 0.8, 0))
		var runtime := definition.create_runtime(actor)
		viewport.add_child(runtime)
		runtime.evaluate_clip(ActorClip.create(actor), 0)
		var title := Label.new()
		title.text = names[index]
		title.position = Vector2(20 + index * 300, 365)
		title.add_theme_font_size_override("font_size", 18)
		panel.add_child(title)
		var swatch := ColorRect.new()
		swatch.position = Vector2(20 + index * 300, 410)
		swatch.size = Vector2(260, 160)
		swatch.material = Render.material(NaturalEngine.material_from_settings(settings), swatch.size)
		panel.add_child(swatch)
	var started := Time.get_ticks_usec()
	for frame in 8:
		await process_frame
		await RenderingServer.frame_post_draw
	var warmup_ms := (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	for frame in 30:
		await process_frame
		await RenderingServer.frame_post_draw
	var warm_average_ms := (Time.get_ticks_usec() - started) / 30000.0
	var image := viewport.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://.godot/verification")
	var result := image.save_png("res://.godot/verification/natural_scene_surfaces.png")
	print("NATURAL_MATERIAL_SCENE_RENDER: save=%d image=%dx%d warmup_8_frames_ms=%.2f warm_30_frames_average_ms=%.2f" % [
		result, image.get_width(), image.get_height(), warmup_ms, warm_average_ms])
	viewport.free()
	quit(0 if result == OK else 1)
