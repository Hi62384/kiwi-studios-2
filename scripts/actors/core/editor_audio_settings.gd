class_name EditorAudioSettings
extends RefCounted
const PATH := "user://editor_audio_settings.cfg"

static func read() -> Dictionary:
	var config := ConfigFile.new()
	config.load(PATH)
	return {"record_mic": bool(config.get_value("microphone", "record_mic", true)),
		"record_system": bool(config.get_value("microphone", "record_system", false)),
		"record_timeline": bool(config.get_value("microphone", "record_timeline", false)),
		"device": str(config.get_value("microphone", "device", "Default")),
		"gain_db": float(config.get_value("microphone", "gain_db", 0.0)),
		"mono": bool(config.get_value("microphone", "mono", false))}

static func write(values: Dictionary) -> void:
	var config := ConfigFile.new()
	for key in values: config.set_value("microphone", key, values[key])
	config.save(PATH)
