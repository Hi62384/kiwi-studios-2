extends Window
## True voxel edits through axis-aligned depth slices. Slice interpolation is
## shown by the same trilinear volume texture used by the renderer.
var host: ActorInspector
var actor: ActorData
var field: ActorObjectData
var definition: ActorObjectDefinition
var view: Control
var axis:=2
var depth:=.5
var radius:=3.
var strength:=.5
var falloff:=1.
var paint_mode:=0
var grid_size:=32
var painting:=false
var before: Dictionary={}
var last:=Vector2.INF
var cursor:=Vector2(-100,-100)
var image: Image
var texture: ImageTexture

func setup(inspector: ActorInspector,owner_actor: ActorData,object: ActorObjectData,object_definition: ActorObjectDefinition) -> void:
	host=inspector; actor=owner_actor; field=object; definition=object_definition; title="3D density · slice painter"; min_size=Vector2i(480,480); close_requested.connect(_close)
	grid_size=preload("res://scripts/actors/fog/fog_field.gd").PAINT_SIZE
	var column:=VBoxContainer.new(); add_child(column); column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var toolbar:=HFlowContainer.new(); column.add_child(toolbar)
	var planes:=OptionButton.new(); toolbar.add_child(planes)
	for name in ["YZ · X depth","XZ · Y depth","XY · Z depth"]: planes.add_item(name)
	planes.select(axis); planes.item_selected.connect(func(value: int): axis=value; refresh())
	var tools:=OptionButton.new(); toolbar.add_child(tools)
	for name in ["Add","Subtract","Set","Smooth","Reset"]: tools.add_item(name)
	tools.item_selected.connect(func(value: int): paint_mode=value)
	for row in [["Depth",0.,1.,.5],["Radius",1.,16.,3.],["Strength",0.,1.,.5],["Falloff",0.,4.,1.]]:
		var label:=Label.new(); label.text=row[0]; toolbar.add_child(label)
		var slider:=HSlider.new(); slider.custom_minimum_size.x=75; slider.min_value=row[1]; slider.max_value=row[2]; slider.step=.01; slider.value=row[3]; toolbar.add_child(slider)
		slider.value_changed.connect(func(value: float):
			match row[0]:
				"Depth": depth=value; refresh()
				"Radius": radius=value
				"Strength": strength=value
				"Falloff": falloff=value
		)
	view=Control.new(); view.size_flags_vertical=Control.SIZE_EXPAND_FILL; view.mouse_filter=Control.MOUSE_FILTER_STOP; column.add_child(view); view.draw.connect(_draw); view.gui_input.connect(_input_slice); view.resized.connect(view.queue_redraw)
	var footer:=Label.new(); footer.text="Paint in 3D through the chosen slice. Esc cancels the current stroke."; footer.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(footer); refresh()

func refresh() -> void:
	image=Image.create(grid_size,grid_size,false,Image.FORMAT_RGBA8); var voxels: Dictionary=field.get_value(&"paint",{})
	for y in grid_size:
		for x in grid_size:
			var p:=point(x,y); var value:=float(voxels.get(p,0.)); image.set_pixel(x,y,Color(value*.4,value*.85,value,1))
	texture=ImageTexture.create_from_image(image); view.queue_redraw()

func point(x: int,y: int) -> Vector3i:
	var z:=clampi(roundi(depth*(grid_size-1)),0,grid_size-1)
	return Vector3i(z,x,y) if axis==0 else (Vector3i(x,z,y) if axis==1 else Vector3i(x,y,z))
func _draw() -> void:
	view.draw_texture_rect(texture,Rect2(Vector2.ZERO,view.size),false)
	view.draw_arc(cursor,radius*view.size.x/grid_size,0.,TAU,48,Color.WHITE,1.5,true)
func _input_slice(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		cursor=event.position; view.queue_redraw()
		if painting: dab(event.position)
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.pressed:
			before=ActorData.copy_value(field.get_value(&"paint",{})); painting=true; last=Vector2.INF; dab(event.position)
		else: commit()
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
		if painting: field.set_value(&"paint",before); painting=false; refresh(); host.model.changed.emit()
		else: _close()
		set_input_as_handled()
func dab(position: Vector2) -> void:
	var pixel:=position/view.size*grid_size
	if last!=Vector2.INF and pixel.distance_to(last)<maxf(.5,radius*.15): return
	last=pixel; var center:=point(clampi(int(pixel.x),0,grid_size-1),clampi(int(pixel.y),0,grid_size-1)); var voxels: Dictionary=field.get_value(&"paint",{}).duplicate()
	voxels=preload("res://scripts/actors/fog/fog_field.gd").paint_dab(voxels,center,radius,strength,falloff,paint_mode)
	field.set_value(&"paint",voxels); host.model.changed.emit(); refresh()
func commit() -> void:
	if not painting: return
	painting=false; var after: Dictionary=field.get_value(&"paint",{}); field.set_value(&"paint",before); host.model.edit_object_property(actor,field,definition,&"paint",after)
func _close() -> void:
	commit(); queue_free()
