class_name KiwiModelWorkspace
extends Control
const Selection = preload("res://Workspaces/ModelWorkspace/model_selection.gd")
signal document_changed
signal model_saved(path: String, saved_session: KiwiModelSession)
signal use_in_scene(path: String)
var session := KiwiModelSession.new()
var canvas := KiwiModelViewport.new()
var path := ""
var source: Variant
var title := Label.new()
var status := Label.new()
var hierarchy := preload("res://Workspaces/ModelWorkspace/model_hierarchy.gd").new()
var properties := VBoxContainer.new()
var context := HBoxContainer.new()
var mode_buttons: Dictionary = {}
var _refresh_pending := false
var _property_gesture := false
var _syncing := false
var _last_geometry := "Extrude"
var _last_amount := .2
var _recent: Array[String] = []
var _inspector_tabs := TabContainer.new()
var _modifiers := VBoxContainer.new()
var _surfaces := VBoxContainer.new()
var _main_split: HSplitContainer
var _left_split: HSplitContainer
var _transform_fields: Dictionary = {}
var _tool_buttons: Dictionary = {}
var _snap_button: CheckButton
var _space_picker: OptionButton
var _layout_ready := false
var _pending_panels: Dictionary = {}
var rig_ui: KiwiRigUI
const OPERATIONS := ["Extrude","Extrude individual","Inset","Bevel","Subdivide","Weld","Smooth","Flip normals","Separate faces","Join meshes","Duplicate","Delete","Group","Parent","Unparent","Center origin","Select all","Invert selection","Select connected","Grow selection","Shrink selection","Select similar normals","Select material","Frame selected","Frame all","Boolean difference","Boolean union","Boolean intersection","Repeat operation"]

func _ready() -> void:
	rig_ui=KiwiRigUI.new(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_theme()
	add_theme_font_size_override("font_size",13)
	var column := VBoxContainer.new(); column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); column.add_theme_constant_override("separation",5); add_child(column)
	var header := HBoxContainer.new(); column.add_child(header)
	title.text="3D MODEL  /  Untitled"; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; title.add_theme_color_override("font_color",Color("79dfc5")); header.add_child(title)
	var file := MenuButton.new(); file.text="File"; header.add_child(file)
	for label in ["Open model / import…","Save   Ctrl+S","Save As…   Ctrl+Shift+S","Save to Super Clipboard"]: file.get_popup().add_item(label)
	file.get_popup().id_pressed.connect(func(id:int):
		match id:
			0: open_dialog()
			1: save()
			2: save_as()
			3: KiwiSuperClipboardService.instance.quick_save(session.document.snapshot(),title.text)
	)
	_button(header,"↶",func(): session.undo(),"Undo · Ctrl+Z"); _button(header,"↷",func(): session.redo(),"Redo · Ctrl+Shift+Z")
	_button(header,"⌕ Commands",func(): command_search(),"Search all tools · Space")
	_button(header,"✦ Quick Rig",func(): rig_ui.quick_rig(),"Create bones → Bind geometry → Pose")
	_button(header,"To Scene ↗",func():
		await save()
		if not path.is_empty(): use_in_scene.emit(path),"Save and create a Basic Mesh actor")
	var tools := HBoxContainer.new(); column.add_child(tools)
	for mode in ["Object","Vertex","Edge","Face"]:
		var button := _button(tools,mode,func(): session.mode=mode; session.elements=PackedInt32Array(); session.changed.emit(),"Selection mode · "+str(mode_buttons.size()+1))
		button.toggle_mode=true; mode_buttons[mode]=button
	_separator(tools)
	_button(tools,"＋ Create",func(): create_menu())
	for name in ["Move","Rotate","Scale"]:
		var button := _button(tools,name,func(): canvas.tool=name; canvas.sculpt=""; canvas.overlay.queue_redraw(); _refresh_pending=true,{"Move":"W","Rotate":"E","Scale":"R"}[name])
		button.toggle_mode=true; _tool_buttons[name]=button
	var space := OptionButton.new(); space.add_item("World axes"); space.add_item("Local axes"); tools.add_child(space); space.item_selected.connect(func(index:int): canvas.local_axes=index==1; canvas.overlay.queue_redraw())
	_space_picker=space
	var snap := CheckButton.new(); snap.text="Snap"; tools.add_child(snap); snap.toggled.connect(func(enabled:bool): canvas.snap=enabled)
	_snap_button=snap
	var view := MenuButton.new(); view.text="View ▾"; tools.add_child(view)
	for label in ["Frame selected · F","Frame all · Shift+F","Perspective / orthographic","Front","Back","Left","Right","Top","Bottom","Grid","Edges","Wireframe","X-ray","Face normals","Components panel","Properties panel"]: view.get_popup().add_item(label)
	view.get_popup().id_pressed.connect(_view_command)
	var context_scroll := ScrollContainer.new(); context_scroll.custom_minimum_size.y=34; context_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; column.add_child(context_scroll); context_scroll.add_child(context)
	var split := HSplitContainer.new(); split.size_flags_vertical=Control.SIZE_EXPAND_FILL; split.split_offset=180; column.add_child(split)
	_left_split=split
	hierarchy.name="ModelComponents"; hierarchy.custom_minimum_size.x=150; hierarchy.size_flags_vertical=Control.SIZE_EXPAND_FILL; hierarchy.hide_root=true; hierarchy.columns=3; hierarchy.set_column_expand(1,false); hierarchy.set_column_custom_minimum_width(1,26); hierarchy.set_column_expand(2,false); hierarchy.set_column_custom_minimum_width(2,26); hierarchy.select_mode=Tree.SELECT_MULTI; hierarchy.allow_reselect=true; split.add_child(hierarchy)
	hierarchy.multi_selected.connect(_tree_selected); hierarchy.item_edited.connect(_rename); hierarchy.button_clicked.connect(_tree_button)
	hierarchy.session=session; hierarchy.tooltip_text="Drag onto a component to parent. Drop in empty space to unparent. World position is preserved."
	var main := HSplitContainer.new(); main.split_offset=950; main.size_flags_horizontal=Control.SIZE_EXPAND_FILL; split.add_child(main)
	_main_split=main
	canvas.session=session; canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL; canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL; main.add_child(canvas)
	canvas.command_requested.connect(run_command); canvas.gesture_finished.connect(_refresh)
	canvas.notice.connect(func(message:String): status.text=message)
	_inspector_tabs.custom_minimum_size.x=235; main.add_child(_inspector_tabs)
	for data in [["Object",properties],["Modifiers",_modifiers],["Surface",_surfaces]]:
		var scroll := ScrollContainer.new(); scroll.name=data[0]; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; _inspector_tabs.add_child(scroll)
		var fields: VBoxContainer=data[1]; fields.size_flags_horizontal=Control.SIZE_EXPAND_FILL; fields.add_theme_constant_override("separation",8); scroll.add_child(fields)
	status.custom_minimum_size.y=22; status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; status.add_theme_color_override("font_color",Color("96adbd")); column.add_child(status)
	session.changed.connect(_changed); _refresh(); _initial_layout.call_deferred()

func _initial_layout() -> void:
	await get_tree().process_frame
	if not is_inside_tree(): return
	if not _pending_panels.is_empty(): _restore_panels(_pending_panels); _pending_panels={}
	else:
		_left_split.split_offset=clampi(int(size.x*.13),150,200)
		_main_split.split_offset=maxi(250,int(_main_split.size.x)-280)
		if size.x<1100: hierarchy.hide()
	_layout_ready=true

func _capture_panels() -> Dictionary:
	return {"hierarchy":hierarchy.visible,"inspector":_inspector_tabs.visible,"inspector_tab":_inspector_tabs.current_tab,"left":_left_split.split_offset,"right":_main_split.split_offset}
func _restore_panels(state: Dictionary) -> void:
	hierarchy.visible=state.get("hierarchy",size.x>=1100); _inspector_tabs.visible=state.get("inspector",true); _inspector_tabs.current_tab=clampi(state.get("inspector_tab",0),0,2)
	_left_split.split_offset=state.get("left",180); _main_split.split_offset=state.get("right",maxi(250,int(_main_split.size.x)-280))

func _draw() -> void: draw_rect(Rect2(Vector2.ZERO,size),Color("101923"))
func _build_theme() -> void:
	theme=Theme.new(); theme.default_font_size=13
	for type in ["Button","MenuButton","OptionButton","CheckButton","Label","LineEdit","Tree","TabContainer","PopupMenu"]: theme.set_font_size("font_size",type,13)
	for data in [["normal","182b3a","344e60"],["hover","24473f","72d6bc"],["pressed","285b51","79e3c5"],["focus","182b3a","73d9c0"],["disabled","17232e","283744"]]:
		var style := StyleBoxFlat.new(); style.bg_color=Color(data[1]); style.border_color=Color(data[2]); style.set_border_width_all(1); style.set_corner_radius_all(6); style.content_margin_left=9; style.content_margin_right=9; style.content_margin_top=5; style.content_margin_bottom=5
		for type in ["Button","OptionButton","MenuButton"]: theme.set_stylebox(data[0],type,style)
	var panel := StyleBoxFlat.new(); panel.bg_color=Color("14222e"); panel.border_color=Color("31495a"); panel.set_border_width_all(1); panel.set_corner_radius_all(7); panel.content_margin_left=8; panel.content_margin_right=8; panel.content_margin_top=7; panel.content_margin_bottom=7
	theme.set_stylebox("panel","Tree",panel); theme.set_stylebox("panel","TabContainer",panel)
	var selected := panel.duplicate(); selected.bg_color=Color("26564d"); selected.border_color=Color("78dbc2"); theme.set_stylebox("selected","Tree",selected); theme.set_stylebox("selected_focus","Tree",selected)
	var field := panel.duplicate(); field.bg_color=Color("0f1d29"); field.content_margin_top=4; field.content_margin_bottom=4
	theme.set_stylebox("normal","LineEdit",field); theme.set_color("font_color","LineEdit",Color("e4eef5"))
	for name in ["tab_selected","tab_unselected","tab_hovered"]:
		var tab := panel.duplicate(); tab.bg_color=Color("26534b") if name=="tab_selected" else Color("192d3c"); theme.set_stylebox(name,"TabContainer",tab)

func _button(parent: Node, label: String, action: Callable, tooltip: String="") -> Button:
	var button := Button.new(); button.text=label; button.tooltip_text=tooltip; button.custom_minimum_size.y=28; parent.add_child(button); button.pressed.connect(action); return button
func _separator(parent: Node) -> void: var separator := VSeparator.new(); parent.add_child(separator)
func _label(parent: Node, text: String) -> void:
	var label := Label.new(); label.text=text; label.add_theme_color_override("font_color",Color("7ddcc4")); parent.add_child(label)
func _clear(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()
func _changed() -> void:
	canvas.request_sync()
	if canvas._drag: _sync_transform_fields()
	if not _property_gesture and not canvas._drag and canvas._create_phase==0 and not canvas._pressed: _refresh_pending=true
	document_changed.emit()
func _process(_delta: float) -> void:
	if canvas.rig_tool!=null and not canvas.rig_tool.drag.is_empty(): return
	if _refresh_pending and is_visible_in_tree(): _refresh_pending=false; _refresh()
func _refresh() -> void:
	if not is_inside_tree(): return
	_syncing=true
	title.text="3D MODEL  /  "+(path.get_file() if not path.is_empty() else "Untitled")
	for mode in mode_buttons: mode_buttons[mode].set_pressed_no_signal(session.mode==mode)
	for tool in _tool_buttons: _tool_buttons[tool].set_pressed_no_signal(canvas.tool==tool and canvas.sculpt.is_empty())
	_snap_button.set_pressed_no_signal(canvas.snap); _space_picker.select(1 if canvas.local_axes else 0)
	_rebuild_tree(); _clear(context); _clear(properties); _clear(_modifiers); _clear(_surfaces)
	_transform_fields.clear()
	var item := session.primary()
	var rigging := canvas.rig_tool!=null and canvas.rig_tool.editor.enabled
	for mode in mode_buttons: mode_buttons[mode].visible=not rigging
	for tool in _tool_buttons: _tool_buttons[tool].visible=not rigging or canvas.rig_tool.editor.mode in ["Pose","Weight"]
	_space_picker.visible=not rigging
	_inspector_tabs.set_tab_title(0,"Rig" if rigging else "Object")
	_inspector_tabs.set_tab_hidden(1,rigging); _inspector_tabs.set_tab_hidden(2,rigging)
	if rigging: _inspector_tabs.current_tab=0
	if canvas.rig_tool!=null and canvas.rig_tool.editor.enabled:
		rig_ui.build_context(context); rig_ui.build_properties(properties); _syncing=false; return
	_button(context,"Extrude" if session.mode=="Face" else "Edit ▾",func():
		if session.mode=="Face": run_command("Extrude")
		else: command_search())
	if session.mode=="Face":
		var push := _button(context,"Push/pull",func(): canvas.push_pull=not canvas.push_pull; canvas.grab_focus(),"Drag faces to extrude/recess · Alt+drag also works")
		push.toggle_mode=true; push.button_pressed=canvas.push_pull
		for name in ["Inset","Bevel","Separate faces"]: _button(context,name,run_command.bind(name))
	elif session.mode=="Edge":
		for name in ["Bevel","Subdivide","Weld"]: _button(context,name,run_command.bind(name))
	else:
		for name in ["Duplicate","Group","Parent","Unparent"]: _button(context,name,run_command.bind(name))
	_button(context,"Deform ▾",_deform_menu)
	var proportion := CheckButton.new(); proportion.text="Proportional"; proportion.button_pressed=canvas.proportional; context.add_child(proportion); proportion.toggled.connect(func(enabled:bool): canvas.proportional=enabled)
	if canvas.proportional or not canvas.sculpt.is_empty():
		_number(context,"Radius",canvas.radius,.02,100,.05,func(value:float): canvas.radius=value)
		if not canvas.sculpt.is_empty(): _number(context,"Strength",canvas.strength,.01,1,.01,func(value:float): canvas.strength=value)
	if item==null:
		_label(properties,"Start with a shape")
		_button(properties,"＋ Create geometry",create_menu)
		_label(properties,"Or open an existing model")
		_button(properties,"Open / import…",open_dialog)
		_syncing=false; return
	_label(properties,item.title)
	if item.locked: _label(properties,"Locked — unlock in Components")
	var affine := KiwiModelDocument.transform_values(item.transform)
	for data in [["Position",affine.position],["Rotation",affine.rotation],["Scale",affine.scale]]:
		var name: String=data[0]; var vector: Vector3=data[1]
		_label(properties,name)
		var row := HBoxContainer.new(); properties.add_child(row)
		for axis in 3:
			var control := _number(row,["X","Y","Z"][axis],vector[axis],-10000,10000,.01,_transform_value.bind(name,axis))
			control.custom_minimum_size.x=62; control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			_transform_fields[name+str(axis)]=control
	if not item.generator.is_empty() and item.skin_mesh==null and item.binding==null:
		_label(properties,"PARAMETRIC · "+item.generator)
		var fields := ["radius","height","segments"] if item.generator not in ["Box","Beam","Panel","Plane","Prism","Stairs"] else ["width","height","depth"]
		if item.generator in ["Sphere","Torus"]: fields=["radius","segments"]
		if item.generator=="Plane": fields=["width","depth"]
		if item.generator=="Arch": fields.append("inner_ratio")
		if item.generator=="Gear": fields.append_array(["teeth","tooth_depth","hole"])
		if item.generator=="Pipe": fields.append("hole")
		if item.generator=="Stairs": fields.append("steps")
		for field in fields:
			var size: Vector3=item.parameters.get("size",Vector3.ONE); var value := float(item.parameters.get(field,24 if field=="segments" else (16 if field=="teeth" else (6 if field=="steps" else .5))))
			if field in ["width","height","depth"] and fields[0]=="width": value=size[["width","height","depth"].find(field)]
			_number(properties,field.capitalize(),value,.001,128 if field in ["segments","teeth","steps"] else 100,1 if field in ["segments","teeth","steps"] else .01,_parameter_value.bind(item.id,field,fields[0]=="width"))
		_button(properties,"Make editable mesh",func(): session.action("Make editable",func(): session.primary().generator=""))
	var metrics := Label.new(); metrics.text="%d vertices · %d faces"%[item.mesh.vertices.size(),item.mesh.faces.size()] if item.mesh!=null else ("Skeleton · %d bones"%item.bones.size() if item.is_skeleton else "Group / transform"); properties.add_child(metrics)
	if item.skin_mesh!=null or item.binding!=null: _label(properties,"Rigged mesh · topology preserved\nQuick Rig → Pose / Weight to edit")
	_label(properties,"PRECISION")
	_number(properties,"Grid",canvas.grid_step,.01,100,.01,func(value:float): canvas.grid_step=value; canvas.rebuild_grid())
	var snap_type := OptionButton.new()
	for name in ["Grid","Vertex","Edge","Surface","Origin"]: snap_type.add_item(name)
	snap_type.select(["Grid","Vertex","Edge","Surface","Origin"].find(canvas.snap_kind)); properties.add_child(snap_type); snap_type.item_selected.connect(func(index:int): canvas.snap_kind=snap_type.get_item_text(index); _refresh_pending=true)
	if canvas.snap_kind=="Surface":
		var align := CheckButton.new(); align.text="Align to surface normal"; align.button_pressed=canvas.align_surface; properties.add_child(align); align.toggled.connect(func(enabled:bool): canvas.align_surface=enabled)
	_button(properties,"Center origin",run_command.bind("Center origin")); _button(properties,"Frame selected",canvas.frame)
	_build_modifiers(item); _build_surfaces(item); _syncing=false

func _sync_transform_fields() -> void:
	var item := session.primary()
	if item==null: return
	for kind in ["Position","Rotation","Scale"]:
		var affine := KiwiModelDocument.transform_values(item.transform)
		var value: Vector3=affine[{"Position":"position","Rotation":"rotation","Scale":"scale"}[kind]]
		for i in 3:
			var control: Variant=_transform_fields.get(kind+str(i))
			if is_instance_valid(control) and not control.dragging and not control.get_line_edit().has_focus(): control.set_value_no_signal(value[i])

func _number(parent: Node, label: String, value: float, minimum: float, maximum: float, step: float, setter: Callable) -> DragNumber:
	var row := VBoxContainer.new(); row.size_flags_horizontal=Control.SIZE_EXPAND_FILL; parent.add_child(row)
	var caption := Label.new(); caption.text=label; caption.add_theme_font_size_override("font_size",11); row.add_child(caption)
	var number := DragNumber.new(); number.min_value=minimum; number.max_value=maximum; number.step=step; number.value=value; row.add_child(number)
	number.interaction_started.connect(func(): session.begin(); _property_gesture=true)
	number.preview_changed.connect(func(next:float): setter.call(next); session.changed.emit())
	number.drag_committed.connect(func(_next:float): _property_gesture=false; session.commit("Change "+label); _refresh_pending=true)
	number.drag_cancelled.connect(func(): _property_gesture=false; session.cancel(); _refresh_pending=true)
	number.value_changed.connect(func(next:float):
		if _syncing or number.dragging: return
		session.action("Change "+label,func(): setter.call(next)))
	return number
func _transform_value(value: float, kind: String, axis: int) -> void:
	for id in session.selected:
		var item := session.document.component(id)
		if item==null or item.locked: continue
		if item.binding!=null: status.text="Move the armature or its parent. Detach before editing bound component rest transforms."; continue
		if kind=="Position": item.transform.origin[axis]=value
		else:
			var affine := KiwiModelDocument.transform_values(item.transform)
			var angles: Vector3=affine.rotation*PI/180.; var scale: Vector3=affine.scale
			if kind=="Rotation": angles[axis]=deg_to_rad(value)
			else: scale[axis]=value if absf(value)>.0001 else .0001
			item.transform.basis=Basis.from_euler(angles)*Basis.from_scale(scale)*affine.model_basis_residual
func _parameter_value(value: float, id: String, field: String, dimensions: bool) -> void:
	var item := session.document.component(id)
	if item==null or item.skin_mesh!=null or item.binding!=null: return
	if dimensions and field in ["width","height","depth"]:
		var size: Vector3=item.parameters.get("size",Vector3.ONE); size[["width","height","depth"].find(field)]=value; item.parameters.size=size
	else: item.parameters[field]=value
	item.mesh=KiwiModelPrimitives.create(item.generator,item.parameters)
	# Regeneration changes topology IDs. Never keep an old vertex/edge/face
	# selection indexing a now smaller primitive; Undo restores the old selection.
	if session.primary()==item: session.elements=PackedInt32Array()

func _rebuild_tree() -> void:
	hierarchy.session=session
	hierarchy.clear(); var root := hierarchy.create_item(); var items := {}
	for item in session.document.components:
		var row := hierarchy.create_item(root); row.set_text(0,item.title); row.set_metadata(0,item.id); row.set_editable(0,true)
		row.set_icon(0,preload("res://resources/Images/ActorIcons/SkeletonRig.svg") if item.is_skeleton else (preload("res://resources/Images/ActorIcons/BasicMesh.svg") if item.mesh!=null else preload("res://resources/Images/ActorIcons/Point3D.svg"))); row.set_icon_max_width(0,18)
		row.set_text(1,"●" if item.visible else "○"); row.set_tooltip_text(1,"Hide / show component")
		row.set_text(2,"L" if item.locked else "·"); row.set_selectable(1,false); row.set_selectable(2,false); items[item.id]=row
		if not item.visible: row.set_custom_color(0,Color("667f90"))
		if session.selected.has(item.id): row.select(0)
	for item in session.document.components:
		if items.has(item.parent_id) and not session.document.is_descendant(item.parent_id,item.id):
			var row: TreeItem=items[item.id]; root.remove_child(row); items[item.parent_id].add_child(row)
	# Text columns remain clickable even when no suitable bundled icon exists.
	if not hierarchy.gui_input.is_connected(_tree_input): hierarchy.gui_input.connect(_tree_input)
func _tree_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT: return
	var row := hierarchy.get_item_at_position(event.position)
	if row==null: return
	var column := hierarchy.get_column_at_position(event.position); var id := str(row.get_metadata(0)); var item := session.document.component(id)
	if column in [1,2] and item!=null:
		session.action("Toggle component state",func():
			if column==1: item.visible=not item.visible
			else: item.locked=not item.locked)
func _tree_button(row: TreeItem, _column: int, _id: int, _mouse_button: int) -> void:
	var item := session.document.component(str(row.get_metadata(0)))
	if item!=null: session.action("Toggle visibility",func(): item.visible=not item.visible)
func _tree_selected(_row: TreeItem, _column: int, _selected: bool) -> void:
	if _syncing: return
	var primary: String=str(_row.get_metadata(0)) if _selected else (session.selected.back() if not session.selected.is_empty() else "")
	session.selected.clear(); var current := hierarchy.get_next_selected(null)
	while current!=null:
		session.selected.append(str(current.get_metadata(0))); current=hierarchy.get_next_selected(current)
	if session.selected.has(primary): session.selected.erase(primary); session.selected.append(primary)
	if canvas.rig_tool!=null and session.primary()!=null and session.primary().is_skeleton: canvas.rig_tool.editor.rig_id=session.primary().id
	session.elements=PackedInt32Array(); session.changed.emit()
func _rename() -> void:
	var row := hierarchy.get_edited(); var item := session.document.component(str(row.get_metadata(0)))
	if item!=null: session.action("Rename component",func(): item.title=row.get_text(0))

func _build_modifiers(item: KiwiModelComponent) -> void:
	if item.mesh==null: _label(_modifiers,"Select a mesh component"); return
	if item.skin_mesh!=null or item.binding!=null: _label(_modifiers,"Rigged geometry is preserved.\nDetach before changing modifiers."); return
	_button(_modifiers,"＋ Add modifier",func(): _choice_menu("MODIFIERS",KiwiModelModifiers.TYPES,func(kind:String): session.action("Add "+kind,func(): item.modifiers.append({"type":kind,"enabled":true,"amount":.1 if kind in ["Bevel","Solidify","Smooth"] else 1.,"axis":0,"count":3}))))
	for i in item.modifiers.size():
		var settings := item.modifiers[i]; var row := HBoxContainer.new(); _modifiers.add_child(row)
		var toggle := CheckButton.new(); toggle.text=str(settings.type); toggle.button_pressed=settings.get("enabled",true); toggle.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(toggle)
		toggle.toggled.connect(func(enabled:bool): session.action("Enable modifier",func(): session.primary().modifiers[i].enabled=enabled))
		_button(row,"↑",func():
			if i>0: session.action("Reorder modifiers",func(): var list:=session.primary().modifiers; var entry:Dictionary=list.pop_at(i); list.insert(i-1,entry)))
		_button(row,"×",func(): session.action("Remove modifier",func(): session.primary().modifiers.remove_at(i)))
		if settings.type in ["Mirror","Linear array","Radial array","Twist","Taper"]:
			var axis := OptionButton.new()
			for name in ["X axis","Y axis","Z axis"]: axis.add_item(name)
			axis.select(settings.get("axis",0)); _modifiers.add_child(axis); axis.item_selected.connect(func(index:int): session.action("Modifier axis",func(): session.primary().modifiers[i].axis=index))
		if settings.type=="Mirror":
			var bisect := CheckButton.new(); bisect.text="Keep half + mirror"; bisect.button_pressed=settings.get("bisect",true); bisect.tooltip_text="Edit the retained half; Apply the modifier to edit the full result."; _modifiers.add_child(bisect)
			bisect.toggled.connect(func(enabled:bool): session.action("Mirror bisection",func(): session.primary().modifiers[i].bisect=enabled))
		if settings.type not in ["Mirror","Subdivision"]: _number(_modifiers,"Width" if settings.type=="Bevel" else "Amount",float(settings.get("amount",1.)),.0001 if settings.type in ["Bevel","Smooth"] else -360,1 if settings.type=="Smooth" else 360,.01,func(value:float): session.primary().modifiers[i].amount=value)
		if settings.type in ["Linear array","Radial array","Subdivision","Smooth"]: _number(_modifiers,"Count",settings.get("count",3),1,3 if settings.type=="Subdivision" else (8 if settings.type=="Smooth" else 64),1,func(value:float): session.primary().modifiers[i].count=int(value))
		_button(_modifiers,"Apply through here",func():
			session.action("Apply modifier",func():
				var current := session.primary()
				for j in i+1: current.mesh=KiwiModelModifiers.apply(current.mesh,current.modifiers[j]) if current.modifiers[j].get("enabled",true) else current.mesh
				current.modifiers=current.modifiers.slice(i+1); current.generator=""))
func _build_surfaces(item: KiwiModelComponent) -> void:
	if item.mesh==null: return
	var shading := CheckButton.new(); shading.text="Smooth normals"; shading.button_pressed=item.mesh.smooth; _surfaces.add_child(shading); shading.toggled.connect(func(enabled:bool): session.action("Shading",func(): session.primary().mesh.smooth=enabled))
	_button(_surfaces,"＋ Material",func(): session.action("Add material",func():
		var material := StandardMaterial3D.new(); material.albedo_color=Color("91bfc8"); material.roughness=.55; session.primary().surface_materials.append(material)))
	for i in item.surface_materials.size():
		var row := HBoxContainer.new(); _surfaces.add_child(row); _label(row,"Material "+str(i+1))
		var color := ColorPickerButton.new(); color.custom_minimum_size=Vector2(50,26); row.add_child(color)
		var material := item.surface_materials[i] as BaseMaterial3D
		color.color=material.albedo_color if material!=null else Color.WHITE
		color.disabled=material==null; color.tooltip_text="Albedo tint" if material!=null else "Shader material — edit its shader parameters in the shader workspace"
		color.popup_closed.connect(func(): _property_gesture=false; session.commit("Material color"))
		color.pressed.connect(func(): session.begin(); _property_gesture=true)
		color.color_changed.connect(func(value:Color):
			var current := session.primary().surface_materials[i] as BaseMaterial3D
			if current==null: return
			var new_material := current.duplicate() as BaseMaterial3D; new_material.albedo_color=value
			session.primary().surface_materials[i]=new_material; session.changed.emit())
		_button(row,"Assign",func(): session.action("Assign material",func():
			var current := session.primary()
			for f in current.mesh.faces.size():
				if session.mode!="Face" or session.elements.has(f): current.mesh.materials[f]=i))
	_button(_surfaces,"Load Material…",_load_material)
func _load_material() -> void:
	var property := ActorProperty.new(); property.options={"extensions":["tres","res"],"native_resource_types":["Material"]}
	var picked := await ActorProjectFilePicker.pick(self,property,"Choose Material")
	if picked.is_empty() or picked==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var material := ResourceLoader.load(picked) as Material
	if material!=null: session.action("Load material",func(): session.primary().surface_materials.append(material))

func create_menu() -> void:
	var choices := KiwiModelPrimitives.SHAPES.duplicate(); choices.append_array(["Draw Box","Draw Cylinder"])
	_choice_menu("CREATE GEOMETRY",choices,func(kind:String):
		if kind.begins_with("Draw "): canvas.start_creation(kind.trim_prefix("Draw "))
		else: session.add(kind,{},canvas.target)
		canvas.request_sync(); canvas.grab_focus())
func _deform_menu() -> void:
	_choice_menu("DEFORM BRUSH",["Grab","Inflate","Smooth","Flatten","Pinch","Off"],func(kind:String): canvas.sculpt="" if kind=="Off" else kind; _refresh(); canvas.grab_focus())
func _choice_menu(heading: String, choices: Array, chosen: Callable) -> void:
	var popup := PopupPanel.new(); var style := StyleBoxFlat.new(); style.bg_color=Color("13212d"); style.border_color=Color("4b8e83"); style.set_border_width_all(1); style.set_corner_radius_all(10); style.content_margin_left=12; style.content_margin_right=12; style.content_margin_top=12; style.content_margin_bottom=12
	popup.add_theme_stylebox_override("panel",style); add_child(popup)
	var column := VBoxContainer.new(); column.custom_minimum_size=Vector2(340,0); popup.add_child(column); _label(column,heading)
	var search := LineEdit.new(); search.placeholder_text="Search…"; column.add_child(search)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size.y=330; column.add_child(scroll); var list := VBoxContainer.new(); list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	var rebuild := func(query:String):
		_clear(list)
		for label: String in choices:
			if _matches(query,label): _button(list,label,func(): popup.hide(); chosen.call(label))
	search.text_changed.connect(rebuild); rebuild.call(""); popup.popup_hide.connect(popup.queue_free); popup.popup_centered(Vector2i(360,420)); search.grab_focus()
static func _matches(query: String, label: String) -> bool:
	var at := 0; var text := label.to_lower()
	for letter in query.to_lower():
		at=text.find(letter,at)
		if at<0: return false
		at+=1
	return true
func command_search() -> void:
	var commands: Array=[]
	for name in _recent: commands.append(name)
	for name in OPERATIONS:
		if not commands.has(name): commands.append(name)
	for name in KiwiModelPrimitives.SHAPES: commands.append("Add "+name)
	commands.append_array(["Draw Box","Draw Cylinder"])
	commands.append_array(["Quick Rig","Draw Bones","Rig Pose","Weight Paint","Bind Rig","Rig Templates"])
	for name in KiwiModelModifiers.TYPES: commands.append("Modifier: "+name)
	_choice_menu("MODELING COMMANDS",commands,run_command)

func run_command(command: String) -> void:
	if command=="Search": command_search(); return
	if command in ["Quick Rig","Draw Bones","Rig Pose","Weight Paint","Bind Rig","Rig Templates"]:
		match command:
			"Quick Rig": rig_ui.quick_rig()
			"Draw Bones": rig_ui.set_mode("Draw")
			"Rig Pose": rig_ui.set_mode("Pose")
			"Weight Paint": rig_ui.set_mode("Weight")
			"Bind Rig": rig_ui.bind_async(rig_ui.method)
			"Rig Templates": rig_ui.templates()
		return
	if command in ["Extrude","Extrude individual","Inset","Bevel","Subdivide","Weld","Smooth","Flip normals","Separate faces","Join meshes","Center origin","Repeat operation"] or command.begins_with("Boolean ") or command.begins_with("Modifier: "):
		for id in session.selected:
			if session.document.component(id).skin_mesh!=null or session.document.component(id).binding!=null: status.text="Rigged mesh topology is preserved. Detach in Rigging before changing geometry."; return
	_recent.erase(command); _recent.push_front(command); if _recent.size()>8: _recent.pop_back()
	if command.begins_with("Add "): session.add(command.trim_prefix("Add "),{},canvas.target)
	elif command.begins_with("Draw "): canvas.start_creation(command.trim_prefix("Draw "))
	elif command.begins_with("Modifier: "):
		if session.primary()!=null: session.action(command,func(): session.primary().modifiers.append({"type":command.trim_prefix("Modifier: "),"enabled":true,"amount":.2,"axis":0,"count":2}))
	elif command in ["Extrude","Extrude individual","Inset","Bevel","Weld"]: _operation_dialog(command)
	elif command in ["Subdivide","Smooth","Flip normals"]: status.text=session.edit_mesh(command,.3)
	elif command=="Duplicate": session.duplicate_selected()
	elif command=="Delete": status.text=session.delete_selected()
	elif command=="Parent": session.parent_selected()
	elif command=="Group": session.group_selected()
	elif command=="Unparent": session.parent_selected(true)
	elif command=="Join meshes": session.join_selected()
	elif command=="Separate faces": _separate()
	elif command=="Center origin": _center_origin()
	elif command=="Frame selected": canvas.frame()
	elif command=="Frame all": canvas.frame(true)
	elif command.begins_with("Boolean "): _boolean(command)
	elif command=="Repeat operation": status.text=session.edit_mesh(_last_geometry,_last_amount)
	elif command in ["Select all","Invert selection","Select connected","Grow selection","Shrink selection","Select similar normals","Select material"]: _selection(command)
	_refresh_pending=true; canvas.grab_focus()
func _operation_dialog(kind: String) -> void:
	var popup := PopupPanel.new(); popup.name="GeometryOperation"; add_child(popup); var fields := VBoxContainer.new(); fields.custom_minimum_size=Vector2(280,100); popup.add_child(fields)
	_label(fields,kind+" · live preview")
	var amount := DragNumber.new(); amount.name="Distance"; amount.min_value=-100 if kind.begins_with("Extrude") else .00001; amount.max_value=100; amount.step=.01; amount.value=.0001 if kind=="Weld" else .2; fields.add_child(amount)
	var before := session.snapshot(); var outcome := {"accepted":false}; _property_gesture=true
	var preview := func(value:float):
		session.restore(before); var error := session.edit_mesh(kind,value,true)
		if not error.is_empty(): status.text=error
	preview.call(amount.value)
	amount.value_changed.connect(preview); amount.preview_changed.connect(preview)
	var row := HBoxContainer.new(); fields.add_child(row)
	_button(row,"Cancel",popup.hide)
	_button(row,"Apply",func():
		outcome.accepted=true; session.restore(before); _last_geometry=kind; _last_amount=amount.value; status.text=session.edit_mesh(kind,amount.value); popup.hide())
	popup.popup_hide.connect(func():
		if not outcome.accepted: session.restore(before)
		_property_gesture=false; _refresh_pending=true
		popup.queue_free())
	popup.popup_centered(Vector2i(320,155))
func _selection(command: String) -> void:
	var item := session.primary()
	if session.mode=="Object":
		if command not in ["Select all","Invert selection"]: status.text="Switch to vertex, edge, or face selection (2–4) first."; return
		var old := session.selected.duplicate(); session.selected.clear()
		for other in session.document.components:
			if session.document.visible_component(other) and not other.locked and (command!="Invert selection" or not old.has(other.id)): session.selected.append(other.id)
	elif item!=null and item.mesh!=null:
		var mesh := item.mesh; var count := mesh.vertices.size() if session.mode=="Vertex" else (mesh.edges().size() if session.mode=="Edge" else mesh.faces.size())
		var old := session.elements.duplicate()
		if command in ["Select all","Invert selection"]:
			session.elements=PackedInt32Array()
			for i in count:
				if command=="Select all" or not old.has(i): session.elements.append(i)
		elif command in ["Select similar normals","Select material"] and session.mode=="Face" and not old.is_empty():
			for f in mesh.faces.size():
				if (mesh.normal(f).dot(mesh.normal(old[0]))>.98 if command=="Select similar normals" else mesh.materials[f]==mesh.materials[old[0]]) and not session.elements.has(f): session.elements.append(f)
		else: session.elements=Selection.expand(mesh,session.mode,old,command)
	session.changed.emit()
func _separate() -> void:
	var item := session.primary()
	if item==null or session.mode!="Face" or session.elements.is_empty(): status.text="Select faces to separate."; return
	session.action("Separate faces",func():
		var copy := item.copy_component(true); copy.title+=" separated"; copy.modifiers.clear(); copy.generator=""; var remove := PackedInt32Array()
		for f in item.mesh.faces.size():
			if not session.elements.has(f): remove.append(f)
		copy.mesh=KiwiModelGeometry.remove_faces(item.mesh,remove); item.mesh=KiwiModelGeometry.remove_faces(item.mesh,session.elements); item.generator=""
		session.document.components.append(copy); session.selected.assign([copy.id]); session.elements=PackedInt32Array())
func _center_origin() -> void:
	var item := session.primary()
	if item==null or item.mesh==null: return
	session.action("Center origin",func(): item.pivot=item.mesh.bounds().get_center())
func _boolean(command: String) -> void:
	if session.selected.size()!=2: status.text="Select the target, then the cutter. The last selected mesh is the cutter."; return
	var a := session.document.component(session.selected[0]); var b := session.primary()
	if a.mesh==null or b.mesh==null: return
	var first_mesh := KiwiModelModifiers.evaluate(a); var second_mesh := KiwiModelModifiers.evaluate(b)
	if first_mesh.faces.size()+second_mesh.faces.size()>2500: status.text="Boolean limited to 2,500 evaluated input faces for responsive editing."; return
	var operation_session := session; var operation_revision := session.revision
	status.text="Evaluating Boolean…"; var before := session.snapshot(); mouse_filter=Control.MOUSE_FILTER_STOP
	var operation := CSGShape3D.OPERATION_SUBTRACTION if command=="Boolean difference" else (CSGShape3D.OPERATION_UNION if command=="Boolean union" else CSGShape3D.OPERATION_INTERSECTION)
	var mesh := await KiwiModelImport.boolean(canvas.world,first_mesh,second_mesh,session.document.world_transform(a).affine_inverse()*session.document.world_transform(b),operation,a.surface_materials,b.surface_materials)
	if not is_inside_tree(): return
	if not is_visible_in_tree() or session!=operation_session or session.revision!=operation_revision: return
	if mesh==null or not mesh.validate().is_empty(): status.text="Boolean failed or produced an empty result; sources kept."; return
	session.restore(before); session.action(command,func():
		var target := session.document.component(a.id); target.mesh=mesh; target.surface_materials.assign(mesh.get_meta("boolean_materials",[])); mesh.remove_meta("boolean_materials"); target.generator=""; target.modifiers.clear(); session.document.component(b.id).visible=false; session.selected.assign([a.id]); session.elements=PackedInt32Array())
	status.text="Boolean baked to editable geometry. Cutter kept hidden."

func _view_command(index: int) -> void:
	match index:
		0: canvas.frame()
		1: canvas.frame(true)
		2: canvas.camera.projection=Camera3D.PROJECTION_ORTHOGONAL if canvas.camera.projection==Camera3D.PROJECTION_PERSPECTIVE else Camera3D.PROJECTION_PERSPECTIVE
		9: canvas.grid.visible=not canvas.grid.visible
		10: canvas.show_edges=not canvas.show_edges
		11: canvas.wireframe=not canvas.wireframe; canvas.request_sync()
		12: canvas.xray=not canvas.xray; canvas.request_sync()
		13: canvas.show_normals=not canvas.show_normals
		14: hierarchy.visible=not hierarchy.visible
		15: _inspector_tabs.visible=not _inspector_tabs.visible
		_: canvas.set_view(["Front","Back","Left","Right","Top","Bottom"][index-3])
	canvas.overlay.queue_redraw()
func open_source(value: Variant, state: Dictionary={}) -> void:
	if rig_ui!=null: rig_ui.cancel_job()
	if session.changed.is_connected(_changed): session.changed.disconnect(_changed)
	if session.changed.is_connected(canvas.request_sync): session.changed.disconnect(canvas.request_sync)
	if state.get("session") is KiwiModelSession:
		session=state.session
	else:
		session=KiwiModelSession.new(); session.document=KiwiModelImport.load_document(value); session.dirty=not value is String
		session.selected.assign(session.document.workspace_state.get("selected",[]))
		session.mode=str(session.document.workspace_state.get("mode","Object")); session.elements=session.document.workspace_state.get("elements",PackedInt32Array())
		if session.selected.is_empty() and not session.document.components.is_empty(): session.selected.assign([session.document.components[0].id])
	canvas.session=session
	canvas.rig_tool.editor.session=session
	var rig_state: Dictionary=state.get("rig",session.document.workspace_state.get("rig",{}))
	canvas.rig_tool.editor.enabled=rig_state.get("enabled",false); canvas.rig_tool.editor.rig_id=rig_state.get("id",""); canvas.rig_tool.editor.selected_bone=rig_state.get("bone",0); canvas.rig_tool.editor.mode=rig_state.get("mode","Edit")
	canvas.rig_tool.geometry_cache.clear(); canvas.rig_tool.heat_signature.clear()
	canvas.rig_tool.region.clear(); canvas.rig_tool.chain=null
	if not session.changed.is_connected(_changed): session.changed.connect(_changed)
	if not session.changed.is_connected(canvas.request_sync): session.changed.connect(canvas.request_sync)
	var native_path := ""
	var rejected := ""
	if value is String and value.get_extension() in ["tres","res"]:
		var candidate := ResourceLoader.load(value) as KiwiModelDocument
		if candidate!=null:
			var errors := candidate.validate()
			if errors.is_empty(): native_path=value
			else: rejected=errors[0]
	source=value; path=str(state.get("path",native_path))
	if value is String and native_path.is_empty() and session.document.components.is_empty(): status.text="No editable geometry found. GLB/GLTF work at runtime; other formats need a Godot-imported resource. Original file unchanged."
	if not rejected.is_empty() and not state.has("session"): path=""; status.text="Model rejected: "+rejected+". Original file unchanged; Save requires a new destination."
	canvas.restore_state(state.get("view",session.document.workspace_state.get("view",{}))); _refresh(); canvas.request_sync()
	var panels: Dictionary=state.get("panels",session.document.workspace_state.get("panels",{}))
	if _layout_ready: _restore_panels(panels)
	else: _pending_panels=panels
func capture_state() -> Dictionary:
	for number in find_children("*","SpinBox",true,false):
		if number is DragNumber and number._pressed: number.cancel_drag()
	canvas.cancel_all(); _property_gesture=false
	return {"session":session,"path":path,"view":canvas.capture_state(),"panels":_capture_panels(),"rig":_rig_state()}

func _exit_tree() -> void:
	if rig_ui!=null: rig_ui.cancel_job()

func _rig_state() -> Dictionary:
	var rig := canvas.rig_tool.editor
	return {"enabled":rig.enabled,"id":rig.rig_id,"bone":rig.selected_bone,"mode":rig.mode}
func open_dialog() -> void:
	var property := ActorProperty.new(); property.options={"extensions":["tres","res","mesh","glb","gltf","obj","fbx"],"raw_extensions":["glb","gltf","obj","fbx"],"native_resource_types":["KiwiModelDocument","Mesh","PackedScene"]}
	var picked := await ActorProjectFilePicker.pick(self,property,"Open editable model or import a mesh")
	if picked.is_empty() or picked==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var tabs := get_tree().get_first_node_in_group("actor_scene_tabs")
	if tabs!=null: tabs.open_model(picked)
func save() -> void:
	if path.is_empty(): await save_as()
	else: await save_to(path)
func save_as() -> void:
	var result := await ActorProjectResourceSaveDialog.pick(self,"Save editable 3D model",path.get_file().get_basename() if not path.is_empty() else "Model","tres",false,PackedStringArray(["tres","res"]),func(): return session.document.snapshot())
	if not result.get("cancelled",true): await save_to(str(result.path))
func save_to(destination: String) -> Error:
	canvas.rig_tool.finish(); canvas.finish_transform(); canvas.finish_extrusion(); session.document.workspace_state={"view":canvas.capture_state(),"panels":_capture_panels(),"selected":session.selected.duplicate(),"mode":session.mode,"elements":session.elements.duplicate(),"rig":_rig_state()}
	var errors := session.document.validate()
	if not errors.is_empty(): status.text="Save cancelled: "+errors[0]; return ERR_INVALID_DATA
	var saved_session := session; var saved_revision := session.revision; var saved := session.document.snapshot()
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		if session==saved_session:
			var bitmap := canvas.viewport.get_texture().get_image(); var factor := minf(240./bitmap.get_width(),180./bitmap.get_height())
			bitmap.resize(maxi(1,roundi(bitmap.get_width()*factor)),maxi(1,roundi(bitmap.get_height()*factor)),Image.INTERPOLATE_LANCZOS)
			# Store PNG bytes, not a GPU texture resource. Mesh-only loads must not
			# allocate thumbnails, and portable texture reloads can race RID setup.
			saved.preview=null; saved.preview_png=bitmap.save_png_to_buffer()
	var error := ResourceSaver.save(saved,destination)
	if error==OK:
		if saved_session.revision==saved_revision: saved_session.dirty=false
		if session==saved_session: path=destination; source=path; status.text="Saved "+path
		model_saved.emit(destination,saved_session)
		if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()
	else: status.text="Save failed (%d)."%error
	_refresh_pending=true; return error
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	var focused := get_viewport().gui_get_focus_owner()
	if focused==null or not is_ancestor_of(focused): return
	if _property_gesture: return
	if event.ctrl_pressed and event.keycode==KEY_S:
		if event.shift_pressed: save_as()
		else: save()
		get_viewport().set_input_as_handled()
	elif not focused is LineEdit and not focused is TextEdit:
		if event.ctrl_pressed and event.keycode==KEY_Z: session.redo() if event.shift_pressed else session.undo()
		elif event.ctrl_pressed and event.keycode==KEY_Y: session.redo()
		elif event.keycode in [KEY_DELETE,KEY_BACKSPACE]: status.text=session.delete_selected()
		else: return
		get_viewport().set_input_as_handled()
