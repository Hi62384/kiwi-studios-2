extends PanelContainer
## Shared nonmodal editor: the same independent material instance is used in both workspaces.
signal material_changed(value: KiwiTextureMaterial)
signal edit_committed
const Library=preload("res://Workspaces/ImageWorkspace/texture_material_library.gd")
const Render=preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd")
const Presets=preload("res://scripts/materials/natural_material_presets.gd")
const HISTORY_PATH="user://natural_material_browser.tres"
static var thumbnails: Dictionary={}
static var settings_clipboard: KiwiTextureMaterial
var studio: KiwiImageWorkspace
var value: KiwiTextureMaterial
var grid:=GridContainer.new()
var fields:=VBoxContainer.new()
var catalog_panel:=VBoxContainer.new()
var settings_scroll:=ScrollContainer.new()
var browse_tab: Button
var settings_tab: Button
var search:=LineEdit.new()
var category:="All"
var preview_viewport: SubViewport
var preview_zoom:=1.0
var preview_pan:=Vector2.ZERO
var preview_drag:=false
var favorites:=PackedStringArray()
var recent:=PackedStringArray()
var custom_materials: Dictionary={}
var active_path:=""
var _filter_generation:=0
var _closed:=false
var _thumbnail_busy:=false
var _original_value: KiwiTextureMaterial
var _comparing:=false
var _advanced_open:=false
var _sidebar_width:=-1.0

static func open(workspace: KiwiImageWorkspace) -> void:
	var existing:=workspace.get_node_or_null("MaterialBrowser")
	if existing!=null and existing.is_closed(): existing=null
	if existing!=null: existing.show(); existing.refresh_from_layer(); existing.reload_shared_presets(); existing.refresh_grid(); return
	var template=workspace.document.live_material_for_id(workspace.document.active_live_material_id)
	if workspace.document.live_edit_enabled and template!=null:
		workspace.canvas.repair_tool.material=template.material.copy_material(); workspace._refresh_context()
	var browser=load("res://Workspaces/ImageWorkspace/texture_material_browser.gd").new()
	browser.studio=workspace; browser.value=workspace.canvas.repair_tool.material.copy_material(); browser.name="MaterialBrowser"
	workspace.add_child(browser)
	browser.material_changed.connect(workspace._material_changed); browser.edit_committed.connect(workspace._material_edit_committed)
	browser.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	browser.offset_left=-370; browser.offset_right=-8; browser.offset_top=180; browser.offset_bottom=workspace.size.y-28
	workspace.resized.connect(func(): if is_instance_valid(browser): browser.offset_bottom=workspace.size.y-28)
	browser._sidebar_width=workspace._side_split.custom_minimum_size.x
	workspace._side_split.custom_minimum_size.x=380

static func open_for_material(host: Node,material: KiwiTextureMaterial,changed_callback: Callable) -> PanelContainer:
	var browser=load("res://Workspaces/ImageWorkspace/texture_material_browser.gd").new()
	browser.value=material.copy_material(); browser.material_changed.connect(changed_callback)
	if host is Control:
		host.add_child(browser); browser.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		browser.offset_left=-380; browser.offset_right=-8; browser.offset_top=12; browser.offset_bottom=-12
	else:
		var window:=Window.new(); window.title="Natural Material"; window.size=Vector2i(380,700); window.exclusive=false; host.add_child(window)
		window.add_child(browser); browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		window.close_requested.connect(window.queue_free); browser.tree_exiting.connect(window.queue_free); window.popup_centered()
	return browser

func _ready() -> void:
	custom_minimum_size=Vector2(340,400)
	var style:=StyleBoxFlat.new(); style.bg_color=Color("17232f"); style.border_color=Color("4b706a"); style.set_border_width_all(1); style.set_content_margin_all(10); add_theme_stylebox_override("panel",style)
	if value==null: value=Library.create("wood/oak")
	_original_value=value.copy_material()
	_load_history()
	reload_shared_presets()
	var layout:=VBoxContainer.new(); add_child(layout)
	var heading:=HBoxContainer.new(); layout.add_child(heading)
	var title:=Label.new(); title.text="NATURAL MATERIALS"; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; heading.add_child(title); _button(heading,"Close",close)
	var tabs:=HBoxContainer.new(); layout.add_child(tabs)
	browse_tab=_button(tabs,"Browse materials",func(): _show_catalog(true)); browse_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	settings_tab=_button(tabs,"Settings",func(): _show_catalog(false)); settings_tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	layout.add_child(catalog_panel); catalog_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	search.placeholder_text="Search name, family, pattern"; catalog_panel.add_child(search); search.text_changed.connect(func(_text: String): refresh_grid())
	var categories:=OptionButton.new(); catalog_panel.add_child(categories)
	for label in ["All","Favorites","Recent","Custom"]+Library.CATEGORIES.keys(): categories.add_item(label)
	categories.item_selected.connect(func(index: int): category=categories.get_item_text(index); refresh_grid())
	var catalog_scroll:=ScrollContainer.new(); catalog_scroll.custom_minimum_size.y=150; catalog_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; catalog_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; catalog_panel.add_child(catalog_scroll)
	grid.columns=3; grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL; catalog_scroll.add_child(grid)
	preview_viewport=SubViewport.new(); preview_viewport.disable_3d=true; preview_viewport.transparent_bg=true; preview_viewport.size=Vector2i(384,144); preview_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE; add_child(preview_viewport)
	var drawing:=ColorRect.new(); drawing.size=Vector2(preview_viewport.size); preview_viewport.add_child(drawing)
	var preview:=TextureRect.new(); preview.texture=preview_viewport.get_texture(); preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; preview.custom_minimum_size=Vector2(300,72); layout.add_child(preview)
	preview.tooltip_text="Actual material output. Scroll to zoom; middle-drag to pan."; preview.gui_input.connect(preview_input)
	settings_scroll.name="MaterialSettingsScroll"; settings_scroll.custom_minimum_size.y=120; settings_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; settings_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; layout.add_child(settings_scroll)
	fields.size_flags_horizontal=Control.SIZE_EXPAND_FILL; settings_scroll.add_child(fields)
	var footer:=HBoxContainer.new(); layout.add_child(footer)
	_button(footer,"Reset",func(): active_path=""; set_material_value(Library.create(value.material_id)); changed(); edit_committed.emit())
	_button(footer,"Copy",func(): settings_clipboard=value.copy_material())
	_button(footer,"Paste",func(): if settings_clipboard!=null: set_material_value(settings_clipboard); changed(); edit_committed.emit())
	_button(footer,"Save new",func(): save_material(true)); _button(footer,"Update",func(): save_material(false))
	var compare:=Button.new(); compare.text="Hold to compare before" if studio!=null else "Hold to compare preview"; compare.tooltip_text="Temporarily compare the original material on the preview and linked artwork"; layout.add_child(compare)
	compare.button_down.connect(func(): _compare(true)); compare.button_up.connect(func(): _compare(false))
	var imports:=HBoxContainer.new(); layout.add_child(imports); _button(imports,"Import preset",load_material); _button(imports,"Image texture",import_image)
	rebuild_fields(); update_preview(); _show_catalog(false)

func _button(parent: Node,caption: String,callback: Callable) -> Button:
	var button:=Button.new(); button.text=caption; button.add_theme_font_size_override("font_size",11); parent.add_child(button); button.pressed.connect(callback); return button

func set_material_value(next: KiwiTextureMaterial) -> void:
	value=next.copy_material(); value.coverage=null; value.source=null; _original_value=value.copy_material()
	if is_node_ready(): rebuild_fields(); update_preview()

func refresh_from_layer() -> void:
	if studio==null: return
	var active=studio.document.live_material_for_id(studio.document.active_live_material_id)
	if studio.document.live_edit_enabled and active!=null: studio.canvas.repair_tool.material=active.material.copy_material()
	set_material_value(studio.canvas.repair_tool.material)

func changed() -> void:
	if studio!=null and studio.canvas._material_busy:
		set_material_value(studio.canvas.repair_tool.material); return
	material_changed.emit(value.copy_material()); update_preview()

func update_preview() -> void:
	if preview_viewport==null: return
	var copy:=(_original_value if _comparing and _original_value!=null else value).copy_material(); copy.coverage=null; copy.source=null; copy.blending="replace"
	var shader:=Render.material(copy,Vector2(preview_viewport.size)/preview_zoom,Transform2D.IDENTITY,true); shader.set_shader_parameter("origin",preview_pan)
	preview_viewport.get_child(0).material=shader; preview_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE

func reload_shared_presets() -> void:
	for preset in Presets.list_presets():
		var saved:=Presets.load_material(preset.id)
		if saved!=null: custom_materials[preset.id]=saved

func refresh_grid() -> void:
	_filter_generation+=1; var request:=_filter_generation
	if not catalog_panel.visible: return
	for child in grid.get_children(): grid.remove_child(child); child.queue_free()
	var builtin_ids:=Library.ids()
	var ids: Array=builtin_ids.duplicate()
	if category in ["All","Custom","Favorites"]: ids.append_array(custom_materials.keys())
	if category=="Custom": ids=custom_materials.keys()
	if category=="Recent": ids=Array(recent)
	for id: String in ids:
		var custom: bool=custom_materials.has(id)
		if not custom and not builtin_ids.has(id): continue
		if category=="Favorites" and not favorites.has(id): continue
		if category not in ["All","Favorites","Recent","Custom"] and (custom or Library.category(id)!=category): continue
		var sample: KiwiTextureMaterial=custom_materials[id] if custom else Library.create(id)
		if not search.text.is_empty() and not (sample.label+" "+sample.material_id).to_lower().contains(search.text.to_lower()): continue
		var card:=VBoxContainer.new(); card.custom_minimum_size.x=98; grid.add_child(card)
		var button:=Button.new(); button.text=""; button.clip_text=true; button.custom_minimum_size=Vector2(100,74); button.expand_icon=true; button.add_theme_constant_override("icon_max_width",78); button.tooltip_text=sample.label+" / "+Library.category(sample.material_id); card.add_child(button)
		button.pressed.connect(func():
			edit_committed.emit(); active_path=id if custom else ""; set_material_value(sample); changed(); edit_committed.emit(); _show_catalog(false)
			recent.erase(id); recent.insert(0,id)
			if recent.size()>24: recent.resize(24)
			_save_history())
		var caption:=Label.new(); caption.text=sample.label; caption.custom_minimum_size.x=98; caption.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; caption.add_theme_font_size_override("font_size",11); card.add_child(caption)
		var star:=_button(card,"Favorite *" if favorites.has(id) else "Favorite",func():
			if favorites.has(id): favorites.erase(id)
			else: favorites.append(id)
			_save_history(); refresh_grid())
		star.tooltip_text="Favorite "+sample.label
		var key:=str(hash(preload("res://scripts/materials/natural_material_engine.gd").settings_from_material(sample)))
		if thumbnails.has(key): button.icon=thumbnails[key]
		else:
			while _thumbnail_busy:
				await get_tree().process_frame
				if _closed or request!=_filter_generation: return
			_thumbnail_busy=true
			var bitmap: Image=await Render.preview(self,sample,Vector2i(88,64))
			_thumbnail_busy=false
			if _closed or request!=_filter_generation: return
			if bitmap!=null and is_instance_valid(button):
				if thumbnails.size()>192: thumbnails.erase(thumbnails.keys()[0])
				thumbnails[key]=ImageTexture.create_from_image(bitmap); button.icon=thumbnails[key]

func rebuild_fields() -> void:
	for child in fields.get_children(): fields.remove_child(child); child.queue_free()
	var name_input:=LineEdit.new(); name_input.text=value.label; fields.add_child(name_input)
	name_input.text_submitted.connect(func(next: String): value.label=next; changed(); edit_committed.emit())
	for key in ["primary","secondary"]:
		var row:=HBoxContainer.new(); fields.add_child(row)
		var label:=Label.new(); label.text="Primary color" if key=="primary" else "Secondary color"; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
		var picker:=ColorPickerButton.new(); picker.color=value.parameters.get(key,Color.WHITE); picker.custom_minimum_size=Vector2(92,26); row.add_child(picker)
		picker.color_changed.connect(func(next: Color): value.parameters[key]=next; changed()); picker.popup_closed.connect(func(): edit_committed.emit())
	_number(fields,"Texture Size",value.texture_size,2,2048,1,func(next: float): value.texture_size=next; changed())
	if value.image==null:
		for parameter in Library.schema(value.material_id):
			var key: String=parameter.key
			_number(fields,str(parameter.label),float(value.parameters.get(key,parameter.default)),float(parameter.min),float(parameter.max),float(parameter.step),func(next: float): value.parameters[key]=next; changed())
	var emboss:=CheckButton.new(); emboss.text="Emboss" if studio!=null else "Surface relief"; emboss.button_pressed=not is_zero_approx(value.relief); fields.add_child(emboss)
	emboss.toggled.connect(func(enabled: bool): value.relief=.6 if enabled else 0.; changed(); edit_committed.emit(); rebuild_fields())
	if not is_zero_approx(value.relief):
		_number(fields,"Emboss strength" if studio!=null else "Relief strength",value.relief,0,2,.01,func(next: float): value.relief=next; changed())
		if studio!=null: _number(fields,"Shadow direction",value.light_direction,0,360,1,func(next: float): value.light_direction=next; changed())
	var advanced:=VBoxContainer.new(); _button(fields,"Advanced",func(): _advanced_open=not _advanced_open; advanced.visible=_advanced_open); fields.add_child(advanced); advanced.visible=_advanced_open
	_number(advanced,"Rotation",value.rotation,-180,180,1,func(next: float): value.rotation=next; changed())
	_number(advanced,"Seed",float(value.parameters.get("seed",0)),0,100000,1,func(next: float): value.parameters.seed=int(next); changed())
	_number(advanced,"Contrast",float(value.parameters.get("contrast",1)),0,3,.01,func(next: float): value.parameters.contrast=next; changed())
	var mapping:=OptionButton.new(); advanced.add_child(mapping); mapping.visible=studio!=null
	for text in ["Canvas aligned","Layer aligned","Stroke direction aligned"]: mapping.add_item(text)
	var mappings:=["canvas","layer","stroke"]; mapping.select(maxi(0,mappings.find(value.alignment)))
	mapping.item_selected.connect(func(index: int): value.alignment=mappings[index]; changed(); edit_committed.emit())
	if value.image!=null:
		_number(advanced,"Image tint",value.tint_strength,0,1,.01,func(next: float): value.tint_strength=next; changed())
		_choice(advanced,"Image tiling",["Repeat","Mirror","Clamp"],["repeat","mirror","clamp"],value.tiling,func(next: String): value.tiling=next; changed())
	if studio!=null:
		_choice(advanced,"Brush application",["Continuous","Stamps","Scatter"],["continuous","stamp","scatter"],value.application,func(next: String): value.application=next; changed(); rebuild_fields())
		if value.application!="continuous":
			_number(advanced,"Stamp spacing",value.spacing,.1,3,.05,func(next: float): value.spacing=next; changed())
			if value.application=="scatter": _number(advanced,"Scatter spread",value.jitter,0,1,.01,func(next: float): value.jitter=next; changed())
			_number(advanced,"Random rotation",value.random_rotation,0,180,1,func(next: float): value.random_rotation=next; changed())
			_number(advanced,"Random scale",value.random_scale,0,1,.01,func(next: float): value.random_scale=next; changed())
			var follow:=CheckButton.new(); follow.text="Follow stroke direction"; follow.button_pressed=value.follow_direction; advanced.add_child(follow)
			follow.toggled.connect(func(next: bool): value.follow_direction=next; changed(); edit_committed.emit())
	var blend_ids: Array=[""]; var blend_names: Array=["No second material"]
	for id in Library.ids(): blend_ids.append(id); blend_names.append(Library.create(id).label)
	for id in custom_materials: blend_ids.append(id); blend_names.append(custom_materials[id].label)
	_choice(advanced,"Mix material",blend_names,blend_ids,value.secondary.material_id if value.secondary!=null else "",func(next: String):
		value.secondary=custom_materials[next].copy_material() if custom_materials.has(next) else (Library.create(next) if not next.is_empty() else null)
		if value.secondary!=null: value.secondary.secondary=null; value.mix_amount=maxf(.5,value.mix_amount)
		changed(); rebuild_fields())
	if value.secondary!=null:
		_number(advanced,"Mix amount",value.mix_amount,0,1,.01,func(next: float): value.mix_amount=next; changed())
		_choice(advanced,"Mix distribution",["Uniform","Noise","Patches"],["uniform","noise","patches"],value.mix_distribution,func(next: String): value.mix_distribution=next; changed())
		_number(advanced,"Second texture size",value.secondary.texture_size,2,2048,1,func(next: float): value.secondary.texture_size=next; changed())
		_number(advanced,"Second rotation",value.secondary.rotation,-180,180,1,func(next: float): value.secondary.rotation=next; changed())

func _choice(parent: Node,caption: String,captions: Array,ids: Array,current: String,callback: Callable) -> void:
	var row:=HBoxContainer.new(); parent.add_child(row)
	var label:=Label.new(); label.text=caption; label.add_theme_font_size_override("font_size",11); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
	var choice:=OptionButton.new(); choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL; choice.fit_to_longest_item=false; choice.custom_minimum_size.x=120
	for text in captions: choice.add_item(str(text))
	choice.select(maxi(0,ids.find(current))); row.add_child(choice)
	choice.item_selected.connect(func(index: int): callback.call(str(ids[index])); edit_committed.emit())

func _number(parent: Node,caption: String,current: float,minimum: float,maximum: float,step: float,callback: Callable) -> void:
	var row:=HBoxContainer.new(); parent.add_child(row)
	var label:=Label.new(); label.text=caption; label.add_theme_font_size_override("font_size",11); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
	var slider:=HSlider.new(); slider.min_value=minimum; slider.max_value=maximum; slider.step=step; slider.value=current; slider.custom_minimum_size.x=72; row.add_child(slider)
	var number:=SpinBox.new(); number.min_value=minimum; number.max_value=maximum; number.step=step; number.value=current; number.custom_minimum_size.x=78; row.add_child(number)
	slider.value_changed.connect(func(next: float): number.set_value_no_signal(next); callback.call(next)); slider.drag_ended.connect(func(_changed: bool): edit_committed.emit())
	number.value_changed.connect(func(next: float): slider.set_value_no_signal(next); callback.call(next); edit_committed.emit())

func _load_history() -> void:
	if not FileAccess.file_exists(HISTORY_PATH): return
	var saved:=ResourceLoader.load(HISTORY_PATH,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved!=null:
		favorites=saved.get_meta("favorites",PackedStringArray()); recent=saved.get_meta("recent",PackedStringArray()); custom_materials=saved.get_meta("custom",{}).duplicate()

func _save_history() -> void:
	var saved:=Resource.new(); saved.set_meta("favorites",favorites); saved.set_meta("recent",recent); saved.set_meta("custom",custom_materials); ResourceSaver.save(saved,HISTORY_PATH)

func save_material(as_new: bool=false) -> void:
	var id:=Presets.save_material(value,"" if as_new else active_path)
	if id.is_empty(): return
	active_path=id; custom_materials[id]=value.copy_material(); _save_history(); refresh_grid()

func load_material() -> void:
	var property:=ActorProperty.new(); property.options={"extensions":["tres","res"],"file_picker":true}
	var path:=await ActorProjectFilePicker.pick(self,property,"Import Natural Material preset")
	if path.is_empty() or path==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiTextureMaterial
	if loaded==null: return
	active_path=Presets.import_file(path)
	if active_path.is_empty(): return
	custom_materials[active_path]=loaded.copy_material(); set_material_value(loaded); changed(); edit_committed.emit(); _save_history(); refresh_grid()

func import_image() -> void:
	var property:=ActorProperty.new(); property.options={"extensions":KiwiImageWorkspace.IMAGE_EXTENSIONS,"file_picker":true}
	var path:=await ActorProjectFilePicker.pick(self,property,"Choose material image")
	if path.is_empty() or path==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var bitmap:=Image.load_from_file(path)
	if bitmap==null: return
	bitmap.generate_mipmaps(); var imported:=Library.create("geometry/checkerboard"); imported.label=path.get_file(); imported.image=ImageTexture.create_from_image(bitmap)
	active_path=""; set_material_value(imported); changed(); edit_committed.emit()

func is_closed() -> bool:
	return _closed

func close() -> void:
	if _closed: return
	if _comparing: _compare(false)
	_closed=true; _filter_generation+=1; name="ClosingMaterialBrowser"; hide(); _restore_sidebar(); edit_committed.emit(); _save_history()
	while _thumbnail_busy: await get_tree().process_frame
	queue_free()

func _restore_sidebar() -> void:
	if _sidebar_width>=0 and is_instance_valid(studio):
		studio._side_split.custom_minimum_size.x=_sidebar_width; _sidebar_width=-1

func _exit_tree() -> void:
	_closed=true; _filter_generation+=1; _restore_sidebar()


func preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_MIDDLE: preview_drag=event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]: preview_zoom=clampf(preview_zoom*(1.2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1/1.2),.1,16); update_preview()
	if event is InputEventMouseMotion and preview_drag: preview_pan-=event.relative/preview_zoom; update_preview()

func _compare(enabled: bool) -> void:
	_comparing=enabled; update_preview()
	if studio==null or not studio.document.live_edit_enabled: return
	if enabled and _original_value!=null:
		var comparison:=studio.document.snapshot(); comparison.set_live_material(comparison.active_live_material_id,_original_value)
		studio.renderer.sync(comparison); studio._refresh_pending=false
	else: studio.renderer.sync(studio.document)
	studio.canvas.preview=studio.renderer.texture(); studio.canvas.queue_redraw()

func _show_catalog(browse: bool) -> void:
	catalog_panel.visible=browse; settings_scroll.visible=not browse
	browse_tab.disabled=browse; settings_tab.disabled=not browse
	if browse: refresh_grid()
	else: _filter_generation+=1
