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
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _failure("Could not open MIDI file.")
	if file.get_length() > MAX_BYTES:
		file.close()
		return _failure("MIDI file exceeds the 32 MiB safety limit.")
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return read_bytes(bytes)

static func _failure(message: String) -> Dictionary:
	return {"error": message, "parts": [], "tempos": [], "time_signatures": [], "warnings": []}

static func read_bytes(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 14 or bytes.size() > MAX_BYTES: return _failure("Invalid MIDI file size.")
	var cursor := Cursor.new(bytes)
	if cursor.block(4).get_string_from_ascii() != "MThd": return _failure("Missing MIDI header.")
	var header_length := cursor.be32()
	if header_length < 6 or header_length > bytes.size() - 8: return _failure("Invalid MIDI header length.")
	var format := cursor.be16()
	var track_count := cursor.be16()
	var division := cursor.be16()
	if format not in [0, 1]: return _failure("Only MIDI type 0 and type 1 are supported; type 2 sequences must be imported separately.")
	if (division & 0x8000) != 0: return _failure("SMPTE-timed MIDI is not supported; convert to quarter-note PPQ timing.")
	if division <= 0 or track_count < 1 or track_count > 1024: return _failure("Invalid MIDI timing or track count.")
	if format == 0 and track_count != 1: return _failure("MIDI type 0 must contain exactly one track.")
	cursor.position = 8 + header_length
	var parts: Array[Dictionary] = []
	var tempos: Array[Dictionary] = []
	var signatures: Array[Dictionary] = []
	var warnings: Array[String] = []
	var duration_ticks := 0
	var event_count := 0
	var note_count := 0
	for track_index in track_count:
		if cursor.position + 8 > bytes.size(): return _failure("Missing MIDI track chunk.")
		var chunk_name := cursor.block(4).get_string_from_ascii()
		var chunk_length := cursor.be32()
		if chunk_name != "MTrk": return _failure("Expected a MIDI track chunk.")
		if chunk_length < 0 or chunk_length > bytes.size() - cursor.position: return _failure("Truncated MIDI track chunk.")
		var track := Cursor.new(bytes, cursor.position, cursor.position + chunk_length)
		cursor.position += chunk_length
		var ticks := 0
		var running := -1
		var active: Dictionary = {}
		var channel_parts: Dictionary = {}
		var channel_pan: Dictionary = {}
		var track_name := "Track %d" % (track_index + 1)
		while track.position < track.end and track.error.is_empty():
			event_count += 1
			if event_count > MAX_EVENTS: return _failure("MIDI event limit exceeded.")
			ticks += track.variable()
			duration_ticks = maxi(duration_ticks, ticks)
			var status := track.byte()
			if status < 0x80:
				if running < 0: return _failure("MIDI running status has no preceding channel event.")
				track.position -= 1
				status = running
			elif status < 0xf0:
				running = status
			if status == 0xff:
				running = -1
				var meta_type := track.byte()
				var meta_length := track.variable()
				var payload := track.block(meta_length)
				if not track.error.is_empty(): break
				match meta_type:
					0x2f: break
					0x03: track_name = payload.get_string_from_utf8()
					0x51:
						if payload.size() == 3:
							if tempos.size() >= KiwiAudioTempoMap.MAX_EVENTS: return _failure("MIDI tempo maps are limited to 4096 events.")
							var microseconds := (int(payload[0]) << 16) | (int(payload[1]) << 8) | int(payload[2])
							if microseconds > 0: tempos.append({"beat": float(ticks) / division, "bpm": 60000000.0 / microseconds, "microseconds": microseconds, "order": event_count})
					0x58:
						if payload.size() >= 4 and int(payload[1]) <= 7:
							if signatures.size() >= KiwiAudioTempoMap.MAX_EVENTS: return _failure("MIDI meter maps are limited to 4096 events.")
							signatures.append({"beat": float(ticks) / division, "numerator": int(payload[0]), "denominator": 1 << int(payload[1]), "clocks_per_click": int(payload[2]), "thirty_seconds": int(payload[3]), "order": event_count})
				if meta_type == 0x2f: break
				continue
			if status in [0xf0, 0xf7]:
				running = -1
				track.block(track.variable())
				if not warnings.has("System-exclusive events are not retained."): warnings.append("System-exclusive events are not retained.")
				continue
			if status >= 0xf0: return _failure("Unsupported system event in MIDI track.")
			var message_type := status & 0xf0
			var channel := status & 15
			var first := track.byte()
			var second := 0 if message_type in [0xc0, 0xd0] else track.byte()
			if first >= 128 or second >= 128: return _failure("Invalid MIDI channel event data.")
			if not channel_parts.has(channel):
				if parts.size() + channel_parts.size() >= KiwiAudioTempoMap.MAX_SOURCES: return _failure("A MIDI import is limited to 128 track/channel sources.")
				channel_parts[channel] = {"id": "midi_%d_%d" % [track_index, channel], "role": "drums" if channel == 9 else "instrument", "label": track_name, "instrument": {"id": "drums" if channel == 9 else "piano", "midi_program": 0, "midi_channel": channel}, "notes": [], "events": []}
			var part: Dictionary = channel_parts[channel]
			var beat := float(ticks) / division
			var note_key := "%d:%d" % [channel, first]
			match message_type:
				0x90:
					if second > 0:
						note_count += 1
						if note_count > KiwiAudioTempoMap.MAX_TOTAL_NOTES: return _failure("A MIDI import is limited to 65536 notes in total.")
						if not active.has(note_key): active[note_key] = []
						active[note_key].append({"id": ("%d:%d:%d:%d:%d" % [track_index, channel, first, ticks, event_count]).sha256_text().substr(0, 32), "pitch": first, "start": beat, "duration": 0.0, "velocity": second / 127.0, "pan": float(channel_pan.get(channel, 0.0))})
					else: _finish_note(active, note_key, part, beat)
				0x80: _finish_note(active, note_key, part, beat)
				0xb0:
					part.events.append({"beat": beat, "type": "control_change", "controller": first, "value": second})
					if first == 10: channel_pan[channel] = clampf((second - 64.0) / 63.0, -1.0, 1.0)
				0xc0:
					part.events.append({"beat": beat, "type": "program_change", "program": first})
					if beat == 0.0:
						part.instrument.midi_program = first
						if channel != 9: part.instrument.id = _program_instrument(first)
				0xe0: part.events.append({"beat": beat, "type": "pitch_bend", "value": (second << 7) | first})
				0xa0: part.events.append({"beat": beat, "type": "poly_pressure", "pitch": first, "value": second})
				0xd0: part.events.append({"beat": beat, "type": "channel_pressure", "value": first})
			if part.events.size() > KiwiAudioTempoMap.MAX_SOURCE_CHANNEL_EVENTS: return _failure("A MIDI source is limited to 16384 channel events.")
		if not track.error.is_empty(): return _failure(track.error)
		for key: String in active:
			var channel := int(key.get_slice(":", 0))
			var part: Dictionary = channel_parts[channel]
			for note: Dictionary in active[key]:
				note.duration = maxf(1.0 / division, float(ticks) / division - float(note.start))
				part.notes.append(note)
			if not active[key].is_empty() and not warnings.has("Unclosed notes were ended at the track boundary."): warnings.append("Unclosed notes were ended at the track boundary.")
		for part: Dictionary in channel_parts.values():
			if part.notes.size() > KiwiAudioTempoMap.MAX_SOURCE_NOTES: return _failure("A MIDI source is limited to 8192 notes.")
			part["duration"] = float(ticks) / division
			part.label = track_name + (" (channel %d)" % (int(part.instrument.midi_channel) + 1) if channel_parts.size() > 1 else "")
			part.notes.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.start) < float(b.start))
			parts.append(part)
	if tempos.is_empty(): tempos.append({"beat": 0.0, "bpm": 120.0, "microseconds": 500000})
	if signatures.is_empty(): signatures.append({"beat": 0.0, "numerator": 4, "denominator": 4, "clocks_per_click": 24, "thirty_seconds": 8})
	tempos.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.beat) < float(b.beat) if float(a.beat) != float(b.beat) else int(a.get("order", 0)) < int(b.get("order", 0)))
	for event: Dictionary in tempos: event.erase("order")
	# Preserve encounter order for conflicting same-beat meter events too.
	signatures.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.beat) < float(b.beat) if float(a.beat) != float(b.beat) else int(a.get("order", 0)) < int(b.get("order", 0)))
	for event: Dictionary in signatures: event.erase("order")
	if float(tempos[0].beat) > 0.0: tempos.push_front({"beat": 0.0, "bpm": 120.0, "microseconds": 500000})
	if float(signatures[0].beat) > 0.0: signatures.push_front({"beat": 0.0, "numerator": 4, "denominator": 4, "clocks_per_click": 24, "thirty_seconds": 8})
	var timing_error := KiwiAudioTempoMap.validate_tempos(tempos)
	if timing_error.is_empty(): timing_error = KiwiAudioTempoMap.validate_meters(signatures)
	if not timing_error.is_empty(): return _failure(timing_error)
	# Count every eventual per-source copy plus the legacy conductor copy
	# before the workspace duplicates any arrays for tracks or undo state.
	if (parts.size() + 1) * (tempos.size() + signatures.size()) > KiwiAudioTempoMap.MAX_MAP_COPIES: return _failure("This import would exceed 65536 copied tempo/meter events. Reduce tracks or conductor events before importing.")
	var channel_events := 0
	for part: Dictionary in parts:
		channel_events += part.events.size()
		for event: Dictionary in part.events:
			var limited := str(event.type) != "program_change" or float(event.beat) > 0.0
			if limited and not warnings.has("MIDI source export retains channel events. Preview defaults to note gates, note-on pan and approximate initial program patches. CC64 sustain can be enabled explicitly in the instrument inspector; other controllers, bends, pressure and later program changes are not performed."):
				warnings.append("MIDI source export retains channel events. Preview defaults to note gates, note-on pan and approximate initial program patches. CC64 sustain can be enabled explicitly in the instrument inspector; other controllers, bends, pressure and later program changes are not performed.")
		var event_error := KiwiAudioTempoMap.validate_channel_events(part.events)
		if not event_error.is_empty(): return _failure(event_error)
	if channel_events > KiwiAudioTempoMap.MAX_TOTAL_CHANNEL_EVENTS: return _failure("A MIDI import is limited to 131072 channel events in total.")
	var effective_tempos := KiwiAudioTempoMap.canonical(tempos)
	return {"error": "", "format": format, "ppq": division, "parts": parts, "tempo": float(effective_tempos[0].bpm), "time_signature": [int(signatures[0].numerator), int(signatures[0].denominator)], "tempos": tempos, "time_signatures": signatures, "duration": float(duration_ticks) / division, "warnings": warnings}

## Optional render-only CC64 policy. Source note lengths and export events stay
## untouched. All events at a note-off beat take effect before that note-off;
## an unreleased pedal closes at the source pattern boundary. No half pedaling.
static func sustain_copy(notes: Array, events: Array, pattern_beats: float, job: RefCounted = null) -> Array:
	var controls: Array[Dictionary] = []
	for i in events.size():
		var event: Dictionary = events[i]
		if str(event.get("type", "")) == "control_change" and int(event.get("controller", -1)) == 64:
			controls.append({"beat": float(event.get("beat", 0.0)), "down": int(event.get("value", 0)) >= 64, "order": i})
	controls.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.beat) < float(b.beat) if float(a.beat) != float(b.beat) else int(a.order) < int(b.order))
	var boundary := maxf(0.0, pattern_beats)
	if boundary <= 0.0:
		for note: Dictionary in notes: boundary = maxf(boundary, float(note.get("start", 0.0)) + maxf(0.0, float(note.get("duration", 0.0))))
	var intervals: Array[Dictionary] = []
	var start := -1.0
	for control in controls:
		if float(control.beat) > boundary: break
		if bool(control.down):
			if start < 0.0: start = float(control.beat)
		elif start >= 0.0:
			if float(control.beat) > start: intervals.append({"start": start, "end": float(control.beat)})
			start = -1.0
	if start >= 0.0 and boundary > start: intervals.append({"start": start, "end": boundary})
	var result: Array = []
	for i in notes.size():
		if job != null and i % 128 == 0 and job.is_cancelled(): return []
		var note: Dictionary = notes[i].duplicate(true)
		var end := float(note.get("start", 0.0)) + maxf(0.0, float(note.get("duration", 0.0)))
		var low := 0; var high := intervals.size()
		while low < high:
			var middle := (low + high) / 2
			if float(intervals[middle].start) <= end: low = middle + 1
			else: high = middle
		if low > 0 and end < float(intervals[low - 1].end):
			note.duration = maxf(float(note.get("duration", 0.0)), float(intervals[low - 1].end) - float(note.get("start", 0.0)))
		result.append(note)
	return result

static func _finish_note(active: Dictionary, key: String, part: Dictionary, beat: float) -> void:
	if not active.has(key) or active[key].is_empty(): return
	var note: Dictionary = active[key].pop_front()
	note.duration = maxf(0.0, beat - float(note.start))
	part.notes.append(note)

static func _program_instrument(program: int) -> String:
	if program < 8: return "piano"
	if program < 16: return "bells"
	if program < 24: return "organ"
	if program < 32: return "pluck"
	if program < 40: return "bass"
	if program < 56: return "strings"
	if program < 64: return "brass"
	if program < 80: return "lead"
	if program < 88: return "lead"
	if program < 104: return "pad"
	if program < 112: return "pluck"
	if program < 120: return "drums"
	return "cinematic"

## tempo may be a BPM number or [{beat,bpm,microseconds?}]; time_signature
## may be [numerator,denominator] or a meter-map array returned by read().
static func write(path: String, parts: Array, tempo: Variant = 120.0, time_signature: Variant = [4, 4]) -> Error:
	# Use the shared completed-file publisher, just like audio export. Never
	# open the final destination with WRITE (which truncates an existing file).
	if FileAccess.file_exists(path): return ERR_ALREADY_EXISTS
	var bytes := write_bytes(parts, tempo, time_signature)
	if bytes.is_empty(): return ERR_INVALID_DATA
	var directory := ProjectSettings.globalize_path("user://audio_workspace/midi_exports/" + ActorData.new_id())
	var created := DirAccess.make_dir_recursive_absolute(directory)
	if created != OK: return created
	var temporary := directory.path_join("source.mid")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		KiwiAudioRenderer._remove_owned(directory)
		return open_error
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		var published := KiwiAudioRenderer._publish_complete(temporary, path)
		if not bool(published.success):
			push_warning(str(published.error))
			error = ERR_ALREADY_EXISTS if FileAccess.file_exists(path) else ERR_FILE_CANT_WRITE
	KiwiAudioRenderer._remove_owned(directory)
	return error

static func write_bytes(parts: Array, tempo: Variant = 120.0, time_signature: Variant = [4, 4]) -> PackedByteArray:
	# Bound source counts before constructing event dictionaries or track buffers.
	# Keep the same per-source and aggregate budgets used by import/documents.
	if parts.size() > KiwiAudioTempoMap.MAX_SOURCES: return PackedByteArray()
	var budget_sources: Array = []
	for part: Variant in parts:
		if not part is Dictionary or not part.get("instrument", {}) is Dictionary: return PackedByteArray()
		var notes: Variant = part.get("notes", [])
		if not notes is Array: return PackedByteArray()
		budget_sources.append({"notes": notes, "midi_events": part.get("events", [])})
	if not KiwiAudioTempoMap.validate_budget(budget_sources).is_empty(): return PackedByteArray()
	var tempo_map: Array = tempo if tempo is Array else [{"beat": 0.0, "bpm": KiwiAudioSynthesis.finite(tempo, 120.0)}]
	var meters: Array = []
	if time_signature is Array and not time_signature.is_empty() and time_signature[0] is Dictionary:
		meters = time_signature
	elif time_signature is Array and time_signature.size() >= 2:
		meters = [{"beat": 0.0, "numerator": int(time_signature[0]), "denominator": int(time_signature[1])}]
	else: meters = [{"beat": 0.0, "numerator": 4, "denominator": 4}]
	if not KiwiAudioTempoMap.validate_tempos(tempo_map).is_empty() or not KiwiAudioTempoMap.validate_meters(meters).is_empty(): return PackedByteArray()
	var conductor: Array[Dictionary] = []
	for item: Variant in tempo_map:
		if not item is Dictionary: continue
		if float(item.get("beat", 0.0)) > MAX_EXPORT_BEAT: return PackedByteArray()
		var raw_microseconds := KiwiAudioSynthesis.finite(item.get("microseconds", 0.0), 0.0)
		if raw_microseconds <= 0.0: raw_microseconds = 60000000.0 / maxf(0.000001, KiwiAudioSynthesis.finite(item.get("bpm", 120.0), 120.0))
		if raw_microseconds < 1.0 or raw_microseconds > 0xffffff: return PackedByteArray()
		var microseconds := int(round(raw_microseconds))
		conductor.append({"tick": _ticks(item.get("beat", 0.0)), "order": 0, "bytes": PackedByteArray([0xff, 0x51, 3, (microseconds >> 16) & 255, (microseconds >> 8) & 255, microseconds & 255])})
	for item: Dictionary in meters:
		if float(item.get("beat", 0.0)) > MAX_EXPORT_BEAT: return PackedByteArray()
		var denominator := int(item.get("denominator", 4))
		if denominator < 1 or denominator > 128 or (denominator & (denominator - 1)) != 0: return PackedByteArray()
		var exponent := 0
		while (1 << exponent) < denominator: exponent += 1
		conductor.append({"tick": _ticks(item.get("beat", 0.0)), "order": 1, "bytes": PackedByteArray([0xff, 0x58, 4, clampi(int(item.get("numerator", 4)), 1, 255), exponent, clampi(int(item.get("clocks_per_click", 24)), 1, 255), clampi(int(item.get("thirty_seconds", 8)), 1, 255)])})
	var tracks: Array[PackedByteArray] = [_encode_track(conductor)]
	for index in parts.size():
		if not parts[index] is Dictionary: return PackedByteArray()
		var part: Dictionary = parts[index]
		if KiwiAudioSynthesis.finite(part.get("duration", 0.0), 0.0) > MAX_EXPORT_BEAT: return PackedByteArray()
		var instrument: Dictionary = part.get("instrument", {})
		var default_channel := index % 15
		if default_channel >= 9: default_channel += 1
		var channel := clampi(int(instrument.get("midi_channel", 9 if str(part.get("role", "")) == "drums" else default_channel)), 0, 15)
		var program := clampi(int(instrument.get("midi_program", _instrument_program(str(instrument.get("id", "piano"))))), 0, 127)
		var events: Array[Dictionary] = []
		var name := str(part.get("label", part.get("role", "Instrument"))).to_utf8_buffer()
		if name.size() > 4096: return PackedByteArray()
		var name_event := PackedByteArray([0xff, 0x03])
		name_event.append_array(_vlq(name.size()))
		name_event.append_array(name)
		events.append({"tick": 0, "order": 0, "bytes": name_event})
		events.append({"tick": 0, "order": 1, "bytes": PackedByteArray([0xc0 | channel, program])})
		for entry: Variant in part.get("notes", []):
			if not entry is Dictionary: continue
			if KiwiAudioSynthesis.finite(entry.get("start", 0.0), 0.0) + maxf(0.0, KiwiAudioSynthesis.finite(entry.get("duration", 0.25), 0.25)) > MAX_EXPORT_BEAT: return PackedByteArray()
			var start := _ticks(entry.get("start", 0.0))
			var finish := maxi(start + 1, _ticks(KiwiAudioSynthesis.finite(entry.get("start", 0.0), 0.0) + maxf(0.0, KiwiAudioSynthesis.finite(entry.get("duration", 0.25), 0.25))))
			var pitch := clampi(int(entry.get("pitch", 60)), 0, 127)
			var velocity := clampi(int(round(clampf(KiwiAudioSynthesis.finite(entry.get("velocity", 0.8), 0.8), 0.0, 1.0) * 127.0)), 0, 127)
			if velocity == 0: continue
			events.append({"tick": start, "order": 4, "bytes": PackedByteArray([0x90 | channel, pitch, velocity])})
			events.append({"tick": finish, "order": 2, "bytes": PackedByteArray([0x80 | channel, pitch, 0])})
		for item: Variant in part.get("events", []):
			if not item is Dictionary: continue
			if KiwiAudioSynthesis.finite(item.get("beat", 0.0), 0.0) > MAX_EXPORT_BEAT: return PackedByteArray()
			var event_bytes := PackedByteArray()
			match str(item.get("type", "")):
				"control_change": event_bytes = PackedByteArray([0xb0 | channel, clampi(int(item.get("controller", 0)), 0, 127), clampi(int(item.get("value", 0)), 0, 127)])
				"program_change":
					if _ticks(item.get("beat", 0.0)) == 0 and int(item.get("program", program)) == program: continue
					event_bytes = PackedByteArray([0xc0 | channel, clampi(int(item.get("program", program)), 0, 127)])
				"pitch_bend":
					var value := clampi(int(item.get("value", 8192)), 0, 16383)
					event_bytes = PackedByteArray([0xe0 | channel, value & 127, (value >> 7) & 127])
				"poly_pressure": event_bytes = PackedByteArray([0xa0 | channel, clampi(int(item.get("pitch", 60)), 0, 127), clampi(int(item.get("value", 0)), 0, 127)])
				"channel_pressure": event_bytes = PackedByteArray([0xd0 | channel, clampi(int(item.get("value", 0)), 0, 127)])
			if not event_bytes.is_empty(): events.append({"tick": _ticks(item.get("beat", 0.0)), "order": 3, "bytes": event_bytes})
		if events.size() > MAX_EVENTS: return PackedByteArray()
		tracks.append(_encode_track(events, _ticks(part.get("duration", 0.0))))
	var output := "MThd".to_ascii_buffer()
	_be32(output, 6)
	_be16(output, 1)
	_be16(output, tracks.size())
	_be16(output, PPQ)
	for track in tracks:
		output.append_array("MTrk".to_ascii_buffer())
		_be32(output, track.size())
		output.append_array(track)
	if output.size() > MAX_BYTES: return PackedByteArray()
	return output

static func _instrument_program(id: String) -> int:
	return int({"piano": 0, "organ": 19, "bells": 10, "strings": 48, "brass": 61, "bass": 38, "lead": 80, "pad": 89, "pluck": 24, "chip": 80, "cinematic": 103}.get(id, 80))

static func _ticks(beat: Variant) -> int:
	return clampi(int(round(KiwiAudioSynthesis.finite(beat, 0.0) * PPQ)), 0, 0x0ffffffe)

static func _encode_track(events: Array[Dictionary], end_tick: int = 0) -> PackedByteArray:
	# Godot's sort is not stable; retain encounter order for same-tick tempo,
	# controller and program events instead of changing their effective value.
	for i in events.size(): events[i]["sequence"] = i
	events.sort_custom(func(a: Dictionary, b: Dictionary):
		if int(a.tick) != int(b.tick): return int(a.tick) < int(b.tick)
		if int(a.order) != int(b.order): return int(a.order) < int(b.order)
		return int(a.sequence) < int(b.sequence))
	var bytes := PackedByteArray()
	var previous := 0
	for event: Dictionary in events:
		var tick := int(event.tick)
		bytes.append_array(_vlq(maxi(0, tick - previous)))
		bytes.append_array(event.bytes)
		previous = tick
	bytes.append_array(_vlq(maxi(0, end_tick - previous)))
	bytes.append_array(PackedByteArray([0xff, 0x2f, 0]))
	return bytes

static func _vlq(value: int) -> PackedByteArray:
	var buffer: Array[int] = [value & 127]
	var remaining := value >> 7
	while remaining > 0:
		buffer.push_front((remaining & 127) | 128)
		remaining >>= 7
	return PackedByteArray(buffer)

static func _be16(bytes: PackedByteArray, value: int) -> void:
	bytes.append((value >> 8) & 255)
	bytes.append(value & 255)

static func _be32(bytes: PackedByteArray, value: int) -> void:
	for shift in [24, 16, 8, 0]: bytes.append((value >> int(shift)) & 255)

static func beat_to_seconds(beat: float, tempos: Array) -> float:
	return KiwiAudioTempoMap.new(tempos).beat_to_seconds(beat)

static func seconds_to_beat(seconds: float, tempos: Array) -> float:
	return KiwiAudioTempoMap.new(tempos).seconds_to_beat(seconds)

