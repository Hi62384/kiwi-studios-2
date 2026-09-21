#FOR OPERATIONS IN THE GLOBAL FILESYSTEM
class_name FileOperations
extends Node

const FILE_COLORED_TEXTURE = preload("uid://mwmlqweqemfk")
const FOLDER_COLORED_TEXTURE = preload("uid://h5xgw3ns54ys")
const SPEAKER_TEXTURE = preload("uid://dcqki3r6v5dxo")
const ThumbnailRenderer = preload("uid://g3isy00e4xs5")
const CUBE_TEXTURE = preload("uid://bw47linn7yref")
const SHADER_TEXTURE = preload("res://resources/Images/ActorIcons/Shader.svg")



enum FileType {
	FOLDER,
	IMAGE,
	AUDIO,
	MODEL,
	MESH,
	GDSCRIPT,
	GDSHADER,
	ENVIRONMENT,
	MATERIAL3D,
	VIDEO,
	SCENE,
}


const _FILE_TYPE_TO_EXTENSION: Dictionary = {
	FileType.VIDEO: ActorVideo.EXTENSIONS,
	FileType.IMAGE : ['png','jpg','jpeg','webp','bmp','svg','tga','hdr','exr'],
		FileType.AUDIO : ['mp3','wav','ogg','flac'],
		FileType.MODEL : ['fbx','glb','gltf'],
		FileType.GDSCRIPT: ['gd'],
		FileType.GDSHADER: ['gdshader'],
		FileType.ENVIRONMENT: ['tres'],
		FileType.MATERIAL3D: ['tres'],
		FileType.MESH: ['tres'],
	}


const _TRES_NAME_TO_FILE_TYPE: Dictionary = {
	"Environment" : FileType.ENVIRONMENT,
	"StandardMaterial3D" : FileType.MATERIAL3D,
	"ArrayMesh" : FileType.MESH,
}



#is_path_inside("res://folder", "res://folder/file.txt") -> true
static func is_path_inside(parent_path: String, child_path: String) -> bool:
	# Normalize slashes (important on Windows)
	parent_path = parent_path.replace("\\", "/")
	child_path = child_path.replace("\\", "/")
	
	if parent_path == child_path:
		return true
	
	# Clean paths (removes "..", ".", etc.)
	parent_path = parent_path.simplify_path()
	child_path = child_path.simplify_path()

	# Ensure proper folder boundary
	var base := parent_path.rstrip("/") + "/"

	return child_path.begins_with(base)



static func file_is_sensitive(file_path: String) -> bool:
	return LocalProjectFilesystem.get_sensetive_file_paths().has(file_path)



static func path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)



static func get_lowest_directory(path: String) -> String:
	if path.get_extension() == "":
		return path
	return path.get_base_dir()



static func _update_local_project_filesystem_if_file_in_project(file: String) -> void:
	if LocalProjectFilesystem.file_exists_in_project_directory(file):
		LocalProjectFilesystem.update_root_folder()


static func file_type_to_extension(file_type: FileType) -> Array:
	return _FILE_TYPE_TO_EXTENSION.get(file_type)



static func _get_tres_type(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	# Read first line (header)
	var first_line := file.get_line()
	file.close()
	
	var regex := RegEx.new()
	
	# 1. Try script_class first (custom resources)
	regex.compile('script_class="([^"]+)"')
	var result := regex.search(first_line)
	if result:
		return result.get_string(1)

	# 2. Fallback to built-in type
	regex.compile('type="([^"]+)"')
	result = regex.search(first_line)
	if result:
		return result.get_string(1)

	return ""







static func get_type_of_file(file_path: String) -> FileType:
	var extension: String = file_path.get_extension().to_lower()
	if extension == "": return FileType.FOLDER
	if extension in ["tres", "res"]:
		var resource := ResourceLoader.load(file_path)
		if resource is ActorSceneData: return FileType.SCENE
		if resource is ActorObjectData:
			if resource.type_id == &"environment": return FileType.ENVIRONMENT
			if resource.type_id in [&"image", &"noise_image"]: return FileType.IMAGE
		if resource is Environment: return FileType.ENVIRONMENT
		if resource is Mesh: return FileType.MESH
		if resource is PackedScene: return FileType.MODEL
		if resource is AudioStream: return FileType.AUDIO
		if resource is Texture2D: return FileType.IMAGE
		if resource is StandardMaterial3D: return FileType.MATERIAL3D
		return FileType.FOLDER
	
	
	for key: FileType in _FILE_TYPE_TO_EXTENSION.keys():
		var arr: Array = _FILE_TYPE_TO_EXTENSION[key]
		
		if arr.has(extension):
			return key
		
	return FileType.FOLDER





static func delete_directory(directory: String) -> void:
	if file_is_sensitive(directory): return
	
	for file in DirAccess.get_files_at(directory):
		delete_file(directory.path_join(file))
	for dir in DirAccess.get_directories_at(directory):
		delete_directory(directory.path_join(dir))
	DirAccess.remove_absolute(directory)
	
	_update_local_project_filesystem_if_file_in_project(directory)



static func create_folder_at(path: String) -> void:
	if !dir_path_string_is_valid(path): return
	path = get_unique_name(path)
	DirAccess.make_dir_recursive_absolute(path)
	_update_local_project_filesystem_if_file_in_project(path)



static func delete_file(file_path: String) -> void:
	if file_is_sensitive(file_path): return
	DirAccess.remove_absolute(file_path)
	_update_local_project_filesystem_if_file_in_project(file_path)



static func move_to_trash(dir: String) -> void:
	if file_is_sensitive(dir): return
	OS.move_to_trash(dir)
	_update_local_project_filesystem_if_file_in_project(dir)



static func move_to_project_trash(dir: String) -> void:
	if file_is_sensitive(dir): return
	move_absolute(dir, LocalProjectFilesystem.get_project_trash_directory())
	_update_local_project_filesystem_if_file_in_project(dir)



#move everything in project trash folder, to system trash folder
static func flush_project_trash() -> void:
	var trash_directory: String = LocalProjectFilesystem.get_project_trash_directory()
	for file in DirAccess.get_files_at(trash_directory):
		move_to_trash(trash_directory.path_join(file))
	for dir in DirAccess.get_directories_at(trash_directory):
		move_to_trash(trash_directory.path_join(dir))



static func open_file(file: String) -> void:
	OS.shell_open(file)



#moves a file or directory to a given dir location
static func move_absolute(from_path: String, to_dir: String) -> void:
	if file_is_sensitive(from_path): return
	var file_name: String = from_path.get_file()
	var new_path: String = to_dir + "/" + file_name
	if path_exists(new_path): return
	DirAccess.rename_absolute(from_path, new_path)
	_update_local_project_filesystem_if_file_in_project(from_path)


static func move_files(path_to_move_to: String, files_to_move: Array[String]) -> void:
	path_to_move_to = get_lowest_directory(path_to_move_to)
	for file_path: String in files_to_move:
		if FileOperations.is_path_inside(file_path, path_to_move_to): 
			continue
		FileOperations.move_absolute(file_path, path_to_move_to)



#changes the name of only the file of the given path, and returns new result
static func get_changed_name_path(path: String, new_name: String) -> String:
	var base_directory: String = path.get_base_dir()
	var extension: String = path.get_extension()
	if extension != "": extension = "." + extension
	var new_path: String = base_directory + "/" + new_name + extension
	return new_path



#adds "-copy" at the end of the paths filename
static func get_unique_name(path: String) -> String:
	while path_exists(path):
		var path_name: String = path.get_basename().get_file()
		path = get_changed_name_path(path, path_name + "-copy")
	return path




#renames a file or directory with the new given name. Extension not needed
static func rename_absolute(path: String, new_name: String) -> void:
	if file_is_sensitive(path): return
	if !dir_path_string_is_valid(new_name): return
	var new_path: String = get_changed_name_path(path, new_name)
	DirAccess.rename_absolute(path, new_path)
	_update_local_project_filesystem_if_file_in_project(path)



static func duplicate_path_absolute(from_path: String, to_path: String) -> void:
	if from_path.get_extension() == "":
		duplicate_directory(from_path, to_path)
	else:
		duplicate_file(from_path, to_path)



static func duplicate_directory(from_path: String, to_path: String) -> void:
	if file_is_sensitive(from_path): return
	if !dir_path_string_is_valid(to_path): return
	
	to_path = get_unique_name(to_path)
	
	var dir := DirAccess.open(from_path)
	if dir == null:
		push_warning("Error opening source directory: " + from_path)
		return

	# Create destination directory if it doesn't exist
	if not DirAccess.dir_exists_absolute(to_path):
		DirAccess.make_dir_recursive_absolute(to_path)

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if file_name != "." and file_name != "..":
			var source := from_path.path_join(file_name)
			var destination := to_path.path_join(file_name)

			if dir.current_is_dir():
				duplicate_directory(source, destination)
			else:
				# Copy file
				var err := DirAccess.copy_absolute(source, destination)
				if err != OK:
					push_warning("Failed to copy file: " + source)

		file_name = dir.get_next()

	dir.list_dir_end()
	_update_local_project_filesystem_if_file_in_project(from_path)



static func duplicate_file(from_path: String, to_path: String) -> void:
	if file_is_sensitive(from_path): return
	if !dir_path_string_is_valid(to_path): return
	to_path = get_unique_name(to_path)
	DirAccess.copy_absolute(from_path, to_path)
	_update_local_project_filesystem_if_file_in_project(from_path)



static func save_resource(res: Resource) -> void:
	ResourceSaver.save(res, res.resource_path)



#returns chosen path, or blank if it was closed
static func get_file_dialog_path(dialog: FileDialog) -> Variant:
	dialog.visible = true
	dialog.root_subfolder = ""
	
	var state: Dictionary = {
		"finished" : false,
		"result" : ""
	}
	
	#only case where should return an array, so set default to empty array-
	#to return empty array when cancelled
	if dialog.file_mode == dialog.FILE_MODE_OPEN_FILES:
		state.result = []
	
	dialog.dir_selected.connect(func(dir: String):
		state.result = dir
		state.finished = true
		)
	
	dialog.file_selected.connect(func(path: String):
		state.result = path
		state.finished = true
		)
	
	dialog.files_selected.connect(func(files: PackedStringArray):
		state.result = files
		state.finished = true
		)
	
	dialog.canceled.connect(func():
		state.finished = true
		)
	
	while !state.finished:
		await dialog.get_tree().process_frame
	
	return state.result



static func dir_path_string_is_valid(path: String) -> bool:
	if path == "":
		return false
	
	path = path.get_basename()
	
	var invalid_chars = ["<",">",'"',"'","\\","//","|","?","*","."]
	
	for invalid_char: String in invalid_chars:
		if path.contains(invalid_char):
			return false

	return true



static func get_file_thumbnail(file: String) -> Texture2D:
	if !(FileAccess.file_exists(file) or DirAccess.dir_exists_absolute(file)):
		return null
	if file.get_extension().to_lower() == "gdshader":
		return SHADER_TEXTURE
	
	if file.get_extension().to_lower() in ["tres", "res"]:
		var resource := ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource is ActorSceneData:
			return load("res://resources/Images/ActorIcons/Scene.svg") as Texture2D
		var editable := resource as ActorObjectData
		if editable != null and editable.type_id == &"text_settings":
			return load("res://resources/Images/ActorIcons/TextSettings.svg") as Texture2D
		if editable != null and editable.type_id == &"environment":
			return await ThumbnailRenderer.render_actor_environment(editable) if is_instance_valid(ThumbnailRenderer._instance) else FILE_COLORED_TEXTURE
		if resource is Environment:
			return await ThumbnailRenderer.render_environment(resource) if is_instance_valid(ThumbnailRenderer._instance) else FILE_COLORED_TEXTURE
		if resource is Texture2D: return resource
		if editable != null and editable.type_id in [&"image", &"noise_image"]:
			return ActorImageGenerator.texture_for_object(editable)
		if editable != null and editable.type_id == &"material" and ThumbnailRenderer._instance != null:
			var preview_material := StandardMaterial3D.new()
			var tint: Color = editable.get_value(&"tint", Color.WHITE)
			tint.a *= editable.get_value(&"opacity", 1.0)
			preview_material.albedo_color = tint
			var albedo_reference := editable.get_value(&"albedo_map") as ActorObjectReference
			if albedo_reference != null:
				preview_material.albedo_texture = ActorImageGenerator.texture_for_object(albedo_reference.resolve(func(path: String):
					return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData))
			preview_material.roughness = editable.get_value(&"roughness", 1.0)
			preview_material.metallic = editable.get_value(&"metallic", 0.0)
			preview_material.metallic_specular = editable.get_value(&"specular", 0.5)
			preview_material.emission_enabled = editable.get_value(&"emission_enabled", false)
			preview_material.emission = editable.get_value(&"emission_color", Color.BLACK)
			preview_material.emission_energy_multiplier = editable.get_value(&"emission_energy", 1.0)
			return await ThumbnailRenderer.render_material(preview_material)
	var file_type: FileType = get_type_of_file(file)
	
	if DirAccess.dir_exists_absolute(file): return FOLDER_COLORED_TEXTURE
	elif file_type == FileType.IMAGE: return load_image(file)
	elif file_type == FileType.AUDIO: return SPEAKER_TEXTURE
	elif file_type == FileType.VIDEO:
		var preview := ActorVideo.frame(file, 0.0)
		var deadline := Time.get_ticks_msec() + 10000
		while preview == null and Time.get_ticks_msec() < deadline and not ActorVideo.info(file).is_empty():
			await (Engine.get_main_loop() as SceneTree).process_frame
			preview = ActorVideo.frame(file, 0.0)
		return preview if preview != null else preload("res://resources/Images/ActorIcons/Video.svg")
	elif file_type == FileType.MODEL: return CUBE_TEXTURE
	elif file_type == FileType.MESH: return CUBE_TEXTURE
	elif file_type == FileType.ENVIRONMENT: return await ThumbnailRenderer.render_environment(ResourceLoader.load(file))
	elif file_type == FileType.MATERIAL3D: return await ThumbnailRenderer.render_material(ResourceLoader.load(file))
	return FILE_COLORED_TEXTURE



static func load_image(path: String) -> Texture2D:
	return ImageTexture.create_from_image(Image.load_from_file(path))



static func load_audio(path: String) -> AudioStream:
	return ActorAudio.source(path)



static func load_3d_model(path: String) -> PackedScene:
	var gltf = GLTFDocument.new()
	var state = GLTFState.new()
	if path.get_extension() == "fbx":
		gltf = FBXDocument.new()
		state = FBXState.new()
	var err = gltf.append_from_file(path, state)
	if err != OK: return null
	var scene = gltf.generate_scene(state)
	if scene == null: return null
	var packed_scene = PackedScene.new()
	packed_scene.pack(scene)
	return packed_scene
	
