extends RefCounted
const Controls=preload("res://Workspaces/ImageWorkspace/image_repair_toolbar.gd")
const Picker=preload("res://Workspaces/ImageWorkspace/image_warp_picker.gd")
static func build(studio: KiwiImageWorkspace) -> void:
	var tool=studio.canvas.repair_tool
	var mode:=studio._toolbar_group("REPAIR","repair")
	var item:=studio._main_layer()
	if item!=null and item.properties.get("texture_material") is KiwiTextureMaterial and tool.main_mode=="repair":
		studio._button(mode,"Bake material",studio.rasterize_selected,"Bake this material before repairing its pixels","check")
	if item!=null and (item.kind not in ["image","paint","basic"] or item.warp!=null):
		studio._button(mode,"Bake warp" if item.warp!=null else "Rasterize",func():
			if item.warp!=null: preload("res://Workspaces/ImageWorkspace/image_warp_toolbar.gd").bake(studio)
			else: studio.rasterize_selected(),"Prepare this layer for pixel editing, with undo/redo","layers")
	tool.main_mode="repair"
	if tool.main_mode=="repair":
		Controls.option(mode,["Nearby","Sample"],["nearby","sample"],tool.repair_source,func(value: String): tool.repair_source=value; tool.config.source_mode="nearby" if value=="nearby" else "manual"; tool.mode="spot" if value=="nearby" else "heal")
	var brush:=studio._toolbar_group("BRUSH","brush")
	Controls.number(brush,"Size",tool.config.size,2,1024,1,func(value: float): tool.configure("size",value))
	Controls.setting(brush,"Hardness",tool.config.hardness,func(value: float): tool.configure("hardness",value))
	Controls.setting(brush,"Strength" if tool.main_mode=="repair" else "Opacity",tool.config.strength if tool.main_mode=="repair" else tool.config.opacity,func(value: float): tool.configure("strength" if tool.main_mode=="repair" else "opacity",value))
	studio._button(brush,"More",func(): Controls.options(studio),"Repair quality, matching and source settings","values")
	studio._next_toolbar_row()
	var context:=studio._toolbar_group("CONTEXT","picker")
	if tool.main_mode=="repair" and tool.repair_source=="sample":
		studio._button(context,"Sample source",func(): tool.pick_source=true; studio.status.text="Click clean source pixels; then paint the repair. Alt-click also samples.","Choose the replacement source","picker")
		Controls.option(context,["Natural Heal","Exact Copy"],["natural","exact"],tool.repair_method,func(value: String): tool.repair_method=value)
		Controls.option(context,["Current layer","Visible layers"],["current","visible"],tool.config.sample_mode,func(value: String): tool.config.sample_mode=value)
		var aligned:=CheckButton.new(); aligned.text="Aligned"; aligned.button_pressed=tool.config.aligned; context.add_child(aligned); aligned.toggled.connect(func(value: bool): tool.config.aligned=value; tool._has_alignment=false)
	var actions:=studio._toolbar_group("SELECTION","mask")
	studio._button(actions,"Fill Selection" if tool.main_mode=="texture" else "Repair Selection",func(): await tool.fill_selection(); tool.finish(),"Apply to the entire active selection with undo/redo","fill")
	var selection:=CheckButton.new(); selection.text="Selection only"; selection.button_pressed=tool.config.selection_only; actions.add_child(selection); selection.toggled.connect(func(value: bool): tool.config.selection_only=value)
	for group in [brush,context]:
		for number in group.find_children("*","SpinBox",true,false):
			number.drag_committed.connect(func(_next: float): studio._commit())
			number.value_changed.connect(func(_next: float): studio._commit())
			number.drag_cancelled.connect(func(): number.preview_changed.emit(number.value); studio._cancel())
