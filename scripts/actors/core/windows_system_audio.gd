class_name WindowsSystemAudio
extends Node
## Out-of-process WASAPI capture; temporary files are confined to a unique session directory.
var pid := -1
var directory := ""
var rate := 48000
var _cursor := 44

func start() -> String:
	if OS.get_name() != "Windows": return "System audio recording currently requires Windows."
	directory = ProjectSettings.globalize_path("user://audio_capture_" + ActorData.new_id())
	DirAccess.make_dir_recursive_absolute(directory)
	for filename in ["windows_loopback.ps1", "windows_loopback.cs"]:
		var source := FileAccess.get_file_as_string("res://scripts/actors/audio/" + filename)
		var target := FileAccess.open(directory.path_join(filename), FileAccess.WRITE)
		if target == null: return "Cannot prepare the system audio recorder."
		target.store_string(source)
		target.close()
	pid = OS.create_process("powershell.exe", PackedStringArray(["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", directory.path_join("windows_loopback.ps1"), "-Source", directory.path_join("windows_loopback.cs"), "-Output", directory.path_join("capture.wav"), "-Stop", directory.path_join("stop"), "-Ready", directory.path_join("ready")]), false)
	var deadline := Time.get_ticks_msec() + 15000
	while pid > 0 and OS.is_process_running(pid) and not FileAccess.file_exists(directory.path_join("ready")) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	var ready := FileAccess.get_file_as_string(directory.path_join("ready")) if FileAccess.file_exists(directory.path_join("ready")) else ""
	if not ready.begins_with("READY:"):
		cleanup()
		return "System audio capture could not start. " + ready
	rate = int(ready.trim_prefix("READY:"))
	_cursor = 44
	return ""

func samples() -> PackedVector2Array:
	var result := PackedVector2Array()
	var file := FileAccess.open(directory.path_join("capture.wav"), FileAccess.READ)
	if file == null: return result
	file.seek(_cursor)
	var bytes := file.get_buffer(mini(262144, maxi(0, file.get_length() - _cursor)))
	for index in bytes.size() / 4:
		result.append(Vector2(bytes.decode_s16(index * 4), bytes.decode_s16(index * 4 + 2)) / 32768.0)
	_cursor += (bytes.size() / 4) * 4
	return result

func stop() -> AudioStreamWAV:
	request_stop()
	var deadline := Time.get_ticks_msec() + 4000
	while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline: await get_tree().process_frame
	var stream := AudioStreamWAV.load_from_file(directory.path_join("capture.wav")) if FileAccess.file_exists(directory.path_join("capture.wav")) else null
	cleanup()
	return stream

func request_stop() -> void:
	if directory.is_empty(): return
	var file := FileAccess.open(directory.path_join("stop"), FileAccess.WRITE)
	if file != null: file.close()

func cleanup() -> void:
	if pid > 0 and OS.is_process_running(pid): OS.kill(pid)
	pid = -1
	if not directory.is_empty():
		for file in ["windows_loopback.ps1", "windows_loopback.cs", "ready", "stop", "capture.wav"]:
			DirAccess.remove_absolute(directory.path_join(file))
		DirAccess.remove_absolute(directory)
	directory = ""

func _exit_tree() -> void:
	request_stop()
	cleanup()
