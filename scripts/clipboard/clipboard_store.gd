class_name KiwiClipboardStore
extends RefCounted
signal changed
var root: String
var data: Dictionary
var error:=""
var read_only:=false
var history:=UndoRedo.new()
const VERSION:=1
func _init(location: String="user://super_clipboard") -> void:
	_native_store().initialize(self,location)

func _read(path: String) -> Dictionary:
	return _native_store().read(self,path)

func _valid_index(value: Dictionary) -> bool:
	return _native_store().valid_index(self,value)

func _write(value: Dictionary) -> bool:
	return _native_store().write(self,value)

func _assign(value: Dictionary) -> void:
	_native_store().assign(self,value)

func commit(title: String,next: Dictionary) -> bool:
	return _native_store().commit(self,title,next)

func folder_valid(id: String) -> bool:
	return _native_store().folder_valid(self,id)

func unique_name(name: String,folder: String,skip: String="") -> String:
	return _native_store().unique_name(self,name,folder,skip)

func _unique_in(next: Dictionary,name: String,folder: String,skip: String) -> String:
	return _native_store().unique_in(self,next,name,folder,skip)

func _name_exists(name: String,folder: String,skip: String) -> bool:
	return _native_store().name_exists(self,name,folder,skip)

func save(value: Variant,name: String="Resource",folder: String="default") -> String:
	return _native_store().save(self,value,name,folder)

func entry_path(id: String,include_deleted: bool=false) -> String:
	return _native_store().entry_path(self,id,include_deleted)

func materialize(id: String,project_root: String) -> String:
	return _native_store().materialize(self,id,project_root)

func create_folder(name: String,parent: String="default") -> String:
	return _native_store().create_folder(self,name,parent)

func rename(id: String,name: String) -> bool:
	return _native_store().rename(self,id,name)

func move(ids: PackedStringArray,folder: String,duplicate: bool=false) -> bool:
	return _native_store().move(self,ids,folder,duplicate)

func _duplicate_folder(next: Dictionary,id: String,parent: String) -> void:
	_native_store().duplicate_folder(self,next,id,parent)

func delete(ids: PackedStringArray,restore: bool=false) -> bool:
	return _native_store().delete(self,ids,restore)

func _delete_children(next: Dictionary,id: String,deleted: bool,visited: Dictionary) -> void:
	_native_store().delete_children(next,id,deleted,visited)

func set_default(id: String) -> bool:
	return _native_store().set_default(self,id)

func save_ui(state: Dictionary) -> void:
	_native_store().save_ui(self,state)

func close() -> void:
	_native_store().close(self)

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE and is_instance_valid(history): history.free()
func icon(id: String) -> Texture2D:
	return _native_store().icon(self,id)


static func _native_store() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("clipboard_store")
