extends Window
const Library=preload("res://Workspaces/ImageWorkspace/texture_material_library.gd")
const Render=preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd")
static var thumbnails: Dictionary={}
static var settings_clipboard: KiwiTextureMaterial
var studio: KiwiImageWorkspace
var grid:=GridContainer.new()
var fields:=VBoxContainer.new()
var search:=LineEdit.new()
var category:="Wood"
var generation:=0
var preview: TextureRect
var preview_viewport: SubViewport
var _filter_generation:=0
var preview_zoom:=1.0
var preview_pan:=Vector2.ZERO
var preview_drag:=false
var custom_materials: Dictionary={}
var active_path:=""

static func open(workspace: KiwiImageWorkspace) -> void:
	var existing:=workspace.get_node_or_null("MaterialBrowser")
	if existing!=null: existing.grab_focus(); return
	var browser=load("res://Workspaces/ImageWorkspace/texture_material_browser.gd").new(); browser.studio=workspace; browser.name="MaterialBrowser"; workspace.add_child(browser)
	browser.popup_centered(Vector2i(1000,640))

func _ready() -> void:
	custom_materials=studio.canvas.repair_tool.custom_materials
	title="Materials · Texture Brush"; min_size=Vector2i(780,480); transient=true; exclusive=false
	close_requested.connect(close)
	var background:=ColorRect.new(); background.color=Color("111c28"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var margin:=MarginContainer.new(); margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); margin.add_theme_constant_override("margin_left",12); margin.add_theme_constant_override("margin_right",12); margin.add_theme_constant_override("margin_top",12); margin.add_theme_constant_override("margin_bottom",12); add_child(margin)
	var layout:=VBoxContainer.new(); margin.add_child(layout)
	var header:=HBoxContainer.new(); layout.add_child(header)
	search.placeholder_text="Search materials…"; search.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(search); search.text_changed.connect(func(_value: String): refresh_grid())
	var categories:=OptionButton.new(); header.add_child(categories)
	for name in ["All","Favorites","Recent"]+Library.CATEGORIES.keys()+["Custom"]: categories.add_item(name)
	category=Library.category(studio.canvas.repair_tool.material.material_id)
	for index in categories.item_count:
		if categories.get_item_text(index)==category: categories.select(index)
	categories.item_selected.connect(func(index: int): category=categories.get_item_text(index); refresh_grid())
	studio._button(header,"Import image",import_image,"Use a project image as a brush texture","image")
	studio._button(header,"Load preset",load_material,"Load a saved independent material preset","folder")
	studio._button(header,"Copy settings",func(): settings_clipboard=studio.canvas.repair_tool.material.copy_material(),"Copy this material's settings","copy")
	studio._button(header,"Paste",func():
		if settings_clipboard!=null: studio.canvas.repair_tool.material=settings_clipboard.copy_material(); changed(); studio._commit(); rebuild_fields(),"Paste an independent copy of material settings","paste")
	var split:=HSplitContainer.new(); split.size_flags_vertical=Control.SIZE_EXPAND_FILL; layout.add_child(split); split.split_offset=350
	var scroll:=ScrollContainer.new(); scroll.custom_minimum_size.x=300; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; split.add_child(scroll)
	grid.columns=3; grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(grid)
	var right:=VBoxContainer.new(); right.size_flags_horizontal=Control.SIZE_EXPAND_FILL; split.add_child(right)
	preview_viewport=SubViewport.new(); preview_viewport.disable_3d=true; preview_viewport.transparent_bg=true; preview_viewport.size=Vector2i(512,256); preview_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; add_child(preview_viewport)
	var drawing:=ColorRect.new(); drawing.size=Vector2(512,256); preview_viewport.add_child(drawing)
	preview=TextureRect.new(); preview.texture=preview_viewport.get_texture(); preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; preview.custom_minimum_size=Vector2(300,180); right.add_child(preview)
	preview.tooltip_text="Scroll to zoom · Middle-drag to pan"; preview.gui_input.connect(preview_input)
	var settings_scroll:=ScrollContainer.new(); settings_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; settings_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; right.add_child(settings_scroll); fields.size_flags_horizontal=Control.SIZE_EXPAND_FILL; settings_scroll.add_child(fields)
	var footer:=HBoxContainer.new(); right.add_child(footer)
	studio._button(footer,"Reset",func(): studio.canvas.repair_tool.material=Library.create(studio.canvas.repair_tool.material.material_id); changed(); studio._commit(); rebuild_fields(),"Reset this instance, not other documents","reset")
	studio._button(footer,"Default / current",func(): drawing.material=Render.material(Library.create(studio.canvas.repair_tool.material.material_id) if drawing.get_meta("default",false)==false else studio.canvas.repair_tool.material,Vector2(512,256)); drawing.set_meta("default",not drawing.get_meta("default",false)),"Compare the factory material with your edited instance","eye")
	studio._button(footer,"Save",func(): save_material(false),"Update the loaded material preset","save")
	studio._button(footer,"Save new",func(): save_material(true),"Save an independent reusable project resource","plus")
	studio._button(footer,"Close",close,"Keep current settings","check")
	refresh_grid(); rebuild_fields(); update_preview()

func refresh_grid() -> void:
	_filter_generation+=1; var request:=_filter_generation
	for child in grid.get_children(): grid.remove_child(child); child.queue_free()
	var ids: Array=Library.ids()
	if category=="All": ids.append_array(custom_materials.keys())
	var selection_group:=ButtonGroup.new()
	if category=="Recent": ids=Array(studio.canvas.repair_tool.recent)
	if category=="Custom": ids=custom_materials.keys()
	for id in ids:
		if custom_materials.has(id):
			if not search.text.is_empty() and not custom_materials[id].label.to_lower().contains(search.text.to_lower()): continue
			var card:=VBoxContainer.new(); grid.add_child(card)
			var button:=Button.new(); button.text=custom_materials[id].label; button.custom_minimum_size=Vector2(96,96); button.expand_icon=true; button.add_theme_constant_override("icon_max_width",80); card.add_child(button)
			button.pressed.connect(func(): studio._commit(); studio.canvas.repair_tool.material=custom_materials[id].copy_material(); active_path=id; changed(); studio._commit(); rebuild_fields())
			var remove:=Button.new(); remove.text="Remove preset"; remove.tooltip_text="Remove from this document's preset list; saved file is kept"; card.add_child(remove); remove.pressed.connect(func(): custom_materials.erase(id); refresh_grid())
			if thumbnails.has(id): button.icon=thumbnails[id]
			else:
				var bitmap:=await Render.preview(self,custom_materials[id],Vector2i(80,80))
				if bitmap==null or request!=_filter_generation: return
				thumbnails[id]=ImageTexture.create_from_image(bitmap)
				if is_instance_valid(button): button.icon=thumbnails[id]
			continue
		if category!="All" and category!="Favorites" and category!="Recent" and Library.category(id)!=category: continue
		if category=="Favorites" and not studio.canvas.repair_tool.favorites.has(id): continue
		if category=="Recent" and not studio.canvas.repair_tool.recent.has(id): continue
		var value:=Library.create(id)
		if not search.text.is_empty() and not (value.label+" "+Library.category(id)).to_lower().contains(search.text.to_lower()): continue
		var card:=VBoxContainer.new(); card.custom_minimum_size.x=90; grid.add_child(card)
		var button:=Button.new(); button.custom_minimum_size=Vector2(90,76); button.expand_icon=true; button.add_theme_constant_override("icon_max_width",80); card.add_child(button)
		button.toggle_mode=true; button.button_group=selection_group; button.button_pressed=studio.canvas.repair_tool.material.material_id==id and studio.canvas.repair_tool.material.image==null
		button.tooltip_text=value.label+" · "+Library.category(id)
		button.pressed.connect(func(): studio._commit(); studio.canvas.repair_tool.choose_material(id); active_path=""; rebuild_fields(); update_preview())
		var row:=HBoxContainer.new(); card.add_child(row)
		var name:=Label.new(); name.text=value.label; name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; name.custom_minimum_size.x=66; name.size_flags_horizontal=Control.SIZE_EXPAND_FILL; name.add_theme_font_size_override("font_size",11); row.add_child(name)
		var star:=Button.new(); star.text="★" if studio.canvas.repair_tool.favorites.has(id) else "☆"; row.add_child(star)
		star.pressed.connect(func():
			var tool=studio.canvas.repair_tool
			if tool.favorites.has(id): tool.favorites.erase(id)
			else: tool.favorites.append(id)
			star.text="★" if tool.favorites.has(id) else "☆")
		if thumbnails.has(id): button.icon=thumbnails[id]
		else:
			var bitmap:=await Render.preview(self,value,Vector2i(80,80))
			if bitmap==null or request!=_filter_generation: return
			thumbnails[id]=ImageTexture.create_from_image(bitmap)
			if is_instance_valid(button): button.icon=thumbnails[id]

func changed() -> void:
	studio.canvas.repair_tool.apply_material_settings(true); studio.canvas.repair_tool.refresh_material(); update_preview()

func refresh_from_layer() -> void:
	var layer:=studio._main_layer()
	if layer!=null and layer.properties.get("texture_material") is KiwiTextureMaterial:
		studio.canvas.repair_tool.material=layer.properties.texture_material.copy_material()
		studio.canvas.repair_tool.material.coverage=null; studio.canvas.repair_tool.material.source=null
		rebuild_fields(); update_preview()

func update_preview() -> void:
	if preview_viewport==null: return
	var value:=studio.canvas.repair_tool.material.copy_material(); value.coverage=null
	value.blending="replace"
	var shader:=Render.material(value,Vector2(preview_viewport.size)/preview_zoom,Transform2D.IDENTITY,true)
	shader.set_shader_parameter("origin",preview_pan)
	(preview_viewport.get_child(0) as ColorRect).material=shader
	preview_viewport.get_child(0).set_meta("default",false)

func rebuild_fields() -> void:
	for child in fields.get_children(): fields.remove_child(child); child.queue_free()
	var tool=studio.canvas.repair_tool; var value: KiwiTextureMaterial=tool.material
	var title_label:=Label.new(); title_label.text=value.label; title_label.add_theme_font_size_override("font_size",18); fields.add_child(title_label)
	var rename:=LineEdit.new(); rename.text=value.label; rename.placeholder_text="Material name"; fields.add_child(rename); rename.text_submitted.connect(func(next: String): value.label=next; changed(); studio._commit())
	for group in ["Appearance","Structure","Variation","Placement","Mixer","Relief"]:
		var section:=VBoxContainer.new(); var toggle:=Button.new(); toggle.text="▾ "+group; fields.add_child(toggle); fields.add_child(section); toggle.pressed.connect(func(): section.visible=not section.visible)
		if group=="Appearance":
			for key in ["primary","secondary"]:
				if value.image!=null and key=="secondary": continue
				var row:=HBoxContainer.new(); section.add_child(row); var label:=Label.new(); label.text="Base color" if key=="primary" else "Detail color"; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
				var color:=ColorPickerButton.new(); color.color=value.parameters.get(key,Color.WHITE); color.custom_minimum_size=Vector2(90,28); row.add_child(color); color.color_changed.connect(func(next: Color): value.parameters[key]=next; changed()); color.popup_closed.connect(studio._commit)
			field(section,"Contrast","contrast",0,3,.01); field(section,"Brightness","brightness",-1,1,.01)
			if value.image!=null:
				var row:=HBoxContainer.new(); section.add_child(row)
				preload("res://Workspaces/ImageWorkspace/image_repair_toolbar.gd").number(row,"Image tint strength",value.tint_strength,0,1,.01,func(next: float): value.tint_strength=next; changed()); row.get_child(1).value_changed.connect(func(_next: float): studio._commit())
				var tiling:=OptionButton.new(); section.add_child(tiling)
				for caption in ["Repeat image","Mirrored repeat","Clamp edges"]: tiling.add_item(caption)
				tiling.select(maxi(0,["repeat","mirror","clamp"].find(value.tiling))); tiling.item_selected.connect(func(index: int): value.tiling=["repeat","mirror","clamp"][index]; changed(); studio._commit())
				studio._button(section,"Remove image",func(): value.image=null; tool.texture_source="procedural"; changed(); studio._commit(); rebuild_fields(),"Return to the procedural material","close")
		if group=="Structure":
			if value.image!=null: toggle.hide(); section.hide(); continue
			var mapping:={"density":"Detail density","thickness":"Feature width","roughness":"Surface roughness","distortion":"Structure distortion","detail":"Fine detail","knots":"Knot density","frequency":"Frequency","octaves":"Octaves","gain":"Noise gain","lacunarity":"Lacunarity"}
			for key in Library.controls(value.material_id): field(section,Library.control_label(value.material_id,key),key,.001 if key=="frequency" else (1 if key=="octaves" else .01),8 if key in ["density","octaves","lacunarity"] else 1,.001 if key=="frequency" else (1.0 if key=="octaves" else .01))
		if group=="Variation":
			field(section,"Random seed","seed",0,100000,1)
		if group=="Placement":
			section.visible=false
			for entry in [["Stamp spacing","spacing",.1,3],["Scatter jitter","jitter",0,1],["Rotation variation","random_rotation",0,180],["Scale variation","random_scale",0,.8]]:
				var row:=HBoxContainer.new(); section.add_child(row); var key: String=entry[1]
				preload("res://Workspaces/ImageWorkspace/image_repair_toolbar.gd").number(row,entry[0],value.get(key),entry[2],entry[3],.01,func(next: float): value.set(key,next); changed()); row.get_child(1).value_changed.connect(func(_next: float): studio._commit())
			var follow:=CheckButton.new(); follow.text="Follow direction · stroke alignment / stamps"; follow.button_pressed=value.follow_direction; section.add_child(follow); follow.toggled.connect(func(next: bool): value.follow_direction=next; changed(); studio._commit())
			var smooth_row:=HBoxContainer.new(); section.add_child(smooth_row)
			preload("res://Workspaces/ImageWorkspace/image_repair_toolbar.gd").number(smooth_row,"Direction smoothing",value.direction_smoothing,0,1,.01,func(next: float): value.direction_smoothing=next; changed()); smooth_row.get_child(1).value_changed.connect(func(_next: float): studio._commit())
		if group=="Mixer":
			section.visible=false
			var enabled:=CheckButton.new(); enabled.text="Mix another material"; enabled.button_pressed=value.secondary!=null; section.add_child(enabled)
			enabled.toggled.connect(func(next: bool): value.secondary=Library.create("stone/marble") if next else null; value.mix_amount=.5 if next else 0.; changed(); studio._commit(); rebuild_fields())
			if value.secondary!=null:
				var choose:=OptionButton.new(); section.add_child(choose); var ids:=Library.ids()
				for id in ids: choose.add_item(Library.category(id)+" / "+Library.create(id).label)
				choose.select(maxi(0,ids.find(value.secondary.material_id))); choose.item_selected.connect(func(index: int): value.secondary=Library.create(ids[index]); changed(); studio._commit(); rebuild_fields())
				var row:=HBoxContainer.new(); section.add_child(row)
				preload("res://Workspaces/ImageWorkspace/image_repair_toolbar.gd").number(row,"Mix amount",value.mix_amount,0,1,.01,func(next: float): value.mix_amount=next; changed()); row.get_child(1).value_changed.connect(func(_next: float): studio._commit())
				var distribution:=OptionButton.new(); section.add_child(distribution)
				for caption in ["Uniform","Noise","Patches","Captured selection"]: distribution.add_item(caption)
				var types:=["uniform","noise","patches","selection"]; distribution.select(maxi(0,types.find(value.mix_distribution)))
				distribution.item_selected.connect(func(index: int):
					if index==3:
						var layer:=studio._main_layer()
						if layer==null or studio.canvas.selection==null: return
						value.mix_mask=await preload("res://Workspaces/ImageWorkspace/image_selection_fill.gd").capture_local_mask(studio,layer)
					value.mix_distribution=types[index]; changed(); studio._commit())
				for entry in [["Texture size","texture_size",2,2048],["Rotation","rotation",-180,180]]:
					var second_row:=HBoxContainer.new(); section.add_child(second_row); var key: String=entry[1]
					preload("res://Workspaces/ImageWorkspace/image_repair_toolbar.gd").number(second_row,entry[0],value.secondary.get(key),entry[2],entry[3],1,func(next: float): value.secondary.set(key,next); changed()); second_row.get_child(1).value_changed.connect(func(_next: float): studio._commit())
				for key in ["primary","secondary"]:
					var color:=ColorPickerButton.new(); color.text="Second material "+key; color.color=value.secondary.parameters[key]; section.add_child(color)
					color.color_changed.connect(func(next: Color): value.secondary.parameters[key]=next; changed()); color.popup_closed.connect(studio._commit)
		if group=="Relief":
			section.visible=false
			for entry in [["Height / depth","relief",-2,2],["Light direction","light_direction",0,360],["Highlights","highlight",0,2],["Shadows","shadow",0,2],["Softness","relief_softness",0,1]]:
				var key: String=entry[1]; var row:=HBoxContainer.new(); section.add_child(row)
				preload("res://Workspaces/ImageWorkspace/image_repair_toolbar.gd").number(row,entry[0],value.get(key),entry[2],entry[3],.01,func(next: float): value.set(key,next); changed())
				row.get_child(1).value_changed.connect(func(_next: float): studio._commit())
	for number in fields.find_children("*","SpinBox",true,false):
		number.drag_committed.connect(func(_next: float): studio._commit())
		number.drag_cancelled.connect(func(): number.preview_changed.emit(number.value); studio._cancel(); refresh_from_layer())

func field(parent: Node,label: String,key: String,minimum: float,maximum: float,step: float) -> void:
	var value: KiwiTextureMaterial=studio.canvas.repair_tool.material; var row:=HBoxContainer.new(); parent.add_child(row)
	preload("res://Workspaces/ImageWorkspace/image_repair_toolbar.gd").number(row,label,float(value.parameters.get(key,1)),minimum,maximum,step,func(next: float): value.parameters[key]=int(next) if step==1 else next; changed())
	var input=row.get_child(1); input.value_changed.connect(func(_next: float): studio._commit())
	var slider:=HSlider.new(); slider.min_value=minimum; slider.max_value=maximum; slider.step=step; slider.value=value.parameters.get(key,1); slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL; slider.custom_minimum_size.x=70; row.add_child(slider)
	slider.value_changed.connect(func(next: float): input.set_value_no_signal(next); value.parameters[key]=int(next) if step==1 else next; changed())
	slider.drag_ended.connect(func(_changed: bool): studio._commit())
	var reset:=Button.new(); reset.text="↺"; reset.tooltip_text="Reset "+label; row.add_child(reset); reset.pressed.connect(func(): var next=Library.create(value.material_id).parameters.get(key,1); input.set_value_no_signal(next); slider.set_value_no_signal(next); value.parameters[key]=next; changed(); studio._commit())

func import_image() -> void:
	var property:=ActorProperty.new(); property.options={"extensions":KiwiImageWorkspace.IMAGE_EXTENSIONS,"file_picker":true}
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Choose brush image")
	if chosen.is_empty() or chosen==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var image:=Image.load_from_file(chosen)
	if image==null: return
	image.generate_mipmaps()
	var value:=Library.create("geometry/checkerboard"); value.label=chosen.get_file(); value.image=ImageTexture.create_from_image(image)
	studio.canvas.repair_tool.material=value; studio.canvas.repair_tool.texture_source="image"; changed(); studio._commit(); rebuild_fields(); studio._refresh_context()

func save_material(as_new: bool=false) -> void:
	var value:=studio.canvas.repair_tool.material.copy_material(); value.coverage=null; value.source=null
	if as_new or active_path.is_empty():
		var result:=await ActorProjectResourceSaveDialog.pick(self,"Save material preset",value.label,"tres",false)
		if result.get("cancelled",true): return
		active_path=result.path
	if ResourceSaver.save(value,active_path)!=OK: studio.status.text="Could not save material"; return
	thumbnails.erase(active_path)
	custom_materials[active_path]=value; studio._commit()
	if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()

func load_material() -> void:
	var property:=ActorProperty.new(); property.options={"extensions":["tres","res"],"file_picker":true}
	var path:=await ActorProjectFilePicker.pick(self,property,"Load material preset")
	if path.is_empty() or path==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var value:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiTextureMaterial
	if value==null: studio.status.text="Choose a texture material preset"; return
	studio._commit(); custom_materials[path]=value.copy_material(); studio.canvas.repair_tool.material=value.copy_material(); active_path=path; changed(); studio._commit(); rebuild_fields()

func close() -> void:
	studio._commit(); _filter_generation+=1; queue_free()

func preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_MIDDLE: preview_drag=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: preview_zoom=clampf(preview_zoom*(1.2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.2),.1,16); update_preview()
	if event is InputEventMouseMotion and preview_drag: preview_pan-=event.relative/preview_zoom; update_preview()
