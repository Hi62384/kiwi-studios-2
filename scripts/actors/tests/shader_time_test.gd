extends SceneTree

const ShaderTime = preload("res://scripts/actors/core/actor_shader_time.gd")
var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var source := """shader_type spatial;
render_mode unshaded;
// TIME should stay in this comment.
/* TIME should stay here too. */
uniform float TIMELINE = 1.0;
void fragment() { ALBEDO = vec3(TIME / 5.0); }
"""
	var transformed: Dictionary = ShaderTime.prepare(source)
	check(source.contains("vec3(TIME / 5.0)"), "Source shader stays unchanged")
	check(str(transformed.code).contains("vec3(%s / 5.0)" % transformed.uniform),
		"Runtime shader substitutes standalone TIME")
	check(str(transformed.code).contains("// TIME") and str(transformed.code).contains("/* TIME")
		and str(transformed.code).contains("TIMELINE"),
		"Comments and longer identifiers are not rewritten")
	check(str(transformed.code).contains("uniform float %s;" % transformed.uniform),
		"Runtime shader declares its controllable time uniform")
	var static_code := "shader_type spatial; void fragment() { ALBEDO = vec3(0.5); }"
	check(ShaderTime.prepare(static_code).code == static_code,
		"Shaders without TIME are not modified")
	var collision := ShaderTime.prepare("shader_type spatial; uniform float kiwi_timeline_time; void fragment() { ALBEDO = vec3(TIME); }")
	check(collision.uniform != "kiwi_timeline_time", "Generated uniform avoids an existing name")
	var registry := ActorRegistry.new()
	BasicActors.register_all(registry)
	var shader := Shader.new()
	shader.code = source
	var object := registry.get_object_definition(&"shader_material").create_object()
	object.set_value(&"shader_path", shader)
	var actor := registry.get_definition(&"basic_shape").create_actor()
	actor.set_value(&"material", ActorObjectReference.from_object(object))
	var runtime := registry.get_definition(&"basic_shape").create_runtime(actor)
	root.add_child(runtime)
	var clip := ActorClip.create(actor)
	runtime.evaluate_clip(clip, 2.25)
	var material := runtime.get("shader_material") as ShaderMaterial
	check(material != null and material.shader != shader and shader.code == source,
		"Actor uses a private transformed shader without editing the source")
	check(material != null and is_equal_approx(float(material.get_shader_parameter(transformed.uniform)), 2.25),
		"Runtime shader receives the timeline playhead time")
	runtime.evaluate_clip(clip, 3.75)
	check(is_equal_approx(float(material.get_shader_parameter(transformed.uniform)), 3.75),
		"Scrubbing updates the time uniform without recompilation")
	var sky_shader := Shader.new()
	sky_shader.code = "shader_type sky; void sky() { COLOR = vec3(TIME); }"
	var sky_object := registry.get_object_definition(&"shader_material").create_object()
	sky_object.set_value(&"shader_path", sky_shader)
	var sky_material := runtime.call("_create_shader_material", sky_object) as ShaderMaterial
	var sky_uniform := str(sky_material.get_meta("kiwi_time_uniform", ""))
	check(not sky_uniform.is_empty() and sky_material.shader.code.contains("vec3(%s)" % sky_uniform),
		"Sky shaders also get controllable timeline time")
	var environment := Environment.new()
	environment.sky = Sky.new()
	environment.sky.sky_material = sky_material
	runtime.set("_world_environment_resource", environment)
	runtime.set_timeline_time(1.5)
	check(is_equal_approx(float(sky_material.get_shader_parameter(sky_uniform)), 1.5),
		"Sky material receives timeline time")
	var environment_object := registry.get_object_definition(&"environment").create_object()
	environment_object.set_value(&"background_mode", 3)
	environment_object.set_value(&"sky_material", ActorObjectReference.from_object(sky_object))
	var environment_actor := registry.get_definition(&"world_environment").create_actor()
	environment_actor.set_value(&"environment", ActorObjectReference.from_object(environment_object))
	var environment_runtime := registry.get_definition(&"world_environment").create_runtime(environment_actor)
	root.add_child(environment_runtime)
	environment_runtime.evaluate_clip(ActorClip.create(environment_actor), 1.5)
	var live_environment := environment_runtime.get("_world_environment_resource") as Environment
	check(live_environment.sky != null and live_environment.sky.process_mode == Sky.PROCESS_MODE_REALTIME,
		"Animated sky uses real-time radiance updates after TIME replacement")
	environment_runtime.free()
	if DisplayServer.get_name() != "headless":
		var viewport := SubViewport.new()
		viewport.size = Vector2i(64, 64)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var camera := Camera3D.new()
		camera.position = Vector3(0, 0, 3)
		viewport.add_child(camera)
		camera.current = true
		runtime.reparent(viewport)
		runtime.evaluate_clip(clip, 0.0)
		await RenderingServer.frame_post_draw
		var dark := viewport.get_texture().get_image().get_pixel(32, 32).r
		runtime.evaluate_clip(clip, 4.0)
		await RenderingServer.frame_post_draw
		var bright := viewport.get_texture().get_image().get_pixel(32, 32).r
		check(bright > dark + 0.3, "Rendered shader pixels follow timeline time")
		viewport.free()
	else:
		runtime.free()
	await process_frame
	print("Shader timeline time checks: %d failures" % failures)
	quit(failures)
