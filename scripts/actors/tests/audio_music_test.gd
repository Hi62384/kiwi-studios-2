extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void: run.call_deferred()
func energy(stream: AudioStreamWAV) -> float:
	if stream == null: return 0.0
	var bytes := stream.data
	var sum := 0.0
	for i in bytes.size() / 2: sum += pow(bytes.decode_s16(i * 2) / 32768.0, 2.0)
	return sum / maxf(1.0, bytes.size() / 2.0)
func run() -> void:
	var started := Time.get_ticks_msec()
	check(is_equal_approx(KiwiAudioInstruments.midi_frequency(69), 440.0), "A4 is 440 Hz")
	var note := {"id": "test", "pitch": 69, "start": 0.25, "duration": 0.5, "velocity": 1.0, "pan": 0.0}
	var patch := {"id": "additive", "harmonics": [1.0], "attack": 0.005, "decay": 0.01, "sustain": 1.0, "release": 0.03, "filter": 6000.0}
	var wave := KiwiAudioInstruments.render_notes([note], patch, 120.0, 16000)
	check(wave != null and energy(wave) > 0.001, "Notes render native stereo PCM")
	var data := wave.data
	var first := 0
	while first < data.size() / 4 and data.decode_s16(first * 4) == 0: first += 1
	check(absi(first - 2000) < 10, "Note onset is sample-accurate")
	var crossings := 0
	for i in range(2501, 5500):
		if data.decode_s16((i - 1) * 4) <= 0 and data.decode_s16(i * 4) > 0: crossings += 1
	check(absf(crossings * 16000.0 / 3000.0 - 440.0) < 8.0, "Rendered pitch is A4")
	var quiet := note.duplicate(true)
	quiet.velocity = 0.2
	check(energy(wave) > energy(KiwiAudioInstruments.render_notes([quiet], patch, 120.0, 16000)) * 10.0, "Velocity affects audio energy")
	var lowpass := patch.duplicate(true)
	lowpass.filter = 100.0
	check(energy(KiwiAudioInstruments.render_notes([note], lowpass, 120.0, 16000)) < energy(wave) * 0.1, "Instrument low-pass attenuates above-cutoff energy")
	var fm_a := KiwiAudioInstruments.render_notes([note], {"id": "fm", "modulation": 0.0}, 120.0, 16000)
	var fm_b := KiwiAudioInstruments.render_notes([note], {"id": "fm", "modulation": 4.0}, 120.0, 16000)
	check(fm_a.data != fm_b.data, "FM modulation changes timbre")
	check(fm_a.data == KiwiAudioInstruments.render_notes([note], {"id": "fm", "modulation": 0.0}, 120.0, 16000).data, "Instrument rendering is deterministic")
	var fast := KiwiAudioInstruments.render_notes([note], patch, 240.0, 16000)
	check(fast.get_length() < wave.get_length(), "Tempo changes note timing")
	check(KiwiAudioInstruments.envelope(0.05, 1.0, 0.1, 0.2, 0.5, 0.2) < KiwiAudioInstruments.envelope(0.1, 1.0, 0.1, 0.2, 0.5, 0.2), "ADSR attack rises")
	check(KiwiAudioInstruments.envelope(1.25, 1.0, 0.1, 0.2, 0.5, 0.2) == 0.0, "ADSR release reaches zero")
	var disabled := note.duplicate(true)
	disabled.probability = 0.0
	check(energy(KiwiAudioInstruments.render_notes([disabled], patch, 120.0, 16000)) == 0.0, "Step probability zero omits sound")
	var source := KiwiAudioSynthesis.generate("ui_confirm", {"duration": 0.2}, 1, 16000)
	for instrument: Dictionary in KiwiAudioInstruments.presets():
		if instrument.kind == "sampler": instrument.sample = source
		if instrument.kind == "multisample": instrument.multisamples = [{"sample": source, "low": 0, "high": 127, "root_pitch": 69}]
		instrument.release = 0.05
		instrument.attack = 0.005
		var rendered := KiwiAudioInstruments.render_notes([note], instrument, 180.0, 16000)
		check(rendered != null and energy(rendered) > 0.0000001, str(instrument.id) + " produces audio")
	var stereo_frames := PackedVector2Array()
	stereo_frames.resize(1600)
	for frame in stereo_frames.size(): stereo_frames[frame] = Vector2(sin(TAU * 440.0 * frame / 16000.0) * 0.3, 0.0)
	var stereo_source := KiwiAudioSourceCache.to_wav(stereo_frames, 16000, true)
	var sampled := KiwiAudioInstruments.render_notes([{"pitch": 60, "start": 0.0, "duration": 0.4, "velocity": 1.0}], {"id": "sampler", "sample": stereo_source}, 120.0, 16000)
	var sampled_bytes := sampled.data
	var right_peak := 0
	var left_peak := 0
	for frame in sampled_bytes.size() / 4:
		left_peak = maxi(left_peak, absi(sampled_bytes.decode_s16(frame * 4)))
		right_peak = maxi(right_peak, absi(sampled_bytes.decode_s16(frame * 4 + 2)))
	check(left_peak > 100 and right_peak == 0, "Sampler preserves independent stereo channels")
	var sustain_note := {"pitch": 69, "start": 0.0, "duration": 0.25, "velocity": 1.0}
	var release_patch := patch.duplicate(true)
	release_patch.release = 0.2
	var released := KiwiAudioInstruments.render_notes([sustain_note], release_patch, 120.0, 16000)
	check(released.get_length() >= 0.325 - 0.0001, "Instrument output includes release tail")
	check(released.data.decode_s16(released.data.size() - 4) == 0, "Release tail ends at zero")
	check(KiwiAudioInstruments.render_notes([note], {"id": "sampler", "sample": "missing"}, 120.0, 16000) == null, "Missing sample is reported instead of faked")
	var settings := {"style": "Electronic", "key": "D", "scale": "minor", "bars": 8, "tempo": 120.0, "seed": 77}
	var music := KiwiAudioComposer.generate(settings)
	check(music == KiwiAudioComposer.generate(settings), "Composition is deterministic including generated IDs")
	var allowed: Array = KiwiAudioComposer.scales().minor
	var total_notes := 0
	for part: Dictionary in music.parts:
		for item: Dictionary in part.notes:
			total_notes += 1
			check(float(item.start) >= 0.0 and float(item.start) + float(item.duration) <= 32.0001, "Notes stay inside arrangement")
			if part.role != "drums": check(posmod(int(item.pitch) - 2, 12) in allowed, "Generated pitched notes remain in selected scale")
	check(total_notes > 50 and music.sections.size() >= 2 and music.chords.size() >= 4, "Music has parts, harmony and sections")
	var regen := KiwiAudioComposer.regenerate({"seed": 78}, music, "melody", str(music.sections[1].id))
	for i in music.parts.size():
		if music.parts[i].role != "melody": check(music.parts[i] == regen.parts[i], "Partial regeneration preserves unrelated parts")
	check(music.sections == regen.sections and music.settings == regen.settings, "Partial regeneration preserves structure and tempo")
	var section_start := float(music.sections[1].start)
	for item: Dictionary in music.parts[0].notes:
		if float(item.start) < section_start: check(item in regen.parts[0].notes, "Other section notes retain IDs and data")
	var changed_chords := KiwiAudioComposer.regenerate({"seed": 79}, music, "chords")
	check(changed_chords.chords != music.chords, "Chord regeneration changes harmony")
	for i in music.parts.size():
		if music.parts[i].role != "chords": check(changed_chords.parts[i] == music.parts[i], "Chord regeneration preserves unrelated edits")
	var uncommon_meter := KiwiAudioComposer.generate({"style": "Fantasy", "time_signature": [7, 8], "bars": 3})
	check(is_equal_approx(float(uncommon_meter.settings.duration) * float(uncommon_meter.settings.tempo) / 60.0, 10.5), "Non-4/4 duration uses quarter-note beats")
	var ambient := KiwiAudioComposer.generate({"style": "Ambient", "bars": 8, "seed": 77})
	check(ambient.parts[3].notes.is_empty(), "Ambient uses no default drum groove")
	check(ambient.parts[0].instrument.id != music.parts[0].instrument.id, "Style changes orchestration")
	for style: String in KiwiAudioComposer.styles():
		var generated := KiwiAudioComposer.generate({"style": style, "bars": 4, "seed": 1})
		check(generated.parts[0].notes.size() > 0, style + " yields an editable melody")
	var pattern := {"steps": 4, "length": 1.0, "swing": 0.2, "lanes": [{"pitch": 36, "values": [{"velocity": 0.8, "ratchets": 2}, 0.0, {"velocity": 0.8, "probability": 0.0}, 1.0]}]}
	var steps := KiwiAudioComposer.pattern_notes(pattern, 2, 5)
	check(steps.size() == 6, "Ratchets, probability, disabled steps and repeat are honored")
	check(is_equal_approx(float(steps[3].start) - float(steps[0].start), 1.0), "Pattern repeats at exact musical length")
	check(steps == KiwiAudioComposer.pattern_notes(pattern, 2, 5), "Pattern probability uses deterministic seed")
	print("Audio music checks: %d failures, %d ms" % [failures, Time.get_ticks_msec() - started])
	quit(failures)
