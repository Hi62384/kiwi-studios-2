class_name ActorKeyframeEditor
extends Control

signal close_requested

var model: ActorTimeline
var timeline: ActorTimelineCanvas
var hints: InteractionHints
var lanes: ActorKeyframeCanvas
var details: HBoxContainer
var heading: Label
var ruler: ActorKeyframeCanvas
var track_scroll: ScrollContainer
var detail_scroll: ScrollContainer
var header_panel: PanelContainer
var _actor: ActorData
var _editing := false
var _before: Array[ActorAnimationTrack] = []
var _details_signature: String = ""
var _detail_updaters: Array[Callable] = []
var curve_popup: PopupPanel

func _ready() -> void:
	add_to_group("actor_keyframe_editors")
	var panel := PanelContainer.new()
	header_panel = panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18232f")
	style.set_corner_radius_all(6)
	style.content_margin_left = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	heading = Label.new()
	var header := HBoxContainer.new()
	panel.add_child(header)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.clip_text = true
	header.add_child(heading)
	var close := Button.new()
	close.text = "← Actors"
	close.tooltip_text = "Return to actors; keep all keyframes"
	header.add_child(close)
	close.pressed.connect(func(): close_requested.emit())
	ruler = ActorKeyframeCanvas.new()
	ruler.model = model
	ruler.timeline = timeline
	ruler.ruler_only = true
	ruler.clip_contents = true
	add_child(ruler)
	track_scroll = ScrollContainer.new()
	track_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	track_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	track_scroll.clip_contents = true
	add_child(track_scroll)
	lanes = ActorKeyframeCanvas.new()
	lanes.model = model
	lanes.timeline = timeline
	lanes.show_ruler = false
	lanes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	track_scroll.add_child(lanes)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	detail_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.clip_contents = true
	detail_scroll.tooltip_text = "Scroll horizontally to reach more keyframe properties"
	detail_scroll.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			detail_scroll.scroll_horizontal += -80 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 80
			detail_scroll.accept_event())
	add_child(detail_scroll)
	details = HBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(details)
	lanes.selection_changed.connect(_build_details)
	lanes.move_requested.connect(_move_keys)
	lanes.move_preview_requested.connect(func(ids: Array[String], delta: float):
		var plan := _key_move_plan(ids, delta, _before)
		if plan.valid: model.restore_animation(_actor, plan.tracks))
	lanes.delete_requested.connect(func(ids: Array[String]): model.delete_keyframes(_actor, ids))
	lanes.interaction_changed.connect(func(text: String):
		if text.begins_with("Esc cancels keyframe drag"):
			_begin_edit()
		elif text.is_empty() and _editing:
			_cancel_edit()
		if hints != null:
			if text.is_empty(): hints.end(lanes)
			else: hints.begin(lanes, text))
	lanes.focus_entered.connect(func():
		if hints != null: hints.begin(self, "Click / Shift-click keys • Drag moves • Delete removes • Ctrl+A selects keys • ←/→ nudges"))
	lanes.focus_exited.connect(func():
		if hints != null: hints.end(self))
	model.changed.connect(refresh)
	clip_contents = true
	resized.connect(_layout_editor)
	_layout_editor()
	refresh()

func _layout_editor() -> void:
	if detail_scroll == null:
		return
	# Only the middle scrolls. These regions are bounded by the existing timeline,
	# never by the number of tracks or the size of a selected value's controls.
	header_panel.visible = false
	var header_size := header_panel.get_combined_minimum_size().y if header_panel.visible else 0.0
	var ruler_size := minf(ActorKeyframeCanvas.HEADER, maxf(0, size.y - 30))
	var detail_size := detail_scroll.get_combined_minimum_size().y
	header_panel.position = Vector2.ZERO
	header_panel.size = Vector2(size.x, header_size)
	ruler.position = Vector2(0, header_size)
	ruler.size = Vector2(size.x, ruler_size)
	track_scroll.position = Vector2(0, header_size + ruler_size)
	track_scroll.size = Vector2(size.x, maxf(0, size.y - header_size - ruler_size - detail_size))
	detail_scroll.position = Vector2(0, size.y - detail_size)
	detail_scroll.size = Vector2(size.x, detail_size)

func refresh() -> void:
	var actor := model.selected_actor()
	if actor != _actor:
		if is_instance_valid(curve_popup): curve_popup.hide()
		cancel_interaction()
		_actor = actor
		lanes.selected_keys.clear()
	lanes.actor = _actor
	ruler.actor = _actor
	for index in range(lanes.selected_keys.size() - 1, -1, -1):
		if _actor == null or model.keyframe_for_id(_actor, lanes.selected_keys[index]) == null:
			lanes.selected_keys.remove_at(index)
	heading.text = "KEYFRAMES  /  " + _actor.display_name if _actor != null else "KEYFRAMES  /  Select an actor"
	lanes.custom_minimum_size.y = maxf(lanes.track_height(), _actor.animation_tracks.size() * lanes.track_height()) if _actor != null else lanes.track_height()
	lanes.queue_redraw()
	ruler.queue_redraw()
	if not _editing:
		_build_details()

func cancel_interaction() -> void:
	if lanes == null:
		return
	lanes.cancel_drag()
	ruler.cancel_drag()
	if _editing:
		_cancel_edit()
	if hints != null:
		hints.end(lanes)
		hints.end(self)

func _move_keys(ids: Array[String], timeline_delta: float) -> void:
	var before := _before if _editing else model.animation_snapshot(_actor)
	var plan := _key_move_plan(ids, timeline_delta, before)
	_editing = false
	if not plan.valid:
		model.restore_animation(_actor, before)
		return
	model.commit_animation_edit(_actor, before, plan.tracks, "Move Keyframes")
	_before = []

func _key_move_plan(ids: Array[String], timeline_delta: float, source: Array[ActorAnimationTrack]) -> Dictionary:
	var after: Array[ActorAnimationTrack] = []
	for track in source:
		after.append(track.copy_track())
	var clip := model.clip_for_actor_id(_actor.id)
	for track in after:
		for key in track.keys:
			if ids.has(key.id):
				key.time += timeline_delta * clip.playback_speed
		track.sort_keys()
		for index in range(1, track.keys.size()):
			if absf(track.keys[index].time - track.keys[index - 1].time) < 0.00001:
				return {"valid": false, "tracks": after}
	return {"valid": true, "tracks": after}

func _build_details() -> void:
	var primary: String = lanes.selected_keys.back() if not lanes.selected_keys.is_empty() else ""
	var selected_track := model.track_for_key(_actor, primary) if _actor != null else null
	var signature := (_actor.id if _actor != null else "") + "|" + primary + "|" + str(selected_track.component if selected_track != null else -1)
	if signature == _details_signature and details.get_child_count() > 0:
		if not _editing:
			for update in _detail_updaters:
				update.call()
		return
	_details_signature = signature
	_detail_updaters.clear()
	for child in details.get_children():
		details.remove_child(child)
		child.queue_free()
	if _actor == null or lanes.selected_keys.is_empty():
		var help := Label.new()
		help.text = "Select an actor and add keys using property diamonds." if _actor == null or _actor.animation_tracks.is_empty() else "Click a key to edit it. Shift-click to move multiple keys."
		help.autowrap_mode = TextServer.AUTOWRAP_OFF
		help.custom_minimum_size.x = 240
		help.modulate = Color("819db4")
		details.add_child(help)
		call_deferred("_layout_editor")
		return
	var key := model.keyframe_for_id(_actor, lanes.selected_keys.back())
	if key == null:
		return
	var clip := model.clip_for_actor_id(_actor.id)
	_number("Time (s)", clip.start_time + (key.time - clip.source_offset) / clip.playback_speed,
		func(value: float): return {"time": clip.local_time(value)})
	_add_curve_button(key)
	if selected_track.component >= 0 or ActorTimeline.component_count(key.value) > 0:
		var separate := Button.new()
		separate.text = "Unseparate" if selected_track.component >= 0 else "Separate"
		separate.tooltip_text = "Join components at their combined key times" if selected_track.component >= 0 else "Give each component its own independently editable track"
		details.add_child(separate)
		separate.pressed.connect(func():
			if selected_track.component >= 0: model.unseparate_track(_actor, selected_track.path)
			else: model.separate_track(_actor, selected_track.path))
	match typeof(key.value):
		TYPE_FLOAT, TYPE_INT:
			_number("Value", float(key.value), func(value: float): return {"value": int(round(value)) if key.value is int else value})
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I:
			var count := 2 if typeof(key.value) in [TYPE_VECTOR2, TYPE_VECTOR2I] else (3 if typeof(key.value) in [TYPE_VECTOR3, TYPE_VECTOR3I] else 4)
			for axis in count:
				_number(["X", "Y", "Z", "W"][axis], key.value[axis], func(value: float):
					var current := model.keyframe_for_id(_actor, key.id)
					var vector: Variant = current.value
					vector[axis] = int(round(value)) if typeof(vector) in [TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I] else value
					return {"value": vector})
		TYPE_BOOL:
			var toggle := CheckButton.new()
			toggle.text = "Value"
			toggle.button_pressed = key.value
			details.add_child(toggle)
			toggle.toggled.connect(func(value: bool): _change_keys(key.id, {"value": value}))
			_detail_updaters.append(func():
				var current := model.keyframe_for_id(_actor, key.id)
				if current != null: toggle.set_pressed_no_signal(current.value))
		TYPE_STRING, TYPE_STRING_NAME:
			var text := LineEdit.new()
			text.custom_minimum_size.x = 180
			text.text = str(key.value)
			details.add_child(text)
			text.text_submitted.connect(func(value: String):
				_change_keys(key.id, {"value": StringName(value) if key.value is StringName else value}))
			_detail_updaters.append(func():
				var current := model.keyframe_for_id(_actor, key.id)
				if current != null and not text.has_focus(): text.text = str(current.value))
		TYPE_COLOR:
			var color := LiveColorPickerButton.new()
			color.color = key.value
			details.add_child(color)
			color.interaction_started.connect(_begin_edit)
			color.preview_changed.connect(func(value: Color): _change_keys(key.id, {"value": value}, true))
			color.drag_committed.connect(func(_original: Color, _value: Color): _finish_edit())
			color.drag_cancelled.connect(func(_original: Color): _cancel_edit())
			_detail_updaters.append(func():
				var current := model.keyframe_for_id(_actor, key.id)
				if current != null: color.set_color_silent(current.value))
			color.interaction_started.connect(func():
				if hints != null: hints.begin(color, "Esc cancels keyframe color drag"))
			color.interaction_ended.connect(func():
				if hints != null: hints.end(color))
	var remove := Button.new()
	remove.text = "Delete"
	remove.tooltip_text = "Delete selected keyframes"
	details.add_child(remove)
	remove.pressed.connect(func(): model.delete_keyframes(_actor, lanes.selected_keys.duplicate()))
	_layout_editor()
	call_deferred("_layout_editor")

func _add_curve_button(key: ActorKeyframe) -> void:
	var button := Button.new()
	button.text = "Value curve"
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.x = 158
	button.tooltip_text = "Edit easing from this keyframe to the next keyframe on this track"
	details.add_child(button)
	var preview := ActorValueCurve.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(preview)
	preview.position = Vector2(90, 2)
	preview.size = Vector2(62, 22)
	var update := func():
		var current := model.keyframe_for_id(_actor, key.id)
		if current == null: return
		preview.curve = ActorValueCurve.for_key(current)
		preview.stepped = current.interpolation == ActorKeyframe.Interpolation.STEP
		preview.queue_redraw()
	update.call()
	_detail_updaters.append(update)
	button.pressed.connect(func(): _open_curve_menu(key.id))

func _open_curve_menu(key_id: String) -> void:
	if is_instance_valid(curve_popup):
		curve_popup.queue_free()
	var key := model.keyframe_for_id(_actor, key_id)
	if key == null: return
	curve_popup = PopupPanel.new()
	add_child(curve_popup)
	var content := VBoxContainer.new()
	curve_popup.add_child(content)
	var title := Label.new()
	title.text = "VALUE CURVE  ·  easing to the next key"
	content.add_child(title)
	var graph := ActorValueCurve.new()
	graph.editable = true
	graph.custom_minimum_size = Vector2(420, 230)
	graph.curve = ActorValueCurve.for_key(key)
	graph.stepped = key.interpolation == ActorKeyframe.Interpolation.STEP
	content.add_child(graph)
	graph.edit_started.connect(_begin_edit)
	graph.preview_changed.connect(func(value: Curve): _change_keys(key_id, {"value_curve": value}, true))
	graph.edit_committed.connect(_finish_edit)
	graph.edit_cancelled.connect(_cancel_edit)
	curve_popup.popup_hide.connect(func(): graph.cancel_edit())
	var target_actor := _actor
	var sync_curve := func():
		if _editing or not is_instance_valid(graph): return
		var current := model.keyframe_for_id(target_actor, key_id)
		if current == null: return
		graph.curve = ActorValueCurve.for_key(current)
		graph.stepped = current.interpolation == ActorKeyframe.Interpolation.STEP
		graph.queue_redraw()
	model.changed.connect(sync_curve)
	curve_popup.tree_exiting.connect(func():
		if model.changed.is_connected(sync_curve): model.changed.disconnect(sync_curve))
	var presets := HFlowContainer.new()
	content.add_child(presets)
	var reset_tangents := Button.new()
	reset_tangents.text = "Reset tangents"
	reset_tangents.tooltip_text = "Reset both tangents of the selected point to straight segments"
	var reset_row := HBoxContainer.new()
	content.add_child(reset_row)
	reset_row.add_child(reset_tangents)
	reset_tangents.add_theme_color_override("font_color", Color("ffce80"))
	reset_tangents.text = "↺  Reset selected point's tangents"
	reset_tangents.pressed.connect(graph.reset_tangents)
	var parameter_row := HBoxContainer.new()
	content.add_child(parameter_row)
	var parameter_label := Label.new()
	parameter_row.add_child(parameter_label)
	var parameter := DragNumber.new()
	parameter.custom_minimum_size.x = 100
	parameter_row.add_child(parameter)
	var setting := {"name": key.curve_template}
	var configure := func(name: String, amount: float):
		setting.name = name
		parameter_row.visible = name in ["Ease", "Smoothstep", "Sin wave", "Step"]
		parameter_label.text = "Frequency" if name == "Sin wave" else ("Steps" if name == "Step" else "Adjustment")
		parameter.step = 1 if name == "Step" else 0.01
		parameter.min_value = -10 if name == "Ease" else (1 if name == "Step" else (0.1 if name == "Sin wave" else 0))
		parameter.max_value = 10 if name == "Ease" else (64 if name == "Step" else (16 if name == "Sin wave" else 1))
		parameter.allow_lesser = name == "Ease"
		parameter.allow_greater = name == "Ease"
		parameter.set_value_no_signal(amount)
	configure.call(key.curve_template, key.curve_adjustment)
	var apply_template := func(amount: float, preview_edit: bool):
		graph.curve = ActorValueCurve.template(setting.name, amount)
		graph.stepped = false
		_change_keys(key_id, {"value_curve": graph.curve, "curve_template": setting.name, "curve_adjustment": amount}, preview_edit)
		graph.queue_redraw()
	parameter.interaction_started.connect(_begin_edit)
	parameter.preview_changed.connect(func(amount: float): apply_template.call(amount, true))
	parameter.drag_committed.connect(func(_amount: float): _finish_edit())
	parameter.drag_cancelled.connect(_cancel_edit)
	parameter.value_changed.connect(func(amount: float): apply_template.call(amount, false))
	var sync_parameter := func():
		if _editing: return
		var current := model.keyframe_for_id(target_actor, key_id)
		if current != null: configure.call(current.curve_template, current.curve_adjustment)
	model.changed.connect(sync_parameter)
	curve_popup.tree_exiting.connect(func():
		if model.changed.is_connected(sync_parameter): model.changed.disconnect(sync_parameter))
	for preset_name in ["Linear", "Ease", "Smoothstep", "Sin wave", "Step"]:
		var choice := Button.new()
		choice.text = preset_name
		presets.add_child(choice)
		choice.pressed.connect(func():
			var amount := 0.0 if preset_name == "Linear" else (4.0 if preset_name == "Step" else 1.0)
			configure.call(preset_name, amount)
			apply_template.call(amount, false))
	var help := Label.new()
	help.text = "Select a point · Drag gold handles to bend the curve\nClick adds points · Right-click removes points · Esc cancels drag"
	help.add_theme_font_size_override("font_size", 10)
	content.add_child(help)
	curve_popup.popup_centered()

func _number(label: String, value: float, make_changes: Callable) -> void:
	var box := HBoxContainer.new()
	details.add_child(box)
	var title := Label.new()
	title.text = "Time" if label == "Time (s)" else ("Ease" if label == "Attenuation" else label)
	title.tooltip_text = label
	title.add_theme_font_size_override("font_size", 10)
	box.add_child(title)
	var input := DragNumber.new()
	input.allow_greater = true
	input.allow_lesser = true
	input.step = 0.01
	input.custom_minimum_size.x = 68
	input.set_value_no_signal(value)
	box.add_child(input)
	var key_id: String = lanes.selected_keys.back()
	_detail_updaters.append(func():
		var current := model.keyframe_for_id(_actor, key_id)
		if current == null:
			return
		var sampled := 0.0
		if label == "Time (s)":
			var clip := model.clip_for_actor_id(_actor.id)
			sampled = clip.start_time + (current.time - clip.source_offset) / clip.playback_speed
		elif label == "Attenuation": sampled = current.attenuation
		elif label == "Value": sampled = float(current.value)
		else: sampled = current.value[["X", "Y", "Z", "W"].find(label)]
		input.set_value_no_signal(sampled))
	input.interaction_started.connect(_begin_edit)
	input.preview_changed.connect(func(number: float): _change_keys(key_id, make_changes.call(number), true, ["X", "Y", "Z", "W"].find(label)))
	input.drag_committed.connect(func(_number: float): _finish_edit())
	input.drag_cancelled.connect(_cancel_edit)
	input.value_changed.connect(func(number: float): _change_keys(key_id, make_changes.call(number), false, ["X", "Y", "Z", "W"].find(label)))
	input.interaction_started.connect(func():
		if hints != null: hints.begin(input, "Esc cancels keyframe property drag"))
	input.interaction_ended.connect(func():
		if hints != null: hints.end(input))

func _change_keys(primary_id: String, changes: Dictionary, preview: bool = false, axis: int = -1) -> void:
	var before := _before if _editing else model.animation_snapshot(_actor)
	var after: Array[ActorAnimationTrack] = []
	var primary: ActorKeyframe
	for track in before:
		for key in track.keys:
			if key.id == primary_id: primary = key
	if primary == null: return
	var ids := lanes.selected_keys.duplicate()
	if not ids.has(primary_id): ids.assign([primary_id])
	for track in before:
		var copy := track.copy_track()
		for key in copy.keys:
			if not ids.has(key.id): continue
			if changes.has("time"): key.time += float(changes.time) - primary.time
			if changes.has("value"):
				var value: Variant = changes.value
				if axis >= 0:
					if typeof(key.value) != typeof(value): continue
					var combined: Variant = key.value
					combined[axis] = value[axis]
					key.value = combined
				elif typeof(key.value) == typeof(value): key.value = ActorData.copy_value(value)
				elif typeof(key.value) in [TYPE_INT, TYPE_FLOAT] and typeof(value) in [TYPE_INT, TYPE_FLOAT]:
					key.value = int(round(value)) if key.value is int else float(value)
			if changes.has("value_curve"):
				key.value_curve = changes.value_curve.duplicate() as Curve if changes.value_curve != null else null
				key.interpolation = ActorKeyframe.Interpolation.LINEAR
				key.curve_template = changes.get("curve_template", "")
			if changes.has("curve_adjustment"): key.curve_adjustment = changes.curve_adjustment
			if changes.has("interpolation"): key.interpolation = changes.interpolation
		copy.sort_keys()
		for index in range(1, copy.keys.size()):
			if absf(copy.keys[index].time - copy.keys[index - 1].time) < 0.00001: return
		after.append(copy)
	if preview: model.restore_animation(_actor, after)
	else: model.commit_animation_edit(_actor, before, after, "Change Selected Keyframes")

func _begin_edit() -> void:
	_editing = true
	_before = model.animation_snapshot(_actor)

func _finish_edit() -> void:
	if not _editing:
		return
	var after := model.animation_snapshot(_actor)
	_editing = false
	model.commit_animation_edit(_actor, _before, after, "Edit Keyframe")
	_before = []

func _cancel_edit() -> void:
	_editing = false
	model.restore_animation(_actor, _before)
	_before = []
