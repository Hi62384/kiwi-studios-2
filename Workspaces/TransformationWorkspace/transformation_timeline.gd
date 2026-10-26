class_name KiwiTransformationTimeline
extends Control
signal selection_changed
signal seek(time: float)
signal gesture_finished
var session: KiwiTransformationSession
var pixels_per_second := 150.
var offset := 0.
var vertical := 0
var drag := ""
var start := Vector2.ZERO
var original: Dictionary={}
var label_width := 140.
const ROW := 26.
func _ready() -> void:
	custom_minimum_size=Vector2(300,115); focus_mode=Control.FOCUS_ALL; mouse_filter=Control.MOUSE_FILTER_STOP; clip_contents=true
func x(time: float) -> float: return label_width+time*pixels_per_second-offset
func time_at(value: float) -> float: return clampf((value-label_width+offset)/pixels_per_second,0,session.document.duration)
func row_y(index: int) -> float: return 28.+(session.document.components.size()-1-index-vertical)*ROW
func hit(point: Vector2) -> Dictionary:
	for item in session.document.components:
		var row := row_y(session.document.components.find(item))
		for key in item.keys:
			if Vector2(x(key.time),row+ROW*.5).distance_to(point)<9: return {"component":item,"key":key}
	return {}
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("101c27"))
	if session==null: return
	var font := ThemeDB.fallback_font; var tick := .25 if pixels_per_second>200 else (1. if pixels_per_second>60 else 2.)
	for i in ceili(session.document.duration/tick)+1:
		var px := x(i*tick)
		if px<label_width or px>size.x: continue
		draw_line(Vector2(px,0),Vector2(px,size.y),Color(1,1,1,.07)); draw_string(font,Vector2(px+4,18),String.num(i*tick,2)+"s",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("a5bfca"))
	for i in session.document.components.size():
		var item := session.document.components[i]; var y := row_y(i)
		if y<28 or y>=size.y: continue
		draw_rect(Rect2(0,y,label_width,ROW),Color("254b48") if session.selected.has(item.id) else Color("1a2b38")); draw_string(font,Vector2(8,y+18),item.title,HORIZONTAL_ALIGNMENT_LEFT,label_width-16,12,Color("d6ebe8")); draw_line(Vector2(label_width,y+ROW),Vector2(size.x,y+ROW),Color(1,1,1,.08))
		for key in item.keys:
			var p := Vector2(x(key.time),y+ROW*.5)
			if p.x<label_width or p.x>size.x: continue
			var selected := session.selected_keys.has(key.id); var c := Color("ffce7a") if selected else Color("73dfc4")
			draw_colored_polygon(PackedVector2Array([p+Vector2(0,-6),p+Vector2(6,0),p+Vector2(0,6),p+Vector2(-6,0)]),c)
			var state := item.state_for_id(key.state_id)
			if state!=null: draw_string(font,p+Vector2(10,4),state.title,HORIZONTAL_ALIGNMENT_LEFT,95,10,Color("b7c8d2"))
	draw_rect(Rect2(0,0,label_width,27),Color("1b2f3d")); draw_string(font,Vector2(9,18),"COMPONENT / STATES",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("79dac2"))
	var head := x(session.playhead)
	if head>=label_width and head<=size.x: draw_line(Vector2(head,0),Vector2(head,size.y),Color("ffd18b"),1.5)
func _gui_input(event: InputEvent) -> void:
	if session==null: return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var delta := -1 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1
			if event.ctrl_pressed: pixels_per_second=clampf(pixels_per_second*(1.15 if delta<0 else 1./1.15),25,600)
			elif event.shift_pressed: offset=clampf(offset+delta*60.,0,maxf(0,session.document.duration*pixels_per_second-size.x+label_width))
			else: vertical=clampi(vertical+delta,0,maxi(0,session.document.components.size()-2))
			queue_redraw(); accept_event(); return
		if event.button_index!=MOUSE_BUTTON_LEFT: return
		grab_focus()
		if event.pressed:
			var found := hit(event.position)
			if not found.is_empty():
				var key: KiwiTransformationKey=found.key; var item: KiwiTransformationComponent=found.component
				if not event.ctrl_pressed and not event.shift_pressed and not session.selected_keys.has(key.id): session.selected_keys.clear()
				if (event.ctrl_pressed or event.shift_pressed) and session.selected_keys.has(key.id): session.selected_keys.erase(key.id)
				elif not session.selected_keys.has(key.id): session.selected_keys.append(key.id)
				session.selected.assign([item.id]); selection_changed.emit(); drag="keys"; start=event.position; original={}
				for component in session.document.components:
					for frame in component.keys:
						if session.selected_keys.has(frame.id) and not component.locked: original[frame.id]=frame.time
				if not original.is_empty(): session.begin()
			elif event.position.x<label_width:
				var index := session.document.components.size()-1-vertical-int((event.position.y-28)/ROW)
				if index>=0 and index<session.document.components.size(): session.select(session.document.components[index].id); selection_changed.emit()
			else: drag="seek"; seek.emit(time_at(event.position.x))
		else:
			if drag=="keys" and not session.pending.is_empty():
				var valid := session.document.validate().is_empty()
				if not valid: session.cancel(); session.message="Keys cannot overlap. Move canceled."
				elif event.position.distance_to(start)<1.: session.cancel()
				else: session.commit("Move state keys")
			drag=""; gesture_finished.emit()
		queue_redraw(); accept_event()
	elif event is InputEventMouseMotion:
		if drag=="seek": seek.emit(time_at(event.position.x))
		elif drag=="keys":
			var delta: float=(event.position.x-start.x)/pixels_per_second
			if not event.ctrl_pressed: delta=snappedf(delta,1./30.)
			var lo := -INF; var hi := INF
			for time: float in original.values(): lo=maxf(lo,-time); hi=minf(hi,session.document.duration-time)
			delta=clampf(delta,lo,hi)
			for item in session.document.components:
				for key in item.keys:
					if original.has(key.id): key.time=float(original[key.id])+delta
		queue_redraw(); accept_event()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE and not drag.is_empty(): session.cancel(); drag=""; gesture_finished.emit()
		elif event.keycode in [KEY_DELETE,KEY_BACKSPACE]: session.delete_keys(); selection_changed.emit()
		elif event.ctrl_pressed and event.keycode==KEY_D: session.duplicate_keys(); selection_changed.emit()
		else: return
		queue_redraw(); accept_event()
