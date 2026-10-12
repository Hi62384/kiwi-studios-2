extends RefCounted
const Controls=preload("res://Workspaces/ImageWorkspace/image_repair_toolbar.gd")
const Picker=preload("res://Workspaces/ImageWorkspace/image_warp_picker.gd")
static func build(studio: KiwiImageWorkspace) -> void:
	var tool=studio.canvas.repair_tool
	var mode:=studio._toolbar_group("TEXTURE & REPAIR","repair")
	var item:=studio._main_layer()
	if item!=null and item.properties.get("texture_material") is KiwiTextureMaterial and tool.main_mode=="repair":
		studio._button(mode,"Bake material",studio.rasterize_selected,"Bake this material before repairing its pixels","check")
	if item!=null and (item.kind not in ["image","paint","basic"] or item.warp!=null):
		studio._button(mode,"Bake warp" if item.warp!=null else "Rasterize",func():
			if item.warp!=null: preload("res://Workspaces/ImageWorkspace/image_warp_toolbar.gd").bake(studio)
			else: studio.rasterize_selected(),"Prepare this layer for pixel editing, with undo/redo","layers")
	Picker.build(studio,mode,"RepairMode","MODE",["repair","texture"],["Repair","Texture Brush"],tool.main_mode,func(index: int):
		tool.switch_mode(["repair","texture"][index])
		studio._refresh_context())
	if tool.main_mode=="repair":
		Controls.option(mode,["Nearby","Sample"],["nearby","sample"],tool.repair_source,func(value: String): tool.repair_source=value; tool.config.source_mode="nearby" if value=="nearby" else "manual"; tool.mode="spot" if value=="nearby" else "heal")
	else:
		Controls.option(mode,["Procedural","Image"],["procedural","image"],tool.texture_source,func(value: String):
			tool.texture_source=value
			load("res://Workspaces/ImageWorkspace/texture_material_browser.gd").open(studio)
			if value=="image": studio.get_node("MaterialBrowser").import_image.call_deferred()
			else: tool.material.image=null; tool.apply_material_settings(); tool.refresh_material())
		studio._button(mode,tool.material.label.left(24) if tool.material!=null else "Choose material",func(): preload("res://Workspaces/ImageWorkspace/texture_material_browser.gd").open(studio),"Browse actual material previews, categories and favorites","noise")
	var brush:=studio._toolbar_group("BRUSH","brush")
	Controls.number(brush,"Size",tool.config.size,2,1024,1,func(value: float): tool.configure("size",value))
	Controls.setting(brush,"Hardness",tool.config.hardness,func(value: float): tool.configure("hardness",value))
	Controls.setting(brush,"Strength" if tool.main_mode=="repair" else "Opacity",tool.config.strength if tool.main_mode=="repair" else tool.config.opacity,func(value: float): tool.configure("strength" if tool.main_mode=="repair" else "opacity",value))
	if tool.main_mode=="texture":
		Controls.number(brush,"Texture Size",tool.material.texture_size,2,2048,1,func(value: float): tool.material.texture_size=value; tool.apply_material_settings(true); tool.refresh_material())
		var scale_slider:=HSlider.new(); scale_slider.min_value=1; scale_slider.max_value=11; scale_slider.step=.01; scale_slider.value=log(tool.material.texture_size)/log(2); scale_slider.custom_minimum_size.x=70; scale_slider.tooltip_text="Texture size · logarithmic scale · independent of brush size"; brush.add_child(scale_slider)
		scale_slider.value_changed.connect(func(next: float): tool.material.texture_size=pow(2,next); tool.apply_material_settings(true); tool.refresh_material()); scale_slider.drag_ended.connect(func(_changed: bool): studio._commit())
	else: studio._button(brush,"More…",func(): Controls.options(studio),"Repair quality, matching and source settings","values")
	studio._next_toolbar_row()
	var context:=studio._toolbar_group("CONTEXT","picker")
	if tool.main_mode=="texture": Controls.option(context,["Continuous","Stamp · baked","Scatter · baked"],["continuous","stamp","scatter"],tool.material.application,func(value: String): tool.material.application=value; tool.refresh_material())
	if tool.main_mode=="repair" and tool.repair_source=="sample":
		studio._button(context,"Sample source",func(): tool.pick_source=true; studio.status.text="Click clean source pixels; then paint the repair. Alt-click also samples.","Choose the replacement source","picker")
		Controls.option(context,["Natural Heal","Exact Copy"],["natural","exact"],tool.repair_method,func(value: String): tool.repair_method=value)
		Controls.option(context,["Current layer","Visible layers"],["current","visible"],tool.config.sample_mode,func(value: String): tool.config.sample_mode=value)
		var aligned:=CheckButton.new(); aligned.text="Aligned"; aligned.button_pressed=tool.config.aligned; context.add_child(aligned); aligned.toggled.connect(func(value: bool): tool.config.aligned=value; tool._has_alignment=false)
	if tool.main_mode=="texture":
		Controls.option(context,["Replace","Overlay","Colorize","Detail only"],["replace","overlay","colorize","detail"],tool.material.blending,func(value: String): tool.material.blending=value; tool.apply_material_settings(); tool.refresh_material())
		Controls.option(context,["Layer aligned","Canvas aligned","Stroke aligned"],["layer","canvas","stroke"],tool.material.alignment,func(value: String): tool.material.alignment=value; tool.apply_material_settings())
		Controls.number(context,"Rotation",tool.material.rotation,-180,180,1,func(value: float): tool.material.rotation=value; tool.apply_material_settings(true); tool.refresh_material())
		var editable:=CheckButton.new(); editable.text="Editable material layer"; editable.disabled=tool.material.application!="continuous"; editable.button_pressed=tool.config.get("editable_texture",true) and not editable.disabled; context.add_child(editable); editable.toggled.connect(func(value: bool): tool.config.editable_texture=value; tool.refresh_material())
	var actions:=studio._toolbar_group("SELECTION","mask")
	studio._button(actions,"Fill Selection" if tool.main_mode=="texture" else "Repair Selection",func(): await tool.fill_selection(); tool.finish(),"Apply to the entire active selection with undo/redo","fill")
	var selection:=CheckButton.new(); selection.text="Selection only"; selection.button_pressed=tool.config.selection_only; actions.add_child(selection); selection.toggled.connect(func(value: bool): tool.config.selection_only=value)
	for group in [brush,context]:
		for number in group.find_children("*","SpinBox",true,false):
			number.drag_committed.connect(func(_next: float): studio._commit())
			number.value_changed.connect(func(_next: float): studio._commit())
			number.drag_cancelled.connect(func(): number.preview_changed.emit(number.value); studio._cancel())
