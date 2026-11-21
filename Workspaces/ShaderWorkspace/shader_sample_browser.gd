extends HSplitContainer
## Shared Samples/Templates page embedded alongside the existing documentation.
## Two viewports total: the selected live material and a serial thumbnail worker.
signal open_requested(entry: Dictionary)
const Catalog = preload("res://Workspaces/ShaderWorkspace/library/shader_sample_catalog.gd")
const Preview = preload("res://Workspaces/ShaderWorkspace/ShaderSamplePreview.cs")
const Application = preload("res://Workspaces/ShaderWorkspace/shader_sample_application.gd")
const PREFS := "user://shader_library.cfg"
const CACHE := "user://shader_library_previews/"
const CACHE_VERSION := "6"
var templates_only := false
var preferences_path := PREFS
var entries: Array[Dictionary] = []
var favorites := PackedStringArray()
var recent := PackedStringArray()
var selected: Dictionary = {}
var search := LineEdit.new()
var type_filter := OptionButton.new()
var category_filter := OptionButton.new()
var collection_filter := OptionButton.new()
var grid := GridContainer.new()
var card_scroll := ScrollContainer.new()
var count := Label.new()
var heading := Label.new()
var description := Label.new()
var source := CodeEdit.new()
var preview_display := TextureRect.new()
var preview_error := Label.new()
var uniforms := VBoxContainer.new()
var geometry := OptionButton.new()
var favorite: Button
var apply: Button
var status := Label.new()
var live: SubViewport
var thumbnail: SubViewport
var _cards: Dictionary = {}
var _textures: Dictionary = {}
var _failures: Dictionary = {}
var _thumbnail_busy := false
var _selection_revision := 0
var _selection_busy := false
var _apply_timer := 0.0

func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service","shader_browser")
static func _operations() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service","shader_browser")
func _ready() -> void: _native().call("ready",self)
func _draw() -> void: _native().call("draw",self)
func _box(background: Color,border: Color) -> StyleBoxFlat: return _native().call("box",background,border)
func _build_sidebar() -> void: _native().call("build_sidebar",self)
func _build_content() -> void: _native().call("build_content",self)
static func matches(entry: Dictionary,query: String,kind: String,category: String,templates: bool,collection: int,favorite_ids: PackedStringArray,recent_ids: PackedStringArray) -> bool: return _operations().call("matches",entry,query,kind,category,templates,collection,favorite_ids,recent_ids)
func refresh() -> void: _native().call("refresh",self)
func _add_card(entry: Dictionary) -> void: _native().call("add_card",self,entry)
func set_templates(value: bool) -> void: _native().call("set_templates",self,value)
func _select(entry: Dictionary) -> void: _native().call("select",self,entry)
func _build_uniforms() -> void: _native().call("build_uniforms",self)
func _process(delta: float) -> void: _native().call("process",self,delta)
func _render_thumbnail(entry: Dictionary) -> void: _native().call("render_thumbnail",self,entry)
func _cache_key(entry: Dictionary) -> String: return _native().call("cache_key",entry)
func _visibility_changed() -> void: _native().call("visibility_changed",self)
func _preview_input(event: InputEvent) -> void: _native().call("preview_input",self,event)
func _copy() -> void: _native().call("copy",self)
func _open() -> void: _native().call("open",self)
func _save_file() -> void: _native().call("save_file",self)
static func write_shader_copy(path: String,code: String) -> Error: return _operations().call("write_shader_copy",path,code)
func _refresh_apply() -> void: _native().call("refresh_apply",self)
func _apply() -> void: _native().call("apply",self)
func _commit_apply(target: Dictionary,entry: Dictionary) -> void: _native().call("commit_apply",self,target,entry)
func _toggle_favorite() -> void: _native().call("toggle_favorite",self)
func _mark_used() -> void: _native().call("mark_used",self)
func _load_preferences() -> void: _native().call("load_preferences",self)
func _save_preferences() -> void: _native().call("save_preferences",self)
func _button(label: String,action: Callable) -> Button:
	var button:=Button.new(); button.text=label; button.pressed.connect(action); return button
