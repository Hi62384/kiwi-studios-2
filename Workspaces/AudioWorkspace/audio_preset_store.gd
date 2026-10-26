extends RefCounted
const ROOT := "user://audio_workspace/presets"
const RECOVERY := "user://audio_workspace/preset_recovery"
const MAX_BYTES := 128*1024*1024

static func owned(path:String)->bool:
	var root:=ProjectSettings.globalize_path(ROOT).replace("\\","/").simplify_path()
	var absolute:=ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()
	var folder:=DirAccess.open(root)
	return folder!=null and absolute.get_base_dir()==root and not folder.is_link(absolute.get_file()) and absolute.get_extension()=="tres"

static func remove(path:String,digest:String)->String:
	if not owned(path) or digest.is_empty() or FileAccess.get_sha256(path)!=digest:return "The preset changed or is outside the library. Refresh before removing it."
	var directory:=ProjectSettings.globalize_path(RECOVERY)
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:return "Could not create the preset recovery folder."
	var destination:=directory.path_join(ActorData.new_id()+"_"+path.get_file())
	var error:=DirAccess.rename_absolute(ProjectSettings.globalize_path(path),destination)
	return "" if error==OK else "Preset removal failed; the original was preserved: "+error_string(error)

static func rename(path:String,digest:String,label:String,folder:String="__preserve")->String:
	if not owned(path) or digest.is_empty() or FileAccess.get_sha256(path)!=digest:return "The preset changed. Refresh before renaming it."
	var preset:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiAudioPreset
	if preset==null:return "The preset is unreadable."
	var copy:=preset.duplicate(false) as KiwiAudioPreset;copy.resource_path="";copy.label=label.substr(0,128)
	if folder!="__preserve":
		folder=folder.replace("\\","/").strip_edges().trim_prefix("/").trim_suffix("/")
		if folder.length()>256 or folder.split("/").has("..") or folder.split("/").has("."):return "Use a short folder label without dot segments."
		copy.folder=folder
	var temporary:=path.get_basename()+".writing-"+ActorData.new_id()+".tres";var backup:=path+".rename-backup-"+ActorData.new_id()
	var error:=ResourceSaver.save(copy,temporary)
	if error!=OK:return "Could not save the renamed preset. Original preserved."
	if FileAccess.get_sha256(path)!=digest:DirAccess.remove_absolute(temporary);return "The preset changed while saving. Original preserved."
	error=DirAccess.rename_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(backup))
	if error!=OK:DirAccess.remove_absolute(temporary);return "Could not retain the previous preset."
	error=DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))
	if error!=OK:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(backup),ProjectSettings.globalize_path(path))
		return "Could not publish the renamed preset; retained backup: "+backup
	return ""

static func recoverable()->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for root in [ROOT,RECOVERY]:
		var folder:=DirAccess.open(root)
		if folder==null:continue
		folder.list_dir_begin();var name:=folder.get_next();var visited:=0
		while not name.is_empty() and visited<2048:
			visited+=1
			if not folder.current_is_dir() and not folder.is_link(name) and (root==RECOVERY and name.ends_with(".tres") or root==ROOT and (name.contains(".tags-backup-") or name.contains(".rename-backup-"))):
				result.append({"path":root.path_join(name),"label":name,"digest":FileAccess.get_sha256(root.path_join(name))})
			name=folder.get_next()
		folder.list_dir_end()
	return result

static func restore(entry:Dictionary)->String:
	var found:=false
	for current in recoverable():
		if current.path==entry.get("path") and current.digest==entry.get("digest"):found=true;break
	if not found:return "The recovery file changed or is unavailable."
	var file:=FileAccess.open(str(entry.path),FileAccess.READ)
	if file==null or file.get_length()>MAX_BYTES:return "Preset recovery supports native files up to 128 MiB."
	file.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT))
	var destination:=ROOT.path_join(ActorData.new_id()+".tres")
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(entry.path),ProjectSettings.globalize_path(destination))!=OK:return "Could not copy the recovery preset."
	var preset:=ResourceLoader.load(destination,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiAudioPreset
	if preset==null:DirAccess.remove_absolute(destination);return "The recovery file is not a readable audio preset."
	preset.id=ActorData.new_id();preset.label+=" (restored)"
	var error:=ResourceSaver.save(preset,destination)
	if error!=OK:return "Could not finalize restored metadata. Recovery original retained."
	return ""
