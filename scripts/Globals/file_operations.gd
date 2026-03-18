#FOR OPERATIONS IN THE GLOBAL FILESYSTEM
class_name FileOperations
extends Node

const FILE_COLORED_TEXTURE = preload("uid://mwmlqweqemfk")
const FOLDER_COLORED_TEXTURE = preload("uid://h5xgw3ns54ys")
const SPEAKER_TEXTURE = preload("uid://dcqki3r6v5dxo")



enum FileType {
	FOLDER,
	IMAGE,
	AUDIO,
	MODEL,
}


const _FILE_TYPE_TO_EXTENSION: Dictionary = {
		FileType.IMAGE : ['png','jpg'],
		FileType.AUDIO : ['mp3','wav'],
		FileType.MODEL : ['fbx','glb','gltf']
	}


static func file_type_to_extension(file_type: FileType) -> Array:
	return _FILE_TYPE_TO_EXTENSION.get(file_type)


static func extension_to_file_type(extension: String) -> FileType:
	for key: FileType in _FILE_TYPE_TO_EXTENSION.keys():
		for _extension: String in _FILE_TYPE_TO_EXTENSION[key]:
			if _extension == extension:
				return key
	return FileType.FOLDER



static func delete_directory(directory: String) -> void:
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file))
	for dir in DirAccess.get_directories_at(directory):
		delete_directory(directory.path_join(dir))
	DirAccess.remove_absolute(directory)



static func move_directory_to_trash(dir: String) -> void:
	OS.move_to_trash(dir)



static func duplicate_directory(from_path: String, to_path: String) -> void:
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
	
	var invalid_chars = ["<",">",'"',"'","\\","//","|","?","*"]
	
	for invalid_char: String in invalid_chars:
		if path.contains(invalid_char):
			return false

	return true



static func get_file_thumbnail(file: String) -> Texture2D:
	if !(FileAccess.file_exists(file) or DirAccess.dir_exists_absolute(file)):
		return null
	
	var file_type: FileType = extension_to_file_type(file.get_extension())
	
	if DirAccess.dir_exists_absolute(file): return FOLDER_COLORED_TEXTURE
	elif file_type == FileType.IMAGE: return load_image(file)
	elif file_type == FileType.AUDIO: return SPEAKER_TEXTURE
	
	return FILE_COLORED_TEXTURE



static func load_image(path: String) -> Texture2D:
	return ImageTexture.create_from_image(Image.load_from_file(path))



static func load_audio(path: String):
	var file = FileAccess.open(path, FileAccess.READ)
	var sound = AudioStreamMP3.new()
	if path.get_extension() == "wav":
		sound =  AudioStreamWAV.new()
	sound.data = file.get_buffer(file.get_length())
	return sound



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
	
