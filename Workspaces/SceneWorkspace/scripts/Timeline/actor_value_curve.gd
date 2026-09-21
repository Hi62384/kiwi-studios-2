class_name ActorValueCurve
extends Control
## Normalized outgoing interpolation curve. Interior points can be added,
## dragged, or removed; endpoints keep progress anchored at zero and one.

signal edit_started
signal preview_changed(curve: Curve)
signal edit_committed
signal edit_cancelled

var curve: Curve
var editable := false
var stepped := false
var _drag_point := -1
var _before: Curve
var selected_point := 0
var _drag_handle := 0

static func preset(name: String) -> Curve:
	var result := Curve.new()
	var segments := 4 if name == "Exponential" else (2 if name == "Sine" else (16 if name == "Step" else 1))
	for index in segments + 1:
		var x := float(index) / segments
		var y := x
		var slope := 1.0
		match name:
			"Quadratic":
				y = x * x
				slope = 2.0 * x
			"Exponential":
				y = (pow(2.0, 8.0 * x) - 1.0) / 255.0
				slope = 8.0 * log(2.0) * pow(2.0, 8.0 * x) / 255.0
			"Ease out":
				y = 1.0 - pow(1.0 - x, 3)
				slope = 3.0 * pow(1.0 - x, 2)
			"Smoothstep":
				y = x * x * (3.0 - 2.0 * x)
				slope = 6.0 * x * (1.0 - x)
			"Sine":
				y = (1.0 - cos(PI * x)) / 2.0
				slope = PI * sin(PI * x) / 2.0
			"Step": y = 1.0 if index == segments else 0.0
		if name == "Step": result.add_point(Vector2(x, y), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
		else: result.add_point(Vector2(x, y), slope, slope, Curve.TANGENT_FREE, Curve.TANGENT_FREE)
	return result

static func for_key(key: ActorKeyframe) -> Curve:
	if key.value_curve != null: return key.value_curve.duplicate() as Curve
	var result := preset("Linear")
	if key.interpolation == ActorKeyframe.Interpolation.EASE:
		result.clear_points()
		for index in 17:
			var x := float(index) / 16
			result.add_point(Vector2(x, ease(x, key.attenuation)), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return result

static func template_value(name: String, adjustment: float, x: float) -> float:
	match name:
		"Ease": return 1.0 - pow(1.0 - x, 1.0 + adjustment) if adjustment >= 0 else pow(x, 1.0 - adjustment)
		"Smoothstep": return lerpf(x, x * x * (3.0 - 2.0 * x), clampf(adjustment, 0, 1))
		"Sin wave": return x + 0.25 * (sin(TAU * adjustment * x) - x * sin(TAU * adjustment))
		"Step": return floorf(x * maxf(1, roundf(adjustment))) / maxf(1, roundf(adjustment))
	return x

static func template(name: String, adjustment: float) -> Curve:
	if name == "Linear": return preset("Linear")
	var result := Curve.new()
	if name == "Step":
		var steps := clampi(int(round(adjustment)), 1, 64)
		result.add_point(Vector2.ZERO, 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
		for index in range(1, steps + 1):
			var x := float(index) / steps
			result.add_point(Vector2(x - 0.00001, float(index - 1) / steps), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
			result.add_point(Vector2(x, float(index) / steps), 0, 0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	else:
		var samples := maxi(8, int(absf(adjustment) * 8)) if name == "Sin wave" else (1 if name == "Smoothstep" else 8)
		for index in samples + 1:
			var x := float(index) / samples
			var lo := maxf(0, x - 0.0001)
			var hi := minf(1, x + 0.0001)
			var slope := (template_value(name, adjustment, hi) - template_value(name, adjustment, lo)) / (hi - lo)
			result.add_point(Vector2(x, template_value(name, adjustment, x)), slope, slope, Curve.TANGENT_FREE, Curve.TANGENT_FREE)
	return result

func graph_rect() -> Rect2:
	var margin := 12.0 if editable else 4.0
	return Rect2(Vector2(margin, margin), (size - Vector2(margin * 2, margin * 2)).max(Vector2.ONE))

func reset_tangents() -> void:
	if curve == null or curve.point_count == 0: return
	cancel_edit()
	selected_point = clampi(selected_point, 0, curve.point_count - 1)
	edit_started.emit()
	# Linear mode follows the neighboring point automatically, restoring a
	# straight segment on each side without changing either point's position.
	curve.set_point_left_mode(selected_point, Curve.TANGENT_LINEAR)
	curve.set_point_right_mode(selected_point, Curve.TANGENT_LINEAR)
	stepped = false
	preview_changed.emit(curve)
	edit_committed.emit()
	queue_redraw()

func graph_point(point: Vector2) -> Vector2:
	var rect := graph_rect()
	return rect.position + Vector2(point.x * rect.size.x, (1.0 - point.y) * rect.size.y)

func tangent_position(index: int, side: int) -> Vector2:
	var origin := graph_point(curve.get_point_position(index))
	var slope := curve.get_point_left_tangent(index) if side < 0 else curve.get_point_right_tangent(index)
	var mode := curve.get_point_left_mode(index) if side < 0 else curve.get_point_right_mode(index)
	if mode == Curve.TANGENT_LINEAR and index + side >= 0 and index + side < curve.point_count:
		var difference := curve.get_point_position(index + side) - curve.get_point_position(index)
		slope = difference.y / difference.x if absf(difference.x) > 0.000001 else 0.0
	var direction := Vector2(graph_rect().size.x, -slope * graph_rect().size.y).normalized() * side
	return origin + direction * 48.0

func _draw() -> void:
	var rect := graph_rect()
	draw_style_box(_style(), Rect2(Vector2.ZERO, size))
	if editable:
		for index in 5:
			var fraction := float(index) / 4
			draw_line(graph_point(Vector2(fraction, 0)), graph_point(Vector2(fraction, 1)), Color(1, 1, 1, 0.08))
			draw_line(graph_point(Vector2(0, fraction)), graph_point(Vector2(1, fraction)), Color(1, 1, 1, 0.08))
	var points := PackedVector2Array()
	for index in 81:
		var x := float(index) / 80
		var y := (0.0 if x < 1 else 1.0) if stepped else (curve.sample(x) if curve != null else x)
		points.append(graph_point(Vector2(x, y)))
	draw_polyline(points, Color("8ae4cb"), 2, true)
	if editable and curve != null:
		selected_point = clampi(selected_point, 0, curve.point_count - 1)
		for side in [-1, 1]:
			if selected_point + side < 0 or selected_point + side >= curve.point_count: continue
			var handle := tangent_position(selected_point, side)
			draw_line(graph_point(curve.get_point_position(selected_point)), handle, Color("dfb677"), 1, true)
			draw_rect(Rect2(handle - Vector2(4, 4), Vector2(8, 8)), Color("ffce80"))
		for index in curve.point_count:
			draw_circle(graph_point(curve.get_point_position(index)), 4, Color("ffce80") if index == selected_point else Color("d5f8ed"))

func _style() -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = Color("14251f")
	result.border_color = Color("3c7667")
	result.set_border_width_all(1)
	result.set_corner_radius_all(5)
	return result

func _gui_input(event: InputEvent) -> void:
	if not editable or not event is InputEventMouseButton or not event.pressed: return
	selected_point = clampi(selected_point, 0, curve.point_count - 1)
	if event.button_index == MOUSE_BUTTON_LEFT:
		for side in [-1, 1]:
			if selected_point + side < 0 or selected_point + side >= curve.point_count: continue
			if tangent_position(selected_point, side).distance_to(event.position) < 9:
				_before = curve.duplicate() as Curve
				_drag_point = selected_point
				_drag_handle = side
				edit_started.emit()
				stepped = false
				accept_event()
				return
	var hit := -1
	for index in curve.point_count:
		if graph_point(curve.get_point_position(index)).distance_to(event.position) < 9: hit = index
	if event.button_index == MOUSE_BUTTON_RIGHT:
		if hit > 0 and hit < curve.point_count - 1:
			edit_started.emit()
			curve.remove_point(hit)
			preview_changed.emit(curve)
			edit_committed.emit()
			queue_redraw()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if hit >= 0:
			selected_point = hit
			queue_redraw()
		if hit == 0 or hit == curve.point_count - 1:
			accept_event()
			return
		_before = curve.duplicate() as Curve
		edit_started.emit()
		stepped = false
		if hit < 0:
			var point := _normalized(event.position)
			for index in range(1, curve.point_count - 1):
				if absf(curve.get_point_position(index).x - point.x) < 0.002:
					hit = index
					curve.set_point_value(hit, point.y)
					break
			if hit < 0:
				var slope := (curve.sample(minf(1, point.x + 0.001)) - curve.sample(maxf(0, point.x - 0.001))) / 0.002
				hit = curve.add_point(point, slope, slope, Curve.TANGENT_FREE, Curve.TANGENT_FREE)
			preview_changed.emit(curve)
		selected_point = hit
		_drag_point = hit
		_drag_handle = 0
		queue_redraw()
	accept_event()

func _normalized(position: Vector2) -> Vector2:
	var rect := graph_rect()
	return Vector2(clampf((position.x - rect.position.x) / rect.size.x, 0.001, 0.999), clampf(1.0 - (position.y - rect.position.y) / rect.size.y, 0, 1))

func cancel_edit() -> void:
	if _drag_point < 0: return
	_drag_point = -1
	_drag_handle = 0
	curve = _before
	edit_cancelled.emit()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if _drag_point < 0: return
	if event is InputEventMouseMotion:
		var local: Vector2 = get_global_transform().affine_inverse() * event.position
		if _drag_handle != 0:
			var delta := local - graph_point(curve.get_point_position(_drag_point))
			var slope := clampf(-delta.y / graph_rect().size.y / (maxf(3, delta.x * _drag_handle) * _drag_handle / graph_rect().size.x), -20, 20)
			if _drag_handle < 0:
				curve.set_point_left_mode(_drag_point, Curve.TANGENT_FREE)
				curve.set_point_left_tangent(_drag_point, slope)
			else:
				curve.set_point_right_mode(_drag_point, Curve.TANGENT_FREE)
				curve.set_point_right_tangent(_drag_point, slope)
		else:
			var point := _normalized(local)
			point.x = clampf(point.x, curve.get_point_position(_drag_point - 1).x + 0.001, curve.get_point_position(_drag_point + 1).x - 0.001)
			curve.set_point_value(_drag_point, point.y)
			curve.set_point_offset(_drag_point, point.x)
		preview_changed.emit(curve)
		queue_redraw()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drag_point = -1
		_drag_handle = 0
		edit_committed.emit()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancel_edit()
	else: return
	get_viewport().set_input_as_handled()
