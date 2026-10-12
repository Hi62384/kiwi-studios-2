extends RefCounted
## Contextual controls and bake operation, separate from canvas gesture logic.
const Number=preload("res://Workspaces/SceneWorkspace/scripts/Timeline/drag_number.gd")
const Picker=preload("res://Workspaces/ImageWorkspace/image_warp_picker.gd")

static func build(workspace: KiwiImageWorkspace) -> void:
	var tool=workspace.canvas.warp_tool
	var item:=workspace._main_layer()
	if item!=null and item.kind=="group":
		workspace._button(workspace.context,"Rasterize group for warp",workspace.rasterize_selected,"Convert the group to pixels with undo/redo","layers")
		return
	var modes:=workspace._toolbar_group("WARP MODE","warp")
	Picker.build(workspace,modes,"WarpMode","WARP MODE",["brush","mesh","pins"],["Warp brush","Mesh warp","Pin warp"],tool.mode,func(index: int): tool.finish(); tool.mode=["brush","mesh","pins"][index]; tool.show_grid=true if index==1 else tool.show_grid; workspace._refresh_context(); workspace.status.text=workspace._tool_hint(); workspace.canvas.queue_redraw())
	if tool.mode=="brush":
		var ids: Array[String]=["push","pinch","bulge","twirl_cw","twirl_ccw","smooth","restore","freeze","thaw"]
		Picker.build(workspace,modes,"WarpBrushType","WARP BRUSH",ids,["Push","Pinch","Bulge","Twirl clockwise","Twirl counterclockwise","Smooth geometry","Restore geometry","Freeze areas","Erase freeze"],tool.brush,func(index: int): tool.finish(); tool.brush=ids[index]; workspace._refresh_context())
		var size_group:=workspace._toolbar_group("SIZE","brush")
		var number:=Number.new(); number.min_value=2; number.max_value=2048; number.value=tool.diameter; number.suffix="px"; number.custom_minimum_size.x=86; size_group.add_child(number)
		number.preview_changed.connect(func(value: float): tool.diameter=value; workspace.canvas.queue_redraw())
		number.value_changed.connect(func(value: float): tool.diameter=value; workspace.canvas.queue_redraw())
		setting_slider(workspace,"STRENGTH",tool.strength,func(value: float): tool.strength=value)
		setting_slider(workspace,"FALLOFF",tool.hardness,func(value: float): tool.hardness=value)
		var pressure:=CheckButton.new(); pressure.text="Pressure"; pressure.button_pressed=tool.pressure_enabled; modes.add_child(pressure)
		pressure.toggled.connect(func(value: bool): tool.pressure_enabled=value)
	elif tool.mode=="mesh":
		var influence:=workspace._toolbar_group("MESH INFLUENCE","warp")
		for entry in [["Radius","mesh_radius",0.0,2.0],["Attenuation","mesh_attenuation",.1,8.0]]:
			var key: String=entry[1]; var label:=Label.new(); label.text=entry[0]; label.add_theme_font_size_override("font_size",11); influence.add_child(label)
			var value:=Number.new(); value.min_value=entry[2]; value.max_value=entry[3]; value.step=.01; value.value=tool.get(key); value.custom_minimum_size.x=70; influence.add_child(value)
			value.tooltip_text="Shift+wheel changes radius · Radius 0 moves only selected points" if key=="mesh_radius" else "Higher attenuation reduces the movement of distant points"
			value.value_changed.connect(func(next: float): tool.set(key,next); workspace.canvas.queue_redraw()); value.preview_changed.connect(func(next: float): tool.set(key,next); workspace.canvas.queue_redraw())
		var resolution:=OptionButton.new(); modes.add_child(resolution)
		for size in [4,8,16]: resolution.add_item("%d × %d" % [size,size])
		var current: int=item.warp.mesh_resolution if item!=null and item.warp!=null else tool.mesh_resolution
		resolution.select([4,8,16].find(current))
		resolution.item_selected.connect(func(index: int):
			tool.mesh_resolution=[4,8,16][index]; tool.selected_points.clear()
			if item!=null: workspace._action(func(): tool.ensure_data(item).change_resolution(tool.mesh_resolution)))
		workspace._button(modes,"Reset points",func():
			if item==null: return
			workspace._action(func():
				var data:=tool.ensure_data(item)
				for i in tool.selected_points:
					if i<data.mesh_points.size(): data.mesh_points[i]=data.mesh_origin(i)
				data.touch()),"Reset selected mesh points","reset")
		workspace._button(modes,"Reset mesh",func():
			if item!=null: workspace._action(func(): var data:=tool.ensure_data(item); data.reset_mesh(data.mesh_resolution)),"Reset all mesh points","warp")
	elif tool.mode=="pins":
		var selected: Dictionary=item.warp.pins[tool.selected_pin] if item!=null and item.warp!=null and tool.selected_pin>=0 and tool.selected_pin<item.warp.pins.size() else {}
		var radius:=Number.new(); radius.min_value=.01; radius.max_value=2; radius.step=.01; radius.value=selected.get("radius",tool.pin_radius); radius.custom_minimum_size.x=80; modes.add_child(radius)
		radius.tooltip_text="Influence radius in layer units (1 = layer width)"
		radius.value_changed.connect(func(value: float):
			tool.pin_radius=value
			if not selected.is_empty(): workspace._action(func(): selected.radius=value; item.warp.touch()))
		var lock:=CheckButton.new(); lock.text="Lock pin"; lock.button_pressed=selected.get("locked",false); lock.disabled=selected.is_empty(); modes.add_child(lock)
		lock.toggled.connect(func(value: bool): workspace._action(func(): selected.locked=value; item.warp.touch()))
		workspace._button(modes,"Reset pin",func():
			if not selected.is_empty(): workspace._action(func(): selected.target=selected.source; item.warp.touch()),"Reset the selected pin","reset")
		workspace._button(modes,"Reset pins",func():
			if item!=null and item.warp!=null: workspace._action(func():
				for pin in item.warp.pins: pin.target=pin.source
				item.warp.touch()),"Reset all pin displacements","warp")
	var options:=workspace._toolbar_group("CONSTRAINTS","mask")
	for spec in [["Selection only","selection_only"],["Show grid","show_grid"],["Freeze overlay","show_freeze"]]:
		var key: String=spec[1]; var check:=CheckButton.new(); check.text=spec[0]; check.button_pressed=tool.get(key); options.add_child(check)
		check.toggled.connect(func(value: bool): tool.set(key,value); workspace.canvas.queue_redraw())
	var actions:=workspace._toolbar_group("GEOMETRY","warp")
	workspace._button(actions,"Reset warp",func():
		if item!=null and item.warp!=null: workspace._action(func(): item.warp.reset_all()),"Reset all brush, mesh and pin deformation","reset")
	workspace._button(actions,"Clear freeze",func():
		if item!=null and item.warp!=null: workspace._action(func(): item.warp.freeze.fill(0); item.warp.touch()),"Clear the freeze mask","eraser")
	workspace._button(actions,"Bake",func(): bake(workspace),"Bake deformation to a raster layer","check")
	workspace._button(actions,"Cancel",tool.cancel,"Cancel the current gesture · Esc","close")
	var enabled:=CheckButton.new(); enabled.text="Enabled"; enabled.button_pressed=item==null or item.warp==null or item.warp.enabled; actions.add_child(enabled)
	enabled.toggled.connect(func(value: bool):
		if item!=null: workspace._action(func(): tool.ensure_data(item).enabled=value; item.warp.touch()))

static func setting_slider(workspace: KiwiImageWorkspace,caption: String,value: float,setter: Callable) -> void:
	var group:=workspace._toolbar_group(caption,"hardness")
	(group.get_parent().get_child(0) as TextureRect).texture=Picker.icon(caption.to_lower())
	var caption_label:=Label.new(); caption_label.text=caption.capitalize(); caption_label.add_theme_font_size_override("font_size",11); group.add_child(caption_label)
	var slider:=HSlider.new(); slider.min_value=0; slider.max_value=1; slider.step=.01; slider.value=value; slider.custom_minimum_size=Vector2(80,28); group.add_child(slider)
	slider.tooltip_text=caption.capitalize()
	var label:=Label.new(); label.text="%d%%" % (value*100); label.custom_minimum_size.x=35; group.add_child(label)
	slider.value_changed.connect(func(next: float): label.text="%d%%" % (next*100); setter.call(next))

static func bake(workspace: KiwiImageWorkspace) -> void:
	workspace.canvas.warp_tool.finish()
	var item:=workspace._main_layer()
	if item==null or item.warp==null: return
	if item.kind not in ["image","basic","paint"]:
		var confirmation:=ConfirmationDialog.new(); confirmation.title="Rasterize and bake warp?"
		confirmation.dialog_text="This turns the selected layer into editable pixels. Undo can restore its original structure."; workspace.add_child(confirmation)
		confirmation.confirmed.connect(func(): confirmation.queue_free(); _bake_confirmed(workspace,item.id))
		confirmation.canceled.connect(confirmation.queue_free); confirmation.popup_centered(Vector2i(430,160))
	else: _bake_confirmed(workspace,item.id)

static func _bake_confirmed(workspace: KiwiImageWorkspace,id: String) -> void:
	var item:=workspace.document.layer_for_id(id)
	if item==null or item.warp==null: return
	var temporary:=KiwiImageDocument.new(); temporary.canvas_size=Vector2i(item.content_dimensions().ceil())
	var copy:=item.copy_layer(); copy.parent_id=""; copy.position=Vector2.ZERO; copy.rotation=0; copy.dimensions=Vector2(temporary.canvas_size)
	copy.opacity=1; copy.blend=0; copy.mask=null; copy.clip_to_below=false; copy.effects.clear()
	for key in ["basis_x","basis_y","flip_x","flip_y","yaw_up_down","yaw_left_right","value_operations","value_basics"]: copy.properties.erase(key)
	temporary.layers.append(copy)
	for child in workspace.document.layers:
		if workspace.document.is_descendant(child.id,id): temporary.layers.append(child.copy_layer())
	var renderer:=KiwiImageRenderer.new(); workspace.add_child(renderer); renderer.sync(temporary)
	var image:=await renderer.flattened(); renderer.queue_free()
	if not is_instance_valid(workspace) or workspace.document.layer_for_id(id)!=item: return
	workspace._action(func():
		var children: Array[String]=[]
		for child in workspace.document.layers:
			if workspace.document.is_descendant(child.id,id): children.append(child.id)
		workspace.document.layers.assign(workspace.document.layers.filter(func(child: KiwiImageLayer): return not children.has(child.id)))
		var old_transform:=item.local_transform(); var extent:=Vector2(temporary.canvas_size)
		item.kind="basic"; item.texture=ImageTexture.create_from_image(image); item.paint_base=item.texture; item.warp=null
		item.dimensions=extent
		item.position=old_transform.origin-extent*.5+old_transform.basis_xform(extent*.5)
		for key in ["noise_image","noise_object","image_path"]: item.properties.erase(key))
	workspace.canvas.queue_redraw(); workspace.status.text="Warp baked into layer pixels"
