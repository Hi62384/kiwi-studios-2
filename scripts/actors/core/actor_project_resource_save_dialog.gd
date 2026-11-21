class_name ActorProjectResourceSaveDialog
extends PopupPanel
## Polished, project-scoped Save As browser for editable actor resources.

signal finished(result: Dictionary)

var project_root: String
var selected_directory: String
var extension: String
var format_picker: OptionButton
var folders: Tree
var files: ItemList
var filename: LineEdit
var breadcrumb: Label
var destination: Label
var status: Label
var save_button: Button
var embedded_toggle: CheckButton
var allow_embedded: bool = true
var _resolved: bool = false
var _file_generation: int = 0
var _thumbnail_cache: Dictionary = {}
var clipboard_value: Variant


static func pick(owner: Node, title_text: String, suggested_name: String,
		file_extension: String = "tres", can_embed: bool = true, formats: PackedStringArray = PackedStringArray(), snapshot: Variant=null) -> Dictionary:
	var dialog := ActorProjectResourceSaveDialog.new()
	dialog.clipboard_value=snapshot
	owner.add_child(dialog)
	dialog._build(title_text, suggested_name, file_extension, can_embed, formats)
	dialog.popup_centered(Vector2i(900, 620))
	dialog.filename.grab_focus()
	dialog.filename.select_all()
	var result: Dictionary = await dialog.finished
	dialog.queue_free()
	return result


func _build(title_text: String, suggested_name: String, file_extension: String,
		can_embed: bool = true, formats: PackedStringArray = PackedStringArray()) -> void:
	_native_save().build(self,title_text,suggested_name,file_extension,can_embed,formats)

func _rebuild_tree() -> void:
	_native_save().rebuild_tree(self)

func _add_tree_entries(parent: TreeItem, directory: String) -> void:
	_native_save().add_tree_entries(self,parent,directory)

func _tree_selected() -> void:
	_native_save().tree_selected(self)

func _tree_activated() -> void:
	_native_save().tree_activated(self)

func _refresh_files() -> void:
	_native_save().refresh_files(self)

func _load_thumbnail(path: String, index: int, generation: int) -> void:
	var thumbnail: Texture2D=_thumbnail_cache.get(path)
	if thumbnail==null:
		thumbnail=await FileOperations.get_file_thumbnail(path)
	_native_save().thumbnail_complete(self,path,index,generation,thumbnail)

func _existing_file_selected(index: int) -> void:
	_native_save().existing_file_selected(self,index)

func _select_existing_path(path: String) -> void:
	_native_save().select_existing_path(self,path)

func _target_path() -> String:
	return _native_save().target_path(self)

func _validate() -> void:
	_native_save().validate(self)

func _save() -> void:
	_native_save().save(self)

func _resolve(result: Variant) -> void:
	_native_save().resolve(self,result)

func _relative_to_project(path: String) -> String:
	return Engine.get_singleton("KiwiNativeServices").service("actor_project_file_picker").relative_to_project(self,path)

func _box(background: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	return _native_save().box(background,border,radius,border_width)

static func _native_save() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","actor_project_save")

func _clipboard_library() -> Object:
	return KiwiSuperClipboardService.instance

func _clipboard_snapshot() -> Variant:
	return clipboard_value.call() if clipboard_value is Callable else clipboard_value
