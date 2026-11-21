class_name KiwiAudioComposer
extends RefCounted
## Deterministic, editable musical sketches. No external models or subscriptions.
## Time is quarter-note beats everywhere, including non-4/4 time signatures.

const SCALE_INTERVALS := {
	"major": [0, 2, 4, 5, 7, 9, 11], "minor": [0, 2, 3, 5, 7, 8, 10],
	"dorian": [0, 2, 3, 5, 7, 9, 10], "mixolydian": [0, 2, 4, 5, 7, 9, 10],
	"pentatonic": [0, 2, 4, 7, 9], "minor_pentatonic": [0, 3, 5, 7, 10],
	"harmonic_minor": [0, 2, 3, 5, 7, 8, 11], "phrygian": [0, 1, 3, 5, 7, 8, 10],
	"lydian": [0, 2, 4, 6, 7, 9, 11], "whole_tone": [0, 2, 4, 6, 8, 10]}
const STYLE_NAMES := ["Ambient", "Cinematic", "Horror", "Suspense", "Comedy", "Electronic", "Synthwave", "Lo-Fi", "Chiptune", "Jazz-Inspired", "Orchestral-Inspired", "Acoustic-Inspired", "Action", "Fantasy", "Background Music", "Cartoon Music"]

static func styles() -> Array:
	return _native().call("styles")

static func scales() -> Dictionary:
	return _native().call("scales")

static func key_pitch(key: Variant) -> int:
	return _native().call("key_pitch", key)

static func scale_pitch(degree: int, root: int = 60, scale_name: String = "major") -> int:
	return _native().call("scale_pitch", degree, root, scale_name)

static func quantize_pitch(pitch: int, key: Variant = 0, scale_name: String = "major") -> int:
	return _native().call("quantize_pitch", pitch, key, scale_name)

static func chord(root: int, scale_name: String, degree: int, inversion: int = 0, seventh: bool = false) -> Array[int]:
	return _native().call("chord", root, scale_name, degree, inversion, seventh)

static func voice_lead(pitches: Array, previous: Array) -> Array[int]:
	return _native().call("voice_lead", pitches, previous)

static func chord_suggestions(degree: int, scale_name: String = "major") -> Array:
	return _native().call("chord_suggestions", degree, scale_name)

static func new_note(pitch: int, start: float, duration: float, velocity: float = 0.8, pan: float = 0.0) -> Dictionary:
	return _native().call("new_note", pitch, start, duration, velocity, pan)

static func _note(pitch: int, start: float, duration: float, velocity: float, role: String, section_id: String, index: int, seed_value: int) -> Dictionary:
	return _native().call("note", pitch, start, duration, velocity, role, section_id, index, seed_value)

static func _style(name: String) -> Dictionary:
	return _native().call("style", name)

static func generate(settings: Dictionary) -> Dictionary:
	return _native().call("generate", settings)

static func _append_note(part: Dictionary, pitch: int, start: float, duration: float, velocity: float, section_id: String, seed_value: int) -> void:
	_native().call("append_note", part, pitch, start, duration, velocity, section_id, seed_value)

static func _nearest_chord(pitch: int, pitches: Array) -> int:
	return _native().call("nearest_chord", pitch, pitches)

static func _section_at(sections: Array, beat: float) -> Dictionary:
	return _native().call("section_at", sections, beat)

static func _ends_section(section: Dictionary, beat: float) -> bool:
	return _native().call("ends_section", section, beat)

static func regenerate(settings: Dictionary, previous: Dictionary, role: String = "", section_id: String = "") -> Dictionary:
	return _native().call("regenerate", settings, previous, role, section_id)

static func pattern_notes(pattern: Dictionary, repeats: int = 1, seed_value: int = 1) -> Array[Dictionary]:
	return _native().call("pattern_notes", pattern, repeats, seed_value)

static func drum_pattern(style: String, energy: float = 0.6, complexity: float = 0.5, fill: bool = false, seed_value: int = 1) -> Dictionary:
	return _native().call("drum_pattern", style, energy, complexity, fill, seed_value)

static func quantize_notes(notes: Array, grid: float = 0.25, strength: float = 1.0) -> Array:
	return _native().call("quantize_notes", notes, grid, strength)

static func humanize(notes: Array, timing: float = 0.02, velocity: float = 0.06, seed_value: int = 1) -> Array:
	return _native().call("humanize", notes, timing, velocity, seed_value)

static func arpeggiate(pitches: Array, start: float, duration: float, step: float = 0.25, direction: String = "up") -> Array[Dictionary]:
	return _native().call("arpeggiate", pitches, start, duration, step, direction)

static func harmonize(notes: Array, key: Variant = "C", scale_name: String = "major", interval: int = 2) -> Array:
	return _native().call("harmonize", notes, key, scale_name, interval)

static func _native() -> RefCounted:
	return Engine.get_singleton("KiwiNativeServices").call("service", "audio_composer")
