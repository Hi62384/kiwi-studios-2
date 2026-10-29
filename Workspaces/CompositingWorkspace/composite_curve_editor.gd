class_name KiwiCompositeCurveEditor
extends Control

signal edit_started
signal points_changed(points: Array)
signal edit_finished

var points: Array[Vector2]=[Vector2.ZERO,Vector2.ONE]
var active_point: int=-1

func _ready() -> void:
	custom_minimum_size=Vector2(260,190)
	mouse_filter=Control.MOUSE_FILTER_STOP

func set_points(value: Array) -> void:
	points.clear()
	for point in value:
		if point is Vector2: points.append(point)
	if points.size()<2: points=[Vector2.ZERO,Vector2.ONE]
	_sort_and_clamp()
	queue_redraw()

func _draw() -> void:
	var rect:=Rect2(Vector2.ZERO,size)
	draw_rect(rect,Color("111a24"),true)
	for division in range(1,4):
		var position_x:=size.x*float(division)/4.
		var position_y:=size.y*float(division)/4.
		draw_line(Vector2(position_x,0),Vector2(position_x,size.y),Color("304252"),1.)
		draw_line(Vector2(0,position_y),Vector2(size.x,position_y),Color("304252"),1.)
	draw_rect(rect,Color("71899b"),false,1.)
	var curve:=PackedVector2Array()
	for step in range(65):
		var x:=float(step)/64.
		curve.append(_canvas_point(Vector2(x,_sample(points,x))))
	if curve.size()>1: draw_polyline(curve,Color("56dbc0"),2.,true)
	for index in points.size():
		var color:=Color("ffe2a0") if index==active_point else Color("efffff")
		draw_circle(_canvas_point(points[index]),5.,color)
		draw_arc(_canvas_point(points[index]),5.,0.,TAU,20,Color("183c43"),2.)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button:=event as InputEventMouseButton
		if button.button_index==MOUSE_BUTTON_LEFT and button.pressed:
			emit_signal("edit_started")
			active_point=_nearest_point(button.position)
			if active_point<0:
				points.append(_normalized_point(button.position)); _sort_and_clamp(); active_point=_nearest_point(button.position)
			_move_active(button.position); accept_event()
		elif button.button_index==MOUSE_BUTTON_LEFT and not button.pressed and active_point>=0:
			active_point=-1; queue_redraw(); emit_signal("edit_finished"); accept_event()
		elif button.button_index==MOUSE_BUTTON_RIGHT and button.pressed:
			var candidate:=_nearest_point(button.position)
			if candidate>0 and candidate<points.size()-1:
				emit_signal("edit_started"); points.remove_at(candidate); _sort_and_clamp(); _publish_points(); emit_signal("edit_finished"); accept_event()
	elif event is InputEventMouseMotion and active_point>=0:
		_move_active((event as InputEventMouseMotion).position); accept_event()

func _move_active(position: Vector2) -> void:
	if active_point<0 or active_point>=points.size(): return
	var normalized:=_normalized_point(position)
	if active_point==0: normalized.x=0.
	elif active_point==points.size()-1: normalized.x=1.
	else:
		var left_x:=points[active_point-1].x+.005
		var right_x:=points[active_point+1].x-.005
		normalized.x=clampf(normalized.x,left_x,right_x)
	points[active_point]=normalized; queue_redraw(); _publish_points()

func _publish_points() -> void:
	_sort_and_clamp(); emit_signal("points_changed",points.duplicate()); queue_redraw()

func _sort_and_clamp() -> void:
	for index in points.size(): points[index]=Vector2(clampf(points[index].x,0.,1.),clampf(points[index].y,0.,1.))
	points.sort_custom(func(a: Vector2,b: Vector2): return a.x<b.x)
	if points.size()>=2: points[0].x=0.; points[-1].x=1.

func _nearest_point(position: Vector2) -> int:
	var best: int=-1; var best_distance:=14.
	for index in points.size():
		var distance:=_canvas_point(points[index]).distance_to(position)
		if distance<best_distance: best=index; best_distance=distance
	return best

func _normalized_point(position: Vector2) -> Vector2:
	return Vector2(clampf(position.x/maxf(1.,size.x),0.,1.),1.-clampf(position.y/maxf(1.,size.y),0.,1.))

func _canvas_point(point: Vector2) -> Vector2:
	return Vector2(point.x*size.x,(1.-point.y)*size.y)

static func _sample(curve: Array,value: float) -> float:
	if curve.size()<2: return value
	var sorted:=curve.duplicate(); sorted.sort_custom(func(a: Vector2,b: Vector2): return a.x<b.x)
	if value<=sorted[0].x: return sorted[0].y
	for index in range(1,sorted.size()):
		var left: Vector2=sorted[index-1]; var right: Vector2=sorted[index]
		if value<=right.x: return lerpf(left.y,right.y,inverse_lerp(left.x,right.x,value))
	return sorted[-1].y
