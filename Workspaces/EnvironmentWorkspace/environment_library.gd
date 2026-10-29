extends VBoxContainer
## A filtered view of project files; paths continue to refer to the original assets.
signal asset_chosen(path: String)
signal source_requested(path: String)
class AssetList extends ItemList:
	func _get_drag_data(point: Vector2) -> Variant:
		var index:=get_item_at_position(point,true)
		if index<0: return null
		var path:=str(get_item_metadata(index)); var label:=Label.new(); label.text=path.get_file(); set_drag_preview(label); return {"files":[path]}
var search:=LineEdit.new()
var category:=OptionButton.new()
var list:=AssetList.new()
var preview:=TextureRect.new()
var info:=Label.new()
var _files: Array[String]=[]
var _directories: Array[String]=[]
var _directory: DirAccess
var _root:=""
var _selected:=""
var _refresh_due:=false
func _ready() -> void:
	search.placeholder_text="Find project assets…"; add_child(search); search.text_changed.connect(func(_text: String): refresh())
	for text in ["All assets","Models","Terrain Materials","Natural Objects","Structures","Miscellaneous Props"]: category.add_item(text)
	add_child(category); category.item_selected.connect(func(_index: int): refresh())
	list.size_flags_vertical=Control.SIZE_EXPAND_FILL; list.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; list.custom_minimum_size.y=90; add_child(list); list.item_selected.connect(_select); list.item_activated.connect(func(index: int): asset_chosen.emit(str(list.get_item_metadata(index))))
	preview.custom_minimum_size.y=70; preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; preview.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(preview)
	info.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; add_child(info)
	var buttons:=HBoxContainer.new(); add_child(buttons)
	for text in ["Use","Open source","↻"]:
		var button:=Button.new(); button.text=text; buttons.add_child(button); button.pressed.connect(func():
			if text=="↻": scan()
			elif not _selected.is_empty():
				if text=="Use": asset_chosen.emit(_selected)
				else: source_requested.emit(_selected))
	scan()
func scan() -> void:
	_root=ActorProjectFilePicker.root_directory(); _directory=null; _directories=[_root]; _files.clear(); _selected=""; preview.texture=null; refresh()
func _process(_delta: float) -> void:
	if not is_visible_in_tree(): return
	var started:=Time.get_ticks_usec(); var changed:=false
	while Time.get_ticks_usec()-started<2000:
		if _directory==null:
			if _directories.is_empty(): break
			_directory=DirAccess.open(_directories.pop_back())
			if _directory==null: continue
			_directory.list_dir_begin()
		var name:=_directory.get_next()
		if name.is_empty(): _directory.list_dir_end(); _directory=null; continue
		if name.begins_with("."): continue
		var path:=_directory.get_current_dir().path_join(name)
		if _directory.current_is_dir():
			if not _directory.is_link(name): _directories.append(path)
		elif compatible(path): _files.append(path); changed=true
		if _files.size()>=20000: _directories.clear(); _directory=null; break
	if changed: _refresh_due=true
	if _refresh_due and _directories.is_empty() and _directory==null: _refresh_due=false; refresh()
static func compatible(path: String) -> bool:
	var extension:=path.get_extension().to_lower()
	if extension in ["glb","gltf","obj","mesh","png","jpg","jpeg","webp"]: return true
	if extension=="res": return true # Native binary resources are validated when used.
	if extension!="tres": return false
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null: return false
	var header:=file.get_buffer(mini(file.get_length(),4096)).get_string_from_utf8()
	return "environment_document.gd" in header or "model_document.gd" in header or "type=\"StandardMaterial3D\"" in header or "type=\"ShaderMaterial\"" in header or "actor_object_data.gd" in header
func refresh() -> void:
	list.clear(); var filter:=search.text.to_lower(); var selection:=category.get_item_text(category.selected)
	for path in _files:
		var lower:=path.to_lower(); var material:=path.get_extension().to_lower() in ["png","jpg","jpeg","webp"] or "material" in lower
		if not filter.is_empty() and not filter in lower: continue
		if selection=="Terrain Materials" and not material: continue
		if selection=="Models" and material: continue
		if selection=="Natural Objects" and not ("tree" in lower or "plant" in lower or "rock" in lower or "natural" in lower): continue
		if selection=="Structures" and not ("structure" in lower or "building" in lower or "wall" in lower or "architecture" in lower): continue
		if selection=="Miscellaneous Props" and (material or "tree" in lower or "structure" in lower): continue
		var index:=list.add_item(path.get_file()); list.set_item_metadata(index,path); list.set_item_tooltip(index,path)
	info.text="%d project assets"%list.item_count
func _select(index: int) -> void:
	_selected=str(list.get_item_metadata(index)); var path:=_selected; info.text=path.get_file(); info.tooltip_text=path
	var texture:=await FileOperations.get_file_thumbnail(path)
	if is_inside_tree() and path==_selected: preview.texture=texture
