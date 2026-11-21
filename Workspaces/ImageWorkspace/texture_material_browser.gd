extends PanelContainer
## Shared nonmodal editor: the same independent material instance is used in both workspaces.
signal material_changed(value: KiwiTextureMaterial)
signal edit_committed
const Library=preload("res://scripts/materials/NaturalMaterialCatalog.cs")
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

static func _native() -> Object:
 return Engine.get_singleton("KiwiNativeServices").service("image_material_browser")

static func open(workspace: KiwiImageWorkspace) -> void:
 _native().open(workspace)

static func open_for_material(host: Node,material: KiwiTextureMaterial,changed_callback: Callable) -> PanelContainer:
 return _native().open_for_material(host,material,changed_callback)

func _ready() -> void:
 _native().ready(self)

func _button(parent: Node,caption: String,callback: Callable) -> Button:
 return _native().button(self,parent,caption,callback)

func set_material_value(next: KiwiTextureMaterial) -> void:
 _native().set_material_value(self,next)

func refresh_from_layer() -> void:
 _native().refresh_from_layer(self)

func changed() -> void:
 _native().changed(self)

func update_preview() -> void:
 _native().update_preview(self)

func reload_shared_presets() -> void:
 _native().reload_shared_presets(self)

func refresh_grid() -> void:
 var state: Dictionary=_native().prepare_grid(self)
 if state.is_empty(): return
 for job: Dictionary in state.jobs:
  while _thumbnail_busy:
   await get_tree().process_frame
   if _closed or state.request!=_filter_generation: return
  _thumbnail_busy=true
  var bitmap: Image=await Render.preview(self,job.sample,Vector2i(88,64))
  _thumbnail_busy=false
  if not _native().complete_thumbnail(self,state.request,job,bitmap): return

func rebuild_fields() -> void:
 _native().rebuild_fields(self)

func _choice(parent: Node,caption: String,captions: Array,ids: Array,current: String,callback: Callable) -> void:
 _native().choice(self,parent,caption,captions,ids,current,callback)

func _number(parent: Node,caption: String,current: float,minimum: float,maximum: float,step: float,callback: Callable) -> void:
 _native().number(self,parent,caption,current,minimum,maximum,step,callback)

func _load_history() -> void:
 _native().load_history(self)

func _save_history() -> void:
 _native().save_history(self)

func save_material(as_new: bool=false) -> void:
 _native().save_material(self,as_new)

func load_material() -> void:
 var property:=ActorProperty.new()
 property.options={"extensions":["tres","res"],"file_picker":true}
 var path:=await ActorProjectFilePicker.pick(self,property,"Import Natural Material preset")
 if path.is_empty() or path==ActorProjectFilePicker.EMPTY_RESOURCE: return
 _native().complete_load(self,path)

func import_image() -> void:
 var property:=ActorProperty.new()
 property.options={"extensions":KiwiImageWorkspace.IMAGE_EXTENSIONS,"file_picker":true}
 var path:=await ActorProjectFilePicker.pick(self,property,"Choose material image")
 if path.is_empty() or path==ActorProjectFilePicker.EMPTY_RESOURCE: return
 _native().complete_image(self,path)

func is_closed() -> bool:
 return _closed

func close() -> void:
 if not _native().begin_close(self): return
 while _thumbnail_busy: await get_tree().process_frame
 queue_free()

func _restore_sidebar() -> void:
 _native().restore_sidebar(self)

func _exit_tree() -> void:
 _native().exit_tree(self)

func preview_input(event: InputEvent) -> void:
 _native().preview_input(self,event)

func _compare(enabled: bool) -> void:
 _native().compare(self,enabled)

func _show_catalog(browse: bool) -> void:
 _native().show_catalog(self,browse)

func _connect_material(callback: Callable) -> void:
 material_changed.connect(callback)

func _invoke_action(callback: Callable) -> void:
 callback.call()

func _invoke_value(callback: Callable,value: Variant) -> void:
 callback.call(value)
