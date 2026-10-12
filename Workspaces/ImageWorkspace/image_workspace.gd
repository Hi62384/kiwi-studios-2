class_name KiwiImageWorkspace
extends Control
## Image Studio coordinates reusable document, renderer, and canvas modules.

signal document_changed
signal image_saved(source: Variant)

const IMAGE_EXTENSIONS := ["png","jpg","jpeg","webp","bmp","tga","svg","hdr","exr"]
const AVAILABLE_EFFECTS := ["mirror","curves","blur","motion_blur","radial_blur","sharpen","emboss","edge_detect","shadow","glow","outline","gradient_map","color_replace","grain","pixelate","halftone","scanlines","chromatic","vignette","wave","twirl","ripple","kaleidoscope"]
const SAVE_FORMATS := ["png","jpg","webp"]
const Layer = preload("res://Workspaces/ImageWorkspace/image_layer.gd")
const Document = preload("res://Workspaces/ImageWorkspace/image_document.gd")
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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_theme()
	if FileAccess.file_exists("user://image_studio_styles.tres"):
		var saved:=ResourceLoader.load("user://image_studio_styles.tres")
		if saved!=null: _presets=saved.get_meta("styles",{})
	_load_paint_presets()
	add_child(renderer)
	_build_ui()
	canvas.gesture_started.connect(_begin)
	canvas.warp_tool.settings_changed.connect(_refresh_context)
	canvas.repair_tool.initialize(self); canvas.repair_tool.settings_changed.connect(_refresh_context)
	canvas.gesture_changed.connect(_preview)
	canvas.gesture_finished.connect(_commit)
	canvas.gesture_cancelled.connect(_cancel)
	canvas.selection_changed.connect(_selection_changed)
	canvas.create_requested.connect(_create_at)
	canvas.duplicate_requested.connect(_duplicate_for_drag)
	canvas.text_edit_requested.connect(_edit_canvas_text)
	canvas.polygon_committed.connect(_save_polygon)
	canvas.files_dropped.connect(_import_paths)
	canvas.color_sampled.connect(func(value: Color): color_picker.color=value; canvas.color=value)
	canvas.hint_changed.connect(func(value: String): status.text=value if not value.is_empty() else _tool_hint())
	canvas.brush_size_changed.connect(func(value: float):
		if is_instance_valid(brush_size): brush_size.set_value_no_signal(value)
		if canvas.tool=="pixel_select": _refresh_context())
	canvas.correction_scale_changed.connect(func(value: float):
		var field: Variant=_context_fields.get("correction_scale")
		if is_instance_valid(field): field.set_value_no_signal(value)
		_persist_paint_presets())
	canvas.threshold_changed.connect(func(_value: float): _refresh_context())
	if document == null: open_source(null)
	set_process(true)


func _build_theme() -> void:
	var skin := Theme.new()
	skin.default_font_size=13
	for kind in ["Button","MenuButton","OptionButton"]:
		skin.set_stylebox("normal",kind,_box(Color("202c3a"),Color("344356"),6,8))
		skin.set_stylebox("hover",kind,_box(Color("2d4153"),Color("5c7b91"),6,8))
		skin.set_stylebox("pressed",kind,_box(Color("21584f"),Color("6ae2c3"),6,8))
		skin.set_stylebox("focus",kind,_box(Color(0,0,0,0),Color("74ddca"),6,1))
		skin.set_color("font_color",kind,Color("d6e4f0"))
		skin.set_color("font_hover_color",kind,Color.WHITE)
		skin.set_font_size("font_size",kind,13)
	skin.set_stylebox("normal","LineEdit",_box(Color("131e2a"),Color("344356"),5,7))
	skin.set_stylebox("normal","TextEdit",_box(Color("131e2a"),Color("344356"),5,8))
	skin.set_stylebox("panel","Tree",_box(Color("17212d"),Color("17212d"),6,4))
	skin.set_stylebox("selected","Tree",_box(Color("214e4c"),Color("3b8072"),4,3))
	skin.set_stylebox("selected_focus","Tree",_box(Color("246255"),Color("6ae2c3"),4,3))
	skin.set_constant("v_separation","Tree",0)
	skin.set_constant("button_margin","Tree",0)
	skin.set_color("font_color","Label",Color("c9d8e6"))
	skin.set_color("font_color","Tree",Color("d5e5ef"))
	theme=skin


func _box(fill: Color,border: Color,radius: int=8,padding: int=8) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new()
	box.bg_color=fill; box.border_color=border
	box.set_border_width_all(1); box.set_corner_radius_all(radius)
	box.content_margin_left=padding; box.content_margin_right=padding
	box.content_margin_top=padding; box.content_margin_bottom=padding
	return box


func _icon(name: String) -> Texture2D:
	if _icons.has(name): return _icons[name]
	var paths := {
		"effects":"<path d='m4 20 13-13 3 3L7 23zM15 2v4M13 4h4M5 5v4M3 7h4M20 15v4M18 17h4'/>",
		"brightness":"<circle cx='12' cy='12' r='4'/><path d='M12 2v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10l2 2M5 19l2-2M17 7l2-2'/>",
		"contrast":"<circle cx='12' cy='12' r='9'/><path d='M12 3a9 9 0 0 1 0 18z' fill='currentColor'/>",
		"saturation":"<path d='M12 2C9 7 5 10 5 15a7 7 0 0 0 14 0c0-5-4-8-7-13zM8 15c0 3 2 4 4 4'/>",
		"exposure":"<circle cx='12' cy='12' r='9'/><path d='M7 8h6M10 5v6m2 5h6'/>",
		"gamma":"<path d='M3 3v18h18M5 18c10 0 3-14 14-14'/>",
		"hue":"<circle cx='12' cy='12' r='9'/><circle cx='12' cy='12' r='3'/><path d='M12 3v6m0 6v6M3 12h6m6 0h6'/>",
		"temperature":"<path d='M9 14V5a3 3 0 0 1 6 0v9a5 5 0 1 1-6 0zM12 8v10M18 5h3m-3 4h3'/>",
		"tint":"<path d='M8 3C6 7 3 10 3 14a5 5 0 0 0 10 0c0-4-3-7-5-11zM16 8c-2 4-4 6-4 9a4 4 0 0 0 8 0c0-3-2-5-4-9z'/>",
		"values":"<path d='M4 6h16M4 12h16M4 18h16'/><circle cx='9' cy='6' r='2'/><circle cx='16' cy='12' r='2'/><circle cx='7' cy='18' r='2'/>",
		"move":"<path d='M5 3l14 9-7 1-3 7z'/>",
		"brush":"<path d='M14 4l5 5-9 9-5 1 1-5zM12 6l5 5'/>",
		"eraser":"<path d='M4 14l9-10 7 6-9 10H8zM8 10l7 6M10 20h11'/>",
		"fill":"<path d='M12 3L3 12l8 8 9-9zM3 12h16M7 3l8 8'/>",
		"picker":"<path d='M15 3l6 6M16 6L5 17l-1 4 4-1L19 9'/>",
		"rect_select":"<path stroke-dasharray='3 3' d='M4 4h16v16H4z'/>",
		"ellipse_select":"<ellipse cx='12' cy='12' rx='9' ry='7' stroke-dasharray='3 3'/>",
		"lasso":"<path d='M7 17C-3 5 17 0 21 10c3 9-17 13-17 6s10-3 7 5'/>",
		"shape":"<rect x='4' y='4' width='16' height='16' rx='3'/>",
		"text":"<path d='M4 5h16M12 5v15M8 20h8'/>",
		"path":"<path d='M5 19L10 4l10 15z'/><circle cx='5' cy='19' r='2'/><circle cx='10' cy='4' r='2'/>",
		"crop":"<path d='M7 2v15h15M2 7h15v15'/>",
		"image":"<rect x='3' y='4' width='18' height='16' rx='2'/><path d='M3 16l6-6 5 5 3-3 4 4'/><circle cx='16' cy='8' r='1'/>",
		"paint":"<path d='M14 4l5 5-9 9-5 1 1-5z'/>",
		"gradient":"<rect x='3' y='4' width='18' height='16' rx='2'/><path d='M7 5v14M11 5v14M15 5v14'/>",
		"group":"<path d='M3 7h7l2 3h9v10H3zM3 7V4h7l2 3h9v3'/>",
		"eye":"<path d='M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z'/><circle cx='12' cy='12' r='3'/>",
		"hidden":"<path d='M3 3l18 18M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z'/>",
		"lock":"<rect x='5' y='10' width='14' height='11' rx='2'/><path d='M8 10V6a4 4 0 018 0v4'/>",
		"unlock":"<rect x='5' y='10' width='14' height='11' rx='2'/><path d='M8 10V6a4 4 0 018 0'/>",
		"plus":"<path d='M12 4v16M4 12h16'/>",
		"undo":"<path d='M9 5L3 10l6 5M3 10h11a6 6 0 010 12'/>",
		"redo":"<path d='M15 5l6 5-6 5M21 10h-11a6 6 0 000 12'/>",
		"mask":"<circle cx='12' cy='12' r='9'/><path d='M12 3v18M12 6h6M12 10h8M12 14h8M12 18h5'/>",
		"search":"<circle cx='10' cy='10' r='6'/><path d='M15 15l6 6'/>"}
	paths["trash"]="<path d='M4 7h16M9 7V4h6v3M7 7l1 14h8l1-14M10 11v6M14 11v6'/>"
	paths["isolate"]="<path d='M3 8V3h5M16 3h5v5M21 16v5h-5M8 21H3v-5'/><circle cx='12' cy='12' r='3'/>"
	paths["isolated"]="<path d='M3 8V3h5M16 3h5v5M21 16v5h-5M8 21H3v-5'/><circle cx='12' cy='12' r='5' fill='#77e4c7'/>"
	paths["ungroup"]="<path d='M4 8V4h4M16 4h4v4M20 16v4h-4M8 20H4v-4M8 12h8M12 8v8'/>"
	paths["duplicate"]="<rect x='7' y='7' width='13' height='13' rx='2'/><path d='M4 16V4h12'/>"
	paths["merge"]="<path d='M4 7l8-4 8 4-8 4zM4 12l8 4 8-4M4 17l8 4 8-4'/>"
	paths["basic"]=paths["paint"]
	paths["position"]="<path d='M12 2v20M2 12h20M8 6l4-4 4 4M8 18l4 4 4-4M6 8l-4 4 4 4M18 8l4 4-4 4'/>"
	paths["rotate"]="<path d='M5 8a8 8 0 111 10M5 3v5h5'/><circle cx='12' cy='12' r='2'/>"
	paths["opacity"]="<path d='M12 3C10 7 5 11 5 15a7 7 0 0014 0c0-4-5-8-7-12zM12 10v10'/>"
	paths["hardness"]="<circle cx='12' cy='12' r='8'/><circle cx='12' cy='12' r='4'/><path d='M12 1v2M12 21v2M1 12h2M21 12h2'/>"
	paths["layers"]="<path d='M3 7l9-4 9 4-9 4zM3 12l9 4 9-4M3 17l9 4 9-4'/>"
	paths["snap"]="<path d='M5 3v10a7 7 0 0014 0V3h-4v10a3 3 0 01-6 0V3zM5 8h4M15 8h4'/>"
	paths["flip_h"]="<path d='M12 3v18M9 5L3 19h6zM15 5l6 14h-6z'/>"
	paths["flip_v"]="<path d='M3 12h18M5 9L19 3v6zM5 15l14 6v-6z'/>"
	paths["fit_layer"]="<path d='M3 8V3h5M16 3h5v5M21 16v5h-5M8 21H3v-5M8 8h8v8H8z'/>"
	paths["aspect"]="<rect x='3' y='6' width='18' height='12' rx='2'/><path d='M7 14l10-4M7 10v4h4M13 10h4v4'/>"
	paths["parent"]="<path d='M9 7H6a4 4 0 000 8h3M15 7h3a4 4 0 010 8h-3M8 11h8v4H8z'/>"
	paths["unparent"]="<path d='M3 3l18 18M9 7H6a4 4 0 000 8h3M15 7h3a4 4 0 012 7M8 11h8v4H8z'/>"
	paths["warp"]="<path d='M4 4c5 3 11-3 16 0-3 5 3 11 0 16-5-3-11 3-16 0 3-5-3-11 0-16zM4 12c6-4 10 4 16 0M12 4c4 6-4 10 0 16'/>"
	paths["repair"]="<path d='m4 14 10-10 6 6-10 10zM9 9l6 6M7 15h1M11 7h1M16 11h1M11 17h1'/><path d='M18 2v5M16 4h5'/>"
	paths["pattern"]="<path d='M3 3h18v18H3zM3 9h18M3 15h18M9 3v18M15 3v18'/><circle cx='6' cy='6' r='1'/><circle cx='12' cy='12' r='1'/><circle cx='18' cy='18' r='1'/>"
	paths["noise"]="<path d='M3 3h18v18H3zM6 7h1M13 5h1M17 10h1M9 12h1M5 17h1M14 18h1M18 15h1'/>"
	paths.merge({
		"mirror":"<path d='M12 2v20M8 5 3 12l5 7zM16 5l5 7-5 7z'/>",
		"blur":"<circle cx='12' cy='12' r='3'/><circle cx='12' cy='12' r='7' stroke-dasharray='2 3'/><circle cx='12' cy='12' r='10' stroke-dasharray='1 5'/>",
		"motion_blur":"<path d='M2 5h12M2 12h7M2 19h12'/><circle cx='17' cy='12' r='4'/>",
		"radial_blur":"<circle cx='12' cy='12' r='3'/><path d='m4 4 4 4m8 8 4 4M4 20l4-4M16 8l4-4M12 2v4M12 18v4M2 12h4M18 12h4'/>",
		"sharpen":"<path d='m3 20 9-17 9 17-9-5zM12 3v12'/>",
		"emboss":"<path d='m4 7 8-4 8 4v10l-8 4-8-4zM4 7l8 4 8-4M12 11v10'/>",
		"edge_detect":"<path d='M4 18V5h14M7 21V8h14'/>",
		"shadow":"<rect x='9' y='9' width='12' height='12' rx='2' stroke-dasharray='2 2'/><rect x='3' y='3' width='12' height='12' rx='2'/>",
		"glow":"<circle cx='12' cy='12' r='4'/><path d='M12 2v3M12 19v3M2 12h3M19 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2'/><circle cx='12' cy='12' r='7' stroke-dasharray='1 3'/>",
		"outline":"<rect x='2' y='2' width='20' height='20' rx='5'/><rect x='6' y='6' width='12' height='12' rx='2'/>",
		"vignette":"<ellipse cx='12' cy='12' rx='10' ry='8'/><ellipse cx='12' cy='12' rx='6' ry='4'/><path d='M3 8l3 2M18 14l3 2'/>",
		"wave":"<path d='M2 8c5-12 5 12 10 0s5 12 10 0M2 16c5-12 5 12 10 0s5 12 10 0'/>",
		"twirl":"<path d='M12 12c0-6 9-5 9 1 0 10-18 12-18 0C3 3 14 0 20 5'/>",
		"ripple":"<ellipse cx='12' cy='12' rx='3' ry='2'/><ellipse cx='12' cy='12' rx='7' ry='5'/><ellipse cx='12' cy='12' rx='10' ry='8'/>",
		"kaleidoscope":"<path d='m12 2 9 5v10l-9 5-9-5V7zM12 2v20M3 7l18 10M3 17 21 7'/>",
		"chromatic":"<circle cx='9' cy='9' r='5'/><circle cx='15' cy='9' r='5'/><circle cx='12' cy='15' r='5'/>",
		"grain":"<path d='M4 4h16v16H4zM7 7h1M14 6h1M10 11h1M17 12h1M6 16h1M13 18h1M17 17h1'/>",
		"pixelate":"<path d='M3 3h8v8H3zM13 3h8v8h-8zM3 13h8v8H3zM13 13h8v8h-8z'/>",
		"halftone":"<circle cx='6' cy='6' r='3'/><circle cx='17' cy='6' r='2'/><circle cx='6' cy='17' r='2'/><circle cx='17' cy='17' r='1'/>",
		"scanlines":"<path d='M3 4h18M3 8h18M3 12h18M3 16h18M3 20h18'/>",
		"curves":"<path d='M3 3v18h18M4 18c4 0 5-12 10-12s3 10 7-2'/><circle cx='14' cy='6' r='2'/>",
		"gradient_map":"<path d='M3 6h18v12H3zM7 6v12M12 6v12M17 6v12M5 2l3 2-3 2'/>",
		"color_replace":"<circle cx='6' cy='7' r='4'/><circle cx='18' cy='17' r='4'/><path d='M13 4h8v6M21 4l-8 8M3 14v6h8'/>",
		"shader":"<path d='m8 5-6 7 6 7M16 5l6 7-6 7M14 3l-4 18'/>",
		"shadows":"<path d='M15 3a9 9 0 1 0 6 14A8 8 0 0 1 15 3z'/>",
		"midtones":"<circle cx='12' cy='12' r='8'/><path d='M8 5v14M12 4v16M16 5v14'/>",
		"highlights":"<path d='m12 2 3 7 7 3-7 3-3 7-3-7-7-3 7-3z'/>",
		"black_point":"<path d='M3 20h18M4 17l8-13 8 13z'/><circle cx='12' cy='13' r='2' fill='#c5dfdf'/>",
		"white_point":"<path d='M3 20h18M4 17l8-13 8 13zM8 14h8'/>",
		"lift":"<path d='M4 20h16M12 17V3M6 9l6-6 6 6'/>",
		"fade":"<circle cx='12' cy='12' r='9'/><path d='M5 9h14M7 13h10M9 17h6' stroke-dasharray='1 3'/>",
		"vibrance":"<path d='m12 3 9 16H3zM12 8v6M8 17h8'/><circle cx='12' cy='17' r='1'/>",
		"cyan_red":"<circle cx='8' cy='12' r='6'/><path d='M14 6h7v12h-7M17 9v6M15 12h4'/>",
		"magenta_green":"<path d='m3 12 6-8 6 8-6 8z'/><circle cx='17' cy='12' r='4'/>",
		"yellow_blue":"<path d='M3 5h8v14H3zM14 5l7 7-7 7z'/>",
		"shadow_warmth":"<path d='M13 4a8 8 0 1 0 6 13A7 7 0 0 1 13 4zM17 3v6M14 6h6'/>",
		"highlight_warmth":"<circle cx='8' cy='12' r='4'/><path d='M8 3v2M8 19v2M1 12h2M13 12h2M19 6v12M16 9l3-3 3 3'/>",
		"red":"<path d='M4 20V4h6a4 4 0 0 1 0 8H4M10 12l6 8M18 4v5'/>",
		"green":"<path d='M18 7a7 7 0 1 0 0 10v-5h-6M20 4v4'/>",
		"blue":"<path d='M5 3v18h7a4 4 0 0 0 0-8H5M5 3h6a5 5 0 0 1 0 10'/>",
		"grayscale":"<rect x='3' y='5' width='18' height='14' rx='2'/><path d='M7 5v14M12 5v14M17 5v14'/>",
		"sepia":"<path d='M6 3h12l3 6-9 12L3 9zM3 9h18M8 9l4 12 4-12'/>",
		"posterize":"<path d='M3 21V3M3 18h5v-5h5V8h5V3h3'/>",
		"solarize":"<path d='M3 19 8 5l5 14 5-14 3 14M3 12h18'/>",
		"threshold":"<rect x='3' y='3' width='18' height='18' rx='2'/><path d='M12 3v18M12 3h9v18h-9z' fill='#c5dfdf'/>",
		"colorize":"<path d='M4 18c-5-8 2-16 11-14 8 2 9 9 5 11-2 1-5-2-7 1s1 6-5 5z'/><circle cx='8' cy='9' r='1'/><circle cx='13' cy='7' r='1'/><circle cx='18' cy='10' r='1'/>",
		"add":"<path d='M4 12h16M12 4v16'/><circle cx='12' cy='12' r='10'/>",
		"subtract":"<circle cx='12' cy='12' r='9'/><path d='M5 12h14'/>",
		"multiply":"<path d='m5 5 14 14M19 5 5 19'/>",
		"divide":"<path d='M4 12h16'/><circle cx='12' cy='5' r='2'/><circle cx='12' cy='19' r='2'/>",
		"power":"<path d='m3 10 8 11M11 10 3 21M14 4c0-5 7-5 7 0 0 3-7 5-7 8h7'/>",
		"clamp":"<path d='M7 3H3v18h4M17 3h4v18h-4M7 12h10'/>",
		"lerp":"<path d='M3 19 21 5M3 5v14h18'/><circle cx='12' cy='12' r='3'/>",
		"minimum":"<path d='m4 15 8-10 8 10M4 20h16'/>",
		"maximum":"<path d='m4 9 8 10 8-10M4 4h16'/>",
		"absolute":"<path d='M3 3v18M21 3v18M7 16l5-10 5 10'/>",
		"invert":"<circle cx='7' cy='8' r='4'/><circle cx='17' cy='16' r='4' fill='#c5dfdf'/><path d='m14 4 6 0-2 5M10 20H4l2-5'/>",
		"smoothstep":"<path d='M3 3v18h18M4 18h3c8 0 1-12 9-12h5'/>"},true)
	var svg: String="<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24'><g fill='none' stroke='#c5dfdf' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'>"+str(paths.get(name,paths.image))+"</g></svg>"
	var bitmap:=Image.new(); bitmap.load_svg_from_string(svg)
	var texture:=ImageTexture.create_from_image(bitmap)
	_icons[name]=texture
	return texture


func _button(parent: Node,text: String,action: Callable,tip: String="",icon_name: String="") -> Button:
	var button:=Button.new()
	button.text=text; button.tooltip_text=tip; button.custom_minimum_size.y=32
	if parent.has_meta("compact_toolbar"): button.custom_minimum_size.y=28
	button.focus_mode=Control.FOCUS_NONE
	if not icon_name.is_empty(): button.icon=_icon(icon_name); button.expand_icon=true; button.add_theme_constant_override("icon_max_width",18)
	if text.is_empty() and not icon_name.is_empty(): button.custom_minimum_size.x=34
	parent.add_child(button); button.pressed.connect(action)
	return button


func _menu(parent: Node,label: String,items: Array) -> MenuButton:
	var button:=MenuButton.new(); button.text=label; button.custom_minimum_size.y=32
	parent.add_child(button)
	var popup:=button.get_popup()
	popup.add_theme_stylebox_override("panel",_box(Color("172431"),Color("416274"),9,10))
	popup.add_theme_stylebox_override("hover",_box(Color("285950"),Color("519887"),5,5))
	popup.add_theme_constant_override("v_separation",12)
	for item: Array in items: popup.add_item(str(item[0]))
	popup.id_pressed.connect(func(index: int): items[index][1].call())
	return button


func _build_ui() -> void:
	var background:=ColorRect.new(); background.color=Color("111a25")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(background)
	var root:=VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left=8; root.offset_top=8; root.offset_right=-8; root.offset_bottom=-8
	root.add_theme_constant_override("separation",7); add_child(root)
	var header:=HBoxContainer.new(); header.add_theme_constant_override("separation",7); root.add_child(header)
	var mark:=Label.new(); mark.text="IMAGE STUDIO"; mark.add_theme_color_override("font_color",Color("77e4c7")); mark.add_theme_font_size_override("font_size",12)
	header.add_child(mark)
	_menu(header,"File",[
		["Save   Ctrl+S",save],["Save image file",save_image],["Save image file as…   Ctrl+Shift+S",save_as],
		["Save project",save_project],["Save project as…",save_project_as],["Export…",export_image],["Open image / document…",_choose_image]])
	_menu(header,"Image",[["Resize / upscale image…",_image_size_dialog],["Scale image 2×",func(): _scale_image(Vector2i(document.canvas_size)*2,Image.INTERPOLATE_LANCZOS)],
		["Scale image ½",func(): _scale_image(Vector2i(Vector2(document.canvas_size)*.5),Image.INTERPOLATE_LANCZOS)]])
	title_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; title_label.clip_text=true; header.add_child(title_label)
	_button(header,"",undo,"Undo · Ctrl+Z","undo")
	_button(header,"",redo,"Redo · Ctrl+Shift+Z / Ctrl+Y","redo")
	var save_button:=_button(header,"Save",save,"Save composition and linked output · Ctrl+S")
	save_button.add_theme_stylebox_override("normal",_box(Color("23594e"),Color("438b79"),6,8))
	context.add_theme_constant_override("separation",8)
	_context_panel.add_theme_stylebox_override("panel",_box(Color("192431"),Color("2b3a4a"),7,3))
	_context_panel.add_child(context)
	context.add_theme_constant_override("h_separation",6); context.add_theme_constant_override("v_separation",3)
	context.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	preset_context.add_theme_constant_override("separation",6)
	preset_panel.add_theme_stylebox_override("panel",_box(Color("151f2b"),Color("293c4c"),6,4))
	preset_panel.visible=false; preset_panel.add_child(preset_context)
	_main_split.size_flags_vertical=Control.SIZE_EXPAND_FILL; root.add_child(_main_split)
	var stage_column:=VBoxContainer.new(); stage_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _main_split.add_child(stage_column)
	_toolbar_surface.custom_minimum_size.y=112; stage_column.add_child(_toolbar_surface)
	# Root-level overlays span both columns and receive input before the sidebar.
	add_child(_context_panel); add_child(preset_panel)
	var stage:=HBoxContainer.new(); stage.size_flags_vertical=Control.SIZE_EXPAND_FILL; stage_column.add_child(stage)
	var rail:=VBoxContainer.new(); rail.custom_minimum_size.x=42; rail.add_theme_constant_override("separation",3); stage.add_child(rail)
	_tool_section(rail,"SELECT",[["move","Move · V"],["pixel_select","Pixel selection · M"]])
	_tool_section(rail,"PAINT",[["brush","Draw · B"],["eraser","Erase · E"],["fill","Bucket · G"]])
	_tool_section(rail,"DEFORM",[["warp","Warp & Liquify · W"],["repair","Texture & Repair"]])
	_tool_section(rail,"ADJUST",[["values","Color adjustments"],["effects","Effects & Styles"]])
	_effects_button=tool_buttons.effects
	color_picker.color=Color("62d9bc")
	color_picker.color_changed.connect(func(value: Color): canvas.color=value)
	canvas.size_flags_horizontal=Control.SIZE_EXPAND_FILL; canvas.size_flags_vertical=Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size=Vector2(260,240); stage.add_child(canvas)
	_side_split.custom_minimum_size.x=285; _side_split.split_offset=280; _main_split.add_child(_side_split)
	_main_split.split_offset=1000
	var properties_panel:=PanelContainer.new(); properties_panel.add_theme_stylebox_override("panel",_box(Color("17212d"),Color("2c3c4c"),8,6))
	var inspector_column:=VBoxContainer.new(); _side_split.add_child(inspector_column)
	_inspector_tool_spacer.custom_minimum_size.y=44; inspector_column.add_child(_inspector_tool_spacer)
	properties_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL; inspector_column.add_child(properties_panel)
	_inspector_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	_inspector_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; properties_panel.add_child(_inspector_scroll)
	properties_panel.add_child(_effects_dock); _effects_dock.hide(); _build_effects_dock()
	inspector.size_flags_horizontal=Control.SIZE_EXPAND_FILL; inspector.add_theme_constant_override("separation",5); _inspector_scroll.add_child(inspector)
	var layers_panel:=PanelContainer.new(); layers_panel.custom_minimum_size.y=160
	layers_panel.add_theme_stylebox_override("panel",_box(Color("17212d"),Color("2c3c4c"),8,9)); _side_split.add_child(layers_panel)
	var layers_column:=VBoxContainer.new(); layers_panel.add_child(layers_column)
	var layers_header:=HBoxContainer.new(); layers_column.add_child(layers_header)
	var layers_title:=Label.new(); layers_title.text="LAYERS"; layers_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	layers_title.add_theme_color_override("font_color",Color("87a2b6")); layers_title.add_theme_font_size_override("font_size",11); layers_header.add_child(layers_title)
	for entry in [["duplicate",duplicate_layers,"Duplicate · Ctrl+D"],["merge",merge_selected,"Merge"],["trash",delete_selected,"Delete · Backspace"],["group",parent_selected,"Parent · Ctrl+G"],["ungroup",unparent_selected,"Unparent · Ctrl+Shift+G"]]:
		var action_button:=_button(layers_header,"",entry[1],entry[2],entry[0]); action_button.custom_minimum_size=Vector2(26,26)
		for state in ["normal","hover","pressed"]: action_button.add_theme_stylebox_override(state,_box(Color("202c3a"),Color("344356"),4,3))
	var layer_body:=HBoxContainer.new(); layer_body.size_flags_vertical=Control.SIZE_EXPAND_FILL; layers_column.add_child(layer_body)
	var creation:=VBoxContainer.new(); creation.add_theme_constant_override("separation",2); creation.set_meta("compact_toolbar",true); layer_body.add_child(creation)
	for entry in [["basic","Basic","paint"],["image","Image","image"],["text","Text","text"],["shape","Shape","shape"]]:
		var kind: String=entry[0]
		var button:=_button(creation,"",func(): _add_layer_from_toolbar(kind),"Add "+str(entry[1])+" layer",entry[2]); button.custom_minimum_size=Vector2(26,26); button.add_theme_stylebox_override("normal",_box(Color("202c3a"),Color("344356"),4,3))
	var list_column:=VBoxContainer.new(); list_column.size_flags_horizontal=Control.SIZE_EXPAND_FILL; layer_body.add_child(list_column)
	var search:=LineEdit.new(); search.placeholder_text="Find a layer…"; list_column.add_child(search)
	search.text_changed.connect(func(value: String): _layer_filter=value; _refresh_layers())
	layer_tree.studio=self; layer_tree.hide_root=true; layer_tree.select_mode=Tree.SELECT_MULTI
	layer_tree.size_flags_vertical=Control.SIZE_EXPAND_FILL; list_column.add_child(layer_tree)
	layer_tree.multi_selected.connect(_tree_selected)
	layer_tree.item_edited.connect(func():
		if _syncing: return
		var item:=layer_tree.get_edited()
		var layer:=document.layer_for_id(str(item.get_metadata(0)))
		if layer != null: _action(func(): layer.label=item.get_text(0)))
	layer_tree.button_clicked.connect(_layer_button)
	layer_tree.item_mouse_selected.connect(func(_at: Vector2,button: int):
		if button==MOUSE_BUTTON_RIGHT: _layer_context())
	var footer:=HBoxContainer.new(); root.add_child(footer)
	status.size_flags_horizontal=Control.SIZE_EXPAND_FILL; status.clip_text=true; status.add_theme_color_override("font_color",Color("8fa8bb")); status.add_theme_font_size_override("font_size",12); footer.add_child(status)
	_button(footer,"−",func(): canvas.set_zoom(canvas.zoom/1.25))
	zoom_label=_button(footer,"100%",func(): canvas.set_zoom(1),"Actual pixels")
	_button(footer,"+",func(): canvas.set_zoom(canvas.zoom*1.25))
	_button(footer,"Fit",canvas.fit,"Fit canvas · F")
	_register_commands()


func _process(_delta: float) -> void:
	if renderer.exporting: return
	var enabled:=is_visible_in_tree()
	if enabled!=_last_enabled: renderer.set_enabled(enabled); _last_enabled=enabled
	if not enabled: return
	_context_panel.size=Vector2(_main_split.size.x,_context_panel.get_combined_minimum_size().y)
	_context_panel.global_position=_toolbar_surface.global_position
	preset_panel.global_position=_toolbar_surface.global_position+Vector2(0,_context_panel.size.y+4)
	preset_panel.size=Vector2(_main_split.size.x,preset_panel.get_combined_minimum_size().y)
	_inspector_tool_spacer.custom_minimum_size.y=_context_panel.size.y+4+(preset_panel.size.y+4 if preset_panel.visible else 0)
	_toolbar_surface.custom_minimum_size.y=_inspector_tool_spacer.custom_minimum_size.y
	if canvas.tool=="path" and document.layer_for_id(canvas.path_layer_id)==null: _set_tool("move"); canvas.path_layer_id=""
	if document!=null:
		renderer.set_preview_camera(canvas.size,canvas.origin(),canvas.zoom)
		canvas.preview_screen_space=true
	zoom_label.text="%d%%" % roundi(canvas.zoom*100)
	if _refresh_pending:
		_refresh_pending=false; renderer.sync(document); canvas.preview=renderer.texture(); canvas.queue_redraw()
	if _tree_pending:
		_tree_pending=false; _refresh_layers()
	if renderer.views.has(canvas.path_layer_id):
		var polygon_layer:=document.layer_for_id(canvas.path_layer_id)
		renderer.views[canvas.path_layer_id].output.visible=canvas.tool!="path" and polygon_layer!=null and document.isolation_allows(polygon_layer)
	if not _inline_text_layer_id.is_empty() and renderer.views.has(_inline_text_layer_id):
		renderer.views[_inline_text_layer_id].direct_text.hide()
		renderer.views[_inline_text_layer_id].output.hide()


func open_source(value: Variant,state: Dictionary={}) -> void:
	_edit_version+=1
	_flatten_cache=null
	source=value
	path=str(value) if value is String else ""
	if value is Texture2D and value.resource_path.get_extension().to_lower() in SAVE_FORMATS:
		path=value.resource_path
	document_path=str(state.get("document_path",""))
	_dirty=bool(state.get("dirty",false))
	_undo.assign(state.get("undo",[])); _redo.assign(state.get("redo",[]))
	if state.get("document") is KiwiImageDocument:
		document=state.document.snapshot()
	elif value is String and value.get_extension().to_lower() in ["tres","res"]:
		document=ResourceLoader.load(value,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiImageDocument
		document_path=path
	elif value is KiwiImageDocument:
		document=value.snapshot()
	elif value is Texture2D and value.has_meta("kiwi_image_document"):
		document=(value.get_meta("kiwi_image_document") as KiwiImageDocument).snapshot()
	else:
		document=null
		if document == null:
			document=Document.new()
			image=ActorImageGenerator.image_from_value(value) if value != null else null
			if image!=null and not image.is_empty():
				document.canvas_size=image.get_size()
				var layer:=Layer.create("image",document.canvas_size)
				layer.label=path.get_file().get_basename() if not path.is_empty() else "Background"
				layer.texture=ImageTexture.create_from_image(image)
				layer.paint_base=layer.texture
				document.layers.append(layer)
			else:
				document.layers.append(Layer.create("basic",document.canvas_size))
			document.output_path=path
	if document == null: document=Document.new()
	canvas.document=document
	var ui: Dictionary=state.get("ui",document.workspace_state)
	_macros=ui.get("macros",{}).duplicate(true)
	_variants=ui.get("variants",{}).duplicate()
	_recent_assets.assign(ui.get("recent_assets",[]))
	_custom_shortcuts=ui.get("custom_shortcuts",{}).duplicate()
	canvas.selected.assign(ui.get("selected",[]))
	if canvas.selected.is_empty() and not document.layers.is_empty(): canvas.selected.append(document.layers[-1].id)
	canvas.zoom=float(ui.get("zoom",.7)); canvas.pan=ui.get("pan",Vector2.ZERO)
	canvas.clear_selection(); canvas.tool=str(ui.get("tool","move"))
	canvas.pixel_mode=str(ui.get("pixel_mode","brush")); canvas.pixel_box_select=bool(ui.get("pixel_box_select",false))
	if canvas.tool in ["crop","lasso_crop"]: canvas.pixel_mode=canvas.tool; canvas.tool="pixel_select"
	if bool(ui.get("effects_open",false)): canvas.tool="effects"
	_effects_open=false; _effects_filter=str(ui.get("effects_filter","")); _effects_search.text=_effects_filter
	_effects_signature=""; _effects_button.set_pressed_no_signal(canvas.tool=="effects")
	canvas.paint_selection_only=bool(ui.get("paint_selection_only",false))
	canvas.stroke_correct=bool(ui.get("stroke_correct",canvas.stroke_correct))
	canvas.brush_type=str(ui.get("brush_type",canvas.brush_type)); canvas.soften_strength=float(ui.get("soften_strength",canvas.soften_strength))
	canvas.correction_strength=float(ui.get("correction_strength",canvas.correction_strength))
	canvas.correction_scale=clampf(float(ui.get("correction_scale",canvas.correction_scale)),.1,16)
	canvas.pixel_match_all=bool(ui.get("pixel_match_all",false))
	canvas.edge_magnet=bool(ui.get("edge_magnet",false)); canvas.edge_threshold=float(ui.get("edge_threshold",.4))
	canvas.object_threshold=float(ui.get("object_threshold",.5)); canvas.smart_selection.invalidate()
	canvas.selection_alpha=float(ui.get("selection_alpha",1)); canvas.selection_falloff=float(ui.get("selection_falloff",0))
	canvas.warp_tool.restore_settings(ui.get("warp_settings",{}))
	canvas.repair_tool.restore_settings(ui.get("repair_settings",{}))
	canvas.sync_pixel_selection()
	_main_split.split_offset=int(ui.get("main_split",1000)); _side_split.split_offset=int(ui.get("side_split",280))
	renderer._topology="_unbuilt_"; renderer.sync(document); canvas.preview=renderer.texture()
	_refresh_layers(); _refresh_inspector(); _refresh_context()
	_update_title()
	if ui.is_empty(): canvas.call_deferred("fit")
	status.text=_tool_hint()
	if canvas.tool=="pixel_select": _prepare_pixel_selection()


func capture_state() -> Dictionary:
	_finish_pending()
	return {"document":document.snapshot(),"document_path":document_path,"dirty":_dirty,
		"undo":_undo.duplicate(),"redo":_redo.duplicate(),"ui":_ui_state()}


func _ui_state() -> Dictionary:
	return {"selected":canvas.selected.duplicate(),"zoom":canvas.zoom,"pan":canvas.pan,"tool":canvas.tool,
		"pixel_mode":canvas.pixel_mode,"pixel_box_select":canvas.pixel_box_select,"effects_open":_effects_open,"effects_filter":_effects_filter,
		"stroke_correct":canvas.stroke_correct,"correction_strength":canvas.correction_strength,
		"brush_type":canvas.brush_type,"soften_strength":canvas.soften_strength,
		"correction_scale":canvas.correction_scale,
		"paint_selection_only":canvas.paint_selection_only,"pixel_match_all":canvas.pixel_match_all,
		"edge_magnet":canvas.edge_magnet,"edge_threshold":canvas.edge_threshold,"object_threshold":canvas.object_threshold,
		"warp_settings":canvas.warp_tool.settings(),
		"repair_settings":canvas.repair_tool.settings(),
		"selection_alpha":canvas.selection_alpha,"selection_falloff":canvas.selection_falloff,
		"main_split":_main_split.split_offset,"side_split":_side_split.split_offset,
		"macros":_macros.duplicate(true),"variants":_variants.duplicate(),"recent_assets":_recent_assets.duplicate(),"custom_shortcuts":_custom_shortcuts.duplicate()}


func _begin() -> void:
	_edit_version+=1
	_flatten_cache=null
	if _before == null and document != null:
		_before=document.snapshot(); _selection_transform_active=false
		if _before.pixel_selection!=null and _before.pixel_selection_reference==null:
			var owner:=_before.layer_for_id(_before.pixel_selection_owner)
			if owner!=null:
				_before.pixel_selection_reference=owner.copy_layer()
				_before.pixel_selection_reference_world=_before.world_transform(owner)
				document.pixel_selection_reference=owner.copy_layer()
				document.pixel_selection_reference_world=_before.pixel_selection_reference_world
		for layer in document.layers:
			if layer.properties.get("values_selection")!=null and not layer.properties.has("values_selection_frame"):
				layer.properties.values_selection_frame=document.world_transform(layer)
				layer.properties.values_selection_dimensions=layer.dimensions


func _preview() -> void:
	_sync_selection_transform()
	_sync_linked_styles()
	_edit_version+=1
	_flatten_cache=null
	if renderer.exporting: _refresh_pending=true; return
	# Resizing reallocates several dependent SubViewports. Keep the last complete
	# composite visible during the drag and rebuild once on release to avoid a
	# black frame between GPU allocations.
	if canvas._drag.begins_with("resize") or _sizing_preview:
		renderer.sync_transforms(document); canvas.preview=renderer.texture()
		_sync_context_values()
		canvas.queue_redraw()
		return
	_refresh_pending=true
	_sync_context_values()


func _commit() -> void:
	if _before == null: return
	_sync_selection_transform()
	_sync_linked_styles()
	# Keep the original mask and its reference layer. Baking here used to clip
	# off-canvas pixels and could only approximate perspective yaw.
	_sizing_preview=false
	_store_active_mask()
	_undo.append(_before); _before=null
	if _undo.size()>40: _undo.pop_front()
	_redo.clear(); _dirty=true
	_refresh_pending=true; _tree_pending=true
	document_changed.emit(); _update_title()


func _sync_selection_transform() -> void:
	if _before==null or _before.pixel_selection==null: return
	var old:=_before.pixel_selection_reference
	if old==null: old=_before.layer_for_id(_before.pixel_selection_owner)
	var current:=document.layer_for_id(_before.pixel_selection_owner)
	if old==null or current==null: return
	var from:=_before.pixel_selection_reference_world if _before.pixel_selection_reference!=null else _before.world_transform(old)
	var to:=document.world_transform(current)
	var same_yaw:=is_equal_approx(float(old.properties.get("yaw_up_down",0)),float(current.properties.get("yaw_up_down",0))) and is_equal_approx(float(old.properties.get("yaw_left_right",0)),float(current.properties.get("yaw_left_right",0)))
	if from.is_equal_approx(to) and old.dimensions.is_equal_approx(current.dimensions) and same_yaw:
		canvas.selection_forward_warp=Callable(); canvas.selection_inverse_warp=Callable()
		canvas.selection_transform=Transform2D.IDENTITY; canvas.selection_inverse=Transform2D.IDENTITY
		canvas._update_selection_preview()
		_selection_transform_active=true
		return
	if not _selection_transform_active:
		# A layer transform starts from the immutable anchored mask. Mask-painting
		# gestures take the identity branch above and retain their live edits.
		canvas.selection=_before.pixel_selection.get_image().duplicate()
		canvas.selection_texture=null
	var current_state:=current.copy_layer()
	var forward:=func(point: Vector2) -> Vector2:
		var local:=old.unproject_point(from.affine_inverse()*point)
		return to*current_state.project_point(local/old.dimensions.max(Vector2.ONE)*current_state.dimensions)
	var inverse:=func(point: Vector2) -> Vector2:
		var local:=current_state.unproject_point(to.affine_inverse()*point)
		return from*old.project_point(local/current_state.dimensions.max(Vector2.ONE)*old.dimensions)
	_selection_transform_active=true
	canvas.selection_transform=Transform2D.IDENTITY; canvas.selection_inverse=Transform2D.IDENTITY
	canvas.selection_forward_warp=forward; canvas.selection_inverse_warp=inverse
	canvas._update_selection_preview()


func _cancel() -> void:
	if _before == null: return
	_sizing_preview=false
	document=_before; _before=null; canvas.document=document
	_refresh_pending=true; _refresh_inspector(); _refresh_layers(); _refresh_context()


func _finish_pending() -> void:
	if canvas.warp_tool.active: canvas.warp_tool.finish()
	if canvas.repair_tool.active: canvas.repair_tool.cancel()
	if canvas._drag in ["object_preview","edge_pending"]:
		if canvas._drag=="object_preview" and canvas._smart_ready: canvas.commit_object_selection()
		else: canvas.cancel_gesture()
	if canvas._drag in ["pixel_select","pixel_box","pixel_lasso"]: canvas._finish(canvas._last)
	canvas.confirm_stroke()
	if _before != null: _commit()


func _action(operation: Callable) -> void:
	_finish_pending(); _begin(); operation.call(); _commit()
	_refresh_inspector(); _refresh_context()


func undo() -> void:
	_edit_version+=1
	_flatten_cache=null
	_finish_pending()
	if _undo.is_empty(): return
	_redo.append(document.snapshot()); document=_undo.pop_back(); _restored()


func redo() -> void:
	_edit_version+=1
	_flatten_cache=null
	_finish_pending()
	if _redo.is_empty(): return
	_undo.append(document.snapshot()); document=_redo.pop_back(); _restored()


func _restored() -> void:
	canvas.document=document
	canvas.selected.assign(canvas.selected.filter(func(id: String): return document.layer_for_id(id)!=null))
	if canvas.selected.is_empty() and document.layer_for_id(document.pixel_selection_owner)!=null: canvas.selected.append(document.pixel_selection_owner)
	canvas.sync_pixel_selection()
	if canvas.tool=="pixel_select": _prepare_pixel_selection()
	if canvas.tool=="path":
		var polygon:=document.layer_for_id(canvas.path_layer_id)
		if polygon!=null: _draw_custom_shape(polygon)
		else: _set_tool("move")
	_refresh_pending=true; _refresh_layers(); _refresh_inspector(); _refresh_context()
	var material_browser:=get_node_or_null("MaterialBrowser")
	if material_browser!=null: material_browser.refresh_from_layer()
	_dirty=true; _update_title(); document_changed.emit()


func _update_title() -> void:
	title_label.text=(path.get_file() if not path.is_empty() else "Untitled composition")+("  •" if _dirty else "")
	title_label.tooltip_text=path


func add_layer(kind: String) -> KiwiImageLayer:
	canvas.grab_focus()
	var layer:=Layer.create(kind,document.canvas_size)
	if kind in ["text","shape"]:
		layer.dimensions=(canvas.size/canvas.zoom*Vector2(.45,.3)).max(Vector2(20,20))
		layer.position=canvas.to_document(canvas.size*.5)-layer.dimensions*.5
		if kind=="text": layer.properties.text_settings.values.font_size=maxf(1,layer.dimensions.y*.24)
	if kind in ["shape","gradient","path"]: layer.properties.color=color_picker.color
	_action(func():
		document.layers.append(layer); canvas.selected.assign([layer.id]))
	_selection_changed()
	return layer


func _add_layer_from_toolbar(kind: String) -> void:
	add_layer(kind)
	if kind=="image": _replace_image()


func _show_add_layer() -> void:
	var popup:=PopupPanel.new(); popup.add_theme_stylebox_override("panel",_box(Color("14212e"),Color("4d8b7e"),12,14)); add_child(popup)
	var column:=VBoxContainer.new(); column.custom_minimum_size=Vector2(430,330); column.add_theme_constant_override("separation",10); popup.add_child(column)
	var heading:=Label.new(); heading.text="Create a new layer"; heading.add_theme_font_size_override("font_size",19); column.add_child(heading)
	var subtitle:=Label.new(); subtitle.text="Start editable, then paint, mask, add effects, duplicate, or merge whenever you need."; subtitle.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; subtitle.add_theme_color_override("font_color",Color("8fa8bb")); column.add_child(subtitle)
	var grid:=GridContainer.new(); grid.columns=2; grid.add_theme_constant_override("h_separation",8); grid.add_theme_constant_override("v_separation",8); column.add_child(grid)
	var choices: Array=[
		["Basic / Empty","Transparent pixels for painting and compositing","basic","paint"],
		["Image","Choose an image from the project","import","image"],
		["Text","Editable type with system fonts","text","text"],
		["Shape","Rectangle, ellipse, triangle or custom polygon","shape","shape"]]
	for choice: Array in choices:
		var card:=Button.new(); card.text=str(choice[0])+"\n"+str(choice[1]); card.alignment=HORIZONTAL_ALIGNMENT_LEFT
		card.icon=_icon(str(choice[3])); card.expand_icon=true; card.add_theme_constant_override("icon_max_width",24)
		card.custom_minimum_size=Vector2(202,54); grid.add_child(card)
		var kind: String=choice[2]
		card.pressed.connect(func(): _create_layer_choice(kind,popup))
	popup.popup_hide.connect(popup.queue_free); popup.popup_centered(Vector2i(470,390))


func _create_layer_choice(kind: String,popup: PopupPanel) -> void:
	popup.hide()
	if kind=="import": _choose_import()
	else: add_layer(kind)


func _create_at(kind: String,bounds: Rect2,points: PackedVector2Array) -> void:
	if kind in ["crop","lasso_crop"]:
		_apply_crop(bounds,points)
		return
	if kind=="path":
		if Geometry2D.triangulate_polygon(points).is_empty():
			status.text="Use at least three non-collinear points without crossing edges."; return
		var target:=document.layer_for_id(canvas.path_layer_id)
		if target==null: return
		_action(func():
			var parent:=document.layer_for_id(target.parent_id)
			var inverse:=document.world_transform(parent).affine_inverse() if parent!=null else Transform2D.IDENTITY
			target.dimensions=bounds.size.max(Vector2.ONE); target.rotation=0
			target.position=inverse*bounds.get_center()-target.dimensions*.5
			target.set_linear_basis(inverse)
			target.properties.shape="custom"; target.properties.points=points; target.properties.path_size=target.dimensions)
		_set_tool("move"); return
	var layer:=Layer.create(kind,document.canvas_size)
	layer.position=bounds.position; layer.dimensions=bounds.size
	if kind!="text": layer.properties.color=color_picker.color
	if kind=="path": layer.properties.points=points; layer.properties.path_size=bounds.size
	_action(func(): document.layers.append(layer); canvas.selected.assign([layer.id]))
	_set_tool("move")
	if kind=="text" and is_instance_valid(_text_input): _text_input.grab_focus(); _text_input.select_all()


func _set_tool(id: String) -> void:
	if canvas.repair_tool.active:
		canvas.repair_tool.finish()
		while canvas.repair_tool.active: await get_tree().process_frame
	if canvas.warp_tool.active: canvas.warp_tool.finish()
	if canvas._drag=="object_preview" and canvas._smart_ready: canvas.commit_object_selection()
	canvas.grab_focus()
	canvas.cancel_gesture()
	if id in ["crop","lasso_crop"]: canvas.tool="pixel_select"; canvas.pixel_mode=id
	else:
		canvas.tool=id
		if id=="pixel_select" and canvas.pixel_mode in ["crop","lasso_crop"]: canvas.pixel_mode="brush"
	canvas.sync_pixel_selection()
	if canvas.tool=="pixel_select" and canvas.pixel_mode not in ["crop","lasso_crop"]: _prepare_pixel_selection()
	if id in ["brush","eraser","fill"]:
		if canvas.selected.is_empty(): add_layer("basic")
		elif _main_layer()!=null and _main_layer().kind not in ["image","paint","basic"]: rasterize_selected()
	_refresh_context()
	for key in tool_buttons: tool_buttons[key].set_pressed_no_signal(key==canvas.tool)
	status.text=_tool_hint(); canvas.queue_redraw()


func _tool_hint() -> String:
	if canvas.tool=="warp":
		if canvas.warp_tool.mode=="mesh": return "Drag points to deform · Shift+wheel: radius · Shift-click: select mesh points · Esc: cancel"
		return "Drag to deform · Shift+wheel: size · Shift-click: select mesh points · Ctrl-click pin: lock · Right-click pin: delete · Esc: cancel"
	if canvas.tool=="repair": return "Drag: repair or paint texture · Alt-click / drag: sample · Shift+wheel: size · Space: pan · Esc: cancel"
	if canvas.tool=="pixel_select" and canvas.pixel_mode in ["crop","lasso_crop"]:
		return "Drag a crop region · Release applies · Right-click / Esc cancels"
	if canvas.tool=="pixel_select" and canvas.pixel_box_select and canvas.pixel_mode in ["brush","erase"]:
		return "Drag: box select · Shift-drag: lasso select · Ctrl: subtract · Esc: cancel"
	var hints:={"move":"Drag to move · Ctrl toggles snap · Shift constrains · Alt-drag duplicates · Space pans · Wheel zooms",
		"brush":"Ctrl: erase · Shift+wheel: size · "+("Alt+wheel: scale · " if canvas.stroke_correct else "")+"Shift/Q/O: line/curve/circle · 0–9: presets · Esc: cancel",
		"eraser":"Erase on selected layer · Shift+wheel: size · [ / ] brush size · Esc cancels",
		"path":"Click adds points · Enter closes polygon · Esc cancels",
		"pixel_select":"Ctrl: subtract pixels · Shift+wheel: size / fill threshold · Ctrl+Z undoes · Copy / Delete / Extract",
		"fill":"Click: fill · Ctrl+click: erase region · Shift+wheel: threshold · Ctrl+Z undoes",
		"lasso_crop":"Draw around the crop · Release applies · Right-click / Esc cancels",
		"shape":"Drag to create a shape · Edit fill, stroke, and corners in Properties",
		"text":"Click to add text · Double-click existing text to edit",
		"crop":"Drag a crop region · Right-click / Esc cancels · Choose extract, copy, or remove above"}
	return str(hints.get(canvas.tool,"Space pans · Wheel zooms · Ctrl+K searches actions"))


func _clear(parent: Node) -> void:
	for child in parent.get_children(): parent.remove_child(child); child.queue_free()


func _tool_section(rail: Node,caption: String,entries: Array) -> void:
	var panel:=PanelContainer.new(); panel.name=caption.capitalize()+"Tools"
	panel.add_theme_stylebox_override("panel",_box(Color("15232d"),Color("2b414d"),6,3)); rail.add_child(panel)
	var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",3); panel.add_child(column)
	var label:=Label.new(); label.text=caption; label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",8); label.add_theme_color_override("font_color",Color("85a4b1")); column.add_child(label)
	for entry in entries:
		var id: String=entry[0]
		var button:=_button(column,"",func(): _set_tool(id),entry[1],"mask" if id=="pixel_select" else id)
		button.custom_minimum_size=Vector2(34,33); button.toggle_mode=true; tool_buttons[id]=button

func _refresh_context() -> void:
	_clear(context)
	_context_host=context
	if canvas.tool in ["pixel_select","repair"]:
		var rows:=VBoxContainer.new(); rows.name="ContextRows"; rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL; rows.add_theme_constant_override("separation",3); context.add_child(rows)
		_next_toolbar_row()
	if canvas.tool=="brush":
		# Brush controls are one row; narrow windows scroll instead of wrapping
		# controls onto a second row and taking space away from the canvas.
		var scroll:=ScrollContainer.new(); scroll.name="BrushToolbarScroll"
		scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
		scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		context.add_child(scroll)
		var row:=HBoxContainer.new(); row.name="BrushToolbarRow"
		row.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_theme_constant_override("separation",5)
		scroll.add_child(row); _context_host=row
	_clear(preset_context); preset_panel.visible=false
	_context_fields.clear()
	var tool_icon:=TextureRect.new(); tool_icon.texture=_icon("lasso" if canvas.tool=="lasso_crop" else ("mask" if canvas.tool=="pixel_select" else canvas.tool)); tool_icon.custom_minimum_size=Vector2(22,22); tool_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; tool_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; tool_icon.size_flags_vertical=Control.SIZE_SHRINK_CENTER; _context_host.add_child(tool_icon)
	var label:=Label.new(); label.text=canvas.tool.replace("_"," ").capitalize()
	label.custom_minimum_size.x=62; label.size_flags_vertical=Control.SIZE_SHRINK_CENTER; label.add_theme_color_override("font_color",Color("7fe3cd")); _context_host.add_child(label)
	if canvas.tool=="brush": label.custom_minimum_size.x=48
	if canvas.tool=="warp":
		preload("res://Workspaces/ImageWorkspace/image_warp_toolbar.gd").build(self)
		return
	if canvas.tool=="repair":
		preload("res://Workspaces/ImageWorkspace/image_repair_toolbar.gd").build(self)
		return
	if canvas.tool in ["values","effects"]:
		_button(context,"Adjustments" if canvas.tool=="values" else "Effects",func(): _open_stack_editor(canvas.tool=="values"),"Choose, order, and preview adjustments" if canvas.tool=="values" else "Choose, order, and preview effects",canvas.tool)
		if not canvas.selected.is_empty():
			var layer:=document.layer_for_id(canvas.selected[-1])
			if layer!=null:
				if canvas.tool=="effects": _effect_selection_control(context,layer)
				else:
					var selected_only:=CheckButton.new(); selected_only.name="ValuesSelectionOnly"; selected_only.text="Affect selected pixels only"; selected_only.button_pressed=layer.properties.get("values_selection_only",false); context.add_child(selected_only)
					selected_only.toggled.connect(_set_adjustment_selection_only)
		return
	if canvas.tool=="pixel_select":
		_pixel_threshold_control("Selection Alpha",canvas.selection_alpha,func(value: float): canvas.selection_alpha=value; if canvas._drag=="object_preview": canvas.set_object_threshold(canvas.object_threshold))
		_pixel_threshold_control("Selection Falloff",canvas.selection_falloff,func(value: float): canvas.selection_falloff=value; if canvas._drag=="object_preview": canvas.set_object_threshold(canvas.object_threshold))
		var modes:=_toolbar_group("SELECT PIXELS","mask")
		for entry in [["brush","brush","Paint selection"],["erase","eraser","Erase selection"],["fill","fill","Select connected colors"],["object","mask","Object Selector"]]:
			var mode: String=entry[0]
			var button:=_button(modes,"",func():
				if canvas._drag=="object_preview" and canvas._smart_ready: canvas.commit_object_selection()
				canvas.cancel_gesture(); canvas.pixel_mode=mode; _refresh_context()
				if mode not in ["crop","lasso_crop"]: _prepare_pixel_selection(),entry[2],entry[1])
			button.toggle_mode=true; button.button_pressed=canvas.pixel_mode==mode
		var value:=DragNumber.new(); value.custom_minimum_size.x=96
		if canvas.pixel_mode in ["brush","fill"]:
			var magnet:=CheckButton.new(); magnet.text="Edge Magnet"; magnet.name="EdgeMagnet"; magnet.button_pressed=canvas.edge_magnet
			modes.add_child(magnet)
			magnet.toggled.connect(func(enabled: bool): canvas.cancel_gesture(); canvas.edge_magnet=enabled; canvas.pixel_box_select=false if enabled else canvas.pixel_box_select; canvas.prepare_smart_selection(); _refresh_context())
			if canvas.edge_magnet:
				_pixel_threshold_control("Edge Threshold",canvas.edge_threshold,func(next: float): canvas.edge_threshold=next; canvas.queue_redraw())
		if canvas.pixel_mode=="object":
			value.queue_free(); _pixel_threshold_control("Object Threshold",canvas.object_threshold,canvas.set_object_threshold)
			var proposal:=_toolbar_group("OBJECT SELECTION","mask")
			_button(proposal,"Apply",canvas.commit_object_selection,"Commit the proposed selection · Enter","check")
			_button(proposal,"Cancel",canvas.cancel_gesture,"Discard the proposed selection · Esc","close")
		elif canvas.pixel_mode=="fill" and not canvas.edge_magnet:
			var all_colors:=CheckButton.new(); all_colors.text="All matching colors"; all_colors.button_pressed=canvas.pixel_match_all; modes.add_child(all_colors)
			all_colors.toggled.connect(func(enabled: bool): canvas.pixel_match_all=enabled)
			value.min_value=0; value.max_value=1; value.step=.01; value.value=canvas.fill_threshold
			value.value_changed.connect(func(next: float): canvas.fill_threshold=clampf(next,0,1)); value.preview_changed.connect(func(next: float): canvas.fill_threshold=clampf(next,0,1))
			_toolbar_group("THRESHOLD","hardness").add_child(value)
		elif canvas.pixel_mode in ["brush","erase"] or (canvas.pixel_mode=="fill" and canvas.edge_magnet):
			var box:=CheckButton.new(); box.text="Box select"; box.name="PixelBoxSelect"; box.button_pressed=canvas.pixel_box_select; modes.add_child(box)
			box.visible=canvas.pixel_mode in ["brush","erase"] and not canvas.edge_magnet
			box.tooltip_text="Box-select pixels · Shift-drag: lasso · Ctrl: subtract"
			box.toggled.connect(func(enabled: bool): canvas.cancel_gesture(); canvas.pixel_box_select=enabled; _refresh_context())
			value.min_value=1; value.max_value=500; value.value=canvas.brush_size; value.suffix="px"
			value.value_changed.connect(func(next: float): canvas.brush_size=clampf(next,1,500)); value.preview_changed.connect(func(next: float): canvas.brush_size=clampf(next,1,500))
			if not canvas.pixel_box_select or canvas.edge_magnet: _toolbar_group("SIZE","brush").add_child(value)
			else: value.queue_free()
		else:
			value.queue_free(); _crop_controls()
		_next_toolbar_row()
		var actions:=_toolbar_group("SELECTED PIXELS","layers")
		_button(actions,"Copy",func(): _apply_pixel_selection("copy"),"Copy selected pixels into a new layer","duplicate")
		_button(actions,"Delete",func(): _apply_pixel_selection("delete"),"Delete selected pixels","trash")
		_button(actions,"Extract",func(): _apply_pixel_selection("extract"),"Move selected pixels to a new layer","crop")
		var selection_tools:=_toolbar_group("SELECTION","mask")
		var fill_group:=_toolbar_group("COLOR FILL","fill")
		var fill_color:=ColorPickerButton.new(); fill_color.color=_selection_fill_color; fill_color.custom_minimum_size=Vector2(48,28); fill_group.add_child(fill_color)
		fill_color.color_changed.connect(func(value: Color): _selection_fill_color=value)
		_button(fill_group,"Confirm",func(): preload("res://Workspaces/ImageWorkspace/image_selection_fill.gd").apply(self,_selection_fill_color),"Fill selected pixels on the active layer","check")
		_button(selection_tools,"Clear",func(): _action(func(): document.pixel_selection=null); canvas.sync_pixel_selection(),"Clear the pixel selection")
		_button(selection_tools,"Opaque",func(): _select_pixel_region(false),"Select every pixel with non-zero alpha")
		_button(selection_tools,"Invert",func(): _select_pixel_region(true),"Invert pixel selection · Ctrl+I")
		_selection_mask_controls()
	elif canvas.tool in ["brush","eraser"]:
		_paint_selection_toggle()
		brush_size=DragNumber.new(); brush_size.min_value=1; brush_size.max_value=500; brush_size.value=canvas.brush_size; brush_size.suffix="px"; brush_size.custom_minimum_size.x=80
		_toolbar_group("BRUSH SIZE","brush").add_child(brush_size)
		brush_size.value_changed.connect(func(value: float): canvas.brush_size=value)
		brush_size.preview_changed.connect(func(value: float): canvas.brush_size=value; canvas.queue_redraw())
		var opacity_group:=_toolbar_group("OPACITY","opacity")
		var opacity:=HSlider.new(); opacity.min_value=.01; opacity.max_value=1; opacity.step=.01; opacity.value=canvas.brush_opacity; opacity.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		opacity.custom_minimum_size=Vector2(80,32); opacity.tooltip_text="Brush opacity"; opacity_group.add_child(opacity)
		opacity.value_changed.connect(func(value: float): canvas.brush_opacity=value)
		var hardness_group:=_toolbar_group("HARDNESS","hardness")
		var hardness:=HSlider.new(); hardness.min_value=0; hardness.max_value=1; hardness.step=.01; hardness.value=canvas.hardness; hardness.custom_minimum_size=Vector2(80,32); hardness.size_flags_vertical=Control.SIZE_SHRINK_CENTER; hardness_group.add_child(hardness)
		hardness.value_changed.connect(func(value: float): canvas.hardness=value)
		if canvas.tool=="brush":
			if canvas.brush_type!="soften":
				var paint_group:=_toolbar_group("PAINT","layers")
				_context_color("Color",paint_group)
				_toolbar_toggle(paint_group,"plus",canvas.paint_new_layer,"Draw each stroke on a new layer",func(value: bool): canvas.paint_new_layer=value)
			var correction_group:=_toolbar_group("STROKE","effects")
			# Prioritize correction beside the tool title, before groups that can wrap.
			_context_host.move_child(correction_group.get_parent().get_parent(),2)
			preload("res://Workspaces/ImageWorkspace/image_warp_picker.gd").build(self,correction_group,"BrushType","BRUSH TYPE",["normal","stroke_correct","soften"],["Normal","Stroke Correct","Soften"],canvas.brush_type,func(index: int):
				_finish_pending(); canvas.cancel_gesture(); canvas.brush_type=["normal","stroke_correct","soften"][index]; _refresh_context(); status.text=_tool_hint(); _persist_paint_presets())
			var strength:=HSlider.new(); strength.min_value=0; strength.max_value=100; strength.step=1
			strength.name="SoftenStrength" if canvas.brush_type=="soften" else "CorrectionStrength"
			strength.value=(canvas.soften_strength if canvas.brush_type=="soften" else canvas.correction_strength)*100; strength.custom_minimum_size=Vector2(85,28)
			strength.tooltip_text="Soften strength" if canvas.brush_type=="soften" else "Correction strength"
			var strength_caption:=Label.new(); strength_caption.text="Strength"; strength_caption.add_theme_font_size_override("font_size",11); strength_caption.visible=canvas.brush_type!="normal"; correction_group.add_child(strength_caption)
			strength.size_flags_vertical=Control.SIZE_SHRINK_CENTER; correction_group.add_child(strength)
			var strength_label:=Label.new(); strength_label.text="%d%%" % strength.value; strength_label.custom_minimum_size.x=34; correction_group.add_child(strength_label)
			strength.visible=canvas.brush_type!="normal"; strength_label.visible=canvas.brush_type!="normal"
			strength.drag_started.connect(func(): strength.set_meta("dragging",true))
			strength.value_changed.connect(func(value: float):
				if canvas.brush_type=="soften": canvas.soften_strength=value/100.0
				else: canvas.correction_strength=value/100.0
				strength_label.text="%d%%" % value
				if not bool(strength.get_meta("dragging",false)): _persist_paint_presets())
			strength.drag_ended.connect(func(_changed: bool):
				strength.set_meta("dragging",false); _persist_paint_presets())
			var scale_label:=Label.new(); scale_label.text="Scale"; correction_group.add_child(scale_label)
			var scale:=DragNumber.new(); scale.name="CorrectionScale"; scale.min_value=.1; scale.max_value=16; scale.step=.01
			scale.value=canvas.correction_scale; scale.suffix="×"; scale.custom_minimum_size=Vector2(72,28)
			scale.tooltip_text="Smooth broader shapes at larger scales · Gap closing stays within 16 image pixels · Alt+wheel"
			correction_group.add_child(scale); _context_fields.correction_scale=scale
			scale.visible=canvas.stroke_correct; scale_label.visible=canvas.stroke_correct
			scale.value_changed.connect(func(value: float): canvas.correction_scale=value; _persist_paint_presets())
			scale.preview_changed.connect(func(value: float): canvas.correction_scale=value)
			scale.drag_committed.connect(func(value: float): canvas.correction_scale=value; _persist_paint_presets())
			scale.drag_cancelled.connect(func(): canvas.correction_scale=scale.value)
		_paint_preset_controls(canvas.tool)
	elif canvas.tool=="fill":
		_paint_selection_toggle()
		_context_color("Color",_toolbar_group("FILL COLOR","fill"))
		var threshold_group:=_toolbar_group("COLOR TOLERANCE","hardness")
		var threshold:=HSlider.new(); threshold.min_value=0; threshold.max_value=1; threshold.step=.01; threshold.value=canvas.fill_threshold; threshold.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		threshold.custom_minimum_size=Vector2(180,32); threshold.tooltip_text="How different neighboring colors may be and still get filled"; threshold_group.add_child(threshold)
		threshold.value_changed.connect(func(value: float): canvas.fill_threshold=value)
		_paint_preset_controls("fill")
	elif canvas.tool in ["crop","lasso_crop"]:
		var scope:=CheckButton.new(); scope.text="Crop entire image"; scope.button_pressed=_crop_canvas; context.add_child(scope)
		scope.toggled.connect(func(value: bool): _crop_canvas=value; _refresh_context())
		if not _crop_canvas:
			var mode:=OptionButton.new(); mode.add_item("Extract + remove original"); mode.add_item("Copy to new layer"); mode.add_item("Remove only")
			mode.select(_crop_action); mode.tooltip_text="What happens to the selected layer(s)"; context.add_child(mode)
			mode.item_selected.connect(func(value: int): _crop_action=value)
	elif canvas.tool=="path":
		_toolbar_toggle(_toolbar_group("SNAP","snap"),"snap",canvas.snapping,"Snap vertices to points, canvas, and layer edges · Ctrl temporarily toggles",func(value: bool): canvas.snapping=value)
	else:
		_toolbar_toggle(_toolbar_group("SNAP","snap"),"snap",canvas.snapping,"Snap to canvas and layers · Ctrl temporarily toggles",func(value: bool): canvas.snapping=value)
		var layer:=_main_layer()
		if layer!=null and canvas.tool in ["move","rect_select","lasso"]:
			var position_group:=_toolbar_group("POSITION","position")
			_context_fields.x=_compact_number("X",layer.position.x,func(value: float): _set_common("position_x",value),-100000,100000,position_group)
			_context_fields.y=_compact_number("Y",layer.position.y,func(value: float): _set_common("position_y",value),-100000,100000,position_group)
			var size_group:=_toolbar_group("SIZE","fit_layer")
			_context_fields.width=_compact_number("W",layer.dimensions.x*(-1 if bool(layer.properties.get("flip_x",false)) else 1),func(value: float): _set_common("width",value),-100000,100000,size_group)
			_context_fields.height=_compact_number("H",layer.dimensions.y*(-1 if bool(layer.properties.get("flip_y",false)) else 1),func(value: float): _set_common("height",value),-100000,100000,size_group)
			if layer.kind in ["image","text","shape"]: _toolbar_toggle(size_group,"aspect",bool(layer.properties.get("keep_aspect",false)),"Keep aspect ratio",func(value: bool): _action(func(): _set_common("keep_aspect",value)))
			var orientation:=_toolbar_group("ROTATION & TILT","rotate")
			_context_fields.rotation=_compact_number("°",rad_to_deg(layer.rotation),func(value: float): _set_common("rotation",deg_to_rad(value)),-100000,100000,orientation)
			_button(orientation,"↺",func(): _action(func(): _set_common("rotation",0.0)),"Reset rotation")
			_compact_number("↕",float(layer.properties.get("yaw_up_down",0)),func(value: float): _set_common("yaw_up_down",clampf(value,-89,89)),-89,89,orientation).tooltip_text="Tilt up / down"
			_button(orientation,"↺",func(): _action(func(): _set_common("yaw_up_down",0.0)),"Reset vertical yaw")
			_compact_number("↔",float(layer.properties.get("yaw_left_right",0)),func(value: float): _set_common("yaw_left_right",clampf(value,-89,89)),-89,89,orientation).tooltip_text="Tilt left / right"
			_button(orientation,"↺",func(): _action(func(): _set_common("yaw_left_right",0.0)),"Reset horizontal yaw")
			var appearance:=_toolbar_group("APPEARANCE","opacity")
			_context_fields.opacity=_compact_number("α",layer.opacity,func(value: float): _set_common("opacity",clampf(value,0,1)),0,1,appearance)
			var blend:=OptionButton.new(); for blend_name in ["Normal","Add","Subtract","Multiply"]: blend.add_item(blend_name)
			blend.select(layer.blend); blend.tooltip_text="Blend mode"; appearance.add_child(blend)
			blend.item_selected.connect(func(value: int): _action(func(): _set_common("blend",value)))
			var flips:=_toolbar_group("LAYER ACTIONS","layers")
			_button(flips,"",func(): _flip_layer(true),"Flip horizontal","flip_h")
			_button(flips,"",func(): _flip_layer(false),"Flip vertical","flip_v")
			_button(flips,"",fill_selected_to_parent,"Fill parent or canvas","fit_layer")
			if layer.kind=="image": _button(flips,"",resize_image_aspect,"Restore source aspect ratio","aspect")
			_button(flips,"",restore_layer_paint,"Restore drawings and erasures","undo")
		elif layer!=null and layer.kind=="text":
			_button(context,"Font…",_font_menu)
			_number(context,"Size",float(layer.properties.font_size),func(value: float): layer.properties.font_size=int(value),1,1000)
			_color(context,"Fill",layer.properties.color,func(value: Color): layer.properties.color=value)
			_check(context,"Bold",bool(layer.properties.bold),func(value: bool): layer.properties.bold=value)
			_check(context,"Keep ratio",bool(layer.properties.get("keep_aspect",true)),func(value: bool): layer.properties.keep_aspect=value)
		elif layer!=null and layer.kind in ["shape","path"] and canvas.tool!="path":
			_color(context,"Fill",layer.properties.color,func(value: Color): layer.properties.color=value)
			_number(context,"Stroke",float(layer.properties.stroke),func(value: float): layer.properties.stroke=value,0,100)
		elif layer!=null and layer.kind in ["image","paint","basic"]:
			_button(context,"Replace…",_replace_image)
			_button(context,"Mask",selection_to_mask,"Use pixel selection as a mask","mask")
			if layer.kind=="image": _check(context,"Keep ratio",bool(layer.properties.get("keep_aspect",true)),func(value: bool): layer.properties.keep_aspect=value)
		elif not canvas.selected.is_empty():
			_button(context,"Duplicate",duplicate_layers,"Ctrl+D")
			_button(context,"Mask",selection_to_mask,"Use selection as layer mask","mask")
	var spacer:=Control.new(); spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _context_host.add_child(spacer)
	if _main_layer()==null or canvas.tool not in ["move","rect_select","lasso"]:
		var size_info:=Label.new(); size_info.text="%d × %d" % [document.canvas_size.x,document.canvas_size.y]; size_info.add_theme_color_override("font_color",Color("8199ad")); _context_host.add_child(size_info)


func _context_color(caption: String,parent: Node=null) -> void:
	var host:=parent if parent!=null else context
	var picker:=ColorPickerButton.new(); picker.color=color_picker.color; picker.custom_minimum_size=Vector2(56 if canvas.tool=="brush" else 72,32); picker.tooltip_text=caption; host.add_child(picker)
	picker.color_changed.connect(func(value: Color): color_picker.color=value; canvas.color=value)

func _crop_controls() -> void:
	var scope:=CheckButton.new(); scope.text="Crop entire image"; scope.button_pressed=_crop_canvas; context.add_child(scope)
	scope.toggled.connect(func(value: bool): _crop_canvas=value; _refresh_context())
	if not _crop_canvas:
		var mode:=OptionButton.new(); mode.add_item("Extract + remove original"); mode.add_item("Copy to new layer"); mode.add_item("Remove only")
		mode.select(_crop_action); context.add_child(mode)
		mode.item_selected.connect(func(value: int): _crop_action=value)

func _pixel_threshold_control(caption: String,value: float,changed: Callable) -> void:
	var group:=_toolbar_group(caption,"hardness")
	var label:=Label.new(); label.text=caption; group.add_child(label)
	var slider:=HSlider.new(); slider.min_value=0; slider.max_value=100; slider.step=1; slider.value=value*100
	slider.name=caption.replace(" ","")
	slider.custom_minimum_size=Vector2(110,28); slider.size_flags_vertical=Control.SIZE_SHRINK_CENTER; group.add_child(slider)
	var amount:=Label.new(); amount.custom_minimum_size.x=40; amount.text="%d%%" % slider.value; group.add_child(amount)
	slider.value_changed.connect(func(next: float): amount.text="%d%%" % next; changed.call(next/100.0))

func _selection_mask_controls() -> void:
	var group:=_toolbar_group("SAVED MASKS","mask")
	var picker:=OptionButton.new(); picker.name="SelectionMaskPicker"; picker.custom_minimum_size.x=125
	picker.add_item("Working selection"); var ids: Array[String]=[""]
	for id: String in document.selection_masks:
		ids.append(id); picker.add_item(str(document.selection_masks[id].label))
		if id==document.active_selection_mask: picker.select(ids.size()-1)
	group.add_child(picker); picker.item_selected.connect(func(index: int): _activate_selection_mask(ids[index]))
	_button(group,"Save mask",func(): _save_selection_mask(false),"Update the selected mask","save")
	_button(group,"Save new",func(): _save_selection_mask(false,true),"Save the current selection as a new mask","plus")
	_button(group,"＋",func(): _save_selection_mask(true),"Create a new empty mask","plus")
	var remove:=_button(group,"",_remove_selection_mask,"Delete the active saved mask","trash")
	remove.disabled=document.active_selection_mask.is_empty()

func _store_active_mask() -> void:
	var id:=document.active_selection_mask
	if id.is_empty() or not document.selection_masks.has(id): return
	var saved: Dictionary=document.selection_masks[id]
	saved.texture=document.pixel_selection; saved.owner=document.pixel_selection_owner
	saved.reference=document.pixel_selection_reference.copy_layer() if document.pixel_selection_reference!=null else null
	saved.world=document.pixel_selection_reference_world

func _save_selection_mask(empty: bool,new_mask: bool=false) -> void:
	_finish_pending()
	if not empty and not new_mask and document.selection_masks.has(document.active_selection_mask):
		_store_active_mask()
		status.text="Updated "+str(document.selection_masks[document.active_selection_mask].label)
		return
	if not empty and document.pixel_selection==null: status.text="Select some pixels first."; return
	_action(func():
		var id:=ActorData.new_id(); var number:=document.selection_masks.size()+1
		var labels: Array=[]
		for saved in document.selection_masks.values(): labels.append(saved.label)
		while "Mask %d" % number in labels: number+=1
		var label:="Mask %d" % number
		document.selection_masks[id]={"label":label}; document.active_selection_mask=id
		if empty:
			document.pixel_selection=null; document.pixel_selection_owner=canvas.selected[-1] if not canvas.selected.is_empty() else ""
			document.pixel_selection_reference=null; document.pixel_selection_reference_world=Transform2D.IDENTITY)
	canvas.sync_pixel_selection(); _refresh_context()

func _activate_selection_mask(id: String) -> void:
	_finish_pending()
	_action(func():
		document.active_selection_mask=id
		if id.is_empty():
			document.pixel_selection=null; document.pixel_selection_reference=null
		else:
			var saved: Dictionary=document.selection_masks[id]
			document.pixel_selection=saved.get("texture"); document.pixel_selection_owner=str(saved.get("owner",""))
			document.pixel_selection_reference=saved.get("reference"); document.pixel_selection_reference_world=saved.get("world",Transform2D.IDENTITY)
			if document.layer_for_id(document.pixel_selection_owner)!=null: canvas.selected.assign([document.pixel_selection_owner]))
	canvas.sync_pixel_selection(); _selection_changed()

func _remove_selection_mask() -> void:
	var id:=document.active_selection_mask
	if id.is_empty(): return
	_action(func(): document.selection_masks.erase(id); document.active_selection_mask="")
	_refresh_context()


func _load_paint_presets(path: String=PAINT_PRESETS_PATH) -> void:
	if FileAccess.file_exists(path):
		var saved:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if saved!=null:
			canvas.stroke_correct=bool(saved.get_meta("stroke_correct",false))
			canvas.brush_type=str(saved.get_meta("brush_type",canvas.brush_type)); canvas.soften_strength=clampf(float(saved.get_meta("soften_strength",.5)),0,1)
			canvas.correction_strength=clampf(float(saved.get_meta("correction_strength",.5)),0,1)
			canvas.correction_scale=clampf(float(saved.get_meta("correction_scale",1.0)),.1,16)
			var stored: Variant=saved.get_meta("presets",{})
			if stored is Dictionary:
				for key in ["brush","eraser","fill"]:
					if stored.has(key) and stored[key] is Array: _paint_presets[key]=stored[key]
	if (_paint_presets.brush as Array).is_empty():
		_paint_presets.brush=[_preset("Hard round",28,1,1,Color("62d9bc")),_preset("Soft round",54,.5,.12,Color("62d9bc")),_preset("Pencil",3,1,1,Color("d7e8ef"))]
	if (_paint_presets.eraser as Array).is_empty():
		_paint_presets.eraser=[_preset("Hard eraser",32,1,1,Color.WHITE),_preset("Soft eraser",70,.55,.08,Color.WHITE)]
	if (_paint_presets.fill as Array).is_empty():
		_paint_presets.fill=[_preset("Exact fill",1,1,1,Color("62d9bc"),.01),_preset("Soft range",1,1,1,Color("62d9bc"),.14)]


func _preset(label: String,size: float,opacity: float,hardness_value: float,preset_color: Color,threshold: float=.08) -> Dictionary:
	return {"id":ActorData.new_id(),"name":label,"size":size,"opacity":opacity,"hardness":hardness_value,"color":preset_color,"threshold":threshold,"mode":"freehand"}


func _paint_preset_controls(kind: String) -> void:
	preset_panel.visible=true
	var caption:=Label.new(); caption.text=kind.capitalize()+" presets"; caption.custom_minimum_size.x=95; caption.add_theme_color_override("font_color",Color("7fcfbe")); preset_context.add_child(caption)
	_button(preset_context,"Save",func(): _save_paint_preset(kind,false),"Update the selected preset, or create one")
	_button(preset_context,"Save +",func(): _save_paint_preset(kind,true),"Save these settings as a new preset")
	var scroll:=ScrollContainer.new(); scroll.custom_minimum_size=Vector2(220,34); scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; preset_context.add_child(scroll)
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",5); scroll.add_child(row)
	var preset_index:=0
	for value: Variant in _paint_presets.get(kind,[]):
		if not value is Dictionary: continue
		var preset: Dictionary=value
		var button:=PresetButton.new(); button.studio=self; button.kind=kind; button.preset_id=str(preset.get("id",""))
		button.text=str(preset_index) if preset_index<10 else ""
		button.icon=_paint_preset_icon(preset,kind); button.expand_icon=true; button.custom_minimum_size=Vector2(64,32)
		button.tooltip_text=str(preset.get("name","Preset"))+" · Drag to reorder · Right-click to delete"
		if preset_index<10: button.tooltip_text+=" · Key "+str(preset_index)
		preset_index+=1
		if str(_active_preset.get(kind,""))==str(preset.get("id","")):
			button.add_theme_stylebox_override("normal",_box(Color("245d54"),Color("79e5ce"),6,2))
		row.add_child(button); button.pressed.connect(func(): _apply_paint_preset(kind,preset))
		button.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
				var menu:=PopupMenu.new(); add_child(menu); menu.add_item("Delete preset")
				menu.id_pressed.connect(func(_id: int): _delete_paint_preset(kind,str(preset.get("id",""))); menu.queue_free())
				menu.popup_hide.connect(func(): if is_instance_valid(menu): menu.queue_free())
				menu.position=Vector2i(get_global_mouse_position()); menu.popup())


func _paint_preset_icon(preset: Dictionary,kind: String) -> Texture2D:
	var bitmap:=Image.create(64,40,false,Image.FORMAT_RGBA8); bitmap.fill(Color("15212d"))
	var preset_color: Color=preset.get("color",Color.WHITE)
	if kind=="fill":
		for y in range(5,35):
			for x in range(5,59): bitmap.set_pixel(x,y,preset_color)
	else:
		var radius:=clampf(float(preset.get("size",28))/7.0,3,15); var hard:=float(preset.get("hardness",1)); var opacity:=float(preset.get("opacity",1))
		for y in 40:
			for x in 64:
				var distance:=Vector2(x-32,y-20).length()/radius
				if distance<=1:
					var alpha:=opacity*clampf((1-distance)/maxf(.001,1-hard),0,1); var pixel:=preset_color; pixel.a=alpha; bitmap.set_pixel(x,y,pixel)
	return ImageTexture.create_from_image(bitmap)


func _apply_paint_preset(kind: String,preset: Dictionary) -> void:
	canvas.cancel_gesture()
	canvas.brush_size=float(preset.get("size",canvas.brush_size)); canvas.brush_opacity=float(preset.get("opacity",canvas.brush_opacity))
	canvas.hardness=float(preset.get("hardness",canvas.hardness)); canvas.fill_threshold=float(preset.get("threshold",canvas.fill_threshold))
	canvas.color=preset.get("color",canvas.color); color_picker.color=canvas.color
	if kind=="brush":
		canvas.stroke_correct=bool(preset.get("stroke_correct",canvas.stroke_correct))
		canvas.brush_type=str(preset.get("brush_type",canvas.brush_type)); canvas.soften_strength=clampf(float(preset.get("soften_strength",canvas.soften_strength)),0,1)
		canvas.correction_strength=clampf(float(preset.get("correction_strength",canvas.correction_strength)),0,1)
		canvas.correction_scale=clampf(float(preset.get("correction_scale",canvas.correction_scale)),.1,16)
		_persist_paint_presets()
	_active_preset[kind]=str(preset.get("id","")); _refresh_context(); canvas.queue_redraw()


func _save_paint_preset(kind: String,as_new: bool) -> void:
	var active:=str(_active_preset.get(kind,"")); var list: Array=_paint_presets.get(kind,[])
	if not as_new and not active.is_empty():
		for index in list.size():
			if str((list[index] as Dictionary).get("id",""))==active:
				var updated:=_current_paint_preset(str((list[index] as Dictionary).get("name","Preset"))); updated.id=active; list[index]=updated
				_paint_presets[kind]=list; _persist_paint_presets(); _refresh_context(); status.text="Preset updated"; return
	var created:=_current_paint_preset("%s %d" % [kind.capitalize(),list.size()+1])
	list.append(created); _paint_presets[kind]=list; _active_preset[kind]=created.id
	_persist_paint_presets(); _refresh_context(); status.text="Preset saved"


func _current_paint_preset(label: String) -> Dictionary:
	var result:=_preset(label,canvas.brush_size,canvas.brush_opacity,canvas.hardness,canvas.color,canvas.fill_threshold)
	if canvas.tool=="brush": result.stroke_correct=canvas.stroke_correct; result.correction_strength=canvas.correction_strength
	if canvas.tool=="brush": result.correction_scale=canvas.correction_scale
	if canvas.tool=="brush": result.brush_type=canvas.brush_type; result.soften_strength=canvas.soften_strength
	result.mode=canvas.brush_mode; return result


func _delete_paint_preset(kind: String,id: String) -> void:
	var list: Array=_paint_presets.get(kind,[]); list.assign(list.filter(func(item: Variant): return not item is Dictionary or str(item.get("id",""))!=id))
	_paint_presets[kind]=list
	if str(_active_preset.get(kind,""))==id: _active_preset[kind]=""
	_persist_paint_presets(); _refresh_context()


func _persist_paint_presets(path: String=PAINT_PRESETS_PATH) -> void:
	var library:=Resource.new(); library.set_meta("presets",_paint_presets)
	library.set_meta("stroke_correct",canvas.stroke_correct); library.set_meta("correction_strength",canvas.correction_strength)
	library.set_meta("correction_scale",canvas.correction_scale)
	library.set_meta("brush_type",canvas.brush_type); library.set_meta("soften_strength",canvas.soften_strength)
	ResourceSaver.save(library,path)


func _move_preset(kind: String,source_id: String,target_id: String) -> void:
	var list: Array=_paint_presets[kind]; var from:=-1; var to:=-1
	for index in list.size():
		if str(list[index].id)==source_id: from=index
		if str(list[index].id)==target_id: to=index
	if from<0 or to<0 or from==to: return
	var moved: Dictionary=list.pop_at(from); list.insert(to,moved)
	_persist_paint_presets(); _refresh_context()


func _paint_selection_toggle() -> void:
	var toggle:=CheckButton.new(); toggle.text="Selection only"; toggle.button_pressed=canvas.paint_selection_only
	toggle.tooltip_text="Only paint selected pixels; show a subtle selection overlay."
	toggle.add_theme_font_size_override("font_size",12); _context_host.add_child(toggle)
	toggle.toggled.connect(func(enabled: bool): canvas.paint_selection_only=enabled; canvas.queue_redraw())


func _select_pixel_region(invert: bool) -> void:
	_finish_pending()
	await _prepare_pixel_selection()
	if canvas.pixel_source==null or canvas.selected.is_empty(): return
	var bytes:=PackedByteArray(); bytes.resize(document.canvas_size.x*document.canvas_size.y*4)
	var source_bytes:=canvas.pixel_source.get_data()
	var previous:=canvas.selection.get_data() if canvas.selection!=null else PackedByteArray()
	var domain:=canvas.pixel_domain
	for y in range(domain.position.y,domain.end.y):
		for x in range(domain.position.x,domain.end.x):
			var offset: int=(y*document.canvas_size.x+x)*4
			var coverage: float=(1.0-(float(previous[offset+3])/255.0 if not previous.is_empty() else 0.0)) if invert else (canvas.selection_alpha if source_bytes[offset+3]>0 else 0.0)
			for channel in 3: bytes[offset+channel]=255
			bytes[offset+3]=roundi(coverage*255)
	var bitmap:=Image.create_from_data(document.canvas_size.x,document.canvas_size.y,false,Image.FORMAT_RGBA8,bytes)
	if not invert and canvas.selection_falloff>0: bitmap=preload("res://Workspaces/ImageWorkspace/pixel_selection_alpha.gd").feather(bitmap,canvas.selection_falloff)
	_action(func():
		document.pixel_selection=ImageTexture.create_from_image(bitmap); document.pixel_selection_owner=canvas.selected[-1]
		var owner:=document.layer_for_id(canvas.selected[-1])
		document.pixel_selection_reference=owner.copy_layer() if owner!=null else null
		document.pixel_selection_reference_world=document.world_transform(owner) if owner!=null else Transform2D.IDENTITY)
	canvas.sync_pixel_selection()


func _set_adjustment_selection_only(enabled: bool) -> void:
	_finish_pending()
	var layer:=_main_layer(); var owner:=document
	if layer==null: return
	var mask: Texture2D
	if enabled:
		canvas.sync_pixel_selection()
		if canvas.selection==null or not canvas.selection.get_used_rect().has_area():
			status.text="Select pixels first, then enable Affect selected pixels only"; _refresh_context(); return
		mask=await preload("res://Workspaces/ImageWorkspace/image_selection_fill.gd").capture_local_mask(self,layer)
		if mask==null: _refresh_context(); return
	if document!=owner or document.layer_for_id(layer.id)!=layer: return
	_action(func():
		layer.properties.values_selection_only=enabled
		if enabled:
			layer.properties.values_selection=mask; layer.properties.values_selection_local=true
			layer.properties.erase("values_selection_frame"); layer.properties.erase("values_selection_dimensions"))

func _next_toolbar_row() -> void:
	var rows:=context.get_node_or_null("ContextRows")
	if rows==null: return
	var line:=HBoxContainer.new(); line.size_flags_horizontal=Control.SIZE_EXPAND_FILL; rows.add_child(line)
	var scroll:=ScrollContainer.new(); scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED; scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO; line.add_child(scroll)
	var row:=HBoxContainer.new(); row.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_theme_constant_override("separation",4); scroll.add_child(row); _context_host=row

func _toolbar_group(caption: String,icon_name: String) -> HBoxContainer:
	var panel:=PanelContainer.new(); panel.tooltip_text=caption.capitalize(); panel.add_theme_stylebox_override("panel",_box(Color("131e2a"),Color("304555"),6,3)); _context_host.add_child(panel)
	var compact:=Theme.new()
	for kind in ["Button","OptionButton","ColorPickerButton"]:
		compact.set_font_size("font_size",kind,12)
		compact.set_stylebox("normal",kind,_box(Color("202c3a"),Color("344356"),5,4))
		compact.set_stylebox("hover",kind,_box(Color("2d4153"),Color("5c7b91"),5,4))
		compact.set_stylebox("pressed",kind,_box(Color("21584f"),Color("6ae2c3"),5,4))
	compact.set_stylebox("normal","LineEdit",_box(Color("131e2a"),Color("344356"),4,3))
	compact.set_font_size("font_size","LineEdit",12); panel.theme=compact
	if canvas.tool=="brush":
		compact.set_font_size("font_size","CheckButton",12)
		compact.set_font_size("font_size","Label",12)
	var row:=HBoxContainer.new(); row.add_theme_constant_override("separation",5); panel.add_child(row)
	var icon:=TextureRect.new(); icon.texture=_icon(icon_name); icon.tooltip_text=caption.capitalize(); icon.custom_minimum_size=Vector2(15,15); icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.size_flags_vertical=Control.SIZE_SHRINK_CENTER; icon.modulate=Color("76cdbb"); row.add_child(icon)
	var controls:=HBoxContainer.new(); controls.set_meta("compact_toolbar",true); controls.add_theme_constant_override("separation",4); row.add_child(controls)
	return controls


func _toolbar_toggle(parent: Node,icon_name: String,enabled: bool,tip: String,changed: Callable) -> void:
	var button:=_button(parent,"",func(): pass,tip,icon_name); button.toggle_mode=true; button.button_pressed=enabled
	button.toggled.connect(changed)


func _compact_number(caption: String,value: float,setter: Callable,minimum: float=-100000,maximum: float=100000,parent: Node=null) -> DragNumber:
	var field:=HBoxContainer.new(); field.add_theme_constant_override("separation",4); (parent if parent!=null else context).add_child(field)
	var label:=Label.new(); label.text=caption; label.add_theme_font_size_override("font_size",12); label.add_theme_color_override("font_color",Color("87acae")); field.add_child(label)
	var input:=DragNumber.new(); input.min_value=minimum; input.max_value=maximum; input.step=.1; input.value=value; input.custom_minimum_size.x=60; field.add_child(input)
	input.interaction_started.connect(_begin)
	input.preview_changed.connect(func(next: float): setter.call(next); _preview())
	input.drag_committed.connect(func(_next: float): _commit())
	input.drag_cancelled.connect(_cancel)
	input.value_changed.connect(func(next: float):
		if input.dragging: return
		_begin(); setter.call(next); _preview(); _commit())
	return input


func _sync_context_values() -> void:
	var layer:=_main_layer()
	if layer==null or _context_fields.is_empty(): return
	if _context_fields.get("x") is DragNumber: _context_fields.x.set_value_no_signal(layer.position.x)
	if _context_fields.get("y") is DragNumber: _context_fields.y.set_value_no_signal(layer.position.y)
	if _context_fields.get("width") is DragNumber: _context_fields.width.set_value_no_signal(layer.dimensions.x*(-1 if bool(layer.properties.get("flip_x",false)) else 1))
	if _context_fields.get("height") is DragNumber: _context_fields.height.set_value_no_signal(layer.dimensions.y*(-1 if bool(layer.properties.get("flip_y",false)) else 1))
	if _context_fields.get("rotation") is DragNumber: _context_fields.rotation.set_value_no_signal(rad_to_deg(layer.rotation))
	if _context_fields.get("opacity") is DragNumber: _context_fields.opacity.set_value_no_signal(layer.opacity)


func _selection_changed() -> void:
	_finish_pending(); _refresh_layers(); _refresh_inspector(); _refresh_context(); canvas.queue_redraw()
	canvas.sync_pixel_selection()
	if canvas.tool=="pixel_select": _prepare_pixel_selection()


func _refresh_layers() -> void:
	if document==null: return
	if _tree_selection_pending: _apply_tree_selection()
	_syncing=true; layer_tree.clear()
	var root:=layer_tree.create_item()
	_tree_children(root,"")
	_syncing=false


func _tree_children(parent: TreeItem,parent_id: String) -> void:
	var children:=document.children(parent_id)
	children.reverse()
	for layer in children:
		if not _layer_filter.is_empty() and not layer.label.to_lower().contains(_layer_filter.to_lower()) and layer.kind!="group": continue
		var item:=layer_tree.create_item(parent)
		item.set_text(0,layer.label); item.set_metadata(0,layer.id); item.set_editable(0,true)
		item.set_icon(0,_icon(layer.kind)); item.set_icon_max_width(0,15)
		item.add_button(0,_small_layer_icon("eye" if layer.visible else "hidden"),0,false,"Toggle visibility")
		item.add_button(0,_small_layer_icon("isolated" if layer.isolated else "isolate"),2,false,"Isolate layer · Multiple layers can be isolated")
		item.add_button(0,_small_layer_icon("lock" if layer.locked else "unlock"),1,false,"Toggle lock")
		if layer.mask!=null: item.set_tooltip_text(0,"Layer mask attached")
		if canvas.selected.has(layer.id): item.select(0)
		if not document.children(layer.id).is_empty(): _tree_children(item,layer.id)


func _tree_selected(item: TreeItem,_column: int,_selected: bool) -> void:
	if _syncing: return
	if _selected and item!=null: _tree_main_id=str(item.get_metadata(0))
	if not _tree_selection_pending:
		_tree_selection_pending=true; _apply_tree_selection.call_deferred()


func _apply_tree_selection() -> void:
	if not _tree_selection_pending: return
	_tree_selection_pending=false
	var chosen: Array[String]=[]
	var current: TreeItem=layer_tree.get_next_selected(null)
	while current!=null:
		chosen.append(str(current.get_metadata(0))); current=layer_tree.get_next_selected(current)
	var main_id:=_tree_main_id
	if chosen.has(main_id): chosen.erase(main_id); chosen.append(main_id)
	canvas.cancel_gesture(); canvas.selected.assign(chosen)
	if canvas.tool=="path": _set_tool("move")
	_refresh_inspector(); _refresh_context(); canvas.queue_redraw()
	canvas.sync_pixel_selection()
	if canvas.tool=="pixel_select": _prepare_pixel_selection()


func _layer_button(item: TreeItem,_column: int,id: int,_mouse: int) -> void:
	var layer:=document.layer_for_id(str(item.get_metadata(0)))
	if layer==null: return
	_action(func():
		if id==0: layer.visible=not layer.visible
		elif id==2: layer.isolated=not layer.isolated
		else: layer.locked=not layer.locked)


func _layer_context() -> void:
	var popup:=PopupMenu.new(); add_child(popup)
	var actions: Array=[
		["Duplicate   Ctrl+D",duplicate_layers],["Copy   Ctrl+C",copy_layers],["Paste   Ctrl+V",paste_layers],
		["Fill parent / canvas",fill_selected_to_parent],["Restore drawing / erasing",restore_layer_paint],
		["Merge into basic layer",merge_selected],
		["Parent to last selected   Ctrl+G",parent_selected],["Unparent",unparent_selected],
		["Copy style",copy_style],["Paste style",paste_style],["Delete",delete_selected]]
	for entry: Array in actions: popup.add_item(entry[0])
	popup.id_pressed.connect(func(index: int): actions[index][1].call())
	popup.popup_hide.connect(popup.queue_free); popup.position=Vector2i(get_global_mouse_position()); popup.popup()


func _main_layer() -> KiwiImageLayer:
	return document.layer_for_id(canvas.selected[-1]) if not canvas.selected.is_empty() else null


func _section(label: String) -> VBoxContainer:
	var toggle:=Button.new(); toggle.text=("▸  " if _collapsed.get(label,false) else "▾  ")+label.to_upper()
	toggle.alignment=HORIZONTAL_ALIGNMENT_LEFT; toggle.flat=true; toggle.add_theme_font_size_override("font_size",11)
	toggle.add_theme_color_override("font_color",Color("85a1b6")); inspector.add_child(toggle)
	var fields:=VBoxContainer.new(); fields.add_theme_constant_override("separation",4)
	fields.visible=not bool(_collapsed.get(label,false)); inspector.add_child(fields)
	toggle.pressed.connect(func(): fields.visible=not fields.visible; _collapsed[label]=not fields.visible; toggle.text=("▾  " if fields.visible else "▸  ")+label.to_upper())
	return fields


func _refresh_inspector() -> void:
	_effects_dock.visible=_effects_open; _inspector_scroll.visible=not _effects_open
	if _effects_open: _refresh_effects_dock(); return
	var old_scroll:=_inspector_scroll.scroll_vertical
	_clear(inspector); _text_input=null
	var layer:=_main_layer()
	if layer==null: return
	if layer.properties.get("texture_material") is KiwiTextureMaterial:
		if canvas.tool=="repair" and get_node_or_null("MaterialBrowser")==null:
			canvas.repair_tool.material=layer.properties.texture_material.copy_material()
			canvas.repair_tool.material.coverage=null; canvas.repair_tool.material.source=null
		_button(inspector,"Edit painted material",func():
			canvas.repair_tool.material=layer.properties.texture_material.copy_material(); canvas.repair_tool.main_mode="texture"; _set_tool("repair")
			load("res://Workspaces/ImageWorkspace/texture_material_browser.gd").open(self),"Change the material without repainting its coverage","noise")
		_button(inspector,"Bake material",rasterize_selected,"Convert this material layer into ordinary editable pixels","check")
	if layer.properties.get("texture_recipe") is KiwiImageTextureRecipe:
		_button(inspector,"Edit procedural texture",func():
			canvas.repair_tool.recipe=layer.properties.texture_recipe.copy_recipe()
			canvas.repair_tool.mode="procedural"; _set_tool("repair")
			canvas.repair_tool.generate(),"Reopen the saved texture recipe","noise")
	if layer.kind=="image":
		_image_source_property(layer)
	elif layer.kind=="text":
		var text_label:=Label.new(); text_label.text="TEXT"; text_label.add_theme_color_override("font_color",Color("70cdb8")); inspector.add_child(text_label)
		_text_input=TextEdit.new(); _text_input.text=str(layer.properties.text); _text_input.custom_minimum_size.y=110; _text_input.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY; inspector.add_child(_text_input)
		_text_input.focus_entered.connect(_begin)
		_text_input.text_changed.connect(func(): _begin(); layer.properties.text=_text_input.text; _preview())
		_text_input.focus_exited.connect(_commit)
		_text_settings_property(layer)
		var align:=OptionButton.new()
		for label in ["Left","Center","Right"]: align.add_item(label)
		align.select(int(layer.properties.alignment)); inspector.add_child(align)
		align.item_selected.connect(func(value: int): _action(func(): layer.properties.alignment=value))
	elif layer.kind=="shape":
		var shape:=OptionButton.new(); for label in ["Rounded rectangle","Ellipse","Triangle","Custom polygon"]: shape.add_item(label)
		shape.select(maxi(0,["rectangle","ellipse","triangle","custom"].find(str(layer.properties.shape)))); inspector.add_child(shape)
		shape.item_selected.connect(func(value: int):
			_action(func(): layer.properties.shape=["rectangle","ellipse","triangle","custom"][value])
			if value==3: _draw_custom_shape(layer))
		if layer.properties.shape=="custom": _button(inspector,"Draw custom shape…",func(): _draw_custom_shape(layer),"Click vertices; Enter closes the shape")
		_check(inspector,"Filled",bool(layer.properties.get("filled",true)),func(value: bool): layer.properties.filled=value)
		_number(inspector,"Corners",float(layer.properties.radius),func(value: float): layer.properties.radius=value,0,500)
		_color(inspector,"Fill",layer.properties.color,func(value: Color): layer.properties.color=value)
		_number(inspector,"Stroke",float(layer.properties.stroke),func(value: float): layer.properties.stroke=value,0,100)
		_color(inspector,"Stroke color",layer.properties.stroke_color,func(value: Color): layer.properties.stroke_color=value)
	elif layer.kind=="path":
		_color(inspector,"Fill",layer.properties.color,func(value: Color): layer.properties.color=value)
		_number(inspector,"Stroke",float(layer.properties.stroke),func(value: float): layer.properties.stroke=value,0,100)
		_color(inspector,"Stroke color",layer.properties.stroke_color,func(value: Color): layer.properties.stroke_color=value)
	elif layer.kind=="noise":
		_noise_layer_property(layer)
	elif layer.kind=="gradient":
		_color(inspector,"Start color",layer.properties.color,func(value: Color): layer.properties.color=value)
		_color(inspector,"End color",layer.properties.color_end,func(value: Color): layer.properties.color_end=value)
		_number(inspector,"Angle",float(layer.properties.gradient_angle),func(value: float): layer.properties.gradient_angle=value,-360,360)
		_check(inspector,"Radial",bool(layer.properties.gradient_radial),func(value: bool): layer.properties.gradient_radial=value)
		_menu(inspector,"Gradient presets",[
			["Mint / ocean",func(): _action(func(): layer.properties.color=Color("69dfbe"); layer.properties.color_end=Color("3261de"))],
			["Sunset",func(): _action(func(): layer.properties.color=Color("f9ab62"); layer.properties.color_end=Color("cc477c"))],
			["Night",func(): _action(func(): layer.properties.color=Color("192346"); layer.properties.color_end=Color("824ed0"))]])
	_inspector_scroll.set_deferred("scroll_vertical",old_scroll)


func _default_text_settings() -> ActorObjectData:
	var settings:=ActorObjectData.new(); settings.type_id=&"text_settings"
	settings.values={&"font":"Arial",&"font_size":72.0,&"bold":false,&"italic":false,&"color":Color.WHITE,
		&"letter_spacing":0,&"line_spacing":0,&"outline_size":0,&"outline_color":Color.BLACK,&"shadow":false,&"shadow_color":Color(0,0,0,.65),&"shadow_offset":Vector2(2,2)}
	return settings


func _save_polygon(points: PackedVector2Array) -> void:
	var layer:=document.layer_for_id(canvas.path_layer_id)
	if layer==null: return
	_action(func():
		var local:=PackedVector2Array()
		if not points.is_empty():
			var bounds:=Rect2(points[0],Vector2.ZERO)
			for point in points: bounds=bounds.expand(point)
			var parent:=document.layer_for_id(layer.parent_id)
			var inverse:=document.world_transform(parent).affine_inverse() if parent!=null else Transform2D.IDENTITY
			layer.dimensions=bounds.size.max(Vector2.ONE); layer.rotation=0
			layer.position=inverse*(bounds.position+layer.dimensions*.5)-layer.dimensions*.5
			layer.set_linear_basis(inverse)
			for point in points: local.append(point-bounds.position)
		# Keep even one/two-point drafts in the resource so leaving the editor never discards them.
		layer.properties.shape="custom"; layer.properties.points=local; layer.properties.path_size=layer.dimensions)


func _draw_custom_shape(layer: KiwiImageLayer) -> void:
	_set_tool("path"); canvas.path_layer_id=layer.id; canvas._points.clear(); canvas.grab_focus()
	canvas._polygon_index=-1
	var vertices: PackedVector2Array=layer.properties.get("points",PackedVector2Array())
	var source_size: Vector2=layer.properties.get("path_size",layer.dimensions)
	for point in vertices: canvas._points.append(document.world_transform(layer)*(point*layer.dimensions/source_size.max(Vector2.ONE)))
	status.text="Drag to place or move vertices · Right-click cancels / deletes · Enter applies · Esc cancels"


func _default_noise_image() -> ActorObjectData:
	var object:=ActorObjectData.new(); object.type_id=&"noise_image"
	object.values={&"noise_type":FastNoiseLite.TYPE_SIMPLEX_SMOOTH,&"fractal_type":FastNoiseLite.FRACTAL_FBM,
		&"seed":0,&"frequency":.015,&"octaves":5,&"lacunarity":2.0,&"gain":.5,&"contrast":1.0,
		&"low_color":Color.BLACK,&"high_color":Color.WHITE,&"seamless":true,&"invert":false,
		&"as_normal_map":false,&"resolution":2}
	return object


func _noise_layer_property(layer: KiwiImageLayer) -> void:
	var object:=layer.properties.get("noise_object") as ActorObjectData
	if object==null:
		object=_default_noise_image(); layer.properties.noise_object=object; layer.texture=ActorImageGenerator.texture_for_object(object)
	var panel:=PanelContainer.new(); panel.add_theme_stylebox_override("panel",_box(Color("121d28"),Color("385064"),7,5)); inspector.add_child(panel)
	var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",4); panel.add_child(column)
	var row:=HBoxContainer.new(); column.add_child(row)
	var title:=Label.new(); title.text="NOISE IMAGE"; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; title.add_theme_color_override("font_color",Color("8fa8bb")); row.add_child(title)
	var preview:=TextureRect.new(); preview.texture=layer.texture; preview.custom_minimum_size=Vector2(46,30); preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; row.add_child(preview)
	var menu:=MenuButton.new(); menu.text="Change…"; row.add_child(menu); menu.get_popup().add_item("New Noise Image",0); menu.get_popup().add_item("Load from project…",1)
	menu.get_popup().id_pressed.connect(func(id: int):
		if id==0: _action(func(): layer.properties.noise_object=_default_noise_image(); _refresh_noise_layer(layer))
		else: _load_noise_layer_object(layer))
	var noise_type:=OptionButton.new()
	for label in ["Simplex","Simplex Smooth","Cellular","Perlin","Value Cubic","Value"]: noise_type.add_item(label)
	noise_type.select(clampi(int(object.get_value(&"noise_type",1)),0,5)); column.add_child(noise_type)
	noise_type.item_selected.connect(func(value: int): _action(func(): _set_noise_object_value(layer,&"noise_type",value)))
	_number(column,"Seed",float(object.get_value(&"seed",0)),func(value: float): _set_noise_object_value(layer,&"seed",int(value)),-2147483648,2147483647,1)
	_slider(column,"Frequency",float(object.get_value(&"frequency",.015)),.0001,.25,func(value: float): _set_noise_object_value(layer,&"frequency",value))
	_number(column,"Octaves",float(object.get_value(&"octaves",5)),func(value: float): _set_noise_object_value(layer,&"octaves",int(value)),1,10,1)
	_slider(column,"Lacunarity",float(object.get_value(&"lacunarity",2)),.01,8,func(value: float): _set_noise_object_value(layer,&"lacunarity",value))
	_slider(column,"Gain",float(object.get_value(&"gain",.5)),0,2,func(value: float): _set_noise_object_value(layer,&"gain",value))
	_slider(column,"Contrast",float(object.get_value(&"contrast",1)),.01,4,func(value: float): _set_noise_object_value(layer,&"contrast",value))
	_color(column,"Low color",object.get_value(&"low_color",Color.BLACK),func(value: Color): _set_noise_object_value(layer,&"low_color",value))
	_color(column,"High color",object.get_value(&"high_color",Color.WHITE),func(value: Color): _set_noise_object_value(layer,&"high_color",value))
	_check(column,"Seamless",bool(object.get_value(&"seamless",true)),func(value: bool): _set_noise_object_value(layer,&"seamless",value))
	_check(column,"Invert",bool(object.get_value(&"invert",false)),func(value: bool): _set_noise_object_value(layer,&"invert",value))
	_check(column,"Show as normal map",bool(object.get_value(&"as_normal_map",false)),func(value: bool): _set_noise_object_value(layer,&"as_normal_map",value))


func _set_noise_object_value(layer: KiwiImageLayer,key: StringName,value: Variant) -> void:
	var object:=layer.properties.get("noise_object") as ActorObjectData
	if object==null: return
	object.set_value(key,value); _refresh_noise_layer(layer)


func _refresh_noise_layer(layer: KiwiImageLayer) -> void:
	var object:=layer.properties.get("noise_object") as ActorObjectData
	layer.texture=ActorImageGenerator.texture_for_object(object) if object!=null else null


func _load_noise_layer_object(layer: KiwiImageLayer) -> void:
	var property:=ActorProperty.new(); property.object_type=&"noise_image"; property.options={"extensions":["tres","res"],"accepted_object_types":["noise_image"],"file_picker":true}
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Choose Noise Image")
	if chosen==ActorProjectFilePicker.EMPTY_RESOURCE:
		_action(func(): layer.properties.noise_object=null; layer.texture=null; layer.properties.erase("noise_path")); return
	if chosen.is_empty(): return
	var loaded:=ResourceLoader.load(chosen,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	if loaded==null or loaded.type_id!=&"noise_image": status.text="Choose a Noise Image resource."; return
	_action(func(): layer.properties.noise_object=loaded.copy_object(); layer.properties.noise_path=chosen; _refresh_noise_layer(layer))


func _ensure_text_settings(layer: KiwiImageLayer) -> ActorObjectData:
	var settings:=layer.properties.get("text_settings") as ActorObjectData
	if settings==null:
		settings=_default_text_settings()
		settings.values.font=layer.properties.get("font","Arial"); settings.values.font_size=float(layer.properties.get("font_size",72))
		settings.values.bold=bool(layer.properties.get("bold",false)); settings.values.color=layer.properties.get("color",Color.WHITE)
		settings.values.outline_size=int(layer.properties.get("outline",0)); settings.values.outline_color=layer.properties.get("outline_color",Color.BLACK)
		layer.properties.text_settings=settings
	return settings


func _text_settings_property(layer: KiwiImageLayer) -> void:
	var settings:=layer.properties.get("text_settings") as ActorObjectData
	if not layer.properties.has("text_settings"): settings=_ensure_text_settings(layer)
	var panel:=PanelContainer.new(); panel.add_theme_stylebox_override("panel",_box(Color("121d28"),Color("385064"),7,5)); inspector.add_child(panel)
	var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",4); panel.add_child(column)
	var row:=HBoxContainer.new(); column.add_child(row)
	var title:=Label.new(); title.text="TEXT SETTINGS"; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; title.add_theme_color_override("font_color",Color("8fa8bb")); row.add_child(title)
	var source:=Label.new(); source.text=str(layer.properties.get("text_settings_path","Embedded" )).get_file() if settings!=null else "Empty"; source.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; source.custom_minimum_size.x=70; row.add_child(source)
	var menu:=MenuButton.new(); menu.text="⋮"; row.add_child(menu)
	var actions: Array=[["New",func(): _action(func(): layer.properties.text_settings=_default_text_settings(); layer.properties.erase("text_settings_path"))],
		["Load from project…",func(): _choose_text_settings(layer)],["Save As…",func(): _save_text_settings(layer)],
		["Clear",func(): _action(func(): layer.properties.text_settings=null; layer.properties.erase("text_settings_path"))]]
	for action: Array in actions: menu.get_popup().add_item(action[0])
	menu.get_popup().id_pressed.connect(func(index: int): actions[index][1].call())
	if settings==null: return
	_button(column,str(settings.get_value(&"font","Arial")),_font_menu,"Choose a system font")
	_number(column,"Font size",float(settings.get_value(&"font_size",72)),func(value: float): _set_text_setting(layer,&"font_size",value),1,1000,1)
	_check(column,"Bold",bool(settings.get_value(&"bold",false)),func(value: bool): _set_text_setting(layer,&"bold",value))
	_check(column,"Italic",bool(settings.get_value(&"italic",false)),func(value: bool): _set_text_setting(layer,&"italic",value))
	_number(column,"Letter spacing",float(settings.get_value(&"letter_spacing",0)),func(value: float): _set_text_setting(layer,&"letter_spacing",int(value)),-64,256,1)
	_number(column,"Line spacing",float(settings.get_value(&"line_spacing",0)),func(value: float): _set_text_setting(layer,&"line_spacing",int(value)),-64,256,1)
	_color(column,"Color",settings.get_value(&"color",Color.WHITE),func(value: Color): _set_text_setting(layer,&"color",value))
	_number(column,"Outline",float(settings.get_value(&"outline_size",0)),func(value: float): _set_text_setting(layer,&"outline_size",int(value)),0,64,1)
	_color(column,"Outline color",settings.get_value(&"outline_color",Color.BLACK),func(value: Color): _set_text_setting(layer,&"outline_color",value))
	_check(column,"Shadow",bool(settings.get_value(&"shadow",false)),func(value: bool): _set_text_setting(layer,&"shadow",value))
	if bool(settings.get_value(&"shadow",false)):
		_color(column,"Shadow color",settings.get_value(&"shadow_color",Color(0,0,0,.65)),func(value: Color): _set_text_setting(layer,&"shadow_color",value))
		var offset: Vector2=settings.get_value(&"shadow_offset",Vector2(2,2))
		_number(column,"Shadow X",offset.x,func(value: float): _set_text_setting_component(layer,&"shadow_offset",0,value))
		_number(column,"Shadow Y",offset.y,func(value: float): _set_text_setting_component(layer,&"shadow_offset",1,value))


func _set_text_setting(layer: KiwiImageLayer,key: StringName,value: Variant) -> void:
	_ensure_text_settings(layer).set_value(key,value)


func _set_text_setting_component(layer: KiwiImageLayer,key: StringName,component: int,value: float) -> void:
	var settings:=_ensure_text_settings(layer); var vector: Vector2=settings.get_value(key,Vector2.ZERO); vector[component]=value; settings.set_value(key,vector)


func _choose_text_settings(layer: KiwiImageLayer) -> void:
	var property:=ActorProperty.new(); property.object_type=&"text_settings"; property.options={"extensions":["tres","res"],"accepted_object_types":["text_settings"],"file_picker":true}
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Choose Text Settings")
	if chosen==ActorProjectFilePicker.EMPTY_RESOURCE:
		_action(func(): layer.properties.text_settings=null; layer.properties.erase("text_settings_path")); return
	if chosen.is_empty(): return
	var loaded:=ResourceLoader.load(chosen,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	if loaded==null or loaded.type_id!=&"text_settings": status.text="Choose a Text Settings resource."; return
	_action(func(): layer.properties.text_settings=loaded.copy_object(); layer.properties.text_settings_path=chosen)


func _save_text_settings(layer: KiwiImageLayer) -> void:
	var settings:=_ensure_text_settings(layer)
	var result:=await ActorProjectResourceSaveDialog.pick(self,"Save Text Settings",layer.label+" Text Settings","tres",false)
	if result.get("cancelled",true): return
	var destination:=str(result.get("path",""))
	if destination.is_empty(): return
	if ResourceSaver.save(settings.copy_object(),destination)==OK:
		_action(func(): layer.properties.text_settings_path=destination)
		if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()
		status.text="Saved Text Settings"


func _image_source_property(layer: KiwiImageLayer) -> void:
	var panel:=PanelContainer.new(); panel.clip_contents=true; panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL; panel.add_theme_stylebox_override("panel",_box(Color("121d28"),Color("385064"),7,5)); inspector.add_child(panel)
	var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",4); panel.add_child(column)
	var row:=HBoxContainer.new(); column.add_child(row)
	var title:=Label.new(); title.text="IMAGE"; title.clip_text=true; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL; title.add_theme_color_override("font_color",Color("8fa8bb")); row.add_child(title)
	var preview:=TextureRect.new(); preview.texture=layer.texture; preview.custom_minimum_size=Vector2(46,34); preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; row.add_child(preview)
	var menu:=MenuButton.new(); menu.text="Change…"; column.add_child(menu)
	var actions: Array=[["Load from project…",_replace_image],["Create Noise Image",func(): _create_noise_image(layer)],["Clear",func(): _action(func(): layer.texture=null; layer.properties.erase("noise_image"))]]
	for action: Array in actions: menu.get_popup().add_item(action[0])
	menu.get_popup().id_pressed.connect(func(index: int): actions[index][1].call())
	if layer.properties.get("noise_image") is Dictionary:
		var badge:=Label.new(); badge.text="PROCEDURAL NOISE"; badge.add_theme_color_override("font_color",Color("70cdb8")); column.add_child(badge)
		var config: Dictionary=layer.properties.noise_image
		var resolution:=OptionButton.new(); for size in ActorImageGenerator.RESOLUTIONS: resolution.add_item("%d × %d" % [size,size])
		resolution.select(int(config.get("resolution",2))); column.add_child(resolution)
		resolution.item_selected.connect(func(value: int): _action(func(): _set_noise_value(layer,"resolution",value)))
		var noise_type:=OptionButton.new(); for type_name in ["Simplex","Smooth Simplex","Cellular","Perlin","Value Cubic","Value"]: noise_type.add_item(type_name)
		noise_type.select(int(config.get("noise_type",FastNoiseLite.TYPE_SIMPLEX_SMOOTH))); column.add_child(noise_type)
		noise_type.item_selected.connect(func(value: int): _action(func(): _set_noise_value(layer,"noise_type",value)))
		_number(column,"Seed",float(config.get("seed",0)),func(value: float): _set_noise_value(layer,"seed",int(value)),0,100000)
		_slider(column,"Frequency",float(config.get("frequency",.015)),.0001,.2,func(value: float): _set_noise_value(layer,"frequency",value))
		_number(column,"Octaves",float(config.get("octaves",5)),func(value: float): _set_noise_value(layer,"octaves",int(value)),1,10)
		_number(column,"Lacunarity",float(config.get("lacunarity",2.0)),func(value: float): _set_noise_value(layer,"lacunarity",value),.01,8)
		_number(column,"Gain",float(config.get("gain",.5)),func(value: float): _set_noise_value(layer,"gain",value),0,2)
		_slider(column,"Contrast",float(config.get("contrast",1.0)),.01,4.0,func(value: float): _set_noise_value(layer,"contrast",value))
		_color(column,"Low color",config.get("low_color",Color.BLACK),func(value: Color): _set_noise_value(layer,"low_color",value))
		_color(column,"High color",config.get("high_color",Color.WHITE),func(value: Color): _set_noise_value(layer,"high_color",value))
		_check(column,"Seamless",bool(config.get("seamless",true)),func(value: bool): _set_noise_value(layer,"seamless",value))
		_check(column,"Invert",bool(config.get("invert",false)),func(value: bool): _set_noise_value(layer,"invert",value))
		_check(column,"Normal map",bool(config.get("as_normal_map",false)),func(value: bool): _set_noise_value(layer,"as_normal_map",value))


func _create_noise_image(layer: KiwiImageLayer) -> void:
	_action(func():
		layer.properties.noise_image={"noise_type":FastNoiseLite.TYPE_SIMPLEX_SMOOTH,"fractal_type":FastNoiseLite.FRACTAL_FBM,"seed":0,"frequency":.015,"octaves":5,"lacunarity":2.0,"gain":.5,"contrast":1.0,"low_color":Color.BLACK,"high_color":Color.WHITE,"seamless":true,"invert":false,"as_normal_map":false,"resolution":2}
		_update_image_noise(layer))


func _set_noise_value(layer: KiwiImageLayer,key: String,value: Variant) -> void:
	var config: Dictionary=layer.properties.get("noise_image",{}); config[key]=value; layer.properties.noise_image=config
	_update_image_noise(layer)


func _update_image_noise(layer: KiwiImageLayer) -> void:
	var config: Dictionary=layer.properties.get("noise_image",{})
	var object:=ActorObjectData.new(); object.type_id=&"noise_image"; object.values=config
	var bitmap:=ActorImageGenerator.generate_noise(object)
	if bitmap!=null and not bitmap.is_empty(): layer.texture=ImageTexture.create_from_image(bitmap); layer.paint_base=layer.texture


func _set_common(key: String,value: Variant) -> void:
	for id in canvas.selected:
		var layer:=document.layer_for_id(id)
		if layer==null or layer.locked: continue
		match key:
			"position_x": layer.position.x=float(value)
			"position_y": layer.position.y=float(value)
			"width":
				_sizing_preview=true
				var center:=layer.position+layer.dimensions*.5
				var amount:=float(value); var ratio:=absf(amount)/maxf(1,layer.dimensions.x)
				layer.properties.flip_x=amount<0
				document.resize_layer(layer,Vector2(maxf(1,absf(amount)),layer.dimensions.y*ratio if bool(layer.properties.get("keep_aspect",false)) else layer.dimensions.y))
				layer.position=center-layer.dimensions*.5
			"height":
				_sizing_preview=true
				var center:=layer.position+layer.dimensions*.5
				var amount:=float(value); var ratio:=absf(amount)/maxf(1,layer.dimensions.y)
				layer.properties.flip_y=amount<0
				document.resize_layer(layer,Vector2(layer.dimensions.x*ratio if bool(layer.properties.get("keep_aspect",false)) else layer.dimensions.x,maxf(1,absf(amount))))
				layer.position=center-layer.dimensions*.5
			"keep_aspect": layer.properties.keep_aspect=bool(value)
			"yaw_up_down","yaw_left_right": layer.properties[key]=value
			_: layer.set(key,value)


func _number(parent: Node,label: String,value: float,setter: Callable,minimum: float=-100000,maximum: float=100000,number_step: float=.1) -> void:
	var row:=HBoxContainer.new(); parent.add_child(row)
	var caption:=Label.new(); caption.text=label; caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(caption)
	var input:=DragNumber.new(); input.min_value=minimum; input.max_value=maximum; input.step=number_step; input.value=value; input.custom_minimum_size.x=114; row.add_child(input)
	input.interaction_started.connect(_begin)
	input.preview_changed.connect(func(next: float): setter.call(next); _preview())
	input.drag_committed.connect(func(_next: float): _commit())
	input.drag_cancelled.connect(_cancel)
	input.value_changed.connect(func(next: float):
		if input.dragging: return
		_begin(); setter.call(next); _preview(); _commit())


func _slider(parent: Node,label: String,value: float,minimum: float,maximum: float,setter: Callable) -> void:
	var row:=HBoxContainer.new(); parent.add_child(row)
	var caption:=Label.new(); caption.text=label; caption.custom_minimum_size.x=80; row.add_child(caption)
	var slider:=HSlider.new(); slider.min_value=minimum; slider.max_value=maximum; slider.step=.01; slider.value=value
	slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(slider)
	var amount:=Label.new(); amount.text="%.2f" % value; amount.custom_minimum_size.x=40; row.add_child(amount)
	slider.drag_started.connect(_begin)
	slider.value_changed.connect(func(next: float): _begin(); setter.call(next); amount.text="%.2f" % next; _preview())
	slider.drag_ended.connect(func(_changed: bool): _commit())
	slider.focus_exited.connect(_commit)


func _color(parent: Node,label: String,value: Color,setter: Callable) -> void:
	var row:=HBoxContainer.new(); parent.add_child(row)
	var caption:=Label.new(); caption.text=label; caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(caption)
	var input:=LiveColorPickerButton.new(); input.color=value; input.custom_minimum_size=Vector2(108,28); row.add_child(input)
	input.interaction_started.connect(_begin)
	input.preview_changed.connect(func(next: Color): _begin(); setter.call(next); _preview())
	input.drag_committed.connect(func(_from: Color,_to: Color): _commit())
	input.drag_cancelled.connect(func(_from: Color): _cancel())


func _check(parent: Node,label: String,value: bool,setter: Callable) -> void:
	var input:=CheckButton.new(); input.text=label; input.button_pressed=value; parent.add_child(input)
	input.toggled.connect(func(next: bool): _action(func(): setter.call(next)))


func _build_value_sliders(layer: KiwiImageLayer) -> void:
	var ranges:={"brightness":Vector2(-1,1),"contrast":Vector2(0,4),"saturation":Vector2(0,4),"exposure":Vector2(-6,6),"gamma":Vector2(.1,4),"hue":Vector2(-PI,PI),"temperature":Vector2(-1,1),"tint":Vector2(-1,1)}
	for name in ranges:
		var key: String=name
		var default: float=preload("res://Workspaces/ImageWorkspace/image_values.gd").BASICS[key]
		var column:=VBoxContainer.new(); column.custom_minimum_size.x=174; column.add_theme_constant_override("separation",0); context.add_child(column)
		var row:=HBoxContainer.new(); column.add_child(row)
		var icon:=TextureRect.new(); icon.texture=_icon(key); icon.custom_minimum_size=Vector2(15,15); icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; icon.size_flags_vertical=Control.SIZE_SHRINK_CENTER; icon.modulate=Color("7fe3cd"); row.add_child(icon)
		var label:=Label.new(); label.text=key.capitalize(); label.add_theme_font_size_override("font_size",12); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
		var value:=Label.new(); value.add_theme_font_size_override("font_size",12); row.add_child(value)
		var reset:=Button.new(); reset.text="↺"; reset.tooltip_text="Reset "+key; reset.flat=true; row.add_child(reset)
		var slider:=HSlider.new(); slider.min_value=ranges[key].x; slider.max_value=ranges[key].y; slider.step=.01
		slider.value=float(layer.properties.get("value_basics",{}).get(key,default)); column.add_child(slider)
		value.text="%.2f" % slider.value; reset.disabled=is_equal_approx(slider.value,default)
		slider.drag_started.connect(_begin)
		slider.value_changed.connect(func(next: float):
			_begin()
			if not layer.properties.has("value_basics"): layer.properties.value_basics={}
			layer.properties.value_basics[key]=next; value.text="%.2f" % next; reset.disabled=is_equal_approx(next,default); _preview())
		slider.drag_ended.connect(func(_changed: bool): _commit())
		slider.focus_exited.connect(_commit)
		reset.pressed.connect(func(): slider.value=default; _commit())


func _open_values(_ordered: bool) -> void:
	_open_stack_editor(true)


func _populate_values(list: VBoxContainer, layer: KiwiImageLayer, ordered: bool) -> void:
	_clear(list)
	if not ordered:
		var ranges:={"brightness":Vector2(-1,1),"contrast":Vector2(0,4),"saturation":Vector2(0,4),"exposure":Vector2(-6,6),"gamma":Vector2(.1,4),"hue":Vector2(-PI,PI),"temperature":Vector2(-1,1),"tint":Vector2(-1,1)}
		for name in ranges:
			var key: String=name
			var defaults: Dictionary=preload("res://Workspaces/ImageWorkspace/image_values.gd").BASICS
			_slider(list,key.capitalize(),float(layer.properties.get("value_basics",{}).get(key,defaults[key])),ranges[key].x,ranges[key].y,func(value: float):
				if not layer.properties.has("value_basics"): layer.properties.value_basics={}
				layer.properties.value_basics[key]=value)
		_button(list,"↺ Reset adjustments",func(): _action(func(): layer.properties.erase("value_basics")); _populate_values(list,layer,ordered))
		return
	var ops: Array=layer.properties.get("value_operations",[])
	for i in ops.size():
		var index:=i
		var op: Dictionary=ops[i]
		var card:=preload("res://Workspaces/ImageWorkspace/image_operation_row.gd").new(); card.index=i
		card.reorder=func(from: int,to: int):
			_action(func(): var item: Dictionary=ops.pop_at(from); ops.insert(to,item))
			_populate_values(list,layer,true)
		card.add_theme_stylebox_override("panel",_box(Color("1c2c3a"),Color("355064"),7,10)); list.add_child(card)
		var column:=VBoxContainer.new(); column.mouse_filter=Control.MOUSE_FILTER_PASS; card.add_child(column)
		var row:=HBoxContainer.new(); column.add_child(row)
		var label:=Label.new(); label.text="⠿  %d  %s" % [i+1,str(op.type).capitalize()]; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
		_check(row,"",bool(op.get("enabled",true)),func(value: bool): op.enabled=value)
		_button(row,"↺",func():
			_action(func():
				var enabled: bool=op.get("enabled",true)
				ops[index]=preload("res://Workspaces/ImageWorkspace/image_values.gd").new_operation(str(op.type)); ops[index].enabled=enabled)
			_populate_values(list,layer,true),"Reset operation parameters")
		_button(row,"×",func(): _action(func(): ops.remove_at(index)); _populate_values(list,layer,true),"Remove operation")
		if not op.has("a"):
			if op.type!="invert": _number(column,"Amount",float(op.get("amount",1)),func(value: float): op.amount=value,-16,64,.01)
			_button(column,"Edit operands",func():
				_action(func():
					var replacement: Dictionary=preload("res://Workspaces/ImageWorkspace/image_values.gd").new_operation(str(op.type))
					replacement.b.value=1.0/maxf(1,float(op.get("amount",1))) if op.type=="snap" else float(op.get("amount",1))
					replacement.preserve_hue=false; replacement.enabled=op.get("enabled",true); ops[index]=replacement)
				_populate_values(list,layer,true))
			continue
		var rebuild:=func(): _populate_values(list,layer,true)
		_operand_controls(column,"A",op,"a",rebuild)
		if op.type not in ["absolute","invert"]:
			_operand_controls(column,"B",op,"b",rebuild)
			_button(column,"⇄ Swap A / B",func(): _action(func(): var operand: Dictionary=op.a; op.a=op.b; op.b=operand); rebuild.call())
		if op.type in ["clamp","lerp","smoothstep"]: _operand_controls(column,"Weight" if op.type=="lerp" else "Upper",op,"c",rebuild)
		if op.type=="snap": _check(column,"Preserve hue",bool(op.get("preserve_hue",true)),func(value: bool): op.preserve_hue=value)
		_check(column,"Affect alpha",bool(op.get("affect_alpha",false)),func(value: bool): op.affect_alpha=value)


func _operand_controls(host: Control, caption: String, op: Dictionary, key: String, rebuild: Callable) -> void:
	var operand: Dictionary=op[key]
	var row:=HBoxContainer.new(); host.add_child(row)
	var label:=Label.new(); label.text=caption; label.custom_minimum_size.x=48; row.add_child(label)
	var type:=OptionButton.new(); type.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(type)
	for title in ["Pixel value","Float","Vector4 · RGBA"]: type.add_item(title)
	type.select(["pixel","float","vector"].find(str(operand.get("kind","pixel"))))
	type.item_selected.connect(func(index: int):
		_action(func(): op[key]={"kind":["pixel","float","vector"][index],"value":float(operand.get("value",1)),"channels":[1.0,1.0,1.0,1.0]})
		rebuild.call())
	if operand.kind=="float":
		_number(host,"Value",float(operand.get("value",0)),func(value: float): operand.value=value,-10000,10000,.01)
	elif operand.kind=="vector":
		var channels: Array=operand.get("channels",[1.0,1.0,1.0,1.0]); operand.channels=channels
		for i in 4:
			var channel:=i
			var channel_row:=HBoxContainer.new(); host.add_child(channel_row)
			var source:=OptionButton.new(); channel_row.add_child(source)
			for title in ["Constant","Pixel R","Pixel G","Pixel B","Pixel A"]: source.add_item(title)
			source.select("rgba".find(str(channels[i]))+1 if channels[i] is String else 0)
			source.item_selected.connect(func(index: int):
				_action(func(): channels[channel]=1.0 if index==0 else "rgba"[index-1])
				rebuild.call())
			if not channels[i] is String:
				_number(channel_row,"RGBA"[i],float(channels[i]),func(value: float): channels[channel]=value,-10000,10000,.01)


func _build_effects(layer: KiwiImageLayer) -> void:
	var effects:=_section("Effects")
	_effect_selection_control(effects,layer)
	var choices: Array=[]
	for kind in AVAILABLE_EFFECTS:
		var effect_kind: String=kind
		choices.append([effect_kind.capitalize(),func(): add_effect(effect_kind)])
	choices.append(["Canvas shader…",_choose_shader_effect])
	_menu(effects,"+ Add effect",choices)
	var style_choices: Array=[
		["Soft shadow",func(): add_effect("shadow")],["Sticker outline",func(): add_effect("outline")],
		["Monochrome",func(): add_effect("grayscale")],["Copy style",copy_style],["Paste style",paste_style],
		["Save current style…",_save_style]]
	for preset_name: String in _presets:
		var name:=preset_name
		style_choices.append([name,func(): _style_clipboard=_presets[name].duplicate(true); paste_style()])
	_menu(effects,"Style presets",style_choices)
	for index in layer.effects.size():
		var effect: Dictionary=layer.effects[index]
		var panel:=PanelContainer.new(); panel.add_theme_stylebox_override("panel",_box(Color("111c28"),Color("304252"),6,7)); effects.add_child(panel)
		var fields:=VBoxContainer.new(); panel.add_child(fields)
		var header:=HBoxContainer.new(); fields.add_child(header)
		var enabled:=CheckButton.new(); enabled.text=str(effect.type).capitalize(); enabled.button_pressed=bool(effect.get("enabled",true)); enabled.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(enabled)
		enabled.toggled.connect(func(value: bool): _action(func(): effect.enabled=value))
		var effect_index:=index
		_button(header,"↑",func(): _move_effect(effect_index,-1),"Move effect earlier")
		_button(header,"↓",func(): _move_effect(effect_index,1),"Move effect later")
		_button(header,"Apply",func(): _apply_effect(layer,effect_index),"Bake effects through this point into layer pixels")
		_button(header,"×",func(): _action(func(): layer.effects.remove_at(effect_index)),"Remove effect")
		var ranges:={"brightness":Vector2(-1,1),"contrast":Vector2(0,3),"saturation":Vector2(0,3),"blur":Vector2(0,24),"sharpen":Vector2(0,2),"outline":Vector2(0,24),"shadow":Vector2(0,24),"glow":Vector2(0,32),"wave":Vector2(0,40),"twirl":Vector2(-12,12),"chromatic":Vector2(0,32),"grain":Vector2(0,1),"pixelate":Vector2(1,128),"halftone":Vector2(2,64),"posterize":Vector2(2,32),"vignette":Vector2(0,2),"color_replace":Vector2(.001,1)}
		if ranges.has(effect.type):
			var limits: Vector2=ranges[effect.type]
			_slider(fields,"Amount",float(effect.get("amount",1)),limits.x,limits.y,func(value: float): effect.amount=value)
		if effect.type in ["outline","shadow","glow","gradient_map","color_replace"]:
			_color(fields,"Color",effect.get("color",Color.BLACK),func(value: Color): effect.color=value)
		if effect.type in ["gradient_map","color_replace"]:
			_color(fields,"End / replacement",effect.get("color2",Color.WHITE),func(value: Color): effect.color2=value)
		if effect.type=="shadow":
			_number(fields,"Offset X",effect.offset.x,func(value: float): effect.offset.x=value,-48,48)
			_number(fields,"Offset Y",effect.offset.y,func(value: float): effect.offset.y=value,-48,48)
		if effect.type=="shader" and effect.get("shader") is Shader: _shader_fields(fields,effect)
		if effect.type=="mirror": _mirror_fields(fields,effect)
		if effect.type=="curves":
			_curve_effect_fields(fields,effect)


func add_effect(kind: String) -> void:
	if canvas.selected.is_empty(): return
	_action(func():
		for id in canvas.selected:
			var layer:=document.layer_for_id(id)
			if layer==null or layer.locked: continue
			layer.effects.append(_new_effect(kind)))

func _new_effect(kind: String) -> Dictionary:
	var effect:={"id":ActorData.new_id(),"type":kind,"enabled":true,
		"amount":0.0 if kind=="brightness" else (8.0 if kind in ["blur","outline","shadow","glow","wave","chromatic","halftone"] else (6.0 if kind in ["pixelate","posterize"] else 1.0)),
		"color":Color.WHITE if kind in ["outline","glow"] else Color(0,0,0,.65),"offset":Vector2(8,8),
		"color2":Color.WHITE,"mirror_side":0,"mirror_position":0.5,
		"curve":ActorValueCurve.preset("Linear") if kind=="curves" else null}
	var amounts:={"emboss":1.0,"edge_detect":1.0,"motion_blur":12.0,"radial_blur":8.0,"kaleidoscope":6.0,"ripple":8.0,"scanlines":.35}
	if amounts.has(kind): effect.amount=amounts[kind]
	effect.angle=0.0; effect.spacing=6.0 if kind=="scanlines" else 12.0
	return effect


func _move_effect(index: int,direction: int) -> void:
	var layer:=_main_layer()
	var target:=clampi(index+direction,0,layer.effects.size()-1)
	_action(func(): var effect: Dictionary=layer.effects[index]; layer.effects.remove_at(index); layer.effects.insert(target,effect))


func _mirror_fields(fields: Node,effect: Dictionary) -> void:
	var side:=OptionButton.new()
	for label in ["Mirror from left","Mirror from right","Mirror from top","Mirror from bottom"]: side.add_item(label)
	side.select(int(effect.get("mirror_side",0))); fields.add_child(side)
	side.item_selected.connect(func(value: int): _action(func(): effect.mirror_side=value))
	_slider(fields,"Mirror line",float(effect.get("mirror_position",0.5)),0.0,1.0,func(value: float): effect.mirror_position=value)


func _effect_selection_control(parent: Node,layer: KiwiImageLayer) -> void:
	var toggle:=CheckBox.new(); toggle.text="Affect selected pixels only"
	toggle.button_pressed=bool(layer.properties.get("effects_selection_only",false))
	toggle.tooltip_text="Limit this layer's effects to the current pixel selection. Toggle again to capture a new selection."
	parent.add_child(toggle)
	toggle.toggled.connect(func(enabled: bool):
		var mask: Texture2D
		if enabled and canvas.selection!=null:
			var size:=Vector2i(layer.dimensions.ceil()).max(Vector2i.ONE)
			var bitmap:=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8); bitmap.fill(Color.TRANSPARENT)
			var world:=document.world_transform(layer)
			var mapping:=canvas.selection_inverse*world
			var translated:=not canvas.selection_inverse_warp.is_valid() and mapping.x.is_equal_approx(Vector2.RIGHT) and mapping.y.is_equal_approx(Vector2.DOWN) and mapping.origin.is_equal_approx(mapping.origin.round()) and is_zero_approx(float(layer.properties.get("yaw_up_down",0))) and is_zero_approx(float(layer.properties.get("yaw_left_right",0)))
			if translated:
				var origin:=Vector2i(mapping.origin.round())
				var region:=Rect2i(origin,size).intersection(Rect2i(Vector2i.ZERO,canvas.selection.get_size()))
				if region.has_area(): bitmap.blit_rect(canvas.selection,region,region.position-origin)
			else:
				for y in size.y:
					for x in size.x:
						var point:=world*layer.project_point(Vector2(x,y)+Vector2.ONE*.5)
						var sample: Vector2=canvas.selection_inverse_warp.call(point) if canvas.selection_inverse_warp.is_valid() else canvas.selection_inverse*point
						var pixel:=Vector2i(sample.floor())
						if pixel.x>=0 and pixel.y>=0 and pixel.x<canvas.selection.get_width() and pixel.y<canvas.selection.get_height(): bitmap.set_pixel(x,y,canvas.selection.get_pixelv(pixel))
			mask=ImageTexture.create_from_image(bitmap)
		_action(func():
			layer.properties.effects_selection_only=enabled
			if enabled: layer.properties.effects_selection=mask))


func _apply_effect(layer: KiwiImageLayer,index: int) -> void:
	if layer==null or not document.can_edit(layer) or index<0 or index>=layer.effects.size(): return
	if layer.kind=="group":
		status.text="Merge the group before applying its effects."; return
	var original:=document
	var version:=_edit_version
	var temporary:=Document.new()
	temporary.canvas_size=Vector2i(layer.dimensions.ceil()).max(Vector2i.ONE)
	var source:=layer.copy_layer()
	source.parent_id=""; source.position=Vector2.ZERO; source.rotation=0.0
	source.set_linear_basis(Transform2D.IDENTITY)
	source.visible=true; source.isolated=false; source.opacity=1.0; source.blend=0; source.clip_to_below=false
	source.properties.erase("yaw_up_down"); source.properties.erase("yaw_left_right")
	for key in source.properties.keys():
		if str(key).begins_with("value_") or str(key).begins_with("values_"): source.properties.erase(key)
	source.effects.assign(source.effects.slice(0,index+1))
	temporary.layers.append(source)
	var baker:=Renderer.new(); add_child(baker); baker.sync(temporary)
	var pixels: Image=await baker.flattened()
	baker.queue_free()
	if original!=document or document.layer_for_id(layer.id)!=layer or version!=_edit_version or pixels==null: return
	# Baking the prefix preserves the order of the remaining effects. Transform,
	# opacity and final color adjustments stay editable on the original layer.
	pixels.convert(Image.FORMAT_RGBA8)
	var texture:=ImageTexture.create_from_image(pixels)
	_action(func():
		layer.kind="basic"; layer.texture=texture; layer.paint_base=texture; layer.mask=null
		layer.effects.assign(layer.effects.slice(index+1))
		layer.properties.erase("linked_style"))
	status.text="Applied effects to layer pixels · Ctrl+Z to undo"


func _choose_shader_effect() -> void:
	var property:=ActorProperty.new(); property.options={"extensions":["gdshader"],"file_picker":true}
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Choose a canvas shader")
	if chosen.is_empty() or chosen==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var shader:=ResourceLoader.load(chosen,"",ResourceLoader.CACHE_MODE_IGNORE) as Shader
	if shader==null or RegEx.create_from_string("shader_type\\s+canvas_item\\s*;").search(shader.code)==null:
		status.text="Choose a shader with shader_type canvas_item."; return
	var layer:=_main_layer()
	if layer==null: return
	_action(func(): layer.effects.append({"id":ActorData.new_id(),"type":"shader","enabled":true,"shader":shader,"uniforms":{}}))


func _shader_fields(parent: Node,effect: Dictionary) -> void:
	var shader: Shader=effect.shader
	for uniform: Dictionary in shader.get_shader_uniform_list():
		var key:=StringName(uniform.name)
		var default_value: Variant=RenderingServer.shader_get_parameter_default(shader.get_rid(),key)
		var value: Variant=effect.uniforms.get(key,default_value)
		match int(uniform.type):
			TYPE_FLOAT,TYPE_INT:
				_number(parent,str(key),float(value) if value!=null else 0,func(next: float): effect.uniforms[key]=int(next) if int(uniform.type)==TYPE_INT else next)
			TYPE_BOOL:
				_check(parent,str(key),bool(value),func(next: bool): effect.uniforms[key]=next)
			TYPE_COLOR:
				_color(parent,str(key),value if value is Color else Color.WHITE,func(next: Color): effect.uniforms[key]=next)
			TYPE_VECTOR2,TYPE_VECTOR3,TYPE_VECTOR4:
				var count:=2 if int(uniform.type)==TYPE_VECTOR2 else (3 if int(uniform.type)==TYPE_VECTOR3 else 4)
				for component in count:
					var c:=component
					_number(parent,str(key)+" "+["X","Y","Z","W"][c],float(value[c]) if value!=null else 0,
						func(next: float):
							var vector: Variant=effect.uniforms.get(key,default_value)
							vector[c]=next; effect.uniforms[key]=vector)
			TYPE_OBJECT:
				_button(parent,str(key)+" · Load image…",func():
					var property:=ActorProperty.new(); property.options={"extensions":IMAGE_EXTENSIONS,"file_picker":true}
					var chosen:=await ActorProjectFilePicker.pick(self,property,"Choose shader texture")
					if chosen==ActorProjectFilePicker.EMPTY_RESOURCE: _action(func(): effect.uniforms[key]=null); return
					if chosen.is_empty(): return
					var bitmap:=Image.load_from_file(chosen)
					if bitmap!=null: _action(func(): effect.uniforms[key]=ImageTexture.create_from_image(bitmap)))


func _font_menu() -> void:
	var layer:=_main_layer()
	if layer==null: return
	var popup:=PopupPanel.new(); popup.add_theme_stylebox_override("panel",_box(Color("14202c"),Color("4a706d"),10,12)); add_child(popup)
	var column:=VBoxContainer.new(); column.custom_minimum_size=Vector2(350,400); popup.add_child(column)
	var search:=LineEdit.new(); search.placeholder_text="Search installed fonts…"; column.add_child(search)
	var actual:=CheckButton.new(); actual.text="Preview with layer text"; column.add_child(actual)
	var scroll:=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(scroll)
	var list:=VBoxContainer.new(); list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	var fonts:=OS.get_system_fonts(); fonts.sort()
	var populate:=func(query: String):
		_clear(list)
		var count:=0
		for family in fonts:
			if not query.is_empty() and not family.to_lower().contains(query.to_lower()): continue
			var selected_font: String=family
			var button:=_button(list,str(layer.properties.get("text","Text")) if actual.button_pressed else family,func(): _action(func(): _set_text_setting(layer,&"font",selected_font)); popup.hide())
			button.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; button.tooltip_text=family
			var font:=SystemFont.new(); font.font_names=PackedStringArray([family]); button.add_theme_font_override("font",font)
			count+=1
			if count>=60: break
	search.text_changed.connect(populate); populate.call("")
	actual.toggled.connect(func(_enabled: bool): populate.call(search.text))
	popup.popup_hide.connect(popup.queue_free); popup.popup_centered(Vector2i(390,460)); search.grab_focus()


func _edit_canvas_text() -> void:
	var layer:=_main_layer()
	if layer==null or layer.kind!="text": return
	_begin()
	_inline_text_layer_id=layer.id
	var editor:=preload("res://Workspaces/ImageWorkspace/image_inline_text_edit.gd").new()
	editor.layer=layer; editor.canvas=canvas
	editor.text=str(layer.properties.get("text",""))
	canvas.add_child(editor)
	editor.grab_focus(); editor.set_caret_line(editor.get_line_count()-1); editor.set_caret_column(editor.get_line(editor.get_line_count()-1).length())
	editor._place_caret(editor.hit_text(editor.get_transform().affine_inverse()*canvas._mouse))
	editor.navigation_requested.connect(func(event: InputEventMouseButton):
		var forwarded: InputEventMouseButton=event.duplicate()
		forwarded.position=editor.get_transform()*event.position
		canvas._input_canvas(forwarded); editor.sync_layout())
	editor.text_changed.connect(func(): layer.properties.text=editor.text; _preview())
	var finish:=func(cancel: bool):
		if editor.is_queued_for_deletion(): return
		_inline_text_layer_id=""
		editor.queue_free()
		if cancel: _cancel()
		else: _commit()
	editor.focus_exited.connect(func(): finish.call(false))
	editor.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed:
			if event.keycode==KEY_ESCAPE: editor.accept_event(); finish.call(true)
			elif event.keycode==KEY_ENTER and event.ctrl_pressed: editor.accept_event(); finish.call(false))


func delete_selected() -> void:
	var ids:=canvas.selected.duplicate()
	_action(func():
		document.layers.assign(document.layers.filter(func(layer: KiwiImageLayer):
			if ids.has(layer.id): return false
			for id in ids:
				if document.is_descendant(layer.id,id): return false
			return true))
		canvas.selected.clear())


func copy_layers() -> void:
	_clipboard.clear()
	for layer in document.layers:
		var include:=canvas.selected.has(layer.id)
		for id in canvas.selected:
			if document.is_descendant(layer.id,id): include=true
		if include: _clipboard.append(layer.copy_layer())
	status.text="Copied %d layer(s)" % _clipboard.size()


func paste_layers() -> void:
	if _clipboard.is_empty(): return
	_action(func():
		var ids: Dictionary={}
		for layer in _clipboard: ids[layer.id]=ActorData.new_id()
		canvas.selected.clear()
		for original in _clipboard:
			var layer:=original.copy_layer(); layer.id=ids[original.id]
			layer.parent_id=str(ids.get(original.parent_id,""))
			if layer.parent_id.is_empty(): layer.position+=Vector2(20,20); canvas.selected.append(layer.id)
			document.layers.append(layer))
	_selection_changed()


func duplicate_layers() -> void:
	copy_layers(); paste_layers()


func _selected_ids_with_relatives(ids: Array[String]) -> Dictionary:
	var keep:={}
	for layer in document.layers:
		if ids.has(layer.id): keep[layer.id]=true
		for id in ids:
			if document.is_descendant(layer.id,id): keep[layer.id]=true
	for id in keep.keys():
		var layer:=document.layer_for_id(str(id))
		while layer!=null and not layer.parent_id.is_empty():
			keep[layer.parent_id]=true; layer=document.layer_for_id(layer.parent_id)
	return keep


func _render_layers(ids: Array[String]) -> Image:
	var temporary:=document.snapshot()
	var keep:=_selected_ids_with_relatives(ids)
	temporary.layers.assign(temporary.layers.filter(func(layer: KiwiImageLayer): return keep.has(layer.id)))
	renderer.sync(temporary)
	var bitmap:=await renderer.flattened()
	renderer._topology="_restore_"; renderer.sync(document)
	return bitmap


func _basic_from_image(bitmap: Image,label: String) -> KiwiImageLayer:
	var used:=bitmap.get_used_rect()
	if used.size.x<1 or used.size.y<1: used=Rect2i(Vector2i.ZERO,Vector2i.ONE)
	var cropped:=bitmap.get_region(used)
	var layer:=Layer.create("basic",document.canvas_size)
	layer.label=label; layer.position=Vector2(used.position); layer.dimensions=Vector2(used.size)
	layer.texture=ImageTexture.create_from_image(cropped)
	layer.paint_base=layer.texture
	return layer


func _remove_roots(ids: Array[String]) -> void:
	document.layers.assign(document.layers.filter(func(layer: KiwiImageLayer):
		if ids.has(layer.id): return false
		for id in ids:
			if document.is_descendant(layer.id,id): return false
		return true))


func merge_selected() -> void:
	var roots:=document.selected_roots(canvas.selected)
	if roots.is_empty(): return
	var ids: Array[String]=[]
	for layer in roots: ids.append(layer.id)
	status.text="Merging layers…"
	var bitmap:=await _render_layers(ids)
	if bitmap==null or bitmap.is_empty(): status.text="Could not merge those layers."; return
	var merged:=_basic_from_image(bitmap,"Merged layer")
	_action(func(): _remove_roots(ids); document.layers.append(merged); canvas.selected.assign([merged.id]))
	status.text="Merged %d layer(s) into an editable basic layer" % ids.size()


func rasterize_selected() -> void:
	if _rasterizing: return
	var roots:=document.selected_roots(canvas.selected)
	var targets: Array[KiwiImageLayer]=[]
	for layer in roots:
		if layer.kind not in ["image","paint","basic"] or layer.properties.get("texture_material") is KiwiTextureMaterial: targets.append(layer)
	if targets.is_empty(): return
	_rasterizing=true; status.text="Preparing layer for pixel editing…"
	var replacements:={}
	for layer in targets:
		var bitmap:=await _render_layers([layer.id])
		if bitmap!=null and not bitmap.is_empty(): replacements[layer.id]=_basic_from_image(bitmap,layer.label)
	if not replacements.is_empty():
		var ids: Array[String]=[]; ids.assign(replacements.keys())
		_action(func():
			for id in ids:
				var original:=document.layer_for_id(id); var index:=document.layers.find(original)
				_remove_roots([id]); document.layers.insert(clampi(index,0,document.layers.size()),replacements[id])
			canvas.selected.clear(); for id in ids: canvas.selected.append(replacements[id].id))
	_rasterizing=false; status.text="Layer is ready for painting and erasing"


func _apply_crop(bounds: Rect2,polygon: PackedVector2Array=PackedVector2Array()) -> void:
	var clipped:=bounds.intersection(Rect2(Vector2.ZERO,Vector2(document.canvas_size)))
	if clipped.size.x<1 or clipped.size.y<1: return
	var region_start:=Vector2i(clipped.position.floor()).clamp(Vector2i.ZERO,document.canvas_size)
	var region_end:=Vector2i(clipped.end.ceil()).clamp(Vector2i.ZERO,document.canvas_size)
	var region:=Rect2i(region_start,region_end-region_start)
	if _crop_canvas:
		_action(func():
			document.canvas_size=region.size
			for layer in document.children(): layer.position-=Vector2(region.position))
		canvas.clear_selection(); canvas.fit(); status.text="Cropped the image canvas"; return
	var roots:=document.selected_roots(canvas.selected)
	if roots.is_empty(): status.text="Select one or more layers to crop."; return
	var ids: Array[String]=[]
	for layer in roots: ids.append(layer.id)
	status.text="Cropping selected layers…"
	var combined:=await _render_layers(ids)
	if combined==null or combined.is_empty(): return
	var extracted:=combined.get_region(region)
	var spans:=_crop_spans(region,polygon)
	if not polygon.is_empty():
		var masked:=Image.create(region.size.x,region.size.y,false,Image.FORMAT_RGBA8)
		masked.fill(Color(0,0,0,0))
		for span in spans:
			var local:=Rect2i(span.position-region.position,span.size)
			masked.blit_rect(extracted,local,local.position)
		extracted=masked
	var new_layer:=Layer.create("basic",document.canvas_size)
	new_layer.label="Cropped selection"; new_layer.position=Vector2(region.position); new_layer.dimensions=Vector2(region.size)
	new_layer.texture=ImageTexture.create_from_image(extracted)
	new_layer.paint_base=new_layer.texture
	var replacements:={}
	if _crop_action!=1:
		for layer in roots:
			var bitmap:=await _render_layers([layer.id])
			if bitmap!=null and not bitmap.is_empty():
				for span in spans: bitmap.fill_rect(span,Color(0,0,0,0))
				replacements[layer.id]=_basic_from_image(bitmap,layer.label)
	_action(func():
		if _crop_action!=1:
			for id in ids:
				var original:=document.layer_for_id(id); var index:=document.layers.find(original)
				_remove_roots([id])
				if replacements.has(id): document.layers.insert(clampi(index,0,document.layers.size()),replacements[id])
		if _crop_action!=2:
			document.layers.append(new_layer); canvas.selected.assign([new_layer.id])
		else:
			canvas.selected.clear(); for id in replacements: canvas.selected.append(replacements[id].id))
	_set_tool("move"); status.text="Crop complete"


func _crop_spans(region: Rect2i,polygon: PackedVector2Array) -> Array[Rect2i]:
	var spans: Array[Rect2i]=[]
	if polygon.is_empty(): spans.append(region); return spans
	for y in range(region.position.y,region.end.y):
		var crossings: Array[float]=[]; var scan:=float(y)+.5
		for index in polygon.size():
			var a:=polygon[index]; var b:=polygon[(index+1)%polygon.size()]
			if (a.y<=scan and b.y>scan) or (b.y<=scan and a.y>scan):
				crossings.append(a.x+(scan-a.y)*(b.x-a.x)/(b.y-a.y))
		crossings.sort()
		for index in range(0,crossings.size()-1,2):
			var left:=clampi(ceili(crossings[index]-.5),region.position.x,region.end.x)
			var right:=clampi(ceili(crossings[index+1]-.5),region.position.x,region.end.x)
			if right>left: spans.append(Rect2i(left,y,right-left,1))
	return spans


func _duplicate_for_drag() -> void:
	duplicate_layers()
	if not _undo.is_empty(): _before=_undo.pop_back()


func select_all() -> void:
	canvas.selected.clear()
	for layer in document.children():
		if document.can_edit(layer): canvas.selected.append(layer.id)
	_selection_changed()


func group_selected() -> void:
	var roots:=document.selected_roots(canvas.selected)
	if roots.is_empty(): add_layer("group"); return
	var group:=Layer.create("group",document.canvas_size)
	_action(func():
		var transforms: Dictionary={}
		for layer in roots: transforms[layer.id]=document.world_transform(layer)
		document.layers.append(group)
		for layer in roots:
			var transform: Transform2D=transforms[layer.id]
			layer.parent_id=group.id; layer.rotation=transform.get_rotation()
			layer.position=transform*(layer.dimensions*.5)-layer.dimensions*.5
		canvas.selected.assign([group.id]))
	_selection_changed()


func ungroup_selected() -> void:
	_action(func():
		for layer in document.selected_roots(canvas.selected):
			if layer.kind!="group": continue
			var parent:=document.layer_for_id(layer.parent_id)
			var inverse:=document.world_transform(parent).affine_inverse() if parent!=null else Transform2D.IDENTITY
			for child in document.children(layer.id):
				var transform:=inverse*document.world_transform(child)
				child.parent_id=layer.parent_id; child.rotation=transform.get_rotation()
				child.position=transform*(child.dimensions*.5)-child.dimensions*.5
			document.layers.erase(layer)
		canvas.selected.clear())


func parent_selected() -> void:
	if canvas.selected.size()<2:
		status.text="Select child layers first, then select the parent layer last."
		return
	var parent_id:=canvas.selected[-1]
	var child_ids: Array[String]=[]
	for id in canvas.selected:
		if id!=parent_id: child_ids.append(id)
	for id in child_ids:
		if document.is_descendant(parent_id,id): status.text="That parenting would create a cycle."; return
	_action(func():
		var parent:=document.layer_for_id(parent_id)
		if parent==null: return
		var inverse:=document.world_transform(parent).affine_inverse()
		for id in child_ids:
			var layer:=document.layer_for_id(id)
			if layer==null: continue
			var transform:=inverse*document.world_transform(layer)
			layer.parent_id=parent_id; layer.rotation=transform.get_rotation()
			layer.position=transform*(layer.dimensions*.5)-layer.dimensions*.5
		canvas.selected.assign([parent_id]))
	status.text="Parented %d layer(s)" % child_ids.size()


func unparent_selected() -> void:
	var ids:=canvas.selected.duplicate()
	_action(func():
		for id in ids:
			var layer:=document.layer_for_id(id)
			if layer==null or layer.parent_id.is_empty(): continue
			var transform:=document.world_transform(layer)
			layer.parent_id=""; layer.rotation=transform.get_rotation()
			layer.position=transform*(layer.dimensions*.5)-layer.dimensions*.5)
	status.text="Unparented selected layers"


func reparent_layers(ids: Array,target_id: String,section: int) -> void:
	var target:=document.layer_for_id(target_id)
	if target==null: return
	var parent_id:=target.id if section==0 else target.parent_id
	for id: String in ids:
		if id==parent_id or document.is_descendant(parent_id,id): return
	var selected_ids: Array[String]=[]; selected_ids.assign(ids)
	_action(func():
		var parent:=document.layer_for_id(parent_id)
		var inverse:=document.world_transform(parent).affine_inverse() if parent!=null else Transform2D.IDENTITY
		for layer in document.selected_roots(selected_ids):
			var transform:=inverse*document.world_transform(layer)
			layer.parent_id=parent_id; layer.rotation=transform.get_rotation()
			layer.position=transform*(layer.dimensions*.5)-layer.dimensions*.5
			document.layers.erase(layer)
			var index:=document.layers.find(target)
			document.layers.insert(clampi(index+(1 if section<=0 else 0),0,document.layers.size()),layer))


func reorder_selected(direction: int) -> void:
	_action(func():
		var roots:=document.selected_roots(canvas.selected)
		if direction>0: roots.reverse()
		for layer in roots:
			var siblings:=document.children(layer.parent_id)
			var next:=siblings.find(layer)+direction
			if next<0 or next>=siblings.size(): continue
			var other: KiwiImageLayer=siblings[next]
			var from:=document.layers.find(layer); var to:=document.layers.find(other)
			document.layers[from]=other; document.layers[to]=layer)


func align_selected(mode: String) -> void:
	var roots:=document.selected_roots(canvas.selected)
	if roots.is_empty(): return
	var bounds:=canvas.selection_bounds() if roots.size()>1 else Rect2(Vector2.ZERO,Vector2(document.canvas_size))
	_action(func():
		for layer in roots:
			var rect:=document.world_transform(layer)*Rect2(Vector2.ZERO,layer.dimensions)
			var delta:=Vector2.ZERO
			match mode:
				"left": delta.x=bounds.position.x-rect.position.x
				"right": delta.x=bounds.end.x-rect.end.x
				"top": delta.y=bounds.position.y-rect.position.y
				"bottom": delta.y=bounds.end.y-rect.end.y
				"center_x": delta.x=bounds.get_center().x-rect.get_center().x
				"center_y": delta.y=bounds.get_center().y-rect.get_center().y
			var parent:=document.layer_for_id(layer.parent_id)
			layer.position+=(document.world_transform(parent).affine_inverse().basis_xform(delta) if parent!=null else delta))


func distribute_selected(horizontal: bool) -> void:
	var layers:=document.selected_roots(canvas.selected)
	if layers.size()<3: return
	layers.sort_custom(func(a: KiwiImageLayer,b: KiwiImageLayer):
		var ca:=document.world_transform(a)*(a.dimensions*.5); var cb:=document.world_transform(b)*(b.dimensions*.5)
		return ca.x<cb.x if horizontal else ca.y<cb.y)
	var first:=document.world_transform(layers[0])*(layers[0].dimensions*.5)
	var last:=document.world_transform(layers[-1])*(layers[-1].dimensions*.5)
	_action(func():
		for index in layers.size():
			var layer:=layers[index]
			var center:=document.world_transform(layer)*(layer.dimensions*.5)
			var goal:=first.lerp(last,float(index)/(layers.size()-1))
			var delta:=Vector2(goal.x-center.x,0) if horizontal else Vector2(0,goal.y-center.y)
			var parent:=document.layer_for_id(layer.parent_id)
			layer.position+=(document.world_transform(parent).affine_inverse().basis_xform(delta) if parent!=null else delta))


func copy_style() -> void:
	var layer:=_main_layer()
	if layer==null: return
	_style_clipboard={"properties":layer.properties.duplicate(true),"effects":layer.copy_layer().effects,"opacity":layer.opacity,"blend":layer.blend}
	status.text="Style copied"


func paste_style() -> void:
	if _style_clipboard.is_empty(): return
	_action(func():
		for id in canvas.selected:
			var layer:=document.layer_for_id(id)
			if layer==null: continue
			for key in ["color","color_end","stroke","stroke_color","radius","font","font_size","bold","outline","outline_color"]:
				if _style_clipboard.properties.has(key): layer.properties[key]=_style_clipboard.properties[key]
			layer.effects.assign(_style_clipboard.effects.duplicate(true))
			for effect in layer.effects:
				if effect.get("curve") is Curve: effect.curve=effect.curve.duplicate()
			layer.opacity=_style_clipboard.opacity; layer.blend=_style_clipboard.blend)


func _save_style() -> void:
	if _main_layer()==null: return
	var dialog:=ConfirmationDialog.new(); dialog.title="Save reusable style"; add_child(dialog)
	var name:=LineEdit.new(); name.text=_main_layer().label+" style"; name.custom_minimum_size.x=280; dialog.add_child(name)
	dialog.confirmed.connect(func():
		if name.text.strip_edges().is_empty(): return
		copy_style(); _presets[name.text.strip_edges()]=_style_clipboard.duplicate(true)
		var library:=Resource.new(); library.set_meta("styles",_presets)
		var error:=ResourceSaver.save(library,"user://image_studio_styles.tres")
		status.text="Style saved for all image documents" if error==OK else "Could not save style library"
		_refresh_inspector())
	dialog.confirmed.connect(dialog.queue_free); dialog.canceled.connect(dialog.queue_free); dialog.close_requested.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(360,130)); name.grab_focus(); name.select_all()


func selection_to_mask() -> void:
	if canvas.selection==null:
		status.text="Draw a pixel selection first (M / L), then choose Mask."; return
	_action(func():
		for id in canvas.selected:
			var layer:=document.layer_for_id(id)
			if layer==null: continue
			var size:=Vector2i(layer.dimensions).max(Vector2i.ONE)
			var mask:=Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
			var transform:=document.world_transform(layer)
			for y in size.y:
				for x in size.x: mask.set_pixel(x,y,Color.WHITE if canvas.selected_pixel(transform*Vector2(x,y)) else Color.BLACK)
			layer.mask=ImageTexture.create_from_image(mask))
	canvas.clear_selection()


func invert_selection() -> void:
	if canvas.selection==null: return
	for y in canvas.selection.get_height():
		for x in canvas.selection.get_width():
			var selected:=canvas.selection.get_pixel(x,y).a>.5
			canvas.selection.set_pixel(x,y,Color(0,0,0,0) if selected else Color.WHITE)
	canvas.selection_texture=ImageTexture.create_from_image(canvas.selection); canvas.pixel_selection_bounds=Rect2(Vector2.ZERO,Vector2(document.canvas_size)); canvas.queue_redraw()


func _save_selection() -> void:
	if canvas.selection==null: status.text="Draw a selection first."; return
	var dialog:=ConfirmationDialog.new(); dialog.title="Save selection"; add_child(dialog)
	var input:=LineEdit.new(); input.text="Selection %d" % (document.selections.size()+1); input.custom_minimum_size.x=280; dialog.add_child(input)
	dialog.confirmed.connect(func():
		if not input.text.strip_edges().is_empty():
			_action(func(): document.selections[input.text.strip_edges()]=ImageTexture.create_from_image(canvas.selection)))
	dialog.confirmed.connect(dialog.queue_free); dialog.canceled.connect(dialog.queue_free); dialog.close_requested.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(340,120)); input.grab_focus(); input.select_all()


func _load_selection() -> void:
	if document.selections.is_empty(): status.text="No saved selections in this document yet."; return
	var popup:=PopupMenu.new(); add_child(popup)
	var names:=document.selections.keys()
	for label in names: popup.add_item(str(label))
	popup.id_pressed.connect(func(index: int):
		canvas.selection=(document.selections[names[index]] as Texture2D).get_image()
		if canvas.selection.get_size()!=document.canvas_size: canvas.selection.resize(document.canvas_size.x,document.canvas_size.y,Image.INTERPOLATE_NEAREST)
		canvas.selection_texture=ImageTexture.create_from_image(canvas.selection)
		var used:=canvas.selection.get_used_rect(); canvas.pixel_selection_bounds=Rect2(used.position,used.size); canvas.queue_redraw())
	popup.popup_hide.connect(popup.queue_free); popup.position=Vector2i(get_global_mouse_position()); popup.popup()


func selection_to_layer() -> void:
	if canvas.selection==null: return
	var bitmap:=await renderer.flattened()
	if bitmap==null or bitmap.is_empty(): status.text="Could not read the canvas."; return
	for y in bitmap.get_height():
		for x in bitmap.get_width():
			var pixel:=bitmap.get_pixel(x,y); pixel.a*=canvas.selection_coverage(Vector2(x,y)); bitmap.set_pixel(x,y,pixel)
	var layer:=Layer.create("image",document.canvas_size); layer.label="Selection"; layer.texture=ImageTexture.create_from_image(bitmap); layer.paint_base=layer.texture
	_action(func(): document.layers.append(layer); canvas.selected.assign([layer.id]))
	canvas.clear_selection()


func _prepare_pixel_selection() -> void:
	_pixel_prepare_generation+=1
	var generation:=_pixel_prepare_generation
	canvas.pixel_source=null
	canvas.smart_selection.invalidate()
	var layer:=_main_layer()
	if layer==null or not document.can_edit(layer): status.text="Select an unlocked layer to select its pixels."; return
	var original:=document
	var temporary:=Document.new(); temporary.canvas_size=document.canvas_size
	var isolated:=layer.copy_layer(); var world:=document.world_transform(layer)
	isolated.parent_id=""; isolated.position=world*(layer.dimensions*.5)-layer.dimensions*.5
	isolated.set_linear_basis(world); isolated.blend=0
	temporary.layers.append(isolated)
	var selection_renderer:=Renderer.new(); add_child(selection_renderer); selection_renderer.sync(temporary)
	var pixels:=await selection_renderer.flattened()
	selection_renderer.queue_free()
	if generation!=_pixel_prepare_generation or original!=document or _main_layer()!=layer: return
	if pixels==null: return
	pixels.convert(Image.FORMAT_RGBA8); canvas.pixel_source=pixels
	var area:=world*Rect2(Vector2.ZERO,layer.content_dimensions())
	canvas.pixel_domain=Rect2i(Vector2i(area.position.floor()),Vector2i(area.size.ceil())).intersection(Rect2i(Vector2i.ZERO,document.canvas_size))
	if canvas.edge_magnet or canvas.pixel_mode=="object": canvas.prepare_smart_selection()
	status.text="Paint selects · Erase subtracts · Fill selects connected colors · Ctrl+Z undoes · Copy / Delete / Extract"


func _apply_pixel_selection(action: String) -> void:
	_finish_pending()
	var layer:=_main_layer()
	if layer==null or not document.can_edit(layer) or canvas.selection==null or canvas.pixel_source==null: return
	if not canvas.selection.get_used_rect().has_area(): return
	var pixels: Image=canvas.pixel_source.duplicate()
	var extracted:=Image.create(pixels.get_width(),pixels.get_height(),false,Image.FORMAT_RGBA8); extracted.fill(Color(0,0,0,0))
	var area:=Rect2i(Vector2i(canvas.pixel_selection_bounds.position.floor()),Vector2i(canvas.pixel_selection_bounds.size.ceil())).intersection(Rect2i(Vector2i.ZERO,pixels.get_size()))
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			var coverage:=canvas.selection_coverage(Vector2(x+.5,y+.5))
			if coverage<=0: continue
			var original:=pixels.get_pixel(x,y); var taken:=original; taken.a*=coverage
			extracted.set_pixel(x,y,taken)
			if action!="copy": pixels.set_pixel(x,y,original.lerp(Color.TRANSPARENT,coverage))
	var selection_layer:=_basic_from_image(extracted,"Selected pixels")
	_action(func():
		if action!="copy":
			var child_transforms: Dictionary={}
			for child in document.children(layer.id): child_transforms[child.id]=document.world_transform(child)
			var baked:=_basic_from_image(pixels,layer.label)
			var parent:=document.layer_for_id(layer.parent_id)
			var inverse:=document.world_transform(parent).affine_inverse() if parent!=null else Transform2D.IDENTITY
			layer.kind="basic"; layer.dimensions=baked.dimensions; layer.position=inverse*(baked.position+baked.dimensions*.5)-baked.dimensions*.5
			layer.rotation=0; layer.opacity=1; layer.texture=baked.texture; layer.paint_base=baked.paint_base; layer.mask=null; layer.warp=null; layer.effects.clear(); layer.properties=baked.properties
			layer.set_linear_basis(inverse)
			var new_inverse:=document.world_transform(layer).affine_inverse()
			for child in document.children(layer.id):
				var previous: Transform2D=child_transforms[child.id]
				child.position=new_inverse*(previous*(child.dimensions*.5))-child.dimensions*.5
				child.set_linear_basis(new_inverse*previous)
		if action!="delete": document.layers.append(selection_layer); canvas.selected.assign([selection_layer.id])
		document.pixel_selection=null; document.pixel_selection_owner=""
		document.pixel_selection_reference=null; document.pixel_selection_reference_world=Transform2D.IDENTITY)
	canvas.clear_selection(); canvas.pixel_source=null; _set_tool("move")


func _flip_layer(horizontal: bool) -> void:
	if canvas.selected.is_empty(): return
	_action(func():
		for id in canvas.selected:
			var layer:=document.layer_for_id(id)
			if layer==null: continue
			var world:=document.world_transform(layer)
			var parent:=document.layer_for_id(layer.parent_id)
			var inverse:=document.world_transform(parent).affine_inverse() if parent!=null else Transform2D.IDENTITY
			var reflection:=Vector2(-1,1) if horizontal else Vector2(1,-1)
			layer.set_linear_basis(inverse*Transform2D(world.x*reflection,world.y*reflection,Vector2.ZERO)))


func _small_layer_icon(key: String) -> Texture2D:
	var cache_key:="small_"+key
	if not _icons.has(cache_key):
		var bitmap:=_icon(key).get_image(); bitmap.resize(14,14,Image.INTERPOLATE_LANCZOS)
		_icons[cache_key]=ImageTexture.create_from_image(bitmap)
	return _icons[cache_key]


func fill_selected_to_parent() -> void:
	var roots:=document.selected_roots(canvas.selected)
	if roots.is_empty(): return
	_action(func():
		for layer in roots:
			var parent:=document.layer_for_id(layer.parent_id)
			layer.rotation=0; layer.properties.erase("basis_x"); layer.properties.erase("basis_y")
			layer.properties.yaw_up_down=0.0; layer.properties.yaw_left_right=0.0
			layer.position=Vector2.ZERO
			document.resize_layer(layer,parent.dimensions if parent!=null else Vector2(document.canvas_size)))
	status.text="Filled the parent bounds" if not roots[0].parent_id.is_empty() else "Filled the canvas"


func resize_image_aspect() -> void:
	var layer:=_main_layer()
	if layer==null or layer.kind!="image" or layer.texture==null: return
	var source_size:=Vector2(layer.texture.get_size())
	if source_size.x<1 or source_size.y<1: return
	var area:=layer.dimensions; var ratio:=source_size.x/source_size.y
	var target:=Vector2(area.y*ratio,area.y) if area.x/area.y>ratio else Vector2(area.x,area.x/ratio)
	_action(func(): document.resize_layer(layer,target); layer.properties.keep_aspect=true)


func restore_layer_paint() -> void:
	var restorable: Array[KiwiImageLayer]=[]
	for id in canvas.selected:
		var layer:=document.layer_for_id(id)
		if layer!=null and layer.paint_base!=null: restorable.append(layer)
	if restorable.is_empty(): status.text="This layer has no paint history to restore."; return
	_action(func():
		for layer in restorable: layer.texture=layer.paint_base)
	status.text="Restored the original layer pixels"


func _canvas_size_dialog() -> void:
	var dialog:=ConfirmationDialog.new(); dialog.title="Canvas size"; add_child(dialog)
	var row:=HBoxContainer.new(); dialog.add_child(row)
	var width:=SpinBox.new(); width.min_value=1; width.max_value=8192; width.value=document.canvas_size.x; row.add_child(width)
	var height:=SpinBox.new(); height.min_value=1; height.max_value=8192; height.value=document.canvas_size.y; row.add_child(height)
	dialog.confirmed.connect(func(): _action(func(): document.canvas_size=Vector2i(int(width.value),int(height.value))); canvas.clear_selection(); canvas.fit())
	dialog.confirmed.connect(dialog.queue_free); dialog.canceled.connect(dialog.queue_free); dialog.close_requested.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(350,120))


func _image_size_dialog() -> void:
	var dialog:=ConfirmationDialog.new(); dialog.title="Resize image"; add_child(dialog)
	var column:=VBoxContainer.new(); column.custom_minimum_size=Vector2(390,190); column.add_theme_constant_override("separation",10); dialog.add_child(column)
	var intro:=Label.new(); intro.text="Scale the canvas and every layer together"; intro.add_theme_color_override("font_color",Color("8fa8bb")); column.add_child(intro)
	var row:=HBoxContainer.new(); column.add_child(row)
	var width:=SpinBox.new(); width.min_value=1; width.max_value=16384; width.value=document.canvas_size.x; width.prefix="Width  "; width.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(width)
	var height:=SpinBox.new(); height.min_value=1; height.max_value=16384; height.value=document.canvas_size.y; height.prefix="Height  "; height.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(height)
	var linked:=CheckButton.new(); linked.text="Keep image aspect ratio"; linked.button_pressed=true; column.add_child(linked)
	var ratio:=float(document.canvas_size.x)/maxf(1,document.canvas_size.y)
	var syncing:=false
	width.value_changed.connect(func(value: float):
		if linked.button_pressed and not syncing: syncing=true; height.value=round(value/ratio); syncing=false)
	height.value_changed.connect(func(value: float):
		if linked.button_pressed and not syncing: syncing=true; width.value=round(value*ratio); syncing=false)
	var quality:=OptionButton.new(); quality.add_item("Lanczos · best for photos"); quality.add_item("Bilinear · fast and smooth"); quality.add_item("Nearest · pixel art"); column.add_child(quality)
	dialog.confirmed.connect(func():
		var interpolation:=Image.INTERPOLATE_LANCZOS if quality.selected==0 else (Image.INTERPOLATE_BILINEAR if quality.selected==1 else Image.INTERPOLATE_NEAREST)
		_scale_image(Vector2i(int(width.value),int(height.value)),interpolation))
	dialog.confirmed.connect(dialog.queue_free); dialog.canceled.connect(dialog.queue_free); dialog.close_requested.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(440,250))


func _scale_image(new_size: Vector2i,interpolation: int) -> void:
	if new_size.x<1 or new_size.y<1 or new_size==document.canvas_size: return
	var ratio:=Vector2(new_size)/Vector2(document.canvas_size)
	_action(func():
		for layer in document.layers:
			layer.position*=ratio; layer.dimensions*=ratio
			if layer.texture!=null and layer.kind in ["image","paint","basic"]:
				var bitmap:=layer.texture.get_image()
				if bitmap!=null:
					bitmap=bitmap.duplicate(); bitmap.resize(maxi(1,roundi(bitmap.get_width()*ratio.x)),maxi(1,roundi(bitmap.get_height()*ratio.y)),interpolation)
					layer.texture=ImageTexture.create_from_image(bitmap)
				if layer.paint_base!=null:
					var original:=layer.paint_base.get_image()
					if original!=null:
						original=original.duplicate(); original.resize(maxi(1,roundi(original.get_width()*ratio.x)),maxi(1,roundi(original.get_height()*ratio.y)),interpolation)
						layer.paint_base=ImageTexture.create_from_image(original)
			if layer.mask!=null:
				var mask:=layer.mask.get_image()
				if mask!=null:
					mask=mask.duplicate(); mask.resize(maxi(1,roundi(mask.get_width()*ratio.x)),maxi(1,roundi(mask.get_height()*ratio.y)),Image.INTERPOLATE_BILINEAR)
					layer.mask=ImageTexture.create_from_image(mask)
			if layer.kind=="text": layer.properties.text_scale=float(layer.properties.get("text_scale",1.0))*minf(ratio.x,ratio.y)
		document.canvas_size=new_size)
	canvas.clear_selection(); canvas.fit(); status.text="Image resized to %d × %d" % [new_size.x,new_size.y]


func _choose_image() -> void:
	var property:=ActorProperty.new(); property.options={"extensions":IMAGE_EXTENSIONS+["tres","res"],"native_resource_types":["KiwiImageDocument"],"file_picker":true}
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Open image or Image Studio document")
	if chosen==ActorProjectFilePicker.EMPTY_RESOURCE: return
	if chosen.is_empty(): return
	var tabs:=get_tree().get_first_node_in_group("actor_scene_tabs")
	if tabs!=null: tabs.open_image(chosen)
	else: open_source(chosen)


func _choose_import() -> void:
	var property:=ActorProperty.new(); property.options={"extensions":IMAGE_EXTENSIONS,"file_picker":true}
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Add an image layer")
	if chosen==ActorProjectFilePicker.EMPTY_RESOURCE: add_layer("image"); return
	if not chosen.is_empty(): _import_paths(PackedStringArray([chosen]),Vector2(document.canvas_size)*.5)


func _replace_image() -> void:
	var layer:=_main_layer()
	if layer==null: return
	var property:=ActorProperty.new(); property.options={"extensions":IMAGE_EXTENSIONS,"file_picker":true}
	var chosen:=await ActorProjectFilePicker.pick(self,property,"Replace layer image")
	if chosen==ActorProjectFilePicker.EMPTY_RESOURCE:
		_action(func(): layer.texture=null; layer.paint_base=null; layer.properties.erase("noise_image"); layer.properties.erase("image_path")); return
	if chosen.is_empty(): return
	var bitmap:=Image.load_from_file(chosen)
	if bitmap!=null: _action(func(): layer.texture=ImageTexture.create_from_image(bitmap); layer.paint_base=layer.texture; layer.properties.erase("noise_image"); layer.properties.image_path=chosen)


func _import_paths(paths: PackedStringArray,at: Vector2) -> void:
	var layers: Array[KiwiImageLayer]=[]
	for file in paths:
		if file.get_extension().to_lower() not in IMAGE_EXTENSIONS: continue
		var bitmap:=Image.load_from_file(file)
		if bitmap==null or bitmap.is_empty(): continue
		var layer:=Layer.create("image",document.canvas_size)
		layer.label=file.get_file().get_basename(); layer.texture=ImageTexture.create_from_image(bitmap)
		layer.paint_base=layer.texture
		var fit:=minf(1.0,minf(document.canvas_size.x/float(bitmap.get_width()),document.canvas_size.y/float(bitmap.get_height())))
		layer.dimensions=Vector2(bitmap.get_size())*fit
		layer.position=at-layer.dimensions*.5; layers.append(layer); _remember_asset(file)
	if layers.is_empty(): return
	_action(func():
		canvas.selected.clear()
		for layer in layers: document.layers.append(layer); canvas.selected.append(layer.id))
	_set_tool("move")


func save() -> void:
	await _save_targets(true,true)


func save_image() -> void:
	if document.output_path.is_empty() and not source is ImageTexture: await save_as(); return
	await _save_targets(true,false)


func save_project() -> void:
	if document_path.is_empty(): await save_project_as(); return
	await _save_targets(false,true)


func save_project_as() -> void:
	var result:=await ActorProjectResourceSaveDialog.pick(self,"Save image project", "Image Project","tres",false)
	if result.get("cancelled",true): return
	document_path=str(result.path)
	await _save_targets(false,true)


func _wait_for_repair() -> void:
	if canvas.repair_tool.active: canvas.repair_tool.finish()
	while canvas.repair_tool.active or (canvas.repair_tool.engine.busy() and not canvas.repair_tool._generation_target.is_empty()): await get_tree().process_frame

func _save_targets(write_image: bool,write_project: bool) -> void:
	if _busy: return
	await _wait_for_repair()
	_finish_pending()
	if document.output_path.is_empty() and document_path.is_empty() and not source is ImageTexture:
		await save_as(); return
	_busy=true; status.text="Rendering and saving…"
	var saved_document:=document
	var save_version:=_edit_version
	var snapshot:=document.snapshot(); snapshot.workspace_state=_ui_state()
	var image_destination:=snapshot.output_path if write_image else ""
	var project_destination:=document_path if write_project else ""
	var embedded_source: Variant=source
	var flattened:=_flatten_cache
	if flattened==null:
		renderer.document=snapshot
		flattened=await renderer.flattened()
		if save_version==_edit_version: _flatten_cache=flattened
		renderer.sync(document)
	if flattened==null or flattened.is_empty():
		status.text="Could not render the image."; _busy=false; return
	image=flattened
	var thumb:=flattened.duplicate(); thumb.resize(192,maxi(1,roundi(192.0*flattened.get_height()/flattened.get_width())),Image.INTERPOLATE_BILINEAR)
	snapshot.preview=ImageTexture.create_from_image(thumb)
	if saved_document==document: document.preview=snapshot.preview; document.workspace_state=snapshot.workspace_state
	var error:=OK
	if write_image and image_destination.is_empty() and embedded_source is ImageTexture:
		embedded_source.set_image(flattened); embedded_source.set_meta("kiwi_image_document",snapshot)
	var results: Array[int]=[OK]
	var job:=WorkerThreadPool.add_task(func():
		if not image_destination.is_empty(): results[0]=_write_bitmap(flattened,image_destination)
		if results[0]==OK and not project_destination.is_empty():
			_pack_project_textures(snapshot)
			results[0]=ResourceSaver.save(snapshot,project_destination),false,"Save Image Studio")
	while not WorkerThreadPool.is_task_completed(job): await get_tree().process_frame
	WorkerThreadPool.wait_for_task_completion(job)
	error=results[0]
	if saved_document!=document: _busy=false; return
	if error!=OK:
		status.text="Could not save the image document (%d)." % error; _busy=false; return
	_dirty=save_version!=_edit_version; _update_title()
	if write_project and not document_path.is_empty():
		path=document_path; source=path; image_saved.emit(path)
	elif write_image: image_saved.emit(source if document.output_path.is_empty() else document.output_path)
	if _dirty: document_changed.emit()
	status.text="Saved · "+("image " if write_image else "")+("project" if write_project and not document_path.is_empty() else "")
	_busy=false
	if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()


func save_as() -> void:
	_finish_pending()
	var result:=await ActorProjectResourceSaveDialog.pick(self,"Save image as",
		path.get_file().get_basename() if not path.is_empty() else "Untitled Image","png",false,PackedStringArray(SAVE_FORMATS))
	if result.get("cancelled",true): return
	document.output_path=str(result.path); path=document.output_path; source=path
	await _save_targets(true,false)


func _pack_project_textures(snapshot: KiwiImageDocument) -> void:
	# Serialize compact lossless buffers, not millions of decimal RGBA bytes.
	# Work only on the immutable save snapshot; live layer textures stay editable.
	var packed: Dictionary={}
	if snapshot.pixel_selection is ImageTexture:
		var compact:=PortableCompressedTexture2D.new(); compact.keep_compressed_buffer=true
		compact.create_from_image(snapshot.pixel_selection.get_image(),PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
		snapshot.pixel_selection=compact
	for layer in snapshot.layers:
		for field in ["texture","paint_base","mask"]:
			var texture: Texture2D=layer.get(field)
			if not texture is ImageTexture or not texture.resource_path.is_empty(): continue
			var id:=texture.get_instance_id()
			if not packed.has(id):
				var bitmap:=texture.get_image()
				if bitmap==null: continue
				var compact:=PortableCompressedTexture2D.new(); compact.keep_compressed_buffer=true
				compact.create_from_image(bitmap,PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS)
				packed[id]=compact
			layer.set(field,packed[id])


func _new_output_path(native_path: String) -> String:
	var base:=native_path.get_basename()
	var output:=base+".png"; var index:=2
	while FileAccess.file_exists(output):
		output=base+"-"+str(index)+".png"; index+=1
	return output


func export_image() -> void:
	var dialog:=FileDialog.new(); dialog.access=FileDialog.ACCESS_FILESYSTEM; dialog.file_mode=FileDialog.FILE_MODE_SAVE_FILE
	dialog.use_native_dialog=true; dialog.title="Export image"; dialog.filters=PackedStringArray(["*.png ; PNG","*.jpg,*.jpeg ; JPEG","*.webp ; WebP"]); dialog.current_file="Image.png"
	add_child(dialog)
	dialog.file_selected.connect(func(destination: String): _export_to(destination); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered_ratio(.75)


func _export_to(destination: String) -> void:
	await _wait_for_repair()
	_finish_pending(); renderer.sync(document)
	var bitmap:=await renderer.flattened()
	if bitmap==null or bitmap.is_empty(): status.text="Could not render the image."; return
	var error:=_write_bitmap(bitmap,destination)
	status.text="Exported "+destination.get_file() if error==OK else "Export failed (%d)" % error
	if error==OK and LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()


func _write_bitmap(bitmap: Image,destination: String) -> Error:
	var disk:=ProjectSettings.globalize_path(destination) if destination.begins_with("res://") or destination.begins_with("user://") else destination
	match destination.get_extension().to_lower():
		"png": return bitmap.save_png(disk)
		"jpg","jpeg": return bitmap.save_jpg(disk,.94)
		"webp": return bitmap.save_webp(disk,false,.9)
	return ERR_FILE_UNRECOGNIZED


func _workflow_window(title: String,minimum:=Vector2(720,500)) -> Dictionary:
	var popup:=PopupPanel.new(); popup.add_theme_stylebox_override("panel",_box(Color("111c28"),Color("426879"),12,14)); add_child(popup)
	var column:=VBoxContainer.new(); column.custom_minimum_size=minimum; column.add_theme_constant_override("separation",10); popup.add_child(column)
	var header:=HBoxContainer.new(); column.add_child(header)
	var heading:=Label.new(); heading.text=title.to_upper(); heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL; heading.add_theme_font_size_override("font_size",18); heading.add_theme_color_override("font_color",Color("77e4c7")); header.add_child(heading)
	_button(header,"×",popup.queue_free,"Close")
	popup.popup_hide.connect(popup.queue_free)
	return {"popup":popup,"body":column}


func _panel_card(parent: Control,title: String,subtitle: String="") -> VBoxContainer:
	var panel:=PanelContainer.new(); panel.add_theme_stylebox_override("panel",_box(Color("182635"),Color("304a5c"),8,9)); parent.add_child(panel)
	var column:=VBoxContainer.new(); column.add_theme_constant_override("separation",5); panel.add_child(column)
	var label:=Label.new(); label.text=title; label.add_theme_color_override("font_color",Color("d9edf2")); label.add_theme_font_size_override("font_size",14); column.add_child(label)
	if not subtitle.is_empty():
		var note:=Label.new(); note.text=subtitle; note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; note.add_theme_color_override("font_color",Color("88a5b8")); column.add_child(note)
	return column


func _transform_panel() -> void:
	var ui:=_workflow_window("Transform & align",Vector2(680,430)); var body: VBoxContainer=ui.body
	var selection:=_panel_card(body,"Selection layout","Align one layer to the canvas, or align several layers to their shared bounds.")
	var align:=HFlowContainer.new(); selection.add_child(align)
	for entry in [["Left","left"],["Center X","center_x"],["Right","right"],["Top","top"],["Center Y","center_y"],["Bottom","bottom"]]:
		var mode: String=entry[1]; _button(align,entry[0],func(): align_selected(mode))
	_button(align,"Distribute X",func(): distribute_selected(true),"Evenly distribute three or more layers")
	_button(align,"Distribute Y",func(): distribute_selected(false),"Evenly distribute three or more layers")
	var match_card:=_panel_card(body,"Match & repeat","Reuse exact transforms without re-entering numbers.")
	var actions:=HFlowContainer.new(); match_card.add_child(actions)
	_button(actions,"Copy transform",_copy_transform)
	_button(actions,"Paste transform",_paste_transform)
	_button(actions,"Match main width",func(): _match_selected_size(true,false))
	_button(actions,"Match main height",func(): _match_selected_size(false,true))
	_button(actions,"Match complete size",func(): _match_selected_size(true,true))
	_button(actions,"Reset rotation / yaw",func(): _action(func():
		for id in canvas.selected:
			var layer:=document.layer_for_id(id)
			if layer!=null: layer.rotation=0; layer.properties.yaw_up_down=0.0; layer.properties.yaw_left_right=0.0))
	(ui.popup as PopupPanel).popup_centered()


func _copy_transform() -> void:
	var layer:=_main_layer()
	if layer==null: return
	_transform_clipboard={"position":layer.position,"dimensions":layer.dimensions,"rotation":layer.rotation,"basis_x":layer.properties.get("basis_x",Vector2.RIGHT),"basis_y":layer.properties.get("basis_y",Vector2.DOWN),"yaw_up_down":layer.properties.get("yaw_up_down",0.0),"yaw_left_right":layer.properties.get("yaw_left_right",0.0)}
	status.text="Transform copied"


func _paste_transform() -> void:
	if _transform_clipboard.is_empty(): return
	_action(func():
		for id in canvas.selected:
			var layer:=document.layer_for_id(id)
			if layer==null: continue
			layer.position=_transform_clipboard.position; layer.dimensions=_transform_clipboard.dimensions; layer.rotation=_transform_clipboard.rotation
			for key in ["basis_x","basis_y","yaw_up_down","yaw_left_right"]: layer.properties[key]=_transform_clipboard[key])


func _match_selected_size(width: bool,height: bool) -> void:
	var main:=_main_layer()
	if main==null: return
	var target:=main.dimensions
	_action(func():
		for id in canvas.selected:
			var layer:=document.layer_for_id(id)
			if layer==null or layer==main: continue
			var dimensions:=layer.dimensions
			if width: dimensions.x=target.x
			if height: dimensions.y=target.y
			document.resize_layer(layer,dimensions))


func _selection_panel() -> void:
	var ui:=_workflow_window("Smart selection & masks",Vector2(720,500)); var body: VBoxContainer=ui.body
	var smart:=_panel_card(body,"Smart pixel selection","Build editable selections from the active layer, then refine them non-destructively.")
	var smart_actions:=HFlowContainer.new(); smart.add_child(smart_actions)
	_button(smart_actions,"Select subject",func(): _smart_select("opaque"),"Select all non-transparent pixels")
	_button(smart_actions,"Select background",func(): _smart_select("transparent"),"Select transparent background pixels")
	_button(smart_actions,"Select similar color…",_select_similar_dialog)
	_button(smart_actions,"Select highlights",func(): _smart_select("highlights"))
	_button(smart_actions,"Select shadows",func(): _smart_select("shadows"))
	var refine:=HFlowContainer.new(); smart.add_child(refine)
	_button(refine,"Grow 2 px",func(): _modify_selection("grow",2))
	_button(refine,"Shrink 2 px",func(): _modify_selection("shrink",2))
	_button(refine,"Feather 3 px",func(): _modify_selection("feather",3))
	_button(refine,"Smooth",func(): _modify_selection("smooth",2))
	_button(refine,"Invert   Ctrl+I",invert_selection)
	_button(refine,"Clear",func(): _action(func(): document.pixel_selection=null; document.pixel_selection_reference=null); canvas.clear_selection())
	var masks:=_panel_card(body,"Layer masks & clipping","Masks stay editable; clipping uses the opacity of the layer directly below.")
	var mask_actions:=HFlowContainer.new(); masks.add_child(mask_actions)
	_button(mask_actions,"Selection → mask",selection_to_mask)
	_button(mask_actions,"Mask → selection",_mask_to_selection,"Load the current layer mask into the pixel-selection brush for editing")
	_button(mask_actions,"Opacity → mask",func(): _source_to_mask(false))
	_button(mask_actions,"Luminance → mask",func(): _source_to_mask(true))
	_button(mask_actions,"Invert mask",_invert_layer_masks)
	_button(mask_actions,"Clear mask",func(): _action(func():
		for id in canvas.selected:
			var layer:=document.layer_for_id(id)
			if layer!=null: layer.mask=null))
	_button(mask_actions,"Toggle clip below",func(): _action(func():
		for id in canvas.selected:
			var layer:=document.layer_for_id(id)
			if layer!=null: layer.clip_to_below=not layer.clip_to_below))
	_button(mask_actions,"Adjustment group",_create_adjustment_group,"Wrap selected layers in a group whose effects adjust the whole group")
	(ui.popup as PopupPanel).popup_centered()


func _commit_selection_bitmap(bitmap: Image) -> void:
	var owner:=_main_layer()
	if owner==null: return
	_action(func():
		document.pixel_selection=ImageTexture.create_from_image(bitmap); document.pixel_selection_owner=owner.id
		document.pixel_selection_reference=owner.copy_layer(); document.pixel_selection_reference_world=document.world_transform(owner))
	canvas.sync_pixel_selection(); _refresh_context()


func _smart_select(kind: String,reference:=Color.TRANSPARENT,threshold: float=.12) -> void:
	await _prepare_pixel_selection()
	if canvas.pixel_source==null: return
	var source:=canvas.pixel_source; var mask:=Image.create(document.canvas_size.x,document.canvas_size.y,false,Image.FORMAT_RGBA8); mask.fill(Color.TRANSPARENT)
	for y in source.get_height():
		for x in source.get_width():
			var color:=source.get_pixel(x,y); var chosen:=false
			match kind:
				"opaque": chosen=color.a>.001
				"transparent": chosen=color.a<=.001
				"highlights": chosen=color.a>.001 and color.get_luminance()>=.65
				"shadows": chosen=color.a>.001 and color.get_luminance()<=.35
				"similar": chosen=color.a>.001 and Vector3(color.r-reference.r,color.g-reference.g,color.b-reference.b).length()<=threshold*1.732
			if chosen: mask.set_pixel(x,y,Color.WHITE)
	_commit_selection_bitmap(mask); status.text="Smart selection created"


func _select_similar_dialog() -> void:
	var dialog:=ConfirmationDialog.new(); dialog.title="Select similar color"; add_child(dialog)
	var column:=VBoxContainer.new(); column.custom_minimum_size=Vector2(380,130); dialog.add_child(column)
	var picker:=ColorPickerButton.new(); picker.color=color_picker.color; picker.text="Reference color"; column.add_child(picker)
	var tolerance:=HSlider.new(); tolerance.min_value=.001; tolerance.max_value=1; tolerance.step=.001; tolerance.value=.12; column.add_child(tolerance)
	dialog.confirmed.connect(func(): _smart_select("similar",picker.color,tolerance.value); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered()


func _current_selection_bitmap() -> Image:
	if canvas.selection!=null and not canvas.selection_inverse_warp.is_valid() and canvas.selection_transform.is_equal_approx(Transform2D.IDENTITY): return canvas.selection.duplicate()
	var result:=Image.create(document.canvas_size.x,document.canvas_size.y,false,Image.FORMAT_RGBA8); result.fill(Color.TRANSPARENT)
	if canvas.selection==null: return result
	for y in document.canvas_size.y:
		for x in document.canvas_size.x:
			result.set_pixel(x,y,Color(1,1,1,canvas.selection_coverage(Vector2(x,y))))
	return result


func _modify_selection(kind: String,radius: int) -> void:
	if canvas.selection==null: return
	var source:=_current_selection_bitmap(); var result:=source.duplicate(); var size:=source.get_size(); var width:=size.x; var height:=size.y
	var horizontal:=PackedFloat32Array(); horizontal.resize(width*height)
	# Separable filters make refinement linear in radius instead of sampling a
	# full square for every canvas pixel.
	for y in height:
		for x in width:
			var value:=0.0 if kind in ["grow","feather","smooth"] else 1.0; var count:=0
			for offset in range(-radius,radius+1):
				var sx:=x+offset; var alpha:=source.get_pixel(sx,y).a if sx>=0 and sx<width else 0.0
				if kind=="grow": value=maxf(value,alpha)
				elif kind=="shrink": value=minf(value,alpha)
				else: value+=alpha; count+=1
			horizontal[y*width+x]=value if kind in ["grow","shrink"] else value/maxi(1,count)
	for y in height:
		for x in width:
			var value:=0.0 if kind in ["grow","feather","smooth"] else 1.0; var count:=0
			for offset in range(-radius,radius+1):
				var sy:=y+offset; var alpha:=horizontal[sy*width+x] if sy>=0 and sy<height else 0.0
				if kind=="grow": value=maxf(value,alpha)
				elif kind=="shrink": value=minf(value,alpha)
				else: value+=alpha; count+=1
			if kind not in ["grow","shrink"]: value/=maxi(1,count)
			if kind=="smooth": value=1.0 if value>=.5 else 0.0
			result.set_pixel(x,y,Color(1,1,1,value))
	_commit_selection_bitmap(result)


func _source_to_mask(luminance: bool) -> void:
	var layer:=_main_layer()
	if layer==null: return
	var bitmap:=layer.texture.get_image() if layer.texture!=null else null
	if bitmap==null:
		status.text="This layer needs raster content or a pixel selection for a mask."; return
	bitmap=bitmap.duplicate(); bitmap.resize(maxi(1,roundi(layer.dimensions.x)),maxi(1,roundi(layer.dimensions.y)),Image.INTERPOLATE_BILINEAR)
	for y in bitmap.get_height():
		for x in bitmap.get_width():
			var color:=bitmap.get_pixel(x,y); var value:=color.get_luminance()*color.a if luminance else color.a
			bitmap.set_pixel(x,y,Color(value,value,value,value))
	_action(func(): layer.mask=ImageTexture.create_from_image(bitmap))


func _mask_to_selection() -> void:
	var layer:=_main_layer()
	if layer==null or layer.mask==null: status.text="The selected layer has no mask."; return
	var local:=layer.mask.get_image(); var result:=Image.create(document.canvas_size.x,document.canvas_size.y,false,Image.FORMAT_RGBA8); result.fill(Color.TRANSPARENT)
	var transform:=document.world_transform(layer); var inverse:=transform.affine_inverse(); var source_size:=Vector2(local.get_size())
	var bounds:=Rect2i(Vector2i((transform*Rect2(Vector2.ZERO,layer.dimensions)).position.floor()),Vector2i((transform*Rect2(Vector2.ZERO,layer.dimensions)).size.ceil())).intersection(Rect2i(Vector2i.ZERO,document.canvas_size))
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			var p: Vector2=(inverse*Vector2(x,y))*source_size/layer.dimensions.max(Vector2.ONE); var sample:=Vector2i(p)
			if Rect2i(Vector2i.ZERO,local.get_size()).has_point(sample):
				var alpha:=local.get_pixelv(sample).a; result.set_pixel(x,y,Color(1,1,1,alpha))
	_commit_selection_bitmap(result); _set_tool("pixel_select")


func _invert_layer_masks() -> void:
	_action(func():
		for id in canvas.selected:
			var layer:=document.layer_for_id(id)
			if layer==null or layer.mask==null: continue
			var bitmap:=layer.mask.get_image().duplicate()
			for y in bitmap.get_height():
				for x in bitmap.get_width():
					var value: float=1.0-bitmap.get_pixel(x,y).a; bitmap.set_pixel(x,y,Color(value,value,value,value))
			layer.mask=ImageTexture.create_from_image(bitmap))


func _create_adjustment_group() -> void:
	var roots:=document.selected_roots(canvas.selected)
	if roots.is_empty(): return
	group_selected()
	var group:=_main_layer()
	if group!=null: group.label="Adjustment group"; add_effect("brightness"); _effects_panel()


func _effects_panel() -> void:
	_set_tool("effects"); _open_stack_editor(false)

func _toggle_effects_panel() -> void:
	_set_tool("effects")

func _open_stack_editor(adjustments: bool) -> void:
	if _main_layer()==null: status.text="Select a layer first."; return
	_finish_pending()
	var editor:=preload("res://Workspaces/ImageWorkspace/image_stack_editor.gd").new()
	editor.workspace=self; editor.layer_id=_main_layer().id; editor.adjustments=adjustments
	add_child(editor); editor.popup_centered()

func _build_effects_dock() -> void:
	_effects_dock.name="EffectsDock"; _effects_dock.add_theme_constant_override("separation",6)
	var header:=HBoxContainer.new(); _effects_dock.add_child(header)
	var title:=Label.new(); title.text="EFFECTS & STYLES"; title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size",12); title.add_theme_color_override("font_color",Color("77e4c7")); header.add_child(title)
	_button(header,"×",_toggle_effects_panel,"Return to layer properties")
	_effects_search.name="EffectsSearch"; _effects_search.placeholder_text="Search effects…"; _effects_search.clear_button_enabled=true
	_effects_dock.add_child(_effects_search)
	_effects_search.text_changed.connect(func(value: String): _effects_filter=value; _refresh_effects_dock())
	_effects_scroll.name="EffectsScroll"; _effects_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	_effects_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	_effects_scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_SHOW_ALWAYS; _effects_dock.add_child(_effects_scroll)
	_effects_content.size_flags_horizontal=Control.SIZE_EXPAND_FILL; _effects_content.add_theme_constant_override("separation",8)
	_effects_scroll.add_child(_effects_content)

func _refresh_effects_dock() -> void:
	if not _effects_open: return
	var layer:=_main_layer()
	var signature:=str(document.get_instance_id())+_effects_filter+(layer.id if layer!=null else "")
	if layer!=null:
		for effect in layer.effects:
			signature+=str(effect.get("id",""))+str(effect.type)
			if effect.get("curve") is Curve: signature+=str(effect.curve.get_instance_id())
	if signature==_effects_signature: return
	_effects_signature=signature
	var old_scroll:=_effects_scroll.scroll_vertical
	_clear(_effects_content)
	if layer==null:
		var empty:=Label.new(); empty.text="Select a layer to edit its effects."; empty.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		_effects_content.add_child(empty); return
	var label:=Label.new(); label.text=layer.label; label.clip_text=true; label.add_theme_color_override("font_color",Color("9db3c6")); _effects_content.add_child(label)
	_effect_selection_control(_effects_content,layer)
	var choices: Array=[]
	for kind in AVAILABLE_EFFECTS:
		var effect_kind: String=kind; var title: String=effect_kind.replace("_"," ").capitalize()
		if title.to_lower().contains(_effects_filter.to_lower()): choices.append([title,func(): add_effect(effect_kind)])
	if "canvas shader".contains(_effects_filter.to_lower()): choices.append(["Canvas shader…",_choose_shader_effect])
	var add:=_menu(_effects_content,"＋ Add effect",choices); add.disabled=choices.is_empty()
	var visible_effects:=0
	for index in layer.effects.size():
		var effect: Dictionary=layer.effects[index]; var effect_index:=index
		var title:=str(effect.type).replace("_"," ").capitalize()
		if not title.to_lower().contains(_effects_filter.to_lower()): continue
		visible_effects+=1
		var panel:=PanelContainer.new(); panel.add_theme_stylebox_override("panel",_box(Color("111c28"),Color("304a5c"),6,7)); _effects_content.add_child(panel)
		var fields:=VBoxContainer.new(); fields.add_theme_constant_override("separation",5); panel.add_child(fields)
		var header:=HBoxContainer.new(); fields.add_child(header)
		var enabled:=CheckButton.new(); enabled.text=title; enabled.button_pressed=effect.get("enabled",true); enabled.size_flags_horizontal=Control.SIZE_EXPAND_FILL; header.add_child(enabled)
		enabled.toggled.connect(func(value: bool): _action(func(): effect.enabled=value))
		_button(header,"×",func(): _action(func(): layer.effects.remove_at(effect_index)),"Remove effect")
		_effect_fields(fields,effect)
		var actions:=HBoxContainer.new(); fields.add_child(actions)
		_button(actions,"Apply",func(): await _apply_effect(layer,effect_index),"Bake effects through this point into layer pixels")
		_button(actions,"↑",func(): _move_effect(effect_index,-1),"Move effect earlier")
		_button(actions,"↓",func(): _move_effect(effect_index,1),"Move effect later")
	if visible_effects==0:
		var empty:=Label.new(); empty.text="No matching effects." if not _effects_filter.is_empty() else "Add an effect to get started."
		empty.add_theme_color_override("font_color",Color("8fa8bb")); _effects_content.add_child(empty)
	var styles: Array=[["Copy style",copy_style],["Paste style",paste_style],["Save current style…",_save_style]]
	for name: String in _presets:
		var style_name:=name; styles.append([style_name,func(): _apply_style_preset(style_name,false)])
		styles.append(["Link: "+style_name,func(): _apply_style_preset(style_name,true)])
	_menu(_effects_content,"Style presets",styles)
	_effects_scroll.set_deferred("scroll_vertical",old_scroll)


func _apply_style_preset(name: String,linked: bool) -> void:
	if not _presets.has(name): return
	_style_clipboard=_presets[name].duplicate(true); paste_style()
	_action(func():
		for id in canvas.selected:
			var layer:=document.layer_for_id(id)
			if layer!=null:
				if linked: layer.properties.linked_style=name
				else: layer.properties.erase("linked_style"))


func _sync_linked_styles() -> void:
	for layer in document.layers:
		var name:=str(layer.properties.get("linked_style",""))
		if name.is_empty() or not _presets.has(name): continue
		var style: Dictionary=_presets[name]
		var values: Dictionary=style.get("properties",{})
		for key in ["color","color_end","stroke","stroke_color","radius","font","font_size","bold","outline","outline_color"]:
			if values.has(key): layer.properties[key]=values[key]
		layer.effects.assign(style.get("effects",[]).duplicate(true)); layer.opacity=float(style.get("opacity",layer.opacity)); layer.blend=int(style.get("blend",layer.blend))


func _effect_fields(fields: Node,effect: Dictionary) -> void:
	if effect.get("type","")=="emboss": _check(fields,"Preserve color",bool(effect.get("preserve_color",false)),func(value: bool): effect.preserve_color=value)
	var extra:={"emboss":Vector2(0,4),"edge_detect":Vector2(0,4),"motion_blur":Vector2(0,64),"radial_blur":Vector2(0,32),"kaleidoscope":Vector2(2,16),"ripple":Vector2(0,40),"scanlines":Vector2(0,1)}
	if extra.has(effect.type):
		var limits: Vector2=extra[effect.type]
		_slider(fields,"Amount",float(effect.get("amount",1)),limits.x,limits.y,func(value: float): effect.amount=value)
	if effect.type in ["motion_blur","kaleidoscope"]: _slider(fields,"Angle",float(effect.get("angle",0)),-180,180,func(value: float): effect.angle=value)
	if effect.type in ["ripple","scanlines"]: _slider(fields,"Frequency" if effect.type=="ripple" else "Line spacing",float(effect.get("spacing",12)),1,64,func(value: float): effect.spacing=value)
	var ranges:={"brightness":Vector2(-1,1),"contrast":Vector2(0,3),"saturation":Vector2(0,3),"blur":Vector2(0,24),"sharpen":Vector2(0,2),"outline":Vector2(0,24),"shadow":Vector2(0,24),"glow":Vector2(0,32),"wave":Vector2(0,40),"twirl":Vector2(-12,12),"chromatic":Vector2(0,32),"grain":Vector2(0,1),"pixelate":Vector2(1,128),"halftone":Vector2(2,64),"posterize":Vector2(2,32),"vignette":Vector2(0,2),"color_replace":Vector2(.001,1)}
	if ranges.has(effect.type):
		var limits: Vector2=ranges[effect.type]; _slider(fields,"Amount",float(effect.get("amount",1)),limits.x,limits.y,func(value: float): effect.amount=value)
	if effect.type in ["outline","shadow","glow","gradient_map","color_replace"]: _color(fields,"Start / target",effect.get("color",Color.BLACK),func(value: Color): effect.color=value)
	if effect.type in ["gradient_map","color_replace"]: _color(fields,"End / replacement",effect.get("color2",Color.WHITE),func(value: Color): effect.color2=value)
	if effect.type=="shadow":
		_number(fields,"Offset X",effect.offset.x,func(value: float): effect.offset.x=value,-128,128)
		_number(fields,"Offset Y",effect.offset.y,func(value: float): effect.offset.y=value,-128,128)
	if effect.type=="mirror": _mirror_fields(fields,effect)
	if effect.type=="shader" and effect.get("shader") is Shader: _shader_fields(fields,effect)
	if effect.type=="curves":
		_curve_effect_fields(fields,effect)

func _curve_effect_fields(fields: Node,effect: Dictionary) -> void:
	var channel:=OptionButton.new(); channel.name="CurveChannel"
	for caption in ["Overall RGB","Red","Green","Blue","Alpha"]: channel.add_item(caption)
	fields.add_child(channel)
	var keys: Array[String]=["master","red","green","blue","alpha"]
	var graph:=ActorValueCurve.new(); graph.editable=true; graph.custom_minimum_size.y=150; fields.add_child(graph)
	var update:=func():
		var key:=keys[channel.selected]
		graph.curve=effect.get("curve",ActorValueCurve.preset("Linear")) if key=="master" else effect.get("curves",{}).get(key,ActorValueCurve.preset("Linear"))
		graph.queue_redraw()
	channel.item_selected.connect(func(_index: int): update.call()); update.call()
	graph.edit_started.connect(_begin)
	graph.preview_changed.connect(func(curve: Curve):
		if channel.selected==0: effect.curve=curve
		else:
			if not effect.has("curves"): effect.curves={}
			effect.curves[keys[channel.selected]]=curve
		_preview())
	graph.edit_committed.connect(_commit); graph.edit_cancelled.connect(_cancel)
	_button(fields,"Reset channel",func():
		_action(func():
			if channel.selected==0: effect.curve=ActorValueCurve.preset("Linear")
			elif effect.has("curves"): effect.curves.erase(keys[channel.selected]))
		update.call(),"Reset the selected curve","reset")


func _asset_shelf() -> void:
	var ui:=_workflow_window("Assets & reusable items",Vector2(720,500)); var body: VBoxContainer=ui.body
	var actions:=HFlowContainer.new(); body.add_child(actions)
	_button(actions,"Import image…",_choose_import); _button(actions,"Add text",func(): add_layer("text")); _button(actions,"Add shape",func(): add_layer("shape")); _button(actions,"Add empty layer",func(): add_layer("basic"))
	var scroll:=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; body.add_child(scroll)
	var shelf:=VBoxContainer.new(); shelf.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(shelf)
	var recent:=_panel_card(shelf,"Recent project assets","Click to place an asset in the center of the current canvas.")
	if _recent_assets.is_empty():
		var empty:=Label.new(); empty.text="Imported project images appear here automatically."; recent.add_child(empty)
	for asset in _recent_assets:
		var file: String=asset
		_button(recent,file.get_file(),func(): _import_paths(PackedStringArray([file]),Vector2(document.canvas_size)*.5),file,"image")
	var styles:=_panel_card(shelf,"Saved styles")
	for name: String in _presets:
		var style_name:=name; _button(styles,name,func(): _style_clipboard=_presets[style_name].duplicate(true); paste_style())
	var selections:=_panel_card(shelf,"Saved selections")
	for name: String in document.selections:
		var selection_name:=name; _button(selections,name,func():
			canvas.selection=(document.selections[selection_name] as Texture2D).get_image().duplicate(); canvas._update_selection_preview())
	(ui.popup as PopupPanel).popup_centered()


func _remember_asset(file: String) -> void:
	_recent_assets.erase(file); _recent_assets.push_front(file)
	if _recent_assets.size()>16: _recent_assets.pop_back()


func _variants_panel() -> void:
	var ui:=_workflow_window("Variants & snapshots",Vector2(650,460)); var body: VBoxContainer=ui.body
	var intro:=Label.new(); intro.text="Save named alternatives instantly, then switch or compare without duplicating files."; intro.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; body.add_child(intro)
	var actions:=HFlowContainer.new(); body.add_child(actions)
	_button(actions,"＋ Capture current",func(): _capture_variant(); (ui.popup as PopupPanel).queue_free())
	if not _variants.is_empty(): _button(actions,"Compare current / variant…",_compare_variant)
	var scroll:=ScrollContainer.new(); scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL; body.add_child(scroll)
	var list:=VBoxContainer.new(); list.size_flags_horizontal=Control.SIZE_EXPAND_FILL; scroll.add_child(list)
	for name: String in _variants:
		var variant_name:=name; var row:=HBoxContainer.new(); list.add_child(row)
		var label:=Label.new(); label.text=variant_name; label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; row.add_child(label)
		_button(row,"Restore",func(): _restore_variant(variant_name))
		_button(row,"×",func(): _variants.erase(variant_name); (ui.popup as PopupPanel).queue_free(); _variants_panel())
	(ui.popup as PopupPanel).popup_centered()


func _capture_variant() -> void:
	var dialog:=ConfirmationDialog.new(); dialog.title="Capture variant"; add_child(dialog)
	var input:=LineEdit.new(); input.text="Variant %d" % (_variants.size()+1); input.custom_minimum_size.x=320; dialog.add_child(input)
	dialog.confirmed.connect(func():
		var name:=input.text.strip_edges()
		if not name.is_empty():
			var variant:=document.snapshot(); variant.workspace_state={}
			var preview_image:=renderer.texture().get_image()
			if preview_image!=null and not preview_image.is_empty(): preview_image.resize(320,maxi(1,roundi(320.0*preview_image.get_height()/preview_image.get_width())),Image.INTERPOLATE_BILINEAR); variant.preview=ImageTexture.create_from_image(preview_image)
			_variants[name]=variant; status.text="Captured "+name
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(); input.grab_focus(); input.select_all()


func _restore_variant(name: String) -> void:
	if not _variants.get(name) is KiwiImageDocument: return
	_undo.append(document.snapshot()); document=(_variants[name] as KiwiImageDocument).snapshot(); canvas.document=document; _restored(); status.text="Restored variant · "+name


func _compare_variant() -> void:
	var popup:=PopupPanel.new(); add_child(popup); popup.add_theme_stylebox_override("panel",_box(Color("111c28"),Color("426879"),10,10))
	var column:=VBoxContainer.new(); column.custom_minimum_size=Vector2(900,560); popup.add_child(column)
	var select:=OptionButton.new(); for name in _variants: select.add_item(name); column.add_child(select)
	var split:=HSplitContainer.new(); split.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(split)
	var current_view:=TextureRect.new(); current_view.texture=renderer.texture(); current_view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; current_view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; split.add_child(current_view)
	var variant_view:=TextureRect.new(); variant_view.expand_mode=TextureRect.EXPAND_IGNORE_SIZE; variant_view.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED; split.add_child(variant_view)
	var update:=func(index: int):
		var names:=_variants.keys(); if index<0 or index>=names.size(): return
		var preview: Texture2D=(_variants[names[index]] as KiwiImageDocument).preview; variant_view.texture=preview
	select.item_selected.connect(update); update.call(0); popup.popup_hide.connect(popup.queue_free); popup.popup_centered()


func _automation_panel() -> void:
	var ui:=_workflow_window("Macros & batch actions",Vector2(700,480)); var body: VBoxContainer=ui.body
	var recording:=_panel_card(body,"Command macro","Record actions launched from the command palette, then replay them in one click.")
	var row:=HFlowContainer.new(); recording.add_child(row)
	_button(row,"Stop & save…" if _macro_recording else "● Start recording",_stop_macro if _macro_recording else _start_macro)
	_button(row,"Customize hotkeys…",_customize_shortcuts)
	if _macro_recording:
		var state:=Label.new(); state.text="Recording %d command(s)" % _macro_buffer.size(); state.add_theme_color_override("font_color",Color("ff9f7b")); recording.add_child(state)
	var list:=_panel_card(body,"Saved macros")
	for name: String in _macros:
		var macro_name:=name; var macro_row:=HBoxContainer.new(); list.add_child(macro_row)
		var label:=Label.new(); label.text=name+"  ·  %d actions" % (_macros[name] as Array).size(); label.size_flags_horizontal=Control.SIZE_EXPAND_FILL; macro_row.add_child(label)
		_button(macro_row,"Run",func(): _run_macro(macro_name))
		_button(macro_row,"×",func(): _macros.erase(macro_name); (ui.popup as PopupPanel).queue_free(); _automation_panel())
	var batch:=_panel_card(body,"Batch shortcuts","Fast operations for every selected or top-level layer.")
	var batch_buttons:=HFlowContainer.new(); batch.add_child(batch_buttons)
	_button(batch_buttons,"Export top-level layers…",_export_layers)
	_button(batch_buttons,"Rasterize selected",rasterize_selected)
	_button(batch_buttons,"Duplicate selected",duplicate_layers)
	(ui.popup as PopupPanel).popup_centered()


func _start_macro() -> void:
	_macro_buffer.clear(); _macro_recording=true; status.text="Macro recording started · use Ctrl+K to run actions"


func _stop_macro() -> void:
	if not _macro_recording: return
	_macro_recording=false
	var dialog:=ConfirmationDialog.new(); dialog.title="Save macro"; add_child(dialog)
	var input:=LineEdit.new(); input.text="Macro %d" % (_macros.size()+1); input.custom_minimum_size.x=320; dialog.add_child(input)
	dialog.confirmed.connect(func(): if not input.text.strip_edges().is_empty(): _macros[input.text.strip_edges()]=_macro_buffer.duplicate(); dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(); input.grab_focus(); input.select_all()


func _run_macro(name: String) -> void:
	var was_recording:=_macro_recording; _macro_recording=false
	for command_name in _macros.get(name,[]): _run_named_command(command_name)
	_macro_recording=was_recording; status.text="Ran macro · "+name


func _shortcut_string(event: InputEventKey) -> String:
	var parts:=PackedStringArray()
	if event.ctrl_pressed: parts.append("Ctrl")
	if event.alt_pressed: parts.append("Alt")
	if event.shift_pressed: parts.append("Shift")
	if event.meta_pressed: parts.append("Meta")
	parts.append(OS.get_keycode_string(event.keycode))
	return "+".join(parts)


func _customize_shortcuts() -> void:
	var dialog:=ConfirmationDialog.new(); dialog.title="Custom command hotkey"; add_child(dialog)
	var column:=VBoxContainer.new(); column.custom_minimum_size=Vector2(470,180); column.add_theme_constant_override("separation",8); dialog.add_child(column)
	var command:=OptionButton.new(); for item in _commands: command.add_item(str(item.name)); column.add_child(command)
	var capture:=LineEdit.new(); capture.placeholder_text="Click here, then press the shortcut"; capture.editable=false; column.add_child(capture)
	var chosen:={"value":""}
	capture.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed:
			chosen.value=_shortcut_string(event); capture.text=chosen.value; capture.accept_event())
	var clear:=CheckButton.new(); clear.text="Remove the custom shortcut for this command"; column.add_child(clear)
	dialog.confirmed.connect(func():
		var name:=str(_commands[command.selected].name)
		if clear.button_pressed: _custom_shortcuts.erase(name)
		elif not chosen.value.is_empty(): _custom_shortcuts[name]=chosen.value
		status.text="Shortcut updated"; dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(); capture.grab_focus()


func _export_presets_panel() -> void:
	var ui:=_workflow_window("Quick export presets",Vector2(650,430)); var body: VBoxContainer=ui.body
	var presets:=_panel_card(body,"Image sizes","Uses the current output folder and adds a size suffix. If no output exists, choose a destination once.")
	var buttons:=HFlowContainer.new(); presets.add_child(buttons)
	_button(buttons,"Original PNG",func(): _quick_export(Vector2i(document.canvas_size),"original","png"))
	_button(buttons,"2× PNG",func(): _quick_export(document.canvas_size*2,"2x","png"))
	_button(buttons,"½ PNG",func(): _quick_export(Vector2i(Vector2(document.canvas_size)*.5),"half","png"))
	_button(buttons,"Thumbnail 512",func(): _quick_export(Vector2i(512,roundi(512.0*document.canvas_size.y/document.canvas_size.x)),"thumb","webp"))
	_button(buttons,"Square 1080",func(): _quick_export(Vector2i(1080,1080),"square","png"))
	_button(buttons,"Story 1080×1920",func(): _quick_export(Vector2i(1080,1920),"story","jpg"))
	var special:=_panel_card(body,"Layer exports")
	var special_buttons:=HFlowContainer.new(); special.add_child(special_buttons)
	_button(special_buttons,"Export selected layer…",_export_selected_layer)
	_button(special_buttons,"Export every top-level layer…",_export_layers)
	_button(special_buttons,"Custom export…",export_image)
	(ui.popup as PopupPanel).popup_centered()


func _quick_export(size: Vector2i,suffix: String,format: String) -> void:
	var destination:=document.output_path
	if destination.is_empty():
		var result:=await ActorProjectResourceSaveDialog.pick(self,"Quick export · "+suffix,"Image-"+suffix,format,false,PackedStringArray(SAVE_FORMATS))
		if result.get("cancelled",true): return
		destination=str(result.path)
	var bitmap:=await renderer.flattened()
	if bitmap==null: return
	bitmap=bitmap.duplicate(); bitmap.resize(maxi(1,size.x),maxi(1,size.y),Image.INTERPOLATE_LANCZOS)
	var output:=destination if document.output_path.is_empty() else destination.get_basename()+"-"+suffix+"."+format
	var error:=_write_bitmap(bitmap,output); status.text="Exported "+output.get_file() if error==OK else "Export failed"
	if error==OK and LocalProjectFilesystem.node!=null: LocalProjectFilesystem.update_root_folder()


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
		if bitmap!=null: _write_bitmap(bitmap,base.path_join(layer.label.validate_filename()+".png"))
	status.text="Exported top-level layers"


func _layer_polygon(layer: KiwiImageLayer) -> PackedVector2Array:
	var points:=PackedVector2Array()
	if layer.kind not in ["shape","path"]: return points
	var shape:=str(layer.properties.get("shape","custom" if layer.kind=="path" else "rectangle"))
	if shape=="ellipse":
		for index in 64: points.append(layer.dimensions*.5+Vector2.from_angle(TAU*index/64.0)*layer.dimensions*.5)
	elif shape=="triangle": points=PackedVector2Array([Vector2(layer.dimensions.x*.5,0),layer.dimensions,Vector2(0,layer.dimensions.y)])
	elif shape=="custom" or layer.kind=="path":
		points=layer.properties.get("points",PackedVector2Array()).duplicate()
		var source: Vector2=layer.properties.get("path_size",layer.dimensions)
		for index in points.size(): points[index]*=layer.dimensions/source.max(Vector2.ONE)
	else: points=PackedVector2Array([Vector2.ZERO,Vector2(layer.dimensions.x,0),layer.dimensions,Vector2(0,layer.dimensions.y)])
	var world:=document.world_transform(layer)
	for index in points.size(): points[index]=world*points[index]
	return points


func _boolean_shapes(operation: String) -> void:
	var layers: Array[KiwiImageLayer]=[]
	for id in canvas.selected:
		var layer:=document.layer_for_id(id)
		if layer!=null and layer.kind in ["shape","path"]: layers.append(layer)
	if layers.size()<2: status.text="Select at least two shape/path layers."; return
	var polygons: Array[PackedVector2Array]=[_layer_polygon(layers[0])]
	for index in range(1,layers.size()):
		var next:=_layer_polygon(layers[index]); var combined: Array[PackedVector2Array]=[]
		for polygon in polygons:
			var pieces: Array[PackedVector2Array]
			match operation:
				"union": pieces=Geometry2D.merge_polygons(polygon,next)
				"intersect": pieces=Geometry2D.intersect_polygons(polygon,next)
				_: pieces=Geometry2D.clip_polygons(polygon,next)
			combined.append_array(pieces)
		polygons=combined
	if polygons.is_empty(): status.text="The boolean operation produced an empty shape."; return
	var created: Array[KiwiImageLayer]=[]
	for polygon in polygons:
		if polygon.size()<3: continue
		var bounds:=Rect2(polygon[0],Vector2.ZERO); for point in polygon: bounds=bounds.expand(point)
		var result:=Layer.create("path",document.canvas_size); result.label=operation.capitalize()+" shape"; result.position=bounds.position; result.dimensions=bounds.size.max(Vector2.ONE)
		var local:=PackedVector2Array(); for point in polygon: local.append(point-bounds.position)
		result.properties.points=local; result.properties.path_size=result.dimensions; result.properties.color=layers[-1].properties.get("color",Color.WHITE); created.append(result)
	_action(func():
		for layer in layers: document.layers.erase(layer)
		canvas.selected.clear(); for layer in created: document.layers.append(layer); canvas.selected.append(layer.id))
	status.text="Created "+operation+" vector result"


func _register_commands() -> void:
	_commands=[
		{"name":"Add image from project","category":"Create","run":_choose_import},{"name":"Add text layer","category":"Create","run":func(): add_layer("text")},
		{"name":"Add shape layer","category":"Create","run":func(): add_layer("shape")},{"name":"Add basic / empty layer","category":"Create","run":func(): add_layer("basic")},
		{"name":"Parent selected layers","category":"Layer","shortcut":"Ctrl+G","run":parent_selected},{"name":"Unparent selected layers","category":"Layer","shortcut":"Ctrl+Shift+G","run":unparent_selected},
		{"name":"Duplicate layers","category":"Layer","shortcut":"Ctrl+D","run":duplicate_layers},{"name":"Delete layers","category":"Layer","shortcut":"Backspace","run":delete_selected},
		{"name":"Merge selected layers","category":"Layer","run":merge_selected},{"name":"Rasterize for painting","category":"Layer","run":rasterize_selected},
		{"name":"Selection to mask","category":"Mask","run":selection_to_mask},{"name":"Copy selection to layer","category":"Selection","run":selection_to_layer},
		{"name":"Select subject","category":"Selection","run":func(): _smart_select("opaque")},{"name":"Select background","category":"Selection","run":func(): _smart_select("transparent")},
		{"name":"Grow selection","category":"Selection","run":func(): _modify_selection("grow",2)},{"name":"Feather selection","category":"Selection","run":func(): _modify_selection("feather",3)},
		{"name":"Clear pixel selection","category":"Selection","run":canvas.clear_selection},{"name":"Canvas size","category":"Image","run":_canvas_size_dialog},
		{"name":"Transform and align","category":"Workflow","run":_transform_panel},{"name":"Effects and styles","category":"Workflow","run":_effects_panel},
		{"name":"Asset shelf","category":"Workflow","run":_asset_shelf},{"name":"Variants","category":"Workflow","run":_variants_panel},{"name":"Macros","category":"Workflow","run":_automation_panel},
		{"name":"Save document","category":"File","shortcut":"Ctrl+S","run":save},{"name":"Save As","category":"File","shortcut":"Ctrl+Shift+S","run":save_as},{"name":"Export flattened image","category":"File","run":export_image},
		{"name":"Quick export presets","category":"File","run":_export_presets_panel},{"name":"Copy style","category":"Style","run":copy_style},{"name":"Paste style","category":"Style","run":paste_style},
		{"name":"Vector union","category":"Vector","run":func(): _boolean_shapes("union")},{"name":"Vector subtract","category":"Vector","run":func(): _boolean_shapes("subtract")},{"name":"Vector intersect","category":"Vector","run":func(): _boolean_shapes("intersect")},
		{"name":"Fit canvas","category":"View","shortcut":"F","run":canvas.fit},{"name":"Load canvas shader effect","category":"Effect","run":_choose_shader_effect}]
	for mode in ["left","center_x","right","top","center_y","bottom"]:
		var align_mode: String=mode; _commands.append({"name":"Align "+mode.replace("_"," "),"category":"Transform","run":func(): align_selected(align_mode)})
	for kind in AVAILABLE_EFFECTS:
		var id: String=kind
		_commands.append({"name":"Add "+id.replace("_"," ")+" effect","category":"Effect","run":func(): add_effect(id)})
	for key in tool_buttons:
		var id: String=key
		_commands.append({"name":"Tool: "+id.replace("_"," ").capitalize(),"category":"Tool","run":func(): _set_tool(id)})


func _execute_command(command: Dictionary) -> void:
	var name:=str(command.name); _last_command_name=name
	_recent_commands.erase(name); _recent_commands.push_front(name)
	if _recent_commands.size()>12: _recent_commands.pop_back()
	if _macro_recording: _macro_buffer.append(name)
	(command.run as Callable).call()


func _run_named_command(name: String) -> void:
	for command in _commands:
		if command.name==name: _execute_command(command); return


func _repeat_last_command() -> void:
	if _last_command_name.is_empty(): status.text="Run a command first."; return
	_run_named_command(_last_command_name)


func _command_palette() -> void:
	var popup:=PopupPanel.new(); popup.add_theme_stylebox_override("panel",_box(Color("14212e"),Color("4e887b"),12,14)); add_child(popup)
	var column:=VBoxContainer.new(); column.custom_minimum_size=Vector2(450,380); popup.add_child(column)
	var search:=LineEdit.new(); search.placeholder_text="What would you like to do?"; column.add_child(search)
	var results:=ItemList.new(); results.size_flags_vertical=Control.SIZE_EXPAND_FILL; column.add_child(results)
	var matches: Array[Dictionary]=[]
	var populate:=func(query: String):
		results.clear(); matches.clear()
		var ordered:=_commands.duplicate()
		ordered.sort_custom(func(a: Dictionary,b: Dictionary):
			var ai:=_recent_commands.find(str(a.name)); var bi:=_recent_commands.find(str(b.name))
			return (ai if ai>=0 else 100)<(bi if bi>=0 else 100))
		for command in ordered:
			var shortcut:=str(_custom_shortcuts.get(command.name,command.get("shortcut","")))
			var searchable:=str(command.name)+" "+str(command.get("category",""))+" "+shortcut
			if query.is_empty() or searchable.to_lower().contains(query.to_lower()):
				matches.append(command); results.add_item("%s  ·  %s%s" % [command.name,command.get("category","Action"),("  ·  "+shortcut if not shortcut.is_empty() else "")])
		for layer in document.layers:
			if not query.is_empty() and (layer.label.to_lower().contains(query.to_lower()) or query.to_lower().begins_with("layer")):
				var target_id:=layer.id
				matches.append({"name":"Select layer: "+layer.label,"category":"Layer","run":func(): canvas.selected.assign([target_id]); _selection_changed()})
				results.add_item("Select layer  ·  "+layer.label)
		if results.item_count>0: results.select(0)
	var activate:=func(index: int):
		if index>=0 and index<matches.size():
			var command: Dictionary=matches[index]; popup.hide(); _execute_command(command)
	search.gui_input.connect(func(event: InputEvent):
		if event is InputEventKey and event.pressed and event.keycode in [KEY_UP,KEY_DOWN] and results.item_count>0:
			var selected:=results.get_selected_items()
			var index:=selected[0] if not selected.is_empty() else 0
			results.select(clampi(index+(-1 if event.keycode==KEY_UP else 1),0,results.item_count-1))
			search.accept_event())
	search.text_changed.connect(populate); search.text_submitted.connect(func(_text: String): activate.call(results.get_selected_items()[0] if not results.get_selected_items().is_empty() else 0))
	results.item_activated.connect(activate); populate.call("")
	popup.popup_hide.connect(popup.queue_free); popup.popup_centered(Vector2i(490,430)); search.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo: return
	var focus:=get_viewport().gui_get_focus_owner()
	if focus!=null and focus!=self and not is_ancestor_of(focus): return
	if focus is LineEdit or focus is TextEdit: return
	var pressed_shortcut:=_shortcut_string(event)
	for command_name in _custom_shortcuts:
		if str(_custom_shortcuts[command_name])==pressed_shortcut:
			_run_named_command(command_name); get_viewport().set_input_as_handled(); return
	if not event.ctrl_pressed and not event.alt_pressed and canvas.tool in ["brush","eraser","fill"]:
		var index:=int(event.keycode)-KEY_0
		if index>=0 and index<10 and index<(_paint_presets[canvas.tool] as Array).size():
			canvas.cancel_gesture(); _apply_paint_preset(canvas.tool,_paint_presets[canvas.tool][index]); get_viewport().set_input_as_handled(); return
	if event.ctrl_pressed:
		match event.keycode:
			KEY_S:
				if event.shift_pressed: save_as()
				else: save()
			KEY_Z:
				if event.shift_pressed: redo()
				else: undo()
			KEY_Y: redo()
			KEY_D: duplicate_layers()
			KEY_I: _select_pixel_region(true)
			KEY_C: copy_layers()
			KEY_V: paste_layers()
			KEY_G:
				if event.shift_pressed: unparent_selected()
				else: parent_selected()
			KEY_A:
				if event.shift_pressed: canvas.clear_selection()
				else: select_all()
			KEY_K: _command_palette()
			KEY_R:
				if event.shift_pressed: _repeat_last_command()
				else: return
			KEY_BRACKETRIGHT: reorder_selected(1)
			KEY_BRACKETLEFT: reorder_selected(-1)
			_: return
	else:
		match event.keycode:
			KEY_DELETE,KEY_BACKSPACE:
				if canvas.tool=="pixel_select": _apply_pixel_selection("delete")
				else: delete_selected()
			KEY_ESCAPE: canvas.cancel_gesture()
			KEY_ENTER:
				if canvas._drag=="object_preview": canvas.commit_object_selection(); get_viewport().set_input_as_handled(); return
				if canvas.tool=="path": canvas.finish_path()
				else: canvas.confirm_stroke()
			KEY_F: canvas.fit()
			KEY_V: _set_tool("move")
			KEY_B: _set_tool("brush")
			KEY_E: _set_tool("eraser")
			KEY_G: _set_tool("fill")
			KEY_L: _set_tool("lasso_crop")
			KEY_C: _set_tool("crop")
			KEY_M: _set_tool("pixel_select")
			KEY_W: _set_tool("warp")
			KEY_BRACKETLEFT: canvas.brush_size=maxf(1,canvas.brush_size-4); _refresh_context()
			KEY_BRACKETRIGHT: canvas.brush_size=minf(500,canvas.brush_size+4); _refresh_context()
			_: return
	get_viewport().set_input_as_handled()
