extends SceneTree
## Explicit demonstration render harness. Defaults to user://audio_test_collection.
## Pass -- --out=/an/absolute/directory to choose another output location.
var failures := 0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	# Each run preserves previous demonstrations (MIDI export intentionally
	# refuses overwrites). A fixed folder made the second QA run fail.
	var output := "user://audio_test_collection/"+ActorData.new_id()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.substr(6)
	var directory_error := DirAccess.make_dir_recursive_absolute(output)
	if directory_error != OK:
		push_error("Could not create demonstration directory.")
		quit(1)
		return
	var ids := ["punch", "metal_impact", "wood_impact", "glass_impact", "explosion", "whoosh", "footsteps", "rolling", "wood_creak", "glass_break", "fabric_rustle", "wind", "rain", "thunder", "water", "fire", "insects", "laser", "plasma", "charge", "force_field", "sparkle", "spell", "whisper", "drone", "sting", "heartbeat", "boing", "pop", "slide_whistle", "ui_confirm", "ui_notify", "riser", "sub_drop", "logo_sting", "motor", "servo", "gear", "hydraulic"]
	var report := {"engine": Engine.get_version_info(), "sample_rate": 44100, "seed": 2026, "audibly_reviewed": false, "scope": "Synthetic stylizations; no realism claim. Listen before production use.", "examples": []}
	for id: String in ids:
		var settings := KiwiAudioSynthesis.default_settings(id)
		settings.duration = minf(float(settings.duration), 3.0)
		var started := Time.get_ticks_msec()
		var stream := KiwiAudioSynthesis.generate(id, settings, 2026, 44100)
		var elapsed := Time.get_ticks_msec() - started
		var file := output.path_join(id + ".wav")
		var error := stream.save_to_wav(file) if stream != null else ERR_CANT_CREATE
		if error != OK: failures += 1
		var peak := 0
		var square := 0.0
		if stream != null:
			var bytes := stream.data
			for i in bytes.size() / 2:
				var sample := bytes.decode_s16(i * 2)
				peak = maxi(peak, absi(sample))
				square += pow(sample / 32768.0, 2.0)
			report.examples.append({"id": id, "category": KiwiAudioSynthesis.preset(id).category, "file": id + ".wav", "seconds": stream.get_length(), "render_ms": elapsed, "peak": peak / 32768.0, "rms": sqrt(square / maxf(1.0, bytes.size() / 2.0)), "settings": settings, "error": error})
	var arrangement := KiwiAudioComposer.generate({"style": "Electronic", "key": "D", "scale": "minor", "bars": 4, "tempo": 120.0, "seed": 2026})
	var layers: Array = []
	for part: Dictionary in arrangement.parts:
		if part.notes.is_empty(): continue
		var stream := KiwiAudioInstruments.render_notes(part.notes, part.instrument, 120.0, 44100)
		if stream == null:
			failures += 1
			continue
		layers.append({"stream": stream, "volume": 0.6, "pan": -0.15 if part.role == "chords" else 0.0})
	var music := KiwiAudioSynthesis.layer(layers, 44100)
	if music.save_to_wav(output.path_join("electronic_arrangement.wav")) != OK: failures += 1
	if KiwiAudioMIDI.write(output.path_join("electronic_arrangement.mid"), arrangement.parts, 120.0, [4, 4]) != OK: failures += 1
	var editable := FileAccess.open(output.path_join("electronic_arrangement.json"), FileAccess.WRITE)
	if editable != null:
		editable.store_string(JSON.stringify(arrangement, "\t"))
		editable.close()
	var report_file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	else: failures += 1
	print("Audio demonstration collection: %d examples + editable music/WAV/MIDI; %d failures; %s" % [report.examples.size(), failures, output])
	quit(failures)
