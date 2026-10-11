extends SceneTree
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void: run.call_deferred()

func wave(rate: int, seconds: int, value: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	var bytes := PackedByteArray()
	bytes.resize(rate * seconds * 2)
	for frame in rate * seconds: bytes.encode_s16(frame * 2, value)
	stream.data = bytes
	return stream

func run() -> void:
	var preferences := EditorAudioSettings.read()
	check(preferences.has("record_mic") and preferences.has("record_system") and preferences.has("record_timeline"), "Recording sources have independent saved preferences")
	var mic := wave(22050, 1, 4096)
	var system := wave(48000, 2, 8192)
	check(ActorAudioRecorder.mix_streams(mic, null) == mic, "Mic-only recording retains its source")
	check(ActorAudioRecorder.mix_streams(null, system) == system, "System-only recording retains its source")
	var mixed := ActorAudioRecorder.mix_streams(mic, system)
	check(mixed.stereo and mixed.mix_rate == 48000 and is_equal_approx(mixed.get_length(), 2.0), "Mixed sources resample and preserve full recording duration")
	check(mixed.data.decode_s16(0) == 12288, "Both selected sources contribute to the recording")
	check(mixed.data.decode_s16(48000 * 4 + 100) == 8192, "A shorter source contributes silence after ending")
	var stereo := AudioStreamWAV.new()
	stereo.format = AudioStreamWAV.FORMAT_16_BITS
	stereo.mix_rate = 48000
	stereo.stereo = true
	var stereo_data := PackedByteArray()
	stereo_data.resize(48000 * 30 * 4)
	stereo_data.encode_s16(0, 12000)
	stereo_data.encode_s16(2, -4000)
	stereo.data = stereo_data
	var started := Time.get_ticks_msec()
	ActorAudioRecorder.convert_to_mono(stereo)
	check(not stereo.stereo and is_equal_approx(stereo.get_length(), 30.0), "Mono finalization preserves a realistic recording duration")
	check(stereo.data.decode_s16(0) == 4000, "Mono conversion averages both channels")
	check(Time.get_ticks_msec() - started < 5000, "Thirty-second mono finalization completes without repeated whole-buffer copies")
	var editor := ActorTimelineEditor.new()
	root.add_child(editor)
	check(editor.mic_options_button.get_parent() == editor.mic_button, "Recording dropdown is part of the mic split button")
	await process_frame
	await process_frame
	check(editor.mic_options_button.get_rect().end.x <= editor.mic_button.size.x, "Dropdown fits within the shared record button outline")
	editor.mic_options_button.call("open_settings")
	var popup: PopupPanel = editor.mic_options_button.get("popup")
	var sources: Array[CheckBox] = []
	for node in popup.get_child(0).get_children():
		if node is CheckBox: sources.append(node)
	check(sources.size() == 3 and sources.all(func(source: CheckBox): return source.button_group == null), "Microphone, system and timeline sources can be enabled together")
	check(popup.find_child("RecordTimelineAudio", true, false) != null, "Recording options expose timeline audio")
	var gain := popup.find_child("InputGain", true, false) as DragNumber
	check(gain != null, "Input gain supports dragging")
	var original := gain.value
	gain.drag_pixels(8, false, false)
	check(is_equal_approx(gain.value, original + 0.2), "Input gain previews drag changes")
	check(is_equal_approx(editor.mic_options_button.get("preferences").gain_db, gain.value), "Gain preview updates preferences without saving during the gesture")
	for node in popup.get_child(0).get_children():
		if node is Label: check(not node.text.contains("Changes apply"), "Recording dropdown has no instruction footer")
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	check(main.get_node("MainUI/ColorRect/VBoxContainer/HBoxContainer/EditorButton").get_script() == null, "Microphone options are no longer attached to Editor")
	main.free()
	editor.free()
	await process_frame
	print("Recording source checks: %d failures" % failures)
	quit(failures)
