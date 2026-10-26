class_name KiwiAudioEncoderProcess
extends RefCounted
## One owner for each FFmpeg process and both pipes. Call on a worker thread.
## Script polling has a deadline. Godot's process creation/kill OS calls are
## synchronous and cannot themselves be given a hard deadline from GDScript.
const LOG_BYTES := 65536
const PROGRESS_BYTES := 8192
const READ_CHUNK_BYTES := 4096
const READ_BURST := 8
const QUIT_GRACE_MSEC := 1500
const STOP_WAIT_MSEC := 2000
const DRAIN_MSEC := 250
const DRAIN_BYTES := 4 * 1024 * 1024
const MAX_WALL_SECONDS := 86400.0

static func run(encoder: String, arguments: PackedStringArray, duration: float = 1.0, job: RefCounted = null, wall_seconds: float = 0.0) -> Dictionary:
	if job != null and job.is_cancelled():
		return {"success": false, "error": "Cancelled.", "cancelled": true, "process_exited": true, "diagnostics": ""}
	# Stdin belongs solely to this invocation and carries FFmpeg's quit command.
	# No shell, process-name termination, process-group kill, or saved PID reuse.
	var args := PackedStringArray(["-stdin", "-nostats"])
	for argument in arguments:
		if argument not in ["-nostdin", "-stdin"]: args.append(argument)
	var process := OS.execute_with_pipe(encoder, args, false)
	if process.is_empty():
		return {"success": false, "error": "FFmpeg could not be started. Check the configured executable path.", "process_exited": true, "diagnostics": ""}
	var pid := int(process.pid)
	var stdio: FileAccess = process.stdio
	var stderr: FileAccess = process.stderr
	var state := {"stderr": PackedByteArray(), "stdout": PackedByteArray(), "partial": "", "bytes": 0}
	var started := Time.get_ticks_msec()
	var expected := duration if is_finite(duration) and duration > 0.0 else 1.0
	var limit := clampf(wall_seconds if wall_seconds > 0.0 and is_finite(wall_seconds) else maxf(300.0, expected * 12.0 + 60.0), 1.0, MAX_WALL_SECONDS)
	var deadline := started + int(limit * 1000.0)
	var stop_started := -1
	var cancelled := false
	var timed_out := false
	var forced := false
	var quit_written := false
	var kill_error := OK
	# On Windows polling exit may release the process-owned pipe handles. Read
	# before the FIRST poll too: a small FFT/analysis job can finish before this
	# script reaches its first iteration. Polling first lost its entire result.
	_read_pipes(stdio, stderr, state, expected, job)
	var running := OS.is_process_running(pid)
	while running:
		_read_pipes(stdio, stderr, state, expected, job)
		var now := Time.get_ticks_msec()
		if stop_started < 0:
			cancelled = job != null and job.is_cancelled()
			timed_out = now >= deadline
			if cancelled or timed_out:
				stop_started = now
				stdio.store_buffer("q\n".to_utf8_buffer())
				quit_written = stdio.get_error() == OK
				if job != null: job.update(0.98, "Stopping audio encoder")
		if stop_started >= 0 and not forced and now - stop_started >= QUIT_GRACE_MSEC:
			# Check once immediately before the single kill. No other code receives
			# this PID while owned. On Unix a not-yet-reaped child retains its PID;
			# on Windows Godot uses the retained process handle for this child.
			running = OS.is_process_running(pid)
			if not running: break
			forced = true
			kill_error = OS.kill(pid)
		if forced and now - stop_started >= QUIT_GRACE_MSEC + STOP_WAIT_MSEC: break
		OS.delay_msec(20)
		_read_pipes(stdio, stderr, state, expected, job)
		running = OS.is_process_running(pid)
	# Capture status before releasing any pipe. A Windows forced kill erases
	# Godot's process record, so -1 is unknown, never a fabricated exit code.
	var reported_code := OS.get_process_exit_code(pid)
	var code := -1 if forced else reported_code
	var exited := not running and code != -1
	if forced and OS.get_name() != "Windows" and kill_error == OK: exited = true
	var drain_deadline := Time.get_ticks_msec() + DRAIN_MSEC
	var drained := 0
	while Time.get_ticks_msec() < drain_deadline and drained < DRAIN_BYTES:
		var before := int(state.bytes)
		_read_pipes(stdio, stderr, state, expected, null)
		var count := int(state.bytes) - before
		drained += count
		if count == 0:
			if exited: break
			OS.delay_msec(10)
	# Always close BOTH ends of stdio and the separate stderr pipe, including
	# cancellation, timeout, failed termination, and normal completion.
	stdio.close()
	stderr.close()
	process.clear()
	cancelled = cancelled or (job != null and job.is_cancelled())
	var log := (state.stderr as PackedByteArray).get_string_from_utf8()
	var error := ""
	if cancelled: error = "Cancelled."
	elif timed_out: error = "FFmpeg exceeded the %.0f-second render time limit." % limit
	elif code != 0: error = "FFmpeg failed (%s): %s" % [code, log.strip_edges()]
	if not exited:
		var warning := "Encoder exit could not be confirmed; its temporary files must be retained."
		error = warning if error.is_empty() else error + " " + warning
	var success := error.is_empty() and code == 0 and exited
	if job != null and success: job.update(1.0, "Audio render finished")
	return {"success": success, "error": error, "exit_code": code, "diagnostics": log,
		"stdout": (state.stdout as PackedByteArray).get_string_from_utf8(), "cancelled": cancelled,
		"timed_out": timed_out, "forced": forced, "quit_written": quit_written,
		"kill_error": kill_error, "reported_exit_code": reported_code, "process_exited": exited, "cleanup_pending": not exited,
		"seconds": float(Time.get_ticks_msec() - started) / 1000.0}

static func _read_pipes(stdio: FileAccess, stderr: FileAccess, state: Dictionary, duration: float, job: RefCounted) -> void:
	for burst in READ_BURST:
		var err := _available(stderr)
		if not err.is_empty():
			state.stderr = _tail_bytes(state.stderr, err, LOG_BYTES)
			state.bytes = int(state.bytes) + err.size()
		var out := _available(stdio)
		if not out.is_empty():
			state.stdout = _tail_bytes(state.stdout, out, LOG_BYTES)
			state.bytes = int(state.bytes) + out.size()
			var text := (str(state.partial) + out.get_string_from_utf8()).right(PROGRESS_BYTES)
			var lines := text.split("\n")
			state.partial = lines[lines.size() - 1]
			for index in maxi(0, lines.size() - 1):
				var line := str(lines[index]).strip_edges()
				if line.begins_with("out_time_us=") and job != null:
					var value := line.trim_prefix("out_time_us=")
					if value.is_valid_float(): job.update(clampf(float(value) / 1000000.0 / maxf(0.01, duration), 0.05, 0.98), "Rendering audio")
		if err.is_empty() and out.is_empty(): break

static func _available(pipe:FileAccess)->PackedByteArray:
	# Godot's Windows get_length() emits an engine error for normal broken-pipe
	# EOF. execute_with_pipe(..., false) creates PIPE_NOWAIT readers: ReadFile
	# returns up to the requested bytes immediately, including a short packet.
	# Do not use blocking read_line() or poll PeekNamedPipe at EOF.
	if OS.get_name()=="Windows":return pipe.get_buffer(READ_CHUNK_BYTES)
	var count:=mini(READ_CHUNK_BYTES,int(pipe.get_length()))
	return pipe.get_buffer(count) if count>0 else PackedByteArray()

static func _tail_bytes(previous: PackedByteArray, incoming: PackedByteArray, limit: int) -> PackedByteArray:
	previous.append_array(incoming)
	return previous.slice(previous.size() - limit) if previous.size() > limit else previous
