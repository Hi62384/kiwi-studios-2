class_name KiwiAudioInstruments
extends RefCounted
## Offline instrument renderer. Notes remain editable; playback consumes native WAVs.
## Oscillator patches are intentionally described as acoustic-like, not recordings.

const MAX_SECONDS := 300.0
const MAX_NOTES := 8192

static func presets() -> Array[Dictionary]:
	return _native().call("presets")

static func _patch(id: String, label: String, kind: String, attack: float, decay: float, sustain: float, release: float, cutoff: float, extra: Dictionary) -> Dictionary:
	return _native().call("patch", id, label, kind, attack, decay, sustain, release, cutoff, extra)

static func default_instrument(id: String) -> Dictionary:
	return _native().call("default_instrument", id)

static func midi_frequency(pitch: float) -> float:
	return _native().call("midi_frequency", pitch)

static func _number(settings: Dictionary, key: String, fallback: float, low: float, high: float) -> float:
	return _native().call("number", settings, key, fallback, low, high)

static func envelope(t: float, gate: float, attack: float, decay: float, sustain: float, release: float) -> float:
	return _native().call("envelope", t, gate, attack, decay, sustain, release)

static func _held_envelope(t: float, attack: float, decay: float, sustain: float) -> float:
	return _native().call("held_envelope", t, attack, decay, sustain)

static func render_notes(notes: Array, instrument: Dictionary, bpm: float, rate: int = 44100, job: RefCounted = null, tempos: Array = [], tempo_scale: float = 1.0) -> AudioStreamWAV:
	return _native().call("render_notes", notes, instrument, bpm, rate, job, tempos, tempo_scale)

static func _sample_mapping(patch: Dictionary, pitch: int, velocity: float) -> Dictionary:
	return _native().call("sample_mapping", patch, pitch, velocity)

static func _sample_at(data: PackedVector2Array, position: float) -> Vector2:
	return _native().call("sample_at", data, position)

static func _table(table: Array, phase: float) -> float:
	return _native().call("table", table, phase)

static func _note_bend(points: Array, beat: float) -> float:
	return _native().call("note_bend", points, beat)

static func _lowpass_coeff(cutoff: float, resonance: float, rate: int) -> PackedFloat64Array:
	return _native().call("lowpass_coeff", cutoff, resonance, rate)

static func _filter(value: float, coeff: PackedFloat64Array, state: PackedFloat64Array) -> float:
	var output := coeff[0] * value + coeff[1] * state[0] + coeff[2] * state[1] - coeff[3] * state[2] - coeff[4] * state[3]
	state[1] = state[0]
	state[0] = value
	state[3] = state[2]
	state[2] = output if is_finite(output) else 0.0
	return state[2]

static func _native() -> RefCounted:
	return Engine.get_singleton("KiwiNativeServices").call("service", "audio_instruments")
