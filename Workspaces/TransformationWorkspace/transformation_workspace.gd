class_name KiwiTransformationWorkspace
extends Control
signal document_changed
signal asset_saved(path: String, saved_session: KiwiTransformationSession)
var session := KiwiTransformationSession.new()
var path := ""
var canvas := KiwiTransformationCanvas.new()
var edit_renderer := KiwiImageRenderer.new()
var animation_renderer := KiwiTransformationRenderer.new()
var timeline := KiwiTransformationTimeline.new()
var components := KiwiTransformationComponents.new()
var properties := VBoxContainer.new()
var key_fields := HBoxContainer.new()
var header := Label.new()
var mode_label := Label.new()
var status := Label.new()
var play_button := Button.new()
var time_control: DragNumber
var tool_context := HBoxContainer.new()
var tools: Dictionary={}
var previewing := false
var playing := false
var loop := true
var onion := false
var shape_kind := "rectangle"
var edit_document := KiwiImageDocument.new()
var _render_pending := true
var _ui_pending := true
var _syncing := false
var _gesture := false
var _number_drag := false
var _component_panel := VBoxContainer.new()
var _property_panel := ScrollContainer.new()
var _split: HSplitContainer
var _right_split := HSplitContainer.new()
var _before_art: Dictionary={}
var _state_name: LineEdit
func _draw() -> void: draw_rect(Rect2(Vector2.ZERO,size),Color("0f1c26"))
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _theme(); add_child(edit_renderer); add_child(animation_renderer)
	animation_renderer.cache.prepared.connect(func(): _render_pending=true)
	_build()
	canvas.gesture_started.connect(_begin_gesture); canvas.gesture_changed.connect(_preview_gesture); canvas.gesture_finished.connect(_finish_gesture); canvas.gesture_cancelled.connect(_cancel_gesture)
	canvas.selection_changed.connect(func(): session.selected.assign(canvas.selected); _ui_pending=true)
	canvas.color_sampled.connect(func(value: Color): canvas.color=value; _ui_pending=true)
	canvas.create_requested.connect(_shape_created)
	canvas.pivot_changed.connect(func(value: Vector2):
		if session.active_state()!=null: session.active_state().pivot=value; canvas.pivot_uv=value)
	canvas.reveal_point.connect(_add_reveal_point)
	canvas.hint_changed.connect(func(value: String): if not value.is_empty(): status.text=value)
	canvas.brush_size_changed.connect(func(_value: float): _ui_pending=true)
	canvas.threshold_changed.connect(func(_value: float): _ui_pending=true)
	canvas.duplicate_requested.connect(func(): session.duplicate_components(); _sync_edit_document())
	canvas.files_dropped.connect(func(paths: PackedStringArray,_at: Vector2): if not paths.is_empty(): import_image(paths[0]))
	timeline.seek.connect(seek); timeline.selection_changed.connect(_key_selected); timeline.gesture_finished.connect(func(): _ui_pending=true; _render_pending=true)
	session.changed.connect(_changed); session.selected.assign([session.document.components[0].id]); _sync_edit_document(); _refresh(); canvas.fit.call_deferred()
func _theme() -> void:
	theme=Theme.new(); theme.default_font_size=13
	for data in [["normal","172b39","355268"],["hover","24483f","72ddc5"],["pressed","286153","7aebcc"],["focus","1a303f","80e5cb"]]:
		var box := StyleBoxFlat.new(); box.bg_color=Color(data[1]); box.border_color=Color(data[2]); box.set_border_width_all(1); box.set_corner_radius_all(6); box.content_margin_left=9; box.content_margin_right=9; box.content_margin_top=5; box.content_margin_bottom=5
		for type in ["Button","OptionButton","LineEdit","MenuButton"]: theme.set_stylebox(data[0],type,box)
	var panel := StyleBoxFlat.new(); panel.bg_color=Color("12232f"); panel.border_color=Color("304c5e"); panel.set_border_width_all(1); panel.set_corner_radius_all(7); theme.set_stylebox("panel","Tree",panel)
func button(parent: Node, text: String, action: Callable, hint: String="") -> Button:
	var control := Button.new(); control.text=text; control.tooltip_text=hint; control.custom_minimum_size.y=28; parent.add_child(control); control.pressed.connect(action); return control
func label(parent: Node, text: String) -> Label:
	var control := Label.new(); control.text=text; control.add_theme_color_override("font_color",Color("80dcca")); parent.add_child(control); return control
func clear(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()
func style_popup(popup: PopupPanel) -> void:
	var box := StyleBoxFlat.new(); box.bg_color=Color("142633"); box.border_color=Color("52796e"); box.set_border_width_all(1); box.set_corner_radius_all(8); box.set_content_margin_all(12); box.shadow_color=Color(0,0,0,.45); box.shadow_size=10; popup.add_theme_stylebox_override("panel",box)
func choice(parent: Node, options: Array, current: String, callback: Callable) -> OptionButton:
	var control := OptionButton.new(); control.clip_text=true; control.custom_minimum_size.x=100; control.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for title: String in options: control.add_item(title)
	control.select(maxi(0,options.find(current))); parent.add_child(control); control.item_selected.connect(func(index: int): callback.call(control.get_item_text(index))); return control
func number(parent: Node, caption: String, value: float, minimum: float, maximum: float, step: float, setter: Callable, state_edit: bool=false, undoable: bool=true) -> DragNumber:
	var column := VBoxContainer.new(); column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; parent.add_child(column); label(column,caption).add_theme_font_size_override("font_size",10)
	var input := DragNumber.new(); input.min_value=minimum; input.max_value=maximum; input.step=step; input.value=value; input.editable=not (state_edit and (previewing or (session.primary()!=null and session.primary().locked))); column.add_child(input)
	var last_valid := {"value":value}
	input.interaction_started.connect(func():
		finish_pending()
		if undoable: session.begin()
		input.set_meta("transformation_drag",true); _number_drag=true)
	input.interaction_ended.connect(func():
		if not input.get_meta("transformation_drag",false): return
		input.set_meta("transformation_drag",false)
		_number_drag=false
		if undoable: _finish_number_transaction.call_deferred(session))
	input.preview_changed.connect(func(next: float): setter.call(next); _render_pending=true)
	input.drag_committed.connect(func(_next: float):
		_number_drag=false
		if undoable:
			if _commit_number(caption,state_edit): last_valid.value=input.value
			else: input.set_value_no_signal(last_valid.value))
	input.drag_cancelled.connect(func():
		_number_drag=false
		if undoable: session.cancel()
		else: setter.call(input.value); _render_pending=true)
	input.value_changed.connect(func(next: float):
		if _syncing or input.dragging: return
		if undoable: session.begin()
		setter.call(next); _render_pending=true
		if undoable:
			if _commit_number(caption,state_edit): last_valid.value=input.value
			else: input.set_value_no_signal(last_valid.value))
	return input
func _finish_number_transaction(owner_session: KiwiTransformationSession) -> void:
	# DragNumber intentionally emits no commit when dragged back to its origin.
	# Release that no-op transaction instead of leaving the inspector suspended.
	if session==owner_session and not _gesture and not _number_drag and timeline.drag.is_empty() and not session.pending.is_empty(): session.cancel()
func _commit_number(caption: String, state_edit: bool) -> bool:
	var errors := session.document.validate()
	if not errors.is_empty(): session.cancel(); status.text=errors[0]; return false
	if state_edit: touch_states()
	session.commit("Change "+caption)
	return true
func _build() -> void:
	var column := VBoxContainer.new(); column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); column.add_theme_constant_override("separation",5); add_child(column)
	var row := HBoxContainer.new(); column.add_child(row); header.text="TRANSFORMATION IMAGE 2D"; header.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_theme_color_override("font_color",Color("7de3c9")); row.add_child(header)
	button(row,"Open…",open_dialog); button(row,"Save",save,"Ctrl+S"); button(row,"Save As…",save_as,"Ctrl+Shift+S"); button(row,"↶",func(): finish_pending(); session.undo(),"Undo · Ctrl+Z"); button(row,"↷",func(): finish_pending(); session.redo(),"Redo · Ctrl+Shift+Z")
	button(row,"Examples…",func(): menu("WORKED EXAMPLES",KiwiTransformationExamples.NAMES,open_example))
	var view := MenuButton.new(); view.text="View ▾"; row.add_child(view)
	for title in ["Fit canvas","Components panel","Properties panel","Onion skin","Grid","Canvas size…"]: view.get_popup().add_item(title)
	view.get_popup().id_pressed.connect(func(index: int):
		match index:
			0: canvas.fit()
			1: _component_panel.visible=not _component_panel.visible
			2: _property_panel.visible=not _property_panel.visible
			3: onion=not onion; _render_pending=true
			4: canvas.show_grid=not canvas.show_grid; canvas.queue_redraw()
			5: canvas_size_dialog()
	)
	var toolbar := HBoxContainer.new(); column.add_child(toolbar)
	for entry in [["move","↖ Move"],["brush","✎ Draw"],["eraser","⌫ Erase"],["fill","◩ Fill"],["picker","◉ Pick"],["shape","▣ Shape"],["pixel_select","◌ Pixels"],["pivot","⊙ Pivot"]]:
		var control := button(toolbar,entry[1],set_tool.bind(entry[0])); control.toggle_mode=true; tools[entry[0]]=control
	toolbar.add_child(tool_context); tool_context.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var main := HSplitContainer.new(); main.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(main); _split=main; main.split_offset=180
	_component_panel.custom_minimum_size.x=150; main.add_child(_component_panel)
	var actions := HBoxContainer.new(); _component_panel.add_child(actions); label(actions,"COMPONENTS").size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(actions,"＋",func(): edit_mode(); session.add_component(),"Add drawing component"); button(actions,"⋯",component_menu)
	components.session=session; components.hide_root=true; components.columns=3; components.select_mode=Tree.SELECT_MULTI; components.allow_reselect=true; components.size_flags_vertical=Control.SIZE_EXPAND_FILL
	for index in [1,2]: components.set_column_expand(index,false); components.set_column_custom_minimum_width(index,24)
	_component_panel.add_child(components); components.multi_selected.connect(_tree_selected); components.item_edited.connect(_rename_component); components.button_clicked.connect(_component_button); components.reorder_requested.connect(func(id: String,index: int): session.reorder(id,index))
	_right_split.size_flags_horizontal=Control.SIZE_EXPAND_FILL; main.add_child(_right_split); _right_split.add_child(canvas); canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL; canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_property_panel.custom_minimum_size.x=235; _property_panel.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; _right_split.add_child(_property_panel); _property_panel.add_child(properties); properties.size_flags_horizontal=Control.SIZE_EXPAND_FILL; properties.add_theme_constant_override("separation",8)
	var playback := HBoxContainer.new(); column.add_child(playback)
	play_button.text="▶"; playback.add_child(play_button); play_button.pressed.connect(toggle_play)
	time_control=number(playback,"PLAYHEAD (s)",0,0,86400,.01,func(value: float): seek(value),false,false)
	time_control.get_parent().custom_minimum_size.x=120; time_control.get_parent().size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	button(playback,"↺",func(): playing=false; seek(0.))
	var looping := CheckButton.new(); looping.text="Loop"; looping.button_pressed=loop; playback.add_child(looping); looping.toggled.connect(func(value: bool): loop=value)
	button(playback,"◆ Insert state",func(): finish_pending(); session.insert_key(),"Insert the chosen reusable state at the playhead · I")
	button(playback,"Edit state",edit_key_state,"Edit the selected key's reusable definition, not its timing")
	mode_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; playback.add_child(mode_label)
	button(playback,"Duration…",duration_dialog)
	column.add_child(timeline); timeline.session=session
	var key_scroll := ScrollContainer.new(); key_scroll.custom_minimum_size.y=55; key_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; column.add_child(key_scroll); key_scroll.add_child(key_fields)
	status.custom_minimum_size.y=21; status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; column.add_child(status)
	resized.connect(func(): if size.x<1050: _component_panel.hide())
	_right_split.split_offset=1000
func _changed() -> void:
	_render_pending=true; _ui_pending=true; document_changed.emit()
func _process(delta: float) -> void:
	edit_renderer.set_enabled(is_visible_in_tree() and not previewing)
	animation_renderer.viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if is_visible_in_tree() and previewing else SubViewport.UPDATE_DISABLED
	if not is_visible_in_tree(): playing=false; return
	if playing:
		session.playhead+=delta
		if session.playhead>session.document.duration:
			if loop: session.playhead=fposmod(session.playhead,session.document.duration)
			else: session.playhead=session.document.duration; playing=false
		_render_pending=true
	if _render_pending:
		_render_pending=false
		if previewing:
			animation_renderer.sync(session,session.playhead); canvas.preview=animation_renderer.texture()
		else:
			if not _gesture: _sync_edit_document()
			if _gesture and canvas._drag.begins_with("resize"): edit_renderer.sync_transforms(edit_document)
			else: edit_renderer.sync(edit_document)
			canvas.preview=edit_renderer.texture()
		canvas.previewing=previewing; canvas.queue_redraw(); timeline.queue_redraw(); time_control.set_value_no_signal(session.playhead)
		play_button.text="Ⅱ" if playing else "▶"
		mode_label.text="ANIMATION PREVIEW" if previewing else ("EDIT STATE · "+session.active_state().title if session.active_state()!=null else "EDIT STATE")
		if previewing: status.text=animation_renderer.status if not animation_renderer.status.is_empty() else "Preview · state artwork is unchanged · Edit state to continue drawing"
	if _ui_pending and not _gesture and not _number_drag and timeline.drag.is_empty(): _ui_pending=false; _refresh()
func _sync_edit_document() -> void:
	edit_document=KiwiImageDocument.new(); edit_document.canvas_size=session.document.canvas_size
	for item in session.document.components:
		var state := session.active_state(item)
		if state==null: continue
		var art := state.artwork.copy_layer(); art.label=item.title; art.visible=art.visible and item.visible; art.locked=item.locked; edit_document.layers.append(art)
	canvas.document=edit_document; canvas.selected.assign(session.selected); canvas.preview_screen_space=false; canvas.pivot_uv=session.active_state().pivot if session.active_state()!=null else Vector2(.5,.5)
	for property in session.pixel_reference: edit_document.set(property,session.pixel_reference[property])
	if canvas.selection!=session.pixel_mask:
		canvas.selection=session.pixel_mask; canvas.selection_texture=ImageTexture.create_from_image(canvas.selection) if canvas.selection!=null else null
	if session.pixel_mask!=null and not session.pixel_reference.is_empty(): canvas.sync_pixel_selection()
	canvas.onion=null
	if onion and session.primary()!=null:
		var item := session.primary(); var state := session.active_state(); var index := item.states.find(state)
		if index>0: canvas.onion=item.states[index-1].artwork
func _begin_gesture() -> void:
	if previewing: return
	session.begin(); _gesture=true; _before_art={}
	for id in canvas.selected:
		var item := session.document.component(id)
		if item!=null: _before_art[id]=session.active_state(item).artwork.copy_layer()
func _capture_art() -> void:
	for id in canvas.selected:
		var item := session.document.component(id); var art := canvas.document.layer_for_id(id)
		if item==null or art==null or item.locked: continue
		var state := session.active_state(item); var visible := state.artwork.visible; state.artwork=art.copy_layer(); state.artwork.visible=visible; state.artwork.locked=false
func _preview_gesture() -> void: _capture_art(); session.pixel_mask=canvas.selection; _render_pending=true
func _finish_gesture() -> void:
	if not _gesture: return
	_capture_art(); session.pixel_mask=canvas.selection
	for property in ["pixel_selection","pixel_selection_owner","pixel_selection_reference","pixel_selection_reference_world"]: session.pixel_reference[property]=canvas.document.get(property)
	touch_states(); _gesture=false; session.commit("Edit component state"); _before_art.clear()
func _cancel_gesture() -> void: _gesture=false; session.cancel(); _before_art.clear(); _render_pending=true
func touch_states() -> void:
	for id in session.selected:
		var item := session.document.component(id)
		if item!=null: session.active_state(item).revision+=1
func finish_pending() -> void:
	canvas.confirm_stroke()
	if not canvas._drag.is_empty() and canvas._drag!="pan": canvas._finish(canvas._last)
	if _gesture: _finish_gesture()
func edit_mode() -> void:
	playing=false; previewing=false; canvas.previewing=false; _render_pending=true; _ui_pending=true
func set_tool(value: String) -> void:
	finish_pending(); edit_mode(); canvas.tool=value; canvas.pixel_mode="brush"; canvas.paint_new_layer=false; _ui_pending=true; canvas.grab_focus()
	if value=="pixel_select":
		canvas.pixel_source=await edit_renderer.flattened()
		canvas.pixel_domain=Rect2i(Vector2i.ZERO,session.document.canvas_size)
func seek(value: float) -> void:
	finish_pending(); previewing=true; canvas.previewing=true; session.playhead=clampf(value,0,session.document.duration); _render_pending=true; _ui_pending=true
func toggle_play() -> void:
	finish_pending(); previewing=true; canvas.previewing=true; playing=not playing
	if playing and session.playhead>=session.document.duration: session.playhead=0.
	_render_pending=true; _ui_pending=true
func _key_selected() -> void:
	playing=false; previewing=true; var selected := selected_key()
	if not selected.is_empty(): session.playhead=selected.key.time
	_render_pending=true; _ui_pending=true
func selected_key() -> Dictionary:
	for item in session.document.components:
		for key in item.keys:
			if session.selected_keys.has(key.id): return {"component":item,"key":key}
	return {}
func edit_key_state() -> void:
	var selected := selected_key()
	if not selected.is_empty(): session.selected.assign([selected.component.id]); session.edit_states[selected.component.id]=selected.key.state_id
	edit_mode()
func _refresh() -> void:
	_syncing=true; header.text="TRANSFORMATION 2D / "+(path.get_file() if not path.is_empty() else "Untitled")+(" •" if session.dirty else "")
	for id in tools: tools[id].set_pressed_no_signal(canvas.tool==id and not previewing)
	_refresh_components(); _refresh_properties(); _refresh_tools(); _refresh_keys(); _syncing=false
func _refresh_components() -> void:
	components.clear(); var root := components.create_item()
	for i in range(session.document.components.size()-1,-1,-1):
		var item := session.document.components[i]; var row := components.create_item(root); row.set_text(0,item.title); row.set_metadata(0,item.id); row.set_editable(0,true); row.set_icon(0,session.active_state(item).artwork.texture); row.set_icon_max_width(0,30)
		row.add_button(1,icon("eye",item.visible),0,false,"Show / hide component"); row.add_button(2,icon("lock",item.locked),1,false,"Lock / unlock component")
		if session.selected.has(item.id): row.select(0)
func icon(kind: String, active: bool) -> Texture2D:
	var image := Image.create(20,20,false,Image.FORMAT_RGBA8); image.fill(Color(0,0,0,0)); var c := Color("78dfc5") if active else Color("526877")
	if kind=="eye":
		for x in range(2,18):
			var y := roundi(4.+5.*sin(float(x-2)/15.*PI)); image.set_pixel(x,y,c); image.set_pixel(x,20-y,c)
		image.fill_rect(Rect2i(9,8,3,5),c)
	else: image.fill_rect(Rect2i(5,8,11,10),c); image.fill_rect(Rect2i(7,3,7,6),c)
	return ImageTexture.create_from_image(image)
func _tree_selected(row: TreeItem,_column: int,selected: bool) -> void:
	if _syncing: return
	var id := str(row.get_metadata(0))
	if selected:
		session.selected.erase(id); session.selected.append(id)
	else: session.selected.erase(id)
	canvas.selected.assign(session.selected); _ui_pending=true; _render_pending=true
func _rename_component() -> void:
	var row := components.get_edited(); var item := session.document.component(str(row.get_metadata(0))); var value := row.get_text(0).strip_edges()
	if item!=null and not item.locked and not value.is_empty(): session.action("Rename component",func(): item.title=value)
func _component_button(row: TreeItem,_column: int,id: int,_mouse: int) -> void:
	var item := session.document.component(str(row.get_metadata(0)))
	if id==0: session.action("Component visibility",func(): item.visible=not item.visible)
	else: session.action("Component lock",func(): item.locked=not item.locked)
func _refresh_properties() -> void:
	clear(properties); var item := session.primary(); var state := session.active_state()
	if item==null or state==null: return
	label(properties,"STATE DEFINITION" if not previewing else "STATE · CHOOSE TO EDIT")
	var picker := OptionButton.new(); picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL; picker.clip_text=true; picker.add_theme_constant_override("icon_max_width",36)
	for value in item.states: picker.add_icon_item(value.artwork.texture,value.title); picker.get_popup().set_item_icon_max_width(picker.item_count-1,24)
	picker.select(item.states.find(state)); properties.add_child(picker); picker.item_selected.connect(func(index: int): finish_pending(); session.edit_states[item.id]=item.states[index].id; session.pixel_mask=null; session.pixel_reference.clear(); canvas.selection=null; canvas.selection_texture=null; edit_mode())
	var row := HBoxContainer.new(); properties.add_child(row); button(row,"＋ State",func(): finish_pending(); edit_mode(); session.add_state(),"Create a new state from this drawing; later painting is independent"); button(row,"＋ Blank",func(): finish_pending(); edit_mode(); session.add_state(true)); button(row,"⋯",state_menu)
	var name_input := LineEdit.new(); _state_name=name_input; name_input.text=state.title; name_input.placeholder_text="State name"; name_input.editable=not item.locked; properties.add_child(name_input); name_input.text_submitted.connect(func(value: String): if not item.locked and not value.strip_edges().is_empty(): session.action("Rename state",func(): state.title=value.strip_edges()))
	for data in [["Position",state.artwork.position],["Scale",state.artwork.dimensions/item.base_size],["Pivot",state.pivot]]:
		row=HBoxContainer.new(); properties.add_child(row); var kind: String=data[0]; var vector: Vector2=data[1]
		for axis in 2:
			number(row,kind+" "+["X","Y"][axis],vector[axis],.01 if kind=="Scale" else (0. if kind=="Pivot" else -100000.),64. if kind=="Scale" else (1. if kind=="Pivot" else 100000.),.01,func(value: float):
				if kind=="Position": state.artwork.position[axis]=value
				elif kind=="Scale": state.artwork.dimensions[axis]=item.base_size[axis]*value
				else: state.pivot[axis]=value; canvas.pivot_uv=state.pivot,true)
	row=HBoxContainer.new(); properties.add_child(row)
	number(row,"Rotation °",rad_to_deg(state.artwork.rotation),-36000,36000,.1,func(value: float): state.artwork.rotation=deg_to_rad(value),true)
	number(row,"Opacity",state.artwork.opacity,0,1,.01,func(value: float): state.artwork.opacity=value,true)
	var visible := CheckButton.new(); visible.text="State visible"; visible.button_pressed=state.artwork.visible; properties.add_child(visible); visible.disabled=item.locked; visible.toggled.connect(func(value: bool): session.action("State visibility",func(): state.artwork.visible=value))
	button(properties,"Import image into this state…",import_dialog)
	button(properties,"Reset transform",func(): if not item.locked: session.action("Reset state transform",func(): state.artwork.position=Vector2.ZERO; state.artwork.rotation=0; state.artwork.dimensions=item.base_size; state.artwork.opacity=1.; state.artwork.visible=true; state.pivot=Vector2(.5,.5)))
func _refresh_tools() -> void:
	clear(tool_context)
	if canvas.tool in ["brush","eraser","fill","shape"]:
		var color := ColorPickerButton.new(); color.color=canvas.color; color.custom_minimum_size=Vector2(42,28); tool_context.add_child(color); color.color_changed.connect(func(value: Color): canvas.color=value)
	if canvas.tool in ["brush","eraser"]:
		number(tool_context,"Size · Shift+wheel",canvas.brush_size,1,500,1,func(value: float): canvas.brush_size=value,false,false)
		number(tool_context,"Opacity",canvas.brush_opacity,0,1,.01,func(value: float): canvas.brush_opacity=value,false,false)
		choice(tool_context,["Normal","Stroke correct"],"Stroke correct" if canvas.stroke_correct else "Normal",func(value: String): canvas.stroke_correct=value=="Stroke correct")
	elif canvas.tool=="fill": number(tool_context,"Threshold · Shift+wheel",canvas.fill_threshold,0,1,.01,func(value: float): canvas.fill_threshold=value,false,false)
	elif canvas.tool=="shape": choice(tool_context,["Rectangle","Ellipse"],shape_kind.capitalize(),func(value: String): shape_kind=value.to_lower())
	elif canvas.tool=="pixel_select":
		var current := "Box (Shift: lasso)" if canvas.pixel_box_select else canvas.pixel_mode.capitalize()
		choice(tool_context,["Brush","Erase","Fill","Box (Shift: lasso)"],current,func(value: String): canvas.pixel_mode="erase" if value=="Erase" else ("fill" if value=="Fill" else "brush"); canvas.pixel_box_select=value.begins_with("Box"))
		button(tool_context,"Extract selection",extract_selection,"Move the selected pixels into a new independent component")
		button(tool_context,"Detach at playhead",detach_at_playhead,"Non-destructive timed split; source drawings stay intact")
		button(tool_context,"Clear",func(): session.action("Clear pixel selection",func(): session.pixel_mask=null; session.pixel_reference.clear()))
	else: button(tool_context,"Fit",canvas.fit); label(tool_context,"Drag handles · W draw / V move · P pivot")
func _refresh_keys() -> void:
	clear(key_fields); button(key_fields,"Events…",events_dialog); var selected := selected_key()
	if selected.is_empty(): label(key_fields,"I inserts selected state · Click ruler to scrub · Drag diamonds to move · Ctrl+D duplicate · Delete removes keys"); return
	var key: KiwiTransformationKey=selected.key; var item: KiwiTransformationComponent=selected.component
	if item.locked: label(key_fields,"Unlock this component to edit its keyframes."); return
	var times := {}
	for component in session.document.components:
		for frame in component.keys:
			if session.selected_keys.has(frame.id): times[frame.id]=frame.time
	number(key_fields,"Key time (s)",key.time,0,session.document.duration,.01,func(value: float):
		var delta := value-float(times[key.id])
		for component in session.document.components:
			if component.locked: continue
			for frame in component.keys:
				if times.has(frame.id): frame.time=float(times[frame.id])+delta)
	var names: Array=[]
	for state in item.states: names.append(state.title)
	choice(key_fields,names,item.state_for_id(key.state_id).title,func(value: String): change_keys("Key state",func(component: KiwiTransformationComponent,frame: KiwiTransformationKey):
		for state in component.states:
			if state.title==value: frame.state_id=state.id; break))
	var display_mode := key.mode if key.mode in KiwiTransformationKey.MODES else ("Grow / Reveal" if key.mode=="Reveal" else "Auto Morph")
	choice(key_fields,KiwiTransformationKey.MODES,display_mode,func(value: String): change_keys("Transition mode",func(_item: KiwiTransformationComponent,frame: KiwiTransformationKey): frame.mode=value))
	button(key_fields,"Curve…",curve_dialog); button(key_fields,"Match points…",match_dialog); button(key_fields,"Morph…",morph_options)
	number(key_fields,"Extra turns",key.turns,-20,20,1,func(value: float):
		for component in session.document.components:
			if component.locked: continue
			for frame in component.keys:
				if session.selected_keys.has(frame.id): frame.turns=roundi(value))
	button(key_fields,"Reveal path",func(): edit_key_state(); set_tool("reveal_path"),"Click points in the canvas to define the selected transition's reveal path")
	button(key_fields,"Clear path",func(): change_keys("Clear reveal path",func(_item: KiwiTransformationComponent,frame: KiwiTransformationKey): frame.reveal_path=PackedVector2Array()))
	number(key_fields,"Reveal width",key.reveal_width,.01,2.,.01,func(value: float): key.reveal_width=value)
	button(key_fields,"⌫",session.delete_keys,"Delete selected keyframes")
func change_keys(title: String, operation: Callable) -> void:
	session.begin()
	for item in session.document.components:
		if item.locked: continue
		for key in item.keys:
			if session.selected_keys.has(key.id): operation.call(item,key)
	var errors := session.document.validate()
	if not errors.is_empty(): session.cancel(); status.text=errors[0]
	else: session.commit(title)
func state_menu() -> void:
	menu("STATES",["Rename","Delete state and its keys","Copy state","Paste as new state","Move state up","Move state down"],func(value: String):
		var item := session.primary(); var state := session.active_state()
		if item==null: return
		match value:
			"Rename":
				if is_instance_valid(_state_name): _state_name.grab_focus(); _state_name.select_all()
			"Delete state and its keys": session.delete_state()
			"Copy state": session.state_clipboard=state.copy_state()
			"Paste as new state":
				if session.state_clipboard!=null and not item.locked:
					session.action("Paste state",func(): var copy := session.state_clipboard.copy_state(true); copy.artwork.id=item.id; item.states.append(copy); session.edit_states[item.id]=copy.id)
			_:
				var index := item.states.find(state); var target := clampi(index+(-1 if value=="Move state up" else 1),0,item.states.size()-1)
				if target!=index and not item.locked: session.action("Reorder state",func(): item.states.remove_at(index); item.states.insert(target,state))
	)
func component_menu() -> void:
	menu("COMPONENTS",["Duplicate","Copy","Paste","Delete","Import image as component…","Merge at playhead…"],func(value: String):
		match value:
			"Duplicate": session.duplicate_components()
			"Copy": session.copy_components()
			"Paste": session.paste_components()
			"Delete": session.delete_components()
			"Import image as component…": session.add_component(); import_dialog()
			"Merge at playhead…": merge_at_playhead()
	)
func menu(title: String, options: Array, callback: Callable) -> void:
	var popup := PopupPanel.new(); add_child(popup); var list := VBoxContainer.new(); list.custom_minimum_size.x=260; popup.add_child(list); label(list,title)
	for option: String in options: button(list,option,func(): popup.hide(); callback.call(option))
	popup.popup_hide.connect(popup.queue_free); popup.popup_centered()
func duration_dialog() -> void:
	var popup := AcceptDialog.new(); popup.title="Animation duration"; add_child(popup); var input := SpinBox.new(); input.min_value=.05; input.max_value=86400; input.step=.05; input.value=session.document.duration; popup.add_child(input)
	popup.confirmed.connect(func(): session.set_duration(input.value); popup.queue_free()); popup.canceled.connect(popup.queue_free); popup.popup_centered(Vector2i(300,100))
func canvas_size_dialog() -> void:
	var popup := AcceptDialog.new(); popup.title="Canvas dimensions (artwork is preserved)"; add_child(popup); var row := HBoxContainer.new(); popup.add_child(row); var controls: Array[SpinBox]=[]
	for axis in 2:
		var value := SpinBox.new(); value.min_value=1; value.max_value=8192; value.value=session.document.canvas_size[axis]; row.add_child(value); controls.append(value)
	popup.confirmed.connect(func():
		var size := Vector2i(controls[0].value,controls[1].value)
		if size.x*size.y<=16777216: session.action("Canvas dimensions",func(): session.document.canvas_size=size); canvas.fit.call_deferred()
		else: status.text="Maximum canvas area is 16 megapixels."
		popup.queue_free())
	popup.canceled.connect(popup.queue_free); popup.popup_centered(Vector2i(360,100))
func _shape_created(kind: String, bounds: Rect2,_points: PackedVector2Array) -> void:
	if kind!="shape" or session.active_state()==null or session.primary().locked: return
	var state := session.active_state(); var art := state.artwork; var image := art.texture.get_image().duplicate(); image.convert(Image.FORMAT_RGBA8)
	var frame := art.local_transform(); var scale := art.dimensions/Vector2(image.get_size()); var inverse := frame.affine_inverse(); var region := (inverse*bounds); region=Rect2(region.position/scale,region.size/scale).intersection(Rect2(Vector2.ZERO,Vector2(image.get_size())))
	for y in range(floori(region.position.y),ceili(region.end.y)):
		for x in range(floori(region.position.x),ceili(region.end.x)):
			var point := frame*(Vector2(x+.5,y+.5)*scale)
			if not bounds.has_point(point): continue
			if shape_kind=="ellipse" and ((point-bounds.get_center())/(bounds.size*.5)).length_squared()>1.: continue
			image.set_pixel(x,y,image.get_pixel(x,y).blend(canvas.color))
	session.action("Draw "+shape_kind,func(): art.texture=ImageTexture.create_from_image(image); state.revision+=1)
func extract_selection() -> void:
	finish_pending(); var state := session.active_state(); var item := session.primary()
	if state==null or item.locked or canvas.selection==null: status.text="Select pixels on an unlocked drawing first."; return
	var old := state.artwork.texture.get_image(); var remaining := old.duplicate(); var extracted := old.duplicate(); var frame := state.artwork.local_transform(); var scale := state.artwork.dimensions/Vector2(old.get_size())
	for y in old.get_height():
		for x in old.get_width():
			var coverage := canvas.selection_coverage(frame*(Vector2(x+.5,y+.5)*scale)); var value := old.get_pixel(x,y); var kept := value; kept.a*=1.-coverage; value.a*=coverage; remaining.set_pixel(x,y,kept); extracted.set_pixel(x,y,value)
	if extracted.get_used_rect().size==Vector2i.ZERO: status.text="The selection contains no visible pixels."; return
	session.action("Extract selected pixels",func():
		state.artwork.texture=ImageTexture.create_from_image(remaining); state.revision+=1
		var copy := KiwiTransformationImage2D.make_component(session.document.canvas_size,"Extracted drawing"); copy.base_size=item.base_size; copy.states[0].artwork=state.artwork.copy_layer(); copy.states[0].artwork.id=copy.id; copy.states[0].artwork.texture=ImageTexture.create_from_image(extracted); copy.states[0].pivot=state.pivot; session.document.components.append(copy); session.selected.assign([copy.id]))
func detach_at_playhead() -> void:
	finish_pending(); var state := session.active_state()
	if state==null or canvas.selection==null: status.text="Select pixels on a component first."; return
	var image := state.artwork.texture.get_image(); var mask := Image.create(image.get_width(),image.get_height(),false,Image.FORMAT_RGBA8); var frame := state.artwork.local_transform(); var scale := state.artwork.dimensions/Vector2(image.get_size())
	for y in image.get_height():
		for x in image.get_width(): mask.set_pixel(x,y,Color(1,1,1,canvas.selection_coverage(frame*(Vector2(x+.5,y+.5)*scale))))
	var message := KiwiMorphComponentEvents.detach(session,mask)
	if not message.is_empty(): status.text=message
	else: seek(session.playhead); status.text="Region detached at the playhead. Original states are unchanged; edit the new component's states to animate it."
func merge_at_playhead() -> void:
	finish_pending()
	if session.selected.size()<2: status.text="Choose at least two adjacent components to merge at the playhead."; return
	var owner_session := session; var revision := session.revision; var at := session.playhead; var ids := PackedStringArray(session.selected)
	var snapshot := KiwiTransformationSession.new(); snapshot.document=session.document.snapshot()
	for item in snapshot.document.components: item.visible=item.visible and ids.has(item.id)
	var capture := KiwiTransformationRenderer.new(); add_child(capture); capture.sync(snapshot,at); status.text="Preparing the selected components for a non-destructive merge…"
	var start := Time.get_ticks_msec(); var ready := false
	while Time.get_ticks_msec()-start<15000:
		await get_tree().process_frame; capture.sync(snapshot,at)
		ready=capture.cache.worker==null and capture.cache.requests.is_empty()
		if ready: break
	if not ready: capture.queue_free(); status.text="Merge preparation timed out; original components are unchanged."; return
	var image := await capture.flattened(); capture.queue_free()
	if session!=owner_session or revision!=session.revision: status.text="Merge canceled because the document changed."; return
	var message := KiwiMorphComponentEvents.merge(session,ids,image,at)
	if not message.is_empty(): status.text=message
	else: seek(at); status.text="Merged snapshot starts here. Earlier source animation remains editable and can be scrubbed backward."
func events_dialog() -> void:
	var popup := PopupPanel.new(); style_popup(popup); add_child(popup); var column := VBoxContainer.new(); column.custom_minimum_size=Vector2(460,100); popup.add_child(column); label(column,"COMPONENT TRANSFERS · non-destructive / reversible")
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size=Vector2(460,220); column.add_child(scroll); var list := VBoxContainer.new(); list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	if session.document.component_events.is_empty(): label(list,"Detach selected pixels, or merge adjacent components at the playhead.")
	for event in session.document.component_events:
		var id: String=event.id; var row := HBoxContainer.new(); list.add_child(row); label(row,event.kind+" → "+session.document.component(event.target).title).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		number(row,"Visibility time (s)",float(event.time),0,session.document.duration,.01,func(value: float):
			for current in session.document.component_events:
				if current.id==id: current.time=value).tooltip_text="Retimes visibility only; captured artwork and poses are not re-baked."
		button(row,"⌫",func(): remove_component_event(id); popup.hide(),"Remove transfer and hide its generated component; original drawings remain intact")
	button(column,"Done",popup.hide); popup.popup_hide.connect(popup.queue_free); popup.popup_centered(Vector2i(500,310))
func remove_component_event(id: String) -> void:
	for event in session.document.component_events:
		if event.id!=id: continue
		session.action("Delete component event",func():
			session.document.component(event.target).visible=false
			session.document.component_events.assign(session.document.component_events.filter(func(current: Dictionary): return current.id!=id)))
		return
func import_dialog() -> void:
	var property := ActorProperty.new(); property.options={"extensions":["png","jpg","jpeg","webp","bmp","svg","tga"],"raw_extensions":["png","jpg","jpeg","webp","bmp","svg","tga"]}
	var owner_session := session; var state := session.active_state(); var picked := await ActorProjectFilePicker.pick(self,property,"Load artwork for this state")
	if owner_session!=session or state!=session.active_state() or picked.is_empty() or picked==ActorProjectFilePicker.EMPTY_RESOURCE: return
	import_image(picked)
func import_image(source: String) -> void:
	var state := session.active_state()
	if state==null or session.primary().locked: return
	var image := Image.load_from_file(source)
	if image==null or image.is_empty(): status.text="This image could not be read."; return
	if image.get_width()>8192 or image.get_height()>8192 or image.get_width()*image.get_height()>16777216: status.text="Maximum state artwork is 8192 pixels per side / 16 megapixels."; return
	edit_mode(); session.action("Load state artwork",func(): state.artwork.texture=ImageTexture.create_from_image(image); state.revision+=1)
func _add_reveal_point(value: Vector2) -> void:
	var selected := selected_key()
	if selected.is_empty(): status.text="Select the outgoing keyframe first."; return
	if selected.key.reveal_path.size()>=64: return
	change_keys("Reveal path point",func(_item: KiwiTransformationComponent,key: KiwiTransformationKey): key.reveal_path.append(value); key.mode="Grow / Reveal"; key.reveal_mode="Path")
func morph_options() -> void:
	var selected := selected_key()
	if selected.is_empty() or selected.component.locked: return
	var component_id: String=selected.component.id; var key_id: String=selected.key.id; var frame: KiwiTransformationKey=selected.key
	var lookup := func() -> KiwiTransformationKey:
		var item := session.document.component(component_id)
		return item.key_for_id(key_id) if item!=null else null
	var popup := PopupPanel.new(); popup.name="MorphOptions"; style_popup(popup); add_child(popup); var outer := VBoxContainer.new(); popup.add_child(outer)
	var scroll := ScrollContainer.new(); scroll.custom_minimum_size=Vector2(480,260); scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; outer.add_child(scroll)
	var panel := VBoxContainer.new(); panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(panel); label(panel,"MORPH SETTINGS · outgoing transition")
	var keys: Array[KiwiTransformationKey]=selected.component.sorted_keys(); var index := keys.find(frame)
	if index+1<keys.size():
		var next_id: String=keys[index+1].id
		number(panel,"Transition duration (s)",keys[index+1].time-frame.time,.001,session.document.duration,.01,func(value: float):
			var item := session.document.component(component_id); var current: KiwiTransformationKey=lookup.call()
			if current!=null: item.key_for_id(next_id).time=current.time+value)
	label(panel,"GROWTH / REVEAL OPTIONS")
	choice(panel,["Point","Path","Directional","Shape expansion"],frame.reveal_mode,func(value: String): change_keys("Growth method",func(_item: KiwiTransformationComponent,key: KiwiTransformationKey):
		key.reveal_mode=value
		if key.mode=="Reveal": key.mode="Grow / Reveal"))
	var origin_toggle := CheckButton.new(); origin_toggle.text="Custom morph origin (otherwise use state pivot)"; origin_toggle.button_pressed=frame.origin_enabled; panel.add_child(origin_toggle); origin_toggle.toggled.connect(func(value: bool): change_keys("Morph origin",func(_item: KiwiTransformationComponent,key: KiwiTransformationKey): key.origin_enabled=value))
	var row := HBoxContainer.new(); panel.add_child(row)
	for axis in 2:
		number(row,"Origin "+["X","Y"][axis],frame.morph_origin[axis],0,1,.01,func(value: float):
			var current: KiwiTransformationKey=lookup.call()
			if current!=null: current.morph_origin[axis]=value)
	number(row,"Direction °",frame.direction,-360,360,1,func(value: float):
		var current: KiwiTransformationKey=lookup.call()
		if current!=null: current.direction=value)
	var advanced := VBoxContainer.new(); var toggle := CheckButton.new(); toggle.text="Advanced correspondence and appearance"; panel.add_child(toggle); panel.add_child(advanced); advanced.hide()
	toggle.toggled.connect(func(value: bool):
		advanced.visible=value; scroll.custom_minimum_size.y=minf(480,get_viewport_rect().size.y-140) if value else 260
		popup.popup_centered.call_deferred(Vector2i(500,int(scroll.custom_minimum_size.y+52))))
	choice(advanced,["Bounds","Local"],frame.alignment,func(value: String): change_keys("Correspondence alignment",func(_item: KiwiTransformationComponent,key: KiwiTransformationKey): key.alignment=value)).tooltip_text="Bounds normalizes shape comparisons; Local emphasizes original positions. Neither crops or moves the component pivot."
	choice(advanced,["Feature reveal","Aligned blend"],frame.appearance,func(value: String): change_keys("Appearance transition",func(_item: KiwiTransformationComponent,key: KiwiTransformationKey): key.appearance=value))
	choice(advanced,["Fast","High"],frame.quality,func(value: String): change_keys("Morph quality",func(_item: KiwiTransformationComponent,key: KiwiTransformationKey): key.quality=value))
	number(advanced,"Interior feature preservation",frame.preservation,0,1,.01,func(value: float):
		var current: KiwiTransformationKey=lookup.call()
		if current!=null: current.preservation=value)
	number(advanced,"Topology expansion bias",frame.topology_bias,-.15,.15,.005,func(value: float):
		var current: KiwiTransformationKey=lookup.call()
		if current!=null: current.topology_bias=value)
	button(outer,"Done",popup.hide); popup.popup_hide.connect(popup.queue_free); popup.popup_centered(Vector2i(500,312))
func curve_dialog() -> void:
	var selected := selected_key()
	if selected.is_empty(): return
	var popup := PopupPanel.new(); style_popup(popup); add_child(popup); var column := VBoxContainer.new(); column.custom_minimum_size=Vector2(430,280); popup.add_child(column)
	var graph := ActorValueCurve.new(); graph.editable=true; graph.custom_minimum_size=Vector2(430,230); graph.curve=selected.key.curve.duplicate() if selected.key.curve!=null else ActorValueCurve.preset("Smoothstep" if selected.key.mode in ["Auto Morph","Shape Morph","Guided Morph","Smooth morph"] else "Linear"); column.add_child(graph)
	graph.edit_started.connect(session.begin); graph.preview_changed.connect(func(curve: Curve):
		for item in session.document.components:
			if item.locked: continue
			for key in item.keys:
				if session.selected_keys.has(key.id): key.curve=curve.duplicate()
		_render_pending=true)
	graph.edit_committed.connect(func(): session.commit("Edit transition curve")); graph.edit_cancelled.connect(session.cancel)
	var row := HBoxContainer.new(); column.add_child(row)
	button(row,"Linear",func(): change_keys("Linear timing",func(_item: KiwiTransformationComponent,key: KiwiTransformationKey): key.curve=ActorValueCurve.preset("Linear")); graph.curve=ActorValueCurve.preset("Linear"); graph.queue_redraw())
	button(row,"Smooth",func(): change_keys("Smooth timing",func(_item: KiwiTransformationComponent,key: KiwiTransformationKey): key.curve=ActorValueCurve.preset("Smoothstep")); graph.curve=ActorValueCurve.preset("Smoothstep"); graph.queue_redraw())
	for data in [["Ease in","Quadratic"],["Ease out","Ease out"]]:
		button(row,data[0],func(): change_keys("Transition easing",func(_item: KiwiTransformationComponent,key: KiwiTransformationKey): key.curve=ActorValueCurve.preset(data[1])); graph.curve=ActorValueCurve.preset(data[1]); graph.queue_redraw())
	button(row,"Reset tangents",graph.reset_tangents); button(row,"Done",popup.hide); popup.popup_hide.connect(func(): graph.cancel_edit(); popup.queue_free()); popup.popup_centered()
func match_dialog() -> void:
	var selected := selected_key()
	if selected.is_empty() or selected.component.locked: return
	var item: KiwiTransformationComponent=selected.component; var key: KiwiTransformationKey=selected.key; var keys := item.sorted_keys(); var index := keys.find(key)
	if index+1>=keys.size(): status.text="Add another state key to the right before matching a transition."; return
	var popup := KiwiTransformationMatchEditor.new(); popup.workspace=self; popup.component_id=item.id; popup.key_id=key.id; popup.next_state_id=keys[index+1].state_id; add_child(popup); popup.open()
static func resolve(value: Variant) -> Dictionary:
	var document: KiwiTransformationImage2D=value if value is KiwiTransformationImage2D else (ResourceLoader.load(str(value),"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiTransformationImage2D if value is String and ResourceLoader.exists(value) else null)
	if document==null: return {"error":"Not a readable Transformation Image 2D asset."}
	var errors := document.validate()
	return {"document":document} if errors.is_empty() else {"error":errors[0]}
func open_source(value: Variant, state: Dictionary={}) -> bool:
	finish_pending(); playing=false
	if session.changed.is_connected(_changed): session.changed.disconnect(_changed)
	if state.get("session") is KiwiTransformationSession: session=state.session
	else:
		var result := resolve(value)
		if result.has("error"): status.text=result.error; session.changed.connect(_changed); return false
		session=KiwiTransformationSession.new(); session.document=result.document.snapshot(); session.dirty=not value is String
		session.restore_view_state(session.document.workspace_state)
	path=str(state.get("path",value if value is String else "")); session.changed.connect(_changed); timeline.session=session; components.session=session
	var ui: Dictionary=state.get("ui",session.document.workspace_state); previewing=ui.get("previewing")==true; loop=ui.get("loop",true)==true; onion=ui.get("onion")==true; canvas.zoom=clampf(view_number(ui,"zoom",.7),.03,32.)
	canvas.pan=ui.pan if ui.get("pan") is Vector2 and ui.pan.is_finite() else Vector2.ZERO
	animation_renderer.clear_views(); canvas.selection=null; canvas.selection_texture=null; canvas.onion=null; timeline.offset=maxf(0.,view_number(ui,"timeline_x",0.)); timeline.vertical=clampi(int(view_number(ui,"timeline_y",0.)),0,maxi(0,session.document.components.size()-2)); timeline.pixels_per_second=clampf(view_number(ui,"timeline_zoom",150.),25,600); _sync_edit_document(); _render_pending=true; _ui_pending=true; return true
static func view_number(ui: Dictionary, name: String, fallback: float) -> float:
	var value: Variant=ui.get(name,fallback)
	return float(value) if (value is float or value is int) and is_finite(float(value)) else fallback
func capture_state() -> Dictionary:
	finish_pending(); playing=false
	return {"session":session,"path":path,"ui":ui_state()}
func ui_state() -> Dictionary: return {"selected":session.selected.duplicate(),"states":session.edit_states.duplicate(),"time":session.playhead,"previewing":previewing,"zoom":canvas.zoom,"pan":canvas.pan,"loop":loop,"onion":onion,"timeline_x":timeline.offset,"timeline_y":timeline.vertical,"timeline_zoom":timeline.pixels_per_second}
func open_dialog() -> void:
	var property := ActorProperty.new(); property.options={"extensions":["tres","res"],"native_resource_types":["KiwiTransformationImage2D"]}
	var picked := await ActorProjectFilePicker.pick(self,property,"Open Transformation Image 2D")
	if picked.is_empty() or picked==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var tabs := get_tree().get_first_node_in_group("actor_scene_tabs")
	if tabs!=null: tabs.open_transformation(picked)
	else: open_source(picked)
func open_example(title: String) -> void:
	var document := KiwiTransformationExamples.create(title)
	var tabs := get_tree().get_first_node_in_group("actor_scene_tabs")
	if tabs!=null: tabs.open_transformation(document)
	elif not session.dirty: open_source(document)
	else:
		var popup := ConfirmationDialog.new(); popup.title="Open example"; popup.dialog_text="Replace this unsaved document?"; add_child(popup)
		popup.confirmed.connect(func(): open_source(document); popup.queue_free()); popup.canceled.connect(popup.queue_free); popup.popup_centered(Vector2i(360,130))
func save() -> void:
	if path.is_empty(): await save_as()
	else: await save_to(path)
func save_as() -> void:
	var owner_session := session
	var result := await ActorProjectResourceSaveDialog.pick(self,"Save editable Transformation Image 2D",path.get_file().get_basename() if not path.is_empty() else "Transformation Image","tres",false,PackedStringArray(["tres","res"]),func(): finish_pending(); return session.document.snapshot())
	if owner_session==session and not result.get("cancelled",true): await save_to(str(result.path))
func save_to(destination: String) -> Error:
	finish_pending(); var errors := session.document.validate()
	if not errors.is_empty(): status.text=errors[0]; return ERR_INVALID_DATA
	var saved_session := session; var revision := session.revision; var saved := session.document.snapshot(); saved.workspace_state=ui_state()
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		if session==saved_session:
			var bitmap := canvas.preview.get_image()
			if bitmap!=null:
				var scale := minf(192./bitmap.get_width(),144./bitmap.get_height()); bitmap.resize(maxi(1,roundi(bitmap.get_width()*scale)),maxi(1,roundi(bitmap.get_height()*scale)),Image.INTERPOLATE_BILINEAR); saved.preview_png=bitmap.save_png_to_buffer()
	var error := ResourceSaver.save(saved,destination)
	if error!=OK: status.text="Save failed (%d)."%error; return error
	if session==saved_session: path=destination; session.document.workspace_state=saved.workspace_state; session.document.preview_png=saved.preview_png
	saved_session.dirty=saved_session.revision!=revision; asset_saved.emit(destination,saved_session)
	if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()
	header.text="TRANSFORMATION 2D / "+path.get_file(); status.text="Saved editable states and animation · "+destination; return OK
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or focus is SpinBox: return
	if event.ctrl_pressed:
		match event.keycode:
			KEY_S:
				if event.shift_pressed: save_as()
				else: save()
			KEY_Z:
				finish_pending()
				if event.shift_pressed: session.redo()
				else: session.undo()
			KEY_Y: finish_pending(); session.redo()
			KEY_C: session.copy_components()
			KEY_V: finish_pending(); edit_mode(); session.paste_components()
			KEY_D: finish_pending(); edit_mode(); session.duplicate_components()
			_: return
	else:
		match event.keycode:
			KEY_SPACE: toggle_play()
			KEY_I: finish_pending(); session.insert_key()
			KEY_V: set_tool("move")
			KEY_W,KEY_B: set_tool("brush")
			KEY_E: set_tool("eraser")
			KEY_G: set_tool("fill")
			KEY_P: set_tool("pivot")
			KEY_F: canvas.fit()
			KEY_DELETE,KEY_BACKSPACE: finish_pending(); session.delete_components()
			_: return
	get_viewport().set_input_as_handled()
