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
	if visited.has(path): return true
	visited[path]=true
	for dependency in ResourceLoader.get_dependencies(path):
		var target:=str(dependency).split("::")[-1]
		if target.get_extension().to_lower() in ["gd","cs","gde","gdextension"]:
			if not target.begins_with("res://") or not FileAccess.file_exists(target): return false
		elif target.get_extension().to_lower() in ["tres","res","tscn","scn"] and not safe_resource(target,visited): return false
	return true
func capture(value: Variant,path: String) -> bool:
	var source_path: String=value if value is String else (value.resource_path if value is Resource else "")
	if value is ActorObjectReference:
		if value.source==ActorObjectReference.Source.ASSET:
			if not safe_resource(value.asset_id): error="Unsafe resource dependency."; return false
			value=ResourceLoader.load(value.asset_id,"",ResourceLoader.CACHE_MODE_IGNORE) if FileAccess.file_exists(value.asset_id) else null
		else: value=value.embedded
	if value is String:
		if not FileAccess.file_exists(value): error="Source file is missing: "+str(value); return false
		var extension: String=value.get_extension().to_lower()
		if adapters.has(extension): return bool(adapters[extension].call(self,value,path))
		if extension in RAW:
			if extension=="glb" and not _self_contained_glb(value): error="This GLB references external files. Save it as an editable Kiwi model first."; return false
			var copied:=copy_file(value)
			if error.is_empty(): return _copy_bytes(copied,path)
			return false
		if extension not in ["tres","res","mesh","material","gdshader","gdshaderinc"]: error="Unsupported file. Save an editable Kiwi resource or a self-contained media file first."; return false
		if not safe_resource(value): error="This resource contains an external executable script and cannot be stored safely."; return false
		value=ResourceLoader.load(value,"",ResourceLoader.CACHE_MODE_IGNORE)
	if not value is Resource: error="Only resource objects or supported media files can be stored."; return false
	var type: String=value.get_class()
	while not type.is_empty(): native_types.append(type); type=ClassDB.get_parent_class(type)
	if value.get_script() is Script: native_types.append(value.get_script().get_global_name())
	if value is ActorObjectData: object_type=str(value.type_id)
	if value is KiwiAudioDocument and not value.portable_media.is_empty():
		var copy: KiwiAudioDocument=value.snapshot()
		var resolved:=KiwiAudioDocument.PortableCopy.resolve(copy,source_path if not source_path.is_empty() else copy._portable_root.path_join("composition.res"),true)
		if not str(resolved.error).is_empty() or not resolved.missing_assets.is_empty(): error="Cannot collect the composition's portable media. "+str(resolved.error); return false
		copy.portable_media={}; copy.scene_binding={}; value=copy
	var clone: Variant=clone_value(value)
	if not error.is_empty() or not clone is Resource: return false
	if not error.is_empty(): return false
	var result:=ResourceSaver.save(clone,path,ResourceSaver.FLAG_RELATIVE_PATHS)
	if result!=OK: error="Unable to write the resource snapshot (error %d)."%result
	return result==OK
func clone_value(value: Variant,field: String="") -> Variant:
	if value is ActorObjectReference and value.source==ActorObjectReference.Source.ASSET:
		if not FileAccess.file_exists(value.asset_id) or not safe_resource(value.asset_id): error="Missing or unsafe resource dependency: "+value.asset_id; return null
		var object:=ResourceLoader.load(value.asset_id,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
		if object==null: error="Invalid resource dependency: "+value.asset_id; return null
		return ActorObjectReference.from_object(clone_value(object))
	if value is Script:
		if not value.resource_path.begins_with("res://"): error="External executable scripts are not supported."; return null
		return value
	if value is ImageTexture or value is CompressedTexture2D or value is ViewportTexture:
		var id: int=value.get_instance_id()
		if resources.has(id): return resources[id]
		var image: Image=value.get_image()
		if image==null or image.is_empty(): error="The texture has no persistent image data."; return null
		if image.is_compressed() and image.decompress()!=OK: error="The texture's compression cannot be decoded."; return null
		if image.get_format() in [Image.FORMAT_RF,Image.FORMAT_RGF,Image.FORMAT_RGBF,Image.FORMAT_RGBAF,Image.FORMAT_RH,Image.FORMAT_RGH,Image.FORMAT_RGBH,Image.FORMAT_RGBAH,Image.FORMAT_RGBE9995]:
			var hdr:=ImageTexture.create_from_image(image); resources[id]=hdr; return hdr
		var compact:=PortableCompressedTexture2D.new(); compact.keep_compressed_buffer=true; compact.create_from_image(image,PortableCompressedTexture2D.COMPRESSION_MODE_LOSSLESS); resources[id]=compact; return compact
	if value is AudioStreamMicrophone: error="Live microphone streams must be recorded before storing them."; return null
	if value is Resource:
		var id: int=value.get_instance_id()
		if resources.has(id): return resources[id]
		var result: Resource=value.duplicate(false)
		if result==null: error="Cannot copy "+value.get_class(); return null
		resources[id]=result; result.resource_path=""
		for property: Dictionary in value.get_property_list():
			var key:=str(property.name)
			if (int(property.usage)&PROPERTY_USAGE_STORAGE)==0 or key in ["resource_path","resource_name","resource_local_to_scene"]: continue
			if key=="output_path": result.set(key,""); continue
			if value is KiwiAudioDocument and key=="scene_binding": result.set(key,{}); continue
			result.set(key,clone_value(value.get(key),key))
		if result is Shader: result.code=_inline_shader(result.code,value.resource_path.get_base_dir(),{})
		return result
	if value is Dictionary:
		var result: Dictionary=value.duplicate()
		for key in result: result[key]=clone_value(value[key],str(key))
		return result
	if value is Array:
		var result: Array=value.duplicate()
		for i in result.size(): result[i]=clone_value(value[i],field)
		return result
	if value is String or value is StringName:
		if field in ["code","text","label","name","display_name","title","description","tooltip_text"]: return value
		var text:=str(value)
		if text.is_empty(): return value
		if text.is_absolute_path() or text.begins_with("res://") or text.begins_with("user://"):
			# Scripts/built-in assets are stable application resources, not project
			# dependencies. Project media paths are always snapshotted.
			if text.begins_with("res://") and text.get_extension() in ["gd","cs"]: return value
			if not FileAccess.file_exists(text): error="Missing dependency: "+text; return value
			if text.get_extension().to_lower() in ["tres","res","mesh","material","gdshader"]:
				if files.has(text): return files[text]
				if not safe_resource(text): error="Unsafe resource dependency: "+text; return value
				var target:=_destination(text)
				files[text]=target
				var resource: Resource=ResourceLoader.load(text,"",ResourceLoader.CACHE_MODE_IGNORE)
				var cloned: Resource=clone_value(resource)
				if cloned==null or ResourceSaver.save(cloned,target,ResourceSaver.FLAG_RELATIVE_PATHS)!=OK: error="Unable to package dependency: "+text
				dependencies.append(target); return target
			return copy_file(text)
	if value is Object or typeof(value) in [TYPE_CALLABLE,TYPE_SIGNAL,TYPE_RID]: error="Live objects and callbacks cannot be stored as reusable resources."; return null
	return value
func _destination(path: String) -> String:
	var hash_context:=HashingContext.new(); hash_context.start(HashingContext.HASH_SHA256)
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null: error="Cannot read dependency: "+path; return ""
	while file.get_position()<file.get_length(): hash_context.update(file.get_buffer(1048576))
	var digest:=hash_context.finish().hex_encode(); file.close()
	var directory: String=root.path_join("assets") if destination_root.is_empty() else destination_root.path_join("assets")
	DirAccess.make_dir_recursive_absolute(directory)
	return directory.path_join(digest+"."+path.get_extension().to_lower())
func copy_file(path: String) -> String:
	if files.has(path): return files[path]
	var target:=_destination(path)
	if not error.is_empty(): return ""
	if not FileAccess.file_exists(target) and not _copy_bytes(path,target): return ""
	files[path]=target; dependencies.append(target); return target
func _copy_bytes(from: String,to: String) -> bool:
	if ProjectSettings.globalize_path(from)==ProjectSettings.globalize_path(to): return true
	var source:=FileAccess.open(from,FileAccess.READ); var target:=FileAccess.open(to+".tmp",FileAccess.WRITE)
	if source==null or target==null: error="Cannot copy required file: "+from; return false
	while source.get_position()<source.get_length():
		target.store_buffer(source.get_buffer(1048576))
		if target.get_error()!=OK: error="Storage is full or unavailable."; return false
	target.flush(); source.close(); target.close()
	if DirAccess.rename_absolute(to+".tmp",to)!=OK: error="Cannot complete file copy: "+to; return false
	return true
func _self_contained_glb(path: String) -> bool:
	var file:=FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()<20 or file.get_32()!=0x46546c67: return false
	file.seek(12); var length:=file.get_32(); var kind:=file.get_32()
	if kind!=0x4e4f534a or length>16777216: return false
	var json: Variant=JSON.parse_string(file.get_buffer(length).get_string_from_utf8())
	if not json is Dictionary: return false
	for key in ["buffers","images"]:
		for item: Dictionary in json.get(key,[]):
			if item.has("uri") and not str(item.uri).begins_with("data:"): return false
	return true
func _inline_shader(code: String,base: String,visited: Dictionary) -> String:
	var expression:=RegEx.new(); expression.compile('#include\\s+"([^"]+)"')
	var result:=code
	for match_ in expression.search_all(code):
		var path: String=match_.get_string(1)
		if not path.is_absolute_path() and not path.begins_with("res://"): path=base.path_join(path)
		if visited.has(path): error="Circular shader include: "+path; return code
		if not FileAccess.file_exists(path): error="Missing shader include: "+path; return code
		var seen:=visited.duplicate(); seen[path]=true
		result=result.replace(match_.get_string(),_inline_shader(FileAccess.get_file_as_string(path),path.get_base_dir(),seen))
	return result
