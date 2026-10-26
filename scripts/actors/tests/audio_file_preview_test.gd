extends SceneTree
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void: run.call_deferred()

func wav(path: String, bits: int, format: int, data: PackedByteArray) -> void:
	var bytes := PackedByteArray(); bytes.resize(44)
	for i in 4: bytes[i] = "RIFF".unicode_at(i); bytes[8 + i] = "WAVE".unicode_at(i); bytes[12 + i] = "fmt ".unicode_at(i); bytes[36 + i] = "data".unicode_at(i)
	bytes.encode_u32(4, 36 + data.size()); bytes.encode_u32(16, 16)
	bytes.encode_u16(20, format); bytes.encode_u16(22, 1); bytes.encode_u32(24, 8000)
	bytes.encode_u32(28, 8000 * (bits / 8)); bytes.encode_u16(32, bits / 8); bytes.encode_u16(34, bits); bytes.encode_u32(40, data.size())
	bytes.append_array(data)
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_buffer(bytes); file.close()

func read(path: String, at: int, count: int) -> PackedVector2Array:
	var info := KiwiAudioPCMFile.inspect(path)
	if not str(info.get("error", "invalid")).is_empty(): return PackedVector2Array()
	var file := FileAccess.open(path, FileAccess.READ)
	var result := KiwiAudioPCMFile.read_frames(file, info, at, count); file.close(); return result

func run() -> void:
	var directory := "user://pcm_reader_" + ActorData.new_id()
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join("eight.wav")
	wav(path, 8, 1, PackedByteArray([0, 128, 255]))
	var info := KiwiAudioPCMFile.inspect(path)
	check(info.error.is_empty() and info.frames == 3 and info.channels == 1, "RIFF metadata counts frames without loading all PCM")
	var samples := read(path, 0, 3)
	check(samples.size() == 3 and samples[0] == Vector2(-1, -1) and samples[1] == Vector2.ZERO and is_equal_approx(samples[2].x, 127.0 / 128), "Raw PCM8 is unsigned and mono duplicates both channels")
	var sixteen := PackedByteArray(); sixteen.resize(6); sixteen.encode_s16(0, -32768); sixteen.encode_s16(2, 16384); sixteen.encode_s16(4, 32767)
	path = directory.path_join("sixteen.wav"); wav(path, 16, 1, sixteen)
	samples = read(path, 1, 2)
	check(samples.size() == 2 and samples[0] == Vector2(0.5, 0.5), "Frame seeking reads only the requested PCM16 window")
	check(read(path, 3, 2).is_empty(), "Reading beyond the data boundary returns no frames")
	path = directory.path_join("twentyfour.wav"); wav(path, 24, 1, PackedByteArray([0, 0, 128, 255, 255, 127]))
	samples = read(path, 0, 2)
	check(samples.size() == 2 and samples[0] == Vector2(-1, -1) and samples[1].x > 0.999, "PCM24 sign extension preserves negative and positive full scale")
	var floats := PackedByteArray(); floats.resize(8); floats.encode_float(0, 0.25); floats.encode_float(4, NAN)
	path = directory.path_join("float.wav"); wav(path, 32, 3, floats)
	samples = read(path, 0, 2)
	check(samples.size() == 2 and samples[0] == Vector2(0.25, 0.25) and samples[1] == Vector2.ZERO, "Float PCM sanitizes nonfinite samples")
	var envelope := KiwiAudioSourceCache.build_file_envelope(path, KiwiAudioPCMFile.inspect(path))
	check(not envelope.levels.is_empty() and envelope.bytes < 1024, "File-backed waveform envelopes use bounded chunk PCM")
	var actor := ActorData.new(); actor.id = ActorData.new_id(); actor.type_id = &"audio"; actor.values = {&"audio": path}
	check(is_equal_approx(ActorAudio.file_duration(path), 2.0 / 8000.0), "Shared duration service can inspect PCM without resource decode")
	var header := PackedByteArray(); header.resize(42)
	for i in 4: header[i] = "fLaC".unicode_at(i)
	header[4] = 128; header[7] = 34
	var rate := 44100; var frames := 88200
	header[18] = rate >> 12; header[19] = (rate >> 4) & 255; header[20] = ((rate & 15) << 4) | 2
	header[21] = (15 << 4) | ((frames >> 32) & 15)
	header[22] = (frames >> 24) & 255; header[23] = (frames >> 16) & 255; header[24] = (frames >> 8) & 255; header[25] = frames & 255
	path = directory.path_join("metadata.flac")
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_buffer(header); file.close()
	check(ActorAudio._flac_pcm_bytes(path) == frames * 4, "FLAC PCM guard reads STREAMINFO fields rather than MD5 bytes")
	check(is_equal_approx(ActorAudio.file_duration(path), 2.0), "FLAC duration is metadata-only; fake payload is never decoded")
	for name in DirAccess.open(directory).get_files(): DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	print("AUDIO_FILE_PREVIEW checks=%d failures=%d" % [checks, failures])
	quit(failures)
