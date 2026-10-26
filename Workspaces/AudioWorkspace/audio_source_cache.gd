class_name KiwiAudioSourceCache
extends Node
## Bounded asynchronous multiresolution envelopes. Scrolling never re-decodes audio.
signal waveform_ready(key: String)
const MAX_CACHE_BYTES := 48 * 1024 * 1024
const MAX_WORKERS := 2
const MAX_DECODE_BYTES := 128 * 1024 * 1024
var entries: Dictionary = {}
var _jobs: Dictionary = {}
var _pending: Dictionary = {}
var _generation: int = 0

static func identity(stream: AudioStream) -> String:
	return str(stream.get_instance_id()) if stream != null else ""

static func decode(stream: AudioStream, rate: int = 44100, start: float = 0.0, duration: float = -1.0, limit_seconds: float = 300.0) -> Dictionary:
	var empty := {"samples": PackedVector2Array(), "rate": rate, "error": ""}
	if stream == null:
		empty.error = "Missing or unreadable audio source."
		return empty
	rate = clampi(rate, 8000, 192000)
	start = maxf(0, start)
	var length := maxf(0, stream.get_length() - start)
	if duration >= 0: length = minf(length, duration)
	if not is_finite(length) or length > limit_seconds:
		empty.error = "This operation is limited to %.0f seconds per region; select a smaller region or use the streaming renderer." % limit_seconds
		return empty
	var count := int(round(length * rate))
	if count <= 0: return empty
	if count > MAX_DECODE_BYTES / 8:
		empty.error = "This sample-edit region exceeds the 128 MiB working-buffer limit; select a shorter region or use streaming export."
		return empty
	var samples := PackedVector2Array()
	samples.resize(count)
	# Read uncompressed WAV without resampling when exact samples are requested.
	if stream is AudioStreamWAV and stream.mix_rate == rate and stream.format in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS]:
		var bytes: PackedByteArray = stream.data
		var channels := 2 if stream.stereo else 1
		var width := 2 if stream.format == AudioStreamWAV.FORMAT_16_BITS else 1
		var first := int(round(start * rate))
		count = mini(count, maxi(0, bytes.size() / (width * channels) - first))
		samples.resize(count)
		for frame in count:
			var offset := (first + frame) * channels * width
			var left := float(bytes.decode_s16(offset)) / 32768.0 if width == 2 else float(int(bytes[offset]) if bytes[offset] < 128 else int(bytes[offset]) - 256) / 128.0
			var right := left
			if channels == 2: right = float(bytes.decode_s16(offset + width)) / 32768.0 if width == 2 else float(int(bytes[offset + width]) if bytes[offset + width] < 128 else int(bytes[offset + width]) - 256) / 128.0
			samples[frame] = Vector2(left, right)
	else:
		var playback := stream.instantiate_playback()
		if playback == null:
			empty.error = "The audio decoder could not be initialized."
			return empty
		playback.start(start)
		var cursor := 0
		while cursor < count:
			var chunk := playback.mix_audio(AudioServer.get_mix_rate() / float(rate), mini(8192, count - cursor))
			if chunk.is_empty(): break
			for sample in chunk:
				if cursor >= count: break
				samples[cursor] = Vector2(sample.x if is_finite(sample.x) else 0.0, sample.y if is_finite(sample.y) else 0.0)
				cursor += 1
		playback.stop()
		samples.resize(cursor)
	return {"samples": samples, "rate": rate, "error": ""}

static func to_wav(samples: PackedVector2Array, rate: int = 44100, stereo: bool = true) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = clampi(rate, 8000, 192000)
	stream.stereo = stereo
	var channels := 2 if stereo else 1
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * channels * 2)
	# Decode divides signed PCM16 by 32768; use the inverse scale so an
	# untouched channel or copied sample survives an edit without one-LSB loss.
	for index in samples.size():
		var sample := samples[index]
		var left := sample.x if stereo else (sample.x + sample.y) * 0.5
		if not is_finite(left): left = 0
		bytes.encode_s16(index * channels * 2, clampi(int(round(left * 32768.0)), -32768, 32767))
		if stereo:
			var right := sample.y if is_finite(sample.y) else 0.0
			bytes.encode_s16(index * 4 + 2, clampi(int(round(right * 32768.0)), -32768, 32767))
	stream.data = bytes
	return stream

func request(stream: AudioStream) -> Dictionary:
	if stream == null: return {}
	return _request_value(stream, identity(stream))

## A paused timeline asks for its cached envelope by file revision before it
## requests a stream. Large weak-only PCM is not reopened on every redraw.
## A miss is loaded on the envelope worker, never in the canvas draw callback.
func request_source(value: Variant) -> Dictionary:
	if value is AudioStream: return request(value)
	var stamp := ActorAudio.source_stamp(value)
	if bool(stamp.missing): return {"missing": true}
	return _request_value(value, str(stamp.key))

func _request_value(value: Variant, key: String) -> Dictionary:
	if key.is_empty(): return {}
	if entries.has(key):
		var entry: Dictionary = entries[key]
		if not bool(entry.get("missing", false)) or Time.get_ticks_msec() < int(entry.get("retry_after", 0)):
			entry.used = Time.get_ticks_msec()
			return entry
		# A metadata invalidation racing a decoder may transiently return null.
		# Do not pin that failure forever under an otherwise unchanged file key.
		entries.erase(key)
	if not _jobs.has(key): _pending[key] = value
	return {}

func invalidate(stream: AudioStream = null) -> void:
	# A completed in-flight envelope must not republish after invalidation.
	_generation += 1
	if stream == null:
		entries.clear()
		_pending.clear()
		for pending_job in _jobs.values(): pending_job.token.cancel()
	else:
		var key := identity(stream)
		entries.erase(key)
		_pending.erase(key)
		if _jobs.has(key): _jobs[key].token.cancel()

func _process(_delta: float) -> void:
	for key in _jobs.keys():
		var job: Dictionary = _jobs[key]
		var thread: Thread = job.thread
		if thread.is_alive(): continue
		var result: Dictionary = thread.wait_to_finish()
		_jobs.erase(key)
		var current := true
		if not job.source is AudioStream:
			var stamp := ActorAudio.source_stamp(job.source)
			current = not bool(stamp.missing) and str(stamp.key) == key
		if int(job.generation) == _generation and current and not bool(result.get("cancelled", false)):
			result.used = Time.get_ticks_msec()
			entries[key] = result
			_evict()
			waveform_ready.emit(key)
	while _jobs.size() < MAX_WORKERS and not _pending.is_empty():
		var key: String = _pending.keys()[0]
		var value: Variant = _pending[key]
		_pending.erase(key)
		var thread := Thread.new()
		var token := KiwiAudioJobs.Work.new()
		if thread.start(_build_source_envelope.bind(value, key, token)) == OK:
			_jobs[key] = {"thread": thread, "generation": _generation, "token": token, "source": value}

static func _build_source_envelope(value: Variant, key: String, token: RefCounted) -> Dictionary:
	if token.is_cancelled(): return {"cancelled": true}
	if not value is AudioStream:
		var stamp := ActorAudio.source_stamp(value)
		if bool(stamp.missing) or str(stamp.key) != key: return {"cancelled": true}
		if str(value).get_extension().to_lower() == "wav":
			var info := ActorAudio.pcm_info(str(value))
			if str(info.get("error", "invalid")).is_empty(): return build_file_envelope(str(value), info, token)
	var stream := ActorAudio.source(value, token)
	if token.is_cancelled(): return {"cancelled": true}
	if stream == null: return {"missing": true, "levels": [], "bytes": 0, "retry_after": Time.get_ticks_msec() + 2000}
	return build_envelope(stream, token)

func _evict() -> void:
	var total := 0
	for entry in entries.values(): total += int(entry.get("bytes", 0))
	while total > MAX_CACHE_BYTES and entries.size() > 1:
		var oldest: String = entries.keys()[0]
		for key in entries:
			if int(entries[key].used) < int(entries[oldest].used): oldest = key
		total -= int(entries[oldest].get("bytes", 0))
		entries.erase(oldest)

static func build_envelope(stream: AudioStream, token: RefCounted = null) -> Dictionary:
	var rate := int(AudioServer.get_mix_rate())
	var seconds := stream.get_length() if stream != null else 0.0
	if seconds <= 0 or not is_finite(seconds): return {"levels": [], "rate": rate, "stride": 256, "duration": 0, "bytes": 0}
	# At most 262144 finest bins (~4 MB stereo min/max) for arbitrarily long files.
	var stride := maxi(256, ceili(seconds * rate / 262144.0))
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var playback := stream.instantiate_playback()
	if playback == null: return {"levels": [], "rate": rate, "stride": stride, "duration": seconds, "bytes": 0}
	playback.start()
	var low := Vector2.ONE
	var high := -Vector2.ONE
	var frames := 0
	var cursor := 0
	var total := int(seconds * rate)
	while cursor < total:
		if token != null and token.is_cancelled():
			playback.stop()
			return {"levels": [], "rate": rate, "duration": seconds, "bytes": 0, "cancelled": true}
		var samples := playback.mix_audio(1.0, mini(16384, total - cursor))
		if samples.is_empty(): break
		for sample in samples:
			low = low.min(sample)
			high = high.max(sample)
			frames += 1
			cursor += 1
			if frames == stride:
				left.append(Vector2(low.x, high.x))
				right.append(Vector2(low.y, high.y))
				frames = 0
				low = Vector2.ONE
				high = -Vector2.ONE
	if frames > 0:
		left.append(Vector2(low.x, high.x))
		right.append(Vector2(low.y, high.y))
	playback.stop()
	return _envelope_levels(left, right, stride, rate, seconds)

static func build_file_envelope(path: String, info: Dictionary, token: RefCounted = null) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"missing": true, "levels": [], "bytes": 0}
	var total := int(info.frames); var rate := int(info.rate)
	var stride := maxi(256, ceili(float(total) / 262144.0))
	var left := PackedVector2Array(); var right := PackedVector2Array()
	var low := Vector2.ONE; var high := -Vector2.ONE
	var cursor := 0; var frames := 0
	while cursor < total:
		if token != null and token.is_cancelled(): file.close(); return {"cancelled": true}
		var samples := KiwiAudioPCMFile.read_frames(file, info, cursor, mini(16384, total - cursor))
		if samples.is_empty(): file.close(); return {"missing": true, "levels": [], "bytes": 0}
		for sample in samples:
			low = low.min(sample); high = high.max(sample); frames += 1; cursor += 1
			if frames == stride:
				left.append(Vector2(low.x, high.x)); right.append(Vector2(low.y, high.y))
				low = Vector2.ONE; high = -Vector2.ONE; frames = 0
	if frames > 0: left.append(Vector2(low.x, high.x)); right.append(Vector2(low.y, high.y))
	file.close()
	if FileAccess.get_modified_time(path) != int(info.modified): return {"cancelled": true}
	return _envelope_levels(left, right, stride, rate, float(info.duration))

static func _envelope_levels(left: PackedVector2Array, right: PackedVector2Array, stride: int, rate: int, seconds: float) -> Dictionary:
	var levels: Array = [{"left": left, "right": right, "stride": stride}]
	var bytes := (left.size() + right.size()) * 8
	while left.size() > 1:
		var next_left := PackedVector2Array()
		var next_right := PackedVector2Array()
		for index in range(0, left.size(), 2):
			var other := mini(index + 1, left.size() - 1)
			next_left.append(Vector2(minf(left[index].x, left[other].x), maxf(left[index].y, left[other].y)))
			next_right.append(Vector2(minf(right[index].x, right[other].x), maxf(right[index].y, right[other].y)))
		left = next_left
		right = next_right
		stride *= 2
		levels.append({"left": left, "right": right, "stride": stride})
		bytes += (left.size() + right.size()) * 8
	return {"levels": levels, "rate": rate, "duration": seconds, "bytes": bytes}

static func range_peaks(entry: Dictionary, start: float, duration: float, pixels: int, channel: int = 0) -> PackedVector2Array:
	var result := PackedVector2Array()
	var levels: Array = entry.get("levels", [])
	if levels.is_empty() or pixels <= 0: return result
	var rate := int(entry.rate)
	var per_pixel := maxf(1, duration * rate / pixels)
	var level: Dictionary = levels[0]
	for candidate in levels:
		if float(candidate.stride) <= per_pixel: level = candidate
	var data: PackedVector2Array = level.left if channel == 0 else level.right
	result.resize(pixels)
	for pixel in pixels:
		var first := clampi(int((start + duration * pixel / pixels) * rate / float(level.stride)), 0, maxi(0, data.size() - 1))
		var last := clampi(ceili((start + duration * (pixel + 1) / pixels) * rate / float(level.stride)), first + 1, data.size())
		var extrema := Vector2.ZERO
		for index in range(first, last):
			extrema.x = minf(extrema.x, data[index].x)
			extrema.y = maxf(extrema.y, data[index].y)
		result[pixel] = extrema
	return result

func _exit_tree() -> void:
	_generation += 1
	for job in _jobs.values(): job.token.cancel()
	for job in _jobs.values(): (job.thread as Thread).wait_to_finish()
	_jobs.clear()
	_pending.clear()
	entries.clear()


static func fit_pattern(stream:AudioStreamWAV,seconds:float)->AudioStreamWAV:
	var rate:=stream.mix_rate
	var decoded:=decode(stream,rate)
	if not str(decoded.get("error","")).is_empty():return null
	if not is_finite(seconds) or seconds <= 0 or seconds*rate*8 > MAX_DECODE_BYTES:return null
	var samples:PackedVector2Array=decoded.samples
	samples.resize(maxi(2,int(round(seconds*rate))))
	# Beat-exact loops have a two-millisecond safety fade rather than an unbounded release tail.
	var fade:=mini(samples.size()/2,maxi(1,int(rate*0.002)))
	for i in fade:
		var gain:=float(i)/fade;samples[i]*=gain;samples[samples.size()-1-i]*=gain
	return to_wav(samples,rate,stream.stereo)
