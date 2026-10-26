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
	return STYLE_NAMES.duplicate()

static func scales() -> Dictionary:
	return SCALE_INTERVALS.duplicate(true)

static func key_pitch(key: Variant) -> int:
	if key is int or key is float: return posmod(int(key), 12)
	var keys := {"C": 0, "C#": 1, "DB": 1, "D": 2, "D#": 3, "EB": 3, "E": 4, "F": 5, "F#": 6, "GB": 6, "G": 7, "G#": 8, "AB": 8, "A": 9, "A#": 10, "BB": 10, "B": 11}
	return int(keys.get(str(key).to_upper(), 0))

static func scale_pitch(degree: int, root: int = 60, scale_name: String = "major") -> int:
	var intervals: Array = SCALE_INTERVALS.get(scale_name, SCALE_INTERVALS.major)
	var octave := floori(float(degree) / intervals.size())
	return root + octave * 12 + int(intervals[posmod(degree, intervals.size())])

static func quantize_pitch(pitch: int, key: Variant = 0, scale_name: String = "major") -> int:
	var intervals: Array = SCALE_INTERVALS.get(scale_name, SCALE_INTERVALS.major)
	var root := key_pitch(key)
	var best := clampi(pitch, 0, 127)
	for distance in 12:
		for direction in [-1, 1]:
			var candidate := pitch + distance * int(direction)
			if candidate >= 0 and candidate <= 127 and posmod(candidate - root, 12) in intervals: return candidate
	return best

static func chord(root: int, scale_name: String, degree: int, inversion: int = 0, seventh: bool = false) -> Array[int]:
	var result: Array[int] = []
	for offset in ([0, 2, 4, 6] if seventh else [0, 2, 4]):
		result.append(scale_pitch(degree + int(offset), root, scale_name))
	for i in posmod(inversion, result.size()):
		result[i] += 12
	result.sort()
	return result

static func voice_lead(pitches: Array, previous: Array) -> Array[int]:
	var best: Array[int] = []
	var best_cost := INF
	for inversion in pitches.size():
		for octave in [-12, 0, 12]:
			var candidate: Array[int] = []
			for i in pitches.size(): candidate.append(int(pitches[i]) + int(octave) + (12 if i < inversion else 0))
			candidate.sort()
			var cost := 0.0
			for i in candidate.size(): cost += absf(candidate[i] - (int(previous[mini(i, previous.size() - 1)]) if not previous.is_empty() else 60 + i * 4))
			if cost < best_cost:
				best_cost = cost
				best = candidate
	return best

static func chord_suggestions(degree: int, scale_name: String = "major") -> Array:
	var choices := {0: [3, 4, 5, 1], 1: [4, 6], 2: [5, 3], 3: [4, 0, 1], 4: [0, 5], 5: [3, 1, 4], 6: [0, 2]}
	var result: Array = []
	for next: int in choices.get(posmod(degree, 7), [0, 4]):
		result.append({"degree": next, "pitches": chord(60, scale_name, next)})
	return result

static func new_note(pitch: int, start: float, duration: float, velocity: float = 0.8, pan: float = 0.0) -> Dictionary:
	return {"id": ActorData.new_id(), "pitch": clampi(pitch, 0, 127), "start": maxf(0.0, start), "duration": maxf(0.001, duration), "velocity": clampf(velocity, 0.0, 1.0), "pan": clampf(pan, -1.0, 1.0)}

static func _note(pitch: int, start: float, duration: float, velocity: float, role: String, section_id: String, index: int, seed_value: int) -> Dictionary:
	return {"id": ("%s:%s:%d:%d" % [role, section_id, index, seed_value]).sha256_text().substr(0, 32), "pitch": clampi(pitch, 0, 127), "start": maxf(0.0, start), "duration": maxf(0.001, duration), "velocity": clampf(velocity, 0.0, 1.0), "pan": 0.0, "section_id": section_id}

static func _style(name: String) -> Dictionary:
	var style := name.to_lower().replace("-", "_").replace(" ", "_")
	var common := {"id": style, "progression": [0, 5, 3, 4], "harmonic_bars": 1, "rhythm": [0.0, 1.0, 1.5, 2.5, 3.0], "melody": "piano", "chords": "poly", "bass": "bass", "pad": "pad", "drums": "backbeat", "swing": 0.0, "seventh": false, "density": 0.7, "structure": ["Intro", "Verse", "Chorus", "Outro"], "default_scale": "major"}
	var details: Dictionary = {}
	match style:
		"ambient": details = {"progression": [0, 3, 5, 1], "harmonic_bars": 2, "rhythm": [0.0, 2.5], "melody": "bells", "chords": "pad", "drums": "none", "density": 0.3, "structure": ["Intro", "A", "B", "Outro"]}
		"cinematic", "orchestral_inspired": details = {"progression": [0, 5, 3, 4], "melody": "strings", "chords": "brass", "drums": "cinematic", "density": 0.65, "default_scale": "minor", "structure": ["Intro", "Theme", "Build", "Climax", "Outro"]}
		"horror": details = {"progression": [0, 1, 0, 6], "harmonic_bars": 2, "rhythm": [0.0, 2.75], "melody": "bells", "chords": "cinematic", "drums": "pulse", "density": 0.25, "default_scale": "phrygian", "structure": ["Intro", "Tension", "Sting", "Outro"]}
		"suspense": details = {"progression": [0, 0, 5, 4], "rhythm": [0.0, 0.75, 1.5, 2.0, 2.75, 3.5], "melody": "pluck", "chords": "strings", "drums": "pulse", "density": 0.6, "default_scale": "minor", "structure": ["Intro", "Tension", "Build", "Outro"]}
		"comedy", "cartoon_music": details = {"progression": [0, 3, 1, 4], "rhythm": [0.0, 0.5, 1.5, 2.0, 3.0, 3.5], "melody": "pluck", "chords": "piano", "drums": "light", "density": 0.85, "structure": ["Intro", "Question", "Answer", "Tag"]}
		"electronic": details = {"progression": [0, 5, 3, 4], "rhythm": [0.0, 0.75, 1.5, 2.0, 2.75, 3.5], "melody": "lead", "chords": "poly", "drums": "four_floor", "density": 0.9, "structure": ["Intro", "Build", "Drop", "Break", "Drop", "Outro"], "default_scale": "minor"}
		"synthwave": details = {"progression": [0, 5, 2, 6], "rhythm": [0.0, 0.5, 1.5, 2.0, 2.5, 3.5], "melody": "lead", "chords": "pad", "drums": "backbeat", "density": 0.8, "default_scale": "minor"}
		"lo_fi": details = {"progression": [1, 4, 0, 5], "rhythm": [0.0, 0.75, 1.5, 2.5, 3.25], "melody": "piano", "chords": "piano", "drums": "lofi", "swing": 0.18, "seventh": true, "density": 0.55}
		"chiptune": details = {"progression": [0, 3, 4, 0], "rhythm": [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5], "melody": "chip", "chords": "chip", "drums": "chip", "density": 0.95}
		"jazz_inspired": details = {"progression": [1, 4, 0, 5], "rhythm": [0.0, 0.66, 1.66, 2.0, 2.66, 3.66], "melody": "piano", "chords": "piano", "bass": "pluck", "drums": "jazz", "swing": 0.28, "seventh": true, "density": 0.7}
		"acoustic_inspired": details = {"progression": [0, 4, 5, 3], "rhythm": [0.0, 1.0, 1.75, 2.5, 3.25], "melody": "pluck", "chords": "pluck", "bass": "pluck", "drums": "light", "density": 0.6}
		"action": details = {"progression": [0, 5, 3, 6], "rhythm": [0.0, 0.5, 0.75, 1.5, 2.0, 2.5, 3.0, 3.5], "melody": "brass", "chords": "strings", "drums": "cinematic", "density": 1.0, "default_scale": "minor", "structure": ["Intro", "Build", "Action", "Break", "Climax", "Outro"]}
		"fantasy": details = {"progression": [0, 3, 5, 4], "rhythm": [0.0, 1.0, 1.5, 2.0, 3.0], "melody": "bells", "chords": "strings", "drums": "light", "density": 0.6, "default_scale": "dorian"}
		"background_music": details = {"progression": [0, 5, 3, 4], "rhythm": [0.0, 1.5, 3.0], "melody": "piano", "chords": "pad", "drums": "light", "density": 0.4}
	common.merge(details, true)
	return common

static func generate(settings: Dictionary) -> Dictionary:
	var config := settings.duplicate(true)
	var style := _style(str(config.get("style", config.get("genre", "Ambient"))))
	var bpm := clampf(KiwiAudioSynthesis.finite(config.get("tempo", config.get("bpm", 100.0)), 100.0), 20.0, 300.0)
	var seed_value := int(config.get("seed", 1))
	var root := key_pitch(config.get("key", "C"))
	var mood := str(config.get("mood", "Neutral")).to_lower()
	var scale_name := str(config.get("scale", ""))
	if not SCALE_INTERVALS.has(scale_name):
		scale_name = "minor" if mood in ["sad", "dark", "melancholic"] else str(style.default_scale)
	var signature: Array = config.get("time_signature", [4, 4])
	var beats_per_bar := clampf(float(signature[0]) * 4.0 / maxf(1.0, float(signature[1])), 1.0, 16.0) if signature.size() >= 2 else 4.0
	var target_beats := clampf(KiwiAudioSynthesis.finite(config.get("duration", 32.0 * 60.0 / bpm), 30.0) * bpm / 60.0, beats_per_bar, 2048.0)
	if config.has("bars"): target_beats = clampi(int(config.bars), 1, 256) * beats_per_bar
	var energy := clampf(KiwiAudioSynthesis.finite(config.get("energy", 0.6), 0.6), 0.0, 1.0)
	var complexity := clampf(KiwiAudioSynthesis.finite(config.get("complexity", 0.5), 0.5), 0.0, 1.0)
	var repetition := clampf(KiwiAudioSynthesis.finite(config.get("repetition", 0.7), 0.7), 0.0, 1.0)
	var variation := clampf(KiwiAudioSynthesis.finite(config.get("variation", 0.35), 0.35), 0.0, 1.0)
	config.merge({"tempo": bpm, "key": root, "scale": scale_name, "seed": seed_value, "duration": target_beats * 60.0 / bpm, "time_signature": signature}, true)
	var section_names: Array = config.get("structure", style.structure)
	if section_names.is_empty(): section_names = ["A"]
	var bars := ceili(target_beats / beats_per_bar)
	var section_count := mini(section_names.size(), maxi(1, bars / 2))
	var sections: Array[Dictionary] = []
	var remaining := target_beats
	var section_start := 0.0
	for i in section_count:
		var section_duration := remaining if i == section_count - 1 else maxf(beats_per_bar, floor(remaining / (section_count - i) / beats_per_bar) * beats_per_bar)
		var name := str(section_names[i].get("name", "Section")) if section_names[i] is Dictionary else str(section_names[i])
		sections.append({"id": "section_%d" % i, "name": name, "start": section_start, "duration": section_duration})
		section_start += section_duration
		remaining -= section_duration
	# An explicit layout is editable data, with stable section IDs. Keep it exact
	# during partial regeneration rather than redistributing renamed sections.
	var layout: Variant = config.get("section_layout", [])
	if layout is Array and not layout.is_empty() and layout.size() <= 64:
		var exact: Array[Dictionary] = []
		var layout_end := 0.0
		for item in layout:
			if not item is Dictionary: continue
			var start := KiwiAudioSynthesis.finite(item.get("start", 0), 0)
			var length := KiwiAudioSynthesis.finite(item.get("duration", 4), 4)
			if start < 0 or length <= 0 or start + length > 2048: continue
			exact.append({"id":str(item.get("id", "section_%d" % exact.size())), "name":str(item.get("name", "Section")), "start":start, "duration":length})
			layout_end = maxf(layout_end, start + length)
		if not exact.is_empty():
			exact.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.start)<float(b.start))
			sections = exact; target_beats = layout_end; bars = ceili(target_beats / beats_per_bar)
			config.duration = target_beats * 60.0 / bpm; config.section_layout = exact.duplicate(true)
	var parts: Array[Dictionary] = []
	var instrument_overrides: Dictionary = config.get("instruments", {})
	for role in ["melody", "chords", "bass", "drums", "pad"]:
		var selected: Variant = instrument_overrides.get(role, style.get(role, "drums"))
		var instrument: Dictionary = selected.duplicate(true) if selected is Dictionary else KiwiAudioInstruments.default_instrument(str(selected))
		parts.append({"id": "part_" + role, "role": role, "instrument": instrument, "notes": [], "patterns": [], "automation": []})
	var chords: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var motif: Array[int] = [0, 2, 1, 4, 2, 1, 0, -1]
	if mood in ["happy", "bright", "playful"]: motif = [0, 2, 4, 3, 5, 4, 2, 0]
	elif mood in ["dark", "sad", "melancholic"]: motif = [4, 2, 1, 0, -1, 1, 2, 0]
	var motif_rotation := rng.randi_range(0, 3)
	var progression: Array = config.get("progression", style.progression)
	if progression.is_empty(): progression = [0]
	if not config.has("progression") and variation > 0.0:
		var variant := posmod(seed_value, 3)
		if style.id in ["jazz_inspired", "lo_fi"]:
			progression = [[1, 4, 0, 5], [1, 4, 2, 5], [1, 4, 0, 3]][variant]
		elif style.id not in ["horror", "suspense"] and variant > 0:
			progression = [0, 3, 5, 4] if variant == 1 else [0, 5, 1, 4]
	var chord_map: Array = config.get("chord_map", [])
	var previous_voicing: Array = []
	var harmonic_beats := beats_per_bar * int(style.harmonic_bars)
	var segments: Array[Dictionary] = []
	for section in sections:
		var cursor := float(section.start)
		var section_end := cursor + float(section.duration)
		while cursor < section_end - 0.000001:
			segments.append({"start":cursor,"duration":minf(beats_per_bar,section_end-cursor),"section":section})
			cursor += beats_per_bar
	for bar in segments.size():
		var bar_start := float(segments[bar].start)
		var bar_duration := float(segments[bar].duration)
		var section:Dictionary = segments[bar].section
		var section_id := str(section.id)
		var section_name := str(section.name).to_lower()
		var section_energy := energy
		if section_name in ["intro", "outro", "break"]: section_energy *= 0.5
		elif section_name in ["chorus", "drop", "climax", "action"]: section_energy = minf(1.0, energy + 0.2)
		var degree := int(progression[(int(bar_start / harmonic_beats)) % progression.size()])
		var mapped_chord: Dictionary = {}
		for existing: Dictionary in chord_map:
			if bar_start >= float(existing.get("start", 0.0)) and bar_start < float(existing.get("start", 0.0)) + float(existing.get("duration", harmonic_beats)):
				degree = int(existing.get("degree", degree))
				mapped_chord = existing
				break
		var voicing := voice_lead(chord(48 + root, scale_name, degree, 0, bool(style.seventh)), previous_voicing)
		if not mapped_chord.is_empty() and mapped_chord.get("pitches", []) is Array:
			voicing.assign(mapped_chord.pitches)
		previous_voicing = voicing
		if fmod(bar_start, harmonic_beats) < 0.0001 or is_equal_approx(bar_start,float(section.start)):
			chords.append({"id": "chord_%d" % chords.size(), "start": bar_start, "duration": minf(harmonic_beats, float(section.start)+float(section.duration) - bar_start), "degree": degree, "pitches": voicing.duplicate(), "section_id": section_id})
		var chord_velocity := 0.36 + section_energy * 0.3
		for k in voicing.size():
			var offset := k * 0.035 if style.id == "acoustic_inspired" else 0.0
			_append_note(parts[1], voicing[k], bar_start + offset, maxf(0.05, bar_duration * 0.93 - offset), chord_velocity, section_id, seed_value)
			if style.id in ["ambient", "cinematic", "orchestral_inspired", "fantasy", "horror"] and bar % int(style.harmonic_bars) == 0:
				_append_note(parts[4], voicing[k] - 12, bar_start, minf(harmonic_beats, float(section.start)+float(section.duration) - bar_start), chord_velocity * 0.65, section_id, seed_value)
		var bass_pitch := scale_pitch(degree, 36 + root, scale_name)
		var bass_steps: Array = [0.0, 2.0] if section_energy < 0.7 else [0.0, 1.5, 2.0, 3.5]
		if style.id == "ambient": bass_steps = [0.0]
		if style.id == "jazz_inspired": bass_steps = [0.0, 1.0, 2.0, 3.0]
		elif style.id != "ambient" and complexity > 0.3 and posmod(seed_value + bar, 3) == 0: bass_steps = [0.0, 1.0, 2.5]
		for b in bass_steps.size():
			var beat := float(bass_steps[b]) / 4.0 * beats_per_bar
			if beat >= bar_duration: continue
			var bass_note := bass_pitch
			if style.id == "jazz_inspired": bass_note = scale_pitch(degree + [0, 2, 4, 5][b % 4], 36 + root, scale_name)
			elif b % 2 == 1 and complexity > 0.4: bass_note = scale_pitch(degree + 4, 36 + root, scale_name)
			_append_note(parts[2], bass_note, bar_start + beat, minf(bar_duration - beat, beats_per_bar * (0.8 if style.id == "ambient" else 0.22)), 0.5 + section_energy * 0.35, section_id, seed_value)
		var rhythm: Array = style.rhythm
		var use_melody := not (section_name == "intro" and bar % 2 == 0)
		for r in rhythm.size():
			if not use_melody: break
			var beat := float(rhythm[r]) / 4.0 * beats_per_bar
			if beat >= bar_duration: continue
			if r > 0 and rng.randf() > float(style.density) * (0.45 + complexity * 0.55): continue
			var phrase := bar % 4
			var motif_index := (r + motif_rotation + (0 if rng.randf() < repetition else rng.randi_range(0, 2))) % motif.size()
			var melodic_degree := degree + motif[motif_index]
			if phrase >= 2: melodic_degree = degree + motif[(motif.size() - 1 - motif_index)] + (1 if complexity > 0.6 else 0)
			if rng.randf() < variation * 0.3: melodic_degree += rng.randi_range(-1, 1)
			var melodic_pitch := scale_pitch(melodic_degree, 60 + root, scale_name)
			if r == 0 or (phrase == 3 and r == rhythm.size() - 1):
				melodic_pitch = _nearest_chord(melodic_pitch, voicing)
			melodic_pitch = clampi(quantize_pitch(melodic_pitch, root, scale_name), 48, 91)
			var next_beat := float(rhythm[r + 1]) / 4.0 * beats_per_bar if r + 1 < rhythm.size() else beats_per_bar
			var note_duration := minf(bar_duration - beat, maxf(0.08, next_beat - beat) * (0.45 if style.id in ["comedy", "cartoon_music", "chiptune"] else 0.82))
			var swung := beat + (float(style.swing) * 0.5 if int(round(beat * 2.0)) % 2 == 1 else 0.0)
			if swung >= bar_duration: continue
			_append_note(parts[0], melodic_pitch, bar_start + swung, minf(note_duration, bar_duration - swung), 0.5 + section_energy * 0.35 + rng.randf_range(-0.06, 0.06), section_id, seed_value)
		if str(style.drums) != "none" and not (section_name in ["intro", "outro"] and section_energy < 0.3):
			var pattern := drum_pattern(str(style.drums), section_energy, complexity, bar == bars - 1 or _ends_section(section, bar_start + bar_duration), seed_value + bar)
			pattern.id = "pattern_%d_%d" % [seed_value, bar]
			pattern["start"] = bar_start
			pattern["section_id"] = section_id
			parts[3].patterns.append(pattern)
			var drum_notes := pattern_notes(pattern, 1, seed_value + bar)
			for drum: Dictionary in drum_notes:
				var start := float(drum.start) / 4.0 * beats_per_bar
				if start >= bar_duration: continue
				_append_note(parts[3], int(drum.pitch), bar_start + start, minf(float(drum.duration), bar_duration - start), float(drum.velocity), section_id, seed_value)
	# Keep empty editable roles, but all notes end inside the chosen arrangement.
	return {"version": 1, "parts": parts, "sections": sections, "chords": chords, "settings": config}

static func _append_note(part: Dictionary, pitch: int, start: float, duration: float, velocity: float, section_id: String, seed_value: int) -> void:
	part.notes.append(_note(pitch, start, duration, velocity, str(part.role), section_id, part.notes.size(), seed_value))

static func _nearest_chord(pitch: int, pitches: Array) -> int:
	var nearest := pitch
	var distance := 999
	for chord_pitch: int in pitches:
		for octave in [-12, 0, 12, 24]:
			var candidate := chord_pitch + int(octave)
			if absi(candidate - pitch) < distance:
				distance = absi(candidate - pitch)
				nearest = candidate
	return nearest

static func _section_at(sections: Array, beat: float) -> Dictionary:
	for section: Dictionary in sections:
		if beat >= float(section.start) and beat < float(section.start) + float(section.duration): return section
	return sections.back()

static func _ends_section(section: Dictionary, beat: float) -> bool:
	return beat >= float(section.start) + float(section.duration) - 0.001

## Generates new material only for the selected role/section. Other dictionaries,
## IDs, instrument settings, automation and notes are copied without alteration.
static func regenerate(settings: Dictionary, previous: Dictionary, role: String = "", section_id: String = "") -> Dictionary:
	if previous.is_empty(): return generate(settings)
	var config: Dictionary = previous.get("settings", {}).duplicate(true)
	config.merge(settings, true)
	if not settings.has("seed"): config.seed = int(config.get("seed", 1)) + 1
	if not role.is_empty() and role not in ["chords", "part_chords"]:
		config["chord_map"] = previous.get("chords", []).duplicate(true)
	config["section_layout"] = previous.get("sections", []).duplicate(true)
	var fresh := generate(config)
	if role.is_empty() and section_id.is_empty(): return fresh
	var result: Dictionary = previous.duplicate(true)
	var section: Dictionary = {}
	for candidate: Dictionary in previous.get("sections", []):
		if str(candidate.id) == section_id: section = candidate
	if not section_id.is_empty() and section.is_empty(): return result
	var start := float(section.get("start", 0.0))
	var end := start + float(section.get("duration", INF))
	for part: Dictionary in result.get("parts", []):
		if not role.is_empty() and str(part.role) != role and str(part.id) != role: continue
		var replacement: Dictionary = {}
		for candidate: Dictionary in fresh.parts:
			if candidate.role == part.role:
				replacement = candidate
				break
		if replacement.is_empty(): continue
		var notes: Array = []
		for note: Dictionary in part.get("notes", []):
			if not section_id.is_empty() and not (float(note.start) >= start and float(note.start) < end): notes.append(note)
		for note: Dictionary in replacement.notes:
			if section_id.is_empty() or (float(note.start) >= start and float(note.start) < end):
				var changed := note.duplicate(true)
				if not section_id.is_empty():
					changed.section_id = section_id
					changed.duration = minf(float(changed.duration), end - float(changed.start))
				notes.append(changed)
		notes.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.start) < float(b.start))
		part.notes = notes
		if str(part.role) == "drums":
			var patterns: Array = []
			for pattern: Dictionary in part.get("patterns", []):
				if not section_id.is_empty() and not (float(pattern.get("start", 0.0)) >= start and float(pattern.get("start", 0.0)) < end): patterns.append(pattern)
			for pattern: Dictionary in replacement.get("patterns", []):
				if section_id.is_empty() or (float(pattern.get("start", 0.0)) >= start and float(pattern.get("start", 0.0)) < end): patterns.append(pattern)
			part.patterns = patterns
	if role.is_empty() or role in ["chords", "part_chords"]:
		var harmonic: Array = []
		for item: Dictionary in result.get("chords", []):
			if not section_id.is_empty() and not (float(item.start) >= start and float(item.start) < end): harmonic.append(item)
		for item: Dictionary in fresh.chords:
			if section_id.is_empty() or (float(item.start) >= start and float(item.start) < end): harmonic.append(item)
		result.chords = harmonic
	# Save regeneration provenance without silently changing the arrangement tempo.
	result["last_regeneration"] = {"seed": config.seed, "role": role, "section_id": section_id}
	return result

## Steps are dictionaries, so probability, ratchets, accents and velocity remain
## editable. A lane supports mute/solo; pattern lengths need not be sixteen.
static func pattern_notes(pattern: Dictionary, repeats: int = 1, seed_value: int = 1) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var lanes: Array = pattern.get("lanes", [])
	var steps := clampi(int(pattern.get("steps", 16)), 1, 256)
	var length_beats := clampf(float(pattern.get("length", 4.0)), 0.0625, 64.0)
	var swing := clampf(float(pattern.get("swing", 0.0)), -0.45, 0.45)
	var has_solo := lanes.any(func(lane: Dictionary): return bool(lane.get("solo", false)))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for repeat_index in clampi(repeats, 1, 256):
		for lane_index in lanes.size():
			var lane: Dictionary = lanes[lane_index]
			if bool(lane.get("mute", false)) or (has_solo and not bool(lane.get("solo", false))): continue
			var lane_steps: Array = lane.get("values", [])
			for step_index in mini(steps, lane_steps.size()):
				var entry: Variant = lane_steps[step_index]
				var cell: Dictionary = entry if entry is Dictionary else {"velocity": float(entry), "enabled": float(entry) > 0.0}
				if not bool(cell.get("enabled", true)) or rng.randf() > clampf(float(cell.get("probability", 1.0)), 0.0, 1.0): continue
				var velocity := clampf(float(cell.get("velocity", 0.8)) * (1.2 if bool(cell.get("accent", false)) else 1.0), 0.0, 1.0)
				if velocity <= 0.0: continue
				var ratchets := clampi(int(cell.get("ratchets", 1)), 1, 8)
				var step_beats := length_beats / steps
				var swung_length := step_beats * (1.0 - swing if step_index % 2 == 1 else 1.0 + swing)
				for ratchet in ratchets:
					var start := repeat_index * length_beats + step_index * step_beats + (swing * step_beats if step_index % 2 == 1 else 0.0) + ratchet * swung_length / ratchets
					if start >= (repeat_index + 1) * length_beats: continue
					var note := _note(int(lane.get("pitch", 36)), start, minf(swung_length * 0.8 / ratchets, (repeat_index + 1) * length_beats - start), velocity, str(lane_index), str(repeat_index), result.size(), seed_value)
					result.append(note)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.start) < float(b.start))
	return result

static func drum_pattern(style: String, energy: float = 0.6, complexity: float = 0.5, fill: bool = false, seed_value: int = 1) -> Dictionary:
	var lanes: Array[Dictionary] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for pitch in [36, 38, 42, 46]:
		var values: Array = []
		for step in 16:
			var enabled := false
			var velocity := 0.6
			match pitch:
				36:
					enabled = step % 4 == 0 if style == "four_floor" else step in [0, 8]
					if style == "pulse": enabled = step in [0, 3, 8, 11]
					if complexity > 0.6 and step in [6, 14] and style != "light": enabled = true
					velocity = 0.65 + energy * 0.3
				38:
					enabled = step in [4, 12] and style != "pulse"
					if style == "cinematic": enabled = step in [6, 12]
					if fill and step >= 12: enabled = step % (1 if complexity > 0.65 else 2) == 0
					velocity = 0.52 + energy * 0.3
				42:
					enabled = step % (1 if energy > 0.8 else 2) == 0 and style not in ["pulse", "cinematic"]
					if style == "light": enabled = step in [2, 6, 10, 14]
					velocity = (0.32 if step % 4 == 2 else 0.46) + energy * 0.1
				46:
					enabled = step == 14 and energy > 0.45 and style not in ["light", "pulse", "cinematic"]
					velocity = 0.42 + energy * 0.15
			values.append({"enabled": enabled, "velocity": clampf(velocity + rng.randf_range(-0.04, 0.04), 0.0, 1.0), "probability": 1.0, "ratchets": 1, "accent": step == 0})
		lanes.append({"id": "drum_%d" % pitch, "pitch": pitch, "mute": false, "solo": false, "values": values})
	return {"id": ActorData.new_id(), "steps": 16, "length": 4.0, "swing": 0.2 if style in ["lofi", "jazz"] else 0.0, "lanes": lanes}

static func quantize_notes(notes: Array, grid: float = 0.25, strength: float = 1.0) -> Array:
	var result := notes.duplicate(true)
	var interval := maxf(0.001, grid)
	for note: Dictionary in result:
		note.start = lerpf(float(note.start), round(float(note.start) / interval) * interval, clampf(strength, 0.0, 1.0))
		note.duration = maxf(interval, lerpf(float(note.duration), round(float(note.duration) / interval) * interval, clampf(strength, 0.0, 1.0)))
	return result

static func humanize(notes: Array, timing: float = 0.02, velocity: float = 0.06, seed_value: int = 1) -> Array:
	var result := notes.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for note: Dictionary in result:
		note.start = maxf(0.0, float(note.start) + rng.randf_range(-absf(timing), absf(timing)))
		note.velocity = clampf(float(note.get("velocity", 0.8)) + rng.randf_range(-absf(velocity), absf(velocity)), 0.0, 1.0)
	return result

static func arpeggiate(pitches: Array, start: float, duration: float, step: float = 0.25, direction: String = "up") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if pitches.is_empty(): return result
	var ordered: Array = pitches.duplicate()
	ordered.sort()
	if direction == "down": ordered.reverse()
	if direction == "up_down" and ordered.size() > 2:
		var back := ordered.slice(1, ordered.size() - 1)
		back.reverse()
		ordered.append_array(back)
	var spacing := maxf(0.03125, step)
	var count := mini(8192, ceili(duration / spacing))
	for i in count:
		result.append(new_note(int(ordered[i % ordered.size()]), start + i * spacing, minf(spacing * 0.8, duration - i * spacing), 0.8 if i % ordered.size() == 0 else 0.65))
	return result

static func harmonize(notes: Array, key: Variant = "C", scale_name: String = "major", interval: int = 2) -> Array:
	var result := notes.duplicate(true)
	var root := key_pitch(key)
	var scale: Array = SCALE_INTERVALS.get(scale_name, SCALE_INTERVALS.major)
	for note: Dictionary in result:
		var pitch := quantize_pitch(int(note.pitch), root, scale_name)
		var degree := scale.find(posmod(pitch - root, 12))
		var octave := floori(float(pitch - root) / 12.0)
		note.pitch = clampi(scale_pitch(degree + interval, root + octave * 12, scale_name), 0, 127)
		note.id = ActorData.new_id()
	return result

