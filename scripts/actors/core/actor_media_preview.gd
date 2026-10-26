class_name ActorMediaPreview
extends VBoxContainer
var path: String
var video := false
var duration := 0.0
var time := 0.0
var playing := false
var image := TextureRect.new()
var player := AudioStreamPlayer.new()
var seek := HSlider.new()
var transport := Button.new()
var audio_job: Dictionary = {}
var audio_path := ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Image previews never mount the audio/video transport controls.
		for control in [image, player, seek, transport]:
			if is_instance_valid(control) and control.get_parent() == null: control.free()

func _ready() -> void:
	add_child(player)
	image.custom_minimum_size = Vector2(180, 160)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(image)
	var extension := path.get_extension().to_lower()
	if extension in ActorInspector.IMAGE_FILE_EXTENSIONS:
		var bitmap := Image.load_from_file(path)
		if bitmap != null: image.texture = ImageTexture.create_from_image(bitmap)
		return
	video = extension in ActorVideo.EXTENSIONS
	if video:
		var metadata := ActorVideo.info(path)
		duration = float(metadata.get("duration", 0.0))
		if metadata.get("audio", false):
			audio_path = ProjectSettings.globalize_path("user://preview_audio_" + ActorData.new_id() + ".wav")
			audio_job = OS.execute_with_pipe(ActorVideo.executable("ffmpeg"), PackedStringArray(["-nostdin", "-v", "error", "-n", "-i", ProjectSettings.globalize_path(path), "-vn", "-ar", "48000", "-ac", "2", "-c:a", "pcm_s16le", audio_path]), false)
	else:
		image.hide()
		player.stream = ActorAudio.source(path)
		if player.stream != null: duration = player.stream.get_length()
	transport.text = "▶ Preview"
	add_child(transport)
	transport.pressed.connect(func():
		if time >= duration: time = 0
		playing = not playing
		transport.text = "Ⅱ Pause" if playing else "▶ Preview"
		if playing and player.stream != null: player.play(time)
		else: player.stop())
	seek.max_value = duration
	seek.step = 0.01
	add_child(seek)
	seek.value_changed.connect(func(value: float):
		time = value
		if playing and player.stream != null: player.play(time))

func _process(delta: float) -> void:
	if not audio_job.is_empty():
		audio_job.stderr.get_buffer(4096)
		if not OS.is_process_running(audio_job.pid):
			if OS.get_process_exit_code(audio_job.pid) == 0: player.stream = AudioStreamWAV.load_from_file(audio_path)
			audio_job.clear()
			if playing and player.stream != null: player.play(time)
	if playing:
		time = minf(duration, time + delta)
		seek.set_value_no_signal(time)
		if time >= duration:
			playing = false
			player.stop()
			transport.text = "▶ Preview"
	if video:
		var frame := ActorVideo.frame(path, time, true)
		if frame != null: image.texture = frame

func _exit_tree() -> void:
	player.stop()
	if not audio_job.is_empty() and OS.is_process_running(audio_job.pid): OS.kill(audio_job.pid)
	if not audio_path.is_empty(): DirAccess.remove_absolute(audio_path)
