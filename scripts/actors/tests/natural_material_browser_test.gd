extends SceneTree
## Graphics-mode integration test for the shared browser used by scene objects.

const NaturalEngine = preload("res://scripts/materials/natural_material_engine.gd")
const Presets = preload("res://scripts/materials/natural_material_presets.gd")
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
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i(1280, 800)
	var app := Control.new()
	app.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(app)
	var host := Control.new()
	host.name = "SceneWorkspace"
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	app.add_child(host)
	var background := ColorRect.new()
	background.color = Color("15212d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(background)
	var registry := ActorRegistry.new()
	BasicActors.register_all(registry)
	var definition := registry.get_object_definition(&"natural_material")
	var model := ActorTimeline.new()
	model.create_actor(registry.get_definition(&"basic_shape"), 0)
	var actor := model.selected_actor()
	actor.set_value(&"shape", 1)
	actor.set_value(&"sphere_radius", 0.9)
	actor.set_value(&"sphere_height", 1.8)
	var object := definition.create_object()
	object.set_value(&"material_settings", NaturalEngine.defaults("wood/oak"))
	actor.set_value(&"material", ActorObjectReference.from_object(object))
	var scene_panel := SubViewportContainer.new()
	scene_panel.position = Vector2(440, 120)
	scene_panel.size = Vector2(430, 470)
	scene_panel.stretch = true
	host.add_child(scene_panel)
	var scene_viewport := SubViewport.new()
	scene_viewport.size = Vector2i(430, 470)
	scene_viewport.own_world_3d = true
	scene_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	scene_panel.add_child(scene_viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("15212d")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.55
	scene_viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	scene_viewport.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 0, 4)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.8
	scene_viewport.add_child(camera)
	var runtime := registry.get_definition(&"basic_shape").create_runtime(actor)
	scene_viewport.add_child(runtime)
	runtime.evaluate_clip(model.selected_clip(), 0)
	var update_runtime := func():
		if is_instance_valid(runtime): runtime.evaluate_clip(model.clip_for_actor_id(actor.id), 0)
	model.changed.connect(update_runtime)
	var scene_label := Label.new()
	scene_label.position = Vector2(470, 40)
	scene_label.text = "LIVE SCENE SURFACE\nShared settings • Undo / Redo"
	scene_label.add_theme_font_size_override("font_size", 19)
	host.add_child(scene_label)
	var inspector := ActorInspector.new()
	inspector.position = Vector2(12, 12)
	inspector.size = Vector2(420, 760)
	host.add_child(inspector)
	inspector.setup(model, registry)
	var editor := inspector.find_child("NaturalMaterialEditor", true, false)
	check(editor != null, "Natural Material exposes its inspector editor")
	if editor == null:
		quit(1)
		return
	editor._open_browser()
	var browser: Control = editor._browser
	check(browser != null and browser is PanelContainer, "Scene opens shared nonmodal browser")
	check(browser.get_parent() == host, "Material dock stays inside the scene workspace when switching tabs")
	host.hide()
	check(not browser.is_visible_in_tree(), "Switching away from the scene hides the material dock")
	host.show()
	editor._open_browser()
	check(editor._browser == browser, "Repeated browser action reuses the open dock")
	browser.call("close")
	editor._open_browser()
	check(editor._browser != browser, "Immediately reopening a closed browser creates a usable dock")
	browser = editor._browser
	var denim := NaturalEngine.material_from_settings(NaturalEngine.defaults("fabric/denim"))
	denim.parameters.seed = 313
	denim.parameters.primary = Color("215b70")
	denim.texture_size = 85
	browser.call("set_material_value", denim)
	browser.call("changed")
	check(object.get_value(&"material_settings").material_id == "fabric/denim", "Browser selection changes the actual scene material")
	check(runtime.get("_natural_settings").material_id == "fabric/denim", "Browser editing immediately updates the actor runtime")
	check(object.get_value(&"material_settings").parameters.seed == 313, "Material-specific settings survive browser transfer")
	browser.emit_signal("edit_committed")
	model.undo()
	check(object.get_value(&"material_settings").material_id == "wood/oak", "Undo shared-browser editing restores the previous material")
	check(browser.get("value").material_id == "wood/oak", "Open shared browser follows scene Undo")
	model.redo()
	check(browser.get("value").material_id == "fabric/denim", "Open shared browser follows scene Redo")
	var preset_id := Presets.save_material(denim)
	check(not preset_id.is_empty(), "Scene settings save through shared preset persistence")
	var restored := Presets.load_material(preset_id)
	check(restored != null and restored.texture_size == 85 and restored.parameters.seed == 313, "Image-compatible preset restores scene settings exactly")
	if restored != null:
		restored.parameters.seed = 1
		check(Presets.load_material(preset_id).parameters.seed == 313, "Editing local instances leaves the saved shared preset unchanged")
	Presets.remove(preset_id)
	if DisplayServer.get_name() != "headless":
		for frame in 6:
			await process_frame
			await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.godot/verification")
		var image := root.get_texture().get_image()
		check(image.save_png("res://.godot/verification/natural_material_browser.png") == OK, "Capture actual shared scene browser")
	else:
		print("NATURAL_MATERIAL_BROWSER_TEST: headless, rendered screenshot check skipped")
	var path := "user://natural_material_browser_file_test.tres"
	check(ResourceSaver.save(object, path) == OK, "Save reusable Natural Material resource")
	inspector.inspect_file_resource(path)
	await process_frame
	var file_editor := inspector.find_child("NaturalMaterialEditor", true, false)
	check(file_editor != null, "Saved Natural Material resources use the same editor")
	if file_editor != null:
		var ownership := file_editor.find_child("NaturalMaterialOwnership", true, false) as Label
		check(ownership != null and ownership.text.begins_with("Saved resource"), "File editing clearly identifies shared-resource scope")
		file_editor._change("texture_size", 143.0)
		file_editor._finish_edit()
		var saved := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
		check(saved.get_value(&"material_settings").texture_size == 143.0, "Committed file material settings persist")
		model.undo()
		saved = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		check(saved.get_value(&"material_settings").texture_size == 85.0, "Undo file material editing restores the saved resource")
	DirAccess.remove_absolute(path)
	if is_instance_valid(browser) and not browser.is_queued_for_deletion(): browser.call("close")
	app.queue_free()
	await process_frame
	model.history.clear_history()
	model.changed.disconnect(update_runtime)
	print("NATURAL_MATERIAL_BROWSER_TEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
