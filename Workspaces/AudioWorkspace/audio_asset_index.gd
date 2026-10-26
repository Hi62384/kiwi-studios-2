class_name KiwiAudioAssetIndex
extends Node
## Opt-in res:// discovery. Worker reads bounded file headers, never audio streams.
signal progress_changed(message: String)
signal scan_finished(generation: int, result: Dictionary)
const MAX_ROOTS := 8
const MAX_ASSETS := 2048
const MAX_DIRECTORIES := 512
const MAX_VISITED := 20000
const MAX_DEPTH := 16
const MAX_SCAN_MSEC := 15000
const MAX_HEADER_BYTES := 65536
const MAX_TOTAL_HEADER_BYTES := 16 * 1024 * 1024
const MAX_PATH_CHARS := 1024
const EXTENSIONS := ["wav", "mp3", "ogg", "flac"]
const EXCLUDED := [".godot", ".git"]
var _generation := 0
var _thread: Thread
var _work: RefCounted
var _running_generation := 0
var _pending: Dictionary = {}
var _progress_elapsed := 0.0

func request(roots: Array[String], previous: Array[Dictionary]) -> int:
	_generation += 1
	if _work != null: _work.cancel()
	_pending = {"roots": roots.duplicate(), "previous": previous.duplicate(true), "generation": _generation}
	return _generation

func cancel() -> void:
	_generation += 1
	_pending.clear()
	if _work != null: _work.cancel()

func busy() -> bool:
	return _thread != null or not _pending.is_empty()

func _process(delta: float) -> void:
	if _thread != null:
		_progress_elapsed += delta
		if _progress_elapsed >= 0.15 and _running_generation == _generation:
			_progress_elapsed = 0.0
			var status: Dictionary = _work.status()
			progress_changed.emit(str(status.description))
		if _thread.is_alive(): return
		var result: Dictionary = _thread.wait_to_finish()
		var accept: bool = _running_generation == _generation and not _work.is_cancelled()
		_thread = null
		_work = null
		if accept: scan_finished.emit(_running_generation, result)
	if _thread == null and not _pending.is_empty():
		var job := _pending
		_pending = {}
		_running_generation = int(job.generation)
		_work = KiwiAudioJobs.Work.new()
		_thread = Thread.new()
		if _thread.start(_scan.bind(job.roots, job.previous, _work)) != OK:
			_thread = null
			_work = null
			scan_finished.emit(_running_generation, {"error": "Could not start the project audio index worker."})

func _exit_tree() -> void:
	cancel()
	if _thread != null: _thread.wait_to_finish()
	_thread = null
	_work = null

static func canonical_root(value: String) -> String:
	if not value.begins_with("res://") or value.length() > MAX_PATH_CHARS or value.contains("\\"): return ""
	var relative := value.substr(6).trim_suffix("/")
	if relative.is_empty(): return "res://"
	for part in relative.split("/", true):
		if part.is_empty() or part in [".", ".."] or part.to_lower() in EXCLUDED or part.contains(":"): return ""
	return "res://" + relative

static func contains_path(root: String, path: String) -> bool:
	return path.begins_with("res://") if root == "res://" else path == root or path.begins_with(root + "/")

static func path_state(path: String, directory: bool = false) -> String:
	# Resolve only from the trusted resource root. Reject every linked component
	# before descending; never globalize a requested path or follow read_link().
	var clean := canonical_root(path)
	if clean.is_empty() or clean != path: return "blocked"
	var access := DirAccess.open("res://")
	if access == null: return "unreadable"
	if path == "res://": return "available" if directory else "blocked"
	var parts := path.substr(6).split("/")
	var at := "res://"
	for index in parts.size():
		var part: String = parts[index]
		if access.is_link(part): return "blocked"
		var is_directory := index < parts.size() - 1 or directory
		if is_directory:
			if not access.dir_exists(part): return "missing"
			at = at.path_join(part)
			access = DirAccess.open(at)
			if access == null: return "unreadable"
		elif not access.file_exists(part): return "missing"
	return "available"

static func usable(entry: Dictionary) -> bool:
	var source := str(entry.get("source", ""))
	var root := canonical_root(str(entry.get("index_root", "")))
	if root.is_empty() or not contains_path(root, source) or source.get_extension().to_lower() not in EXTENSIONS: return false
	if str(entry.get("asset_state", "unverified")) != "available" or path_state(source) != "available": return false
	# This is an action-time readability check only; the scene loader owns decode.
	var file := FileAccess.open(source, FileAccess.READ)
	return file != null

static func _root_for(path: String, roots: Array[String]) -> String:
	for root in roots:
		if contains_path(root, path): return root
	return ""

static func _blank(path: String, root: String) -> Dictionary:
	return {"id": "asset_" + path.sha256_text(), "label": path.get_file(), "kind": "asset", "category": "Project", "origin": "project", "source": path, "project_indexed": true, "index_root": root, "asset_state": "unverified", "metadata_note": "Metadata not checked in this scan."}

static func describe(entry: Dictionary) -> String:
	var state := str(entry.get("asset_state", "unverified"))
	var message := "Readable; playback has not been checked."
	match state:
		"missing": message = "Missing file or containing folder."
		"unreadable": message = "The file or folder could not be read."
		"blocked": message = "Outside the allowed project scope, excluded, or a symbolic link."
		"unverified": message = "Not checked in the latest scan; refresh or choose a smaller folder."
	return str(entry.get("source", "")) + "\n" + message + "\n" + str(entry.get("metadata_note", "Duration not indexed."))

static func _scan(requested: Array[String], previous: Array[Dictionary], work: RefCounted) -> Dictionary:
	var began := Time.get_ticks_msec()
	var roots: Array[String] = []
	for value in requested:
		var root := canonical_root(value)
		if not root.is_empty() and not roots.has(root) and roots.size() < MAX_ROOTS: roots.append(root)
	var records: Dictionary = {}
	for old in previous:
		if records.size() >= MAX_ASSETS: break
		var path := str(old.get("source", ""))
		var root := _root_for(path, roots)
		if root.is_empty() or canonical_root(path) != path: continue
		# Retain identities/favorites without presenting old metadata as current.
		records[path] = _blank(path, root)
	var queue: Array[Dictionary] = []
	for root in roots: queue.append({"path": root, "root": root, "depth": 0})
	var cursor := 0
	var visited := 0
	var inspected := 0
	var skipped_links := 0
	var unreadable_folders := 0
	var header_bytes := 0
	var limit_reason := ""
	var observed: Dictionary = {}
	while cursor < queue.size():
		if work.is_cancelled(): return {"cancelled": true}
		if Time.get_ticks_msec() - began >= MAX_SCAN_MSEC:
			limit_reason = "15-second scan budget reached."
			break
		var folder: Dictionary = queue[cursor]
		cursor += 1
		var folder_state := path_state(str(folder.path), true)
		if folder_state != "available":
			unreadable_folders += 1
			continue
		var directory := DirAccess.open(str(folder.path))
		if directory == null:
			unreadable_folders += 1
			continue
		directory.include_hidden = true
		directory.include_navigational = false
		if directory.list_dir_begin() != OK:
			unreadable_folders += 1
			continue
		var name := directory.get_next()
		while not name.is_empty():
			if work.is_cancelled():
				directory.list_dir_end()
				return {"cancelled": true}
			if visited >= MAX_VISITED or Time.get_ticks_msec() - began >= MAX_SCAN_MSEC:
				limit_reason = "20,000-entry scan budget reached." if visited >= MAX_VISITED else "15-second scan budget reached."
				break
			visited += 1
			var path: String = str(folder.path).path_join(name)
			if name.to_lower() in EXCLUDED or canonical_root(path).is_empty():
				name = directory.get_next()
				continue
			if directory.is_link(name):
				skipped_links += 1
			elif directory.current_is_dir():
				if int(folder.depth) >= MAX_DEPTH or queue.size() >= MAX_DIRECTORIES:
					limit_reason = "Folder/depth limit reached; choose a smaller project folder."
				else: queue.append({"path": path, "root": folder.root, "depth": int(folder.depth) + 1})
			elif path.get_extension().to_lower() in EXTENSIONS:
				if not records.has(path) and records.size() >= MAX_ASSETS:
					limit_reason = "2,048-asset limit reached; choose a smaller project folder."
					break
				if header_bytes >= MAX_TOTAL_HEADER_BYTES:
					limit_reason = "16 MiB metadata-read budget reached; choose a smaller project folder."
					break
				var entry := _inspect(path, str(folder.root), mini(MAX_HEADER_BYTES, MAX_TOTAL_HEADER_BYTES - header_bytes))
				header_bytes += int(entry.get("header_bytes", 0))
				entry.erase("header_bytes")
				records[path] = entry
				observed[path] = true
				inspected += 1
				work.update(float(inspected) / MAX_ASSETS, "Indexing: %d audio files · %d folders" % [inspected, cursor])
			name = directory.get_next()
		directory.list_dir_end()
		# A nonempty iterator name means a hard budget stopped this folder.
		# Depth/folder clipping can still finish the bounded queued folders.
		if not name.is_empty(): break
	for path in records:
		if work.is_cancelled(): return {"cancelled": true}
		if observed.has(path): continue
		if Time.get_ticks_msec() - began >= MAX_SCAN_MSEC:
			if limit_reason.is_empty(): limit_reason = "15-second scan budget reached."
			break
		# Even on partial traversal, check old identities individually. Never infer
		# deletion from absence in a clipped or unreadable directory enumeration.
		var state := path_state(str(path))
		if state == "available":
			var file := FileAccess.open(str(path), FileAccess.READ)
			state = "unverified" if file != null else "unreadable"
		records[path].asset_state = state
	var result_entries: Array[Dictionary] = []
	for entry in records.values():
		entry.description = describe(entry)
		result_entries.append(entry)
	return {"entries": result_entries, "partial": not limit_reason.is_empty() or unreadable_folders > 0, "limit_reason": limit_reason, "inspected": inspected, "folders": cursor, "visited": visited, "skipped_links": skipped_links, "unreadable_folders": unreadable_folders, "header_bytes": header_bytes, "elapsed_msec": Time.get_ticks_msec() - began}

static func _inspect(path: String, root: String, budget: int) -> Dictionary:
	var entry := _blank(path, root)
	entry.asset_state = path_state(path)
	if entry.asset_state != "available": return entry
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		entry.asset_state = "unreadable"
		return entry
	var size := file.get_length()
	entry.size_bytes = size
	entry.modified_time = FileAccess.get_modified_time(path)
	var expected := mini(size, mini(budget, MAX_HEADER_BYTES if path.get_extension().to_lower() == "wav" else 4096))
	var bytes := file.get_buffer(expected)
	file = null
	entry.header_bytes = bytes.size()
	if bytes.size() != expected:
		entry.asset_state = "unreadable"
		entry.metadata_note = "The metadata header could not be fully read."
		return entry
	entry.metadata_note = "Duration not indexed; playback/decoder support is checked only when used."
	match path.get_extension().to_lower():
		"wav": _wav_metadata(bytes, size, entry)
		"flac": _flac_metadata(bytes, entry)
		"mp3", "ogg": entry.metadata_note = "Compressed duration is unknown until loaded; the index does not decode audio."
	return entry

static func _tag(bytes: PackedByteArray, at: int, value: String) -> bool:
	if at < 0 or at + value.length() > bytes.size(): return false
	for index in value.length():
		if bytes[at + index] != value.unicode_at(index): return false
	return true

static func _wav_metadata(bytes: PackedByteArray, size: int, entry: Dictionary) -> void:
	if bytes.size() < 12 or not _tag(bytes, 0, "RIFF") or not _tag(bytes, 8, "WAVE"):
		entry.metadata_note = "Unrecognized WAV header; playback has not been checked."
		return
	var at := 12
	var rate := 0
	var channels := 0
	var block_align := 0
	var byte_rate := 0
	var data_bytes := -1
	var pcm := false
	while at + 8 <= bytes.size():
		var length := int(bytes.decode_u32(at + 4))
		var start := at + 8
		if _tag(bytes, at, "fmt ") and length >= 16 and start + 16 <= bytes.size():
			var format := int(bytes.decode_u16(start))
			channels = int(bytes.decode_u16(start + 2))
			rate = int(bytes.decode_u32(start + 4))
			byte_rate = int(bytes.decode_u32(start + 8))
			block_align = int(bytes.decode_u16(start + 12))
			var bits := int(bytes.decode_u16(start + 14))
			pcm = format in [1, 3] and channels > 0 and channels <= 64 and bits in [8, 16, 24, 32, 64] and block_align == channels * (bits / 8) and byte_rate == rate * block_align
		elif _tag(bytes, at, "data"):
			if start + length <= size: data_bytes = length
			break
		if start + length > bytes.size(): break
		at = start + length + (length % 2)
	if rate > 0: entry.sample_rate = rate
	if channels > 0: entry.channels = channels
	if pcm and rate > 0 and byte_rate > 0 and data_bytes >= 0 and data_bytes % block_align == 0:
		entry.duration = float(data_bytes) / byte_rate
		entry.duration_estimated = true
		entry.metadata_note = "Header-derived duration estimate (PCM/float WAV); samples have not been decoded."
	else: entry.metadata_note = "WAV duration is unknown within the 64 KiB header limit or this encoding; playback is unchecked."

static func _flac_metadata(bytes: PackedByteArray, entry: Dictionary) -> void:
	if bytes.size() < 42 or not _tag(bytes, 0, "fLaC") or (bytes[4] & 127) != 0 or bytes[5] != 0 or bytes[6] != 0 or bytes[7] != 34:
		entry.metadata_note = "FLAC STREAMINFO is unavailable in the bounded header. Preview may require the existing FFmpeg loader."
		return
	var rate := (int(bytes[18]) << 12) | (int(bytes[19]) << 4) | (int(bytes[20]) >> 4)
	var channels := ((int(bytes[20]) >> 1) & 7) + 1
	var samples := ((int(bytes[21]) & 15) << 32) | (int(bytes[22]) << 24) | (int(bytes[23]) << 16) | (int(bytes[24]) << 8) | int(bytes[25])
	entry.sample_rate = rate
	entry.channels = channels
	if rate > 0 and samples > 0:
		entry.duration = float(samples) / rate
		entry.duration_estimated = true
		entry.metadata_note = "Header-derived FLAC duration estimate; decode unchecked. Preview may require the existing FFmpeg loader."
