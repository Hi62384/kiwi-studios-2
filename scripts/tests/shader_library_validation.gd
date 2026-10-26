extends SceneTree
## Run with a graphics display and Forward+ to compile AND render every catalog entry.
## Example: Godot --path . --rendering-method forward_plus --script res://scripts/tests/shader_library_validation.gd
const Catalog = preload("res://Workspaces/ShaderWorkspace/library/shader_sample_catalog.gd")
const Preview = preload("res://Workspaces/ShaderWorkspace/shader_sample_preview.gd")
const OUTPUT := "res://.godot/verification/shader_library"
var _only_type := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--type="):
			_only_type = argument.trim_prefix("--type=")
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("Complete shader validation requires a graphics display and Forward+; headless is not compilation evidence.")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var preview := Preview.new()
	root.add_child(preview)
	await process_frame
	var all: Array[Dictionary] = Catalog.get_entries()
	if not _only_type.is_empty():
		all = all.filter(func(item: Dictionary) -> bool: return str(item.shader_type) == _only_type)
		if all.is_empty():
			push_error("Unknown shader type filter: " + _only_type)
			quit(2)
			return
	var results: Array[Dictionary] = []
	var ids := {}
	var sources := {}
	var failures := 0
	var sample_count := 0
	var template_count := 0
	var start_us := Time.get_ticks_usec()
	for item: Dictionary in all:
		var entry_errors := PackedStringArray()
		var id := str(item.id)
		var source := str(item.source)
		var elapsed_start := Time.get_ticks_usec()
		if ids.has(id): entry_errors.append("Duplicate stable id.")
		ids[id] = true
		if source.sha256_text() != str(item.get("source_sha256", "")):
			entry_errors.append("Source SHA-256 differs from catalog.")
		if str(item.description).is_empty() or str(item.targets).is_empty():
			entry_errors.append("Missing explanation or supported target.")
		var canonical := RegEx.create_from_string("(?m)//.*$").sub(source, "", true)
		canonical = RegEx.create_from_string("\\s+").sub(canonical, "", true)
		if not bool(item.template):
			sample_count += 1
			if sources.has(canonical): entry_errors.append("Duplicate complete sample code: " + str(sources[canonical]))
			sources[canonical] = id
		else:
			template_count += 1
		var error := preview.show_entry(item)
		if not error.is_empty(): entry_errors.append(error)
		# Allow asynchronous GPU compilation, sky radiance and particle preprocessing.
		for frame in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		error = preview.check_errors()
		if not error.is_empty() and not entry_errors.has(error): entry_errors.append(error)
		var screenshot := preview.get_texture().get_image()
		if screenshot == null or screenshot.is_empty():
			entry_errors.append("Viewport returned no actual rendered pixels.")
		else:
			var save_error := screenshot.save_png(OUTPUT.path_join(id + ".png"))
			if save_error != OK: entry_errors.append("Unable to save rendered evidence: %s" % save_error)
		preview.set_active(false)
		var row := {"id": id, "name": item.name, "type": item.shader_type, "template": item.template,
			"source_sha256": source.sha256_text(), "errors": Array(entry_errors),
			"elapsed_ms": (Time.get_ticks_usec() - elapsed_start) / 1000.0,
			"image": id + ".png", "status": "passed" if entry_errors.is_empty() else "failed"}
		results.append(row)
		if not entry_errors.is_empty(): failures += 1
		print("SHADER_VALIDATION %d/%d %s %s" % [results.size(), all.size(), row.status, id])
		for message in entry_errors: print(message)
		# Write incremental results so interruption cannot masquerade as completion.
		_write_report(results, sample_count, template_count, failures, start_us, false)
	if _only_type.is_empty() and (sample_count < 100 or template_count < 20):
		failures += 1
	_write_report(results, sample_count, template_count, failures, start_us, true)
	preview.queue_free()
	await process_frame
	print("SHADER_LIBRARY_RESULT samples=%d templates=%d failures=%d" % [sample_count, template_count, failures])
	quit(0 if failures == 0 else 1)

func _write_report(results: Array[Dictionary], samples: int, templates: int, failures: int, start_us: int, complete: bool) -> void:
	var report := {"complete": complete, "type_filter": _only_type, "engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(),
		"video_adapter": RenderingServer.get_video_adapter_name(), "driver": RenderingServer.get_current_rendering_driver_name(),
		"samples": samples, "templates": templates, "failures": failures,
		"elapsed_ms": (Time.get_ticks_usec() - start_us) / 1000.0, "results": results}
	var file_name := "report.json" if _only_type.is_empty() else "report_" + _only_type + ".json"
	var file := FileAccess.open(OUTPUT.path_join(file_name), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
