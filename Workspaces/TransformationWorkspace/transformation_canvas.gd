class_name KiwiTransformationCanvas
extends KiwiImageCanvas
signal pivot_changed(value: Vector2)
signal reveal_point(value: Vector2)
var previewing := false
var pivot_uv := Vector2(.5,.5)
var show_grid := false
var onion: KiwiImageLayer
var pivot_before := Vector2.ZERO
func _ready() -> void:
	super._ready()
	# The shared canvas allocates its optional repair worker eagerly. This
	# workspace owns that helper too, even though it exposes drawing tools only.
	if repair_tool.engine.get_parent()==null: add_child(repair_tool.engine)
func _draw() -> void:
	var saved_tool := tool
	if previewing: tool="animation_preview"
	super._draw()
	tool=saved_tool
	if document==null: return
	if show_grid:
		var step := 32.*zoom
		if step>=8:
			var rect := Rect2(origin(),Vector2(document.canvas_size)*zoom).intersection(Rect2(Vector2.ZERO,size))
			for x in range(floori((rect.position.x-origin().x)/step),ceili((rect.end.x-origin().x)/step)): draw_line(Vector2(origin().x+x*step,rect.position.y),Vector2(origin().x+x*step,rect.end.y),Color(1,1,1,.09))
			for y in range(floori((rect.position.y-origin().y)/step),ceili((rect.end.y-origin().y)/step)): draw_line(Vector2(rect.position.x,origin().y+y*step),Vector2(rect.end.x,origin().y+y*step),Color(1,1,1,.09))
	if onion!=null and not previewing and onion.texture!=null:
		var transform := Transform2D(0.,origin()).scaled_local(Vector2.ONE*zoom)*onion.local_transform(); draw_set_transform_matrix(transform); draw_texture_rect(onion.texture,Rect2(Vector2.ZERO,onion.dimensions),false,Color(.7,.85,1,.2)); draw_set_transform_matrix(Transform2D.IDENTITY)
	if not previewing and selected.size()==1:
		var layer := document.layer_for_id(selected[0])
		if layer!=null:
			var point := origin()+layer.local_transform()*(layer.dimensions*pivot_uv)*zoom
			draw_circle(point,7,Color("11212b")); draw_arc(point,6,0,TAU,24,Color("ffd18a"),1.5,true); draw_line(point-Vector2(10,0),point+Vector2(10,0),Color("ffd18a")); draw_line(point-Vector2(0,10),point+Vector2(0,10),Color("ffd18a"))
func _input_canvas(event: InputEvent) -> void:
	if document==null: return
	if previewing:
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not Input.is_key_pressed(KEY_SPACE): accept_event(); return
		if event is InputEventKey and event.pressed: return
	if tool in ["pivot","reveal_path"] and selected.size()==1:
		var layer := document.layer_for_id(selected[0])
		if layer!=null and document.can_edit(layer):
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
				var uv := (layer.local_transform().affine_inverse()*to_document(event.position)/layer.dimensions).clamp(Vector2.ZERO,Vector2.ONE)
				if tool=="reveal_path":
					if event.pressed: reveal_point.emit(uv)
				elif event.pressed: pivot_before=pivot_uv; _drag="pivot"; gesture_started.emit(); pivot_changed.emit(uv)
				elif _drag=="pivot": _drag=""; gesture_finished.emit()
				grab_focus(); queue_redraw(); accept_event(); return
			if event is InputEventMouseMotion and _drag=="pivot":
				pivot_changed.emit((layer.local_transform().affine_inverse()*to_document(event.position)/layer.dimensions).clamp(Vector2.ZERO,Vector2.ONE)); queue_redraw(); accept_event(); return
			if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and _drag=="pivot": _drag=""; pivot_changed.emit(pivot_before); gesture_cancelled.emit(); accept_event(); return
	# Components are independent drawings: allow dragging their selected bounds,
	# including transparent interiors (an open eye/mouth often has one).
	if not previewing and tool=="move" and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed and not event.shift_pressed and not event.ctrl_pressed:
		var point := to_document(event.position)
		var bounds := selection_bounds()
		var screen := Rect2(origin()+bounds.position*zoom,bounds.size*zoom)
		var over_handle := _rotation_handle(screen).distance_to(event.position)<12
		for handle in _handles(screen): over_handle=over_handle or handle.distance_to(event.position)<12
		if not selected.is_empty() and bounds.has_point(point) and not over_handle and hit(point)==null:
			_start=point; _last=point; _moved=false; _bounds=bounds; _begin_transform("move"); grab_focus(); accept_event(); return
	super._input_canvas(event)
func _transform(point: Vector2, constrained: bool, control: bool=false) -> void:
	if _drag!="rotate" or _originals.size()!=1: super._transform(point,constrained,control); return
	var entry: Dictionary=_originals[0]; var center: Vector2=entry.world*(entry.dimensions*pivot_uv)
	var angle := (_start-center).angle_to(point-center)
	if constrained or snapping!=control: angle=snappedf(angle,PI/12.)
	entry.layer.rotation=entry.rotation+angle
	var rotated: Transform2D=entry.layer.local_transform(); var correction: Vector2=center-rotated*(entry.dimensions*pivot_uv)
	entry.layer.position+=correction; _moved=true; gesture_changed.emit()
