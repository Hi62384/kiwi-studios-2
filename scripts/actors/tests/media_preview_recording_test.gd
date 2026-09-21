extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var editor := ActorTimelineEditor.new()
	root.add_child(editor)
	var inspector := ActorInspector.new()
	root.add_child(inspector)
	inspector.setup(editor.model, editor.registry)
	var unique := ActorData.new_id()
	var png := "user://preview_" + unique + ".png"
	var copied := "user://preview_copy_" + unique + ".png"
	var converted := "user://preview_" + unique + ".webp"
	var wav_path := "user://preview_" + unique + ".wav"
	var video_path := "user://preview_" + unique + ".mp4"
	var bitmap := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	bitmap.fill(Color.TOMATO)
	bitmap.save_png(png)
	inspector.inspect_file_resource(png)
	var preview := inspector.fields.get_child(1) as ActorMediaPreview
	check(preview != null and preview.image.texture != null, "Image double-click inspection shows an image")
	inspector.refresh()
	check(inspector.fields.get_child(1) == preview, "File preview survives timeline refresh")
	var property := ActorProperty.create(&"image", "Image", "")
	property.options.extensions = ["png", "webp"]
	check(await ActorMediaExport.write_async(editor, png, copied, property), "Asynchronous same-format save succeeds")
	check(FileAccess.get_file_as_bytes(png) == FileAccess.get_file_as_bytes(copied), "Same-format save preserves original bytes")
	check(await ActorMediaExport.write_async(editor, png, converted, property), "Background image format conversion succeeds")
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 48000
	var bytes := PackedByteArray()
	bytes.resize(96000)
	audio.data = bytes
	audio.save_to_wav(wav_path)
	inspector.inspect_file_resource(wav_path)
	preview = inspector.fields.get_child(1)
	check(preview.player.stream != null and preview.duration > 0, "Audio inspection exposes playable audio")
	var log: Array = []
	var encoder := ActorVideo.executable("ffmpeg")
	check(OS.execute(encoder, PackedStringArray(["-nostdin", "-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=12", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "1", "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac", ProjectSettings.globalize_path(video_path)]), log, true) == 0, "Synthetic video fixture encodes")
	inspector.inspect_file_resource(video_path)
	preview = inspector.fields.get_child(1)
	var deadline := Time.get_ticks_msec() + 5000
	while (preview.image.texture == null or preview.player.stream == null) and Time.get_ticks_msec() < deadline: await process_frame
	check(preview.video and preview.image.texture != null, "Video inspection displays decoded frames")
	check(preview.player.stream != null, "Video inspection includes audio preview")
	preview.transport.pressed.emit()
	preview._process(0.2)
	check(preview.playing and preview.time >= 0.2, "Video preview transport advances independently")
	var clip := editor.model.create_actor(editor.registry.get_definition(&"audio"), 0, {&"audio": audio})
	editor.canvas.playhead = 0.1
	editor.playing = true
	editor._evaluate_runtimes()
	var actor := editor.model.actor_for_id(clip.actor_id)
	var previous := actor.animation_time
	check(editor.audio_system.players[clip.id].playing, "Normal playback starts timeline audio")
	editor.audio_recorder.recording = true
	editor.canvas.recording_preview = {"start": 0.1, "duration": 0.0, "layer": 1}
	editor._process(0.2)
	check(is_equal_approx(editor.canvas.playhead, 0.3), "Recording moves playhead")
	check(is_equal_approx(actor.animation_time, previous), "Recording does not evaluate actor animation")
	check(not editor.audio_system.players[clip.id].playing, "Recording stops timeline audio")
	editor.audio_recorder.recording = false
	editor.playing = false
	var viewport := SubViewport.new()
	root.add_child(viewport)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var holder := Node3D.new()
	viewport.add_child(holder)
	editor.runtime_holder = holder
	editor._pause_recording_scene(true)
	check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED and viewport.process_mode == Node.PROCESS_MODE_DISABLED, "Recording freezes scene rendering and node processing")
	editor._pause_recording_scene(false)
	check(viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS and viewport.process_mode == Node.PROCESS_MODE_INHERIT, "Stopping recording restores previous viewport modes")
	editor.runtime_holder = null
	viewport.free()
	check(ActorScreenRecorder.capture_arguments({"input": "desktop"}, 30, true, 2160).has("scale=-2:2160:flags=lanczos,pad=ceil(iw/2)*2:ceil(ih/2)*2"), "Capture resolution scales with preserved aspect ratio")
	inspector.free()
	editor.free()
	for path in [png, copied, converted, wav_path, video_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	await process_frame
	print("Media preview / recording isolation checks: %d failures" % failures)
	quit(failures)
