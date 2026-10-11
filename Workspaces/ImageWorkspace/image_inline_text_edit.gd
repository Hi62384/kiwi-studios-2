extends TextEdit
## Native keyboard/IME editing with the same aligned paragraph layout as the layer.
## Native TextEdit glyphs are hidden; only the shaped text, selection, and caret draw.

signal navigation_requested(event: InputEventMouseButton)
var layer: KiwiImageLayer
var canvas: KiwiImageCanvas
var paragraph:=TextParagraph.new()
var settings: Dictionary
var font: Font
var font_size:=16
var detail:=1.0
var _signature:=0
var _blink:=0.0
var _drag_anchor: int=-1


func _ready() -> void:
	wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY
	caret_blink=true
	for key in ["font_color","font_selected_color","font_outline_color","caret_color","selection_color"]: add_theme_color_override(key,Color.TRANSPARENT)
	for key in ["normal","focus","read_only"]: add_theme_stylebox_override(key,StyleBoxEmpty.new())
	scroll_fit_content_height=true
	text_changed.connect(func(): _signature=0; _blink=0; queue_redraw())
	caret_changed.connect(func(): _blink=0; queue_redraw())
	sync_layout()


func _process(delta: float) -> void:
	_blink=fmod(_blink+delta,1.0)
	sync_layout()
	queue_redraw()


func sync_layout() -> void:
	if layer==null or canvas==null: return
	var world:=canvas.document.world_transform(layer)
	detail=maxf(1,canvas.zoom*maxf(world.x.length(),world.y.length()))
	position=canvas.origin()+world.origin*canvas.zoom
	rotation=world.get_rotation()
	scale=world.get_scale()*canvas.zoom/detail
	settings=ActorTextSettings.values(layer.properties.get("text_settings"))
	if settings.is_empty(): settings=layer.properties
	font=ActorTextSettings.font(settings)
	font_size=maxi(1,roundi(float(settings.get("font_size",72))*float(layer.properties.get("text_scale",1))*detail))
	var signature:=hash([text,layer.dimensions,settings,detail,layer.properties.get("alignment",0)])
	if signature!=_signature:
		_signature=signature
		add_theme_font_override("font",font); add_theme_font_size_override("font_size",font_size)
		paragraph.clear()
		paragraph.width=layer.dimensions.x*detail
		paragraph.alignment=int(layer.properties.get("alignment",0))
		paragraph.add_string(text,font,font_size)
		size=Vector2(layer.dimensions.x*detail,maxf(layer.content_dimensions().y*detail,paragraph.get_size().y+font.get_height(font_size)))
	set_v_scroll(0); set_h_scroll(0)


func _absolute(line: int, column: int) -> int:
	var offset:=column
	for i in line: offset+=get_line(i).length()+1
	return offset


func _line_column(offset: int) -> Vector2i:
	for i in get_line_count():
		if offset<=get_line(i).length(): return Vector2i(offset,i)
		offset-=get_line(i).length()+1
	return Vector2i(get_line(get_line_count()-1).length(),get_line_count()-1)


func _place_caret(offset: int, select_from: int=-1) -> void:
	var at:=_line_column(offset)
	set_caret_line(at.y); set_caret_column(at.x)
	if select_from<0: deselect()
	else:
		var start:=_line_column(mini(offset,select_from)); var end:=_line_column(maxi(offset,select_from))
		select(start.y,start.x,end.y,end.x)
	_blink=0; queue_redraw()


func hit_text(at: Vector2) -> int:
	var top:=0.0
	for i in paragraph.get_line_count():
		var height:=paragraph.get_line_size(i).y
		if at.y<top+height or i==paragraph.get_line_count()-1:
			var remaining:=maxf(0,paragraph.width-paragraph.get_line_width(i))
			var x:=remaining*.5 if paragraph.alignment==HORIZONTAL_ALIGNMENT_CENTER else (remaining if paragraph.alignment==HORIZONTAL_ALIGNMENT_RIGHT else 0.0)
			return TextServerManager.get_primary_interface().shaped_text_hit_test_position(paragraph.get_line_rid(i),at.x-x)
		top+=height
	return 0


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			navigation_requested.emit(event); accept_event(); return
		if event.button_index==MOUSE_BUTTON_LEFT:
			if event.pressed:
				var offset:=hit_text(event.position)
				_drag_anchor=_absolute(get_caret_line(),get_caret_column()) if event.shift_pressed else offset
				_place_caret.call_deferred(offset,_drag_anchor if event.shift_pressed else -1)
			else: _drag_anchor=-1
	elif event is InputEventMouseMotion and _drag_anchor>=0 and event.button_mask&MOUSE_BUTTON_MASK_LEFT:
		_place_caret.call_deferred(hit_text(event.position),_drag_anchor)


func caret_rect_for_line(line: int, offset: int) -> Rect2:
	var carets:=TextServerManager.get_primary_interface().shaped_text_get_carets(paragraph.get_line_rid(line),offset)
	var leading: Rect2=carets.get("leading_rect",carets.get("trailing_rect",Rect2()))
	return Rect2(Vector2(leading.position.x,-paragraph.get_line_ascent(line)),Vector2(maxf(1,detail/maxf(.01,canvas.zoom)),paragraph.get_line_size(line).y))


func _draw() -> void:
	if layer==null or font==null: return
	var server:=TextServerManager.get_primary_interface()
	var caret:=_absolute(get_caret_line(),get_caret_column())
	var top:=0.0
	for i in paragraph.get_line_count():
		var height:=paragraph.get_line_size(i).y
		var baseline:=top+paragraph.get_line_ascent(i)
		var remaining:=maxf(0,paragraph.width-paragraph.get_line_width(i))
		var x:=remaining*.5 if paragraph.alignment==HORIZONTAL_ALIGNMENT_CENTER else (remaining if paragraph.alignment==HORIZONTAL_ALIGNMENT_RIGHT else 0.0)
		var rid:=paragraph.get_line_rid(i)
		if has_selection():
			for span in server.shaped_text_get_selection(rid,_absolute(get_selection_from_line(),get_selection_from_column()),_absolute(get_selection_to_line(),get_selection_to_column())):
				draw_rect(Rect2(Vector2(x+span.x,top),Vector2(span.y-span.x,height)),Color(.15,.55,.65,.35))
		var range:=paragraph.get_line_range(i)
		if has_focus() and _blink<.55 and caret>=range.x and (caret<range.y or i==paragraph.get_line_count()-1):
			var rect:=caret_rect_for_line(i,caret)
			rect.position+=Vector2(x,baseline)
			draw_rect(rect,Color("9df4dc"))
		top+=height
	if paragraph.get_line_count()==0 and has_focus() and _blink<.55: draw_line(Vector2.ZERO,Vector2(0,font.get_height(font_size)),Color("9df4dc"),1)
	if bool(settings.get("shadow",false)): paragraph.draw(get_canvas_item(),Vector2(settings.get("shadow_offset",Vector2(2,2)))*detail,settings.get("shadow_color",Color.BLACK))
	if int(settings.get("outline_size",0))>0: paragraph.draw_outline(get_canvas_item(),Vector2.ZERO,roundi(float(settings.outline_size)*detail),settings.get("outline_color",Color.BLACK))
	paragraph.draw(get_canvas_item(),Vector2.ZERO,settings.get("color",Color.WHITE))
