extends SceneTree
## Real GPU cache verification: unchanged layers must stop drawing while template,
## group, clipping, mutable texture and TIME dependencies continue to update.
const Library = preload("res://Workspaces/ImageWorkspace/texture_material_library.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures += 1; push_error(message)

func pixels(size: Vector2i, color: Color) -> Image:
	var result := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	result.fill(color)
	return result

func frames(count: int = 28) -> void:
	for frame in count: await RenderingServer.frame_post_draw

func count(renderer: KiwiImageRenderer, layer: KiwiImageLayer) -> int:
	return int(renderer.views[layer.id].get("frames_rendered", 0))

func dormant(renderer: KiwiImageRenderer, layer: KiwiImageLayer) -> bool:
	var view: Dictionary = renderer.views[layer.id]
	if view.base.render_target_update_mode != SubViewport.UPDATE_DISABLED: return false
	for stage in view.stages:
		if stage.viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED: return false
	return true

func run() -> void:
	var doc := KiwiImageDocument.new()
	doc.canvas_size = Vector2i(96, 64)
	var left := KiwiImageLayer.create("paint", doc.canvas_size)
	var right := KiwiImageLayer.create("paint", doc.canvas_size)
	doc.layers.assign([left, right])
	var wood := doc.create_live_material(Library.create("wood/oak"))
	var denim := doc.create_live_material(Library.create("fabric/denim"))
	var left_mask := pixels(doc.canvas_size, Color(0, 0, 0, 0))
	left_mask.fill_rect(Rect2i(0, 0, 40, 64), Color.WHITE)
	var right_mask := pixels(doc.canvas_size, Color(0, 0, 0, 0))
	right_mask.fill_rect(Rect2i(56, 0, 40, 64), Color.WHITE)
	var left_region := doc.add_live_region(left, wood.id, ImageTexture.create_from_image(left_mask))
	doc.add_live_region(right, denim.id, ImageTexture.create_from_image(right_mask))
	# Native save must preserve negative/full-precision stamp coordinates. Packing
	# masks uses PNG, while coordinates retain their native floating-point image.
	var coordinate_image := Image.create(3, 2, false, Image.FORMAT_RGF)
	coordinate_image.fill(Color(-413.125, 762.375, 0, 1))
	left_region.coordinates = ImageTexture.create_from_image(coordinate_image)
	left_region.coordinate_rect = Rect2(.1, .2, .3, .4)
	var snapshot := doc.snapshot()
	snapshot.pack_live_material_textures()
	var path := "res://.godot/verification/live_coordinate_roundtrip.tres"
	check(ResourceSaver.save(snapshot, path) == OK, "Floating-point coordinates save in native document")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as KiwiImageDocument
	check(loaded != null and loaded.layers[0].live_paint[0].coordinates.get_image().get_data() == coordinate_image.get_data(), "Coordinate roundtrip retains exact signed float values")
	check(loaded != null and loaded.layers[0].live_paint[0].coordinate_rect == left_region.coordinate_rect, "Cropped coordinate rectangle survives save/load")
	left_region.coordinates = null
	if DisplayServer.get_name() == "headless":
		print("Live material cache model: %d checks, %d failures (GPU checks skipped)" % [checks, failures])
		quit(failures); return
	var renderer := KiwiImageRenderer.new()
	root.add_child(renderer)
	renderer.sync(doc)
	await frames()
	check(dormant(renderer, left) and dormant(renderer, right), "Static source/effect chains become dormant")
	var before := renderer.export_viewport.get_texture().get_image()
	check(before.get_pixel(20, 20).a > .99 and before.get_pixel(70, 20).a > .99, "Dormant caches retain real visible material output")
	var left_count := count(renderer, left); var right_count := count(renderer, right)
	await frames(4)
	check(count(renderer, left) == left_count and count(renderer, right) == right_count, "Unchanged layers execute zero further source passes")
	var edited := wood.material.copy_material()
	edited.parameters.primary = Color("18bd24")
	edited.parameters.secondary = Color("8dfa63")
	doc.set_live_material(wood.id, edited)
	renderer.sync(doc)
	check(not dormant(renderer, left) and dormant(renderer, right), "Template edit wakes only its owning layer")
	await frames()
	var after := renderer.export_viewport.get_texture().get_image()
	check(absf(after.get_pixel(20, 20).g-before.get_pixel(20, 20).g) > .1, "Template changes reach visible cached artwork")
	check(after.get_region(Rect2i(56, 0, 40, 64)).get_data() == before.get_region(Rect2i(56, 0, 40, 64)).get_data(), "Unrelated cached material stays pixel-identical")
	check(count(renderer, left) > left_count and count(renderer, right) == right_count, "Only affected layer rendered additional source passes")
	# Group composition and clipping both depend on the edited child source.
	var group := KiwiImageLayer.create("group", doc.canvas_size)
	left.parent_id = group.id
	var clipped := KiwiImageLayer.create("paint", doc.canvas_size)
	clipped.parent_id = group.id
	clipped.clip_to_below = true
	clipped.texture = ImageTexture.create_from_image(pixels(doc.canvas_size, Color.BLUE))
	doc.layers.assign([group, left, clipped, right])
	renderer.sync(doc)
	await frames()
	check(dormant(renderer, group) and dormant(renderer, clipped), "Group and clipping chains settle to cached output")
	var grouped := renderer.export_viewport.get_texture().get_image()
	check(grouped.get_pixel(20, 20).b > .99 and grouped.get_pixel(48, 20).a < .01, "Clip-to-below uses live source coverage inside group")
	right_count = count(renderer, right)
	var group_count := count(renderer, group); var clip_count := count(renderer, clipped)
	left_mask.fill_rect(Rect2i(0, 0, 24, 64), Color(0, 0, 0, 0))
	(left_region.coverage as ImageTexture).update(left_mask)
	renderer.invalidate_layer(left.id)
	check(not dormant(renderer, left) and not dormant(renderer, group) and not dormant(renderer, clipped), "In-place texture update wakes source, ancestor group and clip dependency")
	check(dormant(renderer, right), "In-place update leaves unrelated cached layer dormant")
	await frames()
	var erased := renderer.export_viewport.get_texture().get_image()
	check(erased.get_pixel(20, 20).a < .01 and erased.get_pixel(30, 20).b > .99, "Cached group and clip output follow changed coverage")
	check(count(renderer, group) > group_count and count(renderer, clipped) > clip_count and count(renderer, right) == right_count, "Dependent source-pass counts increase without unrelated work")
	# Ordinary raster paint also updates in place during a gesture.
	var top := right.texture.get_image()
	top.fill_rect(Rect2i(56, 0, 40, 64), Color.RED)
	(right.texture as ImageTexture).update(top)
	renderer.invalidate_layer(right.id)
	await frames()
	check(renderer.export_viewport.get_texture().get_image().get_pixel(70, 20).r > .99, "In-place raster gesture refreshes cached source")
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode unshaded; void fragment(){vec4 c=texture(TEXTURE,UV); COLOR=vec4(vec3(.5+.5*sin(TIME*6.0)),c.a);}"
	right.effects.append({"id":"clock", "type":"shader", "shader":shader, "enabled":true})
	renderer.sync(doc)
	await frames()
	check(not dormant(renderer, right) and dormant(renderer, left) and dormant(renderer, group), "TIME shader remains dynamic while static dependencies stay cached")
	right_count = count(renderer, right); left_count = count(renderer, left)
	var animated_samples: Array[float] = [renderer.export_viewport.get_texture().get_image().get_pixel(70, 20).r]
	for sample in 3:
		await create_timer(.11).timeout
		await frames(3)
		animated_samples.append(renderer.export_viewport.get_texture().get_image().get_pixel(70, 20).r)
	check(count(renderer, right) > right_count and count(renderer, left) == left_count, "Animated layer continuously renders without awakening static source")
	check(float(animated_samples.max())-float(animated_samples.min()) > .01, "TIME shader output actually animates after static cache settlement")
	right.effects[0].enabled = false
	renderer.sync(doc)
	await frames()
	check(dormant(renderer, right), "Disabling animated effect returns source to static cache")
	renderer.queue_free()
	await process_frame; await process_frame
	print("Live material cache: %d checks, %d failures" % [checks, failures])
	quit(failures)
