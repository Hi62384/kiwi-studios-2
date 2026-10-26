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
	var categories: Dictionary = {}
	var hashes: Dictionary = {}
	var source := KiwiAudioSynthesis.generate("wind", {"duration": 0.3}, 44, 16000)
	for preset: Dictionary in KiwiAudioSynthesis.presets():
		categories[preset.category] = true
		var settings := KiwiAudioSynthesis.default_settings(str(preset.id))
		settings.duration = 0.22
		if preset.id == "sample_grains": settings.sample = source
		var stream := KiwiAudioSynthesis.generate(str(preset.id), settings, 123, 16000)
		check(stream != null, str(preset.id) + " returns a stream")
		if stream == null: continue
		check(energy(stream) > 0.00000001, str(preset.id) + " is audible PCM")
		var data := stream.data
		check(data.size() == 3520 * 2, str(preset.id) + " duration is sample-exact")
		check(data.decode_s16(0) == 0 and data.decode_s16(data.size() - 2) == 0, str(preset.id) + " endpoints are smooth")
		var peak := 0
		for i in data.size() / 2: peak = maxi(peak, absi(data.decode_s16(i * 2)))
		check(peak <= 31458, str(preset.id) + " has limiter headroom")
		var again := KiwiAudioSynthesis.generate(str(preset.id), settings, 123, 16000)
		check(again.data == data, str(preset.id) + " seed is deterministic")
		hashes[data.hex_encode().sha256_text()] = true
		for parameter in ["pitch", "character", "density", "distance"]:
			var varied := settings.duplicate(true)
			varied[parameter] = float(settings.get(parameter, 0.5)) * 1.5 if parameter == "pitch" else (0.05 if float(settings.get(parameter, 0.5)) > 0.25 else 0.95)
			if parameter == "density" and preset.id in ["footsteps", "heartbeat"]:
				var baseline := settings.duplicate(true)
				baseline.duration = 1.5
				varied.duration = 1.5
				check(KiwiAudioSynthesis.generate(str(preset.id), varied, 123, 16000).data != KiwiAudioSynthesis.generate(str(preset.id), baseline, 123, 16000).data, str(preset.id) + " changes repeated-event spacing")
			else:
				check(KiwiAudioSynthesis.generate(str(preset.id), varied, 123, 16000).data != data, str(preset.id) + " responds to " + parameter)
	check(categories.size() >= 12, "All eleven requested families and samples have presets")
	check(hashes.size() >= 45, "Presets yield distinct PCM, not duplicated audio")
	var base := KiwiAudioSynthesis.generate("explosion", {"duration": 0.3, "power": 0.7}, 1, 16000)
	var soft := KiwiAudioSynthesis.generate("explosion", {"duration": 0.3, "power": 0.1}, 1, 16000)
	check(energy(base) > energy(soft) * 10.0, "Power changes signal energy")
	check(base.data != KiwiAudioSynthesis.generate("explosion", {"duration": 0.3, "power": 0.7}, 2, 16000).data, "Seed changes stochastic texture")
	check(base.data != KiwiAudioSynthesis.generate("explosion", {"duration": 0.3, "pitch": 200.0}, 1, 16000).data, "Pitch changes generated material")
	var laser := KiwiAudioSynthesis.generate("laser", {"duration": 0.3}, 1, 16000)
	var layered := KiwiAudioSynthesis.layer([{"stream": base, "pan": -1.0}, {"stream": laser, "start": 0.2, "pan": 1.0}], 16000)
	check(layered.stereo and absf(layered.get_length() - 0.5) < 0.001, "Layer render preserves offsets and channels")
	check(base.data == KiwiAudioSynthesis.generate("explosion", {"duration": 0.3, "power": 0.7}, 1, 16000).data, "Layer render does not mutate source")
	var path := "user://generator_roundtrip.json"
	var preset_data := {"generator": "explosion", "settings": {"power": 0.4}, "layers": [{"generator": "metal_impact", "start": 0.1}]}
	check(KiwiAudioSynthesis.save_preset(path, preset_data) == OK, "Preset save succeeds")
	check(KiwiAudioSynthesis.load_preset(path) == preset_data, "Preset settings and layers roundtrip")
	DirAccess.remove_absolute(path)
	check(KiwiAudioSynthesis.generate("missing", {}, 1, 16000) == null, "Unknown generator fails explicitly")
	check(KiwiAudioSynthesis.generate("sample_grains", {}, 1, 16000) == null, "Missing required sample fails explicitly")
	print("Audio synthesis checks: %d failures, %d presets, %d ms (isolated preflight when run in fixture)" % [failures, KiwiAudioSynthesis.presets().size(), Time.get_ticks_msec() - started])
	quit(failures)
