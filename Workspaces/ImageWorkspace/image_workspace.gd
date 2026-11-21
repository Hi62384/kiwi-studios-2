class_name KiwiImageWorkspace
extends Control
## Image Studio coordinates reusable document, renderer, and canvas modules.

signal document_changed
signal image_saved(source: Variant)

const IMAGE_EXTENSIONS := ["png","jpg","jpeg","webp","bmp","tga","svg","hdr","exr"]
const AVAILABLE_EFFECTS := ["mirror","curves","blur","motion_blur","radial_blur","sharpen","emboss","edge_detect","shadow","glow","outline","gradient_map","color_replace","grain","pixelate","halftone","scanlines","chromatic","vignette","wave","twirl","ripple","kaleidoscope"]
const SAVE_FORMATS := ["png","jpg","webp"]
const Layer = preload("res://Workspaces/ImageWorkspace/KiwiImageLayer.cs")
const Document = preload("res://Workspaces/ImageWorkspace/KiwiImageDocument.cs")
const Renderer = preload("res://Workspaces/ImageWorkspace/image_renderer.gd")
const Canvas = preload("res://Workspaces/ImageWorkspace/image_canvas.gd")

class PresetButton extends Button:
	var studio: KiwiImageWorkspace
	var kind: String
	var preset_id: String
	func _get_drag_data(_at: Vector2) -> Variant:
		var label:=Label.new(); label.text=tooltip_text.get_slice(" · ",0); set_drag_preview(label)
		return {"paint_preset":preset_id,"kind":kind}
	func _can_drop_data(_at: Vector2,data: Variant) -> bool:
		return data is Dictionary and data.get("kind","")==kind and data.has("paint_preset")
	func _drop_data(_at: Vector2,data: Variant) -> void:
		studio._move_preset(kind,str(data.paint_preset),preset_id)

class LayersTree extends Tree:
	var studio: Control
	func _get_drag_data(at: Vector2) -> Variant:
		var item := get_item_at_position(at)
		if item == null: return null
		var label := Label.new(); label.text="Move %d layer(s)" % studio.canvas.selected.size()
		set_drag_preview(label)
		return {"image_layers":studio.canvas.selected.duplicate()}
	func _can_drop_data(at: Vector2,data: Variant) -> bool:
		drop_mode_flags=Tree.DROP_MODE_INBETWEEN | Tree.DROP_MODE_ON_ITEM
		return data is Dictionary and data.has("image_layers") and get_item_at_position(at)!=null
	func _drop_data(at: Vector2,data: Variant) -> void:
		var item := get_item_at_position(at)
		if item != null: studio.reparent_layers(data.image_layers,str(item.get_metadata(0)),get_drop_section_at_position(at))

var document: KiwiImageDocument
var source: Variant
var path := ""
var document_path := ""
var image: Image
var renderer := Renderer.new()
var canvas := Canvas.new()
var layer_tree := LayersTree.new()
var inspector := VBoxContainer.new()
var context := HFlowContainer.new()
var _context_host: Container
var _flatten_cache: Image
var _edit_version:=0
var _pixel_prepare_generation:=0
var _tree_selection_pending:=false
var _inline_text_layer_id: String=""
var _inspector_tool_spacer:=Control.new()
var _toolbar_surface:=Control.new()
var _context_panel:=PanelContainer.new()
var _tree_main_id: String=""
var preset_context := HBoxContainer.new()
var preset_panel := PanelContainer.new()
var live_material_panel:=PanelContainer.new()
var live_material_row:=HBoxContainer.new()
var _preset_filter:="all"
var _paint_tool_settings: Dictionary={}
var _material_thumbnail_cache: Dictionary={}
var _material_thumbnail_requests: Array=[]
var _material_thumbnail_busy:=false
var _material_swatch: Button

var status := Label.new()
var title_label := Label.new()
var zoom_label: Button
var color_picker := ColorPickerButton.new()
var brush_size: DragNumber
var tool_buttons := {}
var _undo: Array[KiwiImageDocument] = []
var _redo: Array[KiwiImageDocument] = []
var _before: KiwiImageDocument
var _clipboard: Array[KiwiImageLayer] = []
var _style_clipboard: Dictionary = {}
var _syncing := false
var _refresh_pending := false
var _tree_pending := false
var _dirty := false
var _busy := false
var _layer_filter := ""
var _font_filter := ""
var _inspector_scroll := ScrollContainer.new()
var _side_split := VSplitContainer.new()
var _main_split := HSplitContainer.new()
var _icons := {}
var _text_input: TextEdit
var _commands: Array[Dictionary] = []
var _collapsed := {"Transform":true,"Mask":true}
var _last_enabled := false
var _presets: Dictionary = {}
var _recent_commands: Array[String] = []
var _crop_canvas := false
var _crop_action := 0 # 0 extract, 1 copy, 2 remove only
var _rasterizing := false
var _selection_fill_color:=Color.WHITE
var _sizing_preview := false
var _selection_transform_active:=false
var _context_fields: Dictionary = {}
var _paint_presets: Dictionary = {"brush":[],"eraser":[],"fill":[]}
var _active_preset: Dictionary = {"brush":"","eraser":"","fill":""}
var _last_command_name: String=""
var _macro_recording:=false
var _macro_buffer: Array[String]=[]
var _macros: Dictionary={}
var _variants: Dictionary={}
var _transform_clipboard: Dictionary={}
var _recent_assets: Array[String]=[]
var _effects_open:=false
var _effects_filter:=""
var _effects_signature:=""
var _effects_dock:=VBoxContainer.new()
var _effects_search:=LineEdit.new()
var _effects_scroll:=ScrollContainer.new()
var _effects_content:=VBoxContainer.new()
var _effects_button: Button
var _custom_shortcuts: Dictionary={}
const PAINT_PRESETS_PATH := "user://image_studio_paint_presets.tres"


func _ready() -> void:
	_native_workspace().ready(self)

func _build_theme() -> void:
	_native_workspace().build_theme(self)

func _box(fill: Color,border: Color,radius: int=8,padding: int=8) -> StyleBoxFlat:
	return _native_workspace().box(fill,border,radius,padding)

func _icon(name: String) -> Texture2D:
	return _native_workspace().icon(self,name)

func _button(parent: Node,text: String,action: Callable,tip: String="",icon_name: String="") -> Button:
	return _native_workspace().button(self,parent,text,action,tip,icon_name)

func _menu(parent: Node,label: String,items: Array) -> MenuButton:
	return _native_workspace().menu(self,parent,label,items)

func _build_ui() -> void:
	_native_workspace().build_ui(self)

func _process(_delta: float) -> void:
	_native_workspace().process(self)

func open_source(value: Variant,state: Dictionary={}) -> void:
	_native_workspace().open_source(self,value,state)

func capture_state() -> Dictionary:
	return _native_workspace().capture_state(self)

func _ui_state() -> Dictionary:
	return _native_workspace().ui_state(self)

func _begin() -> void:
	_native_workspace().begin(self)

func _preview() -> void:
	_native_workspace().preview(self)

func _commit() -> void:
	_native_workspace().commit(self)

func _sync_selection_transform() -> void:
	_native_workspace().sync_selection_transform(self)

func _cancel() -> void:
	_native_workspace().cancel(self)

func _finish_pending() -> void:
	_native_workspace().finish_pending(self)

func _action(operation: Callable) -> void:
	_native_workspace().action(self,operation)

func undo() -> void:
	_native_workspace().undo(self)

func redo() -> void:
	_native_workspace().redo(self)

func _restored() -> void:
	_native_workspace().restored(self)

func _update_title() -> void:
	_native_workspace().update_title(self)

func add_layer(kind: String) -> KiwiImageLayer:
	return _native_workspace().add_layer(self,kind)

func _add_layer_from_toolbar(kind: String) -> void:
	_native_workspace().add_layer_from_toolbar(self,kind)

func _show_add_layer() -> void:
	_native_workspace().show_add_layer(self)

func _create_layer_choice(kind: String,popup: PopupPanel) -> void:
	_native_workspace().create_layer_choice(self,kind,popup)

func _create_at(kind: String,bounds: Rect2,points: PackedVector2Array) -> void:
	_native_workspace().create_at(self,kind,bounds,points)

func _set_tool(id: String) -> void:
	if not _native_workspace().prepare_set_tool(self,id): return
	while canvas.repair_tool.active: await get_tree().process_frame
	_native_workspace().complete_set_tool(self,id)

func _tool_hint() -> String:
	return _native_workspace().tool_hint(self)

func _clear(parent: Node) -> void:
	_native_workspace().clear(parent)

func _tool_section(rail: Node,caption: String,entries: Array) -> void:
	_native_workspace().tool_section(self,rail,caption,entries)

func _refresh_context() -> void:
	_native_workspace().refresh_context(self)

func _context_color(caption: String,parent: Node=null) -> void:
	_native_workspace().context_color(self,caption,parent)

func _crop_controls() -> void:
	_native_workspace().crop_controls(self)

func _pixel_threshold_control(caption: String,value: float,changed: Callable) -> void:
	_native_workspace().pixel_threshold_control(self,caption,value,changed)

func _selection_mask_controls() -> void:
	_native_workspace().selection_mask_controls(self)

func _store_active_mask() -> void:
	_native_workspace().store_active_mask(self)

func _save_selection_mask(empty: bool,new_mask: bool=false) -> void:
	_native_workspace().save_selection_mask(self,empty,new_mask)

func _activate_selection_mask(id: String) -> void:
	_native_workspace().activate_selection_mask(self,id)

func _remove_selection_mask() -> void:
	_native_workspace().remove_selection_mask(self)

func _load_paint_presets(path: String=PAINT_PRESETS_PATH) -> void:
	_native_workspace().load_paint_presets(self,path)

func _preset(label: String,size: float,opacity: float,hardness_value: float,preset_color: Color,threshold: float=.08) -> Dictionary:
	return _native_workspace().preset(label,size,opacity,hardness_value,preset_color,threshold)

func _paint_preset_controls(kind: String) -> void:
	_native_workspace().paint_preset_controls(self,kind)

func _paint_preset_icon(preset: Dictionary,kind: String) -> Texture2D:
	return _native_workspace().paint_preset_icon(preset,kind)

func _apply_paint_preset(kind: String,preset: Dictionary) -> void:
	_native_workspace().apply_paint_preset(self,kind,preset)

func _save_paint_preset(kind: String,as_new: bool) -> void:
	_native_workspace().save_paint_preset(self,kind,as_new)

func _current_paint_preset(label: String) -> Dictionary:
	return _native_workspace().current_paint_preset(self,label)

func _delete_paint_preset(kind: String,id: String) -> void:
	_native_workspace().delete_paint_preset(self,kind,id)

func _persist_paint_presets(path: String=PAINT_PRESETS_PATH) -> void:
	_native_workspace().persist_paint_presets(self,path)

func _move_preset(kind: String,source_id: String,target_id: String) -> void:
	_native_workspace().move_preset(self,kind,source_id,target_id)

func _paint_selection_toggle() -> void:
	_native_workspace().paint_selection_toggle(self)

func _select_pixel_region(invert: bool) -> void:
	_finish_pending()
	await _prepare_pixel_selection()
	_native_workspace().select_pixel_region(self,invert)

func _set_adjustment_selection_only(enabled: bool) -> void:
	var request: Dictionary=_native_workspace().prepare_adjustment_selection(self,enabled)
	if request.is_empty(): return
	var mask: Texture2D
	if enabled: mask=await preload("res://Workspaces/ImageWorkspace/image_selection_fill.gd").capture_local_mask(self,request.layer)
	_native_workspace().complete_adjustment_selection(self,request,mask)

func _next_toolbar_row() -> void:
	_native_workspace().next_toolbar_row(self)

func _toolbar_group(caption: String,icon_name: String) -> HBoxContainer:
	return _native_workspace().toolbar_group(self,caption,icon_name)

func _toolbar_toggle(parent: Node,icon_name: String,enabled: bool,tip: String,changed: Callable) -> void:
	_native_workspace().toolbar_toggle(self,parent,icon_name,enabled,tip,changed)

func _compact_number(caption: String,value: float,setter: Callable,minimum: float=-100000,maximum: float=100000,parent: Node=null) -> DragNumber:
	return _native_workspace().compact_number(self,caption,value,setter,minimum,maximum,parent)

func _sync_context_values() -> void:
	_native_workspace().sync_context_values(self)

func _selection_changed() -> void:
	_native_workspace().selection_changed(self)

func _refresh_layers() -> void:
	_native_workspace().refresh_layers(self)

func _tree_children(parent: TreeItem,parent_id: String) -> void:
	_native_workspace().tree_children(self,parent,parent_id)

func _tree_selected(item: TreeItem,_column: int,_selected: bool) -> void:
	_native_workspace().tree_selected(self,item,_selected)

func _apply_tree_selection() -> void:
	_native_workspace().apply_tree_selection(self)

func _layer_button(item: TreeItem,_column: int,id: int,_mouse: int) -> void:
	_native_workspace().layer_button(self,item,id)

func _layer_context() -> void:
	_native_workspace().layer_context(self)

func _main_layer() -> KiwiImageLayer:
	return _native_workspace().main_layer(self)

func _section(label: String) -> VBoxContainer:
	return _native_workspace().section(self,label)

func _refresh_inspector() -> void:
	_native_workspace().refresh_inspector(self)

func _default_text_settings() -> ActorObjectData:
	return _native_workspace().default_text_settings()

func _save_polygon(points: PackedVector2Array) -> void:
	_native_workspace().save_polygon(self,points)

func _draw_custom_shape(layer: KiwiImageLayer) -> void:
	_native_workspace().draw_custom_shape(self,layer)

func _default_noise_image() -> ActorObjectData:
	return _native_workspace().default_noise_image()

func _noise_layer_property(layer: KiwiImageLayer) -> void:
	_native_workspace().noise_layer_property(self,layer)

func _set_noise_object_value(layer: KiwiImageLayer,key: StringName,value: Variant) -> void:
	_native_workspace().set_noise_object_value(layer,key,value)

func _refresh_noise_layer(layer: KiwiImageLayer) -> void:
	_native_workspace().refresh_noise_layer(layer)

func _load_noise_layer_object(layer: KiwiImageLayer) -> void:
	var property: ActorProperty=_native_workspace().object_picker_property("noise_image")
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Choose Noise Image")
	_native_workspace().object_picker_result(self,layer,"noise_image",chosen)

func _ensure_text_settings(layer: KiwiImageLayer) -> ActorObjectData:
	return _native_workspace().ensure_text_settings(layer)

func _text_settings_property(layer: KiwiImageLayer) -> void:
	_native_workspace().text_settings_property(self,layer)

func _set_text_setting(layer: KiwiImageLayer,key: StringName,value: Variant) -> void:
	_native_workspace().set_text_setting(layer,key,value)

func _set_text_setting_component(layer: KiwiImageLayer,key: StringName,component: int,value: float) -> void:
	_native_workspace().set_text_setting_component(layer,key,component,value)

func _choose_text_settings(layer: KiwiImageLayer) -> void:
	var property: ActorProperty=_native_workspace().object_picker_property("text_settings")
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Choose Text Settings")
	_native_workspace().object_picker_result(self,layer,"text_settings",chosen)

func _save_text_settings(layer: KiwiImageLayer) -> void:
	var settings:=_ensure_text_settings(layer)
	var result:=await ActorProjectResourceSaveDialog.pick(self,"Save Text Settings",layer.label+" Text Settings","tres",false,PackedStringArray(),settings)
	_native_workspace().save_text_settings_result(self,layer,settings,result)

func _image_source_property(layer: KiwiImageLayer) -> void:
	_native_workspace().image_source_property(self,layer)

func _create_noise_image(layer: KiwiImageLayer) -> void:
	_native_workspace().create_noise_image(self,layer)

func _set_noise_value(layer: KiwiImageLayer,key: String,value: Variant) -> void:
	_native_workspace().set_noise_value(layer,key,value)

func _update_image_noise(layer: KiwiImageLayer) -> void:
	_native_workspace().update_image_noise(layer)

func _set_common(key: String,value: Variant) -> void:
	_native_workspace().set_common(self,key,value)

func _number(parent: Node,label: String,value: float,setter: Callable,minimum: float=-100000,maximum: float=100000,number_step: float=.1) -> void:
	_native_workspace().number(self,parent,label,value,setter,minimum,maximum,number_step)

func _slider(parent: Node,label: String,value: float,minimum: float,maximum: float,setter: Callable) -> void:
	_native_workspace().slider(self,parent,label,value,minimum,maximum,setter)

func _color(parent: Node,label: String,value: Color,setter: Callable) -> void:
	_native_workspace().color(self,parent,label,value,setter)

func _check(parent: Node,label: String,value: bool,setter: Callable) -> void:
	_native_workspace().check(self,parent,label,value,setter)

func _build_value_sliders(layer: KiwiImageLayer) -> void:
	_native_workspace().build_value_sliders(self,layer)

func _open_values(_ordered: bool) -> void:
	_open_stack_editor(true)


func _populate_values(list: VBoxContainer, layer: KiwiImageLayer, ordered: bool) -> void:
	_native_workspace().populate_values(self,list,layer,ordered)

func _operand_controls(host: Control, caption: String, op: Dictionary, key: String, rebuild: Callable) -> void:
	_native_workspace().operand_controls(self,host,caption,op,key,rebuild)

func _build_effects(layer: KiwiImageLayer) -> void:
	_native_workspace().build_effects(self,layer)

func add_effect(kind: String) -> void:
	_native_workspace().add_effect(self,kind)

func _new_effect(kind: String) -> Dictionary:
	return _native_workspace().new_effect(kind)

func _move_effect(index: int,direction: int) -> void:
	_native_workspace().move_effect(self,index,direction)

func _mirror_fields(fields: Node,effect: Dictionary) -> void:
	_native_workspace().mirror_fields(self,fields,effect)

func _effect_selection_control(parent: Node,layer: KiwiImageLayer) -> void:
	_native_workspace().effect_selection_control(self,parent,layer)

func _apply_effect(layer: KiwiImageLayer,index: int) -> void:
	var request: Dictionary=_native_workspace().prepare_apply_effect(self,layer,index)
	if request.is_empty(): return
	var pixels: Image=await request.baker.flattened()
	_native_workspace().complete_apply_effect(self,request,pixels)

func _choose_shader_effect() -> void:
	var property:=ActorProperty.new(); property.options={"extensions":["gdshader"],"file_picker":true}
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Choose a canvas shader")
	_native_workspace().choose_shader_effect_result(self,chosen)

func _shader_fields(parent: Node,effect: Dictionary) -> void:
	_native_workspace().shader_fields(self,parent,effect)

func _font_menu() -> void:
	_native_workspace().font_menu(self)

func _edit_canvas_text() -> void:
	_native_workspace().edit_canvas_text(self)

func delete_selected() -> void:
	_native_workspace().delete_selected(self)

func copy_layers() -> void:
	_native_workspace().copy_layers(self)

func paste_layers() -> void:
	_native_workspace().paste_layers(self)

func duplicate_layers() -> void:
	_native_workspace().duplicate_layers(self)

func _selected_ids_with_relatives(ids: Array[String]) -> Dictionary:
	return _native_workspace().selected_ids_with_relatives(self,ids)

func _render_layers(ids: Array[String]) -> Image:
	_native_workspace().prepare_render_layers(self,ids)
	var bitmap: Image=await renderer.flattened()
	_native_workspace().restore_render_layers(self)
	return bitmap

func _basic_from_image(bitmap: Image,label: String) -> KiwiImageLayer:
	return _native_workspace().basic_from_image(self,bitmap,label)

func _remove_roots(ids: Array[String]) -> void:
	_native_workspace().remove_roots(self,ids)

func merge_selected() -> void:
	var request: Dictionary=_native_workspace().prepare_merge(self)
	if request.is_empty(): return
	var bitmap: Image=await _render_layers(request.ids)
	_native_workspace().complete_merge(self,request,bitmap)

func rasterize_selected() -> void:
	var request: Dictionary=_native_workspace().prepare_rasterize(self)
	if request.is_empty(): return
	for layer: KiwiImageLayer in request.targets:
		var bitmap: Image=await _render_layers([layer.id])
		_native_workspace().collect_rasterized(self,request,layer,bitmap)
	_native_workspace().complete_rasterize(self,request)

func _apply_crop(bounds: Rect2,polygon: PackedVector2Array=PackedVector2Array()) -> void:
	var request: Dictionary=_native_workspace().prepare_crop(self,bounds,polygon)
	if request.is_empty(): return
	var combined: Image=await _render_layers(request.ids)
	if not _native_workspace().collect_crop_image(self,request,combined): return
	if request.action!=1:
		for layer: KiwiImageLayer in request.roots:
			var bitmap: Image=await _render_layers([layer.id])
			_native_workspace().collect_crop_replacement(self,request,layer,bitmap)
	_native_workspace().complete_crop(self,request)

func _crop_spans(region: Rect2i,polygon: PackedVector2Array) -> Array[Rect2i]:
	return _native_workspace().crop_spans(region,polygon)

func _duplicate_for_drag() -> void:
	_native_workspace().duplicate_for_drag(self)

func select_all() -> void:
	_native_workspace().select_all(self)

func group_selected() -> void:
	_native_workspace().group_selected(self)

func ungroup_selected() -> void:
	_native_workspace().ungroup_selected(self)

func parent_selected() -> void:
	_native_workspace().parent_selected(self)

func unparent_selected() -> void:
	_native_workspace().unparent_selected(self)

func reparent_layers(ids: Array,target_id: String,section: int) -> void:
	_native_workspace().reparent_layers(self,ids,target_id,section)

func reorder_selected(direction: int) -> void:
	_native_workspace().reorder_selected(self,direction)

func align_selected(mode: String) -> void:
	_native_workspace().align_selected(self,mode)

func distribute_selected(horizontal: bool) -> void:
	_native_workspace().distribute_selected(self,horizontal)

func copy_style() -> void:
	_native_workspace().copy_style(self)

func paste_style() -> void:
	_native_workspace().paste_style(self)

func _save_style() -> void:
	_native_workspace().save_style(self)

func selection_to_mask() -> void:
	_native_workspace().selection_to_mask(self)

func invert_selection() -> void:
	_native_workspace().invert_selection(self)

func _save_selection() -> void:
	_native_workspace().save_selection(self)

func _load_selection() -> void:
	_native_workspace().load_selection(self)

func selection_to_layer() -> void:
	if canvas.selection==null: return
	var bitmap: Image=await renderer.flattened()
	_native_workspace().complete_selection_to_layer(self,bitmap)

func _prepare_pixel_selection() -> void:
	var request: Dictionary=_native_workspace().prepare_pixel_source(self)
	if request.is_empty(): return
	var pixels: Image=await request.renderer.flattened()
	_native_workspace().complete_pixel_source(self,request,pixels)

func _apply_pixel_selection(action: String) -> void:
	var request: Dictionary=_native_workspace().prepare_pixel_action(self,action)
	if request.is_empty(): return
	var mask: Texture2D
	if request.local_mask: mask=await preload("res://Workspaces/ImageWorkspace/image_selection_fill.gd").capture_local_mask(self,request.layer)
	_native_workspace().complete_pixel_action(self,request,mask)

func _flip_layer(horizontal: bool) -> void:
	_native_workspace().flip_layer(self,horizontal)

func _small_layer_icon(key: String) -> Texture2D:
	return _native_workspace().small_layer_icon(self,key)

func fill_selected_to_parent() -> void:
	_native_workspace().fill_selected_to_parent(self)

func resize_image_aspect() -> void:
	_native_workspace().resize_image_aspect(self)

func restore_layer_paint() -> void:
	_native_workspace().restore_layer_paint(self)

func _canvas_size_dialog() -> void:
	_native_workspace().canvas_size_dialog(self)

func _image_size_dialog() -> void:
	_native_workspace().image_size_dialog(self)

func _scale_image(new_size: Vector2i,interpolation: int) -> void:
	_native_workspace().scale_image(self,new_size,interpolation)

func _choose_image() -> void:
	var property:=ActorProperty.new(); property.options={"extensions":IMAGE_EXTENSIONS+["tres","res"],"native_resource_types":["KiwiImageDocument"],"file_picker":true}
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Open image or Image Studio document")
	_native_workspace().choose_image_result(self,chosen)

func _choose_import() -> void:
	var property:=ActorProperty.new(); property.options={"extensions":IMAGE_EXTENSIONS,"file_picker":true}
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Add an image layer")
	_native_workspace().choose_import_result(self,chosen)

func _replace_image() -> void:
	var layer:=_main_layer()
	if layer==null: return
	var property:=ActorProperty.new(); property.options={"extensions":IMAGE_EXTENSIONS,"file_picker":true}
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Replace layer image")
	_native_workspace().replace_image_result(self,layer,chosen)

func _import_paths(paths: PackedStringArray,at: Vector2) -> void:
	_native_workspace().import_paths(self,paths,at)

func save() -> void:
	await _save_targets(true,true)


func save_image() -> void:
	if document.output_path.is_empty() and not source is ImageTexture: await save_as(); return
	await _save_targets(true,false)


func save_project() -> void:
	if document_path.is_empty(): await save_project_as(); return
	await _save_targets(false,true)


func save_project_as() -> void:
	var result:=await ActorProjectResourceSaveDialog.pick(self,"Save image project", "Image Project","tres",false,PackedStringArray(),func(): _finish_pending(); return document.snapshot())
	if _native_workspace().save_project_as_result(self,result): await _save_targets(false,true)

func _wait_for_repair() -> void:
	_native_workspace().prepare_wait_for_repair(self)
	while _native_workspace().repair_pending(self): await get_tree().process_frame

func _save_targets(write_image: bool,write_project: bool) -> void:
	if _busy: return
	await _wait_for_repair()
	var request: Dictionary=_native_workspace().prepare_save_targets(self,write_image,write_project)
	if request.choose_image: await save_as(); return
	if request.flattened==null:
		var flattened: Image=await renderer.flattened()
		_native_workspace().save_rendered(self,request,flattened)
	if not _native_workspace().start_save_job(self,request): return
	while not _native_workspace().save_job_completed(request): await get_tree().process_frame
	_native_workspace().complete_save_job(self,request)

func save_as() -> void:
	_finish_pending()
	var result:=await ActorProjectResourceSaveDialog.pick(self,"Save image as",path.get_file().get_basename() if not path.is_empty() else "Untitled Image","png",false,PackedStringArray(SAVE_FORMATS),func(): return document.snapshot())
	if _native_workspace().save_as_result(self,result): await _save_targets(true,false)

func _pack_project_textures(snapshot: KiwiImageDocument) -> void:
	_native_workspace().pack_project_textures(snapshot)

func _new_output_path(native_path: String) -> String:
	return _native_workspace().new_output_path(native_path)

func export_image() -> void:
	_native_workspace().export_image(self)

func _export_to(destination: String) -> void:
	await _wait_for_repair()
	_finish_pending(); renderer.sync(document)
	var bitmap: Image=await renderer.flattened()
	_native_workspace().complete_image_export(self,destination,bitmap)

func _write_bitmap(bitmap: Image,destination: String) -> Error:
	return _native_workspace().write_bitmap(bitmap,destination)

func _workflow_window(title: String,minimum:=Vector2(720,500)) -> Dictionary:
	return _native_workspace().workflow_window(self,title,minimum)

func _panel_card(parent: Control,title: String,subtitle: String="") -> VBoxContainer:
	return _native_workspace().panel_card(parent,title,subtitle)

func _transform_panel() -> void:
	_native_workspace().transform_panel(self)

func _copy_transform() -> void:
	_native_workspace().copy_transform(self)

func _paste_transform() -> void:
	_native_workspace().paste_transform(self)

func _match_selected_size(width: bool,height: bool) -> void:
	_native_workspace().match_selected_size(self,width,height)

func _selection_panel() -> void:
	_native_workspace().selection_panel(self)

func _commit_selection_bitmap(bitmap: Image) -> void:
	_native_workspace().commit_selection_bitmap(self,bitmap)

func _smart_select(kind: String,reference:=Color.TRANSPARENT,threshold: float=.12) -> void:
	await _prepare_pixel_selection()
	_native_workspace().smart_select(self,kind,reference,threshold)

func _select_similar_dialog() -> void:
	_native_workspace().select_similar_dialog(self)

func _current_selection_bitmap() -> Image:
	return _native_workspace().current_selection_bitmap(self)

func _modify_selection(kind: String,radius: int) -> void:
	_native_workspace().modify_selection(self,kind,radius)

func _source_to_mask(luminance: bool) -> void:
	_native_workspace().source_to_mask(self,luminance)

func _mask_to_selection() -> void:
	_native_workspace().mask_to_selection(self)

func _invert_layer_masks() -> void:
	_native_workspace().invert_layer_masks(self)

func _create_adjustment_group() -> void:
	_native_workspace().create_adjustment_group(self)

func _effects_panel() -> void:
	_set_tool("effects"); _open_stack_editor(false)

func _toggle_effects_panel() -> void:
	_set_tool("effects")

func _open_stack_editor(adjustments: bool) -> void:
	_native_workspace().open_stack_editor(self,adjustments)

func _build_effects_dock() -> void:
	_native_workspace().build_effects_dock(self)

func _refresh_effects_dock() -> void:
	_native_workspace().refresh_effects_dock(self)

func _apply_style_preset(name: String,linked: bool) -> void:
	_native_workspace().apply_style_preset(self,name,linked)

func _sync_linked_styles() -> void:
	_native_workspace().sync_linked_styles(self)

func _effect_fields(fields: Node,effect: Dictionary) -> void:
	_native_workspace().effect_fields(self,fields,effect)

func _curve_effect_fields(fields: Node,effect: Dictionary) -> void:
	_native_workspace().curve_effect_fields(self,fields,effect)

func _asset_shelf() -> void:
	_native_workspace().asset_shelf(self)

func _remember_asset(file: String) -> void:
	_native_workspace().remember_asset(self,file)

func _variants_panel() -> void:
	_native_workspace().variants_panel(self)

func _capture_variant() -> void:
	_native_workspace().capture_variant(self)

func _restore_variant(name: String) -> void:
	_native_workspace().restore_variant(self,name)

func _compare_variant() -> void:
	_native_workspace().compare_variant(self)

func _automation_panel() -> void:
	_native_workspace().automation_panel(self)

func _start_macro() -> void:
	_native_workspace().start_macro(self)

func _stop_macro() -> void:
	_native_workspace().stop_macro(self)

func _run_macro(name: String) -> void:
	_native_workspace().run_macro(self,name)

func _shortcut_string(event: InputEventKey) -> String:
	return _native_workspace().shortcut_string(event)

func _customize_shortcuts() -> void:
	_native_workspace().customize_shortcuts(self)

func _export_presets_panel() -> void:
	_native_workspace().export_presets_panel(self)

func _quick_export(size: Vector2i,suffix: String,format: String) -> void:
	var destination:=document.output_path
	if destination.is_empty():
		var result:=await ActorProjectResourceSaveDialog.pick(self,"Quick export · "+suffix,"Image-"+suffix,format,false,PackedStringArray(SAVE_FORMATS))
		if result.get("cancelled",true): return
		destination=str(result.path)
	var bitmap: Image=await renderer.flattened()
	_native_workspace().complete_quick_export(self,bitmap,size,destination,suffix,format)

func _export_selected_layer() -> void:
	await _wait_for_repair()
	var layer:=_main_layer()
	if layer==null: return
	var bitmap:=await _render_layers([layer.id])
	if bitmap==null: return
	var result:=await ActorProjectResourceSaveDialog.pick(self,"Export selected layer",layer.label,"png",false,PackedStringArray(SAVE_FORMATS))
	if not result.get("cancelled",true): _write_bitmap(bitmap,str(result.path))


func _export_layers() -> void:
	await _wait_for_repair()
	var result:=await ActorProjectResourceSaveDialog.pick(self,"Choose layer export folder","Layers","png",false,PackedStringArray(["png"]))
	if result.get("cancelled",true): return
	var base:=str(result.path).get_base_dir()
	for layer in document.children():
		var bitmap:=await _render_layers([layer.id])
		_native_workspace().write_layer_export(self,bitmap,base,layer.label)
	status.text="Exported top-level layers"


func _layer_polygon(layer: KiwiImageLayer) -> PackedVector2Array:
	return _native_workspace().layer_polygon(self,layer)

func _boolean_shapes(operation: String) -> void:
	_native_workspace().boolean_shapes(self,operation)

func _register_commands() -> void:
	_native_workspace().register_commands(self)

func _execute_command(command: Dictionary) -> void:
	_native_workspace().execute_command(self,command)

func _run_named_command(name: String) -> void:
	_native_workspace().run_named_command(self,name)

func _repeat_last_command() -> void:
	_native_workspace().repeat_last_command(self)

func _command_palette() -> void:
	_native_workspace().command_palette(self)

func _unhandled_key_input(event: InputEvent) -> void:
	_native_workspace().unhandled_key_input(self,event)

func _painting_mode_controls(host: Node) -> void:
	_native_workspace().painting_mode_controls(self,host)

func _material_edit_committed() -> void:
	_native_workspace().material_edit_committed(self)

func _material_changed(value: KiwiTextureMaterial) -> void:
	_native_workspace().material_changed(self,value)

func _material_icon_for(button: Button,value: KiwiTextureMaterial) -> void:
	_native_workspace().material_icon_for(self,button,value)

func _render_material_thumbnails() -> void:
	while true:
		var request: Dictionary=_native_workspace().next_material_thumbnail(self)
		if request.is_empty(): return
		var bitmap: Image
		if not _material_thumbnail_cache.has(request.key): bitmap=await preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd").preview(self,request.material,Vector2i(64,40))
		_native_workspace().complete_material_thumbnail(self,request,bitmap)

func _live_material_controls() -> void:
	_native_workspace().live_material_controls(self)

func _select_live_material(id: String) -> void:
	_native_workspace().select_live_material(self,id)

func _live_material_menu(id: String) -> void:
	_native_workspace().live_material_menu(self,id)

func _bake_active_material() -> void:
	var request: Dictionary=_native_workspace().prepare_material_bake(self)
	if request.is_empty(): return
	var success: bool=await renderer.bake_live_material(request.id)
	_native_workspace().complete_material_bake(self,request,success)

func _delete_active_material() -> void:
	_native_workspace().delete_active_material(self)

func _name_dialog(title: String,current: String,save_callback: Callable) -> void:
	_native_workspace().name_dialog(self,title,current,save_callback)

func _paint_preset_menu(kind: String,preset: Dictionary) -> void:
	_native_workspace().paint_preset_menu(self,kind,preset)

static func _native_workspace() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("image_workspace")

func _invoke_action(operation: Callable) -> void:
	operation.call()

func _connect_button(button: Button,action: Callable) -> void:
	button.pressed.connect(action)

func _connect_menu(popup: PopupMenu,items: Array) -> void:
	popup.id_pressed.connect(func(index: int): items[index][1].call())

func _invoke_value(setter: Callable,value: Variant) -> void:
	setter.call(value)

func _new_preset_button(kind: String,id: String) -> Button:
	var button:=PresetButton.new()
	button.studio=self; button.kind=kind; button.preset_id=id
	return button

func _save_super_clipboard() -> void:
	_finish_pending()
	KiwiSuperClipboardService.instance.quick_save(document.snapshot(),title_label.text)

func _refresh_project_files() -> void:
	if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()

func _choose_effect_texture(effect: Dictionary,key: StringName) -> void:
	var property:=ActorProperty.new(); property.options={"extensions":IMAGE_EXTENSIONS,"file_picker":true}
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Choose shader texture")
	_native_workspace().effect_texture_result(self,effect,key,chosen)
