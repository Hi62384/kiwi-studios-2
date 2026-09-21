class_name ActorAudioRecorder
extends Node
## An isolated, muted capture bus prevents microphone feedback into speakers.
var player: AudioStreamPlayer
var effect: AudioEffectRecord
var bus_name := ""
var recording := false
var preferences_override: Dictionary = {}
var capture: AudioEffectCapture
var peaks := PackedFloat32Array()
var _peak := 0.0
var _peak_frames := 0
var _mono := false
var system_capture: WindowsSystemAudio
var _system_peaks := PackedFloat32Array()
var _mic_peaks := PackedFloat32Array()
var _system_peak := 0.0
var _system_frames := 0

func start() -> String:
	if recording: return ""
	var preferences := EditorAudioSettings.read() if preferences_override.is_empty() else preferences_override
	if not preferences.record_mic and not preferences.record_system: return "Select microphone audio, system audio, or both in the recording dropdown."
	if DisplayServer.get_name() == "headless": return "Microphone capture is unavailable in headless mode."
	if preferences.record_mic and not ProjectSettings.get_setting("audio/driver/enable_input", false):
		return "Microphone input is disabled. Restart the application to enable recording."
	if preferences.record_mic and AudioServer.get_input_device_list().is_empty(): return "No microphone input device is available."
	if preferences.record_system:
		system_capture = WindowsSystemAudio.new()
		add_child(system_capture)
		var error: String = await system_capture.start()
		if not error.is_empty():
			_cleanup()
			return error
	if preferences.record_mic: AudioServer.input_device = preferences.device if AudioServer.get_input_device_list().has(preferences.device) else "Default"
	_mono = preferences.mono
	peaks.clear()
	_peak = 0.0
	_peak_frames = 0
	_system_peaks.clear()
	_mic_peaks.clear()
	_system_peak = 0.0
	_system_frames = 0
	if not preferences.record_mic:
		recording = true
		return ""
	bus_name = "ActorMicrophone_%s" % get_instance_id()
	AudioServer.add_bus()
	var bus := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus, bus_name)
	AudioServer.set_bus_mute(bus, true)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 0.5
	AudioServer.add_bus_effect(bus, capture)
	effect = AudioEffectRecord.new()
	effect.format = AudioStreamWAV.FORMAT_16_BITS
	AudioServer.add_bus_effect(bus, effect)
	player = AudioStreamPlayer.new()
	player.stream = AudioStreamMicrophone.new()
	player.bus = bus_name
	player.volume_db = preferences.gain_db
	add_child(player)
	effect.set_recording_active(true)
	player.play()
	recording = true
	return ""

func stop() -> AudioStreamWAV:
	if not recording: return null
	recording = false
	var stream: AudioStreamWAV
	if effect != null:
		effect.set_recording_active(false)
		player.stop()
		stream = effect.get_recording()
	var system: AudioStreamWAV
	if system_capture != null: system = await system_capture.stop()
	var name := "Microphone + System Recording" if stream != null and system != null else ("System Audio Recording" if system != null else "Microphone Recording")
	stream = mix_streams(stream, system)
	_cleanup()
	if stream == null or stream.get_length() <= 0.0: return null
	stream.resource_name = name
	if _mono and stream.stereo:
		convert_to_mono(stream)
	return stream

static func convert_to_mono(stream: AudioStreamWAV) -> void:
	if not stream.stereo: return
	# AudioStreamWAV.data is a copying getter. Never call it inside a sample loop.
	var source := stream.data
	var data := PackedByteArray()
	data.resize((source.size() / 4) * 2)
	for frame in source.size() / 4:
		data.encode_s16(frame * 2, (source.decode_s16(frame * 4) + source.decode_s16(frame * 4 + 2)) / 2)
	stream.data = data
	stream.stereo = false

func _process(_delta: float) -> void:
	if not recording: return
	if system_capture != null:
		for sample in system_capture.samples():
			_system_peak = maxf(_system_peak, maxf(absf(sample.x), absf(sample.y)))
			_system_frames += 1
			if _system_frames >= int(system_capture.rate / 100.0):
				_system_peaks.append(_system_peak)
				_system_peak = 0.0
				_system_frames = 0
	var samples := capture.get_buffer(capture.get_frames_available()) if capture != null and capture.get_frames_available() > 0 else PackedVector2Array()
	for sample in samples:
		_peak = maxf(_peak, maxf(absf(sample.x), absf(sample.y)))
		_peak_frames += 1
		if _peak_frames >= int(AudioServer.get_mix_rate() / 100.0):
			_mic_peaks.append(_peak)
			_peak = 0.0
			_peak_frames = 0
	peaks = _mic_peaks.duplicate()
	if not _system_peaks.is_empty():
		while peaks.size() < _system_peaks.size(): peaks.append(0.0)
		for index in _system_peaks.size(): peaks[index] = minf(1.0, peaks[index] + _system_peaks[index])

static func mix_streams(mic: AudioStreamWAV, system: AudioStreamWAV) -> AudioStreamWAV:
	if mic == null: return system
	if system == null: return mic
	var output := AudioStreamWAV.new()
	output.format = AudioStreamWAV.FORMAT_16_BITS
	output.stereo = true
	output.mix_rate = system.mix_rate
	var frames := int(maxf(mic.get_length(), system.get_length()) * output.mix_rate)
	var data := PackedByteArray()
	data.resize(frames * 4)
	var mic_data := mic.data
	var system_data := system.data
	for frame in frames:
		var sample := _sample_data(mic_data, mic.mix_rate, mic.stereo, float(frame) / output.mix_rate) + _sample_data(system_data, system.mix_rate, system.stereo, float(frame) / output.mix_rate)
		data.encode_s16(frame * 4, clampi(int(sample.x * 32768.0), -32768, 32767))
		data.encode_s16(frame * 4 + 2, clampi(int(sample.y * 32768.0), -32768, 32767))
	output.data = data
	return output

static func _sample(stream: AudioStreamWAV, time: float) -> Vector2:
	return _sample_data(stream.data, stream.mix_rate, stream.stereo, time)

static func _sample_data(data: PackedByteArray, rate: int, stereo: bool, time: float) -> Vector2:
	var position := time * rate
	var frame := int(position)
	var channels := 2 if stereo else 1
	var count := data.size() / (2 * channels)
	if frame < 0 or frame >= count: return Vector2.ZERO
	var a := Vector2(data.decode_s16(frame * channels * 2), data.decode_s16((frame * channels + channels - 1) * 2))
	var next := mini(frame + 1, count - 1)
	var b := Vector2(data.decode_s16(next * channels * 2), data.decode_s16((next * channels + channels - 1) * 2))
	return a.lerp(b, position - frame) / 32768.0

func _cleanup() -> void:
	recording = false
	if effect != null: effect.set_recording_active(false)
	if system_capture != null:
		system_capture.cleanup()
		system_capture.queue_free()
		system_capture = null
	if is_instance_valid(player):
		player.stop()
		player.queue_free()
	player = null
	var bus := AudioServer.get_bus_index(bus_name)
	if bus > 0: AudioServer.remove_bus(bus)
	bus_name = ""
	effect = null
	capture = null

func _exit_tree() -> void:
	if effect != null: effect.set_recording_active(false)
	_cleanup()
