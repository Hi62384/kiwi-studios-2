extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var parts := [{"role": "melody", "label": "Melody", "instrument": {"id": "piano", "midi_channel": 2, "midi_program": 4}, "notes": [
		{"pitch": 60, "start": 0.0, "duration": 1.0, "velocity": 100.0 / 127.0},
		{"pitch": 60, "start": 0.5, "duration": 1.0, "velocity": 80.0 / 127.0},
		{"pitch": 72, "start": 2.25, "duration": 0.125, "velocity": 1.0}],
		"events": [{"beat": 0.25, "type": "control_change", "controller": 64, "value": 127}, {"beat": 1.0, "type": "pitch_bend", "value": 9000}]}]
	var tempos := [{"beat": 0.0, "bpm": 120.0}, {"beat": 2.0, "bpm": 90.0}]
	var signatures := [{"beat": 0.0, "numerator": 4, "denominator": 4}, {"beat": 2.0, "numerator": 3, "denominator": 8}]
	var bytes := KiwiAudioMIDI.write_bytes(parts, tempos, signatures)
	check(bytes.slice(0, 4).get_string_from_ascii() == "MThd", "Writer emits real Standard MIDI header")
	var imported := KiwiAudioMIDI.read_bytes(bytes)
	check(imported.error.is_empty(), "Written MIDI imports")
	if not imported.error.is_empty():
		quit(failures)
		return
	check(imported.parts.size() == 1 and imported.parts[0].notes.size() == 3, "Note counts roundtrip")
	for i in 3:
		var original: Dictionary = parts[0].notes[i]
		var result: Dictionary = imported.parts[0].notes[i]
		check(original.pitch == result.pitch and is_equal_approx(float(original.start), float(result.start)) and is_equal_approx(float(original.duration), float(result.duration)), "Overlapping same-pitch notes preserve timing")
		check(absf(float(original.velocity) - float(result.velocity)) < 0.008, "MIDI velocity preserves seven-bit accuracy")
	check(imported.tempos.size() == 2 and absf(float(imported.tempos[1].bpm) - 90.0) < 0.001, "Tempo map roundtrips")
	check(imported.time_signatures.size() == 2 and imported.time_signatures[1].denominator == 8, "Meter map roundtrips")
	check(imported.parts[0].instrument.midi_channel == 2 and imported.parts[0].instrument.midi_program == 4, "Channel and program roundtrip")
	check(imported.parts[0].events.any(func(event: Dictionary): return event.type == "pitch_bend" and event.value == 9000), "Pitch bend events roundtrip")
	check(absf(KiwiAudioMIDI.beat_to_seconds(3.0, imported.tempos) - (1.0 + 2.0 / 3.0)) < 0.001, "Tempo map converts beats to seconds")
	var second := KiwiAudioMIDI.read_bytes(KiwiAudioMIDI.write_bytes(imported.parts, imported.tempos, imported.time_signatures))
	check(second.parts[0].notes.size() == 3 and second.tempos == imported.tempos, "Second generation retains notes and tempo")
	check(not KiwiAudioMIDI.read_bytes(bytes.slice(0, bytes.size() - 2)).error.is_empty(), "Truncated MIDI fails safely")
	var bad := bytes.duplicate()
	bad[12] = 0xe7
	check(KiwiAudioMIDI.read_bytes(bad).error.contains("SMPTE"), "Unsupported SMPTE is explicit")
	var running := PackedByteArray([77,84,104,100,0,0,0,6,0,0,0,1,1,224,77,84,114,107,0,0,0,12,0,144,60,100,120,60,0,0,255,47,0])
	running[21] = running.size() - 22
	var parsed := KiwiAudioMIDI.read_bytes(running)
	check(parsed.error.is_empty() and parsed.parts[0].notes.size() == 1, "Running status and zero-velocity note-off work")
	var path := "user://music_roundtrip.mid"
	check(KiwiAudioMIDI.write(path, parts, tempos, signatures) == OK, "MIDI file writes")
	check(KiwiAudioMIDI.read(path).error.is_empty(), "MIDI file reads")
	DirAccess.remove_absolute(path)
	print("Audio MIDI checks: %d failures" % failures)
	quit(failures)
