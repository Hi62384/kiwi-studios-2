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
	FileType.VIDEO: ["mp4", "mov", "mkv", "webm", "avi", "m4v", "ogv", "mpeg", "mpg", "wmv", "ts"],
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
	return _native_files().is_path_inside(parent_path,child_path)

static func file_is_sensitive(file_path: String) -> bool:
	return _native_files().file_is_sensitive(file_path)

static func path_exists(path: String) -> bool:
	return _native_files().path_exists(path)

static func get_lowest_directory(path: String) -> String:
	return _native_files().get_lowest_directory(path)

static func _update_local_project_filesystem_if_file_in_project(file: String) -> void:
	_native_files().update_project(file)

static func file_type_to_extension(file_type: FileType) -> Array:
	return _native_files().file_type_to_extension(file_type)

static func _get_tres_type(path: String) -> String:
	return _native_files().get_tres_type(path)

static func get_type_of_file(file_path: String) -> FileType:
	return _native_files().get_type_of_file(file_path)

static func delete_directory(directory: String) -> void:
	_native_files().delete_directory(directory)

static func create_folder_at(path: String) -> void:
	_native_files().create_folder_at(path)

static func delete_file(file_path: String) -> void:
	_native_files().delete_file(file_path)

static func move_to_trash(dir: String) -> void:
	_native_files().move_to_trash(dir)

static func move_to_project_trash(dir: String) -> void:
	_native_files().move_to_project_trash(dir)

static func flush_project_trash() -> void:
	_native_files().flush_project_trash()

static func open_file(file: String) -> void:
	_native_files().open_file(file)

static func move_absolute(from_path: String, to_dir: String) -> void:
	_native_files().move_absolute(from_path,to_dir)

static func move_files(path_to_move_to: String, files_to_move: Array[String]) -> void:
	_native_files().move_files(path_to_move_to,files_to_move)

static func get_changed_name_path(path: String, new_name: String) -> String:
	return _native_files().get_changed_name_path(path,new_name)

static func get_unique_name(path: String) -> String:
	return _native_files().get_unique_name(path)

static func rename_absolute(path: String, new_name: String) -> void:
	_native_files().rename_absolute(path,new_name)

static func duplicate_path_absolute(from_path: String, to_path: String) -> void:
	_native_files().duplicate_path_absolute(from_path,to_path)

static func duplicate_directory(from_path: String, to_path: String) -> void:
	_native_files().duplicate_directory(from_path,to_path)

static func duplicate_file(from_path: String, to_path: String) -> void:
	_native_files().duplicate_file(from_path,to_path)

static func save_resource(res: Resource) -> void:
	_native_files().save_resource(res)

static func get_file_dialog_path(dialog: FileDialog) -> Variant:
	var state: RefCounted = _native_files().begin_dialog(dialog)
	while not state.finished:
		await dialog.get_tree().process_frame
	return state.result

static func dir_path_string_is_valid(path: String) -> bool:
	return _native_files().dir_path_string_is_valid(path)

static func get_file_thumbnail(file: String) -> Texture2D:
	var plan: Dictionary = _native_files().thumbnail_plan(file)
	if plan.has("texture"): return plan.texture
	match str(plan.get("render","")):
		"text_settings": return await ThumbnailRenderer.render_text_settings(plan.resource)
		"actor_environment": return await ThumbnailRenderer.render_actor_environment(plan.resource)
		"environment": return await ThumbnailRenderer.render_environment(plan.resource)
		"material": return await ThumbnailRenderer.render_material(plan.resource)
	if plan.has("video"):
		var preview := ActorVideo.frame(file,0.0,false)
		var deadline := Time.get_ticks_msec()+10000
		while preview==null and Time.get_ticks_msec()<deadline and not ActorVideo.info(file).is_empty():
			await (Engine.get_main_loop() as SceneTree).process_frame
			preview=ActorVideo.frame(file,0.0,false)
		return preview if preview!=null else preload("res://resources/Images/ActorIcons/Video.svg")
	return null

static func load_image(path: String) -> Texture2D:
	return _native_files().load_image(path)

static func load_audio(path: String) -> AudioStream:
	return (load("res://scripts/actors/core/ActorAudio.cs").call("source",path) as AudioStream)



static func load_3d_model(path: String) -> PackedScene:
	return Engine.get_singleton("KiwiNativeServices").call("service","file_model_import").call("load_3d_model",path)

static func _native_files() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("file_operations")
