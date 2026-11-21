class_name ActorSceneTabs
extends TabBar
const DocumentNative=preload("res://Workspaces/CompositingWorkspace/CompositingDocument.cs")
## Keeps multiple editable ActorSceneData documents alive in one workspace.

const ShaderWorkspaceScript = preload("res://Workspaces/ShaderWorkspace/shader_workspace.gd")
const AudioWorkspaceScript = preload("res://Workspaces/AudioWorkspace/audio_workspace.gd")
const ImageWorkspaceScript = preload("res://Workspaces/ImageWorkspace/image_workspace.gd")
const ModelWorkspaceScript = preload("res://Workspaces/ModelWorkspace/model_workspace.gd")
const EnvironmentWorkspaceScript=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
const TransformationWorkspaceScript = preload("res://Workspaces/TransformationWorkspace/transformation_workspace.gd")
const CompositingWorkspaceScript = preload("res://Workspaces/CompositingWorkspace/CompositingWorkspace.cs")

var timeline: ActorTimelineEditor
var scene_workspace: Control
var shader_workspace: Control
var audio_workspace: Control
var _audio_scene_id := ""
const AUDIO_SCENE_UID_META := &"kiwi_audio_scene_uid"
var image_workspace: Control
var model_workspace: KiwiModelWorkspace
var environment_workspace: KiwiEnvironmentWorkspace
var transformation_workspace: KiwiTransformationWorkspace
var compositing_workspace: Control
var documents: Array[Dictionary] = []
var _switching := false
var _untitled_counter := 1
var _active_index := -1


func _ready() -> void:
	_native_tabs().ready(self)

func _initialize_tabs() -> void:
	_native_tabs().initialize_tabs(self)

func new_scene() -> void:
	_native_tabs().new_scene(self)

func new_shader() -> void:
	_native_tabs().new_shader(self)

func new_image() -> void:
	_native_tabs().new_image(self)

func new_model() -> void:
	_native_tabs().new_model(self)

func new_environment() -> void:
	_native_tabs().new_environment(self)

func new_composition() -> void:
	_native_tabs().new_composition(self)

func open_composition(value: Variant) -> bool:
	return _native_tabs().open_simple_workspace(self,"compositing",value)

func _active_compositing_changed() -> void:
	_native_tabs().active_workspace_changed(self,"compositing")

func _compositing_saved(saved_path: String,saved_document: Resource) -> void:
	_native_tabs().compositing_saved(self,saved_path,saved_document)

func open_environment(value: Variant) -> bool:
	return _native_tabs().open_simple_workspace(self,"environment",value)

func _active_environment_changed() -> void:
	_native_tabs().active_workspace_changed(self,"environment")

func _environment_saved(saved_path: String,saved_session: KiwiEnvironmentSession) -> void:
	_native_tabs().environment_saved(self,saved_path,saved_session)

func _environment_to_scene(saved_path: String) -> void:
	_native_tabs().workspace_asset_to_scene(self,"environment",saved_path)

func _confirm_environment_close(index: int) -> void:
	_native_tabs().confirm_workspace_close(self,index,"environment")

func new_transformation() -> void:
	_native_tabs().new_transformation(self)

func open_transformation(value: Variant) -> bool:
	return _native_tabs().open_transformation(self,value)

func _active_transformation_changed() -> void:
	_native_tabs().active_workspace_changed(self,"transformation")

func _transformation_saved(path: String, edit_session: KiwiTransformationSession) -> void:
	_native_tabs().transformation_saved(self,path,edit_session)

func _confirm_transformation_close(index: int) -> void:
	_native_tabs().confirm_workspace_close(self,index,"transformation")

func open_model(value: Variant) -> bool:
	return _native_tabs().open_simple_workspace(self,"model",value)

func _active_model_changed() -> void:
	_native_tabs().active_workspace_changed(self,"model")

func _model_saved(saved_path: String, saved_session: KiwiModelSession) -> void:
	_native_tabs().model_saved(self,saved_path,saved_session)

func _model_to_scene(saved_path: String) -> void:
	_native_tabs().workspace_asset_to_scene(self,"model",saved_path)

func _confirm_model_close(index: int) -> void:
	_native_tabs().confirm_workspace_close(self,index,"model")

func open_image(source: Variant) -> bool:
	return _native_tabs().open_simple_workspace(self,"image",source)

func open_shader(source: Variant, parameters: Variant = null) -> bool:
	return _native_tabs().open_shader(self,source,parameters)

func load_shader_into_current_tab(path: String) -> void:
	_native_tabs().load_shader_into_current_tab(self,path)

func _synchronized_shader_state(previous: Dictionary, source: Variant, parameters: Variant = null) -> Dictionary:
	return _native_tabs().synchronized_shader_state(previous,source,parameters)

func _shader_binding(context: Variant) -> Dictionary:
	if not context is Dictionary:
		return {}
	var dictionary := context as Dictionary
	if dictionary.get("reader", Callable()) is Callable and dictionary.get("writer", Callable()) is Callable:
		var reader := dictionary.get("reader", Callable()) as Callable
		var writer := dictionary.get("writer", Callable()) as Callable
		if reader.is_valid() and writer.is_valid():
			return {"reader": reader, "writer": writer}
	return {}


func _connect_compact_shader_editor() -> void:
	_native_tabs().connect_compact_shader_editor(self)

func _external_shader_changed(source: Variant) -> void:
	_native_tabs().external_shader_changed(self,source)

func open_scene(path: String) -> bool:
	return _native_tabs().open_scene(self,path)

func close_scene(index: int, discard_changes: bool = false) -> void:
	var context: Dictionary=_native_tabs().prepare_close(self,index)
	if context.is_empty(): return
	if context.recording: await audio_workspace.finish_recording()
	_native_tabs().finish_close(self,context,discard_changes)

func _confirm_image_close(index: int) -> void:
	_native_tabs().confirm_workspace_close(self,index,"image")

func _confirm_compositing_close(index: int) -> void:
	_native_tabs().confirm_workspace_close(self,index,"compositing")

func save_current(path: String = "") -> Error:
	return _native_tabs().save_current(self,path)

func current_scene_path() -> String:
	return _native_tabs().current_scene_path(self)

func current_scene_name() -> String:
	return _native_tabs().current_scene_name(self)

func _tab_selected(index: int) -> void:
	_native_tabs().tab_selected(self,index)

func _open_index(index: int) -> void:
	_native_tabs().open_index(self,index)

func _release_document_history(document:Dictionary)->void:
	_native_tabs().release_document_history(self,document)

func _exit_tree()->void:
	_native_tabs().exit_tree(self)

func _capture_current() -> void:
	_native_tabs().capture_current(self)

func _active_scene_changed() -> void:
	_native_tabs().active_scene_changed(self)

func _add_document(scene: ActorSceneData, path: String, title: String, history: UndoRedo) -> void:
	_native_tabs().add_document(self,scene,path,title,history)

func _ensure_new_tab() -> void:
	_native_tabs().ensure_new_tab(self)

func _blank_scene() -> ActorSceneData:
	return _native_tabs().blank_scene()

func _new_untitled_name() -> String:
	return _native_tabs().new_untitled_name(self)

func _refresh_titles() -> void:
	_native_tabs().refresh_titles(self)

func _filesystem_resource_opened(path: String) -> void:
	_native_tabs().filesystem_resource_opened(self,path)

func _show_new_tab_menu() -> void:
	_native_tabs().show_new_tab_menu(self)

func _new_tab_choice(label: String, description: String) -> Button:
	return _native_tabs().new_tab_choice(label,description)

func _shader_identity(source: Variant) -> String:
	return _native_tabs().shader_identity(source)

func _image_identity(value: Variant) -> String:
	return _native_tabs().image_identity(value)

func _compositing_identity(value: Variant) -> String:
	return _native_tabs().compositing_identity(value)

func _active_image_changed() -> void:
	_native_tabs().active_workspace_changed(self,"image")

func _image_saved(source: Variant) -> void:
	_native_tabs().image_saved(self,source)

func _active_shader_changed() -> void:
	_native_tabs().active_workspace_changed(self,"shader")

func _shader_saved(source: Variant) -> void:
	_native_tabs().shader_saved(self,source)

func _tab_style(background: Color, border: Color) -> StyleBoxFlat:
	return _native_tabs().tab_style(background,border)

func new_audio() -> void:
	_native_tabs().new_audio(self)

func open_audio(value: Variant, binding: Dictionary = {}) -> bool:
	return _native_tabs().open_audio(self,value,binding)

func _audio_identity(value: Variant) -> String:
	return _native_tabs().audio_identity(value)

func _background_audio_changed(changed_session: KiwiAudioEditSession) -> void:
	_native_tabs().background_audio_changed(self,changed_session)

func _active_audio_changed() -> void:
	_native_tabs().active_audio_changed(self)

func _audio_saved(value: Variant) -> void:
	_native_tabs().audio_saved(self,value)

func _audio_document_index(id: String) -> int:
	return _native_tabs().audio_document_index(self,id)

func _audio_scene_index_for_id(id: String) -> int:
	return _native_tabs().audio_scene_index_for_id(self,id)

func _confirm_audio_close(index: int) -> void:
	_native_tabs().confirm_audio_close(self,index)

func _audio_to_scene(stream: AudioStream, label: String) -> void:
	_native_tabs().audio_to_scene(self,stream,label)

func _choose_audio_destination(stream: AudioStream, label: String, source_id: String, reason: String) -> void:
	_native_tabs().choose_audio_destination(self,stream,label,source_id,reason)

func _place_audio_in_scene(stream: AudioStream, label: String, source_id: String, scene_id: String, binding: Dictionary, _rebind: bool = false) -> void:
	_native_tabs().place_audio_in_scene(self,stream,label,source_id,scene_id,binding,_rebind)

static func _association_path(path: String) -> String:
	return _native_tabs().association_path(path)

func _audio_session_for_index(index: int) -> KiwiAudioEditSession:
	return _native_tabs().audio_session_for_index(self,index)

func _scene_index_for_association(association: Dictionary) -> int:
	return _native_tabs().scene_index_for_association(self,association)

func _set_audio_scene_association(source_id: String, scene_id: String, actor_id: String) -> void:
	_native_tabs().set_audio_scene_association(self,source_id,scene_id,actor_id)

func _relocate_audio_associations(uid: String, previous_path: String, destination: String) -> void:
	_native_tabs().relocate_audio_associations(self,uid,previous_path,destination)

static func _stored_scene_path(path: String) -> String:
	return _native_tabs().stored_scene_path(path)

func _audio_saved_document_path(source_id: String) -> String:
	return _native_tabs().audio_saved_document_path(self,source_id)

func open_audio_actor(actor: ActorData) -> bool:
	return _native_tabs().open_audio_actor(self,actor)

static func _native_tabs() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("scene_tabs")

func _read_linked_shader_parameters(binding: Dictionary) -> Variant:
	var reader: Callable=binding.get("reader",Callable())
	return reader.call() if reader.is_valid() else null

func _save_workspace_close_driver(closing: Dictionary, kind: String) -> void:
	var context: Dictionary=_native_tabs().prepare_workspace_close_save(self,closing,kind)
	if context.is_empty(): return
	if kind=="image": await image_workspace.save()
	elif kind=="model": await model_workspace.save()
	elif kind=="environment": await environment_workspace.save()
	elif kind=="transformation": await transformation_workspace.save()
	_native_tabs().finish_workspace_close_save(self,context)

func _save_audio_close_driver(id: String) -> void:
	var session: KiwiAudioEditSession=_native_tabs().prepare_audio_close_save(self,id)
	if session==null: return
	await audio_workspace.save()
	_native_tabs().finish_audio_close_save(self,id,session)
