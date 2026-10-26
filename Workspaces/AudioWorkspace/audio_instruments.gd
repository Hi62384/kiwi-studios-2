class_name KiwiAudioInstruments
extends RefCounted
## Offline instrument renderer. Notes remain editable; playback consumes native WAVs.
## Oscillator patches are intentionally described as acoustic-like, not recordings.

const MAX_SECONDS := 300.0
const MAX_NOTES := 8192

static func presets() -> Array[Dictionary]:
	return [
		_patch("piano", "Piano-like", "fm", 0.002, 0.7, 0.16, 0.35, 6800.0, {"ratio": 2.0, "modulation": 1.5}),
		_patch("organ", "Organ", "additive", 0.008, 0.05, 0.95, 0.09, 12000.0, {"harmonics": [1.0, 0.55, 0.4, 0.15, 0.12, 0.08]}),
		_patch("bells", "Bells", "fm", 0.003, 1.5, 0.03, 1.5, 15000.0, {"ratio": 2.756, "modulation": 2.2}),
		_patch("strings", "Strings-like", "subtractive", 0.18, 0.35, 0.75, 0.6, 4200.0, {"wave": "saw", "detune": 9.0, "width": 0.6, "vibrato": 0.08}),
		_patch("brass", "Brass-like", "subtractive", 0.035, 0.25, 0.68, 0.14, 2600.0, {"wave": "saw", "resonance": 0.18, "filter_envelope": 1.6}),
		_patch("bass", "Synth bass", "subtractive", 0.003, 0.2, 0.42, 0.09, 1200.0, {"wave": "saw", "resonance": 0.2, "filter_envelope": 1.2, "mono": true}),
		_patch("lead", "Synth lead", "subtractive", 0.008, 0.12, 0.7, 0.15, 6500.0, {"wave": "pulse", "detune": 4.0, "vibrato": 0.06, "mono": true}),
		_patch("poly", "Polyphonic synth", "subtractive", 0.02, 0.2, 0.6, 0.3, 3800.0, {"wave": "saw", "detune": 7.0, "width": 0.45}),
		_patch("pad", "Ambient pad", "additive", 0.5, 0.8, 0.72, 1.5, 3400.0, {"harmonics": [1.0, 0.3, 0.18, 0.08], "detune": 6.0, "width": 0.8, "modulation": 0.2}),
		_patch("pluck", "Pluck", "pluck", 0.002, 0.25, 0.05, 0.16, 6000.0, {"damping": 0.996}),
		_patch("fm", "FM synth", "fm", 0.008, 0.5, 0.4, 0.4, 10000.0, {"ratio": 2.0, "modulation": 2.0}),
		_patch("additive", "Additive synth", "additive", 0.02, 0.3, 0.6, 0.3, 12000.0, {"harmonics": [1.0, 0.3, 0.2, 0.1, 0.08]}),
		_patch("wavetable", "Wavetable synth", "wavetable", 0.02, 0.25, 0.65, 0.25, 6000.0, {"table_position": 0.4, "modulation": 0.25}),
		_patch("chip", "Chiptune pulse", "subtractive", 0.002, 0.08, 0.6, 0.04, 10000.0, {"wave": "pulse", "pulse_width": 0.25}),
		_patch("drums", "Electronic drums", "drums", 0.001, 0.18, 0.0, 0.04, 16000.0, {}),
		_patch("cinematic", "Cinematic impact", "modal", 0.004, 1.1, 0.02, 1.0, 5000.0, {"harmonics": [1.0, 1.48, 2.756, 4.2]}),
		_patch("sampler", "Sampler (import a sample)", "sampler", 0.003, 0.1, 1.0, 0.1, 18000.0, {"root_pitch": 60, "sample": "", "width": 1.0}),
		_patch("drum_sampler", "Drum sampler (import mappings)", "multisample", 0.001, 0.05, 1.0, 0.03, 18000.0, {"multisamples": [], "one_shot": true, "width": 1.0}),
		_patch("multisample", "Multisample instrument", "multisample", 0.003, 0.1, 1.0, 0.15, 18000.0, {"multisamples": [], "width": 1.0}),
		_patch("one_shot", "One-shot sample", "sampler", 0.001, 0.1, 1.0, 0.02, 18000.0, {"sample": "", "root_pitch": 60, "one_shot": true, "width": 1.0}),
		_patch("loop_player", "Loop player", "sampler", 0.004, 0.05, 1.0, 0.04, 18000.0, {"sample": "", "root_pitch": 60, "width": 1.0, "loop": true, "loop_start": 0.0, "loop_end": -1.0})]

static func _patch(id: String, label: String, kind: String, attack: float, decay: float, sustain: float, release: float, cutoff: float, extra: Dictionary) -> Dictionary:
	var patch := {"id": id, "label": label, "kind": kind, "attack": attack, "decay": decay, "sustain": sustain, "release": release, "filter": cutoff, "resonance": 0.0, "detune": 0.0, "modulation": 0.0, "vibrato": 0.0, "vibrato_rate": 5.0, "width": 0.0, "gain": 0.55, "seed": 1, "effects": []}
	patch.merge(extra, true)
	return patch

static func default_instrument(id: String) -> Dictionary:
	if id == "drum_kit": id = "drums"
	for instrument: Dictionary in presets():
		if instrument.id == id: return instrument.duplicate(true)
	return presets()[7].duplicate(true)

static func midi_frequency(pitch: float) -> float:
	return 440.0 * pow(2.0, (pitch - 69.0) / 12.0)

static func _number(settings: Dictionary, key: String, fallback: float, low: float, high: float) -> float:
	return clampf(KiwiAudioSynthesis.finite(settings.get(key, fallback), fallback), low, high)

static func envelope(t: float, gate: float, attack: float, decay: float, sustain: float, release: float) -> float:
	var level := _held_envelope(minf(t, gate), attack, decay, sustain)
	if t > gate: level *= maxf(0.0, 1.0 - (t - gate) / maxf(0.00001, release))
	return level

static func _held_envelope(t: float, attack: float, decay: float, sustain: float) -> float:
	if t < attack: return t / maxf(attack, 0.000001)
	if t < attack + decay: return lerpf(1.0, sustain, (t - attack) / maxf(decay, 0.000001))
	return sustain

## Invalid or missing required samples return null, not an invented replacement.
## Pass preloaded streams to worker calls when possible. ActorAudio.source is the
## shared import route; each distinct sample is decoded once per render.
static func render_notes(notes: Array, instrument: Dictionary, bpm: float, rate: int = 44100, job: RefCounted = null, tempos: Array = [], tempo_scale: float = 1.0) -> AudioStreamWAV:
	if notes.size() > MAX_NOTES: return null
	var patch := default_instrument(str(instrument.get("id", "poly")))
	patch.merge(instrument, true)
	var sample_rate := clampi(rate, 8000, 192000)
	var timing := KiwiAudioTempoMap.new(tempos, bpm, tempo_scale)
	if not timing.error.is_empty(): return null
	var beat_limit := timing.seconds_to_beat(MAX_SECONDS)
	var attack := _number(patch, "attack", 0.01, 0.0005, 20.0)
	var decay := _number(patch, "decay", 0.2, 0.001, 20.0)
	var sustain := _number(patch, "sustain", 0.6, 0.0, 1.0)
	var release := _number(patch, "release", 0.2, 0.003, 30.0)
	var clean: Array[Dictionary] = []
	var note_rng := RandomNumberGenerator.new()
	note_rng.seed = int(patch.get("seed", 1))
	var sample_cache: Dictionary = {}
	var duration := 0.01
	for entry: Variant in notes.slice(0, MAX_NOTES):
		if not entry is Dictionary: continue
		if not bool(entry.get("enabled", true)) or bool(entry.get("mute", false)): continue
		if note_rng.randf() > _number(entry, "probability", 1.0, 0.0, 1.0): continue
		var note: Dictionary = entry.duplicate(true)
		note["start"] = maxf(0.0, KiwiAudioSynthesis.finite(note.get("start", 0.0), 0.0))
		note["duration"] = maxf(0.0, KiwiAudioSynthesis.finite(note.get("duration", 0.25), 0.25))
		if float(note.start) > beat_limit or timing.beat_to_seconds(float(note.start) + float(note.duration)) > MAX_SECONDS: return null
		note["pitch"] = clampi(int(note.get("pitch", 60)), 0, 127)
		note["velocity"] = clampf(_number(note, "velocity", 0.8, 0.0, 1.0) * (1.2 if bool(note.get("accent", false)) else 1.0), 0.0, 1.0)
		note["pan"] = _number(note, "pan", 0.0, -1.0, 1.0)
		if note.velocity <= 0.0: continue
		var mapping := _sample_mapping(patch, int(note.pitch), float(note.velocity))
		if str(patch.get("kind", "")) in ["sampler", "multisample"]:
			if mapping.is_empty(): return null
			var source_value: Variant = mapping.get("sample", patch.get("sample", ""))
			var cache_key := str(source_value)
			if source_value is Resource: cache_key = str(source_value.get_instance_id())
			if not sample_cache.has(cache_key):
				var source := ActorAudio.source(source_value)
				if source == null: return null
				var decoded := KiwiAudioSourceCache.decode(source, sample_rate, 0.0, minf(source.get_length(), MAX_SECONDS), MAX_SECONDS)
				if not str(decoded.get("error", "")).is_empty(): return null
				sample_cache[cache_key] = decoded.samples
			if (sample_cache[cache_key] as PackedVector2Array).size() < 2: return null
			note["_samples"] = sample_cache[cache_key]
			note["_root"] = int(mapping.get("root_pitch", patch.get("root_pitch", 60)))
			if bool(patch.get("one_shot", false)):
				var data: PackedVector2Array = note._samples
				var sample_seconds := data.size() / float(sample_rate) / pow(2.0, (float(note.pitch) - float(note._root)) / 12.0)
				note.duration = timing.seconds_to_beat(timing.beat_to_seconds(float(note.start)) + sample_seconds) - float(note.start)
		var ratchets := clampi(int(note.get("ratchets", 1)), 1, 8)
		var note_duration := float(note.duration)
		for ratchet in ratchets:
			if clean.size() >= MAX_NOTES: return null
			var repeated := note.duplicate(true)
			repeated.start = float(note.start) + ratchet * note_duration / ratchets
			repeated.duration = note_duration / ratchets
			# The copy alone gains seconds. Canonical starts, lengths and ratchets
			# stay in musical beats, including gates crossing a tempo change.
			repeated["_start_seconds"] = timing.beat_to_seconds(float(repeated.start))
			repeated["_gate_seconds"] = maxf(1.0 / sample_rate, timing.beat_to_seconds(float(repeated.start) + float(repeated.duration)) - float(repeated._start_seconds))
			clean.append(repeated)
			duration = maxf(duration, float(repeated._start_seconds) + float(repeated._gate_seconds) + release)
	clean.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.start) < float(b.start))
	if duration > MAX_SECONDS: return null
	if bool(patch.get("mono", false)):
		for i in clean.size() - 1:
			clean[i]._gate_seconds = maxf(1.0 / sample_rate, minf(float(clean[i]._gate_seconds), float(clean[i + 1]._start_seconds) - float(clean[i]._start_seconds)))
	var evaluations := 0.0
	for note in clean: evaluations += (float(note._gate_seconds)+release)*sample_rate
	if evaluations > 64000000: return null
	var total_frames := maxi(2, int(ceil(minf(duration, MAX_SECONDS) * sample_rate)))
	var mix := PackedVector2Array()
	mix.resize(total_frames)
	for note_index in clean.size():
		if job != null:
			if job.is_cancelled(): return null
			job.update(float(note_index)/maxi(1,clean.size()),"Rendering instrument notes")
		var note: Dictionary = clean[note_index]
		var start := int(round(float(note._start_seconds) * sample_rate))
		if start >= total_frames: continue
		var gate := float(note._gate_seconds)
		var frames := mini(total_frames - start, maxi(2, int(ceil((gate + release) * sample_rate))))
		var hz := midi_frequency(float(note.pitch))
		var detune := _number(patch, "detune", 0.0, 0.0, 50.0)
		var width := _number(patch, "width", 0.0, 0.0, 1.0)
		var vibrato := _number(patch, "vibrato", 0.0, 0.0, 2.0)
		var vibrato_rate := _number(patch, "vibrato_rate", 5.0, 0.05, 20.0)
		var gain := _number(patch, "gain", 0.55, 0.0, 2.0) * pow(float(note.velocity), 1.3)
		var pan := float(note.pan)
		var pan_gains := Vector2(sqrt((1.0 - pan) * 0.5), sqrt((1.0 + pan) * 0.5))
		var phase := 0.0
		var phase_right := 0.0
		var filter_state_left := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
		var filter_state_right := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
		var coeff := _lowpass_coeff(_number(patch, "filter", 6000.0, 20.0, sample_rate * 0.44), _number(patch, "resonance", 0.0, 0.0, 0.95), sample_rate)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(patch.get("seed", 1)) + int(note.pitch) * 7919 + int(float(note.start) * 480.0) * 31
		var delay := PackedFloat32Array()
		var delay_position := 0
		var kind := str(patch.get("kind", "subtractive"))
		if kind == "pluck":
			delay.resize(maxi(2, int(sample_rate / hz)))
			for j in delay.size(): delay[j] = rng.randf_range(-1.0, 1.0)
		var sample_data: PackedVector2Array = note.get("_samples", PackedVector2Array())
		var sample_ratio := pow(2.0, (float(note.pitch) - float(note.get("_root", 60))) / 12.0)
		var mods: Array = patch.get("modulators", []).duplicate(true)
		var pan_modulated:=mods.any(func(item:Dictionary):return str(item.get("target",""))=="pan" and bool(item.get("enabled",true)))
		var bend_points: Array = note.get("pitch_bend", [])
		for modulator in mods:
			if str(modulator.get("kind","")) == "velocity": modulator.velocity=float(note.velocity)
		for i in frames:
			if job != null and i % 8192 == 0 and job.is_cancelled(): return null
			var t := float(i) / sample_rate
			var bend := 0.0
			if not bend_points.is_empty(): bend = _note_bend(bend_points, timing.seconds_to_beat(float(note._start_seconds) + t) - float(note.start))
			var frequency := hz * pow(2.0, (sin(t * TAU * vibrato_rate) * vibrato * minf(1.0, t * 6.0) + bend + KiwiAudioSynthesis.modulation(mods, "pitch", t, gate, int(patch.get("seed", 1)))) / 12.0)
			frequency = minf(frequency, sample_rate * 0.22)
			var step := frequency / sample_rate
			phase += step * pow(2.0, -detune / 1200.0)
			phase_right += step * pow(2.0, detune / 1200.0)
			var env := envelope(t, gate, attack, decay, sustain, release)
			var value := Vector2.ZERO
			match kind:
				"subtractive":
					var shape := str(patch.get("wave", "saw"))
					var pulse_width := _number(patch, "pulse_width", 0.5, 0.05, 0.95)
					value = Vector2(KiwiAudioSynthesis.wave(phase, step, shape, pulse_width), KiwiAudioSynthesis.wave(phase_right, step, shape, pulse_width))
				"fm":
					var ratio := _number(patch, "ratio", 2.0, 0.25, 10.0)
					var index := _number(patch, "modulation", 2.0, 0.0, 8.0) * exp(-t / maxf(0.02, decay)) * (0.2 + 0.8 * float(note.velocity))
					value.x = sin(TAU * phase + sin(TAU * phase * ratio) * index)
					value.y = sin(TAU * phase_right + sin(TAU * phase_right * ratio) * index)
				"additive":
					var harmonics: Array = patch.get("harmonics", [1.0, 0.3, 0.2])
					var total := 0.0
					for k in mini(harmonics.size(), 24):
						if frequency * (k + 1) >= sample_rate * 0.44: break
						var amount := KiwiAudioSynthesis.finite(harmonics[k], 0.0)
						total += absf(amount)
						value.x += sin(TAU * phase * (k + 1)) * amount
						value.y += sin(TAU * phase_right * (k + 1)) * amount
					value /= maxf(total, 1.0)
				"wavetable":
					var table: Array = patch.get("wavetable", [])
					if table.size() >= 2:
						value = Vector2(_table(table, phase), _table(table, phase_right))
					else:
						var position := clampf(_number(patch, "table_position", 0.4, 0.0, 1.0) + sin(t * 2.0) * _number(patch, "modulation", 0.0, 0.0, 0.5), 0.0, 1.0)
						value = Vector2(lerpf(sin(TAU * phase), KiwiAudioSynthesis.wave(phase, step, "saw"), position), lerpf(sin(TAU * phase_right), KiwiAudioSynthesis.wave(phase_right, step, "saw"), position))
				"pluck":
					var next := (delay_position + 1) % delay.size()
					var plucked := delay[delay_position]
					delay[delay_position] = (plucked + delay[next]) * 0.5 * _number(patch, "damping", 0.996, 0.8, 0.9999)
					delay_position = next
					value = Vector2(plucked, plucked)
				"modal":
					var ratios: Array = patch.get("harmonics", [1.0, 1.48, 2.756, 4.2])
					for k in mini(ratios.size(), 12):
						var modal_hz := frequency * KiwiAudioSynthesis.finite(ratios[k], 1.0)
						if modal_hz < sample_rate * 0.44:
							var partial := sin(t * TAU * modal_hz) * exp(-t * (0.6 + 0.5 * k)) / (k + 1)
							value += Vector2(partial, partial) * 0.55
				"drums":
					var noise := rng.randf_range(-1.0, 1.0)
					var pitch := int(note.pitch)
					var drum := 0.0
					if pitch in [35, 36]:
						drum = sin(TAU * (48.0 * t + 2.8 * (1.0 - exp(-t * 30.0)))) * exp(-t * 11.0) + noise * exp(-t * 100.0) * 0.15
					elif pitch in [38, 40]:
						drum = noise * exp(-t * 19.0) * 0.7 + sin(TAU * 180.0 * t) * exp(-t * 22.0) * 0.3
					elif pitch in [42, 44, 46]:
						var metallic := 0.0
						for f in [3100.0, 4517.0, 5971.0]:
							if float(f) < sample_rate * 0.44: metallic += sin(t * TAU * float(f)) / 3.0
						drum = (noise * 0.65 + metallic * 0.35) * exp(-t * (6.0 if pitch == 46 else 65.0))
					elif pitch in [49, 51, 57]:
						drum = (noise * 0.7 + sin(t * TAU * 3421.0) * 0.3) * exp(-t * 3.5)
					elif pitch == 39:
						var clap_age := fposmod(t, 0.018) if t < 0.072 else t - 0.072
						drum = noise * exp(-clap_age * 50.0) * exp(-t * 12.0)
					else: drum = sin(TAU * hz * t * (1.0 + 0.15 * exp(-t * 20.0))) * exp(-t * 13.0) + noise * 0.15 * exp(-t * 50.0)
					value = Vector2(drum, drum)
					env = minf(1.0, t / 0.001) * maxf(0.0, minf(1.0, (gate + release - t) / 0.006))
				"sampler", "multisample":
					var position := float(i) * sample_ratio
					if bool(patch.get("loop", false)):
						var loop_start := clampf(_number(patch, "loop_start", 0.0, 0.0, MAX_SECONDS) * sample_rate, 0.0, maxf(0.0, sample_data.size() - 2.0))
						var end_setting := KiwiAudioSynthesis.finite(patch.get("loop_end", -1.0), -1.0)
						var loop_end := sample_data.size() - 1.0 if end_setting < 0.0 else clampf(end_setting * sample_rate, loop_start + 1.0, sample_data.size() - 1.0)
						if position >= loop_end: position = loop_start + fposmod(position - loop_start, maxf(1.0, loop_end - loop_start))
						value = _sample_at(sample_data, position)
						var crossfade := minf(sample_rate * 0.005, (loop_end - loop_start) * 0.25)
						if crossfade > 0.0 and position > loop_end - crossfade:
							var blend := (position - (loop_end - crossfade)) / crossfade
							value = value.lerp(_sample_at(sample_data, loop_start + position - (loop_end - crossfade)), blend)
					else: value = _sample_at(sample_data, position)
			if i % 64 == 0:
				var cutoff := _number(patch, "filter", 6000.0, 20.0, sample_rate * 0.44)
				cutoff *= pow(2.0, _number(patch, "filter_envelope", 0.0, -4.0, 6.0) * env + KiwiAudioSynthesis.modulation(mods, "cutoff", t, gate, int(patch.get("seed", 1))))
				coeff = _lowpass_coeff(cutoff, _number(patch, "resonance", 0.0, 0.0, 0.95), sample_rate)
			value = Vector2(_filter(value.x, coeff, filter_state_left), _filter(value.y, coeff, filter_state_right))
			var mono := (value.x + value.y) * 0.5
			value = Vector2(lerpf(mono, value.x, width), lerpf(mono, value.y, width))
			var amplitude := clampf(1.0 + KiwiAudioSynthesis.modulation(mods, "amplitude", t, gate, int(patch.get("seed", 1))), 0.0, 4.0)
			if pan_modulated:
				var moving_pan:=clampf(pan+KiwiAudioSynthesis.modulation(mods,"pan",t,gate,int(patch.get("seed",1))),-1,1)
				pan_gains=Vector2(sqrt((1.-moving_pan)*.5),sqrt((1.+moving_pan)*.5))
			var safety_fade := minf(1.0, i / maxf(1.0, sample_rate * 0.001)) * minf(1.0, (frames - 1 - i) / maxf(1.0, sample_rate * 0.003))
			mix[start + i] += value * pan_gains * gain * env * amplitude * safety_fade
	var maximum := 0.0
	for frame in mix: maximum = maxf(maximum, maxf(absf(frame.x), absf(frame.y)))
	if maximum > 0.96:
		for i in mix.size(): mix[i] *= 0.96 / maximum
	return KiwiAudioSourceCache.to_wav(mix, sample_rate, true)

static func _sample_mapping(patch: Dictionary, pitch: int, velocity: float) -> Dictionary:
	if str(patch.get("kind", "")) == "sampler": return patch
	if str(patch.get("kind", "")) != "multisample": return {}
	for entry: Variant in patch.get("multisamples", []):
		if not entry is Dictionary: continue
		if pitch >= int(entry.get("low", 0)) and pitch <= int(entry.get("high", 127)) and velocity >= float(entry.get("velocity_low", 0.0)) and velocity <= float(entry.get("velocity_high", 1.0)):
			return entry
	return {}

static func _sample_at(data: PackedVector2Array, position: float) -> Vector2:
	if position < 0.0 or position >= data.size() - 1: return Vector2.ZERO
	var index := int(position)
	var fade := minf(1.0, position / 64.0) * minf(1.0, (data.size() - 1.0 - position) / 64.0)
	return data[index].lerp(data[index + 1], position - index) * fade

static func _table(table: Array, phase: float) -> float:
	var position := fposmod(phase, 1.0) * table.size()
	var index := int(position)
	return lerpf(KiwiAudioSynthesis.finite(table[index], 0.0), KiwiAudioSynthesis.finite(table[(index + 1) % table.size()], 0.0), position - index)

static func _note_bend(points: Array, beat: float) -> float:
	var previous := Vector2.ZERO
	for entry: Variant in points:
		if not entry is Dictionary: continue
		var point := Vector2(float(entry.get("time", 0.0)), float(entry.get("semitones", 0.0)))
		if point.x > beat:
			return lerpf(previous.y, point.y, clampf((beat - previous.x) / maxf(0.000001, point.x - previous.x), 0.0, 1.0))
		previous = point
	return previous.y

static func _lowpass_coeff(cutoff: float, resonance: float, rate: int) -> PackedFloat64Array:
	var omega := TAU * clampf(cutoff, 20.0, rate * 0.44) / rate
	var cosine := cos(omega)
	var alpha := sin(omega) / (2.0 * (0.5 + resonance * 8.0))
	var a0 := 1.0 + alpha
	return PackedFloat64Array([(1.0 - cosine) * 0.5 / a0, (1.0 - cosine) / a0, (1.0 - cosine) * 0.5 / a0, -2.0 * cosine / a0, (1.0 - alpha) / a0])

static func _filter(value: float, coeff: PackedFloat64Array, state: PackedFloat64Array) -> float:
	var output := coeff[0] * value + coeff[1] * state[0] + coeff[2] * state[1] - coeff[3] * state[2] - coeff[4] * state[3]
	state[1] = state[0]
	state[0] = value
	state[3] = state[2]
	state[2] = output if is_finite(output) else 0.0
	return state[2]

