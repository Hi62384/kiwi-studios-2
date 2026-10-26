class_name ActorAudio
extends RefCounted
## Shared source identities and conservatively charged, least-recently-used retention.
## The budget is for idle strong-cache retention, not decoder working memory or
## streams retained by players, open waveforms, documents, and worker jobs.
const MAX_CACHE_BYTES := 64 * 1024 * 1024
const MAX_CACHE_SOURCES := 32
const METADATA_INTERVAL_MSEC := 1000
const MAX_IDLE_METADATA := 1024
const MAX_NATIVE_WAV_BYTES := 64 * 1024 * 1024
const MAX_FLAC_DISK_BYTES := 512 * 1024 * 1024
const MAX_FLAC_FILE_BYTES := 128 * 1024 * 1024
const MAX_FLAC_DISK_FILES := 256
const MAX_FLAC_SCAN_ENTRIES := 4096

# Kept as the public strong-cache dictionary for compatibility. Callers should
# use source()/invalidate(); mutating this dictionary bypasses accounting.
static var sources: Dictionary = {}
static var _cache_mutex := Mutex.new()
static var _metadata: Dictionary = {}
static var _identities: Dictionary = {}
static var _loads: Dictionary = {}
static var _retained_bytes := 0
static var _generation := 0
static var _revision := 0
static var _use_serial := 0
static var _flac_disk_mutex := Mutex.new()
static var _flac_used: Dictionary = {}
static var _flac_serial := 0

static func invalidate(path: String = "") -> void:
	_cache_mutex.lock()
	# Even an in-flight first load has a token. It cannot publish after this.
	_generation += 1
	if path.is_empty():
		sources.clear()
		_metadata.clear()
		_identities.clear()
		_retained_bytes = 0
	else:
		var key := _path_key(path)
		_forget_locked(key)
		_metadata.erase(key)
	_cache_mutex.unlock()

static func _path_key(path: String) -> String:
	return ProjectSettings.globalize_path(path).simplify_path()

## Cheap waveform identity. This never opens or decodes an audio stream. File
## metadata is refreshed at most once a second; explicit invalidate is immediate.
static func source_stamp(value: Variant) -> Dictionary:
	if value is AudioStream:
		return {"key": "stream:" + str(value.get_instance_id()), "missing": false}
	var path := str(value) if value != null else ""
	if path.is_empty(): return {"key": "", "missing": true}
	var metadata := _file_metadata(_path_key(path))
	return {"key": str(metadata.get("stamp", "")), "missing": int(metadata.get("size", -1)) < 0}

static func _signature(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"size": -1, "modified": 0}
	var size := file.get_length()
	file.close()
	return {"size": size, "modified": FileAccess.get_modified_time(path)}

static func _file_metadata(path: String, force: bool = false) -> Dictionary:
	var now := Time.get_ticks_msec()
	_cache_mutex.lock()
	var prior: Dictionary = _metadata.get(path, {})
	if not force and not prior.is_empty() and now < int(prior.checked_until):
		var result := prior.duplicate()
		_cache_mutex.unlock()
		return result
	var generation := _generation
	_cache_mutex.unlock()
	var signature := _signature(path)
	_cache_mutex.lock()
	if generation != _generation:
		_cache_mutex.unlock()
		return {}
	prior = _metadata.get(path, {})
	# Another reader may already have refreshed this path while the stat ran.
	if not force and not prior.is_empty() and now < int(prior.checked_until):
		var result := prior.duplicate()
		_cache_mutex.unlock()
		return result
	if prior.is_empty() or int(prior.size) != int(signature.size) or int(prior.modified) != int(signature.modified):
		_forget_locked(path)
		_revision += 1
		prior = {"size": signature.size, "modified": signature.modified, "stamp": path + ":" + str(signature.modified) + ":" + str(signature.size) + ":" + str(_revision), "duration": -1.0}
	prior.checked_until = now + METADATA_INTERVAL_MSEC
	_metadata[path] = prior
	_prune_metadata_locked(path)
	var result := prior.duplicate()
	_cache_mutex.unlock()
	return result

static func source(value: Variant, job: RefCounted = null) -> AudioStream:
	if value is AudioStream: return value
	var path := str(value) if value != null else ""
	if path.is_empty(): return null
	path = _path_key(path)
	var metadata := _file_metadata(path)
	if int(metadata.get("size", -1)) < 0: return null
	_cache_mutex.lock()
	var cached := _cached_locked(path, str(metadata.stamp))
	if cached != null:
		_cache_mutex.unlock()
		return cached
	# Concurrent misses for the same path share a gate, so large PCM is loaded
	# once while the first caller/worker still owns it. Other paths stay independent.
	var load: Dictionary = _loads.get(path, {})
	if load.is_empty():
		load = {"mutex": Mutex.new(), "users": 0}
		_loads[path] = load
	load.users = int(load.users) + 1
	_cache_mutex.unlock()
	var gate: Mutex = load.mutex
	while not gate.try_lock():
		if job != null and job.is_cancelled():
			_release_load(path, load)
			return null
		OS.delay_msec(10)
	var stream := _load_source(path, job)
	gate.unlock()
	_release_load(path, load)
	return stream

static func _release_load(path: String, load: Dictionary) -> void:
	_cache_mutex.lock()
	load.users = int(load.users) - 1
	if int(load.users) == 0: _loads.erase(path)
	_cache_mutex.unlock()

static func pcm_info(path: String) -> Dictionary:
	path = _path_key(path)
	var metadata := _file_metadata(path)
	if int(metadata.get("size", -1)) < 0: return {"error": "Missing source."}
	if metadata.has("pcm_info"): return (metadata.pcm_info as Dictionary).duplicate()
	var info := KiwiAudioPCMFile.inspect(path)
	_cache_mutex.lock()
	if str(_metadata.get(path, {}).get("stamp", "")) == str(metadata.stamp):
		_metadata[path].pcm_info = info.duplicate()
		if str(info.get("error", "invalid")).is_empty(): _metadata[path].duration = float(info.duration)
	_cache_mutex.unlock()
	return info

static func file_duration(value: Variant, job: RefCounted = null) -> float:
	if value is AudioStream: return value.get_length()
	var path := str(value) if value != null else ""
	if path.is_empty(): return 0.0
	var metadata := _file_metadata(_path_key(path))
	if float(metadata.get("duration", -1.0)) >= 0.0: return float(metadata.duration)
	if path.get_extension().to_lower() == "wav":
		var info := pcm_info(path)
		if str(info.get("error", "invalid")).is_empty(): return float(info.duration)
	elif path.get_extension().to_lower() == "flac":
		_flac_pcm_bytes(path)
		var updated := _file_metadata(_path_key(path))
		if float(updated.get("duration", -1.0)) >= 0.0: return float(updated.duration)
	var stream := source(value, job)
	return stream.get_length() if stream != null else 0.0

static func needs_file_preview(value: Variant) -> bool:
	if not value is String: return false
	var path := str(value)
	if path.get_extension().to_lower() == "wav": return int(_file_metadata(_path_key(path)).get("size", 0)) > MAX_NATIVE_WAV_BYTES
	if path.get_extension().to_lower() == "flac":
		var bytes := _flac_pcm_bytes(path)
		return bytes < 0 or bytes > MAX_FLAC_FILE_BYTES - 4096
	return false

static func _load_source(path: String, job: RefCounted = null) -> AudioStream:
	if job != null and job.is_cancelled(): return null
	var metadata := _file_metadata(path)
	if int(metadata.get("size", -1)) < 0: return null
	_cache_mutex.lock()
	var cached := _cached_locked(path, str(metadata.stamp))
	var generation := _generation
	_cache_mutex.unlock()
	if cached != null: return cached
	var stream: AudioStream
	match path.get_extension().to_lower():
		"mp3": stream = AudioStreamMP3.load_from_file(path)
		"wav": stream = AudioStreamWAV.load_from_file(path)
		"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
		"flac": stream = _load_flac(path, metadata, job)
		_:
			# Do not ask ResourceLoader to replace an existing caller's resource.
			var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if resource is AudioStream: stream = resource
	if stream == null: return null
	var after := _file_metadata(path, true)
	if str(after.get("stamp", "")) != str(metadata.stamp): return null
	var cost := _retention_cost(stream, int(metadata.size), path)
	var source_duration := stream.get_length()
	_cache_mutex.lock()
	if generation == _generation and str(_metadata.get(path, {}).get("stamp", "")) == str(metadata.stamp):
		_identities[path] = {"weak": weakref(stream), "stamp": metadata.stamp, "cost": cost, "used": 0}
		_metadata[path].duration = source_duration
		_retain_locked(path, stream)
	# Invalidation drops our ownership only. Never clear/mutate stream.data or
	# free a resource that an active caller may still be using.
	_cache_mutex.unlock()
	return stream

static func _load_flac(path: String, metadata: Dictionary, job: RefCounted = null) -> AudioStream:
	var encoder := ActorVideo.executable("ffmpeg")
	if encoder.is_empty(): return null
	# Reject a known oversized native PCM resource before starting a decoder.
	# Streaming export can still use the original FLAC directly. This does not
	# pretend that AudioStreamWAV is a streaming resource or a global RAM limit.
	var pcm_bytes := _flac_pcm_bytes(path)
	if pcm_bytes < 0 or pcm_bytes > MAX_FLAC_FILE_BYTES - 4096:
		push_warning("Native FLAC preview requires a known mono/stereo frame count and at most 128 MiB decoded PCM. Use a shorter source; streaming export can use the original file.")
		return null
	# A content digest is computed only on a load miss for a new metadata
	# identity, not on waveform redraws. It survives metadata eviction/session
	# load order and detects same-size/timestamp changes after invalidate().
	var digest := str(metadata.get("flac_digest", ""))
	if digest.is_empty():
		if job != null and job.is_cancelled(): return null
		digest = FileAccess.get_sha256(path)
		if digest.is_empty() or (job != null and job.is_cancelled()): return null
		_cache_mutex.lock()
		if str(_metadata.get(path, {}).get("stamp", "")) == str(metadata.stamp): _metadata[path].flac_digest = digest
		_cache_mutex.unlock()
	# This is a disk decode cache, separate from the 64 MiB RAM retention
	# budget. Only a successful owned temporary file is promoted into it.
	var decoded := ProjectSettings.globalize_path("user://audio_cache/" + ("flac:pcm_s16le:" + digest).sha256_text() + ".wav")
	if DirAccess.make_dir_recursive_absolute(decoded.get_base_dir()) != OK: return null
	var cache_parent := DirAccess.open(decoded.get_base_dir().get_base_dir())
	if cache_parent == null or cache_parent.is_link(decoded.get_base_dir().get_file()):
		push_warning("FLAC cache folder must be a regular directory, not a linked directory.")
		return null
	var cached := _flac_disk_read(decoded, "", job)
	if cached != null: return cached
	if not FileAccess.file_exists(decoded):
		var temporary := decoded.get_basename() + "." + ActorData.new_id() + ".wav"
		var result := KiwiAudioEncoderProcess.run(encoder, PackedStringArray(["-v", "error", "-n", "-threads", "1", "-i", path, "-c:a", "pcm_s16le", "-fs", str(MAX_FLAC_FILE_BYTES + 65536), temporary]), 0.0, job, 86400.0)
		if not bool(result.get("success", false)):
			if bool(result.get("process_exited", false)): DirAccess.remove_absolute(temporary)
			else: push_warning(str(result.get("error", "Audio decode failed.")) + " Retained decoder file: " + temporary)
			return null
		return _flac_disk_read(decoded, temporary, job)
	return null

static func _flac_pcm_bytes(path: String) -> int:
	path = _path_key(path)
	var metadata := _file_metadata(path)
	if metadata.has("flac_pcm_bytes"): return int(metadata.flac_pcm_bytes)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return -1
	var header := file.get_buffer(42)
	file.close()
	if header.size() != 42 or header.slice(0, 4).get_string_from_ascii() != "fLaC": return -1
	# STREAMINFO must be the first metadata block and has exactly 34 bytes.
	if (int(header[4]) & 127) != 0 or header[5] != 0 or header[6] != 0 or header[7] != 34: return -1
	var channels := ((int(header[20]) >> 1) & 7) + 1
	var frames := ((int(header[21]) & 15) << 32) | (int(header[22]) << 24) | (int(header[23]) << 16) | (int(header[24]) << 8) | int(header[25])
	var rate := (int(header[18]) << 12) | (int(header[19]) << 4) | (int(header[20]) >> 4)
	var bytes := frames * channels * 2 if channels <= 2 and frames > 0 else -1
	_cache_mutex.lock()
	if str(_metadata.get(path, {}).get("stamp", "")) == str(metadata.get("stamp", "")):
		_metadata[path].flac_pcm_bytes = bytes
		if frames > 0 and rate > 0: _metadata[path].duration = float(frames) / rate
	_cache_mutex.unlock()
	return bytes

static func _flac_disk_read(decoded: String, temporary: String, job: RefCounted) -> AudioStream:
	# Serialize cache inventory, eviction, promotion and read. Decoder processes
	# work outside this lock; their unique in-progress filenames are never evicted.
	_flac_disk_mutex.lock()
	var stream: AudioStream
	if job == null or not job.is_cancelled():
		var current := _signature(decoded)
		var incoming := _signature(temporary) if not temporary.is_empty() else {"size": -1}
		var size := int(current.size) if int(current.size) >= 0 else int(incoming.size)
		if size > 0 and size <= MAX_FLAC_FILE_BYTES and _flac_disk_room(decoded, size, int(current.size) < 0):
			var ready := int(current.size) >= 0
			if not ready and not temporary.is_empty(): ready = DirAccess.rename_absolute(temporary, decoded) == OK
			if ready:
				stream = AudioStreamWAV.load_from_file(decoded)
				if stream != null:
					_flac_serial += 1
					_flac_used[decoded] = _flac_serial
				else: push_warning("The completed FLAC cache entry could not be loaded. Original audio is preserved: " + decoded)
		elif size > 0: push_warning("FLAC cache admission failed: decoded preview exceeds its limit, cache inventory exceeds 4096 entries, or old derived files could not be removed. Original audio is preserved.")
	# Only a successfully exited decoder passes its owned temporary file here.
	# Failed/uncertain encoder exit paths retain their files for recovery above.
	if not temporary.is_empty() and FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
	_flac_disk_mutex.unlock()
	return stream

static func _flac_disk_room(protected_path: String, incoming_bytes: int, is_new: bool) -> bool:
	var directory_path := ProjectSettings.globalize_path("user://audio_cache").simplify_path()
	if protected_path.get_base_dir().simplify_path() != directory_path: return false
	var parent := DirAccess.open(directory_path.get_base_dir())
	if parent == null or parent.is_link(directory_path.get_file()): return false
	var directory := DirAccess.open(directory_path)
	if directory == null or directory.is_link(protected_path.get_file()) or directory.list_dir_begin() != OK: return false
	var entries: Array[Dictionary] = []
	var total := incoming_bytes if is_new else 0
	var visited := 0
	var valid := true
	var name := directory.get_next()
	while not name.is_empty():
		visited += 1
		if visited > MAX_FLAC_SCAN_ENTRIES: valid = false; break
		# Completed cache entries have exactly a lowercase SHA-256 basename.
		# Exclude links, directories, job files and all unrelated names.
		var stem := name.get_basename()
		if not directory.current_is_dir() and not directory.is_link(name) and name.get_extension() == "wav" and stem.length() == 64 and stem.to_lower() == stem and stem.is_valid_hex_number(false):
			var entry_path := directory_path.path_join(name)
			var info := _signature(entry_path)
			if int(info.size) < 0: valid = false; break
			total += int(info.size)
			entries.append({"path": entry_path, "bytes": int(info.size), "used": int(_flac_used.get(entry_path, 0)), "modified": int(info.modified)})
		name = directory.get_next()
	directory.list_dir_end()
	if not valid: return false
	var count := entries.size() + (1 if is_new else 0)
	entries.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.used) != int(b.used): return int(a.used) < int(b.used)
		if int(a.modified) != int(b.modified): return int(a.modified) < int(b.modified)
		return str(a.path) < str(b.path))
	for entry in entries:
		if total <= MAX_FLAC_DISK_BYTES and count <= MAX_FLAC_DISK_FILES: break
		if str(entry.path) == protected_path: continue
		if DirAccess.remove_absolute(str(entry.path)) != OK: continue
		total -= int(entry.bytes); count -= 1; _flac_used.erase(str(entry.path))
	return total <= MAX_FLAC_DISK_BYTES and count <= MAX_FLAC_DISK_FILES

static func _cached_locked(path: String, stamp: String) -> AudioStream:
	var identity: Dictionary = _identities.get(path, {})
	if identity.is_empty() or str(identity.stamp) != stamp: return null
	var reference: WeakRef = identity.weak
	var stream := reference.get_ref() as AudioStream
	if stream != null: _retain_locked(path, stream)
	return stream

static func _retention_cost(stream: AudioStream, file_size: int, path: String) -> int:
	var overhead := 65536 + path.length() * 8
	if stream is AudioStreamWAV:
		# Do not read .data to count it: WAV.get_data() can allocate a full copy.
		# Float32-per-channel accounting overcharges Godot's supported PCM16/8.
		var wav := stream as AudioStreamWAV
		var frames := maxf(0.0, ceil(wav.get_length() * wav.mix_rate))
		var pcm_bytes := frames * (2 if wav.stereo else 1) * 4.0
		if not is_finite(pcm_bytes) or pcm_bytes > MAX_CACHE_BYTES: return MAX_CACHE_BYTES + 1
		return overhead + maxi(file_size * 2, int(pcm_bytes))
	if stream is AudioStreamMP3: return overhead + file_size * 2
	if stream is AudioStreamOggVorbis:
		# Packet tables and allocation overhead are not exposed by Godot. Charge
		# generously rather than treating compressed file size as resident bytes.
		return overhead + 262144 + file_size * 8
	# Composite/custom resources have unknown transitive retention; weak only.
	return MAX_CACHE_BYTES + 1

static func _retain_locked(path: String, stream: AudioStream) -> void:
	var entry: Dictionary = _identities[path]
	_use_serial += 1
	entry.used = _use_serial
	var cost := int(entry.cost)
	if cost > MAX_CACHE_BYTES or sources.has(path): return
	while not sources.is_empty() and (_retained_bytes + cost > MAX_CACHE_BYTES or sources.size() >= MAX_CACHE_SOURCES):
		var oldest: String = str(sources.keys()[0])
		for key in sources:
			if int(_identities[key].used) < int(_identities[oldest].used): oldest = str(key)
		_drop_strong_locked(oldest)
	sources[path] = stream
	_retained_bytes += cost

static func _drop_strong_locked(path: String) -> void:
	if sources.has(path):
		_retained_bytes = maxi(0, _retained_bytes - int(_identities.get(path, {}).get("cost", 0)))
		sources.erase(path)

static func _forget_locked(path: String) -> void:
	_drop_strong_locked(path)
	_identities.erase(path)

static func _prune_metadata_locked(protected_path: String) -> void:
	if _metadata.size() <= MAX_IDLE_METADATA: return
	for key in _metadata.keys():
		if _metadata.size() <= MAX_IDLE_METADATA: break
		if key == protected_path or sources.has(key) or _loads.has(key): continue
		var entry: Dictionary = _identities.get(key, {})
		if not entry.is_empty() and (entry.weak as WeakRef).get_ref() != null: continue
		_identities.erase(key)
		_metadata.erase(key)

static func length(actor: ActorData) -> float:
	if actor.type_id in [&"video", &"video_2d"]: return ActorVideo.length(actor)
	var value: Variant = actor.values.get(&"audio", "")
	if value is AudioStream: return value.get_length()
	var path := str(value) if value != null else ""
	if path.is_empty(): return 0.0
	var metadata := _file_metadata(_path_key(path))
	if int(metadata.get("size", -1)) < 0: return 0.0
	if float(metadata.get("duration", -1.0)) >= 0.0: return float(metadata.duration)
	return file_duration(path)

static func fade_gain(actor: ActorData, clip: ActorClip, time: float) -> float:
	var fade_in := clampf(float(actor.values.get(&"fade_in", 0.0)), 0.0, clip.duration)
	var fade_out := clampf(float(actor.values.get(&"fade_out", 0.0)), 0.0, clip.duration)
	var gain := 1.0
	if fade_in > 0.0: gain = minf(gain, clampf((time - clip.start_time) / fade_in, 0.0, 1.0))
	if fade_out > 0.0: gain = minf(gain, clampf((clip.start_time + clip.duration - time) / fade_out, 0.0, 1.0))
	if str(actor.values.get(&"fade_curve", "linear")) == "equal_power": gain = sin(gain * PI * 0.5)
	return gain

static func valid(actor: ActorData, clip: ActorClip, duration: float, offset: float) -> bool:
	if actor.type_id not in [&"audio", &"video", &"video_2d"]: return true
	var source_duration := length(actor)
	if source_duration == 0.0: return true
	return offset >= -0.000001 and offset + duration * clip.playback_speed <= source_duration + 0.000001
