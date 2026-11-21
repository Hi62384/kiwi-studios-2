class_name KiwiClipboardSnapshot
extends RefCounted
## Extensible snapshot adapter. Resources embed their object graph; raw media
## dependencies are copied once by content hash, never kept as source shortcuts.
var root: String
var destination_root: String
var error:=""
var files: Dictionary={}
var resources: Dictionary={}
var dependencies: Array[String]=[]
var copying:=false
var native_types:=PackedStringArray()
var object_type:=""
const RAW := ["png","jpg","jpeg","webp","bmp","tga","svg","exr","hdr","wav","mp3","ogg","flac","aac","m4a","aiff","aif","mp4","mov","mkv","avi","webm","ogv","glb","mid","midi","ttf","otf","woff","woff2"]
static var adapters: Dictionary={}
static func register_adapter(extension: String,handler: Callable) -> void: adapters[extension.to_lower()]=handler
static func safe_resource(path: String,visited: Dictionary={}) -> bool:
	return _native_snapshot().safe_resource(path,visited)

func capture(value: Variant,path: String) -> bool:
	return _native_snapshot().capture(self,value,path)

func clone_value(value: Variant,field: String="") -> Variant:
	return _native_snapshot().clone_value(self,value,field)

func _destination(path: String) -> String:
	return _native_snapshot().destination(self,path)

func copy_file(path: String) -> String:
	return _native_snapshot().copy_file(self,path)

func _copy_bytes(from: String,to: String) -> bool:
	return _native_snapshot().copy_bytes(self,from,to)

func _self_contained_glb(path: String) -> bool:
	return _native_snapshot().self_contained_glb(path)

func _inline_shader(code: String,base: String,visited: Dictionary) -> String:
	return _native_snapshot().inline_shader(self,code,base,visited)


func _run_capture_adapter(extension: String,value: Variant,path: String) -> bool:
	return bool(adapters[extension].call(self,value,path))

static func _native_snapshot() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("clipboard_snapshot")
