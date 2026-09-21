class_name ActorTimelineCanvas
extends Control

signal time_selected(time: float)
signal scroll_requested(time: float)
signal layer_scroll_requested(offset: float)
signal assets_dropped(paths: PackedStringArray, time: float, layer: int)
signal interaction_changed(hint: String)
signal context_requested(screen_position: Vector2, actor_clicked: bool, timeline_time: float, layer: int)

const HEADER: float = 34.0
const ROW: float = 48.0
const LABEL_WIDTH: float = 140.0

var model: ActorTimeline
var registry: ActorRegistry
var pixels_per_second: float = 65.0
var row_height: float = ROW
var scroll_time: float = 0.0
var scroll_rows: float = 0.0
var playhead: float = 0.0
var snap_enabled: bool = true
var magnet_enabled := false
var split_tool := false

func magnetic_delta(delta: float, moving_times: Array[float], exclude_clips: Array[String] = [], exclude_keys: Array[String] = [], keyframe_view: bool = false, include_playhead: bool = true) -> float:
	if not magnet_enabled: return delta
	var targets: Array[float] = []
	if include_playhead: targets.append(playhead)
	for index in model.clips.size():
		if not model.clip_is_visible(index) or exclude_clips.has(model.clips[index].id): continue
		var clip := model.clips[index]
		if keyframe_view and (model.selected_actor() == null or clip.actor_id != model.selected_actor().id): continue
		targets.append(clip.start_time)
		targets.append(clip.start_time + clip.duration)
	var actor := model.selected_actor() if keyframe_view else model.actor_for_id(model.overlay_actor_id)
	if actor != null:
		var clip := model.clip_for_actor_id(actor.id)
		var index := model.clips.find(clip)
		if keyframe_view or (index >= 0 and model.clip_is_visible(index)):
			if keyframe_view:
				targets.append(clip.start_time)
				targets.append(clip.start_time + clip.duration)
			for track in actor.animation_tracks:
				if not keyframe_view and track.path != model.overlay_path: continue
				for key in track.keys:
					if not exclude_keys.has(key.id) and not exclude_clips.has(clip.id):
						targets.append(clip.start_time + (key.time - clip.source_offset) / clip.playback_speed)
	var correction := 8.0 / pixels_per_second
	var best := delta
	for time in moving_times:
		for target in targets:
			var distance := absf(target - (time + delta))
			if distance < correction:
				correction = distance
				best = target - time
	return best

func snapped_playhead(time: float, bypass: bool = false, keyframe_view: bool = false) -> float:
	if bypass: return maxf(0.0, time)
	if snap_enabled: time = snappedf(time, 0.1)
	return maxf(0.0, time + magnetic_delta(0.0, [time], [], [], keyframe_view, false))
var drag_id: String = ""
var preview_time: float = 0.0
var _drag_offset: float = 0.0
var scrubbing: bool = false
var _scrub_origin: float = 0.0
var drag_mode: String = "move"
var preview_duration: float = 0.0
var preview_layer: int = 0
var preview_valid: bool = true
var _original_start: float = 0.0
var _original_end: float = 0.0
var _pointer_x: float = 0.0
var _bypass_snap: bool = false
var _drag_ids: Array[String] = []
var _drag_originals: Dictionary = {}
var _preview_states: Dictionary = {}
var box_selecting: bool = false
var _box_start: Vector2
var _box_current: Vector2
var _box_base_selection: Array[String] = []
var _fade_actor: ActorData
var _fade_key: StringName
var _fade_original := 0.0
var _fade_pointer := 0.0
var recording_preview: Dictionary = {}
var recording_peaks := PackedFloat32Array()
var _asset_paths := PackedStringArray()
var _asset_templates: Array[Dictionary] = []
var _asset_previews: Array[Dictionary] = []

func display_layer_count() -> int:
	var count := model.layer_count()
	if not recording_preview.is_empty(): count = maxi(count, int(recording_preview.layer) + 1)
	for preview in _asset_previews: count = maxi(count, int(preview.layer) + 1)
	return count

func _clear_asset_drag() -> void:
	_asset_paths.clear()
	_asset_templates.clear()
	_asset_previews.clear()
	queue_redraw()
	interaction_changed.emit("")

func preview_assets(at_position: Vector2, paths: PackedStringArray) -> bool:
	if at_position.x < LABEL_WIDTH or at_position.y < HEADER or not Rect2(Vector2.ZERO, size).has_point(at_position):
		_asset_previews.clear()
		queue_redraw()
		interaction_changed.emit("")
		return false
	if paths != _asset_paths:
		_clear_asset_drag()
		for path in paths:
			var type := ActorFileImport.type_for_path(path)
			var definition := registry.get_definition(&"point_3d" if type == &"scene_instance" else type)
			if definition == null:
				_clear_asset_drag()
				return false
			var actor := definition.create_actor(ActorFileImport.values_for_path(path, registry))
			actor.section_id = model.selected_section_id
			actor.parent_id = model.focused_actor_id
			var duration := ActorAudio.length(actor) if type in [&"audio", &"video", &"video_2d"] else 5.0
			if type == &"scene_instance":
				actor.display_name = path.get_file().get_basename()
				duration = ActorFileImport.scene_duration(ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData)
			if duration <= 0.0: return false
			_asset_templates.append({"actor": actor, "duration": duration, "path": path, "definition": definition})
		_asset_paths = paths.duplicate()
	_asset_previews.clear()
	var desired := snapped_playhead(time_at(at_position.x), Input.is_key_pressed(KEY_SHIFT))
	var layer := layer_at(at_position.y)
	for template in _asset_templates:
		template.actor.section_id = model.selected_section_id
		template.actor.parent_id = model.focused_actor_id
		var start := desired
		if magnet_enabled and not Input.is_key_pressed(KEY_SHIFT):
			start += magnetic_delta(0.0, [start, start + float(template.duration)])
		var neighbors: Array[ActorClip] = []
		for other in model.section_clips():
			if other.layer == layer and model.actors_obstruct(template.actor, model.actor_for_id(other.actor_id)): neighbors.append(other)
		neighbors.sort_custom(func(a: ActorClip, b: ActorClip): return a.start_time < b.start_time)
		for other in neighbors:
			if start < other.start_time + other.duration and start + float(template.duration) > other.start_time: start = other.start_time + other.duration
		var state := template.duplicate()
		state["start"] = start
		state["layer"] = layer
		_asset_previews.append(state)
		layer += 1
	queue_redraw()
	interaction_changed.emit("Release to place • Drag outside to cancel • Shift disables snap")
	return not _asset_previews.is_empty()

func fade_handle(index: int, incoming: bool) -> Vector2:
	var rect := clip_rect(index)
	var actor := model.actors[index]
	var duration := clampf(float(actor.values.get(&"fade_in" if incoming else &"fade_out", 0.0)), 0.0, model.clips[index].duration)
	var margin := minf(6.0, rect.size.x / 2.0)
	var inset := clampf(duration * pixels_per_second, margin, rect.size.x - margin)
	return Vector2(rect.position.x + inset if incoming else rect.end.x - inset, rect.position.y + minf(6.0, rect.size.y / 2.0))

func _draw_fades(index: int, rect: Rect2) -> void:
	if rect.size.y < 16.0 or rect.size.x < 20.0: return
	for incoming in [true, false]:
		var point := fade_handle(index, incoming)
		var edge := rect.position.x if incoming else rect.end.x
		var bottom := rect.end.y - 2.0
		if point.x >= LABEL_WIDTH and point.x <= size.x and point.y >= HEADER and point.y <= size.y:
			draw_line(Vector2(edge, bottom), point, Color(1.0, 0.81, 0.48, 0.7), 1.5)
			draw_circle(point, 4.0, Color("f4bf75"))
			draw_circle(point, 4.0, Color("513e28"), false, 1.0)

func _cancel_fade() -> void:
	if _fade_actor != null:
		model.preview_property(_fade_actor, registry.get_definition(&"audio"), _fade_key, _fade_original)
		_fade_actor = null
		interaction_changed.emit("")


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	custom_minimum_size = Vector2(280, 40)
	mouse_default_cursor_shape = Control.CURSOR_ARROW

static func dropped_paths(data: Variant) -> PackedStringArray:
	var paths := PackedStringArray()
	if data is Dictionary:
		var collection: Variant = data.get("paths", data.get("files", []))
		if collection is Array or collection is PackedStringArray:
			for path in collection: paths.append(ActorResourceSlot.path_from_drag(str(path)))
	if paths.is_empty():
		var path := ActorResourceSlot.path_from_drag(data)
		if not path.is_empty(): paths.append(path)
	return paths

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var paths := dropped_paths(data)
	if paths.is_empty():
		_clear_asset_drag()
		return false
	return preview_assets(at_position, paths)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(at_position, data):
		var placements := _asset_previews.duplicate()
		_clear_asset_drag()
		for placement in placements: assets_dropped.emit(PackedStringArray([placement.path]), placement.start, placement.layer)


func time_at(x: float) -> float:
	return maxf(0.0, scroll_time + (x - LABEL_WIDTH) / pixels_per_second)


func clip_rect(index: int) -> Rect2:
	var clip := model.clips[index]
	var state: Dictionary = _preview_states.get(clip.id, {})
	var time: float = state.get("start", clip.start_time)
	var duration: float = state.get("duration", clip.duration)
	var layer: int = state.get("layer", clip.layer)
	var vertical_margin := clampf(row_height * 0.12, 2.0, 4.0)
	return Rect2(LABEL_WIDTH + (time - scroll_time) * pixels_per_second,
		HEADER + layer * row_height - scroll_rows + vertical_margin,
		duration * pixels_per_second, maxf(row_height - vertical_margin * 2.0, 2.0))


func cancel_drag() -> void:
	_cancel_fade()
	interaction_changed.emit("")
	drag_id = ""
	_drag_ids.clear()
	_drag_originals.clear()
	_preview_states.clear()
	if scrubbing:
		scrubbing = false
		time_selected.emit(_scrub_origin)
	if box_selecting:
		box_selecting = false
		model.set_selection(_box_base_selection,
			_box_base_selection.back() if not _box_base_selection.is_empty() else "")
		_box_base_selection.clear()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and drag_id.is_empty():
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		var hover_index := _clip_hit_index(event.position)
		if hover_index >= 0:
			if split_tool:
				mouse_default_cursor_shape = Control.CURSOR_CROSS
				return
			var rect := clip_rect(hover_index)
			mouse_default_cursor_shape = Control.CURSOR_HSIZE if minf(absf(event.position.x - rect.position.x), absf(event.position.x - rect.end.x)) <= 7.0 else Control.CURSOR_DRAG
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var direction := -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		var amount := direction * maxf(event.factor, 1.0)
		if event.position.y < HEADER:
			scroll_requested.emit(maxf(0.0, scroll_time + amount * 2.0))
		else:
			layer_scroll_requested.emit(maxf(0.0, scroll_rows + amount * row_height))
		accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var context_index := _clip_hit_index(event.position)
		if context_index >= 0:
			var context_id := model.clips[context_index].id
			model.select(context_id, model.is_selected(context_id))
		grab_focus()
		context_requested.emit(event.global_position, context_index >= 0,
			time_at(event.position.x), layer_at(event.position.y))
		accept_event()
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	grab_focus()
	accept_event()
	if event.position.y < HEADER:
		if event.position.x >= LABEL_WIDTH:
			scrubbing = true
			interaction_changed.emit("Esc cancels scrub")
			_scrub_origin = playhead
			time_selected.emit(snapped_playhead(time_at(event.position.x), event.shift_pressed))
		return
	var hit_index := _clip_hit_index(event.position)
	if hit_index >= 0:
		var rect := clip_rect(hit_index)
		if event.position.x >= LABEL_WIDTH:
			if not split_tool and rect.size.y >= 16.0 and rect.size.x >= 20.0 and model.actors[hit_index].type_id == &"audio":
				for incoming in [true, false]:
					if fade_handle(hit_index, incoming).distance_to(event.position) <= 7.0:
						model.select(model.clips[hit_index].id, model.is_selected(model.clips[hit_index].id))
						_fade_actor = model.actors[hit_index]
						_fade_key = &"fade_in" if incoming else &"fade_out"
						_fade_original = float(_fade_actor.values.get(_fade_key, 0.0))
						_fade_pointer = event.global_position.x
						interaction_changed.emit("Drag audio fade • Esc cancels • Shift disables snap")
						return
			if split_tool:
				model.split_clip(model.clips[hit_index].id, time_at(event.position.x))
				return
			var clicked_id := model.clips[hit_index].id
			if event.ctrl_pressed:
				model.toggle_selection(clicked_id)
				return
			# Pressing an actor that already belongs to the selection begins a group
			# gesture; only a genuinely new normal click replaces the selection.
			model.select(clicked_id, event.shift_pressed or model.is_selected(clicked_id))
			drag_id = model.clips[hit_index].id
			interaction_changed.emit("Esc cancels drag")
			_drag_ids.assign(model.linked_clip_ids(model.selected_ids))
			_drag_originals.clear()
			_preview_states.clear()
			for selected_id in _drag_ids:
				var selected_clip := model.clips[model._index_of(selected_id)]
				var state := {"start": selected_clip.start_time, "duration": selected_clip.duration,
					"layer": selected_clip.layer, "offset": selected_clip.source_offset}
				_drag_originals[selected_id] = state.duplicate()
				_preview_states[selected_id] = state.duplicate()
			preview_time = model.clips[hit_index].start_time
			preview_duration = model.clips[hit_index].duration
			preview_layer = model.clips[hit_index].layer
			preview_valid = true
			_original_start = preview_time
			_original_end = preview_time + preview_duration
			drag_mode = "move"
			if absf(event.position.x - rect.position.x) <= minf(7.0, rect.size.x / 3.0):
				drag_mode = "left"
			elif absf(event.position.x - rect.end.x) <= minf(7.0, rect.size.x / 3.0):
				drag_mode = "right"
			_drag_offset = time_at(event.position.x) - preview_time
			if drag_mode == "right":
				_drag_offset = time_at(event.position.x) - _original_end
			_pointer_x = event.position.x
			return
	model.selected_layer = layer_at(event.position.y)
	if event.position.x >= LABEL_WIDTH and event.position.y >= HEADER:
		_begin_box_select(event.position, event.shift_pressed, event.ctrl_pressed)
	else:
		model.select("")


func _begin_box_select(position: Vector2, add: bool, subtract: bool) -> void:
	box_selecting = true
	_box_start = position
	_box_current = position
	_box_base_selection.assign(model.selected_ids)
	_update_box_selection(add, subtract)
	interaction_changed.emit("Esc cancels box select  •  Shift adds  •  Ctrl removes")
	queue_redraw()


func _selection_box() -> Rect2:
	var area := Rect2(_box_start, _box_current - _box_start).abs()
	return area.intersection(Rect2(LABEL_WIDTH, HEADER,
		maxf(size.x - LABEL_WIDTH, 0.0), maxf(size.y - HEADER, 0.0)))


func _update_box_selection(add: bool, subtract: bool) -> void:
	var hits: Array[String] = []
	var area := _selection_box()
	if area.has_area():
		for index in model.clips.size():
			if not model.clip_is_visible(index):
				continue
			if area.intersects(clip_rect(index), true):
				hits.append(model.clips[index].id)
	var next: Array[String] = []
	if add or subtract:
		next.assign(_box_base_selection)
	if subtract:
		for id in hits:
			next.erase(id)
	else:
		for id in hits:
			if not next.has(id):
				next.append(id)
	var primary := ""
	if not subtract and not hits.is_empty():
		primary = hits.back()
	elif not next.is_empty():
		primary = next.back()
	model.set_selection(next, primary)


func _clip_hit_index(position: Vector2) -> int:
	if position.x < LABEL_WIDTH or position.y < HEADER:
		return -1
	var primary_index := model._index_of(model.selected_id)
	if model.clip_is_visible(primary_index) and _expanded_hit_rect(clip_rect(primary_index)).has_point(position):
		return primary_index
	for index in range(model.clips.size() - 1, -1, -1):
		if not model.clip_is_visible(index):
			continue
		if index != primary_index and _expanded_hit_rect(clip_rect(index)).has_point(position):
			return index
	return -1


func _expanded_hit_rect(rect: Rect2) -> Rect2:
	return Rect2(rect.position - Vector2(6, 0), rect.size + Vector2(12, 0))


func layer_at(y: float) -> int:
	return clampi(int(floor((y - HEADER + scroll_rows) / row_height)), 0, model.layer_count() - 1)


## Receive motion/release even when the pointer leaves the timeline while dragging.
func _input(event: InputEvent) -> void:
	if _fade_actor != null:
		if event is InputEventMouseMotion:
			var direction := 1.0 if _fade_key == &"fade_in" else -1.0
			var value: float = _fade_original + (event.global_position.x - _fade_pointer) / pixels_per_second * direction
			if snap_enabled and not event.shift_pressed: value = snappedf(value, 0.1)
			value = clampf(value, 0.0, model.clip_for_actor_id(_fade_actor.id).duration)
			model.preview_property(_fade_actor, registry.get_definition(&"audio"), _fade_key, value)
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			model.commit_property_preview(_fade_actor, registry.get_definition(&"audio"), _fade_key, _fade_original, _fade_actor.values[_fade_key])
			_fade_actor = null
			interaction_changed.emit("")
		elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_cancel_fade()
		get_viewport().set_input_as_handled()
		return
	if drag_id.is_empty() and not scrubbing and not box_selecting:
		return
	if event is InputEventMouseMotion:
		var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if scrubbing:
			time_selected.emit(snapped_playhead(time_at(local_position.x), event.shift_pressed))
		elif box_selecting:
			_box_current = local_position
			_update_box_selection(event.shift_pressed, event.ctrl_pressed)
			interaction_changed.emit("Esc cancels box select  •  Shift adds  •  Ctrl removes")
			queue_redraw()
		else:
			if drag_mode == "move":
				preview_layer = layer_at(local_position.y)
			update_drag(local_position.x, event.shift_pressed)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if scrubbing:
			var local_position: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
			time_selected.emit(snapped_playhead(time_at(local_position.x), event.shift_pressed))
			scrubbing = false
			interaction_changed.emit("")
		elif box_selecting:
			box_selecting = false
			_box_base_selection.clear()
			interaction_changed.emit("")
			queue_redraw()
		else:
			finish_drag()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_drag()
		get_viewport().set_input_as_handled()


func update_drag(pointer_x: float, bypass_snap: bool = false) -> void:
	_pointer_x = pointer_x
	_bypass_snap = bypass_snap
	var target := maxf(0.0, time_at(pointer_x) - _drag_offset)
	if snap_enabled and not bypass_snap:
		target = snappedf(target, 0.1)
	var primary_original: Dictionary = _drag_originals.get(drag_id, {})
	if primary_original.is_empty():
		return
	if magnet_enabled and not bypass_snap:
		var moving_times: Array[float] = []
		for state: Dictionary in _drag_originals.values():
			if drag_mode != "right": moving_times.append(float(state.start))
			if drag_mode != "left": moving_times.append(float(state.start) + float(state.duration))
		var origin := float(primary_original.start) + (float(primary_original.duration) if drag_mode == "right" else 0.0)
		target = origin + magnetic_delta(target - origin, moving_times, _drag_ids)
	_preview_states.clear()
	if drag_mode == "left":
		var delta := target - float(primary_original.start)
		var bounds := _trim_delta_bounds(true)
		delta = clampf(delta, bounds.x, bounds.y)
		for id in _drag_ids:
			var original: Dictionary = _drag_originals[id]
			var clip := model.clips[model._index_of(id)]
			_preview_states[id] = {"start": float(original.start) + delta,
				"duration": float(original.duration) - delta, "layer": int(original.layer),
				"offset": float(original.offset) + delta * clip.playback_speed}
	elif drag_mode == "right":
		var delta := target - (float(primary_original.start) + float(primary_original.duration))
		var bounds := _trim_delta_bounds(false)
		delta = clampf(delta, bounds.x, bounds.y)
		for id in _drag_ids:
			var original: Dictionary = _drag_originals[id]
			_preview_states[id] = {"start": original.start,
				"duration": float(original.duration) + delta, "layer": original.layer,
				"offset": original.offset}
	else:
		var layer_delta := preview_layer - int(primary_original.layer)
		var minimum_layer_delta := -int(primary_original.layer)
		for id in _drag_ids:
			minimum_layer_delta = maxi(minimum_layer_delta, -int(_drag_originals[id].layer))
		layer_delta = maxi(layer_delta, minimum_layer_delta)
		var delta := target - float(primary_original.start)
		delta = model.nearest_free_group_delta(_drag_ids, delta, layer_delta)
		for id in _drag_ids:
			var original: Dictionary = _drag_originals[id]
			_preview_states[id] = {"start": float(original.start) + delta,
				"duration": original.duration, "layer": int(original.layer) + layer_delta,
				"offset": original.offset}
	var primary_preview: Dictionary = _preview_states[drag_id]
	preview_time = primary_preview.start
	preview_duration = primary_preview.duration
	preview_layer = primary_preview.layer
	preview_valid = model.can_place_group(_preview_states)
	interaction_changed.emit("Esc cancels drag")
	queue_redraw()


func _trim_delta_bounds(left_edge: bool) -> Vector2:
	var minimum := -INF
	var maximum := INF
	for id in _drag_ids:
		var original: Dictionary = _drag_originals[id]
		var clip := model.clips[model._index_of(id)]
		var actor := model.actor_for_id(clip.actor_id)
		if actor.type_id in [&"audio", &"video", &"video_2d"]:
			if left_edge:
				minimum = maxf(minimum, -float(original.offset) / clip.playback_speed)
			else:
				maximum = minf(maximum, (ActorAudio.length(actor) - float(original.offset)) / clip.playback_speed - float(original.duration))
		if left_edge:
			minimum = maxf(minimum, -float(original.start))
			maximum = minf(maximum, float(original.duration) - model.minimum_duration(clip))
		else:
			minimum = maxf(minimum, model.minimum_duration(clip) - float(original.duration))
		for other in model.section_clips():
			if not model.actors_obstruct(model.actors[model._index_of(id)], model.actor_for_id(other.actor_id)):
				continue
			if other.id == id or other.layer != int(original.layer):
				continue
			var other_original: Dictionary = _drag_originals.get(other.id, {})
			var other_start: float = other_original.get("start", other.start_time)
			var other_end: float = other_start + float(other_original.get("duration", other.duration))
			if left_edge and other_end <= float(original.start) + 0.000001:
				minimum = maxf(minimum, other_end - float(original.start))
			elif not left_edge and other_start >= float(original.start) + float(original.duration) - 0.000001:
				maximum = minf(maximum, other_start - float(original.start) - float(original.duration))
	return Vector2(minimum, maximum)


func _process(delta: float) -> void:
	if model == null: return
	for index in model.clips.size():
		if model.actors[index].type_id in [&"video", &"video_2d"] and model.clip_is_visible(index):
			queue_redraw()
			break
	if not _asset_paths.is_empty() and get_viewport().gui_is_dragging():
		preview_assets(get_local_mouse_position(), _asset_paths)
	advance_auto_scroll(delta)


func advance_auto_scroll(delta: float) -> void:
	if drag_id.is_empty():
		return
	var direction := 0.0
	if _pointer_x > size.x - 30.0:
		direction = clampf((_pointer_x - size.x + 30.0) / 30.0, 0.0, 2.0)
	elif _pointer_x < LABEL_WIDTH + 30.0:
		direction = -clampf((LABEL_WIDTH + 30.0 - _pointer_x) / 30.0, 0.0, 2.0)
	if direction == 0.0:
		return
	scroll_requested.emit(maxf(0.0, scroll_time + direction * 300.0 * delta / pixels_per_second))
	update_drag(_pointer_x, _bypass_snap)


func finish_drag() -> void:
	interaction_changed.emit("")
	var id := drag_id
	drag_id = ""
	if not id.is_empty() and preview_valid:
		var action := "Move Actors" if _drag_ids.size() > 1 else "Move Actor"
		if drag_mode != "move":
			action = "Trim Actors" if _drag_ids.size() > 1 else "Trim Actor"
		model.commit_clip_states(_preview_states, action, id)
	_drag_ids.clear()
	_drag_originals.clear()
	_preview_states.clear()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END: _clear_asset_drag()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		cancel_drag()


func _draw_video_frames(index: int, rect: Rect2, visible_rect: Rect2) -> void:
	var clip := model.clips[index]
	var state: Dictionary = _preview_states.get(clip.id, {})
	var offset := float(state.get("offset", clip.source_offset))
	var path := str(model.actors[index].values.get(&"video", ""))
	var strip := Rect2(visible_rect.position + Vector2(2, 2), visible_rect.size - Vector2(4, 4))
	if not strip.has_area(): return
	var tile_width := maxf(36.0, strip.size.y * 16.0 / 9.0)
	var x := strip.position.x
	while x < strip.end.x:
		var time := offset + (x - rect.position.x) / pixels_per_second * clip.playback_speed
		var texture := ActorVideo.frame(path, time)
		var tile := Rect2(x, strip.position.y, minf(tile_width - 1, strip.end.x - x), strip.size.y)
		if texture != null: draw_texture_rect(texture, tile, false, Color(1, 1, 1, 0.65))
		x += tile_width
	# Contrast veil keeps labels legible over frames without obscuring selection borders.
	draw_rect(strip, Color(0.02, 0.06, 0.06, 0.3))

func _draw_waveform(index: int, rect: Rect2, visible_rect: Rect2) -> void:
	var editor := get_tree().get_first_node_in_group("actor_timeline_editors") as ActorTimelineEditor
	if editor == null or editor.audio_system == null: return
	var actor := model.actors[index]
	var stream := ActorAudio.source(actor.values.get(&"audio", ""))
	if stream == null: return
	var wave := editor.audio_system.waveform(stream)
	if wave.is_empty():
		queue_redraw()
		return
	var clip := model.clips[index]
	var offset := float(_preview_states.get(clip.id, {}).get("offset", clip.source_offset))
	var center := visible_rect.position.y + visible_rect.size.y * 0.7
	var amplitude := visible_rect.size.y * 0.26
	for x in range(int(visible_rect.position.x) + 2, int(visible_rect.end.x) - 2, 2):
		var source_time := offset + (float(x) - rect.position.x) / pixels_per_second * clip.playback_speed
		var bin := clampi(int(source_time / stream.get_length() * wave.size()), 0, wave.size() - 1)
		var height := maxf(0.5, wave[bin] * amplitude)
		draw_line(Vector2(x, center - height), Vector2(x, center + height), Color(0.56, 0.95, 0.82, 0.55))

func _draw_media_preview(state: Dictionary, recording: bool = false) -> void:
	var rect := Rect2(LABEL_WIDTH + (float(state.start) - scroll_time) * pixels_per_second,
		HEADER + int(state.layer) * row_height - scroll_rows + 4.0,
		maxf(2.0, float(state.duration) * pixels_per_second), maxf(4.0, row_height - 8.0))
	var area := rect.intersection(Rect2(LABEL_WIDTH, HEADER, maxf(0, size.x - LABEL_WIDTH), maxf(0, size.y - HEADER)))
	if not area.has_area(): return
	var tint := Color("ff8291") if recording else Color("92f1cf")
	draw_rect(area, Color(tint, 0.16))
	draw_rect(area, tint, false, 1.5)
	var peaks := recording_peaks if recording else PackedFloat32Array()
	var total := float(state.duration)
	if not recording and state.actor.type_id == &"audio":
		var editor := get_tree().get_first_node_in_group("actor_timeline_editors") as ActorTimelineEditor
		if editor != null: peaks = editor.audio_system.waveform(ActorAudio.source(state.actor.values[&"audio"]))
	if not peaks.is_empty() and total > 0.0:
		for x in range(int(area.position.x) + 1, int(area.end.x), 2):
			var bin := clampi(int((x - rect.position.x) / rect.size.x * peaks.size()), 0, peaks.size() - 1)
			var center := rect.position.y + rect.size.y * 0.7
			var height := maxf(0.5, peaks[bin] * rect.size.y * 0.24)
			draw_line(Vector2(x, center - height), Vector2(x, center + height), tint)
	if area.size.y >= 20 and area.size.x >= 45:
		draw_string(ThemeDB.fallback_font, area.position + Vector2(8, 16), "● Recording" if recording else str(state.path).get_file(), HORIZONTAL_ALIGNMENT_LEFT, area.size.x - 12, 11, tint)

func _draw() -> void:
	if model == null:
		return
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, size), Color("151b24"))
	for index in display_layer_count():
		var y := HEADER + index * row_height - scroll_rows
		if y + row_height < HEADER or y > size.y:
			continue
		draw_rect(Rect2(0, y, size.x, row_height), Color("1e2733") if index % 2 == 0 else Color("19222d"))
	for index in model.clips.size():
		if model.hidden_clip_obstructs_view(index):
			var ghost := clip_rect(index).intersection(Rect2(LABEL_WIDTH, HEADER, maxf(size.x - LABEL_WIDTH, 0), maxf(size.y - HEADER, 0)))
			if ghost.has_area():
				draw_rect(ghost, Color(0.72, 0.48, 0.25, 0.12))
				draw_rect(ghost, Color("a78259"), false, 1.0)
				if ghost.size.y >= 20:
					draw_string(font, ghost.position + Vector2(6, minf(18, ghost.size.y - 3)), "Hidden • " + model.actors[index].display_name,
						HORIZONTAL_ALIGNMENT_LEFT, maxf(0, ghost.size.x - 12), 11, Color("c3a57f"))
	for index in model.clips.size():
		if not model.clip_is_visible(index):
			continue
		var rect := clip_rect(index)
		var visible_rect := rect.intersection(Rect2(LABEL_WIDTH, HEADER, maxf(size.x - LABEL_WIDTH, 0), maxf(size.y - HEADER, 0)))
		if visible_rect.has_area():
			var selected := model.is_selected(model.clips[index].id)
			var primary := model.clips[index].id == model.selected_id
			var style := StyleBoxFlat.new()
			style.bg_color = Color("378a7c") if primary else (Color("26594f") if selected else Color("182e2b"))
			style.border_color = Color("b0ffe6") if primary else (Color("59b39b") if selected else Color("38524a"))
			if _preview_states.has(model.clips[index].id) and not preview_valid:
				style.bg_color = Color("803b48")
				style.border_color = Color("f39b9b")
			style.set_border_width_all(2 if primary else 1)
			style.set_corner_radius_all(int(minf(6.0, visible_rect.size.y * 0.35)))
			draw_style_box(style, visible_rect)
			if model.actors[index].type_id in [&"video", &"video_2d"]: _draw_video_frames(index, rect, visible_rect)
			if model.actors[index].type_id == &"audio":
				_draw_waveform(index, rect, visible_rect)
				_draw_fades(index, rect)
			var compact := visible_rect.size.y < 34.0
			var tiny := visible_rect.size.y < 16.0
			var text_offset := 10.0
			var definition := registry.get_definition(model.actors[index].type_id) if registry != null else null
			var icon_size := minf(28.0, visible_rect.size.y - 7.0)
			if not tiny and icon_size >= 12.0 and definition != null and definition.icon != null and visible_rect.size.x >= 52:
				var icon_position := visible_rect.position + Vector2(7, (visible_rect.size.y - icon_size) * 0.5)
				draw_texture_rect(definition.icon, Rect2(icon_position, Vector2(icon_size, icon_size)), false)
				text_offset = icon_size + 13.0
			if not tiny:
				var title_size := 12 if compact else 13
				var title_y := visible_rect.size.y * 0.5 + 4.0 if compact else 17.0
				draw_string(font, visible_rect.position + Vector2(text_offset, title_y), model.actors[index].display_name,
					HORIZONTAL_ALIGNMENT_LEFT, maxf(visible_rect.size.x - text_offset - 6, 0), title_size, Color.WHITE)
			var draw_state: Dictionary = _preview_states.get(model.clips[index].id, {})
			var details := "%.1fs" % float(draw_state.get("duration", model.clips[index].duration))
			var parent := model.actor_for_id(model.actors[index].parent_id)
			if parent != null:
				details += "  ·  ↳ " + parent.display_name
			if not compact:
				draw_string(font, visible_rect.position + Vector2(text_offset, 32), details,
					HORIZONTAL_ALIGNMENT_LEFT, maxf(visible_rect.size.x - text_offset - 6, 0), 10, Color("bdd6df"))
			if primary and rect.size.x >= 20:
				for edge in [rect.position.x + 4, rect.end.x - 4]:
					if edge >= LABEL_WIDTH and edge <= size.x:
						var inset := minf(10.0, visible_rect.size.y * 0.25)
						draw_line(Vector2(edge, visible_rect.position.y + inset), Vector2(edge, visible_rect.end.y - inset), Color("8ae4cb"), 2)
	for preview in _asset_previews: _draw_media_preview(preview)
	if not recording_preview.is_empty(): _draw_media_preview(recording_preview, true)
	if box_selecting:
		var selection_area := _selection_box()
		if selection_area.has_area():
			draw_rect(selection_area, Color(0.28, 0.82, 0.72, 0.13), true)
			draw_rect(selection_area, Color("72d9c0"), false, 1.5)
	# Paint fixed labels and ruler last so scrolled clips cannot cover them.
	draw_rect(Rect2(0, 0, LABEL_WIDTH, size.y), Color("202a37"))
	for index in display_layer_count():
		var y := HEADER + index * row_height - scroll_rows
		if y >= HEADER and y < size.y:
			var center_y := y + row_height * 0.5
			draw_circle(Vector2(14, center_y), minf(3.0, row_height * 0.16), Color("80dbc4") if index == model.selected_layer else Color("63809c"))
			if row_height >= 15.0:
				draw_string(font, Vector2(25, center_y + 5), "Layer %d" % (index + 1),
					HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 32, 12 if row_height < 30 else 13, Color("c8d2df"))
	draw_rect(Rect2(0, 0, size.x, HEADER), Color("263344"))
	draw_string(font, Vector2(12, 22), "LAYERS", HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 18, 11, Color("b4c3d3"))
	var tick_step := 1.0 if pixels_per_second >= 45.0 else 5.0
	var tick := ceilf(scroll_time / tick_step) * tick_step
	while LABEL_WIDTH + (tick - scroll_time) * pixels_per_second < size.x:
		var x := LABEL_WIDTH + (tick - scroll_time) * pixels_per_second
		draw_line(Vector2(x, HEADER - 6), Vector2(x, size.y), Color(0.7, 0.8, 0.9, 0.12))
		draw_string(font, Vector2(x + 4, 17), "%.0fs" % tick, HORIZONTAL_ALIGNMENT_LEFT, 60, 12, Color("becbd9"))
		tick += tick_step
	var head_x := LABEL_WIDTH + (playhead - scroll_time) * pixels_per_second
	if head_x >= LABEL_WIDTH and head_x <= size.x:
		draw_line(Vector2(head_x, HEADER), Vector2(head_x, size.y), Color(1, 0.78, 0.47, 0.12), 7.0)
		draw_line(Vector2(head_x, 0), Vector2(head_x, size.y), Color("f4bf75"), 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(head_x - 6, 0), Vector2(head_x + 6, 0), Vector2(head_x + 6, 10), Vector2(head_x, 16), Vector2(head_x - 6, 10)]), Color("f4bf75"))
	if model.visible_clips().is_empty():
		draw_string(font, Vector2(LABEL_WIDTH + 18, HEADER + 42), "Add an actor to start",
			HORIZONTAL_ALIGNMENT_LEFT, maxf(size.x - LABEL_WIDTH - 24, 0), 14, Color("aebdcc"))
