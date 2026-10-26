extends SceneTree
const Browser = preload("res://Workspaces/ShaderWorkspace/shader_sample_browser.gd")
const Application = preload("res://Workspaces/ShaderWorkspace/shader_sample_application.gd")
const Preview = preload("res://Workspaces/ShaderWorkspace/shader_sample_preview.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var sample := {"id": "flow", "name": "Flowing Water", "description": "Moving river surface", "category": "Water", "tags": ["ripple", "animated"], "shader_type": "spatial", "template": false}
	check(Browser.matches(sample, "water ripple", "spatial", "Water", false, 0, [], []), "Search includes category and tags with AND terms")
	check(not Browser.matches(sample, "water", "canvas_item", "", false, 0, [], []), "Shader type filter is strict")
	check(not Browser.matches(sample, "water", "", "", true, 0, [], []), "Templates are separate from samples")
	check(not Browser.matches(sample, "", "", "", false, 1, [], []), "Favorites excludes unstarred samples")
	check(Browser.matches(sample, "", "", "", false, 1, ["flow"], []), "Favorites includes starred samples")
	check(Browser.matches(sample, "", "", "", false, 2, [], ["flow"]), "Recent filter includes used samples")
	var registry := ActorRegistry.new()
	BasicActors.register_all(registry)
	var model := ActorTimeline.new()
	check(not Application.target_for_model(model, registry, "spatial").has("actor"), "No selection disables apply")
	var definition := registry.get_definition(&"basic_shape")
	var actor := definition.create_actor()
	var clip := ActorClip.create(actor, 0.0, 5.0)
	model.actors.append(actor)
	model.clips.append(clip)
	model.selected_id = clip.id
	model.selected_ids = [clip.id]
	check(not Application.target_for_model(model, registry, "canvas_item").has("actor"), "Canvas cannot be assigned to spatial actors")
	check(not Application.target_for_model(model, registry, "fog").has("actor"), "Fog cannot be assigned to spatial actors")
	check(not Application.target_for_model(model, registry, "particles").has("actor"), "Unsupported process slots are explicit")
	var target := Application.target_for_model(model, registry, "spatial")
	check(target.has("actor"), "Surface actor accepts spatial sample")
	var before: Variant = actor.get_value(&"material")
	var code := "shader_type spatial; void fragment(){ALBEDO=vec3(0.3,0.8,0.5);}"
	check(Application.apply_to_target(target, code, "Test") == "", "Apply succeeds through actor model")
	var reference: ActorObjectReference = actor.get_value(&"material")
	var object := ActorAnimation.resolve_reference(reference)
	check(object != null and object.values[&"shader_path"] is Shader, "Apply creates an editable shader copy")
	check(object.values[&"shader_path"].code == code, "Applied shader source is complete")
	model.history.undo()
	check(actor.get_value(&"material") == before, "Undo restores original material reference")
	model.history.redo()
	check(actor.get_value(&"material") != null, "Redo restores sample material")
	var sky_definition := registry.get_definition(&"world_environment")
	var sky_actor := sky_definition.create_actor()
	var sky_clip := ActorClip.create(sky_actor, 0, 5)
	model.actors.append(sky_actor)
	model.clips.append(sky_clip)
	model.selected_id = sky_clip.id
	model.selected_ids = [sky_clip.id]
	var sky_target := Application.target_for_model(model, registry, "sky")
	check(sky_target.has("actor"), "Environment actor accepts sky shader")
	check(not Application.target_for_model(model, registry, "spatial").has("actor"), "Sky actor rejects spatial shader")
	var sky_code := "shader_type sky; void sky(){COLOR=vec3(0.3,0.5,0.8);}"
	check(Application.apply_to_target(sky_target, sky_code, "Test Sky") == "", "Sky apply succeeds")
	var environment_object := ActorAnimation.resolve_reference(sky_actor.get_value(&"environment"))
	check(environment_object.values[&"background_mode"] == 3, "Sky uses shader background mode")
	var sky_object := ActorAnimation.resolve_reference(environment_object.values[&"sky_material"])
	check(sky_object.type_id == &"shader_material" and sky_object.values[&"shader_path"].code == sky_code, "Sky slot uses existing registered shader material context")
	var runtime := sky_definition.create_runtime(sky_actor)
	root.add_child(runtime)
	var environment := Environment.new()
	runtime._apply_environment_background(environment, environment_object)
	check(environment.sky != null and environment.sky.sky_material is ShaderMaterial, "Runtime creates actual sky shader material")
	check(environment.sky.sky_material.shader.get_mode() == Shader.MODE_SKY, "Runtime material remains sky shader")
	runtime.queue_free()
	model.history.undo()
	check(sky_actor.get_value(&"environment") == null, "Sky assignment undo restores previous environment")
	var fixture := Preview.test_texture().get_image()
	check(fixture.get_width() == 192 and fixture.get_pixel(0, 0).a < 0.01, "Actual canvas test image includes transparent edges")
	var popup := ShaderDocumentationPopup.new()
	root.add_child(popup)
	check(popup.sections.tab_count == 3, "Documentation, Samples and Templates share three tabs")
	check(popup.documentation_body != null, "Existing documentation remains present")
	popup.queue_free()
	model.history.clear_history()
	await process_frame
	print("SHADER_LIBRARY_BROWSER_TEST: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	call_deferred("quit", 0 if failures == 0 else 1)
