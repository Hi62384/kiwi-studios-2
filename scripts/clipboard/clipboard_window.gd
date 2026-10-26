extends PanelContainer
## Embedded, non-modal floating browser: drags remain in the same viewport.
var service: Node
var store: KiwiClipboardStore
var search:=LineEdit.new()
var tree:=Tree.new()
var files:=ItemList.new()
var preview:=TextureRect.new()
var details:=Label.new()
var status:=Label.new()
var default_button:=Button.new()
var folder:="default"
var trash:=false
var grid:=false
var copied:=PackedStringArray()
var cut:=false
var _dragging:=false
var _resizing:=false
var _origin:=Vector2.ZERO
var _before:=Vector2.ZERO
var _generation:=0
var _listing:=0
var _thumbnails: Dictionary={}
var _thumbnail_jobs: Array[Dictionary]=[]
var _thumbnail_busy:=false
func configure(host: Node) -> void:
	service=host; store=host.store; name="SuperClipboardWindow"; custom_minimum_size=Vector2(540,340); mouse_filter=Control.MOUSE_FILTER_STOP; focus_mode=Control.FOCUS_ALL
	_build_theme()
	var style:=StyleBoxFlat.new(); style.bg_color=Color("101b25"); style.border_color=Color("4c9d8b"); style.set_border_width_all(2); style.set_corner_radius_all(10); style.set_content_margin_all(10); add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",7); add_child(column)
	var title:=HBoxContainer.new(); column.add_child(title)
	var grip:=Label.new(); grip.text="⠿  SUPER CLIPBOARD"; grip.add_theme_color_override("font_color",Color("88e7ca")); grip.size_flags_horizontal=Control.SIZE_EXPAND_FILL; grip.mouse_filter=Control.MOUSE_FILTER_STOP; title.add_child(grip); grip.gui_input.connect(_title_input)
	button(title,"↶",func(): store.history.undo(),"Undo clipboard change"); button(title,"↷",func(): store.history.redo(),"Redo clipboard change")
	button(title,"×",_close,"Close · F8 / Escape")
	search.placeholder_text="Search names or resource types…"; search.clear_button_enabled=true; column.add_child(search); search.text_changed.connect(func(_text: String): _refresh_files())
	var toolbar:=HBoxContainer.new(); column.add_child(toolbar)
	button(toolbar,"Save active",service.save_active_document,"Save an editable snapshot of the active document")
	button(toolbar,"＋ Folder",func(): _prompt("New folder","",func(text: String): store.create_folder(text,folder)))
	var actions:=MenuButton.new(); actions.text="Organize ▾"; toolbar.add_child(actions)
	for label in ["Rename · F2","Move to folder…","Duplicate · Ctrl+D","Copy · Ctrl+C","Cut · Ctrl+X","Paste · Ctrl+V","Delete to Trash"]: actions.get_popup().add_item(label)
	actions.get_popup().id_pressed.connect(func(index: int):
		match index:
			0: _rename()
			1: _move_menu()
			2: store.move(_selection(),folder,true)
			3,4: copied=_selection(); cut=index==4
			5: store.move(copied,folder,not cut)
			6: _delete()
	)
	button(toolbar,"▦",func(): grid=not grid; _refresh_files(),"List / thumbnails")
	button(toolbar,"Trash",func(): trash=not trash; _refresh_files(),"Recover deleted resources")
	var split:=HSplitContainer.new(); split.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(split); split.split_offset=165
	tree.hide_root=false; tree.custom_minimum_size.x=145; split.add_child(tree); tree.item_selected.connect(func(): var item:=tree.get_selected(); if item!=null: folder=str(item.get_metadata(0)); trash=false; _refresh_files())
	tree.set_drag_forwarding(_folder_drag,_folder_can_drop,_folder_drop)
	var right:=VBoxContainer.new(); right.size_flags_horizontal=Control.SIZE_EXPAND_FILL; split.add_child(right)
	files.select_mode=ItemList.SELECT_MULTI; files.size_flags_vertical=Control.SIZE_EXPAND_FILL; files.size_flags_horizontal=Control.SIZE_EXPAND_FILL; files.auto_height=false; right.add_child(files)
	files.set_drag_forwarding(_file_drag,_can_drop,_drop); files.multi_selected.connect(func(_i: int,_selected: bool): _preview()); files.item_activated.connect(func(_index: int): _use())
	files.get_v_scroll_bar().value_changed.connect(func(_value: float): _queue_thumbnails())
	var info:=HBoxContainer.new(); right.add_child(info)
	preview.custom_minimum_size=Vector2(76,56); preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; info.add_child(preview)
	details.text="Drag files in to save; drag files out to reuse."; details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; details.max_lines_visible=3; details.custom_minimum_size.x=180; details.size_flags_horizontal=Control.SIZE_EXPAND_FILL; info.add_child(details)
	var bottom:=HBoxContainer.new(); column.add_child(bottom)
	default_button.text="★ Set default"; default_button.tooltip_text="Use the selected resource as the Default Slot in asset pickers"; default_button.disabled=true; default_button.pressed.connect(func(): var ids:=selected(); if ids.size()==1: store.set_default(ids[0])); bottom.add_child(default_button)
	button(bottom,"Use in project",_use); button(bottom,"Restore",func(): store.delete(selected(),true))
	status.size_flags_horizontal=Control.SIZE_EXPAND_FILL; status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; bottom.add_child(status)
	var resize:=Button.new(); resize.text="◢"; bottom.add_child(resize); resize.gui_input.connect(_resize_input)
	gui_input.connect(_keys); files.gui_input.connect(_keys); tree.gui_input.connect(_keys); search.gui_input.connect(_keys)
	var state: Dictionary=store.data.ui; folder=str(state.get("folder","default")); grid=bool(state.get("grid",false)); size=Vector2(state.get("width",760),state.get("height",470)); position=Vector2(state.get("x",80),state.get("y",100)); _clamp_window()
	search.text=str(state.get("search","")); store.changed.connect(_refresh); _refresh()
	_restore_bounds.call_deferred(state); get_viewport().size_changed.connect(_clamp_window)
func _restore_bounds(state: Dictionary) -> void:
	size=Vector2(state.get("width",760),state.get("height",470)); _clamp_window()
func _build_theme() -> void:
	theme=Theme.new()
	for type in ["Label","Button","MenuButton","LineEdit","ItemList","Tree","PopupMenu"]:
		theme.set_font_size("font_size",type,13); theme.set_color("font_color",type,Color("d9e9ef"))
	for type in ["Button","MenuButton"]:
		for state in ["normal","hover","pressed","focus","disabled"]:
			var box:=StyleBoxFlat.new(); box.bg_color=Color("214b46") if state=="pressed" else Color("213443") if state=="hover" else Color("172734"); box.border_color=Color("70ddbd") if state in ["pressed","focus"] else Color("344f61"); box.set_border_width_all(1); box.set_corner_radius_all(5); box.content_margin_left=9; box.content_margin_right=9; box.content_margin_top=5; box.content_margin_bottom=5; theme.set_stylebox(state,type,box)
	for type in ["LineEdit","ItemList","Tree"]:
		var panel:=StyleBoxFlat.new(); panel.bg_color=Color("101a24"); panel.border_color=Color("2b4354"); panel.set_border_width_all(1); panel.set_corner_radius_all(5); panel.set_content_margin_all(6); theme.set_stylebox("panel" if type!="LineEdit" else "normal",type,panel)
func _selection() -> PackedStringArray:
	var ids:=selected()
	return ids if not ids.is_empty() else PackedStringArray([folder])
func button(parent: Node,text: String,action: Callable,tip: String="") -> Button:
	var input:=Button.new(); input.text=text; input.tooltip_text=tip; input.add_theme_font_size_override("font_size",12); parent.add_child(input); input.pressed.connect(action); return input
func _refresh() -> void:
	if not folder.is_empty() and not store.folder_valid(folder): folder="default"
	tree.clear(); var root:=tree.create_item(); root.set_text(0,"Super Clipboard"); root.set_metadata(0,""); _folders(root,"",{})
	_refresh_files()
func _folders(parent: TreeItem,id: String,visited: Dictionary) -> void:
	if visited.has(id): return
	visited[id]=true
	for key: String in store.data.folders:
		var item: Dictionary=store.data.folders[key]
		if str(item.parent)!=id or item.get("deleted",false): continue
		var row:=tree.create_item(parent); row.set_text(0,str(item.name)); row.set_icon(0,FileOperations.FOLDER_COLORED_TEXTURE); row.set_icon_max_width(0,18); row.set_metadata(0,key)
		if key==folder: row.select(0)
		_folders(row,key,visited)
func _refresh_files() -> void:
	_listing+=1; var token:=_listing; files.clear(); default_button.disabled=true; files.max_columns=0 if grid else 1; files.icon_mode=ItemList.ICON_MODE_TOP if grid else ItemList.ICON_MODE_LEFT; files.fixed_icon_size=Vector2i(72,56) if grid else Vector2i(20,20); files.fixed_column_width=120 if grid else 0
	var query:=search.text.strip_edges().to_lower(); var count:=0
	for id: String in store.data.entries:
		var entry: Dictionary=store.data.entries[id]
		if bool(entry.get("deleted",false))!=trash: continue
		if query.is_empty() and not folder.is_empty() and str(entry.folder)!=folder and not trash: continue
		if not query.is_empty() and not (str(entry.name)+" "+str(entry.type)).to_lower().contains(query): continue
		files.add_item(("★ " if str(store.data.default_slot)==id else "")+str(entry.name),store.icon(id)); files.set_item_metadata(files.item_count-1,id); files.set_item_tooltip(files.item_count-1,str(entry.type)+" · "+str(entry.name)); count+=1
		if count%200==0:
			await get_tree().process_frame
			if token!=_listing: return
	status.text=("Trash · " if trash else "")+str(count)+" items"
	_queue_thumbnails.call_deferred()
func _queue_thumbnails() -> void:
	if not grid or not visible: return
	_thumbnail_jobs.clear()
	for index in files.item_count:
		var rectangle:=files.get_item_rect(index); rectangle.position.y-=files.get_v_scroll_bar().value
		if not rectangle.intersects(Rect2(Vector2.ZERO,files.size)): continue
		var id:=str(files.get_item_metadata(index))
		if _thumbnails.has(id): files.set_item_icon(index,_thumbnails[id])
		else: _thumbnail_jobs.append({"id":id,"index":index,"generation":_listing})
func _process(_dt: float) -> void:
	if not visible or _thumbnail_busy or _thumbnail_jobs.is_empty(): return
	_thumbnail_busy=true; _thumbnail(_thumbnail_jobs.pop_front())
func _thumbnail(job: Dictionary) -> void:
	var path:=store.entry_path(str(job.id),trash); var texture: Texture2D
	if not path.is_empty() and KiwiClipboardSnapshot.safe_resource(path): texture=await FileOperations.get_file_thumbnail(path)
	_thumbnail_busy=false
	if texture==null or job.generation!=_listing or not is_instance_valid(files): return
	if maxf(texture.get_width(),texture.get_height())>128:
		var image:=texture.get_image()
		if image!=null:
			var ratio:=128.0/maxi(image.get_width(),image.get_height()); image.resize(maxi(1,roundi(image.get_width()*ratio)),maxi(1,roundi(image.get_height()*ratio)),Image.INTERPOLATE_BILINEAR); texture=ImageTexture.create_from_image(image)
	_thumbnails[str(job.id)]=texture
	while _thumbnails.size()>128: _thumbnails.erase(_thumbnails.keys()[0])
	if int(job.index)<files.item_count and str(files.get_item_metadata(job.index))==str(job.id): files.set_item_icon(job.index,texture)
func selected() -> PackedStringArray:
	var result:=PackedStringArray()
	for index in files.get_selected_items(): result.append(str(files.get_item_metadata(index)))
	return result
func _preview() -> void:
	_generation+=1; var token:=_generation; var ids:=selected(); preview.texture=null
	default_button.disabled=ids.size()!=1 or trash
	if ids.size()!=1: details.text="%d resources selected"%ids.size(); return
	var entry: Dictionary=store.data.entries[ids[0]]; details.text=str(entry.name)+"\n"+str(entry.type); var path:=store.entry_path(ids[0],trash)
	if not path.is_empty() and KiwiClipboardSnapshot.safe_resource(path):
		var texture:=await FileOperations.get_file_thumbnail(path)
		if token==_generation and is_instance_valid(preview): preview.texture=texture
func _use() -> void:
	var ids:=selected()
	if ids.size()!=1: service.notify("Select one resource to open. Drag multiple files to compatible targets.",true); return
	var path: String=service.import_item(ids[0])
	if path.is_empty(): return
	var tabs:=get_tree().get_first_node_in_group("actor_scene_tabs")
	if tabs!=null: tabs._filesystem_resource_opened(path)
func _rename() -> void:
	var ids:=selected()
	var id:=ids[0] if ids.size()==1 else folder
	var entry: Dictionary=store.data.entries.get(id,store.data.folders.get(id,{}))
	_prompt("Rename",str(entry.get("name","")),func(text: String): _result(store.rename(id,text)))
func _delete() -> void:
	var ids:=selected()
	if ids.is_empty() and folder!="default": ids.append(folder)
	store.delete(ids); status.text="Moved to Trash · undo or restore to recover"
func _prompt(title: String,value: String,confirmed: Callable) -> void:
	var popup:=ConfirmationDialog.new(); popup.title=title; add_child(popup); var input:=LineEdit.new(); input.text=value; popup.add_child(input); popup.confirmed.connect(func(): confirmed.call(input.text); popup.queue_free()); popup.canceled.connect(popup.queue_free); popup.popup_centered(Vector2i(310,100)); input.grab_focus(); input.select_all()
func _move_menu() -> void:
	var popup:=PopupMenu.new(); add_child(popup); var ids:=selected()
	if ids.is_empty(): ids.append(folder)
	for key: String in store.data.folders:
		if store.folder_valid(key): popup.add_item(str(store.data.folders[key].name)); popup.set_item_metadata(popup.item_count-1,key)
	popup.index_pressed.connect(func(index: int): _result(store.move(ids,str(popup.get_item_metadata(index))))); popup.popup_hide.connect(popup.queue_free); popup.position=Vector2i(get_global_mouse_position()); popup.popup()
func _file_drag(_at: Vector2) -> Variant:
	var ids:=selected(); var data: Dictionary=service.drag_payload(ids)
	if data.is_empty(): return null
	var label:=Label.new(); label.text=str(store.data.entries[ids[0]].name)+(str(" +",ids.size()-1) if ids.size()>1 else ""); files.set_drag_preview(label); return data
func _folder_drag(_at: Vector2) -> Variant:
	if folder.is_empty() or folder=="default": return null
	return {"type":"clipboard_folders","clipboard_ids":PackedStringArray([folder])}
func _can_drop(_at: Vector2,data: Variant) -> bool:
	return data is Dictionary and (data.has("clipboard_ids") or data.has("paths"))
func _drop(_at: Vector2,data: Variant) -> void: _receive(data,folder)
func _folder_can_drop(at: Vector2,data: Variant) -> bool: return tree.get_item_at_position(at)!=null and _can_drop(at,data)
func _folder_drop(at: Vector2,data: Variant) -> void:
	var item:=tree.get_item_at_position(at)
	if item!=null: _receive(data,str(item.get_metadata(0)))
func _receive(data: Dictionary,destination: String) -> void:
	if destination.is_empty(): destination="default"
	if data.has("clipboard_ids"): _result(store.move(PackedStringArray(data.clipboard_ids),destination,Input.is_key_pressed(KEY_CTRL))); return
	for path: String in data.get("paths",[]): service.quick_save(path,path.get_file().get_basename(),destination)
func _result(ok: bool) -> void:
	if not ok: status.text=store.error; service.notify(store.error,true)
func _keys(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	var focus:=get_viewport().gui_get_focus_owner()
	if event.keycode==KEY_ESCAPE: _close(); accept_event(); return
	if focus is LineEdit or focus is TextEdit: return
	if event.keycode==KEY_ESCAPE: _close()
	elif event.ctrl_pressed and event.keycode==KEY_Z: store.history.redo() if event.shift_pressed else store.history.undo()
	elif event.ctrl_pressed and event.keycode==KEY_Y: store.history.redo()
	elif event.ctrl_pressed and event.keycode==KEY_D: store.move(_selection(),folder,true)
	elif event.ctrl_pressed and event.keycode in [KEY_C,KEY_X]: copied=_selection(); cut=event.keycode==KEY_X
	elif event.ctrl_pressed and event.keycode==KEY_V:
		store.move(copied,folder,not cut)
		if cut: copied.clear()
	elif event.keycode==KEY_F2: _rename()
	elif event.keycode in [KEY_DELETE,KEY_BACKSPACE]: _delete()
	else: return
	accept_event()
func _title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		_dragging=event.pressed; _origin=get_global_mouse_position(); _before=position
	if event is InputEventMouseMotion and _dragging: position=_before+get_global_mouse_position()-_origin; _clamp_window()
	if not _dragging: _remember()
func _resize_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT: _resizing=event.pressed; _origin=get_global_mouse_position(); _before=size
	if event is InputEventMouseMotion and _resizing: size=(_before+get_global_mouse_position()-_origin).max(custom_minimum_size); _clamp_window()
	if not _resizing: _remember()
func _clamp_window() -> void:
	var bounds:=get_viewport_rect().size; size=size.min(bounds); position=position.clamp(Vector2.ZERO,(bounds-size).max(Vector2.ZERO))
func _remember() -> void:
	if store!=null: store.save_ui({"x":position.x,"y":position.y,"width":size.x,"height":size.y,"folder":folder,"grid":grid,"search":search.text})
func _close() -> void: _remember(); hide()
