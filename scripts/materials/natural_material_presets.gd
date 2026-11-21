extends RefCounted
## User-owned presets shared by Image and Scene workspaces. Callers always receive
## a copy; editing a material instance cannot mutate a stored preset implicitly.
const DIRECTORY="user://natural_materials"
const INDEX=DIRECTORY+"/index.cfg"
static var _index: ConfigFile

static func _native() -> Object:
 return Engine.get_singleton("KiwiNativeServices").service("natural_material_presets")

static func _config() -> ConfigFile:
 return _native().config()

static func _write() -> Error:
 return _native().write()

static func list_presets() -> Array[Dictionary]:
 var result: Array[Dictionary]=[]
 result.assign(_native().list_presets())
 return result

static func load_material(id: String) -> KiwiTextureMaterial:
 return _native().load_material(id)

static func save_material(value: KiwiTextureMaterial,id: String="") -> String:
 return _native().save_material(value,id)

static func remove(id: String) -> Error:
 return _native().remove(id)

static func import_file(path: String) -> String:
 return _native().import_file(path)

static func export_file(id: String,path: String) -> Error:
 return _native().export_file(id,path)

static func favorites() -> Array:
 return _native().favorites()

static func set_favorite(id: String,enabled: bool) -> void:
 _native().set_favorite(id,enabled)

static func recent() -> Array:
 return _native().recent()

static func mark_used(id: String) -> void:
 _native().mark_used(id)
