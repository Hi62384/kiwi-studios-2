extends SceneTree

var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var editor := load("res://Workspaces/SceneWorkspace/Timeline.tscn").instantiate() as ActorTimelineEditor
	root.add_child(editor)
	editor.size = Vector2(1000, 280)
	await process_frame
	check(editor.time_label.get_parent() == editor.play_button.get_parent() and editor.time_label.get_index() == editor.play_button.get_index() + 1, "Playhead time is next to playback")
	check(editor.timing_dialog.is_ancestor_of(editor.start_input), "Clip timing belongs to its context dialog, not the toolbar")
	check(editor.keyframes_button.get_parent() != editor.play_button.get_parent(), "Keyframe view switch is outside the tool strip")
	check(ProjectSettings.get_setting("audio/driver/enable_input"), "Microphone input is enabled")
	if DisplayServer.get_name() == "headless":
		var error: String = await editor.audio_recorder.start()
		check(not error.is_empty() and not editor.audio_recorder.recording, "Headless capture fails gracefully")
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	var pcm := PackedByteArray()
	pcm.resize(176400)
	wav.data = pcm
	editor._record_start = 2.0
	var clip := editor._create_recording(wav)
	check(clip != null and is_equal_approx(clip.duration, 2.0) and clip.start_time == 2.0, "Recording insertion creates a source-length audio actor at the capture cursor")
	check(editor.model.selected_actor().values[&"audio"] is AudioStreamWAV, "Recording is embedded and saveable")
	editor.undo()
	check(editor.model.clips.is_empty(), "Recording creation is undoable")
	editor.redo()
	check(editor.model.selected_clip() == clip, "Recording creation is redoable")
	var actor := editor.model.selected_actor()
	var canvas := editor.canvas
	canvas.magnet_enabled = true
	canvas.snap_enabled = false
	canvas.playhead = 8.35
	check(is_equal_approx(canvas.snapped_playhead(4.05), 4.0), "Playhead magnet snaps to an actor edge")
	check(is_equal_approx(canvas.snapped_playhead(4.05, true), 4.05), "Shift bypasses playhead snapping")
	check(is_equal_approx(canvas.magnetic_delta(8.3, [0.0], [clip.id]), 8.35), "Actor magnet snaps to playhead")
	editor.model.playhead_time = 2.5
	editor.model.add_keyframe(actor, PackedStringArray(["volume_db"]), "Volume", -6.0)
	check(is_equal_approx(canvas.snapped_playhead(2.55, false, true), 2.5), "Keyframe playhead snaps to displayed keys")
	canvas.playhead = 8.35
	var key_id := actor.animation_tracks[0].keys[0].id
	check(is_equal_approx(canvas.magnetic_delta(5.8, [2.5], [], [key_id], true), 5.85), "Keyframes snap to the playhead")
	var point := canvas.fade_handle(0, true)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = point
	press.global_position = canvas.global_position + point
	canvas._gui_input(press)
	check(canvas._fade_actor == actor, "Audio fade knob starts a fade gesture")
	var motion := InputEventMouseMotion.new()
	motion.global_position = press.global_position + Vector2(canvas.pixels_per_second, 0)
	canvas._input(motion)
	check(is_equal_approx(float(actor.values[&"fade_in"]), 1.0), "Dragging a fade knob updates its value live")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	canvas._input(release)
	check(is_equal_approx(ActorAudio.fade_gain(actor, clip, 2.5), 0.5), "Fade affects playback gain")
	editor.undo()
	check(actor.values[&"fade_in"] == 0.0, "Fade gesture is undoable")
	editor.redo()
	check(actor.values[&"fade_in"] == 1.0, "Fade gesture is redoable")
	var fixture_root := "res://scripts/actors/tests/fixtures/"
	var environment_path := fixture_root + "_media_tools_environment.tres"
	var mesh_path := fixture_root + "_media_tools_mesh.tres"
	var native_path := fixture_root + "_media_tools_native_environment.tres"
	var audio_path := fixture_root + "_media_tools_audio.wav"
	for path in [environment_path, mesh_path, native_path, audio_path]: assert(not FileAccess.file_exists(path))
	check(wav.save_to_wav(audio_path) == OK, "Audio fixture saves")
	var environment := editor.registry.get_object_definition(&"environment").create_object()
	environment.values[&"background_mode"] = 2
	check(ResourceSaver.save(environment, environment_path) == OK, "Environment fixture saves")
	check(ResourceSaver.save(BoxMesh.new(), mesh_path) == OK, "Mesh fixture saves")
	var native := Environment.new()
	native.ambient_light_energy = 2.5
	native.background_color = Color.RED
	check(ResourceSaver.save(native, native_path) == OK, "Native environment fixture saves")
	var image_path := "res://resources/Images/ActorIcons/Image3D.svg"
	check(ActorFileImport.type_for_path(ProjectSettings.globalize_path(image_path)) == &"image_3d", "Image files map to image actors")
	check(ActorFileImport.type_for_path(ProjectSettings.globalize_path(mesh_path)) == &"basic_mesh", "Primitive mesh resource files map to mesh actors")
	check(ActorFileImport.type_for_path(ProjectSettings.globalize_path(environment_path)) == &"world_environment", "Environment object files map to environment actors")
	check(ActorFileImport.type_for_path(ProjectSettings.globalize_path(native_path)) == &"world_environment", "Native environment files map to environment actors")
	check(ActorFileImport.type_for_path(ProjectSettings.globalize_path(audio_path)) == &"audio", "Audio files map to audio actors")
	var imported := ActorFileImport.environment_from_native(native, editor.registry)
	check(imported.values[&"ambient_energy"] == 2.5 and imported.values[&"background_color"] == Color.RED, "Native environment conversion preserves settings")
	var runtime: Node = load("res://scripts/actors/examples/basic_actor.tscn").instantiate()
	var preview := Environment.new()
	runtime.call("_configure_environment", preview, environment)
	check(preview.background_mode == Environment.BG_SKY and preview.sky.sky_material is ProceduralSkyMaterial, "Environment thumbnails use the same configuration as actors")
	runtime.free()
	var before := editor.model.clips.size()
	var payload := {"type": "project_files", "paths": PackedStringArray([ProjectSettings.globalize_path(environment_path)])}
	check(canvas._can_drop_data(Vector2(300, 70), payload), "Timeline accepts project environment drags")
	canvas._drop_data(Vector2(300, 70), payload)
	check(editor.model.clips.size() == before + 1 and editor.model.selected_actor().type_id == &"world_environment", "Environment drop creates an actor")
	editor.undo()
	check(editor.model.clips.size() == before, "File drop creation is undoable")
	editor._create_dropped_actors(PackedStringArray([ProjectSettings.globalize_path(image_path)]), 10.0, 1)
	check(editor.model.selected_actor().type_id == &"image_3d", "Image drop creates an image actor")
	editor._create_dropped_actors(PackedStringArray([ProjectSettings.globalize_path(mesh_path)]), 10.0, 2)
	check(editor.model.selected_actor().type_id == &"basic_mesh", "Mesh drop creates a mesh actor")
	editor._create_dropped_actors(PackedStringArray([ProjectSettings.globalize_path(audio_path)]), 10.0, 3)
	check(editor.model.selected_actor().type_id == &"audio" and editor.model.selected_clip().duration == 2.0, "Audio file drop creates a source-length audio actor")
	editor._show_context_menu(Vector2(30, 30), true, 10.0, 2)
	check(editor.context_menu.get_item_index(ActorTimelineEditor.MENU_TIMING) >= 0, "Actor menu offers start/end editing")
	editor.context_menu.hide()
	editor.free()
	await process_frame
	for path in [environment_path, mesh_path, native_path, audio_path]: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Timeline media tools checks: %d failures" % failures)
	quit(failures)
