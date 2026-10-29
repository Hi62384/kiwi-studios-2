class_name KiwiEnvironmentWorkspace
extends Control
signal document_changed
signal environment_saved(path: String,saved_session: KiwiEnvironmentSession)
signal use_in_scene(path: String)
var session:=KiwiEnvironmentSession.new()
var canvas:=KiwiEnvironmentViewport.new()
var path:=""
var title:=Label.new()
var status:=Label.new()
var hierarchy:=preload("res://Workspaces/ModelWorkspace/model_hierarchy.gd").new()
var properties:=VBoxContainer.new()
var search:=LineEdit.new()
var _split:=HSplitContainer.new()
var _right_split:=HSplitContainer.new()
var _left:=VBoxContainer.new()
var _right:=ScrollContainer.new()
var _context:=HBoxContainer.new()
var _building:=false
var _refresh_pending:=false
var _last_selection:=""
var _recent_assets: Array[String]=[]
var _asset_name:=Button.new()
var _transform_inputs: Dictionary={}
var _settings_mode:=false
const Climate=preload("res://Workspaces/EnvironmentWorkspace/environment_climate.gd")
var _climate_mode:=false
var _collapsed: Dictionary={}
var _property_scrolls: Dictionary={}
var _generation_jobs: Array[Dictionary]=[]
var _generation_cancel:=Button.new()
var _terrain_bake: RefCounted
var library:=preload("res://Workspaces/EnvironmentWorkspace/environment_library.gd").new()
var _expanded_landforms: Dictionary={}
var _advanced_generation:=false
var _failed_volumes: Dictionary={}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); theme=Theme.new(); theme.default_font_size=13
	var background:=ColorRect.new(); background.color=Color("101a24"); background.mouse_filter=Control.MOUSE_FILTER_IGNORE; background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	for state in ["normal","hover","pressed","focus"]:
		var style:=StyleBoxFlat.new(); style.bg_color=Color("244b43") if state=="pressed" else Color("182b3a"); style.border_color=Color("78dac2") if state in ["pressed","hover","focus"] else Color("344e60"); style.set_border_width_all(1); style.set_corner_radius_all(5); style.content_margin_left=8; style.content_margin_right=8; style.content_margin_top=4; style.content_margin_bottom=4
		for type in ["Button","MenuButton","OptionButton"]: theme.set_stylebox(state,type,style)
	var column:=VBoxContainer.new(); column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); column.add_theme_constant_override("separation",4); add_child(column)
	var header:=HBoxContainer.new(); column.add_child(header); title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; title.add_theme_color_override("font_color",Color("7dddc5")); header.add_child(title)
	var file:=MenuButton.new(); file.text="File ▾"; header.add_child(file)
	for label in ["Open environment…","Save   Ctrl+S","Save As…   Ctrl+Shift+S","Save to Super Clipboard"]: file.get_popup().add_item(label)
	file.get_popup().id_pressed.connect(func(index: int):
		match index:
			0: open_dialog()
			1: save()
			2: save_as()
			3: KiwiSuperClipboardService.instance.quick_save(session.environment().snapshot(),session.environment().title)
	)
	_button(header,"↶",func(): session.undo(),"Undo · Ctrl+Z"); _button(header,"↷",func(): session.redo(),"Redo · Ctrl+Shift+Z")
	_button(header,"To Scene ↗",_to_scene,"Save a linked environment asset into the Scene Workspace")
	_button(header,"☀ Lighting",func(): _settings_mode=not _settings_mode; _climate_mode=false; _refresh_properties(),"Authored sunlight and world / sky settings")
	_button(header,"◌ Climate & weather",func(): _settings_mode=true; _climate_mode=true; _refresh_properties(),"Time of day, climate, local weather and wind")
	_generation_cancel.text="Cancel generation"; _generation_cancel.visible=false; header.add_child(_generation_cancel); _generation_cancel.pressed.connect(_cancel_generation)
	var view:=MenuButton.new(); view.text="View ▾"; header.add_child(view)
	for label in ["Frame selected · F","Frame all · Shift+F","Perspective / orthographic","Top","Front","Right","Hierarchy panel","Properties panel"]: view.get_popup().add_item(label)
	view.get_popup().id_pressed.connect(func(index: int):
		match index:
			0: canvas.frame()
			1: canvas.frame(true)
			2: canvas.camera.projection=Camera3D.PROJECTION_ORTHOGONAL if canvas.camera.projection==Camera3D.PROJECTION_PERSPECTIVE else Camera3D.PROJECTION_PERSPECTIVE; canvas.update_camera()
			3,4,5: canvas.set_view(["Top","Front","Right"][index-3])
			6: _left.visible=not _left.visible
			7: _right.visible=not _right.visible
	)
	var tools:=HBoxContainer.new(); column.add_child(tools)
	_button(tools,"◎ World",func(): preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd").add(session,canvas.target,true,true); canvas.request_sync(); canvas.frame(true))
	var build:=MenuButton.new(); build.text="⌂ Build ▾"; tools.add_child(build); build.get_popup().add_item("Building")
	for kind: String in preload("res://Workspaces/EnvironmentWorkspace/architecture/architectural_component.gd").TYPES: build.get_popup().add_item(kind)
	build.get_popup().id_pressed.connect(func(index: int):
		if index==0: await preload("res://Workspaces/EnvironmentWorkspace/architecture/building_ui.gd").create(self)
		else: session.add(preload("res://Workspaces/EnvironmentWorkspace/architecture/architectural_component.gd").kinds()[index-1],{},canvas.target); canvas.request_sync(); canvas.grab_focus())
	var nature:=MenuButton.new(); nature.text="♧ Nature ▾"; tools.add_child(nature)
	var natural=preload("res://Workspaces/ModelWorkspace/natural_generator.gd")
	for category: String in ["Tree","Plant","Rock","Prop","Cluster"]:
		var submenu:=PopupMenu.new(); submenu.name=category; nature.get_popup().add_child(submenu); nature.get_popup().add_submenu_item(category,category)
		var choices: Array=[]
		for kind: String in natural.kinds()+preload("res://Workspaces/ModelWorkspace/natural_cluster.gd").kinds():
			if kind.begins_with(category+" / "): choices.append(kind); submenu.add_item(kind.get_slice(" / ",1))
		submenu.id_pressed.connect(func(index: int): session.add(choices[index],{},canvas.target); canvas.request_sync(); canvas.grab_focus())
	for tool in ["Move","Rotate","Scale"]: _button(tools,{"Move":"↔ Move","Rotate":"⟳ Rotate","Scale":"⤢ Scale"}[tool],func(): canvas.environment_tool="Select"; canvas.tool=tool; canvas.grab_focus(); _refresh_context())
	var terrain:=MenuButton.new(); terrain.text="△ Terrain ▾"; tools.add_child(terrain)
	for label in ["Add terrain"]+KiwiEnvironmentViewport.BRUSH_TOOLS+["Paint material","Paint biome","Erase biome"]: terrain.get_popup().add_item(label)
	terrain.get_popup().id_pressed.connect(func(index: int):
		if index==0: session.add_terrain(); canvas.frame()
		else: canvas.environment_tool=(KiwiEnvironmentViewport.BRUSH_TOOLS+["Paint material","Paint biome","Erase biome"])[index-1]; _refresh_context(); canvas.grab_focus()
	)
	var caves:=MenuButton.new(); caves.text="◉ Caves ▾"; tools.add_child(caves)
	for caption in ["Add cave network","Add tunnel","Add chamber","Edit paths / chambers","Dig","Fill","Smooth","Cutaway surface","Wireframe preview"]: caves.get_popup().add_item(caption)
	caves.get_popup().id_pressed.connect(func(index: int):
		if index<3: _add_cave(index)
		elif index<7: canvas.environment_tool=["Cave path","Cave dig","Cave fill","Cave smooth"][index-3]; _refresh_context(); canvas.grab_focus()
		elif index==7: canvas.renderer.cave_cutaway=not canvas.renderer.cave_cutaway; canvas.request_sync()
		else: canvas.viewport.debug_draw=Viewport.DEBUG_DRAW_DISABLED if canvas.viewport.debug_draw==Viewport.DEBUG_DRAW_WIREFRAME else Viewport.DEBUG_DRAW_WIREFRAME)
	_button(tools,"⌖ Place",_place_tool)
	_button(tools,"✣ Scatter",_add_scatter)
	var axes:=OptionButton.new(); axes.add_item("World axes"); axes.add_item("Local axes"); tools.add_child(axes); axes.item_selected.connect(func(index: int): canvas.local_axes=index==1; canvas.overlay.queue_redraw())
	var snap:=CheckButton.new(); snap.text="Snap"; tools.add_child(snap); snap.toggled.connect(func(value: bool): canvas.snap=value)
	var align:=CheckButton.new(); align.text="Align surface"; tools.add_child(align); align.toggled.connect(func(value: bool): canvas.align_surface=value)
	column.add_child(_context); _split.size_flags_vertical=Control.SIZE_EXPAND_FILL; _split.split_offset=200; column.add_child(_split); _left.custom_minimum_size.x=150; _split.add_child(_left); _right_split.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _split.add_child(_right_split)
	search.placeholder_text="Find components…"; _left.add_child(search); search.text_changed.connect(func(_text: String): _refresh_tree())
	var arrange:=HBoxContainer.new(); _left.add_child(arrange); _button(arrange,"＋",func(): session.add_group(),"New group"); _button(arrange,"⧉",func(): session.duplicate_selected(),"Duplicate"); _button(arrange,"×",func(): session.delete_selected(),"Delete")
	var parenting:=MenuButton.new(); parenting.text="Arrange ▾"; arrange.add_child(parenting)
	for label in ["Group selected","Parent to primary selection","Unparent","Save selected as reusable component…","Selected to Super Clipboard"]: parenting.get_popup().add_item(label)
	parenting.get_popup().id_pressed.connect(func(index: int):
		if index==0: session.group_selected()
		elif index in [1,2]: session.parent_selected(index==2)
		elif index==3: _save_component()
		elif index==4:
			var component:=session.selected_environment()
			if component!=null: KiwiSuperClipboardService.instance.quick_save(component,component.title)
	)
	hierarchy.size_flags_vertical=Control.SIZE_EXPAND_FILL; hierarchy.hide_root=true; hierarchy.columns=3; hierarchy.select_mode=Tree.SELECT_MULTI; hierarchy.allow_reselect=true; hierarchy.set_column_title(0,"Environment"); hierarchy.set_column_title(1,"Show"); hierarchy.set_column_title(2,"Lock"); hierarchy.column_titles_visible=true; hierarchy.set_column_expand(1,false); hierarchy.set_column_expand(2,false); hierarchy.set_column_custom_minimum_width(1,42); hierarchy.set_column_custom_minimum_width(2,42); _left.add_child(hierarchy); hierarchy.multi_selected.connect(_tree_selected); hierarchy.item_edited.connect(_tree_edited)
	_asset_name.text="Browse project assets…"; _asset_name.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; _left.add_child(_asset_name); _asset_name.pressed.connect(choose_asset)
	var library_split:=VSplitContainer.new(); library_split.size_flags_vertical=Control.SIZE_EXPAND_FILL; _left.add_child(library_split); _left.remove_child(hierarchy); library_split.add_child(hierarchy); library_split.add_child(library); library_split.split_offset=240; library.asset_chosen.connect(_library_asset); library.source_requested.connect(_open_library_source)
	canvas.session=session; canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL; canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL; _right_split.add_child(canvas)
	_right.custom_minimum_size.x=250; _right.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; _right_split.add_child(_right); properties.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _right.add_child(properties)
	status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; status.add_theme_font_size_override("font_size",11); column.add_child(status)
	canvas.asset_placed.connect(func(asset: String,point: Vector3,normal: Vector3): status.text=session.place_asset(asset,point,normal,canvas.align_surface)); canvas.notice.connect(func(message: String): status.text=message); canvas.command_requested.connect(_command); canvas.gesture_finished.connect(func(): _refresh_pending=true); canvas.brush_settings_changed.connect(_refresh_context)
	canvas.cave_replaced.connect(_replace_cave)
	canvas.water_replaced.connect(func(id: String,source: KiwiTerrainHydrology): _regenerate_terrain(id,{"hydrology":source}))
	canvas.biomes_replaced.connect(func(id: String,source: KiwiTerrainBiomes): _regenerate_terrain(id,{"biomes":source}))
	canvas.world_replaced.connect(func(id: String,source: Resource): preload("res://Workspaces/EnvironmentWorkspace/world/world_ui.gd").apply(self,id,source,"Edit road path"))
	session.changed.connect(_changed); _refresh_pending=true

func _button(parent: Node,text: String,action: Callable,tooltip: String="") -> Button:
	var button:=Button.new(); button.text=text; button.tooltip_text=tooltip; parent.add_child(button); button.pressed.connect(action); return button
func _clear(node: Node) -> void:
	for child in node.get_children(): node.remove_child(child); child.queue_free()
func _changed() -> void:
	canvas.request_sync(); document_changed.emit(); _refresh_pending=true
	for key: String in _transform_inputs:
		var input:=_transform_inputs[key] as DragNumber
		if not is_instance_valid(input) or input._pressed or input.get_line_edit().has_focus(): continue
		var item:=session.primary()
		if item!=null: input.set_value_no_signal(_transform_value(item,key.get_slice(":",0),int(key.get_slice(":",1))))
func _process(_delta: float) -> void:
	_poll_generation()
	_generation_cancel.visible=_terrain_bake!=null or not _generation_jobs.is_empty() or not canvas.renderer.scatter_jobs.is_empty() or session.pending_source_cancel.is_valid()
	if _terrain_bake!=null: status.text="Baking full terrain · %d%%"%roundi(_terrain_bake.progress*100.)
	if str(canvas.environment_tool).begins_with("Cave ") and _generation_jobs.is_empty() and canvas.cave_tool.target().is_empty(): canvas.cave_tool.cancel(); canvas.environment_tool="Select"; _refresh_pending=true
	if canvas.environment_tool=="Water paths" and _generation_jobs.is_empty() and canvas.water_tool.target().is_empty(): canvas.water_tool.cancel(); canvas.environment_tool="Select"; _refresh_pending=true
	if is_visible_in_tree() and not canvas._painting and not canvas._drag and _generation_jobs.is_empty():
		for component in session.document.components:
			var terrain:=session.environment().terrain(component.id)
			if terrain!=null and (not terrain.water_valid() or not terrain.biomes_valid() or not terrain.volumes_valid() or not terrain.cave_biomes_valid()) and int(_failed_volumes.get(component.id,-1))!=terrain.signature(): _regenerate_terrain(component.id,{},false,true); break
		if _generation_jobs.is_empty(): preload("res://Workspaces/EnvironmentWorkspace/world/world_dependencies.gd").poll(self)
	if not _refresh_pending or not is_visible_in_tree() or canvas._painting or canvas._drag: return
	_refresh_pending=false; title.text="ENVIRONMENT  /  "+session.environment().title; _refresh_tree(); _refresh_context(); _refresh_properties()
	if not canvas.renderer.errors.is_empty(): status.text=canvas.renderer.errors[0]
func _refresh_tree() -> void:
	_store_collapsed(hierarchy.get_root()); _building=true; hierarchy.session=session; hierarchy.clear(); var root:=hierarchy.create_item(); var rows:={}; var pending:=session.document.components.duplicate(); var filter:=search.text.to_lower(); var shown:={}
	for item in session.document.components:
		if filter.is_empty() or item.title.to_lower().contains(filter):
			shown[item.id]=true; var parent:=session.document.component(item.parent_id); var visited:={}
			while parent!=null and not visited.has(parent.id): shown[parent.id]=true; visited[parent.id]=true; parent=session.document.component(parent.parent_id)
	for pass_index in session.document.components.size()+1:
		if pending.is_empty(): break
		var removed:=false
		for index in range(pending.size()-1,-1,-1):
			var item: KiwiModelComponent=pending[index]
			if not shown.has(item.id): pending.remove_at(index); removed=true; continue
			if not item.parent_id.is_empty() and not rows.has(item.parent_id): continue
			var row:=hierarchy.create_item(rows.get(item.parent_id,root)); row.set_text(0,item.title); row.set_metadata(0,item.id); row.set_editable(0,true)
			row.collapsed=bool(_collapsed.get(item.id,false)) if filter.is_empty() else false
			for column in [1,2]: row.set_cell_mode(column,TreeItem.CELL_MODE_CHECK); row.set_editable(column,true)
			row.set_checked(1,item.visible); row.set_checked(2,item.locked); rows[item.id]=row
			if session.selected.has(item.id): row.select(0)
			pending.remove_at(index); removed=true
		if not removed: break
	_building=false
func _store_collapsed(row: TreeItem) -> void:
	if row==null: return
	var id: Variant=row.get_metadata(0)
	if id is String: _collapsed[id]=row.collapsed
	var child:=row.get_first_child()
	while child!=null: _store_collapsed(child); child=child.get_next()
func _tree_selected(item: TreeItem,column: int,selected: bool) -> void:
	if _building or column!=0: return
	var id:=str(item.get_metadata(0))
	if selected and not session.selected.has(id): session.selected.append(id)
	elif not selected: session.selected.erase(id)
	session.changed.emit()
func _tree_edited() -> void:
	if _building: return
	var row:=hierarchy.get_edited(); var item:=session.document.component(str(row.get_metadata(0))); var column:=hierarchy.get_edited_column()
	if item==null: return
	session.action("Change environment component",func():
		if column==0: item.title=row.get_text(0)
		elif column==1: item.visible=row.is_checked(1)
		else: item.locked=row.is_checked(2))

func _refresh_context() -> void:
	_clear(_context)
	if canvas.environment_tool in KiwiEnvironmentViewport.BRUSH_TOOLS or canvas.environment_tool in ["Paint material","Paint biome","Erase biome","Paint scatter","Erase scatter"]:
		var label:=Label.new(); label.text=canvas.environment_tool; _context.add_child(label)
		_value(_context,"Radius",canvas.brush_radius,.05,1000.,.05,func(value: float): canvas.brush_radius=value)
		_value(_context,"Strength",canvas.brush_strength,.001,10.,.01,func(value: float): canvas.brush_strength=value)
		_value(_context,"Falloff",canvas.brush_falloff,.01,8.,.01,func(value: float): canvas.brush_falloff=value)
		_value(_context,"Spacing",canvas.brush_spacing,.05,1.,.05,func(value: float): canvas.brush_spacing=value)
		if canvas.environment_tool in ["Paint biome","Erase biome"]:
			var info:=canvas.biome_tool.target()
			if not info.is_empty():
				var chooser:=OptionButton.new(); chooser.fit_to_longest_item=false; _context.add_child(chooser)
				for definition: Dictionary in (info.terrain as KiwiEnvironmentTerrain).biomes.definitions:
					if not definition.get("enabled",true) or definition.get("domain","surface")!="surface": continue
					chooser.add_item(str(definition.get("name","Biome"))); chooser.set_item_metadata(chooser.item_count-1,str(definition.id))
					if str(definition.id)==canvas.biome_tool.biome_id: chooser.select(chooser.item_count-1)
				chooser.item_selected.connect(func(index: int): canvas.biome_tool.biome_id=str(chooser.get_item_metadata(index)); canvas.request_sync())
		if canvas.environment_tool=="Level to height": _value(_context,"Height",canvas.brush_target_height,-10000.,10000.,.1,func(value: float): canvas.brush_target_height=value)
		if canvas.environment_tool=="Terrace": _value(_context,"Step",canvas.brush_terrace_step,.01,1000.,.1,func(value: float): canvas.brush_terrace_step=value)
		var settings:=MenuButton.new(); settings.text="Brush ▾"; _context.add_child(settings)
		for caption in ["Square brush","Mirror X","Mirror Z"]: settings.get_popup().add_check_item(caption)
		for index in 3: settings.get_popup().set_item_checked(index,[canvas.brush_square,canvas.brush_symmetry_x,canvas.brush_symmetry_z][index])
		settings.get_popup().hide_on_checkable_item_selection=false; settings.get_popup().id_pressed.connect(func(index: int):
			var key: String=["brush_square","brush_symmetry_x","brush_symmetry_z"][index]; canvas.set(key,not bool(canvas.get(key))); settings.get_popup().set_item_checked(index,bool(canvas.get(key))))
		if canvas.environment_tool=="Stamp": _button(_context,"Choose stamp…" if canvas.stamp_path.is_empty() else canvas.stamp_path.get_file(),_choose_stamp)
	elif canvas.environment_tool in ["Cave dig","Cave fill","Cave smooth"]:
		var label:=Label.new(); label.text=canvas.environment_tool; _context.add_child(label); _value(_context,"Radius",canvas.brush_radius,.1,100.,.1,func(value: float): canvas.brush_radius=value); _value(_context,"Strength",canvas.cave_tool.strength,.05,1.,.05,func(value: float): canvas.cave_tool.strength=value)
	elif canvas.environment_tool in ["Cave path","Water paths"]:
		var label:=Label.new(); label.text="Drag a point · Shift-click inserts · Right-click removes · Esc cancels"; _context.add_child(label)
	elif canvas.environment_tool=="Place": _button(_context,canvas.placement_asset.get_file() if not canvas.placement_asset.is_empty() else "Choose a model…",choose_asset)
	_context.visible=_context.get_child_count()>0
func _choose_stamp() -> void:
	var property:=ActorProperty.new(); property.options={"extensions":["png","jpg","jpeg","webp"],"raw_extensions":["png","jpg","jpeg","webp"],"native_resource_types":["Texture2D"]}; var selected:=await ActorProjectFilePicker.pick(self,property,"Choose a terrain height stamp")
	if selected.is_empty(): return
	canvas.stamp_path="" if selected==ActorProjectFilePicker.EMPTY_RESOURCE else selected; canvas.stamp_image=ActorImageGenerator.image_from_value(canvas.stamp_path) if not canvas.stamp_path.is_empty() else null; _refresh_context()
func _value(parent: Node,label: String,value: float,low: float,high: float,step: float,write: Callable) -> DragNumber:
	var row:=HBoxContainer.new(); parent.add_child(row); var title:=Label.new(); title.text=label; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(title); var input:=DragNumber.new(); input.min_value=low; input.max_value=high; input.step=step; input.custom_minimum_size.x=85; input.set_value_no_signal(value); row.add_child(input); input.value_changed.connect(write); input.drag_committed.connect(write); return input
func _heading(text: String) -> void:
	var label:=Label.new(); label.text=text; label.add_theme_color_override("font_color",Color("7edbc4")); properties.add_child(label)
func _transform_value(item: KiwiModelComponent,kind: String,axis: int) -> float:
	if kind=="Position": return item.transform.origin[axis]
	if kind=="Rotation": return rad_to_deg(item.transform.basis.get_euler()[axis])
	return item.transform.basis.get_scale()[axis]
func _edit_transform(item: KiwiModelComponent,kind: String,axis: int,value: float) -> void:
	if is_equal_approx(_transform_value(item,kind,axis),value): return
	session.action("Change component "+kind.to_lower(),func():
		if kind=="Position": item.transform.origin[axis]=value
		else:
			var rotation:=item.transform.basis.get_euler(); var scale:=item.transform.basis.get_scale()
			if kind=="Rotation": rotation[axis]=deg_to_rad(value)
			else: scale[axis]=value if absf(value)>.0001 else .0001
			item.transform.basis=Basis.from_euler(rotation)*Basis.from_scale(scale))
func _refresh_properties() -> void:
	if not _last_selection.is_empty(): _property_scrolls[_last_selection]=_right.scroll_vertical
	_clear(properties); _transform_inputs.clear(); var item:=session.primary(); _last_selection="@environment" if _settings_mode else (item.id if item!=null else "")
	_restore_property_scroll.call_deferred(_last_selection)
	if _settings_mode:
		if _climate_mode: _climate_properties()
		else: _environment_properties()
		return
	if item==null:
		_heading("Build an environment"); _button(properties,"＋ Add terrain",func(): session.add_terrain()); _button(properties,"Browse model assets…",choose_asset); return
	preload("res://Workspaces/EnvironmentWorkspace/architecture/building_ui.gd").properties(self,item,properties)
	preload("res://Workspaces/EnvironmentWorkspace/world/world_ui.gd").properties(self,item,properties)
	if preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd").source(item)!=null: _button(properties,"Save reusable building model…",_save_component)
	if preload("res://Workspaces/ModelWorkspace/natural_generator.gd").accepts(item.generator):
		preload("res://Workspaces/ModelWorkspace/natural_ui.gd").properties(self,item,properties)
		_button(properties,"Save reusable natural model…",_save_component)
	if preload("res://Workspaces/ModelWorkspace/natural_cluster.gd").accepts(item):
		preload("res://Workspaces/ModelWorkspace/natural_cluster.gd").properties(self,item,properties)
		_button(properties,"Save reusable natural cluster…",_save_component)
	_heading(item.title)
	for kind in ["Position","Rotation","Scale"]:
		for axis in 3:
			var input:=_value(properties,kind+" "+["X","Y","Z"][axis],_transform_value(item,kind,axis),-100000.,100000.,.01,func(value: float): _edit_transform(item,kind,axis,value)); _transform_inputs[kind+":"+str(axis)]=input
	var terrain:=session.environment().terrain(item.id)
	if terrain!=null:
		_heading("Terrain generator")
		var geology:=OptionButton.new(); geology.fit_to_longest_item=false; properties.add_child(geology)
		for name: String in KiwiEnvironmentTerrain.GEOLOGY: geology.add_item(name)
		geology.select(terrain.geology); geology.item_selected.connect(func(index: int): _regenerate_terrain(item.id,{"geology":index}))
		_generation_properties(item,terrain)
		_erosion_properties(item,terrain)
		_cave_properties(item,terrain)
		_water_properties(item,terrain)
		_biome_properties(item,terrain)
		_value(properties,"Width (m)",terrain.dimensions.x,.1,100000.,.1,func(value: float): _regenerate_terrain(item.id,{"dimensions":Vector2(value,terrain.dimensions.y)}))
		_value(properties,"Length (m)",terrain.dimensions.y,.1,100000.,.1,func(value: float): _regenerate_terrain(item.id,{"dimensions":Vector2(terrain.dimensions.x,value)}))
		for spec in [["Seed","seed",-100000.,100000.,1.],["Base elevation","base_height",-10000.,10000.,.1],["Noise height","amplitude",0.,10000.,.1],["Noise frequency","frequency",.00001,10.,.001]]:
			_value(properties,spec[0],float(terrain.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): var values:={}; values[spec[1]]=int(value) if spec[1]=="seed" else value; _regenerate_terrain(item.id,values))
		var resolution:=OptionButton.new(); resolution.fit_to_longest_item=false; properties.add_child(resolution)
		for count in [33,65,129,257,513,1025]: resolution.add_item("%d × %d samples"%[count,count]); resolution.set_item_metadata(resolution.item_count-1,count)
		for index in resolution.item_count:
			if int(resolution.get_item_metadata(index))==terrain.resolution: resolution.select(index)
		resolution.item_selected.connect(func(index: int): _regenerate_terrain(item.id,{"resolution":int(resolution.get_item_metadata(index))}))
		_button(properties,"Ground material…",func(): _choose_material(item.id)); _button(properties,"Reset sculpt edits",func(): _regenerate_terrain(item.id,{},true))
		_button(properties,"Paint material…",func(): _choose_material(item.id,true))
		_button(properties,"Bake to editable model…",func(): _bake_terrain(item.id))
		_button(properties,"Paint terrain",func(): canvas.environment_tool="Paint material"; _refresh_context(); canvas.grab_focus())
		_heading("Render detail")
		var lod:=CheckButton.new(); lod.text="Automatic terrain LOD"; lod.button_pressed=terrain.lod_enabled; properties.add_child(lod); lod.toggled.connect(func(value: bool): session.action("Toggle terrain LOD",func(): terrain.lod_enabled=value))
		_value(properties,"LOD detail bias",terrain.lod_bias,.1,4.,.1,func(value: float): session.action("Change terrain LOD",func(): terrain.lod_bias=value))
		_value(properties,"Render distance (0 = all)",terrain.render_distance,0.,100000.,10.,func(value: float): session.action("Change terrain render distance",func(): terrain.render_distance=value))
	var scatter:=session.environment().component_settings.get(item.id,{}).get("scatter") as KiwiEnvironmentScatter
	if scatter!=null:
		_heading("Scatter rules")
		var ground:=session.environment().terrain(scatter.terrain_id)
		if ground!=null and ground.biomes!=null:
			_heading("Suitable biomes")
			for definition: Dictionary in ground.biomes.definitions:
				var toggle:=CheckBox.new(); toggle.text=str(definition.get("name","Biome")); toggle.button_pressed=scatter.biome_ids.has(str(definition.id)); properties.add_child(toggle); toggle.toggled.connect(func(value: bool): _set_scatter_biome(scatter,str(definition.id),value))
		for spec in [["Density / m²","density",0.,100.,.01],["Minimum spacing (m)","minimum_distance",.001,100.,.05],["Seed","seed",-100000.,100000.,1.],["Instance budget","budget",1.,20000.,1.]]:
			_value(properties,spec[0],float(scatter.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): session.action("Change scatter rules",func(): scatter.set(spec[1],int(value) if spec[1] in ["seed","budget"] else value)))
		for spec in [["Render cluster size (0 = one batch)","render_cluster_size",0.,4096.,8.],["Render distance (0 = all)","render_distance",0.,100000.,10.],["Detail bias","lod_bias",.05,16.,.05]]:
			_value(properties,spec[0],float(scatter.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): session.action("Change scatter rendering",func(): scatter.set(spec[1],value)))
		var detail:=CheckButton.new(); detail.text="Automatic mesh detail"; detail.button_pressed=scatter.lod_enabled; properties.add_child(detail); detail.toggled.connect(func(on: bool): session.action("Change scatter mesh detail",func(): scatter.lod_enabled=on))
		var streaming:=CheckButton.new(); streaming.text="Stream nearby instance clusters"; streaming.button_pressed=scatter.stream_instances; properties.add_child(streaming); streaming.toggled.connect(func(on: bool): session.action("Change instance streaming",func(): scatter.stream_instances=on))
		_button(properties,"Regenerate",func(): canvas.renderer.signatures.erase(item.id); canvas.request_sync())
		var domain:=OptionButton.new(); properties.add_child(domain)
		for name in ["Terrain surface","Cave floors","Cave ceilings","Cave walls"]: domain.add_item(name)
		domain.select(scatter.surface_domain); domain.item_selected.connect(func(index: int): session.action("Change scatter surface",func(): scatter.surface_domain=index))
		if scatter.use_anchors:
			var height_mode:=OptionButton.new(); properties.add_child(height_mode)
			for caption in ["Anchor on terrain","Anchor offset from terrain","Authored anchor elevation"]: height_mode.add_item(caption)
			height_mode.select(scatter.anchor_height_mode); height_mode.item_selected.connect(func(index: int): session.action("Change anchor height mode",func(): scatter.anchor_height_mode=index))
		for spec in [["Cluster centers","cluster_count",0.,4096.,1.],["Cluster radius (m)","cluster_radius",.01,1000.,.1]]:
			_value(properties,spec[0],float(scatter.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): session.action("Change scatter clusters",func(): scatter.set(spec[1],int(value) if spec[1]=="cluster_count" else value)))
		for spec in [["Temperature min","temperature_range",0,-100.,100.],["Temperature max","temperature_range",1,-100.,100.],["Humidity min","humidity_range",0,0.,1.],["Humidity max","humidity_range",1,0.,1.],["Shore distance min","shore_range",0,0.,1000000.],["Shore distance max","shore_range",1,0.,1000000.],["Water depth min","water_depth_range",0,0.,10000.],["Water depth max","water_depth_range",1,0.,10000.]]:
			_value(properties,spec[0],(scatter.get(spec[1]) as Vector2)[spec[2]],spec[3],spec[4],.1,func(value: float): session.action("Change ecological range",func(): var pair: Vector2=scatter.get(spec[1]); pair[spec[2]]=value; scatter.set(spec[1],pair)))
		_scatter_instances(item,scatter)
		var painting:=HBoxContainer.new(); properties.add_child(painting)
		for mode in ["Paint scatter","Erase scatter"]: _button(painting,mode.get_slice(" ",0),func(): canvas.environment_tool=mode; _refresh_context(); canvas.grab_focus())
		_button(properties,"Clear painted regions",func(): session.action("Clear scatter regions",func(): scatter.paint_regions.clear(); scatter.erase_regions.clear()))
		for spec in [["Scale min","scale_range",0,.01,100.,.01],["Scale max","scale_range",1,.01,100.,.01],["Yaw min","yaw_range",0,-360.,360.,1.],["Yaw max","yaw_range",1,-360.,360.,1.],["Elevation min","height_range",0,-10000.,10000.,.1],["Elevation max","height_range",1,-10000.,10000.,.1],["Slope min","slope_range",0,0.,90.,1.],["Slope max","slope_range",1,0.,90.,1.],["Region X","region_position",0,-10000.,10000.,.1],["Region Z","region_position",1,-10000.,10000.,.1],["Region width","region_size",0,.1,10000.,.1],["Region length","region_size",1,.1,10000.,.1]]:
			var vector: Vector2=scatter.region.position if spec[1]=="region_position" else (scatter.region.size if spec[1]=="region_size" else scatter.get(spec[1]))
			_value(properties,spec[0],vector[spec[2]],spec[3],spec[4],spec[5],func(value: float): session.action("Change scatter range",func():
				var current: Vector2=scatter.region.position if spec[1]=="region_position" else (scatter.region.size if spec[1]=="region_size" else scatter.get(spec[1])); current[spec[2]]=value
				if spec[1]=="region_position": scatter.region.position=current
				elif spec[1]=="region_size": scatter.region.size=current
				else: scatter.set(spec[1],current)))
		var align:=CheckButton.new(); align.text="Follow surface normal"; align.button_pressed=scatter.align_normal; properties.add_child(align); align.toggled.connect(func(value: bool): session.action("Align scatter",func(): scatter.align_normal=value))
		var collision:=CheckButton.new(); collision.text="Object collisions"; collision.button_pressed=scatter.collisions; properties.add_child(collision); collision.toggled.connect(func(value: bool): session.action("Toggle scatter collision",func(): scatter.collisions=value))
		_heading("Weighted asset palette")
		for index in scatter.palette.size():
			var entry: Dictionary=scatter.palette[index]; var row:=HBoxContainer.new(); properties.add_child(row); var label:=Label.new(); label.text=entry.source.components[0].title if entry.source is KiwiModelDocument and not entry.source.components.is_empty() else str(entry.source).get_file(); label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; label.tooltip_text=label.text if entry.source is Resource else str(entry.source); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
			_value(properties,"Weight",float(entry.get("weight",1.)),0.,100.,.1,func(value: float): session.action("Change scatter weight",func(): scatter.palette[index].weight=value))
			_button(row,"×",func(): session.action("Remove scatter source",func(): scatter.palette.remove_at(index)))
		_button(properties,"Add palette model…",func(): _add_palette_asset(item.id))
	var source:=str(session.environment().component_settings.get(item.id,{}).get("source",""))
	if not source.is_empty():
		_button(properties,"Edit source model ↗",_open_model.bind(source))
		var collision:=CheckButton.new(); collision.text="Object collision"; collision.button_pressed=bool(session.environment().component_settings[item.id].get("collision",false)); properties.add_child(collision); collision.toggled.connect(func(value: bool): session.action("Toggle object collision",func(): session.environment().component_settings[item.id].collision=value))
func _restore_property_scroll(id: String) -> void:
	if id==_last_selection: _right.scroll_vertical=int(_property_scrolls.get(id,0))

func _scatter_instances(item: KiwiModelComponent,scatter: KiwiEnvironmentScatter) -> void:
	var node: Node=canvas.renderer.nodes.get(item.id)
	if not is_instance_valid(node): return
	var result: Dictionary=node.get_meta("scatter_result",{}); var placements: Dictionary=result.get("placements",{})
	if not str(result.get("warning","")).is_empty():
		var warning:=Label.new(); warning.text=str(result.warning); warning.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; properties.add_child(warning)
	if placements.is_empty(): return
	_heading("Individual instances")
	var picker:=OptionButton.new(); picker.fit_to_longest_item=false; picker.tooltip_text="Stable candidate identities; up to the first 1000 instances."; properties.add_child(picker)
	var identities: Array=placements.keys().slice(0,1000)
	for id: String in identities: picker.add_item(id)
	var row:=HBoxContainer.new(); properties.add_child(row)
	_button(row,"Remove",func(): session.action("Remove scatter instance",func(): scatter.overrides[identities[picker.selected]]={"deleted":true}))
	_button(row,"Make editable",func(): var id: String=identities[picker.selected]; status.text=session.promote_scatter(item.id,id,placements[id]))
	_button(properties,"Reset instance overrides",func(): session.action("Reset scatter overrides",func(): scatter.overrides.clear()))

func _edit_generation(id: String,edit: Callable) -> void:
	var terrain:=session.environment().terrain(id)
	if terrain==null: return
	var generation:=terrain.generation.duplicate(true) as KiwiTerrainGenerator if terrain.generation!=null else KiwiTerrainGenerator.preset(9); edit.call(generation); _regenerate_terrain(id,{"generation":generation})
func _edit_erosion(id: String,edit: Callable) -> void:
	var terrain:=session.environment().terrain(id)
	if terrain==null: return
	var operations: Array[KiwiTerrainErosion]=[]
	for source in terrain.erosion: operations.append(source.duplicate(true))
	edit.call(operations); _regenerate_terrain(id,{"erosion":operations})
func _set_scatter_biome(scatter: KiwiEnvironmentScatter,id: String,enabled: bool) -> void:
	session.action("Change scatter biome filter",func():
		var ids:=scatter.biome_ids
		if enabled and not ids.has(id): ids.append(id)
		elif not enabled and ids.has(id): ids.remove_at(ids.find(id))
		scatter.biome_ids=ids)
func _edit_biomes(id: String,edit: Callable) -> void:
	var terrain:=session.environment().terrain(id)
	if terrain==null: return
	var source:=terrain.biomes.duplicate(true) as KiwiTerrainBiomes if terrain.biomes!=null else KiwiTerrainBiomes.new()
	edit.call(source); _regenerate_terrain(id,{"biomes":source})
func _biome_properties(item: KiwiModelComponent,terrain: KiwiEnvironmentTerrain) -> void:
	_heading("Climate & biomes")
	if terrain.biomes==null:
		_button(properties,"Add biome rules",func(): _edit_biomes(item.id,func(next: KiwiTerrainBiomes): next.definitions=[KiwiTerrainBiomes.starter(0),KiwiTerrainBiomes.starter(1),KiwiTerrainBiomes.starter(2),KiwiTerrainBiomes.starter(7)])); return
	var source:=terrain.biomes
	for spec in [["Sea-level temperature (°C)","sea_temperature",-100.,100.,.5],["Base humidity","base_humidity",0.,1.,.01],["Altitude lapse (°C / m)","altitude_lapse",0.,.1,.0005],["Climate region size","climate_region_size",1.,100000.,1.]]:
		_value(properties,spec[0],float(source.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): _edit_biomes(item.id,func(next: KiwiTerrainBiomes): next.set(spec[1],value)))
	var add:=MenuButton.new(); add.text="+ Biome"; properties.add_child(add)
	for name: String in KiwiTerrainBiomes.NAMES: add.get_popup().add_item(name)
	add.get_popup().add_item("Custom")
	add.get_popup().id_pressed.connect(func(index: int): _edit_biomes(item.id,func(next: KiwiTerrainBiomes): var definition:=KiwiTerrainBiomes.starter(index if index<KiwiTerrainBiomes.NAMES.size() else 0); definition.id=ActorData.new_id(); definition.name="Custom biome" if index==KiwiTerrainBiomes.NAMES.size() else definition.name; next.definitions.append(definition)))
	var caves:=MenuButton.new(); caves.text="+ Cave biome"; properties.add_child(caves)
	for name: String in KiwiTerrainBiomes.CAVE_NAMES: caves.get_popup().add_item(name)
	caves.get_popup().id_pressed.connect(func(index: int): _edit_biomes(item.id,func(next: KiwiTerrainBiomes):
		if not next.has_cave_rules() and index!=0: next.definitions.append(KiwiTerrainBiomes.cave_starter(0))
		var definition:=KiwiTerrainBiomes.cave_starter(index)
		for existing: Dictionary in next.definitions:
			if str(existing.id)==str(definition.id): definition.id=ActorData.new_id(); break
		next.definitions.append(definition)))
	for index in source.definitions.size():
		var definition: Dictionary=source.definitions[index]; var id:=str(definition.id); var row:=HBoxContainer.new(); properties.add_child(row); var toggle:=CheckBox.new(); toggle.button_pressed=definition.get("enabled",true); row.add_child(toggle); toggle.toggled.connect(func(value: bool): _edit_biomes(item.id,func(next: KiwiTerrainBiomes): next.definitions[index].enabled=value))
		var expand:=Button.new(); expand.text=str(definition.get("name","Biome")); expand.toggle_mode=true; expand.button_pressed=_expanded_landforms.get(id,false); row.add_child(expand); expand.toggled.connect(func(value: bool): _expanded_landforms[id]=value; _refresh_pending=true)
		_button(row,"×",func(): _edit_biomes(item.id,func(next: KiwiTerrainBiomes): next.definitions.remove_at(index)))
		if not expand.button_pressed: continue
		var name:=LineEdit.new(); name.text=str(definition.name); properties.add_child(name); name.text_submitted.connect(func(value: String): _edit_biomes(item.id,func(next: KiwiTerrainBiomes): next.definitions[index].name=value))
		for spec in [["Frequency","frequency",0.,1.,.01],["Region size","region_size",1.,100000.,1.],["Transition","transition",.001,1.,.01],["Suitability weight","weight",0.,100.,.1]]:
			_value(properties,spec[0],float(definition.get(spec[1],1.)),spec[2],spec[3],spec[4],func(value: float): _edit_biomes(item.id,func(next: KiwiTerrainBiomes): next.definitions[index][spec[1]]=value))
		for key: String in ["temperature","humidity","altitude","slope","shore_distance","roughness"]+(["cave_depth","submersion"] if definition.get("domain","surface")=="cave" else []):
			for axis in 2:
				_value(properties,key.capitalize()+[" min"," max"][axis],(definition.get(key,Vector2(-100000,100000)) as Vector2)[axis],-100000.,100000.,.1,func(value: float): _edit_biomes(item.id,func(next: KiwiTerrainBiomes): var limits: Vector2=next.definitions[index].get(key,Vector2(-100000,100000)); limits[axis]=value; next.definitions[index][key]=limits))
		_button(properties,"Use as fallback",func(): _edit_biomes(item.id,func(next: KiwiTerrainBiomes):
			if definition.get("domain","surface")=="cave": next.cave_fallback_id=id
			else: next.fallback_id=id))
		if definition.get("domain","surface")!="cave": _button(properties,"Paint biome mask",func(): canvas.biome_tool.biome_id=id; canvas.environment_tool="Paint biome"; _refresh_context(); canvas.grab_focus())
		else:
			var face:=OptionButton.new(); face.fit_to_longest_item=false; properties.add_child(face)
			for type in ["any","floor","wall","ceiling"]: face.add_item(type.capitalize()); face.set_item_metadata(face.item_count-1,type)
			for which in face.item_count:
				if face.get_item_metadata(which)==definition.get("surface_type","any"): face.select(which)
			face.item_selected.connect(func(which: int): _edit_biomes(item.id,func(next: KiwiTerrainBiomes): next.definitions[index].surface_type=face.get_item_metadata(which)))
		_button(properties,"Add surface material…",func(): _choose_biome_material(item.id,index))
		var materials: Array=definition.get("materials",[])
		for slot in materials.size():
			var entry: Variant=materials[slot]; var path:=str(entry.get("source","")) if entry is Dictionary else str(entry); var row_material:=HBoxContainer.new(); properties.add_child(row_material); var label:=Label.new(); label.text=path.get_file() if entry is String or entry is Dictionary else "Surface material"; label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row_material.add_child(label)
			_button(row_material,"×",func(): _edit_biomes(item.id,func(next: KiwiTerrainBiomes): next.definitions[index].materials.remove_at(slot)))
		var landforms:=MenuButton.new(); landforms.text="+ Biome landform"; properties.add_child(landforms)
		for type: String in KiwiTerrainGenerator.LANDFORMS: landforms.get_popup().add_item(type)
		landforms.get_popup().id_pressed.connect(func(selected: int): _edit_biomes(item.id,func(next: KiwiTerrainBiomes): var layers: Array=next.definitions[index].get("landforms",[]); layers.append({"type":KiwiTerrainGenerator.LANDFORMS[selected],"height":2.,"width":5.,"length":terrain.dimensions.y*.5,"center":Vector2.ZERO}); next.definitions[index].landforms=layers))
		var layers: Array=definition.get("landforms",[])
		for layer in layers.size():
			_heading(str(layers[layer].get("type","Landform")))
			for spec in [["Height","height",-10000.,10000.,.1],["Width","width",.1,100000.,.1],["Length","length",.1,100000.,.1],["Direction","direction",-360.,360.,1.]]:
				_value(properties,spec[0],float(layers[layer].get(spec[1],0.)),spec[2],spec[3],spec[4],func(value: float): _edit_biomes(item.id,func(next: KiwiTerrainBiomes): next.definitions[index].landforms[layer][spec[1]]=value))
			_button(properties,"Remove landform",func(): _edit_biomes(item.id,func(next: KiwiTerrainBiomes): next.definitions[index].landforms.remove_at(layer)))
	_button(properties,"Remove climate & biomes",func(): _regenerate_terrain(item.id,{"biomes":null}))
func _choose_biome_material(id: String,index: int) -> void:
	var property:=ActorProperty.new(); property.options={"extensions":["tres","res","png","jpg","jpeg","webp"],"native_resource_types":["Material","Texture2D"],"accepted_object_types":["material","natural_material","image","noise_image"]}; var selected:=await ActorProjectFilePicker.pick(self,property,"Choose biome surface")
	var terrain:=session.environment().terrain(id)
	if selected.is_empty() or selected==ActorProjectFilePicker.EMPTY_RESOURCE or terrain==null or terrain.biomes==null or index>=terrain.biomes.definitions.size(): return
	_edit_biomes(id,func(next: KiwiTerrainBiomes): var values: Array=next.definitions[index].get("materials",[]); values.append(selected); next.definitions[index].materials=values)
func _edit_water(id: String,edit: Callable) -> void:
	var terrain:=session.environment().terrain(id)
	if terrain==null: return
	var source:=terrain.hydrology.duplicate(true) as KiwiTerrainHydrology if terrain.hydrology!=null else KiwiTerrainHydrology.new()
	edit.call(source)
	if terrain.hydrology!=null and source.geometry_signature()==terrain.hydrology.geometry_signature(): session.action("Change water appearance",func(): terrain.hydrology=source)
	else: _regenerate_terrain(id,{"hydrology":source})
func _water_properties(item: KiwiModelComponent,terrain: KiwiEnvironmentTerrain) -> void:
	_heading("Water & drainage")
	if terrain.hydrology==null:
		_button(properties,"Add rivers, lakes & ocean",func(): _edit_water(item.id,func(_source: KiwiTerrainHydrology): pass)); return
	var source:=terrain.hydrology
	var physical:=CheckButton.new(); physical.text="Water affects physics actors"; physical.button_pressed=source.water_physics; properties.add_child(physical); physical.toggled.connect(func(value: bool): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.water_physics=value))
	_value(properties,"Water density (kg/m³)",source.water_density,.01,20000.,1.,func(value: float): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.water_density=value))
	_value(properties,"Water drag",source.water_drag,0.,10.,.1,func(value: float): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.water_drag=value))
	_button(properties,"Edit river paths in viewport",func(): canvas.environment_tool="Water paths"; _refresh_context(); canvas.grab_focus())
	for spec in [["Water enabled","enabled"],["Automatic rivers","automatic_rivers"],["Basin lakes","automatic_lakes"],["Ocean","ocean_enabled"]]:
		var toggle:=CheckButton.new(); toggle.text=spec[0]; toggle.button_pressed=source.get(spec[1]); properties.add_child(toggle); toggle.toggled.connect(func(value: bool): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.set(spec[1],value)))
	for spec in [["Sea level","sea_level",-10000.,10000.,.1],["River catchment (m²)","catchment_threshold",.1,1000000.,1.],["River width","river_width",.1,100.,.1],["Channel depth","river_depth",.01,100.,.1],["Rainfall","rainfall",0.,100.,.1],["Lake minimum depth","lake_minimum_depth",.01,100.,.1],["Flow speed","flow_speed",0.,100.,.1],["Wave height","wave_strength",0.,10.,.01],["Wave frequency","wave_scale",.01,10.,.01]]:
		_value(properties,spec[0],float(source.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.set(spec[1],value)))
	var color:=ColorPickerButton.new(); color.color=source.water_color; properties.add_child(color); color.color_changed.connect(func(value: Color): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.water_color=value))
	var spray:=CheckButton.new(); spray.text="Waterfall spray"; spray.button_pressed=source.waterfall_spray; properties.add_child(spray); spray.toggled.connect(func(value: bool): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.waterfall_spray=value))
	for spec in [["Spray amount","spray_per_fall",1.,128.,1.],["Spray size","spray_size",.001,10.,.01],["Spray lifetime","spray_lifetime",.01,10.,.1],["Foam","foam_amount",0.,1.,.01]]:
		_value(properties,spec[0],float(source.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.set(spec[1],int(value) if spec[1]=="spray_per_fall" else value)))
	_button(properties,"Water material…",func():
		var property:=ActorProperty.new(); property.options={"extensions":["tres","res"],"native_resource_types":["Material"],"accepted_object_types":["material","natural_material","shader_material"]}; var selected:=await ActorProjectFilePicker.pick(self,property,"Choose water material")
		if selected.is_empty() or session.environment().terrain(item.id)==null: return
		_edit_water(item.id,func(next: KiwiTerrainHydrology): next.material_asset="" if selected==ActorProjectFilePicker.EMPTY_RESOURCE else selected))
	var add:=HBoxContainer.new(); properties.add_child(add)
	_button(add,"+ River",func(): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.manual_rivers.append({"id":ActorData.new_id(),"points":PackedVector3Array([Vector3(0,0,-terrain.dimensions.y*.4),Vector3.ZERO,Vector3(0,0,terrain.dimensions.y*.4)]),"width":next.river_width,"depth":next.river_depth,"follow_terrain":true})))
	_button(add,"+ Lake",func(): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.manual_lakes.append({"center":Vector2.ZERO,"level":terrain.sample(Vector2.ZERO).height+1.})))
	for index in source.manual_rivers.size():
		var river: Dictionary=source.manual_rivers[index]; var row:=HBoxContainer.new(); properties.add_child(row); var expand:=Button.new(); expand.text="River %d · %d points"%[index+1,(river.points as PackedVector3Array).size()]; expand.toggle_mode=true; expand.button_pressed=_expanded_landforms.get(str(river.id),false); row.add_child(expand); expand.toggled.connect(func(value: bool): _expanded_landforms[str(river.id)]=value; _refresh_pending=true)
		_button(row,"×",func(): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.manual_rivers.remove_at(index)))
		if not expand.button_pressed: continue
		for spec in [["Width","width",.1,100.,.1],["Depth","depth",.01,100.,.1]]:
			_value(properties,spec[0],float(river.get(spec[1],1.)),spec[2],spec[3],spec[4],func(value: float): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.manual_rivers[index][spec[1]]=value))
		var follow:=CheckButton.new(); follow.text="Follow terrain downhill"; follow.button_pressed=river.get("follow_terrain",true); properties.add_child(follow); follow.toggled.connect(func(value: bool): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.manual_rivers[index].follow_terrain=value))
		var points: PackedVector3Array=river.points
		for point in points.size():
			for axis in 3:
				_value(properties,"Point %d %s"%[point+1,["X","Y","Z"][axis]],points[point][axis],-100000.,100000.,.1,func(value: float): _edit_water(item.id,func(next: KiwiTerrainHydrology): var values: PackedVector3Array=next.manual_rivers[index].points; var position:=values[point]; position[axis]=value; values[point]=position; next.manual_rivers[index].points=values))
	for index in source.manual_lakes.size():
		_heading("Lake %d"%[index+1]); var lake: Dictionary=source.manual_lakes[index]
		_value(properties,"Water level",float(lake.get("level",0.)),-10000.,10000.,.1,func(value: float): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.manual_lakes[index].level=value))
		for axis in 2:
			_value(properties,"Center "+["X","Z"][axis],(lake.get("center",Vector2.ZERO) as Vector2)[axis],-100000.,100000.,.1,func(value: float): _edit_water(item.id,func(next: KiwiTerrainHydrology): var center: Vector2=next.manual_lakes[index].get("center",Vector2.ZERO); center[axis]=value; next.manual_lakes[index].center=center))
		_button(properties,"Remove lake",func(): _edit_water(item.id,func(next: KiwiTerrainHydrology): next.manual_lakes.remove_at(index)))
	_button(properties,"Remove water system",func(): _regenerate_terrain(item.id,{"hydrology":null}))
func _edit_caves(id: String,edit: Callable) -> void:
	var terrain:=session.environment().terrain(id)
	if terrain==null: return
	var sources: Array[KiwiTerrainCave]=[]
	for cave in terrain.caves: sources.append(cave.duplicate(true))
	edit.call(sources); _regenerate_terrain(id,{"caves":sources})
func _replace_cave(id: String,cave: KiwiTerrainCave) -> void:
	_edit_caves(id,func(sources: Array[KiwiTerrainCave]):
		for index in sources.size():
			if sources[index].cave_id==cave.cave_id: sources[index]=cave; return
		sources.append(cave))
func _add_cave(kind: int=0) -> void:
	var item:=session.primary()
	if item==null or session.environment().terrain(item.id)==null:
		for candidate in session.document.components:
			if session.environment().terrain(candidate.id)!=null: item=candidate; break
	if item==null or session.environment().terrain(item.id)==null: status.text="Add or select a terrain first."; return
	var terrain:=session.environment().terrain(item.id); var origin:=Vector2(0,-terrain.dimensions.y*.3); var surface:=terrain.sample(origin); var entrance:=Vector3(origin.x,float(surface.get("height",0.))+.5,origin.y); var cave:=KiwiTerrainCave.network(entrance,6.,minf(16.,terrain.dimensions.y*.4),2 if kind==0 else 0,terrain.seed+terrain.caves.size()*137)
	if kind==1: cave.title="Tunnel"; cave.chambers=PackedVector4Array()
	elif kind==2: cave.title="Chamber"; cave.paths=[]; cave.chambers=PackedVector4Array([Vector4(entrance.x,entrance.y-6.,entrance.z,3.)])
	_expanded_landforms[cave.cave_id]=true; canvas.cave_tool.cave_id=cave.cave_id; session.select(item.id); _edit_caves(item.id,func(sources: Array[KiwiTerrainCave]): sources.append(cave)); canvas.environment_tool="Cave path"; canvas.renderer.cave_cutaway=true; _refresh_context()
func _cave_properties(item: KiwiModelComponent,terrain: KiwiEnvironmentTerrain) -> void:
	_button(properties,"＋ Cave network",_add_cave)
	if terrain.caves.is_empty(): return
	_value(properties,"Vertical voxel size",terrain.voxel_height,.1,4.,.1,func(value: float): _regenerate_terrain(item.id,{"voxel_height":value}))
	_value(properties,"Voxel cell budget",terrain.voxel_cell_budget,1000.,2000000.,1000.,func(value: float): _regenerate_terrain(item.id,{"voxel_cell_budget":int(value)}))
	_button(properties,"Regenerate cave geometry",func(): _regenerate_terrain(item.id,{},false,true))
	_button(properties,"Density slice…",func(): var slice:=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_slice_view.gd").new(); slice.source=terrain; add_child(slice); slice.popup_centered(Vector2i(660,480)))
	for index in terrain.caves.size():
		var cave:=terrain.caves[index]; var row:=HBoxContainer.new(); properties.add_child(row); var enabled:=CheckBox.new(); enabled.button_pressed=cave.enabled; row.add_child(enabled); enabled.toggled.connect(func(value: bool): _edit_caves(item.id,func(sources: Array[KiwiTerrainCave]): sources[index].enabled=value))
		_button(row,cave.title,func(): _expanded_landforms[cave.cave_id]=not bool(_expanded_landforms.get(cave.cave_id,false)); _refresh_properties())
		_button(row,"Edit",func(): canvas.cave_tool.cave_id=cave.cave_id; canvas.environment_tool="Cave path"; canvas.renderer.cave_cutaway=true; canvas.request_sync(); _refresh_context(); canvas.grab_focus())
		_button(row,"×",func(): _edit_caves(item.id,func(sources: Array[KiwiTerrainCave]): sources.remove_at(index)))
		if not bool(_expanded_landforms.get(cave.cave_id,false)): continue
		var name:=LineEdit.new(); name.text=cave.title; name.placeholder_text="Cave name"; properties.add_child(name); name.text_submitted.connect(func(value: String): _edit_caves(item.id,func(sources: Array[KiwiTerrainCave]): sources[index].title=value))
		for spec in [["Tunnel radius","radius",.1,50.,.1],["Radius variation","radius_variation",0.,.5,.01],["Smooth joins","junction_smoothing",0.,5.,.1],["Wall roughness","roughness",0.,2.,.01],["Detail frequency","detail_frequency",.01,5.,.01],["Detail seed","seed",-100000.,100000.,1.]]:
			_value(properties,spec[0],float(cave.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): _edit_caves(item.id,func(sources: Array[KiwiTerrainCave]): sources[index].set(spec[1],int(value) if spec[1]=="seed" else value)))
		var selected:=OptionButton.new(); selected.fit_to_longest_item=false; properties.add_child(selected); var handles: Array[Dictionary]=[]
		for path in cave.paths.size():
			for point in cave.paths[path].size(): handles.append({"path":path,"point":point,"position":cave.paths[path][point]}); selected.add_item("Tunnel %d · point %d"%[path+1,point+1])
		for point in cave.chambers.size():
			var chamber:=cave.chambers[point]; handles.append({"path":-1,"point":point,"position":Vector3(chamber.x,chamber.y,chamber.z)}); selected.add_item("Chamber %d"%[point+1])
		var chosen:=0
		for handle in handles.size():
			if cave.cave_id==canvas.cave_tool.cave_id and int(handles[handle].path)==canvas.cave_tool.path_index and int(handles[handle].point)==canvas.cave_tool.point_index: chosen=handle; break
		selected.select(chosen if not handles.is_empty() else -1); selected.item_selected.connect(func(which: int): canvas.cave_tool.cave_id=cave.cave_id; canvas.cave_tool.path_index=int(handles[which].path); canvas.cave_tool.point_index=int(handles[which].point); _refresh_properties(); canvas.overlay.queue_redraw())
		if not handles.is_empty():
			var handle: Dictionary=handles[chosen]
			for axis in 3:
				_value(properties,"Point "+["X","Y","Z"][axis],(handle.position as Vector3)[axis],-10000.,10000.,.1,func(value: float): _edit_caves(item.id,func(sources: Array[KiwiTerrainCave]): var point: Vector3=handle.position; point[axis]=value; canvas.cave_tool._set_point(sources[index],int(handle.path),int(handle.point),point)))
			if int(handle.path)<0: _value(properties,"Chamber radius",cave.chambers[int(handle.point)].w,.1,50.,.1,func(value: float): _edit_caves(item.id,func(sources: Array[KiwiTerrainCave]): var point:=sources[index].chambers[int(handle.point)]; point.w=value; sources[index].chambers[int(handle.point)]=point))
		_button(properties,"Clear dig / fill edits",func(): _edit_caves(item.id,func(sources: Array[KiwiTerrainCave]): sources[index].edits.clear()))
func _erosion_properties(item: KiwiModelComponent,terrain: KiwiEnvironmentTerrain) -> void:
	var add:=MenuButton.new(); add.text="＋ Erosion operation ▾"; properties.add_child(add); add.get_popup().add_item("Hydraulic · water & sediment"); add.get_popup().add_item("Thermal · gravity & talus")
	add.get_popup().id_pressed.connect(func(mode: int):
		var operation:=KiwiTerrainErosion.new(); operation.mode=mode; _expanded_landforms[operation.operation_id]=true; _edit_erosion(item.id,func(operations: Array[KiwiTerrainErosion]): operations.append(operation)))
	for index in terrain.erosion.size():
		var operation:=terrain.erosion[index]; var row:=HBoxContainer.new(); properties.add_child(row); var enabled:=CheckBox.new(); enabled.button_pressed=operation.enabled; row.add_child(enabled); enabled.toggled.connect(func(value: bool): _edit_erosion(item.id,func(operations: Array[KiwiTerrainErosion]): operations[index].enabled=value))
		_button(row,"Hydraulic" if operation.mode==0 else "Thermal",func(): _expanded_landforms[operation.operation_id]=not bool(_expanded_landforms.get(operation.operation_id,false)); _refresh_properties())
		for action in ["↑","↓","×"]:
			_button(row,action,func(): _edit_erosion(item.id,func(operations: Array[KiwiTerrainErosion]):
				if action=="×": operations.remove_at(index)
				else:
					var target:=clampi(index+(-1 if action=="↑" else 1),0,operations.size()-1); var moving:=operations.pop_at(index) as KiwiTerrainErosion; operations.insert(target,moving)))
		if not bool(_expanded_landforms.get(operation.operation_id,false)): continue
		var specifications: Array=[["Iterations","iterations",1.,1000.,1.],["Strength","strength",0.,1.,.01]]
		if operation.mode==0: specifications.append_array([["Rainfall","rainfall",0.,1.,.005],["Sediment capacity","sediment_capacity",0.,20.,.1],["Deposition rate","deposition_rate",0.,1.,.01],["Evaporation","evaporation",0.,1.,.01],["Flow rate","flow_rate",0.,1.,.01],["Minimum slope","minimum_slope",0.,1.,.001],["Rain seed","seed",-100000.,100000.,1.]])
		else: specifications.append_array([["Talus angle","talus_angle",0.,85.,1.],["Material mobility","mobility",0.,1.,.01]])
		for spec in specifications:
			_value(properties,spec[0],float(operation.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): _edit_erosion(item.id,func(operations: Array[KiwiTerrainErosion]): operations[index].set(spec[1],int(value) if spec[1] in ["iterations","seed"] else value)))
		var region:=CheckButton.new(); region.text="Limit to circular region"; region.button_pressed=not operation.mask.is_empty(); properties.add_child(region); region.toggled.connect(func(value: bool): _edit_erosion(item.id,func(operations: Array[KiwiTerrainErosion]): operations[index].mask={"center":Vector2.ZERO,"radius":terrain.dimensions.length()*.2,"falloff":.3} if value else {}))
		if region.button_pressed:
			for axis in 2:
				_value(properties,"Region "+["X","Z"][axis],(operation.mask.get("center",Vector2.ZERO) as Vector2)[axis],-100000.,100000.,.1,func(value: float): _edit_erosion(item.id,func(operations: Array[KiwiTerrainErosion]): var center: Vector2=operations[index].mask.get("center",Vector2.ZERO); center[axis]=value; operations[index].mask.center=center))
			_value(properties,"Region radius",float(operation.mask.get("radius",5.)),.01,100000.,.1,func(value: float): _edit_erosion(item.id,func(operations: Array[KiwiTerrainErosion]): operations[index].mask.radius=value))
			_value(properties,"Region falloff",float(operation.mask.get("falloff",.3)),.01,1.,.01,func(value: float): _edit_erosion(item.id,func(operations: Array[KiwiTerrainErosion]): operations[index].mask.falloff=value))
func _generation_properties(item: KiwiModelComponent,terrain: KiwiEnvironmentTerrain) -> void:
	var profile:=OptionButton.new(); profile.fit_to_longest_item=false; properties.add_child(profile); profile.add_item("Original noise")
	for name in KiwiTerrainGenerator.PROFILES: profile.add_item(name)
	profile.select(terrain.generation.profile+1 if terrain.generation!=null else 0)
	profile.item_selected.connect(func(index: int):
		if index==0: _regenerate_terrain(item.id,{"generation":null}); return
		_regenerate_terrain(item.id,{"generation":KiwiTerrainGenerator.preset(index-1),"amplitude":[0.,8.,25.,18.,15.,7.,20.,15.,8.,8.][index-1],"frequency":.04}))
	var controls:=CheckButton.new(); controls.text="Advanced noise & landforms"; controls.button_pressed=_advanced_generation; properties.add_child(controls); controls.toggled.connect(func(value: bool): _advanced_generation=value; _refresh_properties())
	if not _advanced_generation: return
	var generation:=terrain.generation if terrain.generation!=null else KiwiTerrainGenerator.preset(9); var noise:=OptionButton.new(); properties.add_child(noise)
	for name in ["Simplex fractal","Perlin fractal","Ridged fractal","Cellular","Domain warped"]: noise.add_item(name)
	noise.select(generation.noise_type); noise.item_selected.connect(func(index: int): _edit_generation(item.id,func(source: KiwiTerrainGenerator): source.noise_type=index))
	for spec in [["Octaves","octaves",1.,10.,1.],["Lacunarity","lacunarity",1.,5.,.1],["Gain","gain",.01,1.,.01],["Medium scale","medium_weight",0.,2.,.01],["Fine scale","fine_weight",0.,1.,.01],["Warp distance","warp_strength",0.,1000.,.1],["Peak sharpness","sharpness",.1,8.,.1],["Direction","direction",-360.,360.,1.],["Island radius","island_radius",.1,1.5,.01],["Coast transition","transition",.01,1.,.01]]:
		_value(properties,spec[0],float(generation.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): _edit_generation(item.id,func(source: KiwiTerrainGenerator): source.set(spec[1],int(value) if spec[1]=="octaves" else value)))
	var add:=MenuButton.new(); add.text="＋ Geological landform ▾"; properties.add_child(add)
	for name in KiwiTerrainGenerator.LANDFORMS: add.get_popup().add_item(name)
	add.get_popup().id_pressed.connect(func(index: int):
		var id:=ActorData.new_id(); _expanded_landforms[id]=true
		_edit_generation(item.id,func(source: KiwiTerrainGenerator): source.layers.append({"id":id,"type":KiwiTerrainGenerator.LANDFORMS[index],"enabled":true,"center":Vector2.ZERO,"width":5.,"length":12.,"height":5.,"direction":0.,"sharpness":2.,"blend":"add"})))
	for index in generation.layers.size():
		var layer: Dictionary=generation.layers[index]; var id:=str(layer.get("id",index)); var row:=HBoxContainer.new(); properties.add_child(row)
		var enabled:=CheckBox.new(); enabled.button_pressed=bool(layer.get("enabled",true)); row.add_child(enabled); enabled.toggled.connect(func(value: bool): _edit_generation(item.id,func(source: KiwiTerrainGenerator): source.layers[index].enabled=value))
		_button(row,str(layer.get("type","Landform")),func(): _expanded_landforms[id]=not bool(_expanded_landforms.get(id,false)); _refresh_properties())
		for action in ["↑","↓","×"]:
			_button(row,action,func(): _edit_generation(item.id,func(source: KiwiTerrainGenerator):
				if action=="×": source.layers.remove_at(index)
				else:
					var target:=clampi(index+(-1 if action=="↑" else 1),0,source.layers.size()-1); var moving: Dictionary=source.layers.pop_at(index); source.layers.insert(target,moving)))
		if not bool(_expanded_landforms.get(id,false)): continue
		for axis in 2:
			_value(properties,"Center "+["X","Z"][axis],(layer.get("center",Vector2.ZERO) as Vector2)[axis],-100000.,100000.,.1,func(value: float): _edit_generation(item.id,func(source: KiwiTerrainGenerator): var center: Vector2=source.layers[index].get("center",Vector2.ZERO); center[axis]=value; source.layers[index].center=center))
		for spec in [["Width","width",.01,100000.,.1],["Length","length",.01,100000.,.1],["Height","height",-10000.,10000.,.1],["Direction","direction",-360.,360.,1.],["Sharpness","sharpness",.1,8.,.1]]:
			_value(properties,spec[0],float(layer.get(spec[1],1.)),spec[2],spec[3],spec[4],func(value: float): _edit_generation(item.id,func(source: KiwiTerrainGenerator): source.layers[index][spec[1]]=value))
		var blend:=OptionButton.new(); properties.add_child(blend)
		for label in ["add","maximum","minimum","replace"]: blend.add_item(label)
		blend.select(maxi(0,["add","maximum","minimum","replace"].find(str(layer.get("blend","add"))))); blend.item_selected.connect(func(which: int): _edit_generation(item.id,func(source: KiwiTerrainGenerator): source.layers[index].blend=["add","maximum","minimum","replace"][which]))
		var region:=CheckButton.new(); region.text="Limit to circular region"; region.button_pressed=not (layer.get("mask",{}) as Dictionary).is_empty(); properties.add_child(region); region.toggled.connect(func(value: bool): _edit_generation(item.id,func(source: KiwiTerrainGenerator): source.layers[index].mask={"center":source.layers[index].get("center",Vector2.ZERO),"radius":float(source.layers[index].get("width",5.))*2.,"falloff":.3} if value else {}))
		if region.button_pressed:
			_value(properties,"Region radius",float(layer.mask.get("radius",10.)),.01,100000.,.1,func(value: float): _edit_generation(item.id,func(source: KiwiTerrainGenerator): source.layers[index].mask.radius=value))
			_value(properties,"Region falloff",float(layer.mask.get("falloff",.3)),.01,1.,.01,func(value: float): _edit_generation(item.id,func(source: KiwiTerrainGenerator): source.layers[index].mask.falloff=value))

func choose_asset() -> String:
	var property:=ActorProperty.new(); property.options={"extensions":["tres","res","mesh","glb","gltf","obj"],"raw_extensions":["glb","gltf","obj"],"native_resource_types":["KiwiModelDocument","Mesh","PackedScene"]}; var selected:=await ActorProjectFilePicker.pick(self,property,"Choose an environment model")
	if selected.is_empty() or selected==ActorProjectFilePicker.EMPTY_RESOURCE: return ""
	var checked:=KiwiEnvironmentAssets.load_parts(selected)
	if not str(checked.error).is_empty(): status.text=str(checked.error); return ""
	canvas.placement_asset=selected; canvas.environment_tool="Place"; _asset_name.text=selected.get_file()
	if not _recent_assets.has(selected): _recent_assets.append(selected)
	_refresh_context(); canvas.grab_focus(); return selected
func _library_asset(asset: String) -> void:
	var resource: Resource
	if asset.get_extension().to_lower() in ["tres","res"]: resource=ResourceLoader.load(asset)
	if resource is KiwiEnvironmentDocument:
		status.text=session.insert_environment(resource); return
	var material_asset: bool=asset.get_extension().to_lower() in ["png","jpg","jpeg","webp"] or resource is Material or resource is Texture2D or (resource is ActorObjectData and resource.type_id in [&"material",&"natural_material",&"shader_material",&"image",&"noise_image"])
	if material_asset:
		var item:=session.primary()
		if item==null or session.environment().terrain(item.id)==null: status.text="Select a terrain to assign this ground material."; return
		session.action("Assign terrain material",func(): session.environment().component_settings[item.id].material=asset); return
	var result:=KiwiEnvironmentAssets.load_parts(asset)
	if not str(result.error).is_empty(): status.text=str(result.error); return
	canvas.placement_asset=asset; canvas.environment_tool="Place"; _asset_name.text=asset.get_file(); _refresh_context(); canvas.grab_focus()
func _add_palette_asset(id: String) -> void:
	var chosen:=await choose_asset()
	var scatter:=session.environment().component_settings.get(id,{}).get("scatter") as KiwiEnvironmentScatter
	if scatter==null or chosen.is_empty(): return
	var asset:=chosen
	for entry in scatter.palette:
		if str(entry.source)==asset: return
	session.action("Add scatter palette model",func(): scatter.palette.append({"source":asset,"weight":1.}))
func _save_component() -> void:
	if not await preload("res://Workspaces/ModelWorkspace/natural_edit.gd").flush(self): return
	var component: KiwiModelDocument=session.selected_environment()
	var primary:=session.primary()
	if primary!=null and session.selected.size()==1 and (preload("res://Workspaces/ModelWorkspace/natural_generator.gd").accepts(primary.generator) or preload("res://Workspaces/ModelWorkspace/natural_cluster.gd").accepts(primary) or preload("res://Workspaces/EnvironmentWorkspace/architecture/architectural_component.gd").accepts(primary.generator) or preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd").source(primary)!=null):
		component=KiwiModelDocument.new()
		for item in session.document.components:
			if item.id!=primary.id and not session.document.is_descendant(item.id,primary.id): continue
			var source:=item.copy_component()
			if item.id==primary.id: source.parent_id=""; source.transform=Transform3D.IDENTITY
			component.components.append(source)
	if component==null: status.text="Select components to save."; return
	var result:=await ActorProjectResourceSaveDialog.pick(self,"Save reusable component",primary.title if primary!=null else "Environment component","tres",false,PackedStringArray(["tres","res"]),func(): return component)
	if result.get("cancelled",true): return
	var error:=ResourceSaver.save(component,str(result.path)); status.text="Saved reusable component" if error==OK else "Could not save component"
	if error==OK:
		library.scan()
		if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()
func _choose_material(id: String,paint: bool=false) -> void:
	var property:=ActorProperty.new(); property.options={"extensions":["tres","res","png","jpg","jpeg","webp"],"native_resource_types":["Material","Texture2D"],"accepted_object_types":["material","natural_material","shader_material","image","noise_image"]}; var selected:=await ActorProjectFilePicker.pick(self,property,"Choose ground material")
	if selected.is_empty(): return
	var value: Variant=null if selected==ActorProjectFilePicker.EMPTY_RESOURCE else selected
	session.action("Assign terrain material",func(): session.environment().component_settings[id]["paint_material" if paint else "material"]=value)
func _bake_terrain(id: String) -> void:
	if _terrain_bake!=null: return
	if not _generation_jobs.is_empty(): status.text="Finish generation before baking terrain."; return
	canvas.cancel_all(); canvas.sync(); var job:=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_bake.gd").new(); _terrain_bake=job; var baked: KiwiModelDocument=await job.run(canvas.renderer,id,self); _terrain_bake=null
	if baked==null: status.text="Terrain bake canceled." if job.cancelled else job.error; return
	var chosen:=await ActorProjectResourceSaveDialog.pick(self,"Save editable terrain model","Terrain model","res",false,PackedStringArray(["res","tres"]),func(): return baked)
	if chosen.get("cancelled",true): return
	var destination:=str(chosen.path); var saved:=ResourceSaver.save(baked,destination,ResourceSaver.FLAG_COMPRESS if destination.get_extension().to_lower()=="res" else 0); status.text="Saved editable terrain model" if saved==OK else "Could not save terrain model."
	if saved==OK and LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()

func _environment_properties() -> void:
	_heading("Environment lighting")
	var document:=session.environment(); var name:=LineEdit.new(); name.text=document.title; properties.add_child(name); name.text_submitted.connect(func(value: String): session.action("Rename environment",func(): document.title=value))
	var enabled:=CheckButton.new(); enabled.text="Sun enabled"; enabled.button_pressed=bool(document.sunlight.get("enabled",true)); properties.add_child(enabled); enabled.toggled.connect(func(value: bool): session.action("Toggle environment sun",func(): document.sunlight.enabled=value))
	_value(properties,"Sun energy",float(document.sunlight.get("energy",1.5)),0.,100.,.05,func(value: float): session.action("Change sun energy",func(): document.sunlight.energy=value))
	var color:=ColorPickerButton.new(); color.color=document.sunlight.get("color",Color.WHITE); properties.add_child(color); var before:={"value":color.color}
	color.pressed.connect(func(): before.value=document.sunlight.get("color",Color.WHITE))
	color.color_changed.connect(func(value: Color): document.sunlight.color=value; canvas.request_sync())
	color.popup_closed.connect(func():
		document.sunlight.color=before.value
		if color.color!=before.value: session.action("Change sun color",func(): document.sunlight.color=color.color)
		before.value=color.color)
	for axis in 3:
		_value(properties,"Sun rotation "+["X","Y","Z"][axis],(document.sunlight.get("rotation",Vector3(-45,-30,0)) as Vector3)[axis],-360.,360.,.1,func(value: float): session.action("Rotate environment sun",func(): var vector: Vector3=document.sunlight.get("rotation",Vector3(-45,-30,0)); vector[axis]=value; document.sunlight.rotation=vector))
	_button(properties,"World / sky resource…",_choose_world)
	if not document.environment_source.is_empty():
		var path_label:=Label.new(); path_label.text=document.environment_source.get_file(); path_label.tooltip_text=document.environment_source; path_label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; properties.add_child(path_label)
		_button(properties,"Use editor preview background",func(): session.action("Clear world resource",func(): document.environment_source=""))

func _edit_climate(label: String,edit: Callable) -> void:
	var document:=session.environment(); var current:=document.climate as Resource
	if current==null: current=Climate.new()
	var next: Resource=current.call("copy_climate") as Resource; edit.call(next); var errors: PackedStringArray=next.call("validate")
	if not errors.is_empty(): status.text=errors[0]; return
	session.action(label,func(): document.climate=next); canvas.request_sync()

func _climate_properties() -> void:
	var document:=session.environment(); var source:=document.climate as Resource
	if source==null: source=Climate.new()
	_heading("Climate and time")
	var mode:=OptionButton.new(); properties.add_child(mode)
	for label in ["Manual time","Follow scene timeline","Automatic day cycle"]: mode.add_item(label)
	mode.select(source.time_mode); mode.item_selected.connect(func(index: int): _edit_climate("Change environment clock",func(next: Resource): next.time_mode=index))
	for spec in [["Time of day (hours)","time_of_day",0.,23.99,.05],["Day length (seconds)","day_length_seconds",.1,86400.,1.],["Start time","start_time",0.,23.99,.05],["Latitude","latitude",-90.,90.,.1],["Date (day of year)","date_day",1.,366.,1.]]:
		_value(properties,spec[0],float(source.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): _edit_climate("Change "+str(spec[0]).to_lower(),func(next: Resource): next.set(spec[1],int(value) if spec[1]=="date_day" else value)))
	var paused:=CheckButton.new(); paused.text="Pause time"; paused.button_pressed=source.time_paused; properties.add_child(paused); paused.toggled.connect(func(value: bool): _edit_climate("Pause environment time",func(next: Resource): next.time_paused=value))
	var season:=OptionButton.new(); properties.add_child(season)
	for label in Climate.SEASONS: season.add_item(label)
	season.select(source.season); season.item_selected.connect(func(index: int): _edit_climate("Change season",func(next: Resource): next.season=index))
	_heading("Weather and atmosphere")
	var weather:=OptionButton.new(); properties.add_child(weather)
	for label in Climate.WEATHER: weather.add_item(label)
	weather.select(source.weather); weather.item_selected.connect(func(index: int): _edit_climate("Change global weather",func(next: Resource): next.weather=index))
	for spec in [["Temperature (°C)","temperature",-100.,100.,.1],["Humidity","humidity",0.,1.,.01],["Cloud coverage","cloud_coverage",0.,1.,.01],["Weather intensity","weather_intensity",0.,1.,.01],["Visibility (m)","visibility",1.,100000.,10.]]:
		_value(properties,spec[0],float(source.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): _edit_climate("Change "+str(spec[0]).to_lower(),func(next: Resource): next.set(spec[1],value)))
	var automatic:=CheckButton.new(); automatic.text="Deterministic procedural weather"; automatic.button_pressed=source.procedural_weather; properties.add_child(automatic); automatic.toggled.connect(func(value: bool): _edit_climate("Toggle procedural weather",func(next: Resource): next.procedural_weather=value))
	for spec in [["Weather seed","weather_seed",0.,2147483647.,1.],["Weather interval (s)","weather_interval",1.,86400.,10.],["Transition (s)","weather_transition",0.,3600.,1.],["Storm probability","storm_probability",0.,1.,.01],["Rain probability","rain_probability",0.,1.,.01],["Snow probability","snow_probability",0.,1.,.01]]:
		_value(properties,spec[0],float(source.get(spec[1])),spec[2],spec[3],spec[4],func(value: float): _edit_climate("Change procedural weather",func(next: Resource): next.set(spec[1],int(value) if spec[1]=="weather_seed" else value)))
	_heading("Wind")
	for spec in [["Direction X",0], ["Direction Z",2]]:
		_value(properties,spec[0],source.wind_direction[spec[1]],-1.,1.,.01,func(value: float): _edit_climate("Change wind direction",func(next: Resource): var direction: Vector3=next.wind_direction; direction[spec[1]]=value; next.wind_direction=direction))
	_value(properties,"Wind speed (m/s)",source.wind_speed,0.,250.,.1,func(value: float): _edit_climate("Change wind speed",func(next: Resource): next.wind_speed=value))
	_value(properties,"Gust strength",source.gust_strength,0.,1.,.01,func(value: float): _edit_climate("Change wind gusts",func(next: Resource): next.gust_strength=value))
	_local_weather_properties(source)

func _local_weather_properties(source: Resource) -> void:
	_heading("Local weather regions")
	var add:=MenuButton.new(); add.text="＋ Add weather region"; properties.add_child(add)
	for label in ["Sphere","Box","Ellipsoid"]: add.get_popup().add_item(label)
	add.get_popup().id_pressed.connect(func(index: int): _edit_climate("Add weather region",func(next: Resource): next.regions.append({"id":ActorData.new_id(),"name":"Local weather","enabled":true,"shape":["Sphere","Box","Ellipsoid"][index],"center":canvas.target,"size":Vector3.ONE*80.,"blend_distance":15.,"priority":0,"overrides":{"weather":"Rain","weather_intensity":.7,"wind_velocity":next.wind_direction.normalized()*next.wind_speed}})))
	for index in source.regions.size():
		var region: Dictionary=source.regions[index]; var row:=HBoxContainer.new(); properties.add_child(row); var enabled:=CheckButton.new(); enabled.button_pressed=region.get("enabled",true); row.add_child(enabled); enabled.toggled.connect(func(value: bool): _edit_climate("Toggle local weather",func(next: Resource): next.regions[index].enabled=value))
		var name:=LineEdit.new(); name.text=str(region.get("name","Weather region")); name.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(name); name.text_submitted.connect(func(value: String): _edit_climate("Rename weather region",func(next: Resource): next.regions[index].name=value))
		_button(row,"×",func(): _edit_climate("Remove local weather",func(next: Resource): next.regions.remove_at(index)))
		for spec in [["Center X",0],["Center Y",1],["Center Z",2]]:
			_value(properties,str(spec[0]),(region.get("center",Vector3.ZERO) as Vector3)[spec[1]],-100000.,100000.,.1,func(value: float): _edit_climate("Move weather region",func(next: Resource): var center: Vector3=next.regions[index].get("center",Vector3.ZERO); center[spec[1]]=value; next.regions[index].center=center))
		_value(properties,"Radius",float((region.get("size",Vector3.ONE*80.) as Vector3).x)*.5,1.,100000.,1.,func(value: float): _edit_climate("Resize weather region",func(next: Resource): next.regions[index].size=Vector3.ONE*value*2.))
		_value(properties,"Blend distance",float(region.get("blend_distance",0.)),0.,100000.,1.,func(value: float): _edit_climate("Blend local weather",func(next: Resource): next.regions[index].blend_distance=value))
		var overrides: Dictionary=region.get("overrides",{}); var local_weather:=OptionButton.new(); properties.add_child(local_weather)
		for label in Climate.WEATHER: local_weather.add_item(label)
		local_weather.select(maxi(0,Climate.WEATHER.find(str(overrides.get("weather","Clear"))))); local_weather.item_selected.connect(func(which: int): _edit_climate("Change local weather",func(next: Resource): next.regions[index].overrides.weather=Climate.WEATHER[which]))
		_value(properties,"Local intensity",float(overrides.get("weather_intensity",1.)),0.,1.,.01,func(value: float): _edit_climate("Change local weather intensity",func(next: Resource): next.regions[index].overrides.weather_intensity=value))

func _choose_world() -> void:
	var property:=ActorProperty.new(); property.options={"extensions":["tres","res"],"native_resource_types":["Environment"],"accepted_object_types":["environment"]}; var selected:=await ActorProjectFilePicker.pick(self,property,"Choose world / sky environment")
	if selected.is_empty(): return
	session.action("Assign world environment",func(): session.environment().environment_source="" if selected==ActorProjectFilePicker.EMPTY_RESOURCE else selected)
func _add_scatter() -> void:
	var terrain_id:=""; var item:=session.primary()
	if item!=null and session.environment().terrain(item.id)!=null: terrain_id=item.id
	else:
		for candidate in session.document.components:
			if session.environment().terrain(candidate.id)!=null: terrain_id=candidate.id; break
	if terrain_id.is_empty(): status.text="Add or select a terrain first."; return
	if canvas.placement_asset.is_empty(): await choose_asset()
	if not canvas.placement_asset.is_empty(): status.text=session.add_scatter(terrain_id,canvas.placement_asset)
func _command(command: String) -> void:
	if command=="Select all":
		session.selected.clear()
		for item in session.document.components: session.selected.append(item.id)
	elif command=="Invert selection":
		var ids: Array[String]=[]
		for item in session.document.components:
			if not session.selected.has(item.id): ids.append(item.id)
		session.selected=ids
	session.changed.emit()

func _to_scene() -> void:
	if await save()==OK and not path.is_empty(): use_in_scene.emit(path)
func _place_tool() -> void:
	canvas.environment_tool="Place"; _refresh_context()
	if canvas.placement_asset.is_empty(): choose_asset()
func _open_model(source: String) -> void:
	var tabs:=get_tree().get_first_node_in_group("actor_scene_tabs")
	if tabs!=null: tabs.open_model(source)
func _open_library_source(source: String) -> void:
	var tabs:=get_tree().get_first_node_in_group("actor_scene_tabs")
	if tabs==null: return
	if source.get_extension().to_lower() in ["png","jpg","jpeg","webp"]: tabs.open_image(source); return
	var resource: Resource=ResourceLoader.load(source) if source.get_extension().to_lower() in ["tres","res"] else null
	if resource is KiwiEnvironmentDocument: tabs.open_environment(source)
	elif resource is ShaderMaterial: tabs.open_shader(resource.shader,resource)
	elif resource is Material or resource is ActorObjectData: status.text="Use this material on a terrain; edit its source through the project resource inspector."
	else: tabs.open_model(source)

func open_source(value: Variant,state: Dictionary={}) -> bool:
	preload("res://Workspaces/EnvironmentWorkspace/architecture/building_ui.gd").cancel(self)
	_cancel_generation()
	_failed_volumes.clear()
	canvas.cancel_all()
	hierarchy.clear()
	if session.changed.is_connected(_changed): session.changed.disconnect(_changed)
	if session.changed.is_connected(canvas.request_sync): session.changed.disconnect(canvas.request_sync)
	if state.get("session") is KiwiEnvironmentSession: session=state.session
	else:
		var loaded: Resource=value if value is Resource else (ResourceLoader.load(str(value),"",ResourceLoader.CACHE_MODE_IGNORE) if value is String and ResourceLoader.exists(value) else null)
		if loaded!=null and not loaded is KiwiEnvironmentDocument: status.text="Choose an Environment document."; return false
		session=KiwiEnvironmentSession.new()
		if loaded is KiwiEnvironmentDocument: session.document=loaded.snapshot()
		else: session.add_terrain(); session._undo.clear(); session.dirty=false
		var linked: Dictionary=preload("res://Workspaces/EnvironmentWorkspace/architecture/module_links.gd").resolve(session.document)
		if linked.document!=null: session.document=linked.document
		else: status.text=linked.error+" Saved instance geometry is retained."
		if not session.environment().validate().is_empty(): status.text=session.environment().validate()[0]; return false
	var restored:=session.document.workspace_state.duplicate(true); restored.merge(state,true)
	preload("res://Workspaces/EnvironmentWorkspace/world/world_ui.gd").restore(self,restored.get("world_ui",{}))
	canvas.session=session; session.mode="Object"; canvas.rig_tool.editor.session=session; hierarchy.session=session; session.changed.connect(_changed); session.changed.connect(canvas.request_sync); path=str(state.get("path",value if value is String else "")); canvas.restore_state(restored.get("view",{})); canvas.environment_tool=str(restored.get("tool","Select")); canvas.brush_radius=float(restored.get("brush_radius",2.)); canvas.brush_strength=float(restored.get("brush_strength",.2)); canvas.brush_falloff=float(restored.get("brush_falloff",1.)); canvas.placement_asset=str(restored.get("placement_asset","")); _recent_assets.assign(restored.get("recent",[])); session.selected.assign(restored.get("selected",[])); _collapsed=restored.get("collapsed",{}).duplicate(); _property_scrolls=restored.get("property_scrolls",{}).duplicate(); _last_selection=""; _settings_mode=bool(restored.get("settings",false)); _climate_mode=bool(restored.get("climate_mode",false)); _split.split_offset=int(restored.get("hierarchy_width",200)); _left.visible=bool(restored.get("hierarchy_visible",true)); _right.visible=bool(restored.get("properties_visible",true))
	_right_split.split_offset=int(restored.get("properties_split",0)); library.search.text=str(restored.get("library_search","")); library.category.select(clampi(int(restored.get("library_category",0)),0,library.category.item_count-1)); library.refresh(); _asset_name.text=canvas.placement_asset.get_file() if not canvas.placement_asset.is_empty() else "Browse project assets…"
	var brush: Dictionary=restored.get("terrain_brush",{})
	for key in ["brush_spacing","brush_target_height","brush_terrace_step","brush_square","brush_symmetry_x","brush_symmetry_z"]:
		if brush.has(key): canvas.set(key,brush[key])
	canvas.stamp_path=str(brush.get("stamp_path","")); canvas.stamp_image=ActorImageGenerator.image_from_value(canvas.stamp_path) if not canvas.stamp_path.is_empty() else null; _advanced_generation=bool(restored.get("advanced_generation",false)); _expanded_landforms=restored.get("expanded_landforms",{}).duplicate()
	var cave_view: Dictionary=restored.get("cave_view",{}); canvas.cave_tool.cave_id=str(cave_view.get("id","")); canvas.cave_tool.path_index=int(cave_view.get("path",0)); canvas.cave_tool.point_index=int(cave_view.get("point",0)); canvas.renderer.cave_cutaway=bool(cave_view.get("cutaway",false)); canvas.viewport.debug_draw=Viewport.DEBUG_DRAW_WIREFRAME if bool(cave_view.get("wireframe",false)) else Viewport.DEBUG_DRAW_DISABLED
	if library._root!=ActorProjectFilePicker.root_directory(): library.scan()
	_refresh_pending=true; canvas.request_sync(); preload("res://Workspaces/EnvironmentWorkspace/architecture/building_ui.gd").restore(self); return true
func capture_state() -> Dictionary:
	preload("res://Workspaces/EnvironmentWorkspace/architecture/building_ui.gd").cancel(self)
	canvas.cancel_all(); var state:=_editor_state(); state.session=session; state.path=path; return state
func _editor_state() -> Dictionary:
	_store_collapsed(hierarchy.get_root())
	if not _last_selection.is_empty(): _property_scrolls[_last_selection]=_right.scroll_vertical
	var brush:={}
	for key in ["brush_spacing","brush_target_height","brush_terrace_step","brush_square","brush_symmetry_x","brush_symmetry_z","stamp_path"]: brush[key]=canvas.get(key)
	return {"world_ui":preload("res://Workspaces/EnvironmentWorkspace/world/world_ui.gd").capture(self),"view":canvas.capture_state(),"tool":canvas.environment_tool,"brush_radius":canvas.brush_radius,"brush_strength":canvas.brush_strength,"brush_falloff":canvas.brush_falloff,"placement_asset":canvas.placement_asset,"recent":_recent_assets.duplicate(),"selected":session.selected.duplicate(),"collapsed":_collapsed.duplicate(),"property_scrolls":_property_scrolls.duplicate(),"settings":_settings_mode,"climate_mode":_climate_mode,"hierarchy_width":_split.split_offset,"hierarchy_visible":_left.visible,"properties_visible":_right.visible,"properties_split":_right_split.split_offset,"library_search":library.search.text,"library_category":library.category.selected,"terrain_brush":brush,"advanced_generation":_advanced_generation,"expanded_landforms":_expanded_landforms.duplicate(),"cave_view":{"id":canvas.cave_tool.cave_id,"path":canvas.cave_tool.path_index,"point":canvas.cave_tool.point_index,"cutaway":canvas.renderer.cave_cutaway,"wireframe":canvas.viewport.debug_draw==Viewport.DEBUG_DRAW_WIREFRAME}}
func open_dialog() -> void:
	var property:=ActorProperty.new(); property.options={"extensions":["tres","res"],"native_resource_types":["KiwiEnvironmentDocument"]}; var selected:=await ActorProjectFilePicker.pick(self,property,"Open environment")
	if selected.is_empty() or selected==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var tabs:=get_tree().get_first_node_in_group("actor_scene_tabs")
	if tabs!=null: tabs.open_environment(selected)
func save() -> Error:
	if path.is_empty(): return await save_as()
	return await save_to(path)
func save_as() -> Error:
	var result:=await ActorProjectResourceSaveDialog.pick(self,"Save environment",path.get_file().get_basename() if not path.is_empty() else "Environment","tres",false,PackedStringArray(["tres","res"]),func(): return session.environment().snapshot())
	if not result.get("cancelled",true): return await save_to(str(result.path))
	return ERR_SKIP
func save_to(destination: String) -> Error:
	if not await preload("res://Workspaces/ModelWorkspace/natural_edit.gd").flush(self): return ERR_BUSY
	canvas.cancel_all(); var preparing_session:=session
	while not _generation_jobs.is_empty():
		await get_tree().process_frame
		if session!=preparing_session: return ERR_BUSY
	for component in session.document.components:
		var terrain:=session.environment().terrain(component.id)
		if terrain==null or (terrain.water_valid() and terrain.biomes_valid() and terrain.volumes_valid() and terrain.cave_biomes_valid()): continue
		_regenerate_terrain(component.id,{},false,true)
		while not _generation_jobs.is_empty():
			await get_tree().process_frame
			if session!=preparing_session: return ERR_BUSY
		terrain=session.environment().terrain(component.id)
		if terrain==null or not terrain.water_valid() or not terrain.biomes_valid() or not terrain.volumes_valid() or not terrain.cave_biomes_valid(): status.text="Terrain generation must finish before this environment can be saved."; return ERR_CANT_CREATE
	session.environment().workspace_state.merge(_editor_state(),true); var errors:=session.environment().validate()
	if not errors.is_empty(): status.text=errors[0]; return ERR_INVALID_DATA
	canvas.sync()
	var preview_session:=session
	while not canvas.renderer.pending_assets.is_empty() or not canvas.renderer.pending_chunks.is_empty():
		await get_tree().process_frame
		if session!=preview_session: return ERR_BUSY
	var saved_session:=session; var revision:=session.revision; var saved:=session.environment().snapshot() as KiwiEnvironmentDocument
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw; var image:=canvas.viewport.get_texture().get_image(); image.resize(240,160,Image.INTERPOLATE_LANCZOS); saved.preview_png=image.save_png_to_buffer()
	var error:=ResourceSaver.save(saved,destination)
	if error==OK:
		if saved_session.revision==revision: saved_session.dirty=false
		if session==saved_session: path=destination; status.text="Saved "+destination
		environment_saved.emit(destination,saved_session)
		if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()
	else: status.text="Could not save the environment."
	return error
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or not event.ctrl_pressed: return
	if event.keycode==KEY_S: save_as() if event.shift_pressed else save(); get_viewport().set_input_as_handled()
	elif event.keycode==KEY_Z:
		if event.shift_pressed: session.redo()
		else: session.undo()
		get_viewport().set_input_as_handled()
	elif event.keycode==KEY_Y: session.redo(); get_viewport().set_input_as_handled()

func _regenerate_terrain(id: String,settings: Dictionary,reset_edits: bool=false,derived_only: bool=false) -> void:
	var terrain:=session.environment().terrain(id)
	if terrain==null: return
	if maxi(terrain.resolution,int(settings.get("resolution",terrain.resolution)))<129 and terrain.erosion.is_empty() and terrain.caves.is_empty() and terrain.hydrology==null and terrain.biomes==null and not settings.has("biomes") and not settings.has("hydrology") and not settings.has("erosion") and not settings.has("caves"): session.regenerate_terrain(id,settings,reset_edits); return
	_cancel_generation(false); _failed_volumes.erase(id); var job:=preload("res://Workspaces/EnvironmentWorkspace/environment_generation_job.gd").new(); var entry:={"job":job,"session":session,"id":id,"source":terrain,"signature":terrain.signature(),"derived_only":derived_only}; _generation_jobs.append(entry); job.start(terrain,settings,reset_edits); _generation_cancel.show(); status.text="Generating terrain…"
func _cancel_generation(suspend_worlds: bool=true) -> void:
	if suspend_worlds: preload("res://Workspaces/EnvironmentWorkspace/world/world_dependencies.gd").suspend(self)
	if session.pending_source_cancel.is_valid(): session.pending_source_cancel.call()
	if _terrain_bake!=null: _terrain_bake.cancel()
	for entry: Dictionary in _generation_jobs:
		entry.job.cancel()
		if entry.session==session: _failed_volumes[entry.id]=entry.signature
	canvas.renderer.cancel_scatter_generation()
	_generation_cancel.hide()
func _poll_generation() -> void:
	for index in range(_generation_jobs.size()-1,-1,-1):
		var entry: Dictionary=_generation_jobs[index]; var job: RefCounted=entry.job
		if not job.complete():
			if not job.cancelled(): status.text="Generating terrain · %d%%"%roundi(job.progress()*100.)
			continue
		job.collect(); _generation_jobs.remove_at(index)
		if job.cancelled(): continue
		if not str(job.error).is_empty():
			if entry.session==session: _failed_volumes[entry.id]=entry.signature
			status.text=str(job.error); continue
		var target:=entry.session as KiwiEnvironmentSession; var source:=target.environment().terrain(str(entry.id))
		if target!=session or source!=entry.source or source.signature()!=int(entry.signature): status.text="Generation discarded because its terrain changed."; continue
		var generated: KiwiEnvironmentTerrain=job.terrain; var mesh: KiwiModelMesh=job.mesh
		var apply:=func(): target.environment().component_settings[entry.id].terrain=generated; target.document.component(str(entry.id)).mesh=mesh
		if bool(entry.get("derived_only",false)): apply.call(); target.dirty=true; target.revision+=1; target.changed.emit()
		else: target.action("Generate terrain",apply)
		status.text="Terrain generated in %.1f ms"%job.elapsed_ms
	_generation_cancel.visible=not _generation_jobs.is_empty()
func _exit_tree() -> void:
	_cancel_generation()
	var recipe: RefCounted=get_meta("world_recipe_job") if has_meta("world_recipe_job") else null
	if recipe!=null: recipe.cancel(); recipe.collect()
	var site: RefCounted=get_meta("world_site_job") if has_meta("world_site_job") else null
	if site!=null: site.cancel(); site.collect()
	for entry: Dictionary in _generation_jobs: entry.job.collect()
	_generation_jobs.clear()


