extends SceneTree
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void: run.call_deferred()

func source(document: KiwiAudioDocument, start: float, duration: float, offset: float = 0.0, speed: float = 1.0) -> ActorData:
	var track := document.add_track("Pattern", "instrument")
	var actor := ActorData.new()
	actor.id = ActorData.new_id(); actor.type_id = &"audio"; actor.display_name = "Source"
	actor.values = {&"track_id": track.id, &"instrument": {"id": "piano"}, &"source_bpm": 120.0, &"pattern_beats": 4.0, &"source_duration": 2.0,
		&"notes": [{"pitch": 60, "start": 1.0, "duration": 2.0, "velocity": 0.8}]}
	var clip := ActorClip.create(actor, start, duration); clip.source_offset = offset; clip.playback_speed = speed
	document.actors.append(actor); document.clips.append(clip)
	return actor

func first(result: Dictionary) -> Dictionary:
	if not str(result.get("error", "")).is_empty() or result.parts.is_empty() or result.parts[0].notes.is_empty(): return {}
	return result.parts[0].notes[0]

func run() -> void:
	var document := KiwiAudioDocument.new()
	var actor := source(document, 3.0, 0.5, 0.75, 2.0)
	var result := KiwiAudioMIDITimeline.build(document)
	var note := first(result)
	check(result.error.is_empty(), "Placed/slipped/sped source projects successfully")
	check(not note.is_empty() and is_equal_approx(float(note.start), 6.0) and is_equal_approx(float(note.duration), 0.75), "Window intersections map through placement and speed")
	actor.values[&"reverse"] = true
	note = first(KiwiAudioMIDITimeline.build(document))
	check(not note.is_empty() and is_equal_approx(float(note.start), 6.25) and is_equal_approx(float(note.duration), 0.75), "Reverse mirrors the clipped gate inside the selected window")
	actor.values[&"reverse"] = false; actor.values[&"pitch"] = 2.0
	note = first(KiwiAudioMIDITimeline.build(document))
	check(not note.is_empty() and int(note.pitch) == 72, "Static octave clip pitch maps to MIDI notes")
	actor.values[&"pitch"] = 1.01
	check(KiwiAudioMIDITimeline.build(document).error.contains("whole-semitone"), "Fractional-semitone clip pitch is refused explicitly")
	actor.values[&"pitch"] = 1.0
	document.tempo_points.assign([{"beat": 4.0, "bpm": 60.0}])
	note = first(KiwiAudioMIDITimeline.build(document))
	check(not note.is_empty() and is_equal_approx(float(note.start), 5.0) and is_equal_approx(float(note.duration), 0.375), "Changing project conductor maps actual timeline seconds")
	check((actor.values[&"notes"] as Array)[0].duration == 2.0 and document.clips[0].source_offset == 0.75, "Projection preserves source notes and source windows")
	var loops := KiwiAudioDocument.new()
	var loop_actor := source(loops, 0.0, 4.0)
	loop_actor.values[&"loop"] = true
	# Avoid treating the four-second window as a full two-second source.
	var loop_result := KiwiAudioMIDITimeline.build(loops)
	check(loop_result.error.is_empty() and loop_result.parts[0].notes.size() == 2, "Clip loop expands two source occurrences")
	var imported := KiwiAudioMIDI.read_bytes(KiwiAudioMIDI.write_bytes(loop_result.parts, loop_result.tempos, loop_result.meters))
	check(imported.error.is_empty() and imported.parts[0].notes.size() == 2, "Projected notes serialize as real MIDI")
	loop_actor.values[&"automation"] = {"pitch": [{"time": 0.0, "value": 1.0}]}
	check(KiwiAudioMIDITimeline.build(loops).error.contains("pitch automation"), "Unsupported changing pitch does not silently export")
	loop_actor.values[&"automation"] = {}; loops.tracks[0]["frozen_track"] = {}
	check(KiwiAudioMIDITimeline.build(loops).error.contains("Unfreeze"), "Frozen audio is not presented as editable timeline MIDI")
	var mapped := KiwiAudioDocument.new()
	var mapped_actor := source(mapped, 0.0, 3.0)
	mapped_actor.values[&"midi_tempos"] = [{"beat": 0.0, "bpm": 120.0}, {"beat": 2.0, "bpm": 60.0}]
	note = first(KiwiAudioMIDITimeline.build(mapped))
	check(not note.is_empty() and is_equal_approx(float(note.start), 1.0) and is_equal_approx(float(note.duration), 3.0), "Source tempo changes are converted independently into project beats")
	var channels := KiwiAudioDocument.new()
	for i in 16:
		var channel_actor := source(channels, float(i) * 2.0, 2.0)
		if i == 0: channel_actor.values[&"notes"][0]["mute"] = true
	var channel_result := KiwiAudioMIDITimeline.build(channels)
	check(channel_result.error.is_empty() and channel_result.parts.size() == 15, "An empty muted part does not consume one of 15 melodic channels")
	if channel_result.error.is_empty():
		check(not (channel_result.parts as Array).any(func(part: Dictionary): return int(part.instrument.midi_channel) == 9), "Melodic channel assignment preserves channel 10 for percussion")
	print("AUDIO_TIMELINE_MIDI checks=%d failures=%d" % [checks, failures])
	quit(failures)
