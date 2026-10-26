extends SceneTree
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	print("PASS " if condition else "FAIL ", message)
	if not condition: failures += 1; push_error(message)

func _initialize() -> void: run.call_deferred()

func wait_jobs(workspace: KiwiAudioWorkspace) -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while workspace.jobs.busy() and Time.get_ticks_msec() < deadline: await process_frame
	check(not workspace.jobs.busy(), "Background job finishes within the bounded smoke deadline")
	await process_frame

func run() -> void:
	root.size = Vector2i(1440, 960); root.gui_embed_subwindows = true; root.title = "Kiwi Audio Workspace verification"
	# Keep this verification process's physical output quiet; upstream capture
	# still measures the real native mixer. No system/user-app volume changes.
	AudioServer.set_bus_volume_db(0, -18.0)
	var workspace := KiwiAudioWorkspace.new(); root.add_child(workspace); await process_frame
	check(workspace._automation_mode.size.y < 60 and workspace.play_button.size.y < 60, "Transport and automation rows remain compact in the native layout")
	var samples := PackedVector2Array(); samples.resize(44100)
	for i in samples.size(): samples[i] = Vector2(sin(TAU * 440.0 * i / 44100.0), sin(TAU * 660.0 * i / 44100.0)) * 0.1
	var source := KiwiAudioSourceCache.to_wav(samples)
	workspace.open_source(KiwiAudioDocument.from_source(source, "Native audio workflow")); await process_frame
	var directory := "user://native_audio_" + ActorData.new_id(); DirAccess.make_dir_recursive_absolute(directory)
	var composition := directory.path_join("composition.tres")
	check(KiwiAudioWorkspace.save_document(workspace.session.document, composition) == OK, "Native composition saves")
	var loaded := ResourceLoader.load(composition, "", ResourceLoader.CACHE_MODE_IGNORE) as KiwiAudioDocument
	check(loaded != null and loaded.clips.size() == 1 and loaded.title == "Native audio workflow", "Saved native composition reopens with its audio clip")
	if loaded == null: workspace.queue_free(); await process_frame; quit(failures); return
	workspace.open_source(loaded); await process_frame
	var output := directory.path_join("mix.wav")
	workspace._start_render(output, {"sample_rate": 44100, "bit_depth": 16}, "export"); await wait_jobs(workspace)
	var info := KiwiAudioPCMFile.inspect(output)
	check(str(info.get("error", "missing")).is_empty() and absf(float(info.get("duration", 0.0)) - 1.0) < 0.01, "Real WAV export has a matching PCM header and duration")
	var before := FileAccess.get_file_as_bytes(output)
	workspace._start_render(output, {"sample_rate": 44100, "bit_depth": 16}, "export"); await wait_jobs(workspace)
	check(FileAccess.get_file_as_bytes(output) == before, "Repeated export preserves existing destination bytes")
	for child in workspace.get_children():
		if child is AcceptDialog: child.queue_free()
	var capture := AudioEffectCapture.new(); capture.buffer_length = 0.5
	var bus := AudioServer.get_bus_index(workspace.playback._exact_bus)
	AudioServer.add_bus_effect(bus, capture)
	var released: Array[String] = []
	workspace.playback.preview_file_released.connect(func(path: String): released.append(path))
	workspace.render_preview(); await wait_jobs(workspace)
	check(workspace.playback.file_preview.active and workspace.playback.exact_preview.stream == null, "Rendered preview uses bounded file playback rather than whole-WAV resource loading")
	var prime_deadline := Time.get_ticks_msec() + 5000
	while workspace.playback.file_preview.active and workspace.playback.file_preview._priming and Time.get_ticks_msec() < prime_deadline: await process_frame
	check(workspace.playback.file_preview.active and not workspace.playback.file_preview._priming, "Background PCM reader primes its bounded native buffer")
	await create_timer(0.12).timeout
	var captured := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	for sample in captured: peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
	check(captured.size() > 0 and peak > 0.01, "Native audio mixer receives non-silent file-backed PCM")
	for at in [0.4, 0.6, 0.2]:
		workspace.playback.seek(at)
		prime_deadline = Time.get_ticks_msec() + 5000
		while workspace.playback.file_preview.active and workspace.playback.file_preview._priming and Time.get_ticks_msec() < prime_deadline: await process_frame
		await create_timer(0.04).timeout
		print("FILE_SEEK target=%.2f active=%s position=%.5f error=%s" % [at, workspace.playback.file_preview.active, workspace.playback.position, workspace.playback.file_preview._last_error])
		check(workspace.playback.file_preview.active and workspace.playback.position >= at - 0.01 and workspace.playback.position < at + 0.35, "Repeated file preview seek resumes within the prepared range")
	workspace.stop()
	var close_deadline := Time.get_ticks_msec() + 5000
	while workspace.playback.file_preview._readers.size() > 0 and Time.get_ticks_msec() < close_deadline: await process_frame
	check(not workspace.playback.file_preview.active and not released.is_empty(), "Stop closes file playback and releases owned preview paths")
	for path in released: check(not FileAccess.file_exists(path), "Released temporary preview is removed after closing its file handle")
	if DisplayServer.get_name() != "headless":
		await process_frame; await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var screenshot := ProjectSettings.globalize_path("res://.godot/verification/audio_authorized_execution/native_audio_workspace.png")
		check(image != null and image.save_png(screenshot) == OK, "Native workspace viewport screenshot saved")
	workspace.queue_free(); await process_frame; await create_timer(0.05).timeout
	for name in DirAccess.open(directory).get_files(): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	print("AUDIO_NATIVE_WORKFLOW checks=%d failures=%d renderer=%s driver=%s" % [checks, failures, DisplayServer.get_name(), AudioServer.get_driver_name()])
	quit(failures)
