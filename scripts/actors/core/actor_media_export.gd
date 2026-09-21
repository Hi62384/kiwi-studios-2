class_name ActorMediaExport
extends RefCounted
static func write_async(owner: Node, value: Variant, path: String, property: ActorProperty) -> bool:
	var worker := Thread.new()
	if worker.start(write.bind(value, path, property)) != OK: return false
	while worker.is_alive(): await owner.get_tree().process_frame
	return bool(worker.wait_to_finish())

## Real encoding, never a byte-copy with a misleading extension.
static func formats(property: ActorProperty, value: Variant) -> PackedStringArray:
	var extensions := PackedStringArray(property.options.get("extensions", []))
	if extensions.has("mp4"): return PackedStringArray(["mp4", "mov", "mkv", "webm"])
	if extensions.has("mp3") or value is AudioStream: return PackedStringArray(["wav", "mp3", "ogg", "flac"])
	if value is ActorObjectReference or value is ActorObjectData:
		var type: StringName = value.object_type if value is ActorObjectReference else value.type_id
		if type in [&"image", &"noise_image"]: return PackedStringArray(["tres", "png", "jpg", "webp"])
	if value is Texture2D or value is Image or extensions.has("png"): return PackedStringArray(["png", "jpg", "webp", "tres"])
	return PackedStringArray(["gdshader"] if extensions.has("gdshader") else ["tres"])

static func write(value: Variant, path: String, property: ActorProperty) -> bool:
	if FileAccess.file_exists(path): return false
	var extension := path.get_extension().to_lower()
	# Preserve original media bytes when no conversion is requested.
	if value is String and value.get_extension().to_lower() == extension:
		return DirAccess.copy_absolute(ProjectSettings.globalize_path(value), ProjectSettings.globalize_path(path)) == OK
	var resource: Resource = value if value is Resource else null
	if value is ActorObjectReference: resource = ActorAnimation.resolve_reference(value)
	if resource is ActorObjectData and resource.type_id == &"image":
		var original: Variant = resource.get_value(&"source", "")
		if original is String and original.get_extension().to_lower() == extension:
			return DirAccess.copy_absolute(ProjectSettings.globalize_path(original), ProjectSettings.globalize_path(path)) == OK
	if value is AudioStreamWAV and extension == "wav": return value.save_to_wav(ProjectSettings.globalize_path(path)) == OK
	if extension in ["tres", "res"] and resource != null: return ResourceSaver.save(resource, path) == OK
	var image: Image
	if resource is ActorObjectData and resource.type_id in [&"image", &"noise_image"]:
		image = ActorImageGenerator.image_for_object(resource)
	elif value is Texture2D: image = value.get_image()
	elif value is Image: image = value
	elif value is String and PackedStringArray(property.options.get("extensions", [])).has("png"):
		image = Image.load_from_file(value)
	if image != null:
		match extension:
			"png": return image.save_png(path) == OK
			"jpg", "jpeg": return image.save_jpg(path, 0.95) == OK
			"webp": return image.save_webp(path) == OK
			"tres": return ResourceSaver.save(ImageTexture.create_from_image(image), path) == OK
	var source := str(value) if value is String else ""
	var temporary := ""
	if value is AudioStream:
		temporary = ProjectSettings.globalize_path("user://export_" + ActorData.new_id() + ".wav")
		var wav: AudioStreamWAV = value as AudioStreamWAV
		if wav == null:
			var playback: AudioStreamPlayback = value.instantiate_playback()
			playback.start()
			var bytes := PackedByteArray()
			var frames := int(value.get_length() * 48000)
			bytes.resize(frames * 4)
			var cursor := 0
			while cursor < frames:
				var samples := playback.mix_audio(AudioServer.get_mix_rate() / 48000.0, mini(4096, frames - cursor))
				if samples.is_empty(): break
				for sample in samples:
					bytes.encode_s16(cursor * 4, clampi(int(sample.x * 32767), -32768, 32767))
					bytes.encode_s16(cursor * 4 + 2, clampi(int(sample.y * 32767), -32768, 32767))
					cursor += 1
			playback.stop()
			wav = AudioStreamWAV.new()
			wav.format = AudioStreamWAV.FORMAT_16_BITS
			wav.mix_rate = 48000
			wav.stereo = true
			wav.data = bytes
		if wav.save_to_wav(temporary) != OK: return false
		source = temporary
	if source.is_empty() or not FileAccess.file_exists(source): return false
	var encoder := ActorVideo.executable("ffmpeg")
	if encoder.is_empty():
		if not temporary.is_empty(): DirAccess.remove_absolute(temporary)
		return false
	var arguments := PackedStringArray(["-nostdin", "-v", "error", "-n", "-i", ProjectSettings.globalize_path(source)])
	if PackedStringArray(property.options.get("extensions", [])).has("mp4"):
		# Compatible containers can reuse the encoded streams without rendering.
		if source.get_extension().to_lower() in ["mp4", "m4v", "mov"] and extension in ["mp4", "mov", "mkv"]:
			var remux := arguments.duplicate()
			remux.append_array(PackedStringArray(["-map", "0:v:0", "-map", "0:a?", "-c", "copy", ProjectSettings.globalize_path(path)]))
			var log: Array = []
			if OS.execute(encoder, remux, log, true) == 0: return true
			# Remove only the newly created failed output before the codec fallback.
			if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		arguments.append_array(PackedStringArray(["-c:v", "libvpx-vp9", "-deadline", "realtime", "-cpu-used", "6", "-c:a", "libopus"] if extension == "webm" else ["-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p", "-c:a", "aac"]))
	else:
		arguments.append("-vn")
		arguments.append_array(PackedStringArray(["-c:a", {"wav": "pcm_s16le", "mp3": "libmp3lame", "ogg": "libvorbis", "flac": "flac"}.get(extension, "pcm_s16le")]))
	arguments.append(ProjectSettings.globalize_path(path))
	var output: Array = []
	var success := OS.execute(encoder, arguments, output, true) == 0
	if not temporary.is_empty(): DirAccess.remove_absolute(temporary)
	if not success: push_warning("Media export failed: " + "".join(output))
	return success
