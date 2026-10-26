class_name KiwiAudioDoppler
extends RefCounted
## Offline, deterministic moving-source acoustics for the ordered render stack.
## The renderer stages the complete upstream signal as stereo f32le, calls this
## processor, then continues the downstream stack. Never use it on the original
## asset or substitute stereo panning for the propagation-time mapping.
##
## Source emission time u and receiver time t obey:
##   x(u) = travel * tanh(speed * (u - pass_time) / travel)
##   R(u) = sqrt(closest^2 + x(u)^2)
##   t = u + R(u) / 343
## Therefore du/dt = 343 / (343 + radial_velocity(u)). Approaching audio
## genuinely pitches up and receding audio pitches down. The pass eases to rest
## at +/-travel, bounding delay and render tails. Geometry is deliberately static.
## This is a stationary listener in still air: no supersonic motion, moving
## listener, reflections, air absorption, binaural/HRTF or relativistic model.

const SOUND_SPEED := 343.0
const MAX_SPEED := 100.0
const MIN_RATE := 8000
const MAX_RATE := 192000
const MAX_STAGE_BYTES := 512 * 1024 * 1024
const MAX_PROCESSING_MSEC := 60000
const TIMEOUT_ERROR := "Doppler exceeded the 60-second processing budget. Split or bake a shorter region."
const FRAME_BYTES := 8
const BLOCK_FRAMES := 256
const CACHE_FRAMES := 4096
const HALF_TAPS := 16
const TAPS := HALF_TAPS * 2
const PHASES := 1024

# Two independent fixed-size readers avoid cache thrashing between the aligned
# dry signal and its delayed wet signal. Finite samples are checked as read;
# neither PCM nor the complete source is retained in memory.
class FloatReader extends RefCounted:
	var file: FileAccess
	var frames: int = 0
	var first: int = -1
	var values := PackedVector2Array()
	var error := ""

	func open(path: String) -> bool:
		file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			error = "Could not open the staged Doppler input."
			return false
		var size := file.get_length()
		if size <= 0 or size % FRAME_BYTES != 0 or size > MAX_STAGE_BYTES:
			error = "Doppler needs a nonempty stereo f32le stage no larger than 512 MiB. Split or bake a shorter region."
			close()
			return false
		frames = size / FRAME_BYTES
		return true

	func sample(frame: int) -> Vector2:
		if frame < 0 or frame >= frames or not error.is_empty(): return Vector2.ZERO
		if frame < first or frame >= first + values.size():
			# Keep overlap behind the requested tap, as the next output sample
			# starts its sinc window slightly before the current window ends.
			first = maxi(0, frame - CACHE_FRAMES / 4)
			var count := mini(CACHE_FRAMES, frames - first)
			file.seek(first * FRAME_BYTES)
			var data := file.get_buffer(count * FRAME_BYTES)
			if data.size() != count * FRAME_BYTES:
				error = "Could not read the complete staged Doppler input."
				return Vector2.ZERO
			values.resize(count)
			for index in count:
				var left := data.decode_float(index * FRAME_BYTES)
				var right := data.decode_float(index * FRAME_BYTES + 4)
				if not is_finite(left) or not is_finite(right):
					error = "Non-finite audio in the staged Doppler input."
					return Vector2.ZERO
				values[index] = Vector2(left, right)
		return values[frame - first]

	func close() -> void:
		if file != null: file.close()
		file = null
		values.clear()

static func _bounded(p: Dictionary, key: String, fallback: float, low: float, high: float) -> float:
	var raw: Variant = p.get(key, fallback)
	if not (raw is int or raw is float): return fallback
	var value := float(raw)
	return clampf(value, low, high) if is_finite(value) else fallback

static func parameters(p: Dictionary) -> Dictionary:
	return {
		"speed": _bounded(p, "speed", 35.0, 0.0, MAX_SPEED),
		"closest": _bounded(p, "closest", 4.0, 1.0, 50.0),
		"travel": _bounded(p, "travel", 100.0, 10.0, 300.0),
		"pass_time": _bounded(p, "pass_time", 2.0, 0.0, 3600.0),
		"reverse": _bounded(p, "reverse", 0.0, 0.0, 1.0),
		"attenuation": _bounded(p, "attenuation", 1.0, 0.0, 1.0),
		"width": _bounded(p, "width", 0.7, 0.0, 1.0),
		"mix": _bounded(p, "mix", 1.0, 0.0, 1.0)
	}

static func tail_seconds(source_parameters: Dictionary) -> float:
	var p := parameters(source_parameters)
	if float(p.mix) <= 0.0: return 0.0
	var distance := sqrt(float(p.closest) * float(p.closest) + float(p.travel) * float(p.travel))
	# Include zero-padded interpolation support at every supported sample rate.
	# The same bound determines process_f32's exact declared output frame count.
	var support := float(HALF_TAPS + 1) / MIN_RATE * (1.0 + float(p.speed) / SOUND_SPEED)
	return distance / SOUND_SPEED + support

static func _distance(time: float, speed: float, closest: float, travel: float, pass_time: float) -> float:
	var x := travel * tanh(speed * (time - pass_time) / travel)
	return sqrt(closest * closest + x * x)

static func _kernels(speed: float, job: RefCounted, started: int) -> PackedFloat64Array:
	# Fixed conservative source low-pass for the maximum possible pitch ratio.
	# A finite Blackman-windowed sinc reduces aliasing; it is not an ideal brick
	# wall. The resulting high-frequency roll-off is an explicit acoustic limit.
	var cutoff := 0.94 * (1.0 - speed / SOUND_SPEED)
	var table := PackedFloat64Array()
	table.resize(PHASES * TAPS)
	for phase in PHASES:
		if phase % 64 == 0:
			if job != null and job.is_cancelled(): return PackedFloat64Array()
			if Time.get_ticks_msec() - started >= MAX_PROCESSING_MSEC: return PackedFloat64Array()
		var fraction := float(phase) / PHASES
		var total := 0.0
		for tap in TAPS:
			var offset := float(tap - HALF_TAPS + 1) - fraction
			var window := 0.42 + 0.5 * cos(PI * offset / HALF_TAPS) + 0.08 * cos(TAU * offset / HALF_TAPS)
			var weight := cutoff if absf(offset) < 0.000000001 else sin(PI * cutoff * offset) / (PI * offset)
			weight *= window
			table[phase * TAPS + tap] = weight
			total += weight
		for tap in TAPS: table[phase * TAPS + tap] /= total
	return table

static func _resample(reader: FloatReader, position: float, table: PackedFloat64Array) -> Vector2:
	var base := floori(position)
	var phase := int(round((position - base) * PHASES))
	if phase == PHASES:
		base += 1
		phase = 0
	var value := Vector2.ZERO
	var first := base - HALF_TAPS + 1
	for tap in TAPS: value += reader.sample(first + tap) * table[phase * TAPS + tap]
	return value

static func _failure(message: String, dry: FloatReader, wet: FloatReader, output: FileAccess, output_path: String) -> Dictionary:
	dry.close()
	wet.close()
	if output != null:
		output.close()
		# This path was created only after rejecting an existing destination.
		DirAccess.remove_absolute(output_path)
	return {"success": false, "error": message}

static func process_f32(input_path: String, output_path: String, effect: Dictionary, rate: int, job: RefCounted = null) -> Dictionary:
	# Raw contract: interleaved stereo IEEE float32, little endian, no WAV header.
	# The caller supplies the exact sample rate and keeps both files job-owned.
	# This is background/offline work. The cooperative wall-time budget cannot
	# interrupt a blocked filesystem operation; it is checked between work blocks.
	var started := Time.get_ticks_msec()
	if rate < MIN_RATE or rate > MAX_RATE:
		return {"success": false, "error": "Doppler supports render rates from 8000 to 192000 Hz."}
	var absolute_input := ProjectSettings.globalize_path(input_path).simplify_path()
	var absolute_output := ProjectSettings.globalize_path(output_path).simplify_path()
	if absolute_input == absolute_output or FileAccess.file_exists(absolute_output):
		return {"success": false, "error": "Doppler requires a new temporary output; the input and existing files are never overwritten."}
	if str(effect.get("type", "")) != "doppler":
		return {"success": false, "error": "The staged processor is only for a Doppler effect."}
	for curve in effect.get("automation", {}).values():
		if not (curve as Array).is_empty():
			return {"success": false, "error": "Doppler uses static controls. Remove its parameter automation before rendering."}
	if job != null and job.is_cancelled(): return {"success": false, "error": "Cancelled."}
	var p := parameters(effect.get("parameters", {}))
	var mix := float(p.mix) if bool(effect.get("enabled", true)) else 0.0
	var dry := FloatReader.new()
	var wet := FloatReader.new()
	if not dry.open(absolute_input): return _failure(dry.error, dry, wet, null, absolute_output)
	if mix > 0.0 and not wet.open(absolute_input): return _failure(wet.error, dry, wet, null, absolute_output)
	var added_tail := tail_seconds(p) if mix > 0.0 else 0.0
	var output_frames := dry.frames + ceili(added_tail * rate)
	if output_frames > MAX_STAGE_BYTES / FRAME_BYTES:
		return _failure("Doppler and its propagation tail exceed the 512 MiB stage limit. Split or bake a shorter region.", dry, wet, null, absolute_output)
	var kernels := _kernels(float(p.speed), job, started) if mix > 0.0 else PackedFloat64Array()
	if job != null and job.is_cancelled(): return _failure("Cancelled.", dry, wet, null, absolute_output)
	if Time.get_ticks_msec() - started >= MAX_PROCESSING_MSEC or (mix > 0.0 and kernels.is_empty()):
		return _failure(TIMEOUT_ERROR, dry, wet, null, absolute_output)
	var output := FileAccess.open(absolute_output, FileAccess.WRITE)
	if output == null: return _failure("Could not create the staged Doppler output.", dry, wet, null, absolute_output)
	var speed := float(p.speed)
	var closest := float(p.closest)
	var travel := float(p.travel)
	var pass_time := float(p.pass_time)
	var attenuation := float(p.attenuation)
	var width := float(p.width)
	var direction := -1.0 if float(p.reverse) >= 0.5 else 1.0
	var max_delay := sqrt(closest * closest + travel * travel) / SOUND_SPEED
	var wet_start := _distance(0.0, speed, closest, travel, pass_time) / SOUND_SPEED
	var source_end := float(dry.frames + HALF_TAPS) / rate
	var wet_end := source_end + _distance(source_end, speed, closest, travel, pass_time) / SOUND_SPEED
	var previous_source := 0.0
	var previous_ratio := 1.0
	var cursor := 0
	while cursor < output_frames:
		if Time.get_ticks_msec() - started >= MAX_PROCESSING_MSEC:
			return _failure(TIMEOUT_ERROR, dry, wet, output, absolute_output)
		if job != null:
			if job.is_cancelled(): return _failure("Cancelled.", dry, wet, output, absolute_output)
			job.update(0.05 + 0.9 * float(cursor) / output_frames, "Rendering Doppler propagation")
		var count := mini(BLOCK_FRAMES, output_frames - cursor)
		var bytes := PackedByteArray()
		bytes.resize(count * FRAME_BYTES)
		for index in count:
			var frame := cursor + index
			var time := float(frame) / rate
			# Dry remains at t. Moving the dry read pointer with wet would conceal
			# the physical propagation delay and turn the blend into a gain control.
			var value := dry.sample(frame) * (1.0 - mix)
			if mix > 0.0 and time >= wet_start and time <= wet_end:
				# Strictly increasing arrival time: derivative >= 1 - 100/343.
				# Safeguarded Newton stays in the physically valid source-time bracket.
				var low := maxf(0.0, time - max_delay)
				var high := time - closest / SOUND_SPEED
				var source_time := clampf(previous_source + previous_ratio / rate, low, high)
				var distance := closest
				var x := 0.0
				var derivative := 1.0
				var converged := false
				for iteration in 12:
					var eased := tanh(speed * (source_time - pass_time) / travel)
					x = travel * eased
					distance = sqrt(closest * closest + x * x)
					var radial := x / distance * speed * (1.0 - eased * eased)
					derivative = 1.0 + radial / SOUND_SPEED
					var residual := source_time + distance / SOUND_SPEED - time
					if absf(residual) <= 0.001 / rate:
						converged = true
						break
					if residual > 0.0: high = source_time
					else: low = source_time
					var next := source_time - residual / derivative
					source_time = next if next > low and next < high else (low + high) * 0.5
				if not converged:
					return _failure("Doppler propagation-time inversion did not converge.", dry, wet, output, absolute_output)
				previous_source = source_time
				previous_ratio = 1.0 / derivative
				var shifted := _resample(wet, source_time * rate, kernels)
				# closest/R is inverse-distance pressure normalized at the pass.
				# Stereo is an optional balance of the original channels, not HRTF.
				var gain := lerpf(1.0, closest / distance, attenuation)
				var pan := clampf(direction * width * x / distance, -1.0, 1.0)
				shifted *= Vector2(minf(1.0, 1.0 - pan), minf(1.0, 1.0 + pan))
				value += shifted * (mix * gain)
			if not dry.error.is_empty(): return _failure(dry.error, dry, wet, output, absolute_output)
			if not wet.error.is_empty(): return _failure(wet.error, dry, wet, output, absolute_output)
			if not is_finite(value.x) or not is_finite(value.y):
				return _failure("Non-finite audio produced by Doppler.", dry, wet, output, absolute_output)
			# Keep float headroom. Final output limiting remains the renderer's job.
			bytes.encode_float(index * FRAME_BYTES, value.x)
			bytes.encode_float(index * FRAME_BYTES + 4, value.y)
		output.store_buffer(bytes)
		if output.get_error() != OK: return _failure("Could not write the complete Doppler stage.", dry, wet, output, absolute_output)
		cursor += count
	if job != null and job.is_cancelled(): return _failure("Cancelled.", dry, wet, output, absolute_output)
	if Time.get_ticks_msec() - started >= MAX_PROCESSING_MSEC: return _failure(TIMEOUT_ERROR, dry, wet, output, absolute_output)
	output.flush()
	if output.get_error() != OK: return _failure("Could not flush the Doppler stage.", dry, wet, output, absolute_output)
	if Time.get_ticks_msec() - started >= MAX_PROCESSING_MSEC: return _failure(TIMEOUT_ERROR, dry, wet, output, absolute_output)
	output.close()
	dry.close()
	wet.close()
	return {"success": true, "error": "", "frames": output_frames, "duration": float(output_frames) / rate, "sample_rate": rate, "channels": 2, "tail_seconds": float(ceili(added_tail * rate)) / rate}
