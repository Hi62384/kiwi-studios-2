extends SceneTree
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void: run.call_deferred()

class FakeAudio:
	extends ActorAudioRecorder
	var output: AudioStreamWAV
	func stop() -> AudioStreamWAV:
		recording = false
		return output

func run() -> void:
	var editor := ActorTimelineEditor.new()
	root.add_child(editor)
	check(editor.screen_button.get_parent() == editor.mic_button.get_parent() and editor.screen_button.get_index() == editor.mic_button.get_index() + 1, "Screen recorder sits beside microphone control")
	editor.screen_button.call("open_settings")
	var popup: PopupPanel = editor.screen_button.get("popup")
	check(popup.find_child("CaptureTarget", true, false) != null, "Screen capture options expose targets")
	check(popup.find_child("RecordMicrophone", true, false) != null and popup.find_child("RecordSystemAudio", true, false) != null, "Screen recorder exposes independent audio source checkboxes")
	var property := editor.registry.get_definition(&"audio").find_property(&"audio")
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 48000
	var bytes := PackedByteArray()
	bytes.resize(48000 * 2 * 2)
	for frame in 96000: bytes.encode_s16(frame * 2, int(sin(frame * 0.05) * 12000))
	stream.data = bytes
	var unique := ActorData.new_id()
	var paths: Array[String] = []
	for format in ["wav", "mp3", "ogg", "flac"]:
		var path: String = "user://media_export_" + unique + "." + format
		check(ActorMediaExport.write(stream, path, property), "Audio export encodes " + format)
		check(ActorAudio.source(path) != null, "Exported audio can be loaded again: " + format)
		paths.append(path)
	var image := Image.create(8, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.CORNFLOWER_BLUE)
	var image_property := ActorProperty.create(&"image", "Image", "")
	image_property.options.extensions = ["png", "jpg", "webp"]
	for format in ["png", "jpg", "webp", "tres"]:
		var path: String = "user://media_image_" + unique + "." + format
		check(ActorMediaExport.write(ImageTexture.create_from_image(image), path, image_property), "Image export encodes " + format)
		paths.append(path)
	var save := ActorProjectResourceSaveDialog.new()
	root.add_child(save)
	save._build("Save Audio", "Audio", "wav", true, PackedStringArray(["wav", "mp3", "ogg"]))
	check(save.format_picker.item_count == 3, "Save browser provides format choices")
	save.format_picker.select(1)
	save.format_picker.item_selected.emit(1)
	check(save._target_path().ends_with(".mp3"), "Chosen format controls output filename")
	save.free()
	var row: Node = load("res://CustomNodes/ExpandableButton/ExpandableButton.tscn").instantiate()
	root.add_child(row)
	row.icon = ImageTexture.create_from_image(Image.create(1000, 10, false, Image.FORMAT_RGB8))
	row.text = "A very long filename that must not overflow its filesystem row " + "extra".repeat(20)
	check(row.get_node("Panel/HBoxContainer/MainIcon").expand_mode == TextureRect.EXPAND_IGNORE_SIZE, "Thumbnail dimensions cannot resize filesystem icons")
	check(row.get_node("Panel/HBoxContainer/Text").clip_text, "Long filesystem labels are clipped")
	row.expanded = true
	row.expanded = false
	check(not row.get_node("HBoxContainer/ChildrenContainer").visible, "Folder row collapse updates consistently")
	row.free()
	var screen := ActorScreenRecorder.new()
	root.add_child(screen)
	var target_args := ActorScreenRecorder.capture_arguments({"input": "desktop", "position": Vector2i(-1920, 0), "size": Vector2i(1920, 1080)}, 30, true)
	check(target_args.has("-1920") and target_args.has("1920x1080"), "Display capture preserves monitor offsets")
	# Exercise real FFmpeg finalization using synthetic input, never desktop/mic capture.
	screen.directory = ProjectSettings.globalize_path("user://screen_test_" + unique)
	DirAccess.make_dir_recursive_absolute(screen.directory)
	screen.output_path = screen.directory.path_join("capture.mp4")
	screen.process = OS.execute_with_pipe(ActorVideo.executable("ffmpeg"), PackedStringArray(["-v", "error", "-re", "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=24", "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-movflags", "+frag_keyframe+empty_moov", screen.output_path]), false)
	var deadline := Time.get_ticks_msec() + 8000
	while not FileAccess.file_exists(screen.output_path) and Time.get_ticks_msec() < deadline: await process_frame
	await create_timer(0.5).timeout
	var fake := FakeAudio.new()
	fake.output = stream
	screen.add_child(fake)
	screen.audio_recorder = fake
	screen.recording = true
	var path: String = await screen.stop()
	check(not path.is_empty() and ActorVideo.info(path).get("audio", false), "Screen finalization produces MP4 with selected audio")
	var video_property := editor.registry.get_definition(&"video").find_property(&"video")
	var export_path := "user://screen_export_" + unique + ".webm"
	check(ActorMediaExport.write(path, export_path, video_property), "Video Save As transcodes containers/codecs")
	paths.append(export_path)
	var recording_directory := screen.directory
	screen.free()
	for name in ["capture.mp4", "recording.mp4"]: DirAccess.remove_absolute(recording_directory.path_join(name))
	DirAccess.remove_absolute(recording_directory)
	for path_to_remove in paths: DirAccess.remove_absolute(ProjectSettings.globalize_path(path_to_remove))
	editor.free()
	await process_frame
	print("Media Save As and screen recording checks: %d failures" % failures)
	quit(failures)
