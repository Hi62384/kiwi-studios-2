extends Control
var texture: Texture2D:
	set(value): texture=value; queue_redraw()
var zoom:=1.0
var pan:=Vector2.ZERO
var dragging:=false

func _ready() -> void:
	clip_contents=true
	var blend:=CanvasItemMaterial.new(); blend.blend_mode=CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA; material=blend
	mouse_default_cursor_shape=Control.CURSOR_DRAG
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("0d151e"))
	if texture==null: return
	var dimensions:=Vector2(texture.get_size())
	var fit:=minf((size.x-24)/dimensions.x,(size.y-24)/dimensions.y)
	var extent:=dimensions*fit*zoom
	var rect:=Rect2((size-extent)*.5+pan,extent)
	for y in range(0,int(size.y),20):
		for x in range(0,int(size.x),20):
			if (x/20+y/20)%2==0: draw_rect(Rect2(x,y,20,20),Color("16232f"))
	draw_texture_rect(texture,rect,false)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]: dragging=event.pressed; accept_event()
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var previous:=zoom
			zoom=clampf(zoom*(1.2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.2),.1,32)
			pan=event.position-size*.5-(event.position-size*.5-pan)*(zoom/previous)
			queue_redraw(); accept_event()
		if event.double_click: zoom=1; pan=Vector2.ZERO; queue_redraw()
	elif event is InputEventMouseMotion and dragging:
		pan+=event.relative; queue_redraw(); accept_event()
