extends SceneTree
## Real-renderer benchmark: script synchronization, submitted-frame wall time,
## and Godot's measured viewport CPU/GPU times are reported separately.
const Library = preload("res://Workspaces/ImageWorkspace/texture_material_library.gd")
var results: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func viewport_count(node: Node) -> int:
	var count := 1 if node is SubViewport else 0
	for child in node.get_children(): count += viewport_count(child)
	return count

func measured_viewports(node: Node) -> Array[SubViewport]:
	var result: Array[SubViewport] = []
	if node is SubViewport: result.append(node)
	for child in node.get_children(): result.append_array(measured_viewports(child))
	return result

func coverage_hashes(document: KiwiImageDocument) -> Dictionary:
	var result: Dictionary = {}
	for layer in document.layers:
		for region in layer.live_paint:
			if region.coverage != null:
				result[layer.id+"/"+region.id] = hash(region.coverage.get_image().get_data())
	return result

func valid_readback(image: Image, extent: Vector2i) -> bool:
	if image == null or image.get_size() != extent or not image.get_used_rect().has_area(): return false
	for row in 2:
		for column in 3:
			var sample := image.get_pixel((column*2+1)*extent.x/6, (row*2+1)*extent.y/4)
			if absf(sample.a-.8) > .025: return false
	return true

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Benchmark requires real rendering; headless measurements are invalid.")
		quit(1); return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var adaptive_only := OS.get_cmdline_user_args().has("--adaptive-only")
	var output_path := "res://.godot/verification/live_material_benchmark_adaptive.json" if adaptive_only else "res://.godot/verification/live_material_benchmark.json"
	var workloads: Array = [[Vector2i(1280, 720), false], [Vector2i(2048, 2048), false], [Vector2i(4096, 4096), false], [Vector2i(4096, 4096), true]]
	if adaptive_only: workloads = [[Vector2i(4096, 4096), true]]
	for workload in workloads:
		var extent: Vector2i = workload[0]
		var adaptive: bool = workload[1]
		var document := KiwiImageDocument.new()
		document.canvas_size = extent
		var materials: Array = []
		for id in ["wood/oak", "fabric/denim", "stone/marble"]:
			var material := Library.create(id)
			material.texture_size = 128
			material.relief = .2
			materials.append(document.create_live_material(material))
		for layer_index in 2:
			var layer := KiwiImageLayer.create("paint", extent)
			document.layers.append(layer)
			for material_index in 3:
				var mask := Image.create(extent.x, extent.y, false, Image.FORMAT_RGBA8)
				mask.fill(Color(0, 0, 0, 0))
				mask.fill_rect(Rect2i(material_index*extent.x/3, layer_index*extent.y/2,
					extent.x/3, extent.y/2), Color(1, 1, 1, .8))
				document.add_live_region(layer, materials[material_index].id, ImageTexture.create_from_image(mask))
		var renderer := KiwiImageRenderer.new()
		root.add_child(renderer)
		if adaptive:
			renderer.set_interactive_preview(true)
			renderer.set_preview_camera(Vector2(2048, 2048), Vector2.ZERO, .5)
		renderer.sync(document)
		var rendered_extent := Vector2i(2048, 2048) if adaptive else extent
		var measured := measured_viewports(renderer)
		for surface in measured: RenderingServer.viewport_set_measure_render_time(surface.get_viewport_rid(), true)
		for frame in 15: await RenderingServer.frame_post_draw
		var before_viewports := viewport_count(renderer)
		var original_coverage_hashes := coverage_hashes(document)
		var before_image := renderer.export_viewport.get_texture().get_image()
		if not valid_readback(before_image, rendered_extent):
			push_error("Benchmark shader output is missing or has incorrect coverage.")
			renderer.queue_free(); await process_frame; quit(1); return
		var sync_usec := 0
		var frame_times: Array[float] = []
		var gpu_sum := 0.0; var render_cpu_sum := 0.0
		for frame in 24:
			var material: KiwiTextureMaterial = materials[0].material.copy_material()
			material.parameters.contrast = .8 + float(frame % 8)*.1
			var started := Time.get_ticks_usec()
			document.set_live_material(materials[0].id, material)
			renderer.sync(document)
			sync_usec += Time.get_ticks_usec() - started
			# Disabled viewports retain their last timing sample. Exclude them so
			# cached layers do not contribute stale GPU work to this frame.
			var active_surfaces: Array[SubViewport] = []
			for surface in measured:
				if surface.render_target_update_mode != SubViewport.UPDATE_DISABLED: active_surfaces.append(surface)
			await RenderingServer.frame_post_draw
			frame_times.append((Time.get_ticks_usec()-started)/1000.0)
			for surface in active_surfaces:
				gpu_sum += RenderingServer.viewport_get_measured_render_time_gpu(surface.get_viewport_rid())
				render_cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(surface.get_viewport_rid())
		frame_times.sort()
		var sum := 0.0
		for duration in frame_times: sum += duration
		var stable := original_coverage_hashes == coverage_hashes(document)
		for frame in 15: await RenderingServer.frame_post_draw
		var after_image := renderer.export_viewport.get_texture().get_image()
		var valid_output := valid_readback(after_image, rendered_extent)
		var changed := valid_output and hash(before_image.get_data()) != hash(after_image.get_data())
		var record := {"size":str(extent), "layers":2, "regions":6, "templates":3,
			"preview_mode":"adaptive_interactive" if adaptive else "native", "render_scale":renderer.render_scale, "rendered_extent":str(rendered_extent),
			"renderer":RenderingServer.get_current_rendering_method(), "frames":24,
			"mean_sync_cpu_ms":sync_usec/24000.0, "mean_rendered_frame_wall_ms":sum/24.0,
			"median_rendered_frame_wall_ms":frame_times[12], "p95_rendered_frame_wall_ms":frame_times[22],
			"mean_viewport_gpu_ms":gpu_sum/24.0, "mean_viewport_render_cpu_ms":render_cpu_sum/24.0,
			"gpu_timestamps_available":gpu_sum>0.0,
			"viewports_before":before_viewports, "viewports_after":viewport_count(renderer),
			"coverage_regions_checked":original_coverage_hashes.size(), "coverage_unchanged":stable,
			"valid_rendered_output":valid_output, "parameter_changed_rendered_pixels":changed}
		results.append(record)
		print("LIVE_MATERIAL_BENCHMARK ", JSON.stringify(record))
		var partial := FileAccess.open(output_path, FileAccess.WRITE)
		partial.store_string(JSON.stringify(results, "\t")); partial.close()
		if not stable or not valid_output or not changed or before_viewports != viewport_count(renderer):
			push_error("Live edits changed coverage, failed to render, or allocated extra persistent viewports.")
			renderer.queue_free(); await process_frame; quit(1); return
		renderer.queue_free()
		await process_frame; await process_frame
	var output := FileAccess.open(output_path, FileAccess.WRITE)
	output.store_string(JSON.stringify(results, "\t"))
	output.close()
	quit(0)
