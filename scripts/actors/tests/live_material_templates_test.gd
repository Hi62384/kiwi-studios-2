extends SceneTree
## Run with a real renderer to verify rendering, baking and saved material masks.
const Library = preload("res://Workspaces/ImageWorkspace/texture_material_library.gd")
var failures := 0
var checks := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func mask(size: Vector2i, rect: Rect2i, alpha: float = 1.0) -> Texture2D:
	var pixels := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	pixels.fill(Color(0, 0, 0, 0))
	pixels.fill_rect(rect, Color(1, 1, 1, alpha))
	return ImageTexture.create_from_image(pixels)

func difference(a: Image, b: Image, area: Rect2i) -> float:
	var sum := 0.0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var ca := a.get_pixel(x, y); var cb := b.get_pixel(x, y)
			sum += absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)+absf(ca.a-cb.a)
	return sum / maxi(1, area.get_area()*4)

func run() -> void:
	var doc := KiwiImageDocument.new()
	doc.canvas_size = Vector2i(128, 96)
	var layer := KiwiImageLayer.create("paint", doc.canvas_size)
	doc.layers.append(layer)
	var original := layer.texture.get_image()
	original.fill_rect(Rect2i(0, 0, 128, 8), Color.RED)
	layer.texture = ImageTexture.create_from_image(original)
	var template := doc.create_live_material(Library.create("wood/oak"), "Table")
	var second := doc.create_live_material(Library.create("fabric/denim"), "Table")
	check(template.id != second.id, "Same labels have independent stable ownership IDs")
	var first_mask := mask(doc.canvas_size, Rect2i(8, 16, 40, 24), .65)
	var first := doc.add_live_region(layer, template.id, first_mask)
	check(layer.live_paint.size() == 2, "Existing raster is frozen before a new material segment")
	check(layer.texture.get_image().get_used_rect().get_area() == 0, "Transparent top raster remains available for later Color strokes")
	check(layer.paint_base == layer.texture, "Restore raster history cannot duplicate the frozen base over live content")
	var other_layer := KiwiImageLayer.create("paint", doc.canvas_size)
	doc.layers.append(other_layer)
	var second_region := doc.add_live_region(other_layer, template.id, mask(doc.canvas_size, Rect2i(70, 16, 40, 24)))
	var independent := doc.add_live_region(layer, second.id, mask(doc.canvas_size, Rect2i(20, 60, 80, 24)))
	var prior := doc.snapshot()
	var wood := template.material.copy_material()
	wood.parameters.primary = Color("0a600e")
	wood.parameters.secondary = Color("8de542")
	doc.set_live_material(template.id, wood)
	check(prior.live_material_for_id(template.id).material.parameters.primary != wood.parameters.primary, "Material parameter undo snapshots are independent")
	check(first.coverage == first_mask, "Changing material does not rewrite coverage")
	check(second.material.parameters.primary != wood.parameters.primary, "Changing one template leaves another template unchanged")
	check(prior.layers[0].live_paint[1] != first and prior.layers[0].live_paint[1].coverage == first.coverage, "History copies region metadata and shares immutable textures")
	var after := doc.snapshot()
	check(doc.delete_live_material(template.id), "Delete accepts a valid template")
	check(layer.live_paint.size() == 2 and layer.live_paint[-1].template_id == second.id, "Delete removes only owned material segments")
	check(other_layer.live_paint.is_empty(), "Delete removes all owned regions across layers")
	check(layer.live_paint[0].raster.get_image().get_data() == original.get_data(), "Delete preserves unrelated raster bytes")
	doc = after.snapshot()
	layer = doc.layers[0]; other_layer = doc.layers[1]
	check(doc.live_material_has_artwork(template.id), "Undo snapshot restores deleted artwork and template")
	var save_path := "res://.godot/verification/live_material_roundtrip.tres"
	var save_snapshot := doc.snapshot()
	save_snapshot.pack_live_material_textures()
	check(ResourceSaver.save(save_snapshot, save_path) == OK, "Live materials save as a native document")
	var loaded := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as KiwiImageDocument
	check(loaded != null and loaded.live_materials.size() == 2, "Native load restores all template resources")
	check(loaded.layers[0].live_paint[1].coverage.get_image().get_data() == first_mask.get_image().get_data(), "Lossless native load preserves fractional coverage exactly")
	check(loaded.live_material_for_id(template.id).material.parameters.primary == wood.parameters.primary, "Native load preserves edited material settings")
	check(loaded.layers[1].live_paint[0].template_id == second_region.template_id, "Cross-layer ownership survives native loading")
	var erased := doc.snapshot()
	var eraser := mask(doc.canvas_size, Rect2i(8, 16, 10, 12)).get_image()
	erased.layers[0].erase_live_paint(eraser)
	check(erased.layers[0].live_paint[1].coverage.get_image().get_pixel(10, 20).a == 0, "Eraser removes live coverage")
	check(doc.layers[0].live_paint[1].coverage.get_image().get_pixel(10, 20).a > .6, "Eraser leaves undo snapshot masks unchanged")
	if DisplayServer.get_name() == "headless":
		print("Live material model: %d checks, %d failures (GPU checks skipped: headless)" % [checks, failures])
		quit(failures); return
	var renderer := KiwiImageRenderer.new()
	root.add_child(renderer)
	renderer.sync(doc)
	var before := await renderer.flattened()
	check(before.get_pixel(2, 2).r > .95, "Renderer preserves original raster before material regions")
	check(absf(before.get_pixel(20, 20).a - .65) < .02, "Live renderer preserves fractional coverage alpha")
	renderer.sync(loaded)
	var reopened := await renderer.flattened()
	check(difference(before, reopened, Rect2i(Vector2i.ZERO, doc.canvas_size)) < .001, "Reopening a native document reproduces the same rendered live artwork")
	renderer.sync(doc)
	doc.layers[0].live_paint[1].opacity = .5
	renderer.sync(doc)
	var low_opacity := await renderer.flattened()
	check(absf(low_opacity.get_pixel(20, 20).a - .325) < .02, "Per-region opacity multiplies coverage exactly once")
	doc.layers[0].live_paint[1].opacity = 1.0
	renderer.sync(doc)
	var image_before := before.duplicate()
	var changed := doc.live_material_for_id(template.id).material.copy_material()
	changed.parameters.primary = Color("830918"); changed.parameters.secondary = Color("fa705e")
	doc.set_live_material(template.id, changed)
	renderer.sync(doc)
	var recolored := await renderer.flattened()
	check(difference(before, recolored, Rect2i(8, 16, 40, 24)) > .03, "Existing first region updates from template color changes")
	check(difference(before, recolored, Rect2i(70, 16, 40, 24)) > .03, "Existing second layer updates from the same template")
	check(difference(before, recolored, Rect2i(20, 60, 80, 24)) < .001, "Other template pixels do not change")
	changed = changed.copy_material(); changed.texture_size *= 2.7
	doc.set_live_material(template.id, changed)
	renderer.sync(doc)
	var rescaled := await renderer.flattened()
	check(difference(recolored, rescaled, Rect2i(70, 16, 40, 24)) > .004, "Texture size changes existing drawings without repainting")
	check(rescaled.get_pixel(3, 50).a == 0, "Parameter changes never extend the stored coverage shape")
	var before_bake := doc.snapshot()
	doc.live_material_for_id(template.id).visible = false
	var hidden_bake: bool = await renderer.bake_live_material(template.id)
	check(not hidden_bake, "Hidden template cannot be silently baked into empty pixels")
	check(doc.live_material_for_id(template.id) != null and doc.live_material_has_artwork(template.id), "Rejected hidden bake retains its full editable artwork")
	doc.live_material_for_id(template.id).visible = true
	check(await renderer.bake_live_material(template.id), "GPU bake succeeds")
	var baked := await renderer.flattened()
	check(difference(rescaled, baked, Rect2i(Vector2i.ZERO, doc.canvas_size)) < .006, "Bake preserves appearance and opacity without duplicating content")
	check(doc.live_material_for_id(template.id) == null and doc.live_material_for_id(second.id) != null, "Bake removes only the finished template")
	check(doc.layers[1].live_paint.is_empty() and doc.layers[1].texture.get_image().get_used_rect().has_area(), "Fully baked layer becomes an ordinary editable raster")
	check(doc.layers[0].live_paint.size() == 3 and doc.layers[0].live_paint[1].raster != null, "Bake preserves stack order around another live material")
	var before_other := baked.duplicate()
	var denim := doc.live_material_for_id(second.id).material.copy_material(); denim.parameters.primary = Color.YELLOW
	doc.set_live_material(second.id, denim); renderer.sync(doc)
	var changed_other := await renderer.flattened()
	check(difference(before_other, changed_other, Rect2i(70, 16, 40, 24)) < .001, "Baked pixels are independent of subsequent material edits")
	doc = before_bake.snapshot(); renderer.sync(doc)
	var undone_bake := await renderer.flattened()
	check(difference(rescaled, undone_bake, Rect2i(Vector2i.ZERO, doc.canvas_size)) < .001, "Undo restores live template, masks and exact pre-bake appearance")
	# Interleave Color content between material segments and check the actual GPU order.
	var top := doc.layers[0].texture.get_image(); top.fill_rect(Rect2i(8, 16, 40, 24), Color.BLUE)
	doc.layers[0].texture = ImageTexture.create_from_image(top); renderer.sync(doc)
	var painted_top := await renderer.flattened()
	check(painted_top.get_pixel(20, 20).b > .98 and painted_top.get_pixel(20, 20).r < .02, "Ordinary Color paint appears above older live material")
	doc.add_live_region(doc.layers[0], second.id, mask(doc.canvas_size, Rect2i(8, 16, 15, 24)))
	renderer.sync(doc)
	var ordered := await renderer.flattened()
	check(ordered.get_pixel(15, 20).b < .95 and ordered.get_pixel(35, 20).b > .98, "Later material covers intervening raster only inside its new coverage")
	var source := await renderer.source_image(doc.layers[0])
	check(source != null and source.get_pixel(35, 20).b > .98, "Bucket source includes all prior raster and material segments")
	# Existing layer mask, opacity and transforms operate on the entire live stack.
	doc.layers[0].opacity = .5; doc.layers[0].position = Vector2(0, 4)
	var layer_mask := Image.create(128, 96, false, Image.FORMAT_RGBA8); layer_mask.fill(Color.WHITE); layer_mask.fill_rect(Rect2i(0, 0, 64, 96), Color.BLACK)
	doc.layers[0].mask = ImageTexture.create_from_image(layer_mask); renderer.sync(doc)
	var masked := await renderer.flattened()
	check(masked.get_pixel(35, 24).a < .01, "Layer mask clips live and raster segments together after transform")
	check(masked.get_pixel(85, 70).a > .45 and masked.get_pixel(85, 70).a < .55, "Layer opacity affects the composed live stack")
	var sheet := Image.create(128*4, 96, false, Image.FORMAT_RGBA8)
	for index in 4:
		var entry: Image = [image_before, recolored, rescaled, baked][index]
		sheet.blit_rect(entry, Rect2i(Vector2i.ZERO, doc.canvas_size), Vector2i(index*128, 0))
	sheet.save_png("res://.godot/verification/live_material_workflow.png")
	var started := Time.get_ticks_usec()
	for index in 120: renderer.sync(doc)
	print("Live stack sync (%d layers, %d regions): %.3f ms/update" % [doc.layers.size(), doc.layers[0].live_paint.size(), (Time.get_ticks_usec()-started)/120000.0])
	await group_and_clip_checks(renderer)
	renderer.queue_free(); await process_frame
	print("Live material templates: %d checks, %d failures" % [checks, failures])
	quit(failures)


func group_and_clip_checks(renderer: KiwiImageRenderer) -> void:
	var doc := KiwiImageDocument.new(); doc.canvas_size = Vector2i(128, 96)
	var group := KiwiImageLayer.create("group", doc.canvas_size)
	group.opacity = .4
	var background := KiwiImageLayer.create("paint", doc.canvas_size)
	background.parent_id = group.id
	background.texture = mask(doc.canvas_size, Rect2i(0, 0, 64, 96))
	var foreground := KiwiImageLayer.create("paint", doc.canvas_size)
	foreground.parent_id = group.id; foreground.clip_to_below = true
	doc.layers.assign([group, background, foreground])
	var template := doc.create_live_material(Library.create("wood/oak"))
	doc.add_live_region(foreground, template.id, mask(doc.canvas_size, Rect2i(0, 0, 128, 96)))
	renderer.sync(doc)
	var clipped := await renderer.flattened()
	check(absf(clipped.get_pixel(20, 30).a-.4)<.02, "Group opacity applies once to overlapping raster and live material")
	check(clipped.get_pixel(100, 30).a<.01, "Live material respects clip-to-below inside a group")
	check(clipped.get_pixel(20, 30).r<.9, "Clipped foreground retains procedural color rather than the white clipping source")
	group.position = Vector2(16, 8)
	renderer.sync(doc)
	var moved := await renderer.flattened()
	check(moved.get_pixel(8, 30).a < .01 and moved.get_pixel(30, 40).a > .35, "Group transforms move all live and raster contents together")
	group.visible = false; renderer.sync(doc)
	var hidden := await renderer.flattened()
	check(not hidden.get_used_rect().has_area(), "Group visibility hides every owned live region")
	group.visible = true
	var mask_image := Image.create(128, 96, false, Image.FORMAT_RGBA8)
	mask_image.fill(Color.WHITE); mask_image.fill_rect(Rect2i(0, 0, 128, 48), Color.BLACK)
	group.mask = ImageTexture.create_from_image(mask_image); renderer.sync(doc)
	var masked := await renderer.flattened()
	check(masked.get_pixel(30, 30).a < .01 and masked.get_pixel(30, 70).a > .35, "Group mask clips the combined child composition")
	group.mask = null; foreground.isolated = true; renderer.sync(doc)
	var isolated := await renderer.flattened()
	check(isolated.get_pixel(30, 40).a > .35, "Isolated live child remains visible through its group container")
	check(not doc.isolation_allows(background), "Isolation excludes unrelated group siblings")
	foreground.isolated = false; group.isolated = true
	check(doc.isolation_allows(background) and doc.isolation_allows(foreground), "Isolating a group includes its raster and live children")
	group.isolated = false; group.opacity = 1.0; group.position = Vector2.ZERO
	doc.resize_layer(group, Vector2(64, 48)); renderer.sync_transforms(doc)
	for frame in 14: await RenderingServer.frame_post_draw
	var resized := renderer.export_viewport.get_texture().get_image()
	check(resized.get_pixel(24, 30).a > .95 and resized.get_pixel(40, 30).a < .01, "Group resize preview scales children once rather than twice")
