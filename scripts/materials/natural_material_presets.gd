extends RefCounted
## User-owned presets shared by Image and Scene workspaces. Callers always receive
## a copy; editing a material instance cannot mutate a stored preset implicitly.
const DIRECTORY="user://natural_materials"
const INDEX=DIRECTORY+"/index.cfg"
static var _index: ConfigFile

static func _config() -> ConfigFile:
	if _index==null:
		_index=ConfigFile.new();_index.load(INDEX)
	return _index

static func _write() -> Error:
	var error:=DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if error!=OK: return error
	return _config().save(INDEX)

static func list_presets() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for id in _config().get_sections():
		if id=="preferences": continue
		result.append({"id":id,"name":str(_config().get_value(id,"name",id)),"material_id":str(_config().get_value(id,"material_id","wood/oak"))})
	result.sort_custom(func(a: Dictionary,b: Dictionary): return a.name.naturalnocasecmp_to(b.name)<0)
	return result

static func load_material(id: String) -> KiwiTextureMaterial:
	if not _config().has_section(id): return null
	var path:=DIRECTORY+"/"+id+".tres"
	var material:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiTextureMaterial
	return material.copy_material() if material!=null else null

static func save_material(value: KiwiTextureMaterial,id: String="") -> String:
	if id.is_empty(): id="material_"+str(Time.get_unix_time_from_system()).replace(".","_")+"_"+str(randi())
	if not id.is_valid_filename() or id.contains("/") or id.contains("\\") or id=="preferences": return ""
	if DirAccess.make_dir_recursive_absolute(DIRECTORY)!=OK: return ""
	var copy:=value.copy_material();copy.coverage=null;copy.source=null
	if ResourceSaver.save(copy,DIRECTORY+"/"+id+".tres")!=OK: return ""
	_config().set_value(id,"name",copy.label);_config().set_value(id,"material_id",copy.material_id)
	return id if _write()==OK else ""

static func remove(id: String) -> Error:
	if not _config().has_section(id): return ERR_DOES_NOT_EXIST
	_config().erase_section(id)
	var error:=_write()
	if error!=OK: return error
	return DirAccess.remove_absolute(DIRECTORY+"/"+id+".tres")

static func import_file(path: String) -> String:
	var value:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiTextureMaterial
	return save_material(value) if value!=null else ""

static func export_file(id: String,path: String) -> Error:
	var value:=load_material(id)
	return ResourceSaver.save(value,path) if value!=null else ERR_DOES_NOT_EXIST

static func favorites() -> Array:
	return Array(_config().get_value("preferences","favorites",[]))

static func set_favorite(id: String,enabled: bool) -> void:
	var values:=favorites()
	if enabled and not values.has(id): values.append(id)
	if not enabled: values.erase(id)
	_config().set_value("preferences","favorites",values);_write()

static func recent() -> Array:
	return Array(_config().get_value("preferences","recent",[]))

static func mark_used(id: String) -> void:
	var values:=recent();values.erase(id);values.push_front(id)
	if values.size()>24: values.resize(24)
	_config().set_value("preferences","recent",values);_write()
