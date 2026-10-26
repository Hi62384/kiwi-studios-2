class_name KiwiAudioFilePreview
extends Node
## Bounded file-backed PCM monitoring. One worker owns each file handle and
## converts small chunks; only the main thread touches the native player.
## UI/audio scheduling can still underrun. This is not a realtime DSP engine.
signal finished
signal failed(message: String)
signal released(path: String)
const CHUNK_FRAMES := 2048
const MAX_BURSTS := 8
const QUEUE_CHUNKS := 32
const MAX_READERS := 3

class Reader extends RefCounted:
	var mutex := Mutex.new()
	var wake := Semaphore.new()
	var pending_wake := false
	var cancelled := false
	var generation := 0
	var first := 0
	var looped := false
	var done := false
	var error := ""
	var chunks: Array[Dictionary] = []
	var path := ""
	var info: Dictionary = {}

	func _notify_locked() -> void:
		if not pending_wake:
			pending_wake = true
			wake.post()

	func seek_to(frame: int, loop: bool) -> int:
		mutex.lock()
		generation += 1; first = frame; looped = loop
		chunks.clear(); done = false
		var value := generation
		_notify_locked()
		mutex.unlock()
		return value

	func cancel() -> void:
		mutex.lock()
		cancelled = true; chunks.clear()
		_notify_locked()
		mutex.unlock()

	func take(max_frames: int) -> Dictionary:
		mutex.lock()
		var packet: Dictionary = {}
		if not chunks.is_empty() and (chunks[0].samples as PackedVector2Array).size() <= max_frames:
			packet = chunks.pop_front()
			_notify_locked()
		mutex.unlock()
		return packet

	func status() -> Dictionary:
		mutex.lock()
		var value := {"error": error, "done": done, "queued": chunks.size()}
		mutex.unlock()
		return value

	func _set_error(message: String) -> void:
		mutex.lock()
		if not cancelled: error = message
		mutex.unlock()

	func run() -> void:
		# FileAccess never crosses threads. No Node, player or signal is used here.
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			_set_error("The file preview source could not be opened.")
			return
		if file.get_length() != int(info.file_bytes) or FileAccess.get_modified_time(path) != int(info.modified):
			file.close()
			_set_error("The PCM source changed before playback. Prepare it again.")
			return
		var cursor := 0
		var current := -1
		var checked := Time.get_ticks_msec()
		while true:
			mutex.lock()
			var stop := cancelled
			if current != generation:
				current = generation; cursor = first
			var wait_for_work := done or chunks.size() >= QUEUE_CHUNKS
			var looping := looped
			mutex.unlock()
			if stop: break
			if wait_for_work:
				wake.wait()
				mutex.lock(); pending_wake = false; mutex.unlock()
				continue
			if Time.get_ticks_msec() - checked >= 1000:
				checked = Time.get_ticks_msec()
				if file.get_length() != int(info.file_bytes) or FileAccess.get_modified_time(path) != int(info.modified):
					_set_error("File preview stopped because its PCM source changed.")
					break
			if cursor >= int(info.frames):
				if looping: cursor = 0
				else:
					mutex.lock()
					if current == generation: done = true
					mutex.unlock()
					continue
			var count := mini(CHUNK_FRAMES, int(info.frames) - cursor)
			var samples := KiwiAudioPCMFile.read_frames(file, info, cursor, count)
			if samples.size() != count:
				_set_error("The PCM preview file ended before its declared data boundary.")
				break
			cursor += count
			var final := cursor >= int(info.frames) and not looping
			mutex.lock()
			# A seek/close can happen during I/O. Never publish its old PCM.
			if current == generation and not cancelled:
				chunks.append({"samples": samples, "generation": current, "final": final})
				if final: done = true
			mutex.unlock()
		file.close()

var player := AudioStreamPlayer.new()
var active := false
var loop_enabled := false:
	set(value):
		if loop_enabled == value: return
		var position := position_seconds()
		loop_enabled = value
		# Discard pre-buffered old loop boundaries when changing the policy.
		if active: seek_file(position)
var duration := 0.0
var info: Dictionary = {}
var _reader: Reader
var _readers: Array[Dictionary] = []
var _playback: AudioStreamGeneratorPlayback
var _capacity := 0
var _origin := 0
var _pushed := 0
var _eof := false
var _priming := false
var _primed_at := 0
var _generation := 0
var _skips := 0
var _last_error := ""
var _held := false

func _ready() -> void: add_child(player)

func open_file(path: String, bus: String = "Master", prepared: Dictionary = {}, owned: bool = false, retained_owner: RefCounted = null, auto_start: bool = true) -> String:
	close_file()
	_reap_readers()
	_last_error = ""; _held = not auto_start
	if _readers.size() >= MAX_READERS:
		return "Previous PCM readers are still closing. Wait for disk access to finish before opening another preview."
	# Header inspection is bounded; all ongoing bulk reads and conversion are
	# off the UI thread. A prepared render normally supplies this metadata.
	info = prepared.duplicate() if not prepared.is_empty() else KiwiAudioPCMFile.inspect(path)
	if not str(info.get("error", "invalid PCM metadata")).is_empty(): return str(info.get("error", "Invalid PCM metadata."))
	if int(info.get("frames", 0)) <= 0 or int(info.get("rate", 0)) < 8000: return "The PCM preview metadata has no playable frames."
	duration = float(info.duration)
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = int(info.rate); generator.buffer_length = 0.75
	player.stream = generator; player.bus = bus
	var reader := Reader.new(); reader.path = path; reader.info = info.duplicate()
	var thread := Thread.new()
	_reader = reader
	if thread.start(reader.run) != OK:
		_reader = null; player.stream = null; info = {}; duration = 0.0
		return "The PCM preview worker could not be started."
	_readers.append({"reader": reader, "thread": thread, "path": path, "owned": owned, "owner": retained_owner})
	active = true
	seek_file(0.0)
	return _last_error

func seek_file(seconds: float) -> void:
	if not active or _reader == null: return
	# play() creates fresh native playback. Pause it afterwards, before any
	# real PCM is pushed; a pause set before play can be lost by the start.
	player.stop(); player.play(); player.stream_paused = true
	_playback = player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _playback == null: _fail("The native generator playback could not be initialized."); return
	_capacity = _playback.get_frames_available()
	_origin = clampi(int(seconds * int(info.rate)), 0, int(info.frames))
	_pushed = 0; _eof = false; _priming = true
	_primed_at = Time.get_ticks_msec()
	_generation = _reader.seek_to(_origin, loop_enabled)

# A prepared recording must fill its bounded buffer before opening devices,
# but must not play through the countdown or asynchronous device startup.
func prepared_token() -> Dictionary:
	return {"reader": weakref(_reader), "generation": _generation} if _reader != null else {}

func is_primed(token: Dictionary = {}) -> bool:
	if not active or _reader == null or _playback == null or _priming: return false
	if not token.is_empty() and (not token.get("reader") is WeakRef or token.reader.get_ref() != _reader or int(token.get("generation", -1)) != _generation): return false
	return str(_reader.status().get("error", "")).is_empty()

func start_primed(token: Dictionary = {}) -> String:
	if not _held or not is_primed(token): return "The prepared PCM buffer is no longer ready. Prepare the take again."
	_held = false; player.stream_paused = false
	_skips = _playback.get_skips()
	return ""

func position_seconds() -> float:
	if not active or _playback == null: return 0.0
	# Native resampling may prefetch a small block even while paused; that is
	# not elapsed recording playback time. Held startup stays at its origin.
	if _held: return float(_origin) / int(info.rate)
	var queued := maxi(0, _capacity - _playback.get_frames_available())
	var consumed := maxi(0, _pushed - queued) if not _priming else 0
	var frame := _origin + consumed
	if loop_enabled and int(info.frames) > 0: frame %= int(info.frames)
	return minf(duration, float(frame) / int(info.rate))

func _process(_delta: float) -> void:
	_reap_readers()
	if not active or _reader == null or _playback == null: return
	var state := _reader.status()
	if not str(state.error).is_empty(): _fail(str(state.error)); return
	if not _priming and not _held:
		var skips := _playback.get_skips()
		if skips > _skips and not _eof:
			_fail("File preview underrun: disk/UI did not supply PCM in time. Stop other heavy work and prepare a shorter range.")
			return
		_skips = skips
	_pump()
	if not active: return
	if _priming:
		var needed := mini(int(info.rate) / 4, _capacity)
		if not loop_enabled: needed = mini(needed, int(info.frames) - _origin)
		if _pushed >= needed or (_eof and _pushed > 0):
			_priming = false
			player.stream_paused = _held
			_skips = _playback.get_skips()
		elif Time.get_ticks_msec() - _primed_at > 5000:
			_fail("PCM preview could not prepare its bounded playback buffer within five seconds.")
			return
	if active and not _held and (_eof or (_origin >= int(info.frames) and not loop_enabled)) and _capacity - _playback.get_frames_available() <= 0:
		close_file(); finished.emit()

func _pump() -> void:
	for burst in MAX_BURSTS:
		if not active or _reader == null or _playback == null or _eof: return
		var packet := _reader.take(_playback.get_frames_available())
		if packet.is_empty(): return
		if int(packet.generation) != _generation: continue
		var samples: PackedVector2Array = packet.samples
		if not _playback.push_buffer(samples): _fail("The native generator refused a bounded PCM chunk."); return
		_pushed += samples.size()
		if bool(packet.final): _eof = true

func close_file() -> void:
	active = false; player.stop(); player.stream = null; _playback = null
	if _reader != null: _reader.cancel(); _reader = null
	info = {}; duration = 0.0; _priming = false
	# Ordinary close/seek never waits for disk I/O. Release owned paths only
	# after the worker confirms its handle is closed.
	_reap_readers()

func _reap_readers(wait: bool = false) -> void:
	for index in range(_readers.size() - 1, -1, -1):
		var entry := _readers[index]
		var thread: Thread = entry.thread
		if not wait and thread.is_alive(): continue
		if entry.reader == _reader: continue
		thread.wait_to_finish()
		_readers.remove_at(index)
		if bool(entry.owned): released.emit(str(entry.path))

func _fail(message: String) -> void:
	close_file(); _last_error = message; failed.emit(message)

func _exit_tree() -> void:
	close_file()
	# Godot/OS synchronous file calls cannot be forcibly cancelled safely.
	# Final teardown must join owned workers; a stalled filesystem may delay it.
	_reap_readers(true)
