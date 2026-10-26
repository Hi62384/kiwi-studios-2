extends SceneTree
## Adaptive preview must affect only render targets, never source pixels, texture
## mapping, Bucket region detection, native export or baked artwork.
const Library = preload("res://Workspaces/ImageWorkspace/texture_material_library.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)

func frames(count: int = 18) -> void:
	for frame in count: await RenderingServer.frame_post_draw

func difference(a: Image, b: Image) -> float:
	var sum := 0.0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y); var cb := b.get_pixel(x, y)
			sum += absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)+absf(ca.a-cb.a)
	return sum/(a.get_width()*a.get_height()*4.0)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Adaptive material preview: GPU checks require a real renderer")
		quit(0); return
	var doc := KiwiImageDocument.new(); doc.canvas_size = Vector2i(512, 128)
	var layer := KiwiImageLayer.create("paint", doc.canvas_size)
	layer.position = Vector2(16, 0)
	doc.layers.append(layer)
	var material := Library.create("wood/oak")
	material.texture_size = 512; material.relief = 0.0
	var template := doc.create_live_material(material)
	var mask := Image.create(512, 128, false, Image.FORMAT_RGBA8)
	mask.fill_rect(Rect2i(32, 32, 160, 64), Color(1, 1, 1, .8))
	# A single-pixel hole must survive native Bucket reads, even if the reduced
	# screen preview cannot represent it at its current zoom.
	mask.set_pixel(101, 55, Color(0, 0, 0, 0))
	var region := doc.add_live_region(layer, template.id, ImageTexture.create_from_image(mask), Transform2D(0, Vector2(37, 19)))
	var coverage_hash := hash(region.coverage.get_image().get_data())
	var renderer := KiwiImageRenderer.new(); root.add_child(renderer)
	renderer.sync(doc)
	var native_source := await renderer.source_image(layer)
	var native_export := await renderer.flattened()
	renderer.preview_interactive_limit = 128 # Small fixture exercises the 2048px production cap.
	renderer.set_interactive_preview(true)
	renderer.set_preview_camera(Vector2(256, 64), Vector2.ZERO, .5)
	await frames()
	check(is_equal_approx(renderer.render_scale, .25), "Interactive preview respects target resolution cap")
	check(renderer.views[layer.id].base.size == Vector2i(224, 128), "Only scaled source target plus fixed effect padding is allocated")
	check(renderer.viewport.size == Vector2i(256, 64), "Screen viewport retains its requested dimensions")
	var shader_material: ShaderMaterial = renderer.views[layer.id].live_views[region.id].display.material
	check(shader_material.get_shader_parameter("extent") == layer.dimensions and is_equal_approx(shader_material.get_shader_parameter("texture_size"), 512.0), "Material mapping uses native extent and texture scale at reduced resolution")
	var reduced := renderer.export_viewport.get_texture().get_image()
	check(absf(reduced.get_pixel(40, 24).a-.8) < .02 and reduced.get_pixel(15, 24).a < .01, "Camera compensation preserves artwork position and coverage")
	var expected := native_export.duplicate(); expected.resize(256, 64, Image.INTERPOLATE_BILINEAR)
	check(difference(reduced, expected) < .02, "Reduced procedural preview preserves pattern coordinates and colors")
	check(region.coverage.get_size() == Vector2(512, 128) and hash(region.coverage.get_image().get_data()) == coverage_hash, "Preview reduction never resizes or edits native coverage")
	var exact_source := await renderer.source_image(layer)
	check(exact_source.get_size() == Vector2i(512, 128) and exact_source.get_data() == native_source.get_data(), "Bucket reads exact native source pixels at reduced preview resolution")
	check(exact_source.get_pixel(101, 55).a == 0.0, "Bucket readback retains single-pixel holes")
	check(is_equal_approx(renderer.render_scale, .25), "Native Bucket readback leaves interactive scale unchanged")
	var exact_export := await renderer.flattened()
	check(exact_export.get_size() == doc.canvas_size and difference(exact_export, native_export) < .001, "Export renders native dimensions and identical material output")
	check(is_equal_approx(renderer.render_scale, .25), "Export restores prior adaptive preview scale")
	renderer.set_preview_camera(Vector2(512, 128), Vector2.ZERO, 1.0)
	check(is_equal_approx(renderer.render_scale, .25), "Active gesture remains economical at high zoom")
	renderer.set_interactive_preview(false)
	check(is_equal_approx(renderer.render_scale, .25), "Gesture release keeps reduced preview through debounce")
	await create_timer(.42).timeout
	await frames()
	check(is_equal_approx(renderer.render_scale, 1.0), "Idle high-zoom preview refines to native resolution")
	check(renderer.views[layer.id].base.size == Vector2i(608, 224), "Idle refinement reallocates native source targets")
	var refined := renderer.export_viewport.get_texture().get_image()
	check(difference(refined, native_export) < .001, "Refined preview matches full-resolution reference")
	var sheet := Image.create(1536, 128, false, Image.FORMAT_RGBA8)
	var enlarged := reduced.duplicate(); enlarged.resize(512, 128, Image.INTERPOLATE_BILINEAR)
	for index in 3: sheet.blit_rect([native_export, enlarged, refined][index], Rect2i(0, 0, 512, 128), Vector2i(index*512, 0))
	sheet.save_png("res://.godot/verification/adaptive_material_preview.png")
	renderer.set_interactive_preview(true)
	check(await renderer.bake_live_material(template.id), "Material bake succeeds while preview is reduced")
	check(layer.texture.get_size() == Vector2(512, 128), "Baked artwork preserves native raster dimensions")
	var baked := await renderer.flattened()
	check(difference(baked, native_export) < .006, "Adaptive mode cannot lower baked artwork quality")
	renderer.queue_free(); await process_frame; await process_frame
	print("Adaptive material preview: %d checks, %d failures" % [checks, failures])
	quit(failures)
