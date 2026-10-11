class_name ActorScreenRecorder
extends Node
## Windows capture uses FFmpeg GDI and an independent mic/loopback recorder.
var recording := false
var process: Dictionary = {}
var directory := ""
var output_path := ""
var audio_recorder: ActorAudioRecorder
var _audio_lead := 0.0
var last_error := ""

static func targets() -> Array[Dictionary]:
	var result: Array[Dictionary] = [{"label": "Entire desktop (all displays)", "input": "desktop", "category": "Entire display"}]
	var desktop := Rect2i()
	for screen in DisplayServer.get_screen_count():
		var area := Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
		desktop = area if screen == 0 else desktop.merge(area)
		result.append({"label": "Display %d" % (screen + 1), "input": "desktop", "category": "Entire display", "position": DisplayServer.screen_get_position(screen), "size": DisplayServer.screen_get_size(screen)})
	if desktop.has_area():
		result[0].position = desktop.position
		result[0].size = desktop.size
	if OS.get_name() == "Windows" and DisplayServer.get_name() != "headless":
		var output: Array = []
		OS.execute("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-Command", "@(Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } | Select-Object @{n='label';e={$_.MainWindowTitle}},@{n='input';e={'hwnd=' + $_.MainWindowHandle.ToInt64()}}) | ConvertTo-Json -Compress"]), output)
		var windows: Variant = JSON.parse_string("".join(output))
		if windows is Dictionary: windows = [windows]
		if windows is Array:
			for window in windows:
				if window is Dictionary:
					window.category = "Windows"
					result.append(window)
	return result

static func capture_arguments(target: Dictionary, fps: int, cursor: bool, resolution: int = 0) -> PackedStringArray:
	var arguments := PackedStringArray(["-hide_banner", "-loglevel", "error", "-n", "-f", "gdigrab", "-framerate", str(fps), "-draw_mouse", "1" if cursor else "0"])
	if target.has("position") and target.has("size"):
		arguments.append_array(PackedStringArray(["-offset_x", str(target.position.x), "-offset_y", str(target.position.y), "-video_size", "%dx%d" % [target.size.x, target.size.y]]))
	var filter := "pad=ceil(iw/2)*2:ceil(ih/2)*2"
	if resolution > 0: filter = "scale=-2:%d:flags=lanczos," % resolution + filter
	arguments.append_array(PackedStringArray(["-i", str(target.get("input", "desktop")), "-vf", filter, "-c:v", "libx264", "-preset", "ultrafast", "-crf", "16", "-pix_fmt", "yuv420p", "-movflags", "+frag_keyframe+empty_moov"]))
	return arguments

func start(options: Dictionary, target: Dictionary) -> String:
	if recording: return "Already recording."
	if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless": return "Screen recording requires the Windows desktop."
	var encoder := ActorVideo.executable("ffmpeg")
	if encoder.is_empty(): return "FFmpeg is required for screen recording."
	target = target.duplicate()
	if str(target.get("input", "")).begins_with("hwnd="):
		var bounds_output: Array = []
		var window_args := PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", ProjectSettings.globalize_path("res://scripts/actors/core/screen_capture_window.ps1"), "-WindowHandle", str(target.input).trim_prefix("hwnd=")])
		if target.has("tab_name"): window_args.append_array(PackedStringArray(["-TabName", target.tab_name]))
		OS.execute("powershell.exe", window_args, bounds_output)
		var bounds: Variant = JSON.parse_string("".join(bounds_output))
		if not bounds is Dictionary or bounds.width <= 0 or bounds.height <= 0: return "The selected window is no longer available."
		target.input = "desktop"
		target.position = Vector2i(bounds.x, bounds.y)
		target.size = Vector2i(bounds.width, bounds.height)
		var desktop := Rect2i()
		for screen in DisplayServer.get_screen_count():
			var area := Rect2i(DisplayServer.screen_get_position(screen), DisplayServer.screen_get_size(screen))
			desktop = area if screen == 0 else desktop.merge(area)
		var area := Rect2i(target.position, target.size).intersection(desktop)
		if not area.has_area(): return "The selected window is outside the visible desktop."
		target.position = area.position
		target.size = area.size
	directory = ProjectSettings.globalize_path("user://screen_recordings/" + ActorData.new_id())
	DirAccess.make_dir_recursive_absolute(directory)
	var audio_started := Time.get_ticks_msec()
	if options.record_mic or options.record_system or options.get("record_timeline", false):
		audio_recorder = ActorAudioRecorder.new()
		audio_recorder.preferences_override = options.duplicate()
		add_child(audio_recorder)
		var error: String = await audio_recorder.start()
		if not error.is_empty(): cleanup(); return error
		audio_started = Time.get_ticks_msec()
	var arguments := capture_arguments(target, int(options.get("screen_fps", 30)), bool(options.get("screen_cursor", true)), int(options.get("screen_resolution", 0)))
	output_path = directory.path_join("capture.mp4")
	arguments.append(output_path)
	process = OS.execute_with_pipe(encoder, arguments, false)
	if process.is_empty(): cleanup(); return "Screen capture could not start."
	var deadline := Time.get_ticks_msec() + 10000
	while OS.is_process_running(process.pid) and not FileAccess.file_exists(output_path) and Time.get_ticks_msec() < deadline:
		_drain_errors()
		await get_tree().process_frame
	if not OS.is_process_running(process.pid) or not FileAccess.file_exists(output_path):
		_drain_errors()
		var error := "Screen capture failed. " + last_error
		cleanup()
		return error
	_audio_lead = (Time.get_ticks_msec() - audio_started) / 1000.0
	recording = true
	return ""

func _drain_errors() -> void:
	if process.has("stderr"):
		var bytes: PackedByteArray = process.stderr.get_buffer(4096)
		if not bytes.is_empty(): last_error = (last_error + bytes.get_string_from_utf8()).right(2000)

func _process(_delta: float) -> void:
	_drain_errors()

func stop() -> String:
	if not recording: return ""
	recording = false
	if OS.is_process_running(process.pid): process.stdio.store_string("q\n")
	var deadline := Time.get_ticks_msec() + 10000
	while OS.is_process_running(process.pid) and Time.get_ticks_msec() < deadline:
		_drain_errors()
		await get_tree().process_frame
	if OS.is_process_running(process.pid): OS.kill(process.pid)
	process.clear()
	var audio: AudioStreamWAV
	if audio_recorder != null: audio = await audio_recorder.stop()
	if audio != null:
		var wav := directory.path_join("audio.wav")
		if audio.save_to_wav(wav) == OK:
			var merged := directory.path_join("recording.mp4")
			var args := PackedStringArray(["-nostdin", "-v", "error", "-n", "-i", output_path, "-ss", str(_audio_lead), "-i", wav, "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy", "-af", "apad", "-c:a", "aac", "-shortest", merged])
			var job := OS.execute_with_pipe(ActorVideo.executable("ffmpeg"), args, false)
			if not job.is_empty():
				process = job
				while OS.is_process_running(job.pid):
					job.stderr.get_buffer(4096)
					await get_tree().process_frame
				if OS.get_process_exit_code(job.pid) == 0 and FileAccess.file_exists(merged): output_path = merged
				process.clear()
			DirAccess.remove_absolute(wav)
	var result := output_path if not ActorVideo.info(output_path).is_empty() else ""
	cleanup()
	return result

func cleanup() -> void:
	recording = false
	if process.has("pid") and OS.is_process_running(process.pid): OS.kill(process.pid)
	process.clear()
	if is_instance_valid(audio_recorder):
		audio_recorder._cleanup()
		audio_recorder.queue_free()
	audio_recorder = null

func _exit_tree() -> void: cleanup()
