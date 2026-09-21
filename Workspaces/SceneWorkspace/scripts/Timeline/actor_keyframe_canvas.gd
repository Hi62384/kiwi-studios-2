class_name ActorKeyframeCanvas
extends Control

signal selection_changed
signal move_requested(ids: Array[String], timeline_delta: float)
signal move_preview_requested(ids: Array[String], timeline_delta: float)
signal delete_requested(ids: Array[String])
signal interaction_changed(text: String)

const ROW := 30.0
const HEADER := 56.0
var model: ActorTimeline
var timeline: ActorTimelineCanvas
var actor: ActorData
var selected_keys: Array[String] = []
var _dragging := false
var _drag_origin: float
var _delta := 0.0
var _original_times: Dictionary = {}
var overlay_mode := false
var overlay_path := PackedStringArray()
var _scrubbing := false
var _scrub_origin := 0.0
var show_ruler := true
var ruler_only := false
var box_selecting := false
var _box_start: Vector2
var _box_end: Vector2
var _box_base: Array[String] = []

func track_height() -> float:
	return timeline.row_height * ROW / ActorTimelineCanvas.ROW

func header_height() -> float:
	return HEADER if show_ruler else 0.0

func _selection_box() -> Rect2:
	return Rect2(_box_start, _box_end - _box_start).abs()

func _update_box(add: bool, subtract: bool) -> void:
	selected_keys.assign(_box_base if add or subtract else [])
	var tracks := displayed_tracks()
	for row in tracks.size():
		for key in tracks[row].keys:
			if _selection_box().has_point(key_position(key, row)):
				if subtract:
					selected_keys.erase(key.id)
				elif not selected_keys.has(key.id):
					selected_keys.append(key.id)
	selection_changed.emit()
	queue_redraw()

func displayed_tracks() -> Array[ActorAnimationTrack]:
	if actor == null:
		return []
	if not overlay_mode:
		return actor.animation_tracks
	var result: Array[ActorAnimationTrack] = []
	for track in actor.animation_tracks:
		if track.path == model.overlay_path: result.append(track)
	return result

func overlay_rect() -> Rect2:
	if actor == null:
		return Rect2()
	var index := model.clips.find(model.clip_for_actor_id(actor.id))
	return timeline.clip_rect(index) if index >= 0 and model.clip_is_visible(index) else Rect2()

func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func cancel_drag() -> void:
	if box_selecting:
		box_selecting = false
		selected_keys.assign(_box_base)
		selection_changed.emit()
		interaction_changed.emit("")
		queue_redraw()
	if _scrubbing:
		_scrubbing = false
		timeline.time_selected.emit(_scrub_origin)
	if not _dragging:
		return
	_dragging = false
	_delta = 0
	_original_times.clear()
	interaction_changed.emit("")
	queue_redraw()

func key_position(key: ActorKeyframe, row: int) -> Vector2:
	var clip := model.clip_for_actor_id(actor.id)
	var source_time: float = _original_times.get(key.id, key.time) if _dragging and selected_keys.has(key.id) else key.time
	var time := clip.start_time + (source_time - clip.source_offset) / clip.playback_speed
	if selected_keys.has(key.id) and _dragging:
		time += _delta
	return Vector2(ActorTimelineCanvas.LABEL_WIDTH + (time - timeline.scroll_time) * timeline.pixels_per_second,
		overlay_rect().position.y + overlay_rect().size.y * float(row + 1) / float(displayed_tracks().size() + 1) if overlay_mode else header_height() + row * track_height() + track_height() / 2)

func _get_tooltip(at_position: Vector2) -> String:
	if actor == null:
		return ""
	var tracks := displayed_tracks()
	for row in tracks.size():
		var track := tracks[row]
		if not overlay_mode and at_position.x < ActorTimelineCanvas.LABEL_WIDTH and int((at_position.y - header_height()) / track_height()) == row:
			return track.label + "\n" + " / ".join(track.path)
		for key in track.keys:
			if key_position(key, row).distance_to(at_position) < 10:
				return "%s\nValue: %s\nSource time: %.2fs" % [track.label, str(key.value), key.time]
	return ""

func _draw() -> void:
	if not overlay_mode:
		draw_rect(Rect2(Vector2.ZERO, size), Color("121b26"))
	if actor == null:
		return
	var font := ThemeDB.fallback_font
	if overlay_mode and not overlay_rect().has_area():
		return
	if not overlay_mode and show_ruler:
		_draw_ruler(font)
	var tracks: Array[ActorAnimationTrack] = []
	if not ruler_only:
		tracks = displayed_tracks()
	for row in tracks.size():
		var track := tracks[row]
		if not overlay_mode:
			draw_rect(Rect2(0, header_height() + row * track_height(), size.x, track_height()), Color("202d3a") if row % 2 == 0 else Color("192531"))
		for key in track.keys:
			var position := key_position(key, row)
			if position.x < ActorTimelineCanvas.LABEL_WIDTH or position.x > size.x:
				continue
			if overlay_mode and not overlay_rect().has_point(position):
				continue
			var radius := minf(6, track_height() * 0.4) if not overlay_mode else minf(6, overlay_rect().size.y / (tracks.size() + 1) * 0.4)
			var points := PackedVector2Array([position + Vector2(0, -radius), position + Vector2(radius, 0), position + Vector2(0, radius), position + Vector2(-radius, 0)])
			draw_colored_polygon(points, Color("ffce80") if selected_keys.has(key.id) else Color("72cfb8"))
		if not overlay_mode:
			draw_rect(Rect2(0, header_height() + row * track_height(), ActorTimelineCanvas.LABEL_WIDTH, track_height()), Color("17222e"))
			var label := track.label if not track.label.is_empty() else " / ".join(track.path)
			if track_height() >= 14:
				draw_string(font, Vector2(10, header_height() + row * track_height() + track_height() / 2 + 4), label, HORIZONTAL_ALIGNMENT_LEFT, ActorTimelineCanvas.LABEL_WIDTH - 20, 11, Color("c5d5e3"))
	var cursor_x := ActorTimelineCanvas.LABEL_WIDTH + (timeline.playhead - timeline.scroll_time) * timeline.pixels_per_second
	if not overlay_mode and cursor_x >= ActorTimelineCanvas.LABEL_WIDTH:
		draw_line(Vector2(cursor_x, 0), Vector2(cursor_x, size.y), Color("ffce80"), 1)
	if box_selecting:
		draw_rect(_selection_box(), Color(0.45, 0.81, 0.72, 0.18))
		draw_rect(_selection_box(), Color("72cfb8"), false, 1)

func _draw_ruler(font: Font) -> void:
	draw_rect(Rect2(0, 0, size.x, HEADER), Color("263545"))
	var step := maxf(1, ceilf(55.0 / timeline.pixels_per_second))
	var time := floorf(timeline.scroll_time / step) * step
	while time < timeline.scroll_time + size.x / timeline.pixels_per_second:
		var x := ActorTimelineCanvas.LABEL_WIDTH + (time - timeline.scroll_time) * timeline.pixels_per_second
		if x >= ActorTimelineCanvas.LABEL_WIDTH:
			draw_string(font, Vector2(x + 3, 17), "%.0fs" % time, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("c5d5e3"))
			draw_line(Vector2(x, 22), Vector2(x, size.y), Color(0.4, 0.55, 0.65, 0.15))
		time += step
	var clip := model.clip_for_actor_id(actor.id)
	var x := ActorTimelineCanvas.LABEL_WIDTH + (clip.start_time - timeline.scroll_time) * timeline.pixels_per_second
	var rect := Rect2(x, 27, clip.duration * timeline.pixels_per_second, 24).intersection(Rect2(ActorTimelineCanvas.LABEL_WIDTH, 27, maxf(size.x - ActorTimelineCanvas.LABEL_WIDTH, 0), 24))
	if rect.has_area():
		draw_style_box(_clip_style(), rect)
		draw_string(font, rect.position + Vector2(6, 16), "%s  ·  %.2fs" % [actor.display_name, clip.duration], HORIZONTAL_ALIGNMENT_LEFT, maxf(rect.size.x - 12, 0), 11, Color("daf6ed"))
	draw_rect(Rect2(0, 0, ActorTimelineCanvas.LABEL_WIDTH, HEADER), Color("17222e"))
	draw_string(font, Vector2(10, 18), "TIME / ACTOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("72cfb8"))

func _clip_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("28554f")
	style.border_color = Color("72cfb8")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style

func _gui_input(event: InputEvent) -> void:
	if actor == null:
		return
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_DELETE, KEY_BACKSPACE] and not selected_keys.is_empty():
			delete_requested.emit(selected_keys.duplicate())
			selected_keys.clear()
			selection_changed.emit()
			accept_event()
		elif event.keycode == KEY_A and event.ctrl_pressed:
			selected_keys.clear()
			for track in displayed_tracks():
				for key in track.keys:
					selected_keys.append(key.id)
			selection_changed.emit()
			queue_redraw()
			accept_event()
		elif event.keycode in [KEY_LEFT, KEY_RIGHT] and not selected_keys.is_empty():
			move_requested.emit(selected_keys.duplicate(), (1 if event.keycode == KEY_RIGHT else -1) * (1.0 if event.shift_pressed else 0.1))
			accept_event()
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	grab_focus()
	if not overlay_mode and show_ruler and event.position.y < HEADER and event.position.x >= ActorTimelineCanvas.LABEL_WIDTH:
		if timeline.split_tool and event.position.y >= 27:
			model.split_clip(model.clip_for_actor_id(actor.id).id, timeline.time_at(event.position.x))
			accept_event()
			return
		_scrubbing = true
		_scrub_origin = timeline.playhead
		timeline.time_selected.emit(timeline.snapped_playhead(timeline.time_at(event.position.x), event.shift_pressed, true))
		accept_event()
		return
	var hit := ""
	var hit_distance := 10.0
	if overlay_mode: hit_distance = minf(10, overlay_rect().size.y / (displayed_tracks().size() + 1) * 0.5)
	var tracks := displayed_tracks()
	for row in tracks.size():
		for key in tracks[row].keys:
			var distance := key_position(key, row).distance_to(event.position)
			if event.position.x >= ActorTimelineCanvas.LABEL_WIDTH and distance < hit_distance:
				hit = key.id
				hit_distance = distance
	if hit.is_empty():
		if not overlay_mode and not ruler_only and event.position.x >= ActorTimelineCanvas.LABEL_WIDTH:
			box_selecting = true
			_box_start = event.position
			_box_end = event.position
			_box_base.assign(selected_keys)
			_update_box(event.shift_pressed, event.ctrl_pressed)
			interaction_changed.emit("Esc cancels box select • Shift adds • Ctrl removes")
	elif event.ctrl_pressed and selected_keys.has(hit):
		selected_keys.erase(hit)
	else:
		if not event.shift_pressed and not event.ctrl_pressed and not selected_keys.has(hit):
			selected_keys.clear()
		selected_keys.erase(hit)
		selected_keys.append(hit)
		_dragging = true
		_drag_origin = event.global_position.x
		_delta = 0
		_original_times.clear()
		for id in selected_keys:
			var selected := model.keyframe_for_id(actor, id)
			if selected != null: _original_times[id] = selected.time
		interaction_changed.emit("Esc cancels keyframe drag • Shift disables snap")
	selection_changed.emit()
	queue_redraw()
	accept_event()

func _input(event: InputEvent) -> void:
	if box_selecting:
		if event is InputEventMouseMotion:
			_box_end = get_global_transform().affine_inverse() * event.position
			_update_box(event.shift_pressed, event.ctrl_pressed)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_box_end = get_global_transform().affine_inverse() * event.position
			_update_box(event.shift_pressed, event.ctrl_pressed)
			box_selecting = false
			interaction_changed.emit("")
			queue_redraw()
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			cancel_drag()
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if overlay_mode and not timeline.split_tool and is_visible_in_tree() and overlay_rect().has_area() and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = get_global_transform().affine_inverse() * event.position
		var overlay_tracks := displayed_tracks()
		for row in overlay_tracks.size():
			var track := overlay_tracks[row]
			for key in track.keys:
				if local.x >= ActorTimelineCanvas.LABEL_WIDTH and overlay_rect().has_point(local) and key_position(key, row).distance_to(local) < minf(10, overlay_rect().size.y / (overlay_tracks.size() + 1) * 0.5):
					var click := event.duplicate() as InputEventMouseButton
					click.position = local
					_gui_input(click)
					get_viewport().set_input_as_handled()
					return
	if _scrubbing:
		if event is InputEventMouseMotion:
			timeline.time_selected.emit(timeline.snapped_playhead(timeline.time_at((get_global_transform().affine_inverse() * event.position).x), event.shift_pressed, true))
		elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_scrubbing = false
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_scrubbing = false
			timeline.time_selected.emit(_scrub_origin)
		else:
			return
		get_viewport().set_input_as_handled()
		return
	if not _dragging:
		return
	if event is InputEventMouseMotion:
		_delta = (event.position.x - _drag_origin) / timeline.pixels_per_second
		if timeline.snap_enabled and not event.shift_pressed:
			_delta = snappedf(_delta, 0.1)
		if timeline.magnet_enabled and not event.shift_pressed:
			var moving_times: Array[float] = []
			var clip := model.clip_for_actor_id(actor.id)
			for source: float in _original_times.values(): moving_times.append(clip.start_time + (source - clip.source_offset) / clip.playback_speed)
			_delta = timeline.magnetic_delta(_delta, moving_times, [], selected_keys, not overlay_mode)
		move_preview_requested.emit(selected_keys.duplicate(), _delta)
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
		if not is_zero_approx(_delta):
			move_requested.emit(selected_keys.duplicate(), _delta)
		_delta = 0
		_original_times.clear()
		interaction_changed.emit("")
		queue_redraw()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_dragging = false
		_delta = 0
		_original_times.clear()
		interaction_changed.emit("")
		queue_redraw()
		get_viewport().set_input_as_handled()
