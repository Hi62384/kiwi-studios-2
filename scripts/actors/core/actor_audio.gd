class_name ActorAudio
extends RefCounted
## Shared source cache and source-time waveform envelopes.

static var sources: Dictionary = {}

static func source(value: Variant) -> AudioStream:
	if value is AudioStream: return value
	var path := str(value) if value != null else ""
	if path.is_empty() or not FileAccess.file_exists(path): return null
	if sources.has(path): return sources[path]
	var stream: AudioStream
	match path.get_extension().to_lower():
		"mp3": stream = AudioStreamMP3.load_from_file(path)
		"wav": stream = AudioStreamWAV.load_from_file(path)
		"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
		"flac":
			var encoder := ActorVideo.executable("ffmpeg")
			if encoder.is_empty(): return null
			var decoded := ProjectSettings.globalize_path("user://audio_cache/" + (path + str(FileAccess.get_modified_time(path))).sha256_text() + ".wav")
			DirAccess.make_dir_recursive_absolute(decoded.get_base_dir())
			if not FileAccess.file_exists(decoded):
				var output: Array = []
				if OS.execute(encoder, PackedStringArray(["-nostdin", "-v", "error", "-n", "-i", ProjectSettings.globalize_path(path), "-c:a", "pcm_s16le", decoded]), output) != 0: return null
			stream = AudioStreamWAV.load_from_file(decoded)
		_:
			var resource := ResourceLoader.load(path)
			if resource is AudioStream: stream = resource
	if stream != null: sources[path] = stream
	return stream

static func length(actor: ActorData) -> float:
	if actor.type_id in [&"video", &"video_2d"]: return ActorVideo.length(actor)
	var stream := source(actor.values.get(&"audio", ""))
	return stream.get_length() if stream != null else 0.0

static func fade_gain(actor: ActorData, clip: ActorClip, time: float) -> float:
	var fade_in := clampf(float(actor.values.get(&"fade_in", 0.0)), 0.0, clip.duration)
	var fade_out := clampf(float(actor.values.get(&"fade_out", 0.0)), 0.0, clip.duration)
	var gain := 1.0
	if fade_in > 0.0: gain = minf(gain, clampf((time - clip.start_time) / fade_in, 0.0, 1.0))
	if fade_out > 0.0: gain = minf(gain, clampf((clip.start_time + clip.duration - time) / fade_out, 0.0, 1.0))
	return gain

static func valid(actor: ActorData, clip: ActorClip, duration: float, offset: float) -> bool:
	if actor.type_id not in [&"audio", &"video", &"video_2d"]: return true
	if length(actor) == 0.0: return true
	return offset >= -0.000001 and offset + duration * clip.playback_speed <= length(actor) + 0.000001
