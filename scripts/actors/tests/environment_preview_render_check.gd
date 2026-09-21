extends SceneTree
## Run with an actual rendering driver, not --headless. The window stays hidden.
const Renderer = preload("res://scripts/Extra/thumbnail_renderer.gd")

func _initialize() -> void:
	root.hide()
	run.call_deferred()

func run() -> void:
	var renderer := Node3D.new()
	renderer.set_script(Renderer)
	var viewport := SubViewport.new()
	viewport.name = "SubViewport"
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	renderer.add_child(viewport)
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.name = "DirectionalLight3D"
	viewport.add_child(light)
	for name in ["ObjectHolder", "SphereRenderer"]:
		var mesh := MeshInstance3D.new()
		mesh.name = name
		mesh.mesh = SphereMesh.new()
		mesh.position.z = -2.0
		viewport.add_child(mesh)
	root.add_child(renderer)
	var registry := ActorRegistry.new()
	BasicActors.register_all(registry)
	var object := registry.get_object_definition(&"environment").create_object()
	object.values[&"background_mode"] = 0
	object.values[&"background_color"] = Color.RED
	var texture := await Renderer.render_actor_environment(object)
	assert(texture != null)
	var red_image := texture.get_image()
	assert(red_image.get_pixel(128, 128).r > red_image.get_pixel(128, 128).g + 0.2)
	object.values[&"background_color"] = Color.BLUE
	texture = await Renderer.render_actor_environment(object)
	var blue_image := texture.get_image()
	assert(blue_image.get_pixel(128, 128).b > blue_image.get_pixel(128, 128).r + 0.2)
	object.values[&"background_mode"] = 2
	texture = await Renderer.render_actor_environment(object)
	assert(texture != null)
	assert(texture.get_image().get_pixel(128, 40) != blue_image.get_pixel(128, 40))
	renderer.free()
	await process_frame
	print("Environment preview rendering: passed")
	quit()
