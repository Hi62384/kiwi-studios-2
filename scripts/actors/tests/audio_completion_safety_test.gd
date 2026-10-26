extends SceneTree
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var notes := [{"pitch": 60, "start": 0.0, "duration": 1.0}, {"pitch": 64, "start": 2.0, "duration": 0.5}]
	var events := [{"beat": 0.5, "type": "control_change", "controller": 64, "value": 127}, {"beat": 2.0, "type": "control_change", "controller": 64, "value": 0}]
	var rendered := KiwiAudioMIDI.sustain_copy(notes, events, 4.0)
	check(is_equal_approx(float(rendered[0].duration), 2.0), "CC64 extends a released key to pedal-up")
	check(rendered[1] == notes[1], "Pedal-up does not extend later notes")
	check(is_equal_approx(float(notes[0].duration), 1.0), "Sustain rendering preserves editable source gate")
	var held := KiwiAudioMIDI.sustain_copy(notes, [events[0]], 4.0)
	check(is_equal_approx(float(held[0].duration), 4.0), "Unreleased pedal closes at the source boundary")
	var off_at_release := KiwiAudioMIDI.sustain_copy(notes, [events[0], {"beat": 1.0, "type": "control_change", "controller": 64, "value": 0}], 4.0)
	check(is_equal_approx(float(off_at_release[0].duration), 1.0), "Same-beat pedal-up precedes note-off")
	check(KiwiAudioTempoMap.validate_source({"midi_sustain": "yes"}).contains("boolean"), "Serialized sustain policy requires a boolean")
	var parts := [{"label": "Export safety", "instrument": {"id": "piano"}, "notes": notes, "events": events}]
	var path := "user://midi_safety_" + ActorData.new_id() + ".mid"
	check(KiwiAudioMIDI.write(path, parts) == OK, "New MIDI destination receives a completed file")
	var original := FileAccess.get_file_as_bytes(path)
	check(original.slice(0, 4).get_string_from_ascii() == "MThd", "Published MIDI has an SMF header")
	check(KiwiAudioMIDI.write(path, []) == ERR_ALREADY_EXISTS, "Existing MIDI destination is refused before any write")
	check(FileAccess.get_file_as_bytes(path) == original, "Refused MIDI export preserves every existing byte")
	DirAccess.remove_absolute(path)
	print("AUDIO_COMPLETION_SAFETY checks=%d failures=%d" % [checks, failures])
	quit(failures)
