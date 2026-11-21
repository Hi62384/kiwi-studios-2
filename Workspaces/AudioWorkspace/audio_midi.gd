class_name KiwiAudioMIDI
extends RefCounted
## Standard MIDI File type-0/type-1 reader, type-1 writer (PPQ timing).
## Retains channel events for source export; synthesis does not play all controls.
## SMPTE division and type-2 independent sequences are rejected with an explanation.
const PPQ := 480
const MAX_EXPORT_BEAT := float(0x0ffffffe) / PPQ
const MAX_BYTES := 32 * 1024 * 1024
const MAX_EVENTS := 1000000

class Cursor:
	extends RefCounted
	var data := PackedByteArray()
	var position := 0
	var end := 0
	var error := ""
	func _init(bytes: PackedByteArray, start: int = 0, finish: int = -1) -> void:
		data = bytes
		position = start
		end = bytes.size() if finish < 0 else mini(finish, bytes.size())
	func byte() -> int:
		if position >= end:
			error = "Truncated MIDI event."
			return 0
		var value := int(data[position])
		position += 1
		return value
	func be16() -> int: return (byte() << 8) | byte()
	func be32() -> int: return (byte() << 24) | (byte() << 16) | (byte() << 8) | byte()
	func block(count: int) -> PackedByteArray:
		if count < 0 or count > end - position:
			error = "MIDI chunk extends beyond the file."
			return PackedByteArray()
		var value := data.slice(position, position + count)
		position += count
		return value
	func variable() -> int:
		var value := 0
		for i in 4:
			var b := byte()
			if not error.is_empty(): return 0
			value = (value << 7) | (b & 127)
			if b < 128: return value
		error = "Invalid MIDI variable-length integer."
		return 0

static func read(path: String) -> Dictionary:
	return _native().call("read", path)

static func _failure(message: String) -> Dictionary:
	return {"error": message, "parts": [], "tempos": [], "time_signatures": [], "warnings": []}

static func read_bytes(bytes: PackedByteArray) -> Dictionary:
	return _native().call("read_bytes", bytes)

static func sustain_copy(notes: Array, events: Array, pattern_beats: float, job: RefCounted = null) -> Array:
	return _native().call("sustain_copy", notes, events, pattern_beats, job)

static func _finish_note(active: Dictionary, key: String, part: Dictionary, beat: float) -> void:
	if not active.has(key) or active[key].is_empty(): return
	var note: Dictionary = active[key].pop_front()
	note.duration = maxf(0.0, beat - float(note.start))
	part.notes.append(note)

static func _program_instrument(program: int) -> String:
	return _native().call("program_instrument", program)

static func write(path: String, parts: Array, tempo: Variant = 120.0, time_signature: Variant = [4, 4]) -> Error:
	return _native().call("write", path, parts, tempo, time_signature)

static func write_bytes(parts: Array, tempo: Variant = 120.0, time_signature: Variant = [4, 4]) -> PackedByteArray:
	return _native().call("write_bytes", parts, tempo, time_signature)

static func _instrument_program(id: String) -> int:
	return _native().call("instrument_program", id)

static func _ticks(beat: Variant) -> int:
	return _native().call("ticks", beat)

static func _encode_track(events: Array[Dictionary], end_tick: int = 0) -> PackedByteArray:
	return _native().call("encode_track", events, end_tick)

static func _vlq(value: int) -> PackedByteArray:
	return _native().call("vlq", value)

static func _be16(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 8) & 255)
	bytes.append(value & 255)

static func _be32(bytes: PackedByteArray, value: int) -> void:
	for shift in [24, 16, 8, 0]: bytes.append((value >> int(shift)) & 255)

static func beat_to_seconds(beat: float, tempos: Array) -> float:
	return _native().call("beat_to_seconds", beat, tempos)

static func seconds_to_beat(seconds: float, tempos: Array) -> float:
	return _native().call("seconds_to_beat", seconds, tempos)

static func _native() -> RefCounted:
	return Engine.get_singleton("KiwiNativeServices").call("service", "audio_midi")
