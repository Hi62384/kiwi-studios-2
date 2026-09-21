extends SceneTree
var failures := 0

class TestRecorder:
	extends ActorAudioRecorder
	var output: AudioStreamWAV
	func start() -> String:
		recording = true
		peaks = PackedFloat32Array([0.2, 0.5, 0.7])
		return ""
	func stop() -> AudioStreamWAV:
		recording = false
		return output

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var editor := ActorTimelineEditor.new()
	root.add_child(editor)
	editor.size = Vector2(1000, 300)
	await process_frame
	await process_frame
	var canvas := editor.canvas
	canvas.snap_enabled = false
	canvas.magnet_enabled = true
	canvas.playhead = 6.25
	var paths := PackedStringArray([ProjectSettings.globalize_path("res://resources/Images/ActorIcons/Image3D.svg")])
	var position := Vector2(ActorTimelineCanvas.LABEL_WIDTH + 6.2 * canvas.pixels_per_second, 70)
	check(canvas.preview_assets(position, paths), "A file drag produces a placement ghost")
	check(canvas._asset_previews.size() == 1 and is_equal_approx(canvas._asset_previews[0].start, 6.25), "Placement ghost snaps to the playhead")
	check(editor.model.clips.is_empty() and not editor.model.history.has_undo(), "Placement preview does not create actors or undo entries")
	position.x += 130
	canvas.preview_assets(position, paths)
	check(canvas._asset_previews[0].start > 8.0, "Placement follows the mouse")
	canvas.preview_assets(Vector2(-10, 70), paths)
	check(canvas._asset_previews.is_empty() and editor.model.clips.is_empty(), "Leaving the timeline cancels the visible placement")
	canvas._notification(Control.NOTIFICATION_DRAG_END)
	check(canvas._asset_paths.is_empty(), "Releasing an off-timeline drag clears the preview")
	canvas._drop_data(position, {"paths": paths})
	check(editor.model.clips.size() == 1 and editor.model.selected_actor().type_id == &"image_3d", "Dropping commits the preview as an actor")
	editor.undo()
	check(editor.model.clips.is_empty(), "Committed placement is undoable")
	editor.audio_recorder.free()
	var recorder := TestRecorder.new()
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 44100
	var data := PackedByteArray()
	data.resize(176400)
	wav.data = data
	recorder.output = wav
	editor.add_child(recorder)
	editor.audio_recorder = recorder
	canvas.playhead = 3.4
	editor.toggle_recording()
	check(editor.playing and recorder.recording, "Recording starts video transport")
	check(not canvas.recording_preview.is_empty(), "Recording displays a temporary audio actor")
	editor._process(0.5)
	check(is_equal_approx(canvas.playhead, 3.9) and is_equal_approx(canvas.recording_preview.duration, 0.5), "Recording advances the playhead and grows behind it")
	check(canvas.recording_peaks.size() == 3, "Live recording shows captured waveform peaks")
	check(editor.model.clips.is_empty(), "Live recording remains uncommitted until stop")
	editor.toggle_recording()
	check(not editor.playing and canvas.recording_preview.is_empty(), "Stopping pauses video and clears the temporary clip")
	check(editor.model.clips.size() == 1 and is_equal_approx(editor.model.selected_clip().start_time, 3.4), "Stopping creates the captured clip at its original start")
	editor.undo()
	check(editor.model.clips.is_empty(), "Recording insertion remains undoable")
	editor.redo()
	editor.timing_dialog.popup_centered(Vector2i(380, 108))
	await process_frame
	check(editor.start_input.size.y < 50 and editor.end_input.size.y < 50, "Timing inputs no longer stretch vertically")
	editor.timing_dialog.hide()
	var settings_button := Button.new()
	settings_button.set_script(load("res://scripts/Extra/editor_settings_button.gd"))
	root.add_child(settings_button)
	settings_button.call("open_settings")
	check(settings_button.get("device") is OptionButton and settings_button.get("popup").visible, "Editor opens microphone preferences")
	settings_button.free()
	editor.free()
	await process_frame
	print("Live recording / placement checks: %d failures" % failures)
	quit(failures)
