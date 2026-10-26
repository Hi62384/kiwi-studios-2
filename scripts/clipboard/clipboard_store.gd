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
	root=ProjectSettings.globalize_path(location).replace("\\","/").simplify_path(); DirAccess.make_dir_recursive_absolute(root.path_join("objects"))
	data=_read(root.path_join("index.json"))
	if data.is_empty() and not read_only:
		data=_read(root.path_join("index.backup.json"))
		if not data.is_empty(): error="Recovered Super Clipboard from its last valid index."
	if data.is_empty():
		if not read_only and FileAccess.file_exists(root.path_join("index.json")):
			DirAccess.copy_absolute(root.path_join("index.json"),root.path_join("index.corrupt-"+ActorData.new_id()+".json")); error="Clipboard metadata is damaged. Existing stored data and the damaged index were preserved."
		data={"version":VERSION,"folders":{"default":{"name":"Default","parent":"","deleted":false}},"entries":{},"default_slot":"","ui":{}}
		if not FileAccess.file_exists(root.path_join("index.json")): _write(data)
func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parser:=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path))!=OK: return {}
	var envelope: Variant=parser.data
	if not envelope is Dictionary or not envelope.get("payload") is String or str(envelope.get("checksum",""))!=str(envelope.payload).sha256_text(): return {}
	if parser.parse(envelope.payload)!=OK: return {}
	var value: Variant=parser.data
	if value is Dictionary and int(value.get("version",0))>VERSION: read_only=true; error="This clipboard was created by a newer Kiwi version. It was left unchanged."; return {}
	if not value is Dictionary or int(value.get("version",0))!=VERSION or not value.get("folders") is Dictionary or not value.get("entries") is Dictionary: return {}
	if not _valid_index(value): return {}
	return value
func _valid_index(value: Dictionary) -> bool:
	if not value.folders.get("default") is Dictionary or not value.get("default_slot") is String or not value.get("ui",{}) is Dictionary: return false
	for id: String in value.folders:
		var entry: Variant=value.folders[id]
		if (id!="default" and (id.length()!=32 or not id.is_valid_hex_number(false))) or not entry is Dictionary: return false
		if not entry.get("name") is String or not entry.get("parent") is String: return false
		var parent:=id; var seen:={}
		while not parent.is_empty():
			if seen.has(parent) or seen.size()>64 or not value.folders.get(parent) is Dictionary: return false
			seen[parent]=true; parent=str(value.folders[parent].get("parent",""))
	for id: String in value.entries:
		var entry: Variant=value.entries[id]
		if id.length()!=32 or not id.is_valid_hex_number(false) or not entry is Dictionary: return false
		for key in ["name","folder","path","type","extension"]:
			if not entry.get(key) is String: return false
		if not value.folders.has(entry.folder) or not entry.get("native_types",[]) is Array: return false
		var path:=root.path_join(str(entry.path)).simplify_path()
		if str(entry.path).is_absolute_path() or not FileOperations.is_path_inside(root.path_join("objects"),path): return false
	return str(value.default_slot).is_empty() or value.entries.has(str(value.default_slot))
func _write(value: Dictionary) -> bool:
	if read_only: return false
	var payload:=JSON.stringify(value); var target:=root.path_join("index.json"); var temporary:=root.path_join("index.pending.json"); var backup:=root.path_join("index.backup.json")
	var file:=FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: error="Cannot write Super Clipboard metadata."; return false
	file.store_string(JSON.stringify({"payload":payload,"checksum":payload.sha256_text()})); file.flush(); file.close()
	if _read(temporary).is_empty(): error="Clipboard metadata validation failed. Nothing was replaced."; return false
	if FileAccess.file_exists(target) and not _read(target).is_empty():
		if DirAccess.copy_absolute(target,backup)!=OK: error="Cannot back up Super Clipboard metadata."; return false
	if read_only: return false
	if FileAccess.file_exists(target) and DirAccess.remove_absolute(target)!=OK: error="Cannot replace clipboard metadata."; return false
	if DirAccess.rename_absolute(temporary,target)!=OK: error="Metadata replacement failed; the backup remains available."; return false
	return true
func _assign(value: Dictionary) -> void:
	value=value.duplicate(true); value.ui=data.get("ui",{}).duplicate(true)
	if _write(value): data=value.duplicate(true); changed.emit()
func commit(title: String,next: Dictionary) -> bool:
	var before:=data.duplicate(true)
	if not _write(next): return false
	history.create_action(title); history.add_do_method(_assign.bind(next.duplicate(true))); history.add_undo_method(_assign.bind(before)); history.commit_action(false); data=next.duplicate(true); changed.emit(); return true
func folder_valid(id: String) -> bool: return data.folders.has(id) and not data.folders[id].get("deleted",false)
func unique_name(name: String,folder: String,skip: String="") -> String:
	var base:=name.strip_edges().replace("\n"," ").left(120)
	if base.is_empty(): base="Untitled"
	var candidate:=base; var count:=2
	while _name_exists(candidate,folder,skip): candidate=base+" ("+str(count)+")"; count+=1
	return candidate
func _unique_in(next: Dictionary,name: String,folder: String,skip: String) -> String:
	var original:=data; data=next
	var result:=unique_name(name,folder,skip); data=original; return result
func _name_exists(name: String,folder: String,skip: String) -> bool:
	for collection: Dictionary in [data.entries,data.folders]:
		for id: String in collection:
			var entry: Dictionary=collection[id]
			if id!=skip and not entry.get("deleted",false) and str(entry.get("folder",entry.get("parent","")))==folder and str(entry.name).nocasecmp_to(name)==0: return true
	return false
func save(value: Variant,name: String="Resource",folder: String="default") -> String:
	if read_only: return ""
	error=""
	if not folder_valid(folder): error="Choose an existing clipboard folder."; return ""
	var id:=ActorData.new_id(); var directory:=root.path_join("objects").path_join(id); DirAccess.make_dir_recursive_absolute(directory)
	var extension: String=value.get_extension().to_lower() if value is String else "tres"
	if extension not in KiwiClipboardSnapshot.RAW and not KiwiClipboardSnapshot.adapters.has(extension): extension="gdshader" if value is Shader or extension=="gdshader" else "tres"
	var path:=directory.path_join("resource."+extension)
	var snapshot:=KiwiClipboardSnapshot.new(); snapshot.root=root
	if not snapshot.capture(value,path): error=snapshot.error; return ""
	var native_type: String=value.type_id if value is ActorObjectData else (value.get_class() if value is Resource else extension)
	if value is Resource and not value is ActorObjectData and value.get_script() is Script and not value.get_script().get_global_name().is_empty(): native_type=value.get_script().get_global_name()
	var next:=data.duplicate(true); next.entries[id]={"name":unique_name(name,folder),"folder":folder,"id":id,"path":path.substr(root.length()+1),"type":snapshot.object_type if not snapshot.object_type.is_empty() else native_type,"native_types":Array(snapshot.native_types),"object_type":snapshot.object_type,"extension":extension,"original":value.resource_path if value is Resource else str(value),"dependencies":snapshot.dependencies,"created":Time.get_unix_time_from_system(),"deleted":false}; next.default_slot=id
	if not commit("Save to Super Clipboard",next): return ""
	return id
func entry_path(id: String,include_deleted: bool=false) -> String:
	if id.length()!=32 or not id.is_valid_hex_number(false): return ""
	var entry: Dictionary=data.entries.get(id,{})
	if entry.is_empty() or (entry.get("deleted",false) and not include_deleted): return ""
	var path:=root.path_join(str(entry.get("path",""))).simplify_path()
	return path if FileOperations.is_path_inside(root.path_join("objects"),path) and FileAccess.file_exists(path) else ""
func materialize(id: String,project_root: String) -> String:
	error=""; var source:=entry_path(id)
	if source.is_empty(): error="Stored resource data is missing."; return ""
	if project_root.is_empty() or not DirAccess.dir_exists_absolute(project_root): error="Open a project before using a clipboard resource."; return ""
	var folder:=project_root.path_join("Super Clipboard").path_join(id)
	if not FileOperations.is_path_inside(project_root,folder): error="Invalid clipboard identifier."; return ""
	var path:=folder.path_join(str(data.entries[id].name).validate_filename()+"."+str(data.entries[id].extension))
	var marker:=folder.path_join("import.json")
	if FileAccess.file_exists(marker):
		var imported: Variant=JSON.parse_string(FileAccess.get_file_as_string(marker))
		if imported is Dictionary:
			var previous:=folder.path_join(str(imported.get("file",""))).simplify_path()
			if FileOperations.is_path_inside(folder,previous) and FileAccess.file_exists(previous): return previous
	DirAccess.make_dir_recursive_absolute(folder)
	path=FileOperations.get_unique_name(path)
	var snapshot:=KiwiClipboardSnapshot.new(); snapshot.root=root; snapshot.destination_root=folder
	if not snapshot.capture(source,path): error=snapshot.error; return ""
	var file:=FileAccess.open(marker,FileAccess.WRITE)
	if file==null: error="Cannot record the project import."; return ""
	file.store_string(JSON.stringify({"id":id,"file":path.get_file()})); file.close()
	if LocalProjectFilesystem.node!=null: LocalProjectFilesystem.node.update_root_folder()
	return path
func create_folder(name: String,parent: String="default") -> String:
	if not parent.is_empty() and not folder_valid(parent): error="Invalid parent folder."; return ""
	var id:=ActorData.new_id(); var next:=data.duplicate(true); next.folders[id]={"name":unique_name(name,parent),"parent":parent,"deleted":false}
	return id if commit("Create clipboard folder",next) else ""
func rename(id: String,name: String) -> bool:
	if id=="default": error="Default is the built-in quick-save folder."; return false
	var collection: String="entries" if data.entries.has(id) else "folders"
	if not data[collection].has(id): return false
	var next:=data.duplicate(true); var entry: Dictionary=next[collection][id]; entry.name=unique_name(name,str(entry.get("folder",entry.get("parent",""))),id)
	return commit("Rename clipboard item",next)
func move(ids: PackedStringArray,folder: String,duplicate: bool=false) -> bool:
	if not folder_valid(folder): error="Invalid destination folder."; return false
	var next:=data.duplicate(true)
	for id in ids:
		if id=="default": continue
		var collection: String="entries" if data.entries.has(id) else "folders"
		if not next[collection].has(id): continue
		if collection=="folders":
			var ancestor:=folder; var visited:={}
			while not ancestor.is_empty() and not visited.has(ancestor):
				if ancestor==id: error="A folder cannot be moved inside itself."; return false
				visited[ancestor]=true; ancestor=str(next.folders.get(ancestor,{}).get("parent",""))
		var item: Dictionary=next[collection][id]
		if duplicate:
			if collection=="folders": _duplicate_folder(next,id,folder); continue
			var new_id:=ActorData.new_id(); item=item.duplicate(true); item.id=new_id; next.entries[new_id]=item
		item["folder" if collection=="entries" else "parent"]=folder; item.name=_unique_in(next,str(item.name),folder,str(item.get("id",id)))
	return commit("Duplicate clipboard items" if duplicate else "Move clipboard items",next)
func _duplicate_folder(next: Dictionary,id: String,parent: String) -> void:
	var copy:=ActorData.new_id(); next.folders[copy]=data.folders[id].duplicate(true); next.folders[copy].parent=parent; next.folders[copy].name=unique_name(str(next.folders[copy].name),parent)
	for entry_id: String in data.entries:
		if str(data.entries[entry_id].folder)!=id or data.entries[entry_id].get("deleted",false): continue
		var entry:=ActorData.new_id(); next.entries[entry]=data.entries[entry_id].duplicate(true); next.entries[entry].id=entry; next.entries[entry].folder=copy
	for folder_id: String in data.folders:
		if str(data.folders[folder_id].parent)==id and not data.folders[folder_id].get("deleted",false): _duplicate_folder(next,folder_id,copy)
func delete(ids: PackedStringArray,restore: bool=false) -> bool:
	var next:=data.duplicate(true)
	for id in ids:
		if id=="default": continue
		var collection: String="entries" if next.entries.has(id) else "folders"
		if not next[collection].has(id): continue
		next[collection][id].deleted=not restore
		if restore:
			var parent_key: String="folder" if collection=="entries" else "parent"
			var parent_id:=str(next[collection][id].get(parent_key,""))
			if not parent_id.is_empty() and not folder_valid(parent_id): next[collection][id][parent_key]="default"
		if collection=="folders": _delete_children(next,id,not restore,{})
		if str(next.default_slot)==id and not restore: next.default_slot=""
	if next.entries.has(str(next.default_slot)) and next.entries[str(next.default_slot)].get("deleted",false): next.default_slot=""
	return commit("Restore clipboard items" if restore else "Move clipboard items to Trash",next)
func _delete_children(next: Dictionary,id: String,deleted: bool,visited: Dictionary) -> void:
	if visited.has(id): return
	visited[id]=true
	for entry: Dictionary in next.entries.values():
		if str(entry.folder)==id: entry.deleted=deleted
	for key: String in next.folders:
		if str(next.folders[key].parent)==id: next.folders[key].deleted=deleted; _delete_children(next,key,deleted,visited)
func set_default(id: String) -> bool:
	if entry_path(id).is_empty(): return false
	var next:=data.duplicate(true); next.default_slot=id; return commit("Set clipboard Default Slot",next)
func save_ui(state: Dictionary) -> void:
	var next:=data.duplicate(true); next.ui=state.duplicate(true)
	if _write(next): data.ui=next.ui
func close() -> void:
	if is_instance_valid(history): history.clear_history(); history.free(); history=null
func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE and is_instance_valid(history): history.free()
func icon(id: String) -> Texture2D:
	var entry: Dictionary=data.entries.get(id,{})
	var extension:=str(entry.get("extension","")); var types: Array=entry.get("native_types",[])
	if extension=="gdshader" or types.has("Shader"): return FileOperations.SHADER_TEXTURE
	if extension in ["wav","mp3","ogg","flac","m4a","aac"] or types.has("AudioStream") or types.has("KiwiAudioDocument"): return FileOperations.SPEAKER_TEXTURE
	if extension=="glb" or types.has("Mesh") or types.has("KiwiModelDocument") or types.has("KiwiRigPreset"): return FileOperations.CUBE_TEXTURE
	if extension in ["png","jpg","jpeg","webp","svg","bmp","exr","hdr"] or types.has("Texture2D") or types.has("KiwiImageDocument") or str(entry.get("object_type","")) in ["image","noise_image"]: return preload("res://resources/Images/ActorIcons/Image2D.svg")
	if extension in ActorVideo.EXTENSIONS: return preload("res://resources/Images/ActorIcons/Video.svg")
	if types.has("ActorSceneData"): return preload("res://resources/Images/ActorIcons/Camera3D.svg")
	if types.has("KiwiTransformationImage2D"): return preload("res://resources/Images/ActorIcons/Transformation2D.svg")
	if str(entry.get("object_type",""))=="text_settings": return preload("res://resources/Images/ActorIcons/TextSettings.svg")
	if str(entry.get("object_type","")) in ["material","shader_material","natural_material"] or types.has("Material"): return preload("res://resources/Images/ActorIcons/Sphere.svg")
	return FileOperations.FILE_COLORED_TEXTURE
