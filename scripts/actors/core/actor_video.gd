class_name ActorVideo
extends Node
## FFmpeg-backed, seekable preview cache. Originals are never rewritten.
## Decode ten-second windows on demand instead of expanding entire movies to images.
const EXTENSIONS := ["mp4", "mov", "mkv", "webm", "avi", "m4v", "ogv", "mpeg", "mpg", "wmv", "ts"]
const PREVIEW_FPS := 24.0
const WINDOW := 10.0
static var _instance: ActorVideo
static var _metadata: Dictionary = {}
static var _textures: Dictionary = {}
var _pending: Dictionary = {}
var _running: Dictionary = {}
var _completed: Dictionary = {}

static func executable(tool: String) -> String:
	var configured := str(ProjectSettings.get_setting("kiwi/media/" + tool + "_path", ""))
	if not configured.is_empty(): return configured
	for directory in OS.get_environment("PATH").split(";" if OS.get_name() == "Windows" else ":"):
		var candidate := directory.path_join(tool + (".exe" if OS.get_name() == "Windows" else ""))
		if FileAccess.file_exists(candidate): return candidate
	return ""

static func info(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path): return {}
	var key := path + ":" + str(FileAccess.get_modified_time(path))
	if _metadata.has(key): return _metadata[key]
	var probe := executable("ffprobe")
	if probe.is_empty(): return {}
	var output: Array = []
	var absolute := ProjectSettings.globalize_path(path)
	if OS.execute(probe, PackedStringArray(["-v", "error", "-show_format", "-show_streams", "-of", "json", absolute]), output) != 0: return {}
	var json: Variant = JSON.parse_string("".join(output))
	if not json is Dictionary: return {}
	var video: Dictionary = {}
	var audio := false
	for stream in json.get("streams", []):
		if stream.get("codec_type") == "video" and video.is_empty(): video = stream
		if stream.get("codec_type") == "audio": audio = true
	if video.is_empty(): return {}
	var duration := float(video.get("duration", json.get("format", {}).get("duration", 0.0)))
	if duration <= 0.0: duration = float(json.get("format", {}).get("duration", 0.0))
	if not is_finite(duration) or duration <= 0.0: return {}
	var directory := ProjectSettings.globalize_path("user://video_cache/" + key.sha256_text())
	DirAccess.make_dir_recursive_absolute(directory)
	var result := {"path": absolute, "duration": duration, "width": int(video.get("width", 1)), "height": int(video.get("height", 1)), "audio": audio, "directory": directory}
	_metadata[key] = result
	return result

static func length(actor: ActorData) -> float:
	return float(info(str(actor.values.get(&"video", ""))).get("duration", 0.0))

static func audio(path: String) -> AudioStreamWAV:
	var source := info(path)
	if source.is_empty() or not source.audio: return null
	var encoder := executable("ffmpeg")
	if encoder.is_empty(): return null
	var target: String = source.directory.path_join("audio.wav")
	if not FileAccess.file_exists(target):
		var output: Array = []
		if OS.execute(encoder, PackedStringArray(["-nostdin", "-v", "error", "-y", "-i", source.path, "-map", "0:a:0", "-vn", "-af", "apad,atrim=duration=" + str(source.duration), "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", target]), output) != 0: return null
	var stream := AudioStreamWAV.load_from_file(target)
	if stream != null: stream.resource_path = "" # Actor-owned audio survives cache removal/save.
	return stream

static func manager() -> ActorVideo:
	if not is_instance_valid(_instance):
		_instance = ActorVideo.new()
		(Engine.get_main_loop() as SceneTree).root.add_child(_instance)
	return _instance

static func frame(path: String, time: float, priority: bool = false) -> Texture2D:
	var source := info(path)
	if source.is_empty(): return null
	time = clampf(time, 0.0, maxf(0.0, float(source.duration) - 1.0 / PREVIEW_FPS))
	var window := int(time / WINDOW)
	var number := int((time - window * WINDOW) * PREVIEW_FPS) + 1
	var directory: String = source.directory.path_join("window_%d" % window)
	var filename := directory.path_join("%06d.jpg" % number)
	if _textures.has(filename): return _textures[filename]
	if FileAccess.file_exists(filename):
		var image := Image.load_from_file(filename)
		if image != null and not image.is_empty():
			if _textures.size() >= 192: _textures.erase(_textures.keys()[0])
			var texture := ImageTexture.create_from_image(image)
			_textures[filename] = texture
			return texture
	var worker := manager()
	if not worker._completed.has(directory) and not worker._running.has(directory):
		priority = priority or worker._pending.get(directory, {}).get("priority", false)
		if worker._pending.size() >= 32 and not worker._pending.has(directory): worker._pending.erase(worker._pending.keys()[0])
		worker._pending[directory] = {"source": source, "window": window, "priority": priority}
	return null

func _process(_delta: float) -> void:
	for directory in _running.keys():
		if not OS.is_process_running(_running[directory]):
			_running.erase(directory)
			_completed[directory] = true
	if _running.size() >= 2 or _pending.is_empty(): return
	var encoder := executable("ffmpeg")
	if encoder.is_empty(): _pending.clear(); return
	var directory: String = _pending.keys()[0]
	for key in _pending:
		if _pending[key].priority: directory = key; break
	var request: Dictionary = _pending[directory]
	_pending.erase(directory)
	DirAccess.make_dir_recursive_absolute(directory)
	var pid := OS.create_process(encoder, PackedStringArray(["-nostdin", "-v", "error", "-y", "-ss", str(request.window * WINDOW), "-i", request.source.path, "-t", str(WINDOW), "-an", "-vf", "fps=24,scale=720:-2", "-q:v", "4", "-atomic_writing", "1", directory.path_join("%06d.jpg")]), false)
	if pid > 0: _running[directory] = pid

func _exit_tree() -> void:
	for pid in _running.values():
		if OS.is_process_running(pid): OS.kill(pid)
	_running.clear()
	_pending.clear()
	_textures.clear()
