extends SceneTree
## Run with a graphics display / Forward+; headless intentionally reports SKIP.
const Preview = preload("res://Workspaces/ShaderWorkspace/shader_sample_preview.gd")
var failures := 0
var evidence := "res://.godot/verification/"

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("SHADER_LIBRARY_RENDER_TEST: SKIP (graphics display required)")
		quit()
		return
	var renderer := Preview.new()
	root.add_child(renderer)
	var fixtures := [
		{"id":"canvas", "shader_type":"canvas_item", "source":"shader_type canvas_item; void fragment(){COLOR=texture(TEXTURE,UV)*vec4(0.2,0.8,1.0,1.0);}"},
		{"id":"spatial", "shader_type":"spatial", "source":"shader_type spatial; void fragment(){ALBEDO=vec3(UV,0.35);ROUGHNESS=0.35;}"},
		{"id":"sky", "shader_type":"sky", "source":"shader_type sky; void sky(){COLOR=mix(vec3(0.04,0.12,0.4),vec3(0.9,0.5,0.2),pow(1.0-abs(EYEDIR.y),3.0));}"},
		{"id":"fog", "shader_type":"fog", "source":"shader_type fog; void fog(){DENSITY=0.7;ALBEDO=vec3(0.2,0.65,0.9);EMISSION=vec3(0.1,0.2,0.4);}"},
		{"id":"particles", "shader_type":"particles", "source":"shader_type particles; void start(){TRANSFORM[0].xyz*=0.07;TRANSFORM[1].xyz*=0.07;TRANSFORM[2].xyz*=0.07;TRANSFORM[3].xyz=vec3(sin(float(NUMBER)*12.7),cos(float(NUMBER)*8.3),0.0);VELOCITY=vec3(0.0,0.3,0.0);COLOR=vec4(1.0,0.4,0.05,1.0);} void process(){TRANSFORM[3].xyz+=VELOCITY*DELTA;}"}
	]
	var results: Array[Dictionary] = []
	for fixture in fixtures:
		var start := Time.get_ticks_usec()
		var error: String = renderer.show_entry(fixture)
		check(error.is_empty(), str(fixture.id) + " starts real shader preview: " + error)
		for _frame in 10: await process_frame
		await RenderingServer.frame_post_draw
		error = renderer.check_errors()
		check(error.is_empty(), str(fixture.id) + " compiles on GPU: " + error)
		check(renderer.material.shader.code == fixture.source, "Preview runs original complete source")
		var image := renderer.get_texture().get_image()
		check(image != null and not image.is_empty(), str(fixture.id) + " renders an image")
		if image != null:
			image.save_png(evidence + "library_fixture_" + str(fixture.id) + ".png")
			results.append({"id":fixture.id,"milliseconds":(Time.get_ticks_usec()-start)/1000.0,"sha256":image.get_data().hex_encode().sha256_text()})
		renderer.set_active(false)
	# Verify that a compiler failure cannot be mistaken for a successful preview.
	print("EXPECTED_SHADER_COMPILER_ERROR_BEGIN")
	var invalid: String = renderer.show_entry({"shader_type":"spatial", "source":"shader_type spatial; void fragment(){ALBEDO=undefined_library_test_symbol;}"})
	for _frame in 3: await process_frame
	invalid = renderer.check_errors()
	check(not invalid.is_empty() and invalid.contains("compilation failed"), "Engine shader error produces explicit preview failure")
	print("EXPECTED_SHADER_COMPILER_ERROR_END")
	var file := FileAccess.open(evidence + "shader_library_render_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_method(),"failures":failures,"results":results}, "\t"))
	file.close()
	renderer.queue_free()
	await process_frame
	print("SHADER_LIBRARY_RENDER_TEST: %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	call_deferred("quit", 0 if failures == 0 else 1)
