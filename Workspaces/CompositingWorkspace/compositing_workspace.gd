class_name KiwiCompositingWorkspace
extends Control
const CompositeCurveEditor=preload("res://Workspaces/CompositingWorkspace/composite_curve_editor.gd")
static var _layer_clipboard: KiwiCompositeLayer
static var _layer_graph_clipboard: KiwiCompositeGraph
static var _hierarchy_clipboard: KiwiCompositingDocument
static var _hierarchy_clipboard_root: String=""
signal document_changed
signal composition_saved(path: String,document: KiwiCompositingDocument)
var document:=KiwiCompositingDocument.new()
var evaluator:=KiwiCompositingEvaluator.new()
var source: Variant
var path:=""
var selected_id:=""
var selected_graph_node_id:=""
var dirty:=false
var image_view:=TextureRect.new()
var layer_tree:=Tree.new()
var inspector:=VBoxContainer.new()
var status:=Label.new()
var title_edit:=LineEdit.new()
var resolution_label:=Label.new()
var graph_edit:=GraphEdit.new()
var mode:=0
var preview_time:=0.0
var time_slider:=HSlider.new()
var time_spin:=SpinBox.new()
var play_timer:=Timer.new()
var _history: Array[KiwiCompositingDocument]=[]
var _redo: Array[KiwiCompositingDocument]=[]
var _file_dialog: FileDialog
var _video_dialog: FileDialog
var _export_dialog: FileDialog
var _refreshing:=false
var _layer_controls: Array[Control]=[]
var _graph_controls: Array[Control]=[]
var _graph_node_controls: Array[Button]=[]
var graph_search:=LineEdit.new()
var _graph_move_before: KiwiCompositingDocument
var _video_retry_elapsed:=0.0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _build(); _ensure_document(); _set_mode(0)

func _process(delta: float) -> void:
	if not status.text.begins_with("Waiting for the requested video frame:"): return
	_video_retry_elapsed+=delta
	if _video_retry_elapsed>=.15: _video_retry_elapsed=0.; _render()

func _build() -> void:
	var root:=VBoxContainer.new(); root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_theme_constant_override("separation",6); add_child(root)
	var header:=HBoxContainer.new(); root.add_child(header); title_edit.custom_minimum_size.x=170; title_edit.placeholder_text="Composition name"; title_edit.text=document.title; header.add_child(title_edit); title_edit.text_submitted.connect(_rename_document); _button(header,"Save",save,"Save composition"); _button(header,"Save As",save_as,"Save to a new project resource"); _button(header,"Undo",undo); _button(header,"Redo",redo); _button(header,"Layers",func(): _set_mode(0)); _button(header,"Nodes",func(): _set_mode(1)); _button(header,"▶",_toggle_play,"Play/pause composition preview"); _button(header,"Export Video",_choose_export_video,"Render the composition to an MP4 video file"); time_spin.min_value=0.; time_spin.max_value=document.duration; time_spin.step=1.0/document.frame_rate; time_spin.suffix=" s"; time_spin.custom_minimum_size.x=105; header.add_child(time_spin); time_spin.value_changed.connect(_time_changed); resolution_label.text="1920 × 1080 · 24 fps"; resolution_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; resolution_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; header.add_child(resolution_label)
	var tools_scroll:=ScrollContainer.new(); tools_scroll.custom_minimum_size.y=36; tools_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; tools_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; root.add_child(tools_scroll)
	var tools:=HBoxContainer.new(); tools.size_flags_horizontal=Control.SIZE_EXPAND_FILL; tools_scroll.add_child(tools)
	for data in [["＋ Image",choose_image,"Add a non-destructive image layer"],["＋ Video",choose_video,"Add a seekable video-footage layer"],["＋ Text",func(): _add_layer(KiwiCompositeLayer.Kind.TEXT),"Add an editable text overlay"],["＋ Shape",func(): _add_layer(KiwiCompositeLayer.Kind.SHAPE),"Add a vector-like procedural shape"],["＋ Solid",func(): _add_layer(KiwiCompositeLayer.Kind.SOLID),"Add a solid color layer"],["＋ Adjustment",func(): _add_layer(KiwiCompositeLayer.Kind.ADJUSTMENT),"Add an adjustment layer"],["Group",_group_layers,"Group selected layers"],["Ungroup",_ungroup_layer,"Ungroup the selected group"],["Duplicate",_duplicate_layer,"Duplicate selected layer"],["Copy",_copy_layer,"Copy selected layer"],["Paste",_paste_layer,"Paste copied layer"],["↑",func(): _move_layer(1),"Move layer up"],["↓",func(): _move_layer(-1),"Move layer down"],["Solo",_toggle_solo,"Solo the selected layer"],["Layer Graph",_open_layer_graph,"Open or create a node graph that processes this layer"],["Delete",_delete_layer,"Remove selected layer"],["Refresh",_render,"Render the current composition"]]: _layer_controls.append(_button(tools,data[0],data[1],data[2]))
	graph_search.placeholder_text="Find graph nodes…"; graph_search.custom_minimum_size=Vector2(145,28); graph_search.visible=false; tools.add_child(graph_search); graph_search.text_changed.connect(_filter_graph_nodes)
	for data in [["New Graph",_new_graph],["Image Source",func(): _add_graph_node("Image Source")],["Layer Source",func(): _add_graph_node("Layer Source")],["Solid Color",func(): _add_graph_node("Solid Color")],["Over",func(): _add_graph_node("Over")],["Merge",func(): _add_graph_node("Merge")],["Mask",func(): _add_graph_node("Mask")],["Blur",func(): _add_graph_node("Blur")],["Chroma Key",func(): _add_graph_node("Chroma Key")],["Luma Key",func(): _add_graph_node("Luma Key")],["Color Grade",func(): _add_graph_node("Color Grade")],["Output",func(): _add_graph_node("Output")],["Duplicate Node",_duplicate_graph_node],["Delete Node",_delete_graph_node]]:
		var graph_button:=_button(tools,data[0],data[1],"Graph node workflow; connect compatible ports"); _graph_controls.append(graph_button)
		if data[0] not in ["New Graph","Duplicate Node","Delete Node"]: _graph_node_controls.append(graph_button)
	_button(header,"PNG Sequence",func(): choose_sequence_export("png"),"Export color-managed RGBA frames"); _button(header,"EXR Sequence",func(): choose_sequence_export("exr"),"Export scene-linear float RGBA frames")
	var split:=HSplitContainer.new(); split.size_flags_vertical=Control.SIZE_EXPAND_FILL; root.add_child(split)
	var left:=VBoxContainer.new(); left.custom_minimum_size.x=210; split.add_child(left); var layers_label:=Label.new(); layers_label.text="LAYERS · bottom to top"; left.add_child(layers_label); layer_tree.size_flags_vertical=Control.SIZE_EXPAND_FILL; layer_tree.select_mode=Tree.SELECT_MULTI; left.add_child(layer_tree); layer_tree.item_selected.connect(_layer_selected); layer_tree.multi_selected.connect(func(item: TreeItem,column: int,selected: bool): if selected: _layer_selected())
	var center:=VBoxContainer.new(); center.size_flags_horizontal=Control.SIZE_EXPAND_FILL; split.add_child(center)
	var viewer_scroll:=ScrollContainer.new(); viewer_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; viewer_scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL; viewer_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; viewer_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; center.add_child(viewer_scroll)
	var viewer_back:=CenterContainer.new(); viewer_back.custom_minimum_size=Vector2(480,270); viewer_back.size_flags_horizontal=Control.SIZE_EXPAND_FILL; viewer_back.size_flags_vertical=Control.SIZE_EXPAND_FILL; viewer_scroll.add_child(viewer_back)
	image_view.expand_mode=TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL; image_view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; image_view.custom_minimum_size=Vector2(480,270); viewer_back.add_child(image_view)
	graph_edit.visible=false; graph_edit.size_flags_vertical=Control.SIZE_EXPAND_FILL; graph_edit.size_flags_stretch_ratio=1.; graph_edit.size_flags_horizontal=Control.SIZE_EXPAND_FILL; graph_edit.show_grid=true; graph_edit.connection_request.connect(_graph_connect_request); graph_edit.disconnection_request.connect(_graph_disconnect_request); graph_edit.node_selected.connect(_graph_node_selected); graph_edit.node_deselected.connect(_graph_node_deselected); graph_edit.begin_node_move.connect(func(): _graph_move_before=document.duplicate(true)); graph_edit.end_node_move.connect(_graph_nodes_moved); center.add_child(graph_edit)
	time_slider.min_value=0.; time_slider.max_value=document.duration; time_slider.step=1.0/document.frame_rate; center.add_child(time_slider); time_slider.value_changed.connect(_time_changed)
	var right_scroll:=ScrollContainer.new(); right_scroll.custom_minimum_size.x=250; split.add_child(right_scroll); right_scroll.add_child(inspector)
	status.text="Ready"; root.add_child(status)
	_file_dialog=FileDialog.new(); _file_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE; _file_dialog.access=FileDialog.ACCESS_RESOURCES; _file_dialog.add_filter("*.png, *.jpg, *.jpeg, *.webp, *.tga, *.bmp", "Images"); add_child(_file_dialog); _file_dialog.file_selected.connect(_image_selected)
	_video_dialog=FileDialog.new(); _video_dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE; _video_dialog.access=FileDialog.ACCESS_RESOURCES; _video_dialog.add_filter("*.mp4, *.mov, *.mkv, *.webm, *.avi, *.m4v, *.ogv, *.mpeg, *.mpg", "Video footage"); add_child(_video_dialog); _video_dialog.file_selected.connect(_video_selected)
	_export_dialog=FileDialog.new(); _export_dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE; _export_dialog.access=FileDialog.ACCESS_FILESYSTEM; _export_dialog.add_filter("*.mp4", "MP4 video"); _export_dialog.current_file=document.title.validate_filename()+".mp4"; add_child(_export_dialog); _export_dialog.file_selected.connect(func(destination: String): export_video(destination))
	play_timer.wait_time=1.0/document.frame_rate; play_timer.timeout.connect(_advance_time); add_child(play_timer)

func _button(parent: Node,text: String,action: Callable,hint: String="") -> Button:
	var button:=Button.new(); button.text=text; button.tooltip_text=hint; button.custom_minimum_size.y=28; parent.add_child(button); button.pressed.connect(action); return button

func _rename_document(value: String) -> void:
	var before: KiwiCompositingDocument=document.duplicate(true); document.title=value.strip_edges(); if document.title.is_empty(): document.title="Untitled Composition"; _commit("Rename composition",before)

func open_source(value: Variant,state: Dictionary={}) -> void:
	source=value; path=str(value) if value is String else ""
	if value is KiwiCompositingDocument: document=value
	elif value is String and ResourceLoader.exists(value): document=ResourceLoader.load(value,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiCompositingDocument
	else: document=KiwiCompositingDocument.new()
	if document==null: document=KiwiCompositingDocument.new(); status.text="The composition could not be read; opened a blank document."
	dirty=not value is String
	if state.has("selected_id"): selected_id=str(state.selected_id)
	if state.has("mode"): mode=int(state.mode)
	if state.has("preview_time"): preview_time=float(state.preview_time)
	_history.clear(); _redo.clear(); evaluator.clear_cache(); _ensure_document(); _refresh_ui(); _render()

func capture_state() -> Dictionary: return {"document":document,"path":path,"selected_id":selected_id,"mode":mode,"dirty":dirty,"preview_time":preview_time}
func _ensure_document() -> void:
	if document==null: document=KiwiCompositingDocument.new()
	if document.layers.is_empty(): var background:=document.add_layer(KiwiCompositeLayer.Kind.SOLID,"Background"); background.color=Color(0.,0.,0.,0.)

func _set_mode(value: int) -> void:
	mode=value; image_view.get_parent().get_parent().visible=true; graph_edit.visible=value==1
	graph_search.visible=value==1
	for control in _layer_controls: control.visible=value==0
	for control in _graph_controls: control.visible=value==1
	_filter_graph_nodes(graph_search.text)
	_refresh_graph(); _refresh_inspector(); _render()

func _filter_graph_nodes(query: String) -> void:
	var normalized:=query.strip_edges().to_lower()
	for button in _graph_node_controls: button.visible=mode==1 and (normalized.is_empty() or button.text.to_lower().contains(normalized))

func _refresh_ui() -> void:
	_refreshing=true; title_edit.text=document.title; resolution_label.text="%d × %d  ·  %.2f fps"%[document.canvas_size.x,document.canvas_size.y,document.frame_rate]
	time_spin.max_value=document.duration; time_spin.step=1.0/document.frame_rate; time_spin.set_value_no_signal(clampf(preview_time,0.,document.duration)); time_slider.max_value=document.duration; time_slider.step=1.0/document.frame_rate; time_slider.set_value_no_signal(clampf(preview_time,0.,document.duration)); play_timer.wait_time=1.0/document.frame_rate
	layer_tree.clear(); var root:=layer_tree.create_item(); root.set_text(0,document.title)
	var item_by_id: Dictionary={}; var pending: Array[KiwiCompositeLayer]=[]
	for layer in document.layers:
		if layer!=null: pending.append(layer)
	for _attempt in pending.size()+1:
		var progressed:=false
		for index in range(pending.size()-1,-1,-1):
			var layer:=pending[index]; var parent: TreeItem=root
			if not layer.parent_id.is_empty():
				if not item_by_id.has(layer.parent_id): continue
				parent=item_by_id[layer.parent_id]
			var item:=layer_tree.create_item(parent); item.set_text(0,("◉ " if layer.visible else "○ ")+layer.name); item.set_metadata(0,layer.id); item.set_selectable(0,true); item_by_id[layer.id]=item
			if layer.locked: item.set_text(0,"🔒 "+layer.name)
			if layer.id==selected_id: item.select(0)
			pending.remove_at(index); progressed=true
		if not progressed: break
	_refresh_inspector(); _refresh_graph(); _refreshing=false

func _layer_selected() -> void:
	if _refreshing: return
	var item:=layer_tree.get_selected(); if item==null: return
	selected_id=str(item.get_metadata(0)); _refresh_inspector(); _render()

func _refresh_inspector() -> void:
	for child in inspector.get_children(): child.queue_free()
	if mode==1 and not selected_graph_node_id.is_empty(): _refresh_graph_inspector(); return
	var layer:=document.layer(selected_id)
	if layer==null:
		var empty:=Label.new(); empty.text="Select a layer to edit its source, blend, and timing."; empty.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; inspector.add_child(empty); return
	var header:=Label.new(); header.text="LAYER · "+["Image","Solid","Video","CGI","VFX","Text","Shape","Mask","Adjustment","Group","Linked Composition"][layer.kind]; inspector.add_child(header)
	_line("Name",layer.name,func(value: String): _edit_layer("Rename layer",func(target: KiwiCompositeLayer): target.name=value))
	_check("Visible",layer.visible,func(value: bool): _edit_layer("Toggle visibility",func(target: KiwiCompositeLayer): target.visible=value))
	_check("Lock",layer.locked,func(value: bool): _edit_layer("Lock layer",func(target: KiwiCompositeLayer): target.locked=value))
	var display_position: Vector2=document.sample_layer_value(layer.id,"position",preview_time,layer.position); var display_rotation: float=document.sample_layer_value(layer.id,"rotation",preview_time,layer.rotation); var display_scale: Vector2=document.sample_layer_value(layer.id,"scale",preview_time,layer.scale); var display_opacity: float=document.sample_layer_value(layer.id,"opacity",preview_time,layer.opacity)
	_number("Opacity",display_opacity,0.,1.,.01,func(value: float): _set_animated_property("opacity",value))
	_number("X",display_position.x,-10000.,10000.,1.,func(value: float): var current: Vector2=document.sample_layer_value(layer.id,"position",preview_time,layer.position); current.x=value; _set_animated_property("position",current))
	_number("Y",display_position.y,-10000.,10000.,1.,func(value: float): var current: Vector2=document.sample_layer_value(layer.id,"position",preview_time,layer.position); current.y=value; _set_animated_property("position",current))
	_number("Rotation",rad_to_deg(display_rotation),-3600.,3600.,1.,func(value: float): _set_animated_property("rotation",deg_to_rad(value)))
	_number("Scale X",display_scale.x,.01,100.,.01,func(value: float): var current: Vector2=document.sample_layer_value(layer.id,"scale",preview_time,layer.scale); current.x=value; _set_animated_property("scale",current))
	_number("Scale Y",display_scale.y,.01,100.,.01,func(value: float): var current: Vector2=document.sample_layer_value(layer.id,"scale",preview_time,layer.scale); current.y=value; _set_animated_property("scale",current))
	var key_section:=Label.new(); key_section.text="ANIMATION · %.3f s"%preview_time; inspector.add_child(key_section)
	var key_button:=_button(inspector,"Set transform & opacity keys",func(): _key_layer_transform(layer),"Key position, rotation, scale and opacity at the current playhead"); key_button.custom_minimum_size.y=24
	var keyed_properties:=PackedStringArray()
	for property in ["position","rotation","scale","opacity"]:
		if document.has_layer_track(layer.id,property): keyed_properties.append(property.capitalize())
	var key_summary:=Label.new(); key_summary.text="Animated: "+(", ".join(keyed_properties) if not keyed_properties.is_empty() else "None"); inspector.add_child(key_summary)
	_number("Timeline start",layer.start_time,0.,layer.end_time if layer.end_time>=0. else document.duration,.01,func(value: float): _edit_layer("Move layer in time",func(target: KiwiCompositeLayer): target.start_time=value))
	_number("Timeline end",layer.end_time if layer.end_time>=0. else document.duration,layer.start_time,document.duration,.01,func(value: float): _edit_layer("Trim layer in time",func(target: KiwiCompositeLayer): target.end_time=value))
	if layer.kind==KiwiCompositeLayer.Kind.SOLID: _color("Color",layer.color,func(value: Color): _edit_layer("Change solid color",func(target: KiwiCompositeLayer): target.color=value))
	if layer.kind==KiwiCompositeLayer.Kind.SHAPE:
		var shape_picker:=OptionButton.new(); for shape_name in ["rectangle","ellipse","triangle","polygon"]: shape_picker.add_item(shape_name.capitalize())
		var shape_index:=maxi(0,["rectangle","ellipse","triangle","polygon"].find(str(layer.settings.get("shape","rectangle")))); shape_picker.select(shape_index); inspector.add_child(shape_picker); shape_picker.item_selected.connect(func(value: int): _edit_layer("Change shape",func(target: KiwiCompositeLayer): target.settings["shape"]=["rectangle","ellipse","triangle","polygon"][value]))
		_number("Width",float(layer.settings.get("size",Vector2i(256,256)).x),1.,4096.,1.,func(value: float): _edit_layer("Resize shape",func(target: KiwiCompositeLayer): var size: Vector2i=target.settings.get("size",Vector2i(256,256)); size.x=int(value); target.settings["size"]=size))
		_number("Height",float(layer.settings.get("size",Vector2i(256,256)).y),1.,4096.,1.,func(value: float): _edit_layer("Resize shape",func(target: KiwiCompositeLayer): var size: Vector2i=target.settings.get("size",Vector2i(256,256)); size.y=int(value); target.settings["size"]=size))
		_color("Fill",layer.color,func(value: Color): _edit_layer("Change shape color",func(target: KiwiCompositeLayer): target.color=value))
	if layer.kind==KiwiCompositeLayer.Kind.TEXT:
		_line("Text",str(layer.settings.get("text","Text")),func(value: String): _edit_layer("Change text",func(target: KiwiCompositeLayer): target.settings["text"]=value))
		_number("Font size",float(layer.settings.get("font_size",72)),1.,512.,1.,func(value: float): _edit_layer("Change text size",func(target: KiwiCompositeLayer): target.settings["font_size"]=int(value)))
		_line("Font resource path",str(layer.settings.get("font_path","")),func(value: String): _edit_layer("Change text font",func(target: KiwiCompositeLayer): target.settings["font_path"]=value))
		_color("Text color",layer.color,func(value: Color): _edit_layer("Change text color",func(target: KiwiCompositeLayer): target.color=value))
	if layer.kind==KiwiCompositeLayer.Kind.ADJUSTMENT:
		for setting in [["Exposure","exposure",-16.,16.,.05],["Brightness","brightness",-2.,2.,.01],["Contrast","contrast",0.,4.,.01],["Saturation","saturation",0.,4.,.01],["Temperature","temperature",-1.,1.,.01],["Tint","tint",-1.,1.,.01]]: _number(setting[0],float(layer.settings.get(setting[1],1. if setting[1] in ["contrast","saturation"] else 0.)),setting[2],setting[3],setting[4],func(value: float): _edit_layer("Change adjustment",func(target: KiwiCompositeLayer): target.settings[setting[1]]=value))
		_curve_controls(inspector,layer.settings.get("curves",{}),func(value: Dictionary): layer.settings["curves"]=value; evaluator.clear_cache(); _render())
	if layer.kind==KiwiCompositeLayer.Kind.IMAGE: _line("Source",layer.source_path,func(value: String): _edit_layer("Change image source",func(target: KiwiCompositeLayer): target.source_path=value))
	if layer.kind==KiwiCompositeLayer.Kind.VIDEO:
		_line("Video source",layer.source_path,func(value: String): _edit_layer("Change video source",func(target: KiwiCompositeLayer): target.source_path=value))
		_number("Source offset",layer.source_time_offset,0.,100000.,.01,func(value: float): _edit_layer("Change video source offset",func(target: KiwiCompositeLayer): target.source_time_offset=value))
		_number("Playback speed",layer.playback_speed,.01,100.,.01,func(value: float): _edit_layer("Change video playback speed",func(target: KiwiCompositeLayer): target.playback_speed=value))
	var blend:=OptionButton.new(); blend.add_item("Over")
	for name in ["Under","In","Out","Atop","Add","Subtract","Multiply","Screen","Difference","Minimum","Maximum","Crossfade"]: blend.add_item(name)
	blend.select(layer.blend_mode); inspector.add_child(blend); blend.item_selected.connect(func(value: int): _edit_layer("Change blend mode",func(target: KiwiCompositeLayer): target.blend_mode=value))

func _refresh_graph_inspector() -> void:
	var graph:=_graph_by_id(document.active_graph_id); var node:=graph.node(selected_graph_node_id) if graph!=null else null
	if node==null: selected_graph_node_id=""; var empty:=Label.new(); empty.text="Select a node to edit its settings."; inspector.add_child(empty); return
	var title:=Label.new(); title.text="NODE · "+node.kind; inspector.add_child(title)
	match node.kind:
		"Image Source": _line("Image path",str(node.settings.get("path","")),func(value: String): _set_graph_setting(node,"path",value))
		"Layer Source":
			var layer_picker:=OptionButton.new(); inspector.add_child(layer_picker); var selected:=0; var index:=0
			for layer in document.layers:
				layer_picker.add_item(layer.name); layer_picker.set_item_metadata(index,layer.id); if layer.id==str(node.settings.get("layer_id","")): selected=index
				index+=1
			if layer_picker.item_count>0: layer_picker.select(selected)
			layer_picker.item_selected.connect(func(value: int): _set_graph_setting(node,"layer_id",str(layer_picker.get_item_metadata(value))))
		"Solid Color": _color("Color",node.settings.get("color",Color.WHITE),func(value: Color): _set_graph_setting(node,"color",value))
		"Color Grade":
			for setting in [["Exposure","exposure",-16.,16.,.05],["Brightness","brightness",-2.,2.,.01],["Contrast","contrast",0.,4.,.01],["Saturation","saturation",0.,4.,.01]]: _number(setting[0],float(node.settings.get(setting[1],1. if setting[1] in ["contrast","saturation"] else 0.)),setting[2],setting[3],setting[4],func(value: float): _set_graph_setting(node,setting[1],value))
			_curve_controls(inspector,node.settings.get("curves",{}),func(value: Dictionary): node.settings["curves"]=value; evaluator.clear_cache(); _render())
		"Merge":
			var modes:=OptionButton.new(); for name in ["Over","Under","In","Out","Atop","Add","Subtract","Multiply","Screen","Difference","Minimum","Maximum"]: modes.add_item(name)
			modes.select(int(node.settings.get("mode",0))); inspector.add_child(modes); modes.item_selected.connect(func(value: int): _set_graph_setting(node,"mode",value))
			_number("Opacity",float(node.settings.get("opacity",1.)),0.,1.,.01,func(value: float): _set_graph_setting(node,"opacity",value))
		"Blur": _number("Radius",float(node.settings.get("radius",2)),0.,32.,1.,func(value: float): _set_graph_setting(node,"radius",int(value)))
		"Mask":
			var note:=Label.new(); note.text="Connect an RGBA image and an alpha mask."; note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; inspector.add_child(note)
		"Chroma Key":
			_color("Key color",node.settings.get("key_color",Color.GREEN),func(value: Color): _set_graph_setting(node,"key_color",value))
			_number("Tolerance",float(node.settings.get("tolerance",.2)),0.,2.,.01,func(value: float): _set_graph_setting(node,"tolerance",value))
			_number("Softness",float(node.settings.get("softness",.1)),.001,1.,.01,func(value: float): _set_graph_setting(node,"softness",value))
			_number("Spill",float(node.settings.get("spill",.5)),0.,1.,.01,func(value: float): _set_graph_setting(node,"spill",value))
		"Luma Key":
			_number("Low threshold",float(node.settings.get("low",.1)),0.,1.,.01,func(value: float): _set_graph_setting(node,"low",value))
			_number("High threshold",float(node.settings.get("high",.9)),0.,1.,.01,func(value: float): _set_graph_setting(node,"high",value))
			_number("Softness",float(node.settings.get("softness",.05)),.001,1.,.01,func(value: float): _set_graph_setting(node,"softness",value))
			_check("Invert matte",bool(node.settings.get("invert",false)),func(value: bool): _set_graph_setting(node,"invert",value))
		"Depth Compare":
			var note:=Label.new(); note.text="Depth comparison is not available in the preview evaluator yet."; note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; inspector.add_child(note)

func _set_graph_setting(node: KiwiCompositeGraphNode,key: String,value: Variant) -> void:
	var before: KiwiCompositingDocument=document.duplicate(true); node.settings[key]=value; _commit("Change "+node.kind+" settings",before)

func _curve_controls(parent: Control,initial: Dictionary,apply: Callable) -> void:
	var header:=Label.new(); header.text="CHANNEL CURVES"; parent.add_child(header)
	var channels:=OptionButton.new()
	for name in ["Master","Red","Green","Blue"]: channels.add_item(name)
	parent.add_child(channels)
	var editor=CompositeCurveEditor.new(); parent.add_child(editor)
	var curves: Dictionary=initial.duplicate(true)
	var channel_names: Array[String]=["master","red","green","blue"]
	var active_channel: String="master"
	var before_edit: Array[KiwiCompositingDocument]=[]
	var load_channel:=func(index: int) -> void:
		active_channel=channel_names[index]
		var values: Array=curves.get(active_channel,[])
		editor.set_points(values)
	channels.item_selected.connect(load_channel)
	load_channel.call(0)
	editor.edit_started.connect(func(): before_edit.clear(); before_edit.append(document.duplicate(true)))
	editor.points_changed.connect(func(value: Array): curves[active_channel]=value; apply.call(curves.duplicate(true)))
	editor.edit_finished.connect(func():
		if not before_edit.is_empty(): _commit("Edit "+active_channel.capitalize()+" curve",before_edit.pop_back())
	)

func _line(caption: String,value: String,callback: Callable) -> void:
	var row:=VBoxContainer.new(); inspector.add_child(row); var label:=Label.new(); label.text=caption; row.add_child(label); var edit:=LineEdit.new(); edit.text=value; row.add_child(edit); edit.text_submitted.connect(callback)
func _number(caption: String,value: float,minimum: float,maximum: float,step: float,callback: Callable) -> void:
	var row:=HBoxContainer.new(); inspector.add_child(row); var label:=Label.new(); label.text=caption; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label); var spin:=SpinBox.new(); spin.min_value=minimum; spin.max_value=maximum; spin.step=step; spin.value=value; spin.custom_minimum_size.x=105; row.add_child(spin); spin.value_changed.connect(callback)
func _check(caption: String,value: bool,callback: Callable) -> void:
	var control:=CheckButton.new(); control.text=caption; control.button_pressed=value; inspector.add_child(control); control.toggled.connect(callback)
func _color(caption: String,value: Color,callback: Callable) -> void:
	var control:=ColorPickerButton.new(); control.text=caption; control.color=value; inspector.add_child(control); control.color_changed.connect(callback)

func _edit_layer(label: String,edit: Callable) -> void:
	var target:=document.layer(selected_id); if target==null: return
	var snapshot: KiwiCompositingDocument=document.duplicate(true); edit.call(target); _commit(label,snapshot)

func _set_animated_property(property: String,value: Variant) -> void:
	var target:=document.layer(selected_id)
	if target==null: return
	if document.has_layer_track(target.id,property):
		var snapshot: KiwiCompositingDocument=document.duplicate(true); document.set_layer_key(target.id,property,preview_time,value); _commit("Set "+property+" key",snapshot)
	else:
		_edit_layer("Change "+property,func(layer: KiwiCompositeLayer): layer.set(property,value))

func _key_layer_transform(layer: KiwiCompositeLayer) -> void:
	var target:=document.layer(layer.id)
	if target==null: return
	var snapshot: KiwiCompositingDocument=document.duplicate(true)
	var position: Vector2=document.sample_layer_value(target.id,"position",preview_time,target.position); var rotation: float=document.sample_layer_value(target.id,"rotation",preview_time,target.rotation); var scale: Vector2=document.sample_layer_value(target.id,"scale",preview_time,target.scale); var opacity: float=document.sample_layer_value(target.id,"opacity",preview_time,target.opacity)
	for entry in [["position",position],["rotation",rotation],["scale",scale],["opacity",opacity]]: document.set_layer_key(target.id,entry[0],preview_time,entry[1])
	_commit("Set transform and opacity keys",snapshot)

func _commit(label: String,snapshot: KiwiCompositingDocument) -> void:
	if document.signature()==snapshot.signature(): return
	_history.append(snapshot); if _history.size()>100: _history.pop_front(); _redo.clear(); _changed(label)

func _changed(message: String) -> void:
	dirty=true; evaluator.clear_cache(); status.text=message; _refresh_ui(); _render(); document_changed.emit()

func _add_layer(kind: int) -> void:
	var before: KiwiCompositingDocument=document.duplicate(true); var layer:=document.add_layer(kind,["Image","Solid Color","Video","CGI","VFX","Text","Shape","Mask","Adjustment","Group","Linked Composition"][kind]); selected_id=layer.id
	if kind==KiwiCompositeLayer.Kind.SOLID: layer.color=Color(.2,.24,.3,1.)
	elif kind==KiwiCompositeLayer.Kind.ADJUSTMENT: layer.settings={"exposure":0.,"brightness":0.,"contrast":1.,"saturation":1.}
	elif kind==KiwiCompositeLayer.Kind.SHAPE: layer.settings={"shape":"rectangle","size":Vector2i(256,256)}; layer.color=Color.WHITE
	elif kind==KiwiCompositeLayer.Kind.TEXT: layer.settings={"text":"Text","font_size":72,"size":Vector2i(640,180)}; layer.color=Color.WHITE
	_commit("Add layer",before)

func _delete_layer() -> void:
	var index:=-1
	for i in document.layers.size():
		if document.layers[i].id==selected_id: index=i; break
	if index<0: return
	var before: KiwiCompositingDocument=document.duplicate(true); var remove_ids:={selected_id:true}; var changed:=true
	while changed:
		changed=false
		for item in document.layers:
			if item!=null and remove_ids.has(item.parent_id) and not remove_ids.has(item.id): remove_ids[item.id]=true; changed=true
	for i in range(document.layers.size()-1,-1,-1):
		if remove_ids.has(document.layers[i].id): document.layers.remove_at(i)
	for i in range(document.animation.size()-1,-1,-1):
		if remove_ids.has(str(document.animation[i].get("layer_id",""))): document.animation.remove_at(i)
	if document.solo_layer_id in remove_ids: document.solo_layer_id=""
	selected_id=""; _commit("Delete layer",before)

func _selected_layer_ids() -> Array[String]:
	var ids: Array[String]=[]
	var item:=layer_tree.get_next_selected(null)
	while item!=null:
		var id:=str(item.get_metadata(0)); if not id.is_empty() and document.layer(id)!=null: ids.append(id)
		item=layer_tree.get_next_selected(item)
	if ids.is_empty() and document.layer(selected_id)!=null: ids.append(selected_id)
	return ids

func _duplicate_layer() -> void:
	var target:=document.layer(selected_id)
	if target==null: return
	var before: KiwiCompositingDocument=document.duplicate(true)
	var remap: Dictionary={target.id:ActorData.new_id()}; var expanded:=true
	while expanded:
		expanded=false
		for item in document.layers:
			if remap.has(item.parent_id) and not remap.has(item.id): remap[item.id]=ActorData.new_id(); expanded=true
	var copies: Array[KiwiCompositeLayer]=[]
	for item in document.layers:
		if not remap.has(item.id): continue
		var copy:=item.duplicate(true) as KiwiCompositeLayer
		copy.id=remap[item.id]; copy.name+=" Copy"; copy.parent_id=remap.get(item.parent_id,item.parent_id); copy.mask_id=remap.get(item.mask_id,item.mask_id)
		copy.processing_graph_id=_clone_processing_graph(item.processing_graph_id,copy.id); copies.append(copy)
		var graph:=_graph_by_id(copy.processing_graph_id)
		if graph!=null:
			for node in graph.nodes:
				if node.kind=="Layer Source": node.settings["layer_id"]=remap.get(str(node.settings.get("layer_id","")),node.settings.get("layer_id",""))
	var copied_tracks: Array[Dictionary]=[]
	for track in document.animation:
		var owner:=str(track.get("layer_id",""))
		if remap.has(owner):
			var copied: Dictionary=track.duplicate(true); copied["layer_id"]=remap[owner]; copied_tracks.append(copied)
	document.layers.append_array(copies); document.animation.append_array(copied_tracks); selected_id=remap[target.id]; _commit("Duplicate layer hierarchy",before)

func _move_layer(direction: int) -> void:
	var target:=document.layer(selected_id); if target==null: return
	var index:=document.layers.find(target); var destination:=index+direction
	if destination<0 or destination>=document.layers.size(): return
	if document.layers[destination].parent_id!=target.parent_id: return
	var before: KiwiCompositingDocument=document.duplicate(true); document.layers.remove_at(index); document.layers.insert(destination,target); _commit("Reorder layer",before)

func _group_layers() -> void:
	var ids:=_selected_layer_ids(); if ids.size()<2: status.text="Select at least two layers to group."; return
	var parent_id:=document.layer(ids[0]).parent_id
	for id in ids:
		if document.layer(id).parent_id!=parent_id: status.text="Group layers that share the same parent."; return
	var before: KiwiCompositingDocument=document.duplicate(true); var group:=document.add_layer(KiwiCompositeLayer.Kind.GROUP,"Group"); group.parent_id=parent_id
	for id in ids: document.layer(id).parent_id=group.id
	selected_id=group.id; _commit("Group layers",before)

func _ungroup_layer() -> void:
	var group:=document.layer(selected_id); if group==null or group.kind!=KiwiCompositeLayer.Kind.GROUP: return
	var before: KiwiCompositingDocument=document.duplicate(true); var parent_id:=group.parent_id
	for item in document.layers:
		if item!=null and item.parent_id==group.id: item.parent_id=parent_id
	var index:=document.layers.find(group); document.layers.remove_at(index); selected_id=""; _commit("Ungroup layers",before)

func _copy_layer() -> void:
	var layer:=document.layer(selected_id)
	if layer==null: return
	_hierarchy_clipboard=document.duplicate(true); _hierarchy_clipboard_root=layer.id
	status.text="Copied "+layer.name

func _paste_layer() -> void:
	if _hierarchy_clipboard==null: status.text="Copy a layer first."; return
	var before: KiwiCompositingDocument=document.duplicate(true)
	var remap: Dictionary={_hierarchy_clipboard_root:ActorData.new_id()}; var expanded:=true
	while expanded:
		expanded=false
		for item in _hierarchy_clipboard.layers:
			if remap.has(item.parent_id) and not remap.has(item.id): remap[item.id]=ActorData.new_id(); expanded=true
	for item in _hierarchy_clipboard.layers:
		if not remap.has(item.id): continue
		var copy:=item.duplicate(true) as KiwiCompositeLayer; copy.id=remap[item.id]; copy.parent_id=remap.get(item.parent_id,""); copy.mask_id=remap.get(item.mask_id,""); copy.processing_graph_id=""
		for source_graph in _hierarchy_clipboard.graphs:
			if source_graph.id==item.processing_graph_id:
				copy.processing_graph_id=_clone_graph(source_graph,copy.id)
				var graph:=_graph_by_id(copy.processing_graph_id)
				for node in graph.nodes:
					if node.kind=="Layer Source": node.settings["layer_id"]=remap.get(str(node.settings.get("layer_id","")),node.settings.get("layer_id",""))
		document.layers.append(copy)
	for track in _hierarchy_clipboard.animation:
		var owner:=str(track.get("layer_id",""))
		if remap.has(owner):
			var copied: Dictionary=track.duplicate(true); copied["layer_id"]=remap[owner]; document.animation.append(copied)
	selected_id=remap[_hierarchy_clipboard_root]; _commit("Paste layer hierarchy",before)

func _clone_processing_graph(id: String,new_layer_id: String) -> String:
	var graph:=_graph_by_id(id)
	return _clone_graph(graph,new_layer_id) if graph!=null else ""

func _clone_graph(source_graph: KiwiCompositeGraph,new_layer_id: String) -> String:
	var copy:=source_graph.duplicate(true) as KiwiCompositeGraph; copy.id=ActorData.new_id(); copy.name+=" Copy"; var remap: Dictionary={}
	for node in copy.nodes:
		var old_id:=node.id; node.id=ActorData.new_id(); remap[old_id]=node.id
	for edge in copy.connections: edge.from_node=remap.get(edge.from_node,edge.from_node); edge.to_node=remap.get(edge.to_node,edge.to_node)
	copy.output_node=remap.get(copy.output_node,copy.output_node); document.graphs.append(copy); return copy.id

func _toggle_solo() -> void:
	var before: KiwiCompositingDocument=document.duplicate(true); document.solo_layer_id="" if document.solo_layer_id==selected_id else selected_id; _commit("Solo layer",before)

func choose_image() -> void: _file_dialog.popup_centered(Vector2i(640,440))
func _image_selected(source_path: String) -> void:
	var before: KiwiCompositingDocument=document.duplicate(true); var layer:=document.add_layer(KiwiCompositeLayer.Kind.IMAGE,source_path.get_file().get_basename()); layer.source_path=source_path; selected_id=layer.id; _commit("Add image layer",before)

func choose_video() -> void: _video_dialog.popup_centered(Vector2i(680,460))

func _video_selected(source_path: String) -> void:
	var metadata:=ActorVideo.info(source_path)
	if metadata.is_empty(): status.text="The video could not be opened. Check the format and FFmpeg setup."; return
	var before: KiwiCompositingDocument=document.duplicate(true); var layer:=document.add_layer(KiwiCompositeLayer.Kind.VIDEO,source_path.get_file().get_basename()); layer.source_path=source_path; layer.end_time=minf(float(metadata.duration),document.duration); selected_id=layer.id; _commit("Add video footage layer",before)

func _choose_export_video() -> void: _export_dialog.current_file=document.title.validate_filename()+".mp4"; _export_dialog.popup_centered(Vector2i(740,480))

func export_video(destination: String) -> bool:
	var encoder:=ActorVideo.executable("ffmpeg")
	if encoder.is_empty(): status.text="Video export requires FFmpeg; no source media has been changed."; return false
	var folder: String="user://compositing_render_"+ActorData.new_id(); var absolute_folder:=ProjectSettings.globalize_path(folder); DirAccess.make_dir_recursive_absolute(absolute_folder)
	var frames:=maxi(1,ceili(document.duration*document.frame_rate)); var frame_pattern:=absolute_folder.path_join("frame_%06d.png")
	for index in frames:
		var time:=float(index)/document.frame_rate; evaluator.clear_cache(); var buffer:=evaluator.evaluate(document,time)
		if buffer==null:
			status.text="Video render stopped at frame %d: %s"%[index,evaluator.last_error]; _remove_render_frames(absolute_folder,frames); return false
		var image:=_display_preview(buffer.image); var frame_path:=absolute_folder.path_join("frame_%06d.png"%index); var error:=image.save_png(frame_path)
		if error!=OK: status.text="Could not write rendered frame %d."%index; _remove_render_frames(absolute_folder,frames); return false
		status.text="Rendering frame %d / %d"%[index+1,frames]
		await get_tree().process_frame
	var absolute_output:=ProjectSettings.globalize_path(destination); var arguments:=PackedStringArray(["-nostdin","-v","error","-y","-framerate",str(document.frame_rate),"-start_number","0","-i",frame_pattern,"-frames:v",str(frames),"-c:v","libx264","-pix_fmt","yuv420p","-movflags","+faststart",absolute_output]); var output: Array=[]; var exit_code:=OS.execute(encoder,arguments,output,true)
	_remove_render_frames(absolute_folder,frames)
	if exit_code!=0 or not FileAccess.file_exists(destination): status.text="Video export failed. FFmpeg: "+" ".join(output); return false
	status.text="Video exported · silent MP4 · "+destination; return true

func choose_sequence_export(format: String) -> void:
	var dialog:=FileDialog.new(); dialog.file_mode=FileDialog.FILE_MODE_OPEN_DIR; dialog.access=FileDialog.ACCESS_FILESYSTEM; dialog.title="Export "+format.to_upper()+" sequence"; add_child(dialog)
	dialog.dir_selected.connect(func(folder: String): export_sequence(folder,format); dialog.queue_free()); dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(Vector2i(740,480))

func export_sequence(folder: String,format: String="png") -> bool:
	if format not in ["png","exr"]: status.text="Choose PNG or EXR output."; return false
	var frames:=maxi(1,ceili(document.duration*document.frame_rate)); var absolute:=ProjectSettings.globalize_path(folder)
	if DirAccess.make_dir_recursive_absolute(absolute)!=OK: status.text="Cannot create sequence directory."; return false
	var prefix:=document.title.validate_filename()+"_"
	for index in frames:
		if FileAccess.file_exists(absolute.path_join(prefix+"%06d."%index+format)): status.text="Sequence files already exist. Choose another directory."; return false
	for index in frames:
		var buffer:=evaluator.evaluate(document,float(index)/document.frame_rate)
		if buffer==null: status.text="Sequence stopped: "+evaluator.last_error; return false
		var image:=buffer.image if format=="exr" else _display_preview(buffer.image)
		var destination:=absolute.path_join(prefix+"%06d."%index+format)
		var error:=image.save_exr(destination,false) if format=="exr" else image.save_png(destination)
		if error!=OK: status.text="Sequence write failed: "+error_string(error); return false
		status.text="Sequence frame %d / %d"%[index+1,frames]; await get_tree().process_frame
	status.text="Exported "+format.to_upper()+" sequence · "+folder; return true

func _remove_render_frames(folder: String,frame_count: int) -> void:
	for index in frame_count: DirAccess.remove_absolute(folder.path_join("frame_%06d.png"%index))
	DirAccess.remove_absolute(folder)

func _render() -> void:
	if document==null: return
	_video_retry_elapsed=0.
	var size:=document.canvas_size; var factor:=minf(1.,1024./maxi(size.x,size.y)); var preview: KiwiCompositingDocument=document.duplicate(true)
	if factor<1.:
		preview.canvas_size=Vector2i(maxi(1,roundi(size.x*factor)),maxi(1,roundi(size.y*factor)))
		for layer in preview.layers: layer.position*=factor; layer.scale*=factor
		for track in preview.animation:
			if str(track.get("property","")) in ["position","scale"]:
				for key in track.get("keys",[]):
					if key.get("value") is Vector2: key["value"]*=factor
	var result:=evaluator.evaluate(preview,preview_time)
	if mode==1:
		var active_graph:=_graph_by_id(preview.active_graph_id)
		if active_graph!=null:
			result=evaluator.evaluate_node_output(preview,active_graph,selected_graph_node_id,preview_time) if not selected_graph_node_id.is_empty() else evaluator.evaluate_graph(preview,active_graph,preview_time)
	if result==null: status.text=evaluator.last_error; return
	image_view.texture=ImageTexture.create_from_image(_display_preview(result.image)); status.text="Preview ready · %d nodes"%evaluator.nodes_evaluated

func _time_changed(value: float) -> void:
	preview_time=clampf(value,0.,document.duration); time_spin.set_value_no_signal(preview_time); time_slider.set_value_no_signal(preview_time); evaluator.clear_cache()
	_refresh_time_dependent_inspector()
	_render()

func _toggle_play() -> void:
	if play_timer.is_stopped(): play_timer.start()
	else: play_timer.stop()

func _advance_time() -> void:
	preview_time+=1.0/document.frame_rate
	if preview_time>document.duration: preview_time=0.
	time_spin.set_value_no_signal(preview_time); time_slider.set_value_no_signal(preview_time); _refresh_time_dependent_inspector(); _render()

func _refresh_time_dependent_inspector() -> void:
	if mode!=0: return
	var selected:=document.layer(selected_id)
	if selected!=null and ["position","rotation","scale","opacity"].any(func(property: String): return document.has_layer_track(selected.id,property)): _refresh_inspector()

func _display_preview(source_image: Image) -> Image:
	var input:=source_image.duplicate(); input.convert(Image.FORMAT_RGBAF); var image:=Image.create(input.get_width(),input.get_height(),false,Image.FORMAT_RGBA8)
	for y in input.get_height():
		for x in input.get_width():
			var color: Color=input.get_pixel(x,y); var display:=Color(color.r,color.g,color.b).linear_to_srgb(); image.set_pixel(x,y,Color(clampf(display.r,0.,1.),clampf(display.g,0.,1.),clampf(display.b,0.,1.),clampf(color.a,0.,1.)))
	return image

func _refresh_graph() -> void:
	# GraphEdit's connection renderer is initialized after it enters the scene tree.
	# Defer model-to-view synchronization so first-frame tab construction cannot hit
	# the native connections_layer before it has been created.
	if not graph_edit.is_inside_tree(): return
	if not graph_edit.is_node_ready():
		_refresh_graph.call_deferred(); return
	graph_edit.clear_connections()
	for node in graph_edit.get_children():
		# GraphEdit keeps its connection renderer as a required child. Only remove
		# graph nodes created by this workspace; dropping the renderer breaks every
		# later connection refresh and leaves a blank editor.
		if node is GraphNode:
			graph_edit.remove_child(node); node.queue_free()
	var graph:=_graph_by_id(document.active_graph_id)
	if graph==null and not document.graphs.is_empty(): graph=document.graphs[0]
	if graph==null: return
	var visual_by_id: Dictionary={}
	for index in graph.nodes.size():
		var model_node:=graph.nodes[index]; var visual:=GraphNode.new(); visual.name="CompositeNode%d"%index; visual.title=model_node.kind; visual.position_offset=model_node.position; visual.set_meta("composite_id",model_node.id); graph_edit.add_child(visual); visual_by_id[model_node.id]=visual.name
		var inputs:=_graph_inputs(model_node.kind); var outputs:=_graph_outputs(model_node.kind); var rows:=maxi(1,maxi(inputs.size(),outputs.size())); var input_indices:={}; var output_indices:={}
		for row_index in rows:
			var row:=HBoxContainer.new(); visual.add_child(row); var input_label:=Label.new(); input_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; var output_label:=Label.new(); output_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT; output_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			var has_input:=row_index<inputs.size(); var has_output:=row_index<outputs.size()
			if has_input: input_label.text=str(inputs[row_index]); input_indices[str(inputs[row_index])]=row_index
			if has_output: output_label.text=str(outputs[row_index]); output_indices[str(outputs[row_index])]=row_index
			row.add_child(input_label); row.add_child(output_label); visual.set_slot(row_index,has_input,_port_type(str(inputs[row_index]) if has_input else ""),Color("74d9c4"),has_output,_port_type(str(outputs[row_index]) if has_output else ""),Color("74d9c4"))
		visual.set_meta("input_ports",input_indices); visual.set_meta("output_ports",output_indices)
		if model_node.id==selected_graph_node_id: visual.selected=true
	for edge in graph.connections:
		if not visual_by_id.has(edge.from_node) or not visual_by_id.has(edge.to_node): continue
		var from_node: GraphNode=graph_edit.get_node_or_null(str(visual_by_id[edge.from_node])); var to_node: GraphNode=graph_edit.get_node_or_null(str(visual_by_id[edge.to_node]))
		if from_node!=null and to_node!=null and from_node.get_meta("output_ports",{}).has(edge.from_port) and to_node.get_meta("input_ports",{}).has(edge.to_port): graph_edit.connect_node(from_node.name,int(from_node.get_meta("output_ports")[edge.from_port]),to_node.name,int(to_node.get_meta("input_ports")[edge.to_port]))

func _new_graph() -> void:
	if not document.graphs.is_empty(): document.active_graph_id=document.graphs[0].id; _set_mode(1); return
	var before: KiwiCompositingDocument=document.duplicate(true); var graph:=KiwiCompositeGraph.new(); var output:=KiwiCompositeGraphNode.new(); output.kind="Output"; output.position=Vector2(420,120); graph.nodes.append(output); graph.output_node=output.id; document.graphs.append(graph); document.active_graph_id=graph.id; mode=1; _commit("Create node graph",before); _set_mode(1)

func _open_layer_graph() -> void:
	var layer:=document.layer(selected_id)
	if layer==null: status.text="Select a layer first."; return
	var graph:=_graph_by_id(layer.processing_graph_id)
	if graph==null:
		var before: KiwiCompositingDocument=document.duplicate(true); graph=KiwiCompositeGraph.new(); graph.name=layer.name+" Processing"; var source_node:=KiwiCompositeGraphNode.new(); source_node.kind="Layer Source"; source_node.settings={"layer_id":layer.id}; source_node.position=Vector2(80,120); var output_node:=KiwiCompositeGraphNode.new(); output_node.kind="Output"; output_node.position=Vector2(420,120); graph.nodes.append(source_node); graph.nodes.append(output_node); graph.output_node=output_node.id; var edge:=KiwiCompositeGraphConnection.new(); edge.from_node=source_node.id; edge.from_port="image"; edge.to_node=output_node.id; edge.to_port="image"; graph.connections.append(edge); document.graphs.append(graph); layer.processing_graph_id=graph.id; _commit("Create layer processing graph",before)
	document.active_graph_id=graph.id; mode=1; _set_mode(1)

func _graph_by_id(id: String) -> KiwiCompositeGraph:
	for graph in document.graphs:
		if graph!=null and graph.id==id: return graph
	return null

func _graph_node_selected(node: Node) -> void:
	if _refreshing or node==null: return
	selected_graph_node_id=str(node.get_meta("composite_id","")); _refresh_inspector()

func _graph_node_deselected(node: Node) -> void:
	if _refreshing or node==null or str(node.get_meta("composite_id",""))!=selected_graph_node_id: return
	selected_graph_node_id=""; _refresh_inspector()

func _duplicate_graph_node() -> void:
	var graph:=_graph_by_id(document.active_graph_id); var node:=graph.node(selected_graph_node_id) if graph!=null else null
	if node==null: return
	var before: KiwiCompositingDocument=document.duplicate(true); var copy:=node.duplicate(true) as KiwiCompositeGraphNode; copy.id=ActorData.new_id(); copy.position+=Vector2(40,40); graph.nodes.append(copy); selected_graph_node_id=copy.id; _commit("Duplicate graph node",before)

func _delete_graph_node() -> void:
	var graph:=_graph_by_id(document.active_graph_id); var node:=graph.node(selected_graph_node_id) if graph!=null else null
	if node==null: return
	var before: KiwiCompositingDocument=document.duplicate(true)
	for index in range(graph.connections.size()-1,-1,-1):
		if graph.connections[index].from_node==node.id or graph.connections[index].to_node==node.id: graph.connections.remove_at(index)
	graph.nodes.erase(node)
	if graph.output_node==node.id: graph.output_node=""
	for layer in document.layers:
		if layer.processing_graph_id==graph.id: layer.processing_graph_id=""
	selected_graph_node_id=""; _commit("Delete graph node",before)

func _add_graph_node(kind: String) -> void:
	if document.graphs.is_empty(): _new_graph()
	var graph:=_graph_by_id(document.active_graph_id); if graph==null: graph=document.graphs[0]
	var before: KiwiCompositingDocument=document.duplicate(true); var node:=KiwiCompositeGraphNode.new(); node.kind=kind; node.position=Vector2(80+graph.nodes.size()*35,80+graph.nodes.size()*35)
	if kind=="Solid Color": node.settings={"color":Color.WHITE}
	if kind=="Image Source": node.settings={"path":""}
	if kind=="Layer Source": node.settings={"layer_id":selected_id}
	if kind=="Merge": node.settings={"mode":KiwiCompositeLayer.Blend.OVER,"opacity":1.}
	if kind=="Blur": node.settings={"radius":2}
	graph.nodes.append(node)
	if kind=="Output": graph.output_node=node.id
	selected_graph_node_id=node.id; _commit("Add "+kind+" node",before)

func _graph_inputs(kind: String) -> Array[String]:
	match kind:
		"Over","Merge": return ["foreground","background"]
		"Color Grade","Alpha Extract","Blur","Output": return ["image"]
		"Mask": return ["image","mask"]
		"Chroma Key","Luma Key": return ["image"]
		"Depth Compare": return ["image","depth"]
	return []

func _graph_outputs(kind: String) -> Array[String]:
	match kind:
		"Image Source","Layer Source","Solid Color","Over","Merge","Mask","Blur": return ["image"]
		"Chroma Key","Luma Key","Color Grade": return ["output"]
		"Alpha Extract": return ["mask"]
		"Depth Compare": return ["image","mask"]
	return []

func _port_type(port: String) -> int:
	return 1 if port=="mask" else (2 if port=="depth" else 0)

func _graph_connect_request(from_name: StringName,from_port: int,to_name: StringName,to_port: int) -> void:
	var source:=graph_edit.get_node_or_null(NodePath(from_name)) as GraphNode; var destination:=graph_edit.get_node_or_null(NodePath(to_name)) as GraphNode
	if source==null or destination==null or document.graphs.is_empty(): return
	var from_ports: Dictionary=source.get_meta("output_ports",{}); var to_ports: Dictionary=destination.get_meta("input_ports",{}); var from_key: String=""; var to_key: String=""
	for key in from_ports:
		if int(from_ports[key])==from_port: from_key=str(key)
	for key in to_ports:
		if int(to_ports[key])==to_port: to_key=str(key)
	if from_key.is_empty() or to_key.is_empty(): return
	var before: KiwiCompositingDocument=document.duplicate(true); var graph:=_graph_by_id(document.active_graph_id); if graph==null: return
	var edge:=KiwiCompositeGraphConnection.new(); edge.from_node=str(source.get_meta("composite_id")); edge.from_port=from_key; edge.to_node=str(destination.get_meta("composite_id")); edge.to_port=to_key; graph.connections.append(edge); var errors:=graph.validate()
	if not errors.is_empty(): document=before; status.text=errors[0]; _refresh_ui(); return
	graph_edit.connect_node(from_name,from_port,to_name,to_port); _commit("Connect compositing nodes",before)

func _graph_disconnect_request(from_name: StringName,from_port: int,to_name: StringName,to_port: int) -> void:
	var source:=graph_edit.get_node_or_null(NodePath(from_name)) as GraphNode; var destination:=graph_edit.get_node_or_null(NodePath(to_name)) as GraphNode
	if source==null or destination==null or document.graphs.is_empty(): return
	var from_ports: Dictionary=source.get_meta("output_ports",{}); var to_ports: Dictionary=destination.get_meta("input_ports",{}); var from_key: String=""; var to_key: String=""
	for key in from_ports:
		if int(from_ports[key])==from_port: from_key=str(key)
	for key in to_ports:
		if int(to_ports[key])==to_port: to_key=str(key)
	var before: KiwiCompositingDocument=document.duplicate(true); var graph:=_graph_by_id(document.active_graph_id); if graph==null: return
	for index in range(graph.connections.size()-1,-1,-1):
		var edge:=graph.connections[index]
		if edge.from_node==source.get_meta("composite_id") and edge.from_port==from_key and edge.to_node==destination.get_meta("composite_id") and edge.to_port==to_key: graph.connections.remove_at(index)
	graph_edit.disconnect_node(from_name,from_port,to_name,to_port); _commit("Disconnect compositing nodes",before)

func _graph_nodes_moved() -> void:
	if document.graphs.is_empty(): return
	var graph:=_graph_by_id(document.active_graph_id); if graph==null: return
	var changed:=false
	for visual: GraphNode in graph_edit.get_children():
		var id:=str(visual.get_meta("composite_id","")); var model_node:=graph.node(id)
		if model_node!=null and model_node.position!=visual.position_offset: model_node.position=visual.position_offset; changed=true
	if changed and _graph_move_before!=null: _commit("Move compositing nodes",_graph_move_before); _graph_move_before=null

func save() -> void:
	if not path.is_empty(): _save_path(path)
	else: save_as()
func save_as() -> void:
	var dialog:=FileDialog.new(); dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE; dialog.access=FileDialog.ACCESS_RESOURCES; dialog.add_filter("*.tres", "Kiwi Compositing Document"); dialog.current_file=document.title.validate_filename()+".tres"; add_child(dialog); dialog.file_selected.connect(func(destination: String): _save_path(destination); dialog.queue_free()); dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(Vector2i(650,440))
func _save_path(destination: String) -> void:
	var errors:=document.validate()
	if not errors.is_empty(): status.text="Cannot save: "+"; ".join(errors); return
	document.resource_name=document.title; var error:=ResourceSaver.save(document,destination)
	if error!=OK: status.text="Save failed: "+error_string(error); return
	path=destination; source=destination; dirty=false; status.text="Saved  ·  "+destination; composition_saved.emit(destination,document); document_changed.emit()

func undo() -> void:
	if _history.is_empty(): return
	_redo.append(document.duplicate(true)); document=_history.pop_back(); _changed("Undo")
func redo() -> void:
	if _redo.is_empty(): return
	_history.append(document.duplicate(true)); document=_redo.pop_back(); _changed("Redo")
