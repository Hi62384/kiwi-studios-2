extends SceneTree
var failures := 0
var display_offset := Vector2(24, 24)
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: run.call_deferred()
func mouse(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point + display_offset
	event.global_position = point + display_offset
	event.pressed = pressed
	root.push_input(event, true)
func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point + display_offset
	event.global_position = point + display_offset
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)
func run() -> void:
	var editor := ActorTimelineEditor.new()
	root.add_child(editor)
	editor.hide()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	root.add_child(viewport)
	editor.runtime_holder = Node3D.new()
	viewport.add_child(editor.runtime_holder)
	var display := TextureRect.new()
	display.position = display_offset
	display.size = Vector2(960, 540)
	display.texture = viewport.get_texture()
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	root.add_child(display)
	var covering_button := Button.new()
	display.add_child(covering_button)
	covering_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gizmo := ActorUIGizmo.new()
	gizmo.editor = editor
	gizmo.display = display
	display.add_child(gizmo)
	var clip := editor.model.create_actor(editor.registry.get_definition(&"basic_shape_2d"), 0)
	var actor := editor.model.selected_actor()
	await process_frame
	mouse(Vector2(480, 270), true)
	motion(Vector2(520, 290))
	mouse(Vector2(520, 290), false)
	check(actor.get_value(&"position").is_equal_approx(Vector2(80, 40)), "Root viewport clicks reach 2D item and map through scaled TextureRect")
	editor.model.undo()
	check(actor.get_value(&"position") == Vector2.ZERO, "Direct viewport movement undoes")
	check(gizmo.get_child_count() == 0, "No move/rotate/scale toolbar")
	var runtime := editor._runtime_for_clip(clip.id) as ActorUIRuntime
	var corner := gizmo.corners(runtime)[2]
	mouse(corner, true)
	motion(corner + Vector2(20, 15))
	mouse(corner + Vector2(20, 15), false)
	check(actor.get_value(&"size").is_equal_approx(Vector2(480, 300)), "Outline knobs resize layout independently of scale")
	check(actor.get_value(&"scale") == Vector2.ONE, "Layout resize preserves scale")
	editor.model.undo()
	var fonts := ActorTextSettings.system_fonts()
	check(not fonts.is_empty(), "Installed font discovery returns actual fonts")
	var inspector := ActorInspector.new()
	root.add_child(inspector)
	inspector.setup(editor.model, editor.registry)
	var font_button := inspector._font_editor(inspector.fields, "Arial", func(_font: String): pass)
	font_button.pressed.emit()
	var font_popup := font_button.get_child(0) as ActorFontPicker
	check(font_popup != null and font_popup.options.get_child_count() == fonts.size(), "Font popup displays discovered font families as preview buttons")
	if font_popup != null and font_popup.options.get_child_count() > 0:
		check((font_popup.options.get_child(0) as Button).has_theme_font_override("font"), "Each font choice previews its own installed typeface")
	editor.model.selected_layer = 1
	var text_clip := editor.model.create_actor(editor.registry.get_definition(&"text_2d"), 0)
	var text_actor := editor.model.selected_actor()
	var text_runtime := editor._runtime_for_clip(text_clip.id) as ActorUIRuntime
	var input := inspector.fields.find_child("text", true, false) as LineEdit
	check(input != null, "Text inspector has an editable text field")
	var version := editor.model.history.get_version()
	input.text = "Live"
	input.text_changed.emit("Live")
	check(text_runtime.label.text == "Live", "Typing previews text in viewport without Enter")
	input.text = "Live now"
	input.text_changed.emit("Live now")
	check(editor.model.history.get_version() == version, "Typing previews do not add history entries")
	input.focus_exited.emit()
	check(editor.model.history.get_version() == version + 1, "Typing session commits one history entry")
	editor.model.undo()
	check(text_actor.get_value(&"text") == "Text", "Undo restores original text")
	check(ActorAnimationTrack.interpolate_text("AB", "ABCDEF", 0.5) == "ABCD", "Text interpolation progressively adds a suffix")
	check(ActorAnimationTrack.interpolate_text("AB", "XYZ", 0.4) == "", "Different text first deletes previous letters")
	check(ActorAnimationTrack.interpolate_text("AB", "XYZ", 0.6) == "X", "Different text then adds replacement letters")
	check(ActorAnimationTrack.interpolate_text("ABCDEF", "AB", 0.5) == "ABCD", "Shorter text progressively deletes its suffix")
	var track := ActorAnimationTrack.new()
	var first := ActorKeyframe.new()
	first.value = "AB"
	first.interpolation = ActorKeyframe.Interpolation.STEP
	var last := ActorKeyframe.new()
	last.value = "ABCDEF"
	last.time = 1
	track.keys = [first, last]
	check(track.sample(0.5) == "ABCD", "Previously stepped text keys also interpolate")
	print("Installed font families: %d" % fonts.size())
	inspector.free()
	editor.free()
	display.free()
	viewport.free()
	await process_frame
	print("Viewport clicks / live text / font / text interpolation checks: %d failures" % failures)
	quit(failures)
