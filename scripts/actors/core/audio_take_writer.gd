extends RefCounted
## Bounded producer/consumer PCM capture. The audio ring is drained on the
## owner thread; only this writer's worker owns its file while recording.
const MAX_PENDING_BYTES := 2 * 1024 * 1024
const MAX_FILE_BYTES := 2 * 1024 * 1024 * 1024 - 44
var path := ""
var rate := 44100
var mono := false
var bytes_written := 0
var _thread: Thread
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _pending: Array[PackedByteArray] = []
var _pending_bytes := 0
var _closing := false
var _problem := ""

func start(destination: String, sample_rate: int, single_channel: bool) -> String:
	if _thread != null: return "The take writer is already active."
	path = destination; rate = sample_rate; mono = single_channel
	if rate < 8000 or rate > 192000: return "Unsupported recording sample rate."
	if FileAccess.file_exists(path): return "The take destination already exists."
	bytes_written=0;_pending.clear();_pending_bytes=0;_closing=false;_problem="";_wake=Semaphore.new()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return "Could not create the take file."
	_write_header(file, 0); file.close()
	_thread = Thread.new()
	var error := _thread.start(_run)
	if error != OK: _thread = null; return "Could not start the disk capture worker: " + error_string(error)
	return ""

func append_frames(samples: PackedVector2Array) -> void:
	if samples.is_empty(): return
	if _thread == null: fail("The take writer is not active."); return
	# The recorder drains at most 16384 frames per call.
	if samples.size() > 16384: fail("Capture block exceeded its frame budget."); return
	var channels := 1 if mono else 2
	var data := PackedByteArray(); data.resize(samples.size() * channels * 2)
	for index in samples.size():
		var sample := samples[index]
		var left := (sample.x + sample.y) * .5 if mono else sample.x
		data.encode_s16(index * channels * 2, clampi(roundi((left if is_finite(left) else 0.) * 32768.), -32768, 32767))
		if not mono: data.encode_s16(index * 4 + 2, clampi(roundi((sample.y if is_finite(sample.y) else 0.) * 32768.), -32768, 32767))
	_mutex.lock()
	if not _closing and _problem.is_empty():
		if _pending_bytes + data.size() > MAX_PENDING_BYTES:
			_problem = "The recording disk could not keep up. The captured prefix has been preserved."
		else:
			_pending.append(data); _pending_bytes += data.size()
	_mutex.unlock(); _wake.post()

func fail(message: String) -> void:
	_mutex.lock()
	if _problem.is_empty(): _problem = message
	_mutex.unlock()

func error() -> String:
	_mutex.lock(); var result := _problem; _mutex.unlock(); return result

func pending_bytes()->int:
	_mutex.lock();var result:=_pending_bytes;_mutex.unlock();return result

func request_finish() -> void:
	_mutex.lock(); _closing = true; _mutex.unlock(); _wake.post()

func busy() -> bool:
	return _thread != null and _thread.is_alive()

func finish() -> Dictionary:
	request_finish()
	if _thread != null: _thread.wait_to_finish(); _thread = null
	return {"path":path,"frames":bytes_written / (2 if mono else 4),"rate":rate,"channels":1 if mono else 2,"error":error()}

func _run() -> void:
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null: fail("The take file could not be opened by the capture worker."); return
	file.seek(44)
	var checkpoint := Time.get_ticks_msec()
	while true:
		_wake.wait()
		while true:
			_mutex.lock()
			var block := PackedByteArray()
			if not _pending.is_empty(): block = _pending.pop_front(); _pending_bytes -= block.size()
			var closing := _closing
			_mutex.unlock()
			if block.is_empty():
				if closing: _write_header(file, bytes_written); file.flush(); file.close(); return
				break
			if bytes_written + block.size() > MAX_FILE_BYTES:
				fail("The 2 GiB per-source recording limit was reached; the take prefix is retained."); continue
			file.store_buffer(block)
			if file.get_error() != OK:
				fail("Recording write failed; the last checkpoint is retained."); file.close(); return
			bytes_written += block.size()
			if Time.get_ticks_msec() >= checkpoint:
				_write_header(file, bytes_written); file.flush(); file.seek(44 + bytes_written)
				checkpoint = Time.get_ticks_msec() + 1000

func _write_header(file: FileAccess, length: int) -> void:
	var channels := 1 if mono else 2
	file.seek(0); file.store_buffer("RIFF".to_ascii_buffer()); file.store_32(36 + length)
	file.store_buffer("WAVEfmt ".to_ascii_buffer()); file.store_32(16); file.store_16(1); file.store_16(channels)
	file.store_32(rate); file.store_32(rate * channels * 2); file.store_16(channels * 2); file.store_16(16)
	file.store_buffer("data".to_ascii_buffer()); file.store_32(length)
