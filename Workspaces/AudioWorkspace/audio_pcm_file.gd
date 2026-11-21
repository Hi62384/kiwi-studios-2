class_name KiwiAudioPCMFile
extends RefCounted
## Seekable RIFF PCM reader: metadata and small frame windows, never whole PCM.
const MAX_HEADER := 1024 * 1024
const MAX_CHUNKS := 128
const MAX_READ_FRAMES := 16384

static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "audio_pcm")
static func inspect(path: String) -> Dictionary: return _native().call("inspect", path)
static func read_frames(file: FileAccess, info: Dictionary, first: int, count: int) -> PackedVector2Array: return _native().call("read_frames", file, info, first, count)
static func _sample(bytes: PackedByteArray, at: int, bits: int, format: int) -> float: return _native().call("sample", bytes, at, bits, format)
