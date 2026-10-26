class_name KiwiAudioMIDITimeline
extends RefCounted
## Bounded note-only SMF projection. No PCM decode/render or document mutation.
## Audio FX, routing, automation and sample/instrument voice behavior are excluded.
const MAX_CLIPS := 128
const MAX_CYCLES := 4096
const MAX_EVALUATIONS := 1000000

static func preflight(document: KiwiAudioDocument) -> String:
	if document == null: return "No composition is open."
	if document.tracks.size() > 256 or document.clips.size() > 2048 or document.actors.size() > 2048: return "Timeline MIDI supports compositions with at most 256 tracks and 2048 total clips. Export a smaller composition."
	var timing_error := document.midi_timing_error()
	if not timing_error.is_empty(): return timing_error
	var input_notes := 0
	var clips := 0
	for actor in document.actors:
		if actor == null: return "A source actor is missing."
		var notes: Variant = actor.values.get(&"notes", [])
		if not notes is Array: return "Invalid note source."
		if notes.is_empty(): continue
		if not actor.values.get(&"instrument", {}) is Dictionary or not actor.values.get(&"step_settings", {}) is Dictionary: return "Invalid note instrument or step settings."
		clips += 1; input_notes += notes.size()
		if notes.size() > KiwiAudioTempoMap.MAX_SOURCE_NOTES or input_notes > KiwiAudioTempoMap.MAX_TOTAL_NOTES or clips > MAX_CLIPS:
			return "Timeline MIDI supports 128 note clips, 8192 notes per source and 65536 input notes. Export a smaller composition."
	var errors := document.validate()
	return "\n".join(errors)

static func build(document: KiwiAudioDocument, job: RefCounted = null) -> Dictionary:
	var problem := preflight(document)
	if not problem.is_empty(): return _failure(problem)
	var conductor := document.conductor()
	var parts: Array = []
	var part_ids: Dictionary = {}
	var solos: Array[String] = []
	for track in document.tracks:
		if bool(track.get("solo", false)): solos.append(str(track.id))
	var state := {"evaluations": 0, "notes": 0}
	for index in document.clips.size():
		if job != null:
			if job.is_cancelled(): return _failure("Cancelled.")
			job.update(float(index) / maxi(1, document.clips.size()), "Mapping timeline notes to MIDI")
		var clip := document.clips[index]
		var actor := document.actors[index]
		var track := document.track_for_clip(clip.id)
		var notes: Array = actor.values.get(&"notes", [])
		if notes.is_empty() or bool(actor.values.get(&"muted", false)) or bool(track.get("mute", false)): continue
		if not solos.is_empty():
			var audible := false
			for solo_id in solos:
				if KiwiAudioRenderer.route_reaches(document, str(track.id), solo_id): audible = true; break
			if not audible: continue
		if track.has("frozen_track"): return _failure("Unfreeze note tracks before timeline MIDI export; frozen audio is not an editable note performance.")
		if not (actor.values.get(&"automation", {}).get("pitch", []) as Array).is_empty(): return _failure("Timeline MIDI cannot represent clip pitch automation. Export audio or remove that curve in a separate composition.")
		var pitch_shift := 12.0 * log(float(actor.values.get(&"pitch", 1.0))) / log(2.0)
		if absf(pitch_shift - roundf(pitch_shift)) > 0.0001: return _failure("Timeline MIDI requires whole-semitone clip pitch; continuous/microtonal pitch requires audio export.")
		var patch_value: Variant = actor.values.get(&"instrument", track.get("instrument", {"id": "poly"}))
		if not patch_value is Dictionary: return _failure("Invalid instrument metadata on a note track.")
		var patch: Dictionary = patch_value
		var program := clampi(int(patch.get("midi_program", KiwiAudioMIDI._instrument_program(str(patch.get("id", "poly"))))), 0, 127)
		var drums := int(patch.get("midi_channel", -1)) == 9 or str(patch.get("id", "")) in ["drums", "drum_kit", "drum_sampler"] or str(patch.get("kind", "")) == "drums"
		var key := str(track.id) + ":" + str(program) + ":" + str(drums)
		if not part_ids.has(key):
			part_ids[key] = parts.size()
			parts.append({"label": str(track.get("name", "Notes")).substr(0, 1024), "role": "drums" if drums else "instrument", "instrument": {"midi_channel": 9 if drums else -1, "midi_program": program}, "notes": [], "events": [], "duration": 0.0})
		var part: Dictionary = parts[int(part_ids[key])]
		var timing := KiwiAudioTempoMap.new(actor.values.get(&"midi_tempos", []), KiwiAudioEditSession.note_source_tempo(actor, document), float(actor.values.get(&"midi_tempo_scale", 1.0)))
		if not timing.error.is_empty(): return _failure(timing.error)
		var pattern := float(actor.values.get(&"pattern_beats", 0.0))
		if not is_finite(pattern) or pattern < 0.0 or pattern > KiwiAudioTempoMap.MAX_BEAT: return _failure("Invalid source pattern length.")
		var period := timing.beat_to_seconds(pattern) if pattern > 0.0 else 0.0
		var looping := bool(actor.values.get(&"loop", false))
		if looping and period <= 0.0: return _failure("Looped note sources require an explicit positive pattern length for timeline MIDI export.")
		var pending_scale := float(actor.values.get(&"notes_source_scale", 1.0))
		var window_start := clip.source_offset * pending_scale
		var duration := clip.duration
		# Match pending derived-note window remapping without synthesizing PCM.
		var old_length := float(actor.values.get(&"source_duration", 0.0)) * pending_scale
		var full_source := window_start < 0.00001 and absf(duration * clip.playback_speed - old_length) < 0.001
		if period > 0.0:
			if full_source: duration = period / clip.playback_speed
			if not looping:
				window_start = minf(window_start, maxf(0.0, period - 1.0 / 44100.0))
				duration = minf(duration, maxf(1.0 / 44100.0, period - window_start) / clip.playback_speed)
		var window_end := window_start + duration * clip.playback_speed
		if not is_finite(window_start) or not is_finite(window_end) or window_end > 10000000.0: return _failure("Timeline MIDI source windows must stay within ten million source seconds.")
		if looping and window_end / period > 1000000.0: return _failure("Timeline MIDI source windows must stay within one million absolute loop cycles.")
		if looping and (window_end - window_start) / period > MAX_CYCLES: return _failure("Timeline MIDI limits loop expansion to 4096 source cycles per clip.")
		if bool(actor.values.get(&"midi_sustain", false)):
			notes = KiwiAudioMIDI.sustain_copy(notes, actor.values.get(&"midi_events", []), pattern, job)
		notes = KiwiAudioStepControls.render_copy(notes, actor.values.get(&"step_settings", {}), patch)
		var rng := RandomNumberGenerator.new(); rng.seed = int(patch.get("seed", 1))
		for note: Dictionary in notes:
			if job != null and job.is_cancelled(): return _failure("Cancelled.")
			if not bool(note.get("enabled", true)) or bool(note.get("mute", false)): continue
			if rng.randf() > clampf(KiwiAudioSynthesis.finite(note.get("probability", 1.0), 1.0), 0.0, 1.0): continue
			var velocity := clampf(float(note.get("velocity", 0.8)) * (1.2 if bool(note.get("accent", false)) else 1.0), 0.0, 1.0)
			if velocity <= 0.0: continue
			var pitch := int(note.get("pitch", 60)) + roundi(pitch_shift)
			if pitch < 0 or pitch > 127: return _failure("Clip pitch would move an exported note outside MIDI 0-127.")
			var ratchets := clampi(int(KiwiAudioSynthesis.finite(note.get("ratchets", 1), 1.0)), 1, 8)
			var gate := float(note.get("duration", 0.25)) / ratchets
			for ratchet in ratchets:
				var beat := float(note.get("start", 0.0)) + ratchet * gate
				var a := timing.beat_to_seconds(beat)
				var b := timing.beat_to_seconds(beat + gate)
				if period > 0.0: b = minf(b, period)
				if b <= a: continue
				var first := maxi(0, floori((window_start - b) / period) + 1) if looping else 0
				var last := ceili((window_end - a) / period) - 1 if looping else 0
				if last - first + 1 > MAX_CYCLES: return _failure("Timeline MIDI loop expansion exceeds its source-cycle limit.")
				for cycle in range(first, last + 1):
					state.evaluations += 1
					if job != null and int(state.evaluations) % 128 == 0 and job.is_cancelled(): return _failure("Cancelled.")
					if int(state.evaluations) > MAX_EVALUATIONS: return _failure("Timeline MIDI exceeded one million note/window evaluations. Export a smaller composition.")
					var offset := cycle * period if looping else 0.0
					var left := maxf(window_start, a + offset); var right := minf(window_end, b + offset)
					if right <= left: continue
					var start := clip.start_time + (window_end - right if bool(actor.values.get(&"reverse", false)) else left - window_start) / clip.playback_speed
					var end := clip.start_time + (window_end - left if bool(actor.values.get(&"reverse", false)) else right - window_start) / clip.playback_speed
					var start_beat := conductor.seconds_to_beat(start); var end_beat := conductor.seconds_to_beat(end)
					if end_beat > KiwiAudioMIDI.MAX_EXPORT_BEAT: return _failure("The timeline extends beyond the supported SMF tick range.")
					state.notes += 1
					if int(state.notes) > KiwiAudioTempoMap.MAX_TOTAL_NOTES or (part.notes as Array).size() >= KiwiAudioTempoMap.MAX_SOURCE_NOTES: return _failure("Expanded MIDI exceeds 65536 total notes or 8192 notes per track/program part.")
					part.notes.append({"pitch": pitch, "start": start_beat, "duration": end_beat - start_beat, "velocity": velocity})
					part.duration = maxf(float(part.duration), end_beat)
	parts = parts.filter(func(part: Dictionary): return not (part.notes as Array).is_empty())
	if parts.is_empty(): return _failure("There are no unmuted editable notes in these timeline windows.")
	# Empty/out-of-window/probability-muted sources must not consume channels.
	var next_channel := 0
	var percussion_program := -1
	for part: Dictionary in parts:
		if str(part.role) == "drums":
			var program := int(part.instrument.midi_program)
			if percussion_program >= 0 and percussion_program != program: return _failure("Percussion parts must share one MIDI program on channel 10. Export differing drum programs separately.")
			percussion_program = program
		else:
			if next_channel == 9: next_channel += 1
			if next_channel >= 16: return _failure("Timeline MIDI supports 15 melodic track/program parts plus shared channel-10 percussion. Export fewer parts.")
			part.instrument.midi_channel = next_channel; next_channel += 1
	var tempos: Array = [{"beat": 0.0, "bpm": document.tempo}]; tempos.append_array(document.tempo_points)
	var meters: Array = [{"beat": 0.0, "numerator": document.time_signature.x, "denominator": document.time_signature.y}]; meters.append_array(document.meter_points)
	return {"error": "", "parts": parts, "tempos": tempos, "meters": meters}

static func _failure(message: String) -> Dictionary:
	return {"error": message, "parts": [], "tempos": [], "meters": []}
