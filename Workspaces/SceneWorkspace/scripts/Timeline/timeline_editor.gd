class_name ActorTimelineEditor
extends VBoxContainer

const MENU_HEADER := 100
const MENU_DUPLICATE := 101
const MENU_COPY := 102
const MENU_PASTE := 103
const MENU_PARENT := 104
const MENU_UNPARENT := 105
const MENU_DELETE := 106
const MENU_DELETE_SECTION := 107
const MENU_FOCUS_ACTOR := 108
const MENU_TIMING := 109

var model := ActorTimeline.new()
var registry := ActorRegistry.new()
var canvas: ActorTimelineCanvas
var add_button: Button
var actor_picker: ActorPicker
var undo_button: Button
var redo_button: Button
var context_menu: PopupMenu
var start_input: DragNumber
var end_input: DragNumber
var x_zoom: HSlider
var y_zoom: HSlider
var time_label: Label
var h_scroll: HScrollBar
var v_scroll: VScrollBar
var _definitions: Array[ActorDefinition] = []
var inspector: ActorInspector
var hints := InteractionHints.new()
var hint_label: Label
var runtime_holder: Node3D
var _runtimes: Dictionary = {}
var physics := KiwiTimelinePhysics.new()
var _particle_seek_states: Dictionary = {}
var viewport_gizmo: ActorUIGizmo
var inspector_ui_state := ActorInspectorState.new()
var _ui_save_revision: int = 0
var _displayed_section_id: String = ""
var _displayed_focus_id: String = ""
var breadcrumb_row: HBoxContainer
var _breadcrumb_signature: String = ""
var _timeline_section_states: Dictionary = {}
var snap_button: CheckButton
var keyframe_editor: ActorKeyframeEditor
var keyframes_button: Button
var keyframe_view: Control
var breadcrumb_panel: PanelContainer
var actor_view: HBoxContainer
var property_overlay: ActorKeyframeCanvas
var play_button: Button
var magnet_button: Button
var split_button: Button
var playing := false
var exporting := false
var _video_duration_override := -1.0
var video_duration: float:
	get:
		if _video_duration_override > 0.0: return _video_duration_override
		var end := 0.0
		for clip in model.clips:
			end = maxf(end, clip.start_time + clip.duration)
		return end if end > 0.0 else 10.0


func video_duration_is_custom() -> bool:
	return _video_duration_override > 0.0


func set_video_duration(value: float) -> void:
	var next := maxf(0.01, value)
	if is_equal_approx(_video_duration_override, next): return
	var previous := _video_duration_override
	model.history.create_action("Set Video Duration")
	model.history.add_do_method(_apply_video_duration.bind(next))
	model.history.add_undo_method(_apply_video_duration.bind(previous))
	model.history.commit_action()


func reset_video_duration() -> void:
	if not video_duration_is_custom(): return
	var previous := _video_duration_override
	model.history.create_action("Reset Video Duration")
	model.history.add_do_method(_apply_video_duration.bind(-1.0))
	model.history.add_undo_method(_apply_video_duration.bind(previous))
	model.history.commit_action()


func _apply_video_duration(value: float) -> void:
	_video_duration_override = value
	model.changed.emit()
var audio_system: ActorAudioSystem
var audio_recorder: ActorAudioRecorder
var mic_button: Button
var mic_options_button: Button
var screen_button: Button
var screen_recorder: ActorScreenRecorder
var _record_start := 0.0
var _record_elapsed := 0.0
var _record_layer := 0
var _record_busy := false
var _recording_viewport: SubViewport
var _saved_viewport_update := 0
var _saved_scene_process := 0
var timing_dialog: AcceptDialog
var _actor_clipboard: Array[Dictionary] = []
var _context_time: float = 0.0
var _context_layer: int = 0
var _context_on_actor: bool = false
var _context_section_id: String = ""
var _timing_drag_original: Dictionary = {}
var _timing_drag_kind: String = ""


func _exit_tree() -> void:
	physics.dispose()
	_flush_ui_state_save()
	_pause_recording_scene(false)
	if is_instance_valid(viewport_gizmo): viewport_gizmo.queue_free()
	# Undo callables retain the model; release their references when closing the UI.
	if is_instance_valid(model.history):
		model.history.clear_history()
		model.history.free()
	if is_instance_valid(runtime_holder):
		runtime_holder.queue_free()
	_runtimes.clear()
	_particle_seek_states.clear()


func _ready() -> void:
	audio_system = ActorAudioSystem.new()
	add_child(audio_system)
	audio_recorder = ActorAudioRecorder.new()
	add_child(audio_recorder)
	screen_recorder = ActorScreenRecorder.new()
	add_child(screen_recorder)
	add_to_group("actor_timeline_editors")
	_apply_theme()
	BasicActors.register_all(registry)
	_definitions = registry.get_definitions()
	var toolbar_panel := PanelContainer.new()
	toolbar_panel.add_theme_stylebox_override("panel", _box(Color("202a37"), Color("34465a")))
	add_child(toolbar_panel)
	var toolbar_scroll := ScrollContainer.new()
	toolbar_scroll.custom_minimum_size.y = 26
	toolbar_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	toolbar_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	toolbar_scroll.tooltip_text = "Scroll to reach more timeline controls"
	toolbar_scroll.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			toolbar_scroll.scroll_horizontal += -80 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 80
			toolbar_scroll.accept_event())
	toolbar_panel.add_child(toolbar_scroll)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("h_separation", 8)
	toolbar.add_theme_constant_override("v_separation", 6)
	toolbar_scroll.add_child(toolbar)
	add_button = Button.new()
	add_button.text = "+  Add actor"
	add_button.add_theme_stylebox_override("normal", _box(Color("286c62"), Color("4ca58e")))
	add_button.tooltip_text = "Create an actor at the timeline cursor"
	toolbar.add_child(add_button)
	actor_picker = ActorPicker.new()
	actor_picker.theme = theme
	actor_picker.add_theme_stylebox_override("panel", _box(Color("192330"), Color("4b6d80")))
	add_child(actor_picker)
	actor_picker.setup(_definitions)
	actor_picker.actor_chosen.connect(create_actor)
	add_button.pressed.connect(func(): actor_picker.open(model.selected_layer, canvas.playhead))
	actor_picker.about_to_popup.connect(func(): hints.begin(actor_picker, "Enter adds first match • Esc closes picker"))
	actor_picker.popup_hide.connect(func(): hints.end(actor_picker))
	undo_button = _button(toolbar, "Undo", undo)
	redo_button = _button(toolbar, "Redo", redo)
	play_button = _button(toolbar, "▶", toggle_playback)
	play_button.tooltip_text = "Play / pause (Space when focused on the timeline or scene tree)"
	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 12)
	toolbar.add_child(time_label)
	mic_button = _button(toolbar, "", toggle_recording)
	mic_button.icon = _toolbar_icon("mic")
	mic_button.custom_minimum_size.x = 62
	mic_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := mic_button.get_theme_stylebox(state).duplicate() as StyleBox
		style.content_margin_right = 30
		mic_button.add_theme_stylebox_override(state, style)
	mic_button.tooltip_text = "Record selected audio sources (R); use ▾ for recording options"
	mic_options_button = Button.new()
	mic_options_button.set_script(load("res://scripts/Extra/editor_settings_button.gd"))
	mic_options_button.text = "▾"
	mic_options_button.flat = true
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := mic_button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		style.content_margin_left = 3
		style.content_margin_right = 3
		style.set_border_width_all(0)
		style.corner_radius_top_left = 0
		style.corner_radius_bottom_left = 0
		mic_options_button.add_theme_stylebox_override(state, style)
	mic_options_button.mouse_filter = Control.MOUSE_FILTER_STOP
	mic_options_button.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	mic_options_button.offset_left = -26
	mic_options_button.offset_right = -1
	mic_options_button.offset_top = 1
	mic_options_button.offset_bottom = -1
	mic_options_button.tooltip_text = "Recording sources and microphone options"
	mic_button.add_child(mic_options_button)
	var divider := VSeparator.new()
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	divider.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	divider.offset_left = -28
	divider.offset_right = -26
	divider.offset_top = 5
	divider.offset_bottom = -5
	mic_button.add_child(divider)
	screen_button = Button.new()
	screen_button.set_script(load("res://scripts/Extra/screen_record_options.gd"))
	screen_button.text = "▾"
	screen_button.icon = _toolbar_icon("screen")
	screen_button.tooltip_text = "Screen recording: choose a display or window and audio sources"
	screen_button.set("is_recording", func(): return screen_recorder.recording)
	screen_button.set("stop_recording", _stop_screen_recording)
	screen_button.connect("recording_requested", _start_screen_recording)
	toolbar.add_child(screen_button)
	keyframes_button = Button.new()
	keyframes_button.text = "◇  Keyframes"
	keyframes_button.icon = _toolbar_icon("keys")
	keyframes_button.text = "Keyframes"
	keyframes_button.toggle_mode = true
	keyframes_button.tooltip_text = "Switch this timeline area between actors and keyframes without resizing it"
	keyframes_button.toggled.connect(set_keyframe_view)
	timing_dialog = AcceptDialog.new()
	timing_dialog.title = "Actor Clip Timing"
	add_child(timing_dialog)
	var timing_content := VBoxContainer.new()
	timing_dialog.add_child(timing_content)
	var timing_panel := PanelContainer.new()
	timing_panel.add_theme_stylebox_override("panel", _box(Color("18232f"), Color("3b5368")))
	timing_content.add_child(timing_panel)
	timing_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var timing_row := HBoxContainer.new()
	timing_row.add_theme_constant_override("separation", 6)
	timing_panel.add_child(timing_row)
	start_input = _timing_input(timing_row, "START")
	end_input = _timing_input(timing_row, "END")
	_connect_timing_input(start_input, "start")
	_connect_timing_input(end_input, "end")
	var snap := CheckButton.new()
	snap_button = snap
	snap.text = "Snap"
	snap.icon = _toolbar_icon("grid")
	snap.button_pressed = true
	snap.tooltip_text = "Snap to 0.1 seconds. Hold Shift while dragging for free movement."
	toolbar.add_child(snap)
	snap.toggled.connect(func(enabled: bool): canvas.snap_enabled = enabled)
	magnet_button = Button.new()
	magnet_button.text = "Magnet"
	magnet_button.toggle_mode = true
	magnet_button.tooltip_text = "Magnetic snap to visible actor edges and displayed keys; Shift bypasses snapping"
	toolbar.add_child(magnet_button)
	magnet_button.toggled.connect(func(enabled: bool): canvas.magnet_enabled = enabled)
	split_button = Button.new()
	split_button.toggle_mode = true
	split_button.tooltip_text = "Split tool (B). Click an actor to cut at that time; V returns to selection."
	split_button.icon = _toolbar_icon("split")
	toolbar.add_child(split_button)
	split_button.toggled.connect(func(enabled: bool):
		canvas.cancel_drag()
		canvas.split_tool = enabled)
	undo_button.icon = _toolbar_icon("undo")
	redo_button.icon = _toolbar_icon("redo")
	magnet_button.icon = _toolbar_icon("magnet")
	magnet_button.text = ""
	undo_button.tooltip_text = "Undo (Ctrl+Z)"
	redo_button.tooltip_text = "Redo (Ctrl+Shift+Z / Ctrl+Y)"
	undo_button.text = ""
	redo_button.text = ""
	add_button.icon = _toolbar_icon("add")
	add_button.text = "Add actor"
	var zoom_panel := PanelContainer.new()
	zoom_panel.add_theme_stylebox_override("panel", _box(Color("18232f"), Color("3b5368")))
	toolbar.add_child(zoom_panel)
	var zoom_row := HBoxContainer.new()
	zoom_row.add_theme_constant_override("separation", 6)
	zoom_panel.add_child(zoom_row)
	x_zoom = _zoom_slider(zoom_row, "X", 15.0, 160.0, 65.0, "Horizontal timeline scale")
	y_zoom = _zoom_slider(zoom_row, "Y", 12.0, 180.0, ActorTimelineCanvas.ROW, "Layer height scale")
	x_zoom.value_changed.connect(func(value: float):
		canvas.cancel_drag()
		canvas.pixels_per_second = value
		_refresh())
	y_zoom.value_changed.connect(func(value: float):
		canvas.cancel_drag()
		canvas.row_height = value
		keyframe_editor.refresh()
		_refresh())
	breadcrumb_panel = PanelContainer.new()
	breadcrumb_panel.add_theme_stylebox_override("panel", _box(Color("18232f"), Color("34465a")))
	add_child(breadcrumb_panel)
	var breadcrumb_scroll := ScrollContainer.new()
	breadcrumb_scroll.custom_minimum_size.y = 20
	breadcrumb_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	breadcrumb_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	breadcrumb_panel.add_child(breadcrumb_scroll)
	breadcrumb_row = HBoxContainer.new()
	breadcrumb_row.add_theme_constant_override("separation", 4)
	breadcrumb_scroll.add_child(breadcrumb_row)
	# A plain Control isolates both views' minimum sizes from the outer splitter.
	# Tracks and details scroll inside the existing timeline allocation.
	var body := Control.new()
	body.custom_minimum_size = Vector2(280, 40)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)
	actor_view = HBoxContainer.new()
	body.add_child(actor_view)
	actor_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas = ActorTimelineCanvas.new()
	canvas.name = "TimelineCanvas"
	canvas.model = model
	canvas.registry = registry
	canvas.assets_dropped.connect(_create_dropped_actors)
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	actor_view.add_child(canvas)
	var overlay := ActorKeyframeCanvas.new()
	property_overlay = overlay
	overlay.model = model
	overlay.timeline = canvas
	overlay.overlay_mode = true
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(overlay)
	overlay.name = "PropertyKeyframeOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	model.changed.connect(func():
		if overlay.actor != model.actor_for_id(model.overlay_actor_id) or overlay.overlay_path != model.overlay_path:
			overlay.cancel_drag()
			overlay.selected_keys.clear()
			overlay.overlay_path = model.overlay_path.duplicate()
		overlay.actor = model.actor_for_id(model.overlay_actor_id)
		overlay.queue_redraw())
	overlay.move_requested.connect(func(ids: Array[String], delta: float):
		keyframe_editor._actor = overlay.actor
		keyframe_editor._move_keys(ids, delta))
	overlay.move_preview_requested.connect(func(ids: Array[String], delta: float):
		var plan := keyframe_editor._key_move_plan(ids, delta, keyframe_editor._before)
		if plan.valid: model.restore_animation(overlay.actor, plan.tracks))
	overlay.interaction_changed.connect(func(text: String):
		if not text.is_empty():
			keyframe_editor._actor = overlay.actor
			keyframe_editor._begin_edit()
			hints.begin(overlay, text)
		else:
			if keyframe_editor._editing: keyframe_editor._cancel_edit()
			hints.end(overlay))
	overlay.delete_requested.connect(func(ids: Array[String]): model.delete_keyframes(overlay.actor, ids))
	overlay.selection_changed.connect(func():
		keyframe_editor.lanes.selected_keys.assign(overlay.selected_keys)
		keyframe_editor._build_details())
	canvas.draw.connect(func(): overlay.queue_redraw())
	canvas.time_selected.connect(func(time: float):
		canvas.playhead = time
		_evaluate_runtimes()
		if not playing: audio_system.scrub(model, time)
		_refresh())
	v_scroll = VScrollBar.new()
	actor_view.add_child(v_scroll)
	v_scroll.value_changed.connect(func(value: float):
		canvas.scroll_rows = value
		canvas.queue_redraw())
	h_scroll = HScrollBar.new()
	add_child(h_scroll)
	h_scroll.value_changed.connect(func(value: float):
		canvas.scroll_time = value
		canvas.queue_redraw()
		if keyframe_editor != null and keyframe_editor.lanes != null:
			keyframe_editor.lanes.queue_redraw())
	h_scroll.value_changed.connect(func(_value: float): keyframe_editor.ruler.queue_redraw())
	canvas.scroll_requested.connect(func(time: float):
		h_scroll.max_value = maxf(h_scroll.max_value, time + h_scroll.page + 15.0)
		h_scroll.value = time)
	canvas.layer_scroll_requested.connect(func(offset: float): v_scroll.value = offset)
	context_menu = PopupMenu.new()
	context_menu.name = "ActorContextMenu"
	add_child(context_menu)
	_style_context_menu()
	context_menu.id_pressed.connect(_context_action_selected)
	context_menu.popup_hide.connect(func(): hints.end(context_menu))
	canvas.context_requested.connect(_show_context_menu)
	keyframe_editor = ActorKeyframeEditor.new()
	keyframe_editor.model = model
	keyframe_editor.timeline = canvas
	keyframe_editor.hints = hints
	keyframe_view = Control.new()
	body.add_child(keyframe_view)
	keyframe_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	keyframe_view.hide()
	keyframe_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	keyframe_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	keyframe_view.add_child(keyframe_editor)
	keyframe_editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	keyframe_editor.close_requested.connect(func(): set_keyframe_view(false))
	hint_label = Label.new()
	hint_label.custom_minimum_size.y = 18
	hint_label.add_theme_font_size_override("font_size", 11)
	hint_label.modulate = Color("aebdcc")
	hint_label.clip_text = true
	var footer := HBoxContainer.new()
	add_child(footer)
	hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(hint_label)
	footer.add_child(keyframes_button)
	hints.changed.connect(func(text: String): hint_label.text = text)
	canvas.interaction_changed.connect(func(text: String):
		if text.is_empty():
			hints.end(canvas)
		else:
			hints.begin(canvas, text))
	model.changed.connect(_on_model_changed)
	canvas.resized.connect(_refresh)
	var properties_panel := get_node_or_null("../HSplitContainer/PropertiesPanel") as Control
	if properties_panel != null:
		if StaticData.loaded_project != null:
			if StaticData.loaded_project.actor_inspector_state == null:
				StaticData.loaded_project.actor_inspector_state = ActorInspectorState.new()
			inspector_ui_state = StaticData.loaded_project.actor_inspector_state
		inspector = ActorInspector.new()
		properties_panel.add_child(inspector)
		inspector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inspector.offset_left = 10
		inspector.offset_top = 10
		inspector.offset_right = -10
		inspector.offset_bottom = -10
		properties_panel.custom_minimum_size.x = 220
		inspector.theme = theme
		inspector.hints = hints
		inspector.setup(model, registry, inspector_ui_state)
		inspector.ui_state_changed.connect(_schedule_ui_state_save)
		var project_filesystem := get_node_or_null("../../VSplitContainer/FileSystem")
		if project_filesystem != null and project_filesystem.has_signal("file_resource_opened"):
			project_filesystem.file_resource_opened.connect(_inspect_project_resource)
	_setup_runtime_holder()
	# Shader compilation failures can leave RenderingServer state attached to an
	# otherwise valid material. Rebuilding the actor runtime on the next source
	# revision gives a corrected shader a completely fresh mesh/material RID.
	call_deferred("_connect_shader_editor")
	_refresh()


func _inspect_project_resource(path: String) -> void:
	if path.get_extension().to_lower() in ["tres", "res"]:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource is ActorSceneData:
			return
	inspector.inspect_file_resource(path)


func _toolbar_icon(kind: String) -> Texture2D:
	var paths := {
		"undo": '<path d="M8 4 3 9l5 5M3 9h9a6 6 0 0 1 0 12"/>',
		"redo": '<path d="m16 4 5 5-5 5m5-5h-9a6 6 0 0 0 0 12"/>',
		"magnet": '<path d="M5 3v10a7 7 0 0 0 14 0V3h-5v10a2 2 0 0 1-4 0V3Z"/><path d="M5 7h5m4 0h5"/>',
		"split": '<circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="m8 8 12 12M8 16 20 4"/>',
		"mic": '<rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3m-4 0h8"/>',
		"screen": '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M8 22h8m-4-5v5"/><circle cx="17" cy="7" r="2"/>',
		"stop": '<rect x="5" y="5" width="14" height="14" rx="2"/>',
		"keys": '<path d="m12 3 8 9-8 9-8-9Z"/>',
		"grid": '<path d="M3 7h18M3 17h18M7 3v18M17 3v18"/>',
		"add": '<path d="M12 4v16M4 12h16"/>'}
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24"><g fill="none" stroke="#94dfc6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + str(paths.get(kind, paths.add)) + '</g></svg>'
	if kind == "stop": svg = svg.replace("#94dfc6", "#ff8291")
	var image := Image.new()
	image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(image)

func _pause_recording_scene(paused: bool) -> void:
	if paused:
		if is_instance_valid(_recording_viewport): return
		if not is_instance_valid(runtime_holder): return
		_recording_viewport = runtime_holder.get_viewport() as SubViewport
		if _recording_viewport == null: return
		_saved_viewport_update = _recording_viewport.render_target_update_mode
		_saved_scene_process = _recording_viewport.process_mode
		_recording_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_recording_viewport.process_mode = Node.PROCESS_MODE_DISABLED
	elif is_instance_valid(_recording_viewport):
		_recording_viewport.render_target_update_mode = _saved_viewport_update
		_recording_viewport.process_mode = _saved_scene_process
		_recording_viewport = null

func _active_recording_audio() -> ActorAudioRecorder:
	if screen_recorder.recording and is_instance_valid(screen_recorder.audio_recorder):
		return screen_recorder.audio_recorder
	if audio_recorder.recording:
		return audio_recorder
	return null

func _recording_timeline_audio() -> bool:
	var recorder := _active_recording_audio()
	return recorder != null and recorder.record_timeline

func _route_timeline_audio() -> void:
	if audio_system == null: return
	var recorder := _active_recording_audio()
	var destination := "Master"
	if recorder != null and recorder.record_timeline and not recorder.timeline_bus_name.is_empty():
		destination = recorder.timeline_bus_name
	audio_system.set_output_bus(destination)

func toggle_recording() -> void:
	if screen_recorder.recording: return
	if _record_busy: return
	_record_busy = true
	if audio_recorder.recording:
		playing = false
		_evaluate_runtimes()
		var stream: AudioStreamWAV = await audio_recorder.stop()
		_route_timeline_audio()
		_pause_recording_scene(false)
		_record_busy = false
		canvas.recording_preview.clear()
		playing = false
		play_button.text = "▶"
		_evaluate_runtimes()
		mic_button.icon = _toolbar_icon("mic")
		mic_button.self_modulate = Color.WHITE
		mic_button.tooltip_text = "Record selected audio sources (R); use ▾ for recording options"
		hints.end(audio_recorder)
		if stream != null:
			_create_recording(stream)
		else:
			_audio_notice("No audio was captured. Check the selected recording sources and their permissions.")
		_refresh()
	else:
		playing = false
		for player in audio_system.players.values(): player.stop()
		_pause_recording_scene(true)
		var error: String = await audio_recorder.start()
		_record_busy = false
		if not error.is_empty():
			_pause_recording_scene(false)
			_audio_notice(error)
			return
		_record_start = canvas.playhead
		_record_elapsed = 0.0
		_record_layer = model.selected_layer
		for existing in model.section_clips(): _record_layer = maxi(_record_layer, existing.layer + 1)
		canvas.recording_preview = {"start": _record_start, "duration": 0.0, "layer": _record_layer}
		playing = true
		play_button.text = "Ⅱ"
		_route_timeline_audio()
		_evaluate_runtimes()
		mic_button.icon = _toolbar_icon("stop")
		mic_button.self_modulate = Color.WHITE
		mic_button.tooltip_text = "Stop recording and create an audio actor (R)"
		hints.begin(audio_recorder, "Recording audio • R or the stop button finishes recording")
		_refresh()
		v_scroll.value = maxf(0.0, (_record_layer + 1) * canvas.row_height - v_scroll.page)

func _create_recording(stream: AudioStreamWAV) -> ActorClip:
	model.selected_layer = _record_layer
	var clip := model.create_actor(registry.get_definition(&"audio"), _record_start, {&"audio": stream})
	if clip != null:
		model.actor_for_id(clip.actor_id).display_name = stream.resource_name if not stream.resource_name.is_empty() else "Audio Recording"
		model.changed.emit()
	return clip

func _audio_notice(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "Audio Recording"
	dialog.dialog_text = message
	add_child(dialog)
	dialog.popup_centered(Vector2i(460, 130))
	dialog.popup_hide.connect(dialog.queue_free)

func toggle_playback() -> void:
	if _record_busy: return
	if screen_recorder.recording:
		_stop_screen_recording()
		return
	if audio_recorder.recording:
		toggle_recording()
		return
	playing = not playing
	play_button.text = "Ⅱ" if playing else "▶"
	_evaluate_runtimes()

func _process(delta: float) -> void:
	if physics.pending and not exporting and not audio_recorder.recording and not screen_recorder.recording:
		_evaluate_runtimes()
		if physics.pending: return
	if not playing or canvas == null: return
	canvas.playhead += delta
	if audio_recorder.recording or screen_recorder.recording:
		_record_elapsed += delta
		canvas.recording_preview.duration = _record_elapsed
		canvas.recording_peaks = screen_recorder.audio_recorder.peaks if screen_recorder.recording and screen_recorder.audio_recorder != null else audio_recorder.peaks
	_evaluate_runtimes()
	_refresh()
	var right_time := canvas.scroll_time + maxf(0, canvas.size.x - ActorTimelineCanvas.LABEL_WIDTH) / canvas.pixels_per_second
	if canvas.playhead > right_time: h_scroll.value = canvas.playhead - maxf(0, right_time - canvas.scroll_time) * 0.8

func _start_screen_recording(options: Dictionary, target: Dictionary) -> void:
	if _record_busy or audio_recorder.recording or screen_recorder.recording: return
	playing = false
	for player in audio_system.players.values(): player.stop()
	_pause_recording_scene(true)
	_record_busy = true
	var error: String = await screen_recorder.start(options, target)
	_record_busy = false
	if not error.is_empty():
		_pause_recording_scene(false)
		_audio_notice(error)
		return
	_record_start = canvas.playhead
	_record_elapsed = 0.0
	_record_layer = model.selected_layer
	for clip in model.section_clips(): _record_layer = maxi(_record_layer, clip.layer + 1)
	canvas.recording_preview = {"start": _record_start, "duration": 0.0, "layer": _record_layer}
	canvas.recording_peaks = PackedFloat32Array()
	playing = true
	play_button.text = "Ⅱ"
	_route_timeline_audio()
	_evaluate_runtimes()
	screen_button.icon = _toolbar_icon("stop")
	screen_button.tooltip_text = "Stop screen recording"
	mic_button.disabled = true
	hints.begin(screen_recorder, "Screen recording • Click screen stop or press Space to finish")
	_refresh()

func _stop_screen_recording() -> void:
	if _record_busy or not screen_recorder.recording: return
	_record_busy = true
	playing = false
	_evaluate_runtimes()
	var path: String = await screen_recorder.stop()
	_route_timeline_audio()
	_pause_recording_scene(false)
	_record_busy = false
	canvas.recording_preview.clear()
	play_button.text = "▶"
	screen_button.icon = _toolbar_icon("screen")
	screen_button.tooltip_text = "Screen recording: choose a display or window and audio sources"
	mic_button.disabled = false
	hints.end(screen_recorder)
	_refresh()
	if not path.is_empty():
		var dimension := await ActorDimensionDialog.choose(self, "Screen Recording")
		if dimension.is_empty(): return
		model.selected_layer = _record_layer
		var clip := model.create_actor(registry.get_definition(&"video_2d" if dimension == &"2d" else &"video"), _record_start, {&"video": path})
		if clip != null:
			var actor := model.actor_for_id(clip.actor_id)
			actor.display_name = "Screen Recording"
			var audio := model.actor_for_id(str(actor.values.get(&"linked_audio_actor", "")))
			if audio != null: audio.display_name = "Screen Recording Audio"
			model.changed.emit()
	else: _audio_notice("Screen recording could not be finalized. " + screen_recorder.last_error)
	_refresh()

func set_keyframe_view(enabled: bool) -> void:
	canvas.cancel_drag()
	property_overlay.cancel_drag()
	if not enabled:
		keyframe_editor.cancel_interaction()
	keyframes_button.set_pressed_no_signal(enabled)
	actor_view.visible = not enabled
	keyframe_view.visible = enabled
	breadcrumb_panel.visible = not enabled
	if enabled:
		keyframe_editor.refresh()


func _button(parent: Control, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _timing_input(parent: Control, label_text: String) -> DragNumber:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color("82a7bc"))
	parent.add_child(label)
	var input := DragNumber.new()
	input.min_value = 0.0
	input.max_value = 86400.0
	input.allow_greater = true
	input.step = 0.01
	input.suffix = " s"
	input.custom_minimum_size.x = 92
	input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	input.update_on_text_changed = false
	input.get_line_edit().add_theme_color_override("font_color", Color("e2f2f7"))
	parent.add_child(input)
	return input


func _zoom_slider(parent: Control, axis: String, minimum: float, maximum: float,
		initial: float, tooltip: String) -> HSlider:
	var badge := Label.new()
	badge.text = axis
	badge.custom_minimum_size = Vector2(18, 18)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_color_override("font_color", Color("83dfc8"))
	badge.add_theme_font_size_override("font_size", 10)
	parent.add_child(badge)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.value = initial
	slider.step = 1.0
	slider.custom_minimum_size.x = 68
	slider.tooltip_text = tooltip
	parent.add_child(slider)
	return slider


func _connect_timing_input(input: DragNumber, kind: String) -> void:
	input.interaction_started.connect(func():
		_timing_drag_kind = kind
		_timing_drag_original = _capture_clip_states()
		hints.begin(input, "Drag to change %s • Esc cancels" % kind))
	input.preview_changed.connect(func(value: float):
		if _timing_drag_kind != kind:
			return
		var states := _timing_states(value, kind, _timing_drag_original)
		model.preview_clip_states(states, model.selected_id))
	input.drag_committed.connect(func(_value: float):
		if _timing_drag_kind != kind:
			return
		var final_states := _capture_clip_states()
		if final_states != _timing_drag_original:
			model.commit_clip_state_preview(_timing_drag_original, final_states,
				"Change Actor %s" % kind.capitalize(), model.selected_id)
		_timing_drag_kind = ""
		_timing_drag_original.clear()
		hints.end(input)
		_refresh())
	input.drag_cancelled.connect(func():
		if _timing_drag_kind == kind and not _timing_drag_original.is_empty():
			model.preview_clip_states(_timing_drag_original, model.selected_id)
		_timing_drag_kind = ""
		_timing_drag_original.clear()
		hints.end(input))
	input.interaction_ended.connect(func(): hints.end(input))
	input.value_changed.connect(func(value: float):
		if not _timing_drag_kind.is_empty():
			return
		var states := _timing_states(value, kind, _capture_clip_states())
		model.commit_clip_states(states, "Change Actor %s" % kind.capitalize(), model.selected_id)
		_refresh())


func _capture_clip_states() -> Dictionary:
	var states: Dictionary = {}
	for id in model.linked_clip_ids(model.selected_ids):
		var index := model._index_of(id)
		if index >= 0:
			var clip := model.clips[index]
			states[id] = {"start": clip.start_time, "duration": clip.duration,
				"layer": clip.layer, "offset": clip.source_offset}
	return states


func _timing_states(value: float, kind: String, originals: Dictionary) -> Dictionary:
	if not originals.has(model.selected_id):
		return {}
	var result := originals.duplicate(true)
	var primary: Dictionary = originals[model.selected_id]
	if kind == "start":
		var delta := value - float(primary.start)
		for id: String in result:
			result[id].start = float(originals[id].start) + delta
	else:
		var delta := value - float(primary.start) - float(primary.duration)
		for id: String in result:
			result[id].duration = float(originals[id].duration) + delta
	return result


func create_actor(type_index: int) -> void:
	canvas.cancel_drag()
	if type_index < 0 or type_index >= _definitions.size():
		return
	var definition := _definitions[type_index]
	var initial_values: Dictionary = {}
	for property in definition.properties:
		if property.options.get("prompt_on_create", false):
			var picker_property := property
			if not property.object_type.is_empty():
				picker_property = ActorProperty.new()
				picker_property.id = property.id
				picker_property.label = property.label
				picker_property.value_type = TYPE_STRING
				picker_property.options = {
					"extensions": property.options.get("prompt_extensions", []),
					"file_picker": true
				}
			var chosen := await ActorProjectFilePicker.pick(self, picker_property, "Choose %s for %s" % [property.label, definition.display_name])
			if chosen==ActorProjectFilePicker.EMPTY_RESOURCE: initial_values[property.id]=null; continue
			if chosen.is_empty():
				canvas.grab_focus()
				return
			if not property.object_type.is_empty():
				var object_definition := registry.get_object_definition(property.object_type)
				var target_property := StringName(property.options.get("prompt_object_property", &""))
				if object_definition == null or target_property.is_empty() or object_definition.find_property(target_property) == null:
					canvas.grab_focus()
					return
				var object := object_definition.create_object()
				object.set_value(target_property, chosen)
				initial_values[property.id] = ActorObjectReference.from_object(object)
			else:
				initial_values[property.id] = chosen
	var clip := model.create_actor(definition, canvas.playhead, initial_values)
	if clip == null: return
	canvas.grab_focus()
	# Keep the newly selected row visible as the list grows.
	v_scroll.value = maxf(0.0, (clip.layer + 1) * canvas.row_height - v_scroll.page)
	if clip.start_time < h_scroll.value or clip.start_time > h_scroll.value + h_scroll.page:
		h_scroll.value = clip.start_time
func _create_dropped_actors(paths: PackedStringArray, time: float, layer: int) -> void:
	canvas.cancel_drag()
	for path in paths:
		var type := ActorFileImport.type_for_path(path)
		if type == &"scene_instance":
			var source := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
			model.selected_layer = layer
			model.instantiate_scene(source, registry.get_definition(&"point_3d"), time, layer,
				path.get_file().get_basename())
			continue
		if type in [&"image_3d", &"video", &"text_3d"]:
			var dimension := await ActorDimensionDialog.choose(self, path.get_file())
			if dimension.is_empty(): continue
			if dimension == &"2d":
				type = {&"image_3d": &"image_2d", &"video": &"video_2d", &"text_3d": &"text_2d"}[type]
		var definition := registry.get_definition(type)
		if definition == null: continue
		model.selected_layer = layer
		var clip := model.create_actor(definition, time, ActorFileImport.values_for_path(path, registry))
		if clip != null:
			model.actor_for_id(clip.actor_id).display_name = path.get_file().get_basename()
			model.changed.emit()
	_refresh()
	canvas.grab_focus()

func delete_selected() -> void:
	canvas.cancel_drag()
	model.delete_selected()
	canvas.grab_focus()


func unparent_selected() -> void:
	canvas.cancel_drag()
	var actor_ids: Array[String] = []
	for actor in model.selected_actors():
		actor_ids.append(actor.id)
	model.unparent_many(actor_ids)
	canvas.grab_focus()


func parent_selected() -> void:
	var parent := model.selected_actor()
	if parent == null or model.selected_ids.size() < 2:
		return
	var children: Array[String] = []
	for actor in model.selected_actors():
		if actor.id != parent.id:
			children.append(actor.id)
	model.parent_many(children, parent.id)
	canvas.grab_focus()


func copy_selected() -> void:
	_actor_clipboard = _capture_selected_snapshots()
	canvas.grab_focus()
	_update_idle_hint()


func duplicate_selected() -> void:
	var snapshots := _capture_selected_snapshots()
	if snapshots.is_empty():
		return
	var start := INF
	var layer := 2147483647
	for snapshot in snapshots:
		start = minf(start, float(snapshot.start))
		layer = mini(layer, int(snapshot.layer))
	model.paste_snapshots(snapshots, start, layer, [], "Duplicate Actors", true)
	canvas.grab_focus()


func paste_copied(as_children: bool, time: float, layer: int) -> void:
	if _actor_clipboard.is_empty():
		return
	var parents: Array[String] = []
	if as_children:
		for actor in model.selected_actors():
			parents.append(actor.id)
	model.paste_snapshots(_actor_clipboard, time, layer, parents, "Paste Actors")
	canvas.grab_focus()


func _capture_selected_snapshots() -> Array[Dictionary]:
	var snapshots: Array[Dictionary] = []
	for id in model.selected_ids:
		var index := model._index_of(id)
		if index < 0:
			continue
		var actor := model.actors[index]
		var clip := model.clips[index]
		snapshots.append({
			"actor": actor.copy_actor(),
			"source_id": actor.id,
			"source_parent": actor.parent_id,
			"start": clip.start_time,
			"duration": clip.duration,
			"offset": clip.source_offset,
			"speed": clip.playback_speed,
			"layer": clip.layer
		})
	return snapshots


const MENU_EDIT_AUDIO := 90721

func _show_context_menu(screen_position: Vector2, actor_clicked: bool = true,
		timeline_time: float = -1.0, layer: int = -1, root_label: String = "", section_id: String = "") -> void:
	_context_on_actor = actor_clicked
	_context_section_id = section_id
	_context_time = canvas.playhead if timeline_time < 0.0 else timeline_time
	_context_layer = model.selected_layer if layer < 0 else layer
	context_menu.clear()
	if actor_clicked and not model.selected_ids.is_empty():
		var count := model.selected_ids.size()
		var header := model.selected_actor().display_name.to_upper() if count == 1 else "%d ACTORS SELECTED" % count
		context_menu.add_item(header, MENU_HEADER)
		context_menu.set_item_disabled(context_menu.get_item_index(MENU_HEADER), true)
		var definition := registry.get_definition(model.selected_actor().type_id)
		if definition != null and definition.icon != null:
			context_menu.set_item_icon(context_menu.get_item_index(MENU_HEADER), definition.icon)
		context_menu.add_separator()
		context_menu.add_item("Go Up One Level  •  F" if model.selected_actor().id == model.focused_actor_id else "Focus Actor  •  F", MENU_FOCUS_ACTOR)
		context_menu.set_item_tooltip(context_menu.get_item_index(MENU_FOCUS_ACTOR), "Return to the parent view" if model.selected_actor().id == model.focused_actor_id else "Show only %s and its descendants" % model.selected_actor().display_name)
		context_menu.add_item("Duplicate", MENU_DUPLICATE)
		context_menu.add_item("Copy", MENU_COPY)
		if count == 1 and model.selected_actor().type_id == &"audio":
			context_menu.add_item("Edit in Audio Workspace", MENU_EDIT_AUDIO)
		context_menu.add_item("Set Start / End…", MENU_TIMING)
		if not _actor_clipboard.is_empty():
			var paste_label := "Paste as Child" if count == 1 else "Paste to Each as Child"
			context_menu.add_item(paste_label, MENU_PASTE)
		if count > 1:
			context_menu.add_separator()
			context_menu.add_item("Parent to %s" % model.selected_actor().display_name, MENU_PARENT)
		var has_parented_actor := false
		for actor in model.selected_actors():
			if not actor.parent_id.is_empty():
				has_parented_actor = true
				break
		context_menu.add_item("Unparent", MENU_UNPARENT)
		context_menu.set_item_disabled(context_menu.get_item_index(MENU_UNPARENT), not has_parented_actor)
		context_menu.add_separator()
		context_menu.add_item("Delete", MENU_DELETE)
	else:
		var header := root_label if not root_label.is_empty() else "TIMELINE  •  %.1fs" % _context_time
		context_menu.add_item(header, MENU_HEADER)
		context_menu.set_item_disabled(context_menu.get_item_index(MENU_HEADER), true)
		context_menu.add_separator()
		var paste_label := "Paste into Scene" if not root_label.is_empty() else "Paste at Playhead"
		context_menu.add_item("%s  •  %.2fs" % [paste_label, canvas.playhead], MENU_PASTE)
		context_menu.set_item_disabled(context_menu.get_item_index(MENU_PASTE), _actor_clipboard.is_empty())
		if not section_id.is_empty():
			context_menu.add_separator()
			context_menu.add_item("Delete Section…", MENU_DELETE_SECTION)
	context_menu.position = Vector2i(screen_position)
	hints.begin(context_menu, "Choose an action • Esc closes menu")
	context_menu.popup()


func _context_action_selected(id: int) -> void:
	match id:
		MENU_EDIT_AUDIO:
			var tabs := get_tree().get_first_node_in_group("actor_scene_tabs")
			var actor := model.selected_actor()
			if tabs != null and actor != null: tabs.open_audio_actor(actor)
		MENU_DUPLICATE: duplicate_selected()
		MENU_COPY: copy_selected()
		MENU_PASTE: paste_copied(_context_on_actor, canvas.playhead, _context_layer)
		MENU_PARENT: parent_selected()
		MENU_UNPARENT: unparent_selected()
		MENU_DELETE: delete_selected()
		MENU_DELETE_SECTION: _confirm_delete_section(_context_section_id)
		MENU_FOCUS_ACTOR: focus_selected_actor()
		MENU_TIMING:
			_refresh()
			timing_dialog.popup_centered(Vector2i(380, 108))


func focus_selected_actor() -> void:
	var actor := model.selected_actor()
	if actor == null:
		return
	canvas.cancel_drag()
	model.focus_actor(actor.id)
	canvas.grab_focus()


func _update_breadcrumbs() -> void:
	if breadcrumb_row == null:
		return
	var section := model.section_for_id(model.selected_section_id)
	if section == null:
		return
	var path := model.focus_path()
	var signature := section.id + "|" + section.display_name
	for actor in path:
		signature += "|" + actor.id + "|" + actor.display_name
	if signature == _breadcrumb_signature:
		return
	_breadcrumb_signature = signature
	for child in breadcrumb_row.get_children():
		breadcrumb_row.remove_child(child)
		child.queue_free()
	var section_button := _button(breadcrumb_row, section.display_name, func():
		canvas.cancel_drag()
		model.leave_actor_focus()
		canvas.grab_focus())
	section_button.tooltip_text = "Return to entire section  •  Alt+Home"
	for actor in path:
		var arrow := Label.new()
		arrow.text = " › "
		arrow.modulate = Color("75889b")
		breadcrumb_row.add_child(arrow)
		var actor_id := actor.id
		var button := _button(breadcrumb_row, actor.display_name, func():
			canvas.cancel_drag()
			model.focus_actor(actor_id)
			canvas.grab_focus())
		button.tooltip_text = "View this actor and its descendants"
		if actor_id == model.focused_actor_id:
			button.add_theme_stylebox_override("normal", _box(Color("245b5b"), Color("72cfb8")))


func _confirm_delete_section(section_id: String) -> void:
	var section := model.section_for_id(section_id)
	if section == null:
		return
	var count := 0
	for actor in model.actors:
		if actor.section_id == section_id:
			count += 1
	if count == 0:
		canvas.cancel_drag()
		model.delete_section(section_id)
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Delete Section"
	dialog.dialog_text = "Delete \"%s\" and its %d actor(s)?\nYou can undo this action." % [section.display_name, count]
	if model.sections.size() == 1:
		dialog.dialog_text += "\nA new empty section will replace the last section."
	dialog.ok_button_text = "Delete Section"
	dialog.add_theme_stylebox_override("panel", _box(Color("202a37"), Color("34465a")))
	add_child(dialog)
	dialog.confirmed.connect(func():
		canvas.cancel_drag()
		model.delete_section(section_id)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(440, 170))


func undo() -> void:
	canvas.cancel_drag()
	model.undo()


func redo() -> void:
	canvas.cancel_drag()
	model.redo()


func capture_scene_data(duplicate_resources: bool = true) -> ActorSceneData:
	# Flush the currently displayed section before copying the state map.
	if canvas != null and not model.selected_section_id.is_empty():
		_timeline_section_states[model.selected_section_id] = {
			"x": canvas.scroll_time, "y": canvas.scroll_rows,
			"zoom_x": canvas.pixels_per_second, "zoom_y": canvas.row_height,
			"cursor": canvas.playhead, "snap": canvas.snap_enabled}
	var scene := ActorSceneData.new()
	for actor in model.actors:
		scene.actors.append(actor.duplicate(true) if duplicate_resources else actor)
	for clip in model.clips:
		scene.clips.append(clip.duplicate(true) if duplicate_resources else clip)
	for section in model.sections:
		scene.sections.append(section.duplicate(true) if duplicate_resources else section)
	scene.selected_ids.assign(model.selected_ids)
	scene.selected_id = model.selected_id
	scene.selected_layer = model.selected_layer
	scene.selected_section_id = model.selected_section_id
	scene.focused_actor_id = model.focused_actor_id
	scene.playhead_time = canvas.playhead if canvas != null else model.playhead_time
	scene.overlay_actor_id = model.overlay_actor_id
	scene.overlay_path = model.overlay_path.duplicate()
	scene.section_navigation = model.navigation_state()
	scene.timeline_section_states = _timeline_section_states.duplicate(true)
	scene.inspector_state = inspector_ui_state.duplicate(true)
	scene.keyframe_view_enabled = keyframe_view != null and keyframe_view.visible
	scene.video_duration = video_duration
	scene.video_duration_custom = video_duration_is_custom()
	if keyframe_editor != null and keyframe_editor.lanes != null:
		scene.selected_key_ids.assign(keyframe_editor.lanes.selected_keys)
		scene.keyframe_track_scroll = keyframe_editor.track_scroll.scroll_vertical
		scene.keyframe_detail_scroll = keyframe_editor.detail_scroll.scroll_horizontal
	var split := get_parent() as SplitContainer
	if split != null:
		scene.timeline_split_offset = split.split_offset
	var camera := get_node_or_null("../../../../World/SubViewport/Freecam") as Node3D
	if camera != null:
		scene.editor_camera_transform = camera.transform
		var head := camera.get_node_or_null("Head") as Node3D
		var lens := camera.get_node_or_null("Head/Camera3D") as Camera3D
		if head != null: scene.editor_camera_head_rotation = head.rotation
		if lens != null: scene.editor_camera_lens_rotation = lens.rotation
		scene.editor_camera_speed = float(camera.get("speed"))
	return scene


func restore_scene_data(scene: ActorSceneData, retain_previous_history: bool = false) -> void:
	if scene == null:
		return
	canvas.cancel_drag()
	model.actors.assign(scene.actors)
	model.clips.assign(scene.clips)
	model.sections.assign(scene.sections)
	if model.sections.is_empty():
		model.sections.append(ActorSection.new())
	model.selected_ids.assign(scene.selected_ids)
	model.selected_id = scene.selected_id
	model.selected_layer = scene.selected_layer
	model.selected_section_id = scene.selected_section_id
	if model.section_for_id(model.selected_section_id) == null:
		model.selected_section_id = model.sections[0].id
	model.focused_actor_id = scene.focused_actor_id
	model.playhead_time = scene.playhead_time
	model.overlay_actor_id = scene.overlay_actor_id
	model.overlay_path = scene.overlay_path.duplicate()
	model.restore_navigation_state(scene.section_navigation)
	_video_duration_override = maxf(0.01, scene.video_duration) if scene.video_duration_custom else -1.0
	if not retain_previous_history and is_instance_valid(model.history):
		model.history.clear_history()
		model.history.free()
	model.history = UndoRedo.new()
	_timeline_section_states = scene.timeline_section_states.duplicate(true)
	inspector_ui_state.restore_from(scene.inspector_state)
	_displayed_section_id = ""
	_displayed_focus_id = ""
	_recreate_runtimes()
	model.changed.emit()
	set_keyframe_view(scene.keyframe_view_enabled)
	if keyframe_editor != null and keyframe_editor.lanes != null:
		keyframe_editor.lanes.selected_keys.assign(scene.selected_key_ids)
		keyframe_editor.track_scroll.scroll_vertical = scene.keyframe_track_scroll
		keyframe_editor.detail_scroll.scroll_horizontal = scene.keyframe_detail_scroll
		keyframe_editor.lanes.queue_redraw()
	var split := get_parent() as SplitContainer
	if split != null:
		split.split_offset = scene.timeline_split_offset
	var camera := get_node_or_null("../../../../World/SubViewport/Freecam") as Node3D
	if camera != null:
		camera.transform = scene.editor_camera_transform
		var head := camera.get_node_or_null("Head") as Node3D
		var lens := camera.get_node_or_null("Head/Camera3D") as Camera3D
		if head != null: head.rotation = scene.editor_camera_head_rotation
		if lens != null: lens.rotation = scene.editor_camera_lens_rotation
		camera.set("speed", scene.editor_camera_speed)


func _setup_runtime_holder() -> void:
	var viewport := get_node_or_null("../../../../World/SubViewport") as SubViewport
	if viewport == null:
		return
	var editor_camera := viewport.get_node_or_null("Freecam/Head/Camera3D") as Camera3D
	if editor_camera != null:
		editor_camera.cull_mask |= 2
		editor_camera.make_current()
	runtime_holder = Node3D.new()
	runtime_holder.name = "ActorRuntimes"
	viewport.add_child(runtime_holder)
	var gizmo := ActorUIGizmo.new()
	viewport_gizmo = gizmo
	gizmo.editor = self
	var display := get_node_or_null("../HSplitContainer/VBoxContainer/Viewport") as TextureRect
	if display != null:
		gizmo.display = display
		display.add_child(gizmo)
	else:
		var overlay := CanvasLayer.new()
		overlay.layer = 100
		runtime_holder.add_child(overlay)
		overlay.add_child(gizmo)
	_sync_runtimes()


func _connect_shader_editor() -> void:
	var shader_editor := get_tree().get_first_node_in_group("shader_code_editor")
	if shader_editor == null or not shader_editor.has_signal("shader_changed"):
		return
	var callback := Callable(self, "_on_shader_source_changed")
	if not shader_editor.is_connected("shader_changed", callback):
		shader_editor.connect("shader_changed", callback)


func _on_shader_source_changed(_source: Variant) -> void:
	_recreate_runtimes()


func refresh_saved_shader(source: Variant) -> void:
	# Match shader-uniform edits: evaluate the model immediately so every live
	# runtime samples the newly saved program and reapplies its parameters.
	_on_model_changed()
	if inspector != null:
		inspector.refresh_shader_source(source)


func _recreate_runtimes() -> void:
	physics.dispose()
	if runtime_holder == null:
		return
	# Detach before queueing deletion so the failed runtime stops participating in
	# rendering immediately. Calling free() on live 3D nodes here can crash Godot
	# while RenderingServer is processing the SubViewport.
	for runtime in _runtimes.values():
		if is_instance_valid(runtime) and runtime.get_parent() != null:
			runtime.get_parent().remove_child(runtime)
	for runtime in _runtimes.values():
		if is_instance_valid(runtime):
			runtime.queue_free()
	_runtimes.clear()
	_particle_seek_states.clear()
	_sync_runtimes()


func _on_model_changed() -> void:
	physics.mark_dirty()
	model.validate_focus()
	_sync_runtimes()
	_refresh()


func _sync_runtimes() -> void:
	if runtime_holder == null:
		return
	var live_ids: Dictionary = {}
	for index in model.clips.size():
		var clip := model.clips[index]
		live_ids[clip.id] = true
		if not _runtimes.has(clip.id):
			var definition := registry.get_definition(model.actors[index].type_id)
			var runtime := definition.create_runtime(model.actors[index]) if definition != null else null
			if runtime != null:
				runtime_holder.add_child(runtime)
				_runtimes[clip.id] = runtime
	# Reparent live runtimes before freeing stale parents. Deleting an actor can
	# otherwise free still-live child runtimes along with its node subtree.
	for index in model.actors.size():
		var actor := model.actors[index]
		var clip := model.clips[index]
		var runtime := _runtime_for_clip(clip.id)
		if runtime == null:
			continue
		var parent_runtime: ActorRuntime = null
		if not actor.parent_id.is_empty():
			for parent_index in model.actors.size():
				if model.actors[parent_index].id == actor.parent_id:
					parent_runtime = _runtime_for_clip(model.clips[parent_index].id)
					break
		var target_parent: Node = parent_runtime.parenting_node() if parent_runtime != null else runtime_holder
		if runtime.get_parent() != target_parent:
			if runtime.get_parent() != null:
				runtime.get_parent().remove_child(runtime)
			target_parent.add_child(runtime)
	for id in _runtimes.keys():
		if not live_ids.has(id):
			var stale_value: Variant = _runtimes.get(id)
			# Never cast a stale Object reference: GDScript reports the cast itself
			# as an error before is_instance_valid() could protect it.
			if is_instance_valid(stale_value):
				(stale_value as ActorRuntime).free()
			_runtimes.erase(id)
	_evaluate_runtimes()


func _runtime_for_clip(clip_id: String) -> ActorRuntime:
	var value: Variant = _runtimes.get(clip_id)
	if not is_instance_valid(value):
		_runtimes.erase(clip_id)
		return null
	return value as ActorRuntime


func _evaluate_runtimes() -> void:
	if audio_recorder.recording or screen_recorder.recording:
		_route_timeline_audio()
		if _recording_timeline_audio():
			model.playhead_time = canvas.playhead
			audio_system.synchronize(model, canvas.playhead, playing)
		else:
			for player in audio_system.players.values(): player.stop()
		return
	if audio_system != null and audio_system.output_bus != "Master": audio_system.set_output_bus("Master")
	model.playhead_time = canvas.playhead
	physics.restore_visuals()
	var indices: Array[int] = []
	for index in model.actors.size():
		model.actors[index].animation_time = model.clips[index].local_time(canvas.playhead)
		indices.append(index)
	if audio_system != null:
		audio_system.synchronize(model, canvas.playhead, playing)
	indices.sort_custom(func(a: int, b: int):
		return _actor_depth(model.actors[a]) < _actor_depth(model.actors[b]))
	for index in indices:
		var clip := model.clips[index]
		var runtime := _runtime_for_clip(clip.id)
		if runtime != null:
			runtime.evaluate_clip(clip, canvas.playhead)
	var rig_attachment_bases := {}
	for index in indices:
		var runtime := _runtime_for_clip(model.clips[index].id)
		if runtime!=null and runtime.actor.values.has(&"model_rigid_bone"): rig_attachment_bases[runtime.actor.id]=runtime.remote_transform()
		if runtime!=null and runtime.has_method("apply_rig_attachment"): runtime.apply_rig_attachment()
	_apply_remote_transforms()
	physics.evaluate(model,_runtimes,canvas.playhead)
	for index in indices:
		var runtime := _runtime_for_clip(model.clips[index].id)
		if runtime==null or physics.prototypes.is_empty() or not runtime.has_method("apply_rig_attachment"): continue
		# A rigid bone attachment is an absolute rest-to-pose delta, not something
		# that can be applied twice to its already-transformed output.
		if rig_attachment_bases.has(runtime.actor.id):
			if physics.display_states.get(runtime.actor.id,{}).get("initialized",false): continue
			runtime.apply_remote_transform(rig_attachment_bases[runtime.actor.id],true,true,true)
		runtime.apply_rig_attachment()
	if not exporting: _sync_particle_seeks()
	if not exporting:
		var editor_camera := get_node_or_null("../../../../World/SubViewport/Freecam/Head/Camera3D") as Camera3D
		if editor_camera != null and not editor_camera.is_current(): editor_camera.make_current()
	_update_camera_overlays()


func _update_camera_overlays() -> void:
	for index in model.actors.size():
		if model.actors[index].type_id != &"camera_3d": continue
		var runtime := _runtime_for_clip(model.clips[index].id)
		if runtime != null and runtime.has_method("update_camera_overlay"):
			runtime.update_camera_overlay()


func _sync_particle_seeks() -> void:
	for index in model.actors.size():
		var actor := model.actors[index]
		if actor.type_id not in [&"particles_2d", &"particles_3d"]: continue
		var clip := model.clips[index]
		var runtime := _runtime_for_clip(clip.id)
		if runtime == null: continue
		var particle: Node = runtime.get("particles_2d") if actor.type_id == &"particles_2d" else runtime.get("content")
		if particle == null or not particle is GPUParticles2D and not particle is GPUParticles3D: continue
		var active_now := runtime.active and bool(particle.get("emitting"))
		if not active_now:
			_particle_seek_states.erase(clip.id)
			continue
		if playing:
			particle.set("speed_scale", 1.0)
			_particle_seek_states.erase(clip.id)
			continue
		var local_time := maxf(0.0, clip.local_time(canvas.playhead))
		var signature := int(runtime.get("_particle_settings_hash"))
		var previous: Dictionary = _particle_seek_states.get(clip.id, {})
		particle.set("speed_scale", 0.0)
		if previous.get("instance", -1) == particle.get_instance_id() \
				and is_equal_approx(float(previous.get("time", -1.0)), local_time) \
				and previous.get("settings", -1) == signature:
			continue
		particle.restart()
		var lifetime := maxf(0.05, float(particle.get("lifetime")))
		var seek_time := local_time if bool(particle.get("one_shot")) else fmod(local_time, lifetime * 2.0)
		if seek_time > 0.0 and particle.has_method("request_particles_process"):
			particle.call("request_particles_process", seek_time)
		_particle_seek_states[clip.id] = {"instance": particle.get_instance_id(),
			"time": local_time, "settings": signature}


func _apply_remote_transforms() -> void:
	for index in model.actors.size():
		var remote := model.actors[index]
		if remote.type_id != &"remote_transform" or not model.clips[index].contains_time(canvas.playhead):
			continue
		var target := model.actor_for_id(str(remote.get_value(&"remote_actor", "")))
		if target == null or target == remote:
			continue
		var source_runtime := _runtime_for_clip(model.clips[index].id)
		var target_clip := model.clip_for_actor_id(target.id)
		var target_runtime := _runtime_for_clip(target_clip.id) if target_clip != null else null
		if source_runtime == null or target_runtime == null or not source_runtime.supports_remote_transform() or not target_runtime.supports_remote_transform():
			continue
		target_runtime.apply_remote_transform(source_runtime.remote_transform(),
			remote.get_value(&"set_position", true), remote.get_value(&"set_rotation", true),
			remote.get_value(&"set_scale", true))


func _actor_depth(actor: ActorData) -> int:
	var depth := 0
	var parent := model.actor_for_id(actor.parent_id)
	var visited: Dictionary = {}
	while parent != null and not visited.has(parent.id):
		visited[parent.id] = true
		depth += 1
		parent = model.actor_for_id(parent.parent_id)
	return depth


var _ui_state_save_timer: Timer
var _ui_state_save_project: Project

func _flush_ui_state_save() -> void:
	if _ui_state_save_project != null and not _ui_state_save_project.resource_path.is_empty():
		FileOperations.save_resource(_ui_state_save_project)
	_ui_state_save_project = null

func _schedule_ui_state_save() -> void:
	if StaticData.loaded_project == null or StaticData.loaded_project.resource_path.is_empty():
		return
	if _ui_state_save_project != null and _ui_state_save_project != StaticData.loaded_project:
		_flush_ui_state_save()
	_ui_state_save_project = StaticData.loaded_project
	if not is_instance_valid(_ui_state_save_timer):
		_ui_state_save_timer = Timer.new()
		_ui_state_save_timer.one_shot = true
		add_child(_ui_state_save_timer)
		_ui_state_save_timer.timeout.connect(_flush_ui_state_save)
	_ui_state_save_timer.start(0.35)


func _input(event: InputEvent) -> void:
	# The older filesystem/viewport use their own focus tracker. Clear it when
	# interacting here so their global shortcuts cannot also delete or undo files.
	if event is InputEventMouseButton and event.pressed and get_global_rect().has_point(event.position):
		FocusableKeyInput.current_focused_instance = null


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if is_instance_valid(FocusableKeyInput.current_focused_instance):
		return
	var focused := get_viewport().gui_get_focus_owner()
	var owns_focus := focused != null and (is_ancestor_of(focused) or (is_instance_valid(inspector) and inspector.is_ancestor_of(focused)))
	if not owns_focus or focused is LineEdit or focused is TextEdit:
		return
	handle_actor_shortcut(event, focused == canvas)


func handle_actor_shortcut(event: InputEventKey, selection_shortcuts: bool = true) -> bool:
	if not event.pressed or event.echo:
		return false
	if event.is_action_pressed("redo"):
		redo()
	elif event.is_action_pressed("undo"):
		undo()
	elif event.keycode == KEY_SPACE:
		toggle_playback()
	elif event.keycode == KEY_R and not event.ctrl_pressed:
		toggle_recording()
	elif event.keycode == KEY_B and not event.ctrl_pressed:
		split_button.button_pressed = not split_button.button_pressed
	elif event.keycode == KEY_V and not event.ctrl_pressed:
		split_button.button_pressed = false
	elif event.keycode == KEY_A and event.ctrl_pressed and selection_shortcuts:
		model.select_all()
	elif event.keycode == KEY_A and event.shift_pressed and selection_shortcuts:
		actor_picker.open(model.selected_layer, canvas.playhead)
	elif event.keycode == KEY_LEFT and event.alt_pressed and not model.focused_actor_id.is_empty():
		canvas.cancel_drag()
		model.focus_parent()
	elif event.keycode == KEY_HOME and event.alt_pressed and not model.focused_actor_id.is_empty():
		canvas.cancel_drag()
		model.leave_actor_focus()
	elif event.keycode == KEY_F and not event.ctrl_pressed and not event.alt_pressed and not model.selected_ids.is_empty():
		focus_selected_actor()
	elif event.keycode == KEY_D and event.ctrl_pressed and not model.selected_ids.is_empty():
		duplicate_selected()
	elif event.keycode == KEY_C and event.ctrl_pressed and not model.selected_ids.is_empty():
		copy_selected()
	elif event.keycode == KEY_V and event.ctrl_pressed and not _actor_clipboard.is_empty():
		paste_copied(false, canvas.playhead, model.selected_layer)
	elif event.keycode == KEY_P and event.shift_pressed:
		unparent_selected()
	elif event.keycode == KEY_P and model.selected_ids.size() > 1:
		parent_selected()
	elif event.keycode in [KEY_DELETE, KEY_BACKSPACE] or event.is_action_pressed("delete"):
		delete_selected()
	else:
		return false
	get_viewport().set_input_as_handled()
	return true


func _refresh() -> void:
	if canvas == null or h_scroll == null:
		return
	model.validate_focus()
	var restored: Dictionary = {}
	var section_changed := _displayed_section_id != model.selected_section_id
	if section_changed:
		if not _displayed_section_id.is_empty():
			_timeline_section_states[_displayed_section_id] = {"x": canvas.scroll_time, "y": canvas.scroll_rows,
				"zoom_x": canvas.pixels_per_second, "zoom_y": canvas.row_height, "cursor": canvas.playhead,
				"snap": canvas.snap_enabled}
		restored = _timeline_section_states.get(model.selected_section_id, {})
		if not restored.is_empty():
			canvas.pixels_per_second = float(restored.zoom_x)
			canvas.row_height = float(restored.zoom_y)
			canvas.playhead = float(restored.cursor)
			canvas.snap_enabled = bool(restored.snap)
			x_zoom.set_value_no_signal(canvas.pixels_per_second)
			y_zoom.set_value_no_signal(canvas.row_height)
			snap_button.set_pressed_no_signal(canvas.snap_enabled)
	if section_changed or _displayed_focus_id != model.focused_actor_id:
		_displayed_section_id = model.selected_section_id
		_displayed_focus_id = model.focused_actor_id
		canvas.cancel_drag()
		if section_changed and restored.is_empty():
			h_scroll.value = 0.0
			v_scroll.value = 0.0
	var clip := model.selected_clip()
	start_input.editable = clip != null
	end_input.editable = clip != null
	start_input.set_value_no_signal(clip.start_time if clip != null else 0.0)
	end_input.set_value_no_signal(clip.start_time + clip.duration if clip != null else 0.0)
	undo_button.disabled = not model.history.has_undo()
	redo_button.disabled = not model.history.has_redo()
	undo_button.tooltip_text = "Undo " + model.history.get_current_action_name() if model.history.has_undo() else "Nothing to undo"
	time_label.text = "  ◷  %02d:%05.2f  " % [int(canvas.playhead / 60.0), fmod(canvas.playhead, 60.0)]
	var end_time := maxf(60.0, canvas.playhead + 15.0)
	for item in model.visible_clips():
		end_time = maxf(end_time, item.start_time + item.duration + 15.0)
	for index in model.clips.size():
		if model.hidden_clip_obstructs_view(index):
			end_time = maxf(end_time, model.clips[index].start_time + model.clips[index].duration + 15.0)
	h_scroll.page = maxf(1.0, (canvas.size.x - ActorTimelineCanvas.LABEL_WIDTH) / canvas.pixels_per_second)
	h_scroll.max_value = maxf(end_time, h_scroll.page)
	v_scroll.page = maxf(1.0, canvas.size.y - ActorTimelineCanvas.HEADER)
	v_scroll.max_value = maxf(v_scroll.page, canvas.display_layer_count() * canvas.row_height)
	if not canvas.recording_preview.is_empty():
		v_scroll.max_value = maxf(v_scroll.max_value, (int(canvas.recording_preview.layer) + 2) * canvas.row_height)
	if not restored.is_empty():
		h_scroll.value = float(restored.x)
		v_scroll.value = float(restored.y)
		canvas.scroll_time = h_scroll.value
		canvas.scroll_rows = v_scroll.value
	if section_changed:
		_evaluate_runtimes()
	canvas.queue_redraw()
	model.playhead_time = canvas.playhead
	if keyframe_editor != null and keyframe_editor.lanes != null:
		keyframe_editor.lanes.queue_redraw()
		keyframe_editor.ruler.queue_redraw()
	if is_instance_valid(inspector):
		inspector.refresh()
	_update_breadcrumbs()
	_update_idle_hint()


func _update_idle_hint() -> void:
	if canvas == null:
		return
	var shortcuts := PackedStringArray()
	shortcuts.append("Space Pause" if playing else "Space Play")
	shortcuts.append("R Record mic")
	shortcuts.append("V Select tool" if canvas.split_tool else "B Split tool")
	if model.selected_ids.is_empty():
		shortcuts.append("Shift+A Add actor")
		shortcuts.append("Drag empty area Box select")
		if not model.clips.is_empty():
			shortcuts.append("Ctrl+A Select all")
	else:
		shortcuts.append("Delete/Backspace Delete")
		shortcuts.append("Ctrl+D Duplicate")
		shortcuts.append("Ctrl+C Copy")
		shortcuts.append("F Go up one level" if model.selected_actor() != null and model.selected_actor().id == model.focused_actor_id else "F Focus primary actor")
		if model.selected_ids.size() > 1:
			shortcuts.append("P Parent to primary")
		var can_unparent := false
		for actor in model.selected_actors():
			if not actor.parent_id.is_empty():
				can_unparent = true
				break
		if can_unparent:
			shortcuts.append("Shift+P Unparent")
		if model.selected_ids.size() < model.clips.size():
			shortcuts.append("Ctrl+A Select all")
	if not model.focused_actor_id.is_empty():
		shortcuts.append("Alt+← Back to parent")
		shortcuts.append("Alt+Home Section view")
	if not _actor_clipboard.is_empty():
		shortcuts.append("Ctrl+V Paste at playhead")
	if model.history.has_undo():
		shortcuts.append("Ctrl+Z Undo")
	if model.history.has_redo():
		shortcuts.append("Ctrl+Shift+Z Redo")
	hints.set_idle("  •  ".join(shortcuts))


func _box(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	return style


func _style_context_menu() -> void:
	context_menu.min_size = Vector2i(245, 0)
	var panel := _box(Color("17212d"), Color("4b6075"))
	panel.set_corner_radius_all(9)
	panel.shadow_color = Color(0, 0, 0, 0.38)
	panel.shadow_size = 8
	panel.content_margin_left = 7
	panel.content_margin_right = 7
	panel.content_margin_top = 7
	panel.content_margin_bottom = 7
	context_menu.add_theme_stylebox_override("panel", panel)
	var hover := _box(Color("294c54"), Color("5fa99a"))
	hover.set_corner_radius_all(5)
	hover.content_margin_top = 5
	hover.content_margin_bottom = 5
	context_menu.add_theme_stylebox_override("hover", hover)
	context_menu.add_theme_color_override("font_color", Color("dce8f3"))
	context_menu.add_theme_color_override("font_hover_color", Color("ffffff"))
	context_menu.add_theme_color_override("font_disabled_color", Color("7f95a8"))
	context_menu.add_theme_color_override("font_separator_color", Color("7890a5"))
	context_menu.add_theme_constant_override("item_start_padding", 12)
	context_menu.add_theme_constant_override("item_end_padding", 16)
	context_menu.add_theme_constant_override("v_separation", 5)
	context_menu.add_theme_constant_override("separator_height", 10)
	context_menu.add_theme_constant_override("icon_max_width", 20)
	context_menu.add_theme_font_size_override("font_size", 13)


func _apply_theme() -> void:
	theme = Theme.new()
	theme.default_font_size = 13
	add_theme_constant_override("separation", 3)
	for type in ["Button", "MenuButton"]:
		theme.set_stylebox("normal", type, _box(Color("2a3849"), Color("42546a")))
		theme.set_stylebox("hover", type, _box(Color("3a5065"), Color("7493ad")))
		theme.set_stylebox("pressed", type, _box(Color("214f50"), Color("80dbc4")))
		theme.set_stylebox("disabled", type, _box(Color("232c38"), Color("303e4e")))
		var focus := _box(Color.TRANSPARENT, Color("80dbc4"))
		focus.draw_center = false
		theme.set_stylebox("focus", type, focus)
		theme.set_color("font_color", type, Color("e3edf7"))
		theme.set_color("font_disabled_color", type, Color("65788d"))
	theme.set_stylebox("normal", "LineEdit", _box(Color("151f2b"), Color("42546a")))
	theme.set_color("font_color", "Label", Color("b9cbdc"))
