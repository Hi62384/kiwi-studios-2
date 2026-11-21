class_name ActorProjectFilePicker
extends PopupPanel
## Generic, read-only asset picker constrained to the loaded project directory.

signal finished(path: String)

## Distinct from Cancel (empty string): the caller must clear its resource slot.
const EMPTY_RESOURCE := "::empty-resource::"

var project_root: String
var allowed_extensions: PackedStringArray
var allowed_raw_extensions: PackedStringArray
var allowed_resource_type: StringName
var accepted_object_types: PackedStringArray
var allowed_native_types: PackedStringArray
var current_directory: String
var selected_path: String = ""
var search: LineEdit
var folders: Tree
var files: ItemList
var breadcrumb: Label
var file_count: Label
var selection_name: Label
var selection_path: Label
var selection_preview: TextureRect
var choose_button: Button
var _resolved: bool = false
var _refresh_generation: int = 0
var _tree_generation: int = 0
var _thumbnail_cache: Dictionary = {}
var _thumbnail_jobs: Array[Dictionary]=[]
var _thumbnail_running:=false
var _indexed_paths: Array[String]=[]
var _scan_ready:=false
var _scan_entries:=0
var _path_match_cache: Dictionary={}
var clipboard_source:=false
var clipboard_folder:="default"
var _clipboard_ids: Dictionary={}
var source_project: Button
var source_clipboard: Button


static func pick(owner: Node, property: ActorProperty, title: String = "Choose a project asset",from_clipboard: bool=false) -> String:
	var picker := ActorProjectFilePicker.new()
	owner.add_child(picker)
	picker._build(property, title)
	if from_clipboard: picker._set_clipboard_source(true)
	picker.popup_centered(Vector2i(980, 650))
	picker.search.grab_focus()
	var result: String = await picker.finished
	picker.queue_free()
	return result


static func root_directory() -> String:
	return _native_picker().root_directory()

static func is_allowed_path(root: String, path: String, extensions: PackedStringArray) -> bool:
	return _native_picker().is_allowed_path(root,path,extensions)

func _build(property: ActorProperty, title_text: String) -> void:
	_native_picker().build(self,property,title_text)

func _rebuild_folders() -> void:
	var generation: int=_native_picker().prepare_folders(self)
	if generation<0: return
	var scan: Dictionary=await _scan_directory(project_root,generation)
	_native_picker().complete_folders(self,scan,generation)

func _scan_directory(directory: String,generation: int=-1) -> Dictionary:
	var job: RefCounted=_native_picker().begin_scan(self,directory,generation)
	while not job.step(16):
		await get_tree().process_frame
	return job.result()

func _populate_tree(parent: TreeItem, scan: Dictionary) -> void:
	_native_picker().populate_tree(self,parent,scan)

func _tree_item_selected() -> void:
	_native_picker().tree_item_selected(self)

func _tree_item_activated() -> void:
	_native_picker().tree_item_activated(self)

func _refresh_files() -> void:
	_native_picker().refresh_files(self)

func _collect_files(directory: String, result: Array[String], recursive: bool, query: String = "") -> void:
	_native_picker().collect_files(self,directory,result,recursive,query)

func _load_thumbnail(path: String, index: int, generation: int) -> void:
	_native_picker().load_thumbnail(self,path,index,generation)

func _load_tree_thumbnail(path: String, item: TreeItem, generation: int) -> void:
	_native_picker().load_tree_thumbnail(self,path,item,generation)

func _process(_delta: float) -> void:
	_native_picker().process(self)

func _process_thumbnail(job: Dictionary) -> void:
	var thumbnail: Texture2D=_thumbnail_cache.get(job.path)
	if thumbnail==null:
		thumbnail=await FileOperations.get_file_thumbnail(job.path)
	_native_picker().thumbnail_complete(self,job,thumbnail)

func _file_selected(index: int) -> void:
	_native_picker().file_selected(self,index)

func _select_asset(path: String, preview: Texture2D) -> void:
	_native_picker().select_asset(self,path,preview)

func _relative_to_project(path: String) -> String:
	return _native_picker().relative_to_project(self,path)

func _path_allowed(path: String) -> bool:
	return _native_picker().path_allowed(self,path)

func _path_allowed_uncached(path: String) -> bool:
	return _native_picker().path_allowed_uncached(self,path)

func _godot_resource_path(path: String) -> String:
	return _native_picker().godot_resource_path(path)

func _choose() -> void:
	_native_picker().choose(self)

func _set_clipboard_source(enabled: bool) -> void:
	_native_picker().set_clipboard_source(self,enabled)

func _clipboard_folders(parent: TreeItem,id: String,visited: Dictionary) -> void:
	_native_picker().clipboard_folders(self,parent,id,visited)

func _refresh_clipboard_files() -> void:
	_native_picker().refresh_clipboard_files(self)

func _clipboard_compatible(entry: Dictionary) -> bool:
	return _native_picker().clipboard_compatible(self,entry)

func _choose_default_slot() -> void:
	_native_picker().choose_default_slot(self)

func _resolve(path: String) -> void:
	_native_picker().resolve(self,path)

func _box(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	return _native_picker().box(background,border,radius,border_width)

static func _native_picker() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","actor_project_file_picker")

func _clipboard_library() -> Object:
	return KiwiSuperClipboardService.instance
