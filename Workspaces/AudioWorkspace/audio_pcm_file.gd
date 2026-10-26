class_name KiwiAudioPCMFile
extends RefCounted
## Seekable RIFF PCM reader: metadata and small frame windows, never whole PCM.
const MAX_HEADER := 1024 * 1024
const MAX_CHUNKS := 128
const MAX_READ_FRAMES := 16384

static func inspect(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"error": "Could not open PCM source."}
	var size := file.get_length()
	var head := file.get_buffer(12)
	if head.size() != 12 or head.slice(0, 4).get_string_from_ascii() != "RIFF" or head.slice(8, 12).get_string_from_ascii() != "WAVE":
		file.close(); return {"error": "File preview supports RIFF PCM WAV; RF64 and compressed WAV require conversion or a shorter render range."}
	var info: Dictionary = {}
	var cursor := 12
	for chunk in MAX_CHUNKS:
		if cursor + 8 > size or cursor + 8 > MAX_HEADER: break
		file.seek(cursor)
		var header := file.get_buffer(8)
		if header.size() != 8: break
		var tag := header.slice(0, 4).get_string_from_ascii()
		var bytes := int(header.decode_u32(4))
		var start := cursor + 8
		if bytes > size - start: break
		if tag == "fmt " and bytes >= 16:
			var fmt := file.get_buffer(mini(bytes, 40))
			if fmt.size() < 16: break
			var format := int(fmt.decode_u16(0)); var channels := int(fmt.decode_u16(2))
			var rate := int(fmt.decode_u32(4)); var align := int(fmt.decode_u16(12)); var bits := int(fmt.decode_u16(14))
			if format == 0xfffe:
				if fmt.size() < 40 or int(fmt.decode_u16(16)) < 22 or int(fmt.decode_u16(18)) != bits: break
				if fmt.slice(28, 40) != PackedByteArray([0, 0, 16, 0, 128, 0, 0, 170, 0, 56, 155, 113]): break
				format = int(fmt.decode_u32(24))
			if channels not in [1, 2] or rate < 8000 or rate > 192000 or align != channels * (bits / 8): break
			if not (format == 1 and bits in [8, 16, 24, 32]) and not (format == 3 and bits == 32): break
			if int(fmt.decode_u32(8)) != rate * align: break
			info = {"format": format, "channels": channels, "rate": rate, "bits": bits, "align": align}
		elif tag == "data" and not info.is_empty() and bytes > 0 and bytes % int(info.align) == 0:
			info.data_offset = start; info.data_bytes = bytes; info.frames = bytes / int(info.align)
			info.duration = float(info.frames) / int(info.rate); info.error = ""
			info.file_bytes = size; info.modified = FileAccess.get_modified_time(path)
			file.close(); return info
		cursor = start + bytes + (bytes % 2)
	file.close()
	return {"error": "Unsupported/truncated WAV or metadata exceeds the 1 MiB/128-chunk header bound. Use PCM mono/stereo or a shorter converted source."}

static func read_frames(file: FileAccess, info: Dictionary, first: int, count: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	if file == null or first < 0 or count <= 0 or not str(info.get("error", "invalid")).is_empty(): return result
	count = mini(MAX_READ_FRAMES, mini(count, maxi(0, int(info.frames) - first)))
	if count == 0: return result
	file.seek(int(info.data_offset) + first * int(info.align))
	var bytes := file.get_buffer(count * int(info.align))
	count = mini(count, bytes.size() / int(info.align))
	result.resize(count)
	var width := int(info.bits) / 8
	for frame in count:
		var at := frame * int(info.align)
		var left := _sample(bytes, at, int(info.bits), int(info.format))
		var right := _sample(bytes, at + width, int(info.bits), int(info.format)) if int(info.channels) == 2 else left
		result[frame] = Vector2(left, right)
	return result

static func _sample(bytes: PackedByteArray, at: int, bits: int, format: int) -> float:
	var value := 0.0
	if format == 3: value = bytes.decode_float(at)
	elif bits == 8: value = (int(bytes[at]) - 128) / 128.0
	elif bits == 16: value = bytes.decode_s16(at) / 32768.0
	elif bits == 24:
		var signed := int(bytes[at]) | (int(bytes[at + 1]) << 8) | (int(bytes[at + 2]) << 16)
		if (signed & 0x800000) != 0: signed -= 0x1000000
		value = signed / 8388608.0
	else: value = bytes.decode_s32(at) / 2147483648.0
	return value if is_finite(value) else 0.0
