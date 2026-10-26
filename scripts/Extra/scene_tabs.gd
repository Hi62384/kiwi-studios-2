class_name ActorSceneTabs
extends TabBar
## Keeps multiple editable ActorSceneData documents alive in one workspace.

const ShaderWorkspaceScript = preload("res://Workspaces/ShaderWorkspace/shader_workspace.gd")
const AudioWorkspaceScript = preload("res://Workspaces/AudioWorkspace/audio_workspace.gd")
const ImageWorkspaceScript = preload("res://Workspaces/ImageWorkspace/image_workspace.gd")
const ModelWorkspaceScript = preload("res://Workspaces/ModelWorkspace/model_workspace.gd")
const TransformationWorkspaceScript = preload("res://Workspaces/TransformationWorkspace/transformation_workspace.gd")

var timeline: ActorTimelineEditor
var scene_workspace: Control
var shader_workspace: Control
var audio_workspace: Control
var _audio_scene_id := ""
const AUDIO_SCENE_UID_META := &"kiwi_audio_scene_uid"
var image_workspace: Control
var model_workspace: KiwiModelWorkspace
var transformation_workspace: KiwiTransformationWorkspace
var documents: Array[Dictionary] = []
var _switching := false
var _untitled_counter := 1
var _active_index := -1


func _ready() -> void:
	add_to_group("actor_scene_tabs")
	tab_close_display_policy = TabBar.CLOSE_BUTTON_SHOW_ACTIVE_ONLY
	clip_tabs = true
	max_tab_width = 220
	select_with_rmb = true
	add_theme_font_size_override("font_size", 12)
	tab_changed.connect(_tab_selected)
	tab_close_pressed.connect(close_scene)
	add_to_group("actor_scene_tabs")
	call_deferred("_initialize_tabs")


func _initialize_tabs() -> void:
	timeline = get_node_or_null("../WorkspaceContainer/SceneWorkspace/VBoxContainer/HSplitContainer/VSplitContainer2/ActorTimeline") as ActorTimelineEditor
	if timeline == null:
		timeline = get_tree().get_first_node_in_group("actor_timeline_editors") as ActorTimelineEditor
	if timeline == null:
		return
	scene_workspace = get_node_or_null("../WorkspaceContainer/SceneWorkspace") as Control
	if scene_workspace != null:
		shader_workspace = ShaderWorkspaceScript.new()
		shader_workspace.name = "ShaderWorkspace"
		shader_workspace.visible = false
		scene_workspace.get_parent().add_child(shader_workspace)
		shader_workspace.shader_saved.connect(_shader_saved)
		shader_workspace.document_changed.connect(_active_shader_changed)
		image_workspace = ImageWorkspaceScript.new()
		image_workspace.name = "ImageWorkspace"
		image_workspace.visible = false
		scene_workspace.get_parent().add_child(image_workspace)
		image_workspace.document_changed.connect(_active_image_changed)
		image_workspace.image_saved.connect(_image_saved)
		audio_workspace = AudioWorkspaceScript.new()
		audio_workspace.name = "AudioWorkspace"
		audio_workspace.visible = false
		scene_workspace.get_parent().add_child(audio_workspace)
		audio_workspace.document_changed.connect(_active_audio_changed)
		audio_workspace.background_document_changed.connect(_background_audio_changed)
		audio_workspace.audio_saved.connect(_audio_saved)
		audio_workspace.use_in_scene.connect(_audio_to_scene)
		model_workspace=ModelWorkspaceScript.new()
		model_workspace.name="ModelWorkspace"; model_workspace.visible=false
		scene_workspace.get_parent().add_child(model_workspace)
		model_workspace.document_changed.connect(_active_model_changed)
		model_workspace.model_saved.connect(_model_saved)
		model_workspace.use_in_scene.connect(_model_to_scene)
		transformation_workspace=TransformationWorkspaceScript.new(); transformation_workspace.name="TransformationWorkspace"; transformation_workspace.visible=false
		scene_workspace.get_parent().add_child(transformation_workspace)
		transformation_workspace.document_changed.connect(_active_transformation_changed); transformation_workspace.asset_saved.connect(_transformation_saved)
	var file_system := get_node_or_null("../WorkspaceContainer/SceneWorkspace/VBoxContainer/HSplitContainer/VSplitContainer/FileSystem")
	if file_system != null and file_system.has_signal("file_resource_opened"):
		file_system.connect("file_resource_opened", _filesystem_resource_opened)
	if file_system != null and file_system.has_signal("shader_file_opened"):
		file_system.connect("shader_file_opened", open_shader)
	clear_tabs()
	_add_document(timeline.capture_scene_data(false), "", "Main Scene", timeline.model.history)
	_active_index = 0
	current_tab = 0
	timeline.model.changed.connect(_active_scene_changed)
	call_deferred("_connect_compact_shader_editor")
	_refresh_titles()
	_ensure_new_tab()


func new_scene() -> void:
	if timeline == null:
		return
	_capture_current()
	_add_document(_blank_scene(), "", _new_untitled_name(), UndoRedo.new())
	_open_index(documents.size() - 1)


func new_shader() -> void:
	var shader := Shader.new()
	shader.resource_name = "Untitled Shader"
	shader.code = "shader_type spatial;\n\nvoid fragment() {\n    ALBEDO = vec3(0.72, 0.82, 0.9);\n    ROUGHNESS = 0.35;\n}\n"
	open_shader(shader)
	if shader_workspace != null:
		shader_workspace.requires_path = true
		shader_workspace.load_shader_button.show()
		var document := documents[_active_index]
		document.state = shader_workspace.capture_state()
		documents[_active_index] = document


func new_image() -> void:
	var blank:=KiwiImageDocument.new()
	blank.layers.append(KiwiImageLayer.create("basic",blank.canvas_size))
	open_image(blank)


func new_model() -> void:
	open_model(KiwiModelDocument.new())

func new_transformation() -> void: open_transformation(KiwiTransformationImage2D.blank())

func open_transformation(value: Variant) -> bool:
	if transformation_workspace==null: return false
	var identity := ProjectSettings.globalize_path(str(value)).replace("\\","/").simplify_path() if value is String else "embedded:"+str(value.get_instance_id())
	for i in documents.size():
		if documents[i].get("type","")=="transformation" and documents[i].identity==identity: _capture_current(); _open_index(i); return true
	var result := KiwiTransformationWorkspace.resolve(value)
	if result.has("error"):
		transformation_workspace.status.text=result.error
		var popup := AcceptDialog.new(); popup.name="TransformationOpenError"; popup.title="Could not open Transformation Image"; popup.dialog_text=str(result.error); add_child(popup)
		popup.confirmed.connect(popup.queue_free); popup.canceled.connect(popup.queue_free); popup.popup_centered(Vector2i(420,140)); return false
	_capture_current(); var edit_session := KiwiTransformationSession.new(); edit_session.document=result.document.snapshot(); edit_session.dirty=not value is String
	var ui: Dictionary=edit_session.document.workspace_state; edit_session.restore_view_state(ui)
	var path := str(value) if value is String else ""; var title := path.get_file() if not path.is_empty() else "Untitled Transformation"
	documents.append({"type":"transformation","source":value,"identity":identity,"path":path,"name":title,"state":{"session":edit_session,"path":path,"ui":ui},"dirty":edit_session.dirty})
	_switching=true; add_tab(title,preload("res://resources/Images/ActorIcons/Transformation2D.svg"))
	if tab_count>documents.size(): move_tab(tab_count-1,documents.size()-1)
	_ensure_new_tab(); _switching=false; _open_index(documents.size()-1); return true

func _active_transformation_changed() -> void:
	if _switching or _active_index<0 or _active_index>=documents.size() or documents[_active_index].get("type","")!="transformation": return
	documents[_active_index].dirty=transformation_workspace.session.dirty; _refresh_titles()

func _transformation_saved(path: String, edit_session: KiwiTransformationSession) -> void:
	ActorTransformationStates.invalidate(path)
	if timeline != null: timeline.model.changed.emit()
	for i in documents.size():
		if documents[i].get("type","")!="transformation": continue
		if documents[i].state.get("session")!=edit_session and not (i==_active_index and transformation_workspace.session==edit_session): continue
		documents[i].source=path; documents[i].path=path; documents[i].identity=ProjectSettings.globalize_path(path).replace("\\","/").simplify_path(); documents[i].name=path.get_file(); documents[i].dirty=edit_session.dirty; documents[i].state.path=path; _refresh_titles(); return

func _confirm_transformation_close(index: int) -> void:
	var closing := documents[index]; var popup := ConfirmationDialog.new(); popup.title="Unsaved Transformation Image"; popup.dialog_text="Save changes to "+str(closing.name)+"?"; popup.ok_button_text="Save"; popup.cancel_button_text="Keep editing"; add_child(popup)
	var discard := popup.add_button("Discard",false,"discard")
	discard.pressed.connect(func(): popup.queue_free(); var at := documents.find(closing); if at>=0: close_scene(at,true))
	popup.confirmed.connect(func():
		popup.queue_free(); var at := documents.find(closing)
		if at<0: return
		_capture_current(); _open_index(at); var edit_session := transformation_workspace.session; await transformation_workspace.save(); at=documents.find(closing)
		if at>=0 and not edit_session.dirty: close_scene(at,true))
	popup.canceled.connect(popup.queue_free); popup.popup_centered(Vector2i(410,140))


func open_model(value: Variant) -> bool:
	if model_workspace==null: return false
	var identity := ProjectSettings.globalize_path(str(value)).replace("\\","/").simplify_path() if value is String else "embedded:"+str(value.get_instance_id())
	for index in documents.size():
		if documents[index].get("type","")=="model" and documents[index].get("identity","")==identity:
			_capture_current(); _open_index(index); return true
	_capture_current()
	var title := str(value).get_file() if value is String else "Untitled Model"
	documents.append({"type":"model","source":value,"identity":identity,"path":"","name":title,"state":{},"dirty":false})
	_switching=true; add_tab(title,preload("res://resources/Images/ActorIcons/BasicMesh.svg"))
	if tab_count>documents.size(): move_tab(tab_count-1,documents.size()-1)
	_ensure_new_tab(); _switching=false; _open_index(documents.size()-1)
	return true


func _active_model_changed() -> void:
	if _switching or _active_index<0 or _active_index>=documents.size() or documents[_active_index].get("type","")!="model": return
	documents[_active_index].dirty=model_workspace.session.dirty
	_refresh_titles()


func _model_saved(saved_path: String, saved_session: KiwiModelSession) -> void:
	var index := -1
	for i in documents.size():
		if documents[i].get("type","")=="model" and (documents[i].get("state",{}).get("session")==saved_session or (i==_active_index and model_workspace.session==saved_session)): index=i; break
	if index<0: return
	var document := documents[index]
	document.source=saved_path; document.path=saved_path; document.identity=ProjectSettings.globalize_path(saved_path).replace("\\","/").simplify_path(); document.name=saved_path.get_file(); document.dirty=false
	document.state.path=saved_path; document.dirty=saved_session.dirty
	documents[index]=document; _refresh_titles()
	get_tree().call_group("actor_shader_runtimes","refresh_saved_model",saved_path)
	if timeline!=null:
		timeline.physics.invalidate_asset(saved_path)
		timeline._evaluate_runtimes()


func _model_to_scene(saved_path: String) -> void:
	_capture_current()
	for i in range(documents.size()-1,-1,-1):
		if documents[i].get("type","")=="scene":
			_open_index(i)
			timeline.model.create_actor(timeline.registry.get_definition(&"basic_mesh"),timeline.canvas.playhead,{&"mesh_path":saved_path})
			return
	new_scene()
	timeline.model.create_actor(timeline.registry.get_definition(&"basic_mesh"),timeline.canvas.playhead,{&"mesh_path":saved_path})


func _confirm_model_close(index: int) -> void:
	var closing := documents[index]
	var dialog := ConfirmationDialog.new(); dialog.title="Unsaved model"; dialog.dialog_text="Save changes to "+str(documents[index].name)+"?"; dialog.ok_button_text="Save"; dialog.cancel_button_text="Keep editing"; add_child(dialog)
	var discard := dialog.add_button("Discard",false,"discard")
	discard.pressed.connect(func():
		dialog.queue_free(); var current_index := documents.find(closing)
		if current_index>=0: close_scene(current_index,true))
	dialog.confirmed.connect(func():
		dialog.queue_free(); _capture_current(); var current_index := documents.find(closing)
		if current_index<0: return
		_open_index(current_index); var closing_session := model_workspace.session; await model_workspace.save(); current_index=documents.find(closing)
		if current_index>=0 and not closing_session.dirty: close_scene(current_index,true))
	dialog.canceled.connect(dialog.queue_free); dialog.popup_centered(Vector2i(390,150))


func open_image(source: Variant) -> bool:
	if image_workspace == null or not (source is String or source is Image or source is Texture2D or source is KiwiImageDocument): return false
	var identity := _image_identity(source)
	for index in documents.size():
		if str(documents[index].get("type", "")) == "image" and str(documents[index].get("identity", "")) == identity:
			_capture_current()
			_open_index(index)
			return true
	_capture_current()
	var path := str(source) if source is String else ""
	var title := path.get_file() if not path.is_empty() else "Untitled Image"
	documents.append({"type": "image", "source": source, "identity": identity,
		"path": path, "name": title, "state": {}, "dirty": false})
	_switching = true
	add_tab(title, preload("res://resources/Images/ActorIcons/Image2D.svg"))
	if tab_count > documents.size(): move_tab(tab_count - 1, documents.size() - 1)
	_ensure_new_tab()
	_switching = false
	_open_index(documents.size() - 1)
	return true


func open_shader(source: Variant, parameters: Variant = null) -> bool:
	if shader_workspace == null or not (source is Shader or source is String): return false
	var identity := _shader_identity(source)
	for index in documents.size():
		if str(documents[index].get("type", "scene")) == "shader" and str(documents[index].get("identity", "")) == identity:
			_capture_current()
			var existing := documents[index]
			existing.source = source
			existing.state = _synchronized_shader_state(existing.get("state", {}), source, parameters)
			var updated_binding := _shader_binding(parameters)
			if not updated_binding.is_empty():
				if (existing.get("binding", {}) as Dictionary).is_empty():
					existing.state.parameters_linked = true
				existing.binding = updated_binding
			existing.dirty = false
			documents[index] = existing
			_open_index(index)
			return true
	_capture_current()
	var path := str(source) if source is String else ""
	var title: String = path.get_file() if not path.is_empty() else (source.resource_name if not source.resource_name.is_empty() else "Untitled Shader")
	documents.append({"type": "shader", "source": source, "identity": identity,
		"path": path, "name": title, "state": _synchronized_shader_state({}, source, parameters),
		"binding": _shader_binding(parameters), "dirty": false})
	_switching = true
	add_tab(title, preload("res://resources/Images/ActorIcons/Shader.svg"))
	if tab_count > documents.size(): move_tab(tab_count - 1, documents.size() - 1)
	_ensure_new_tab()
	_switching = false
	_open_index(documents.size() - 1)
	return true


func load_shader_into_current_tab(path: String) -> void:
	if _active_index < 0 or _active_index >= documents.size() or path.is_empty(): return
	var current := documents[_active_index]
	if str(current.get("type", "")) != "shader" or not str(current.get("path", "")).is_empty():
		open_shader(path)
		return
	var identity := _shader_identity(path)
	for index in documents.size():
		if index != _active_index and str(documents[index].get("type", "")) == "shader" \
				and str(documents[index].get("identity", "")) == identity:
			_open_index(index)
			return
	current.source = path
	current.path = path
	current.identity = identity
	current.name = path.get_file()
	current.state = _synchronized_shader_state({}, path)
	current.binding = {}
	current.dirty = false
	documents[_active_index] = current
	_open_index(_active_index)


func _synchronized_shader_state(previous: Dictionary, source: Variant, parameters: Variant = null) -> Dictionary:
	var state := previous.duplicate(true)
	if source is Shader:
		state.code = source.code
	else:
		var file := FileAccess.open(str(source), FileAccess.READ)
		if file != null:
			state.code = file.get_as_text()
	if parameters is Dictionary:
		var dictionary := parameters as Dictionary
		var values: Variant = dictionary.get("values", dictionary)
		if values is Dictionary:
			state.parameters = values.duplicate(true)
		if dictionary.has("reader") and dictionary.has("writer") and not state.has("parameters_linked"):
			state.parameters_linked = true
	return state


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
	for candidate in get_tree().get_nodes_in_group("shader_code_editor"):
		if candidate is ShaderCodeEditor and not (candidate as ShaderCodeEditor).dedicated_mode:
			var compact := candidate as ShaderCodeEditor
			if not compact.shader_changed.is_connected(_external_shader_changed):
				compact.shader_changed.connect(_external_shader_changed)


func _external_shader_changed(source: Variant) -> void:
	var identity := _shader_identity(source)
	for index in documents.size():
		var document := documents[index]
		if str(document.get("type", "")) != "shader" or str(document.get("identity", "")) != identity:
			continue
		document.source = source
		document.state = _synchronized_shader_state(document.get("state", {}), source)
		document.dirty = false
		documents[index] = document
	_refresh_titles()


func open_scene(path: String) -> bool:
	if timeline == null or path.is_empty():
		return false
	var normalized := path.replace("\\", "/").simplify_path()
	for index in documents.size():
		if str(documents[index].path).replace("\\", "/").simplify_path() == normalized:
			_capture_current()
			_open_index(index)
			return true
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	if loaded == null:
		return false
	_capture_current()
	_add_document(loaded, path, path.get_file().get_basename(), UndoRedo.new())
	_open_index(documents.size() - 1)
	return true


func close_scene(index: int, discard_changes: bool = false) -> void:
	if index < 0 or index >= documents.size():
		return
	_capture_current()
	var closing_document := documents[index]
	if str(closing_document.get("type", "")) == "audio" and audio_workspace != null:
		var closing_session: Variant = closing_document.get("state", {}).get("session")
		if closing_session != null and closing_session == audio_workspace._record_session:
			await audio_workspace.finish_recording()
			index = documents.find(closing_document)
			if index < 0: return
			closing_document.dirty = closing_session.dirty
	if not discard_changes and str(documents[index].get("type", "")) == "image" and bool(documents[index].get("dirty", false)):
		_confirm_image_close(index)
		return
	if not discard_changes and str(documents[index].get("type", "")) == "audio" and bool(documents[index].get("dirty", false)):
		_confirm_audio_close(index)
		return
	if not discard_changes and str(documents[index].get("type", ""))=="model" and bool(documents[index].get("dirty",false)):
		_confirm_model_close(index)
		return
	if not discard_changes and documents[index].get("type","")=="transformation" and documents[index].dirty: _confirm_transformation_close(index); return
	var previous_active := _active_index
	_switching = true
	documents.remove_at(index)
	remove_tab(index)
	_switching = false
	if documents.is_empty():
		_add_document(_blank_scene(), "", _new_untitled_name(), UndoRedo.new())
		_open_index(0)
	elif index == previous_active:
		_open_index(clampi(index, 0, documents.size() - 1))
	else:
		_active_index = previous_active - 1 if index < previous_active else previous_active
		_switching = true
		current_tab = _active_index
		_switching = false
		_refresh_titles()
	_release_document_history(closing_document)


func _confirm_image_close(index: int) -> void:
	var popup := PopupPanel.new()
	popup.add_theme_stylebox_override("panel", _tab_style(Color("14212e"),Color("4a8275")))
	add_child(popup)
	var column := VBoxContainer.new(); column.custom_minimum_size=Vector2(350,96); column.add_theme_constant_override("separation",8); popup.add_child(column)
	var title := Label.new(); title.text="Save your image changes?"; title.add_theme_font_size_override("font_size",19); column.add_child(title)
	var detail := Label.new(); detail.text=str(documents[index].name)+" has unsaved edits."; detail.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; column.add_child(detail)
	var row := HBoxContainer.new(); column.add_child(row)
	var cancel := Button.new(); cancel.text="Keep editing"; row.add_child(cancel); cancel.pressed.connect(popup.hide)
	var discard := Button.new(); discard.text="Discard"; row.add_child(discard)
	discard.pressed.connect(func(): popup.hide(); close_scene(index,true))
	var save_button := Button.new(); save_button.text="Save"; save_button.add_theme_stylebox_override("normal",_tab_style(Color("23594e"),Color("68d2b6"))); row.add_child(save_button)
	save_button.pressed.connect(func():
		popup.hide()
		_capture_current(); _open_index(index)
		await image_workspace.save()
		if not image_workspace._dirty: close_scene(index,true))
	popup.popup_hide.connect(popup.queue_free)
	popup.popup_centered(Vector2i(390,132))


func save_current(path: String = "") -> Error:
	if timeline == null or _active_index < 0 or _active_index >= documents.size():
		return ERR_UNAVAILABLE
	if str(documents[_active_index].get("type", "scene")) != "scene":
		return ERR_UNAVAILABLE
	_capture_current()
	var document := documents[_active_index]
	var destination := path if not path.is_empty() else str(document.path)
	if destination.is_empty():
		return ERR_FILE_BAD_PATH
	var scene := timeline.capture_scene_data(true)
	scene.resource_name = destination.get_file().get_basename()
	scene.set_meta(AUDIO_SCENE_UID_META, str(document.get("persistent_id", "")))
	var error := ResourceSaver.save(scene, destination)
	if error != OK:
		return error
	var previous_path := str(document.path)
	document.path = destination
	document.persistent_saved = true
	document.name = destination.get_file().get_basename()
	document.dirty = false
	documents[_active_index] = document
	_relocate_audio_associations(str(document.get("persistent_id", "")), previous_path, destination)
	_refresh_titles()
	if LocalProjectFilesystem.node != null:
		LocalProjectFilesystem.update_root_folder()
	return OK


func current_scene_path() -> String:
	return str(documents[_active_index].path) if _active_index >= 0 and _active_index < documents.size() and str(documents[_active_index].get("type", "scene")) == "scene" else ""


func current_scene_name() -> String:
	return str(documents[_active_index].name) if _active_index >= 0 and _active_index < documents.size() else "New Scene"


func _tab_selected(index: int) -> void:
	if _switching or timeline == null or index < 0 or index >= documents.size():
		if not _switching and timeline != null and index == documents.size():
			_show_new_tab_menu()
		return
	_capture_current()
	_open_index(index)


func _open_index(index: int) -> void:
	if timeline == null or index < 0 or index >= documents.size():
		return
	_switching = true
	current_tab = index
	var document := documents[index]
	if audio_workspace != null: audio_workspace.visible = false
	if model_workspace != null: model_workspace.visible=false
	if transformation_workspace!=null: transformation_workspace.visible=false
	if document.get("type","")=="transformation":
		if scene_workspace!=null: scene_workspace.visible=false
		if shader_workspace!=null: shader_workspace.visible=false
		if image_workspace!=null: image_workspace.visible=false
		transformation_workspace.visible=true; transformation_workspace.open_source(document.source,document.state)
	elif str(document.get("type", "scene"))=="model":
		if scene_workspace!=null: scene_workspace.visible=false
		if shader_workspace!=null: shader_workspace.visible=false
		if image_workspace!=null: image_workspace.visible=false
		model_workspace.visible=true
		model_workspace.open_source(document.source,document.state)
	elif str(document.get("type", "scene")) == "shader":
		if scene_workspace != null: scene_workspace.visible = false
		if image_workspace != null: image_workspace.visible = false
		shader_workspace.visible = true
		var binding: Dictionary = document.get("binding", {})
		var state: Dictionary = document.state
		var reader := binding.get("reader", Callable()) as Callable
		if bool(state.get("parameters_linked", false)) and reader.is_valid():
			var linked_values: Variant = reader.call()
			if linked_values is Dictionary:
				state.parameters = linked_values.duplicate(true)
			document.state = state
			documents[index] = document
		shader_workspace.open_source(document.source, state, binding)
	elif str(document.get("type", "scene")) == "image":
		if scene_workspace != null: scene_workspace.visible = false
		if shader_workspace != null: shader_workspace.visible = false
		image_workspace.visible = true
		image_workspace.open_source(document.source, document.state)
	elif str(document.get("type", "scene")) == "audio":
		if scene_workspace != null: scene_workspace.visible = false
		if shader_workspace != null: shader_workspace.visible = false
		if image_workspace != null: image_workspace.visible = false
		audio_workspace.visible = true
		audio_workspace.open_source(document.source, document.state)
		audio_workspace.set_scene_binding(not audio_workspace.session.document.scene_binding.is_empty())
		audio_workspace.send_scene_button.tooltip_text = "Save the editable composition before sending, then save the destination scene. The Scene Edit Audio command can reopen the composition after restart. Moving either saved file requires relinking."
	else:
		if shader_workspace != null: shader_workspace.visible = false
		if image_workspace != null: image_workspace.visible = false
		if scene_workspace != null: scene_workspace.visible = true
		_audio_scene_id = str(document.get("id", ""))
		timeline.restore_scene_data(document.scene, true)
		# restore_scene_data allocates a fresh standalone history. Tabs restore
		# their retained history instead; release that otherwise orphaned object.
		if timeline.model.history != document.history:
			timeline.model.history.clear_history();timeline.model.history.free()
		timeline.model.history = document.history
	_active_index = index
	_switching = false
	_refresh_titles()

func _release_document_history(document:Dictionary)->void:
	var history:Variant=document.get("history")
	if not is_instance_valid(history) or not history is UndoRedo:return
	if is_instance_valid(timeline) and timeline.model.history==history:return
	for other in documents:
		if other.get("history")==history:return
	history.clear_history();history.free()

func _exit_tree()->void:
	# The live timeline owns its current history; the tab bar owns retained
	# inactive histories. UndoRedo is Object, not RefCounted.
	var retained:=documents.duplicate();documents.clear()
	for document in retained:_release_document_history(document)


func _capture_current() -> void:
	if _switching or timeline == null or _active_index < 0 or _active_index >= documents.size():
		return
	var document := documents[_active_index]
	if document.get("type","")=="transformation":
		document.state=transformation_workspace.capture_state(); document.path=transformation_workspace.path; document.dirty=transformation_workspace.session.dirty
	elif str(document.get("type", "scene"))=="model":
		document.state=model_workspace.capture_state()
		document.path=model_workspace.path
		document.dirty=model_workspace.session.dirty
	elif str(document.get("type", "scene")) == "shader":
		if shader_workspace != null:
			document.state = shader_workspace.capture_state()
			document.source = document.state.source
			document.path = document.state.path
			document.identity = _shader_identity(document.source)
	elif str(document.get("type", "scene")) == "image":
		if image_workspace != null:
			document.state = image_workspace.capture_state()
			document.source = image_workspace.source
			document.path = image_workspace.path
			document.identity = _image_identity(document.source)
	elif str(document.get("type", "scene")) == "audio":
		if audio_workspace != null:
			document.state = audio_workspace.capture_state()
			document.source = audio_workspace.source
			document.path = audio_workspace.path
			document.identity = _audio_identity(document.source)
	else:
		document.scene = timeline.capture_scene_data(false)
		document.scene.set_meta(AUDIO_SCENE_UID_META, str(document.get("persistent_id", "")))
		document.history = timeline.model.history
	documents[_active_index] = document


func _active_scene_changed() -> void:
	if _switching or _active_index < 0 or _active_index >= documents.size():
		return
	var document := documents[_active_index]
	if str(document.get("type", "scene")) != "scene": return
	document.dirty = true
	documents[_active_index] = document
	_refresh_titles()


func _add_document(scene: ActorSceneData, path: String, title: String, history: UndoRedo) -> void:
	var persistent_id := str(scene.get_meta(AUDIO_SCENE_UID_META, ""))
	var persistent_saved := not path.is_empty() and not persistent_id.is_empty() and persistent_id.length() <= 128
	if persistent_id.is_empty() or persistent_id.length() > 128: persistent_id = ActorData.new_id()
	scene.set_meta(AUDIO_SCENE_UID_META, persistent_id)
	documents.append({"id": ActorData.new_id(), "persistent_id": persistent_id, "persistent_saved": persistent_saved, "type": "scene", "scene": scene, "path": path, "name": title, "history": history, "dirty": false})
	_switching = true
	add_tab(title, preload("res://Workspaces/SceneWorkspace/Icon.png"))
	if tab_count > documents.size():
		move_tab(tab_count - 1, documents.size() - 1)
	_ensure_new_tab()
	_switching = false


func _ensure_new_tab() -> void:
	if tab_count == documents.size():
		add_tab("", preload("res://resources/Images/BasicImages/Plus.png"))
	set_tab_tooltip(documents.size(), "Create a scene, model, shader, image, transformation image, or audio tab")


func _blank_scene() -> ActorSceneData:
	var scene := ActorSceneData.new()
	var section := ActorSection.new()
	scene.sections.append(section)
	scene.selected_section_id = section.id
	scene.inspector_state = ActorInspectorState.new()
	return scene


func _new_untitled_name() -> String:
	var result := "Untitled %d" % _untitled_counter
	_untitled_counter += 1
	return result


func _refresh_titles() -> void:
	for index in mini(documents.size(), tab_count):
		var document := documents[index]
		set_tab_title(index, str(document.name) + ("  •" if document.dirty else ""))
		var fallback := "Unsaved " + str(document.get("type", "scene"))
		set_tab_tooltip(index, str(document.path) if not str(document.path).is_empty() else fallback)


func _filesystem_resource_opened(path: String) -> void:
	if path.get_extension().to_lower() in AudioWorkspaceScript.AUDIO_EXTENSIONS:
		open_audio(path)
		return
	if path.get_extension().to_lower() in ImageWorkspaceScript.IMAGE_EXTENSIONS:
		open_image(path)
		return
	if path.get_extension().to_lower() not in ["tres", "res"]:
		return
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource is ActorSceneData:
		open_scene(path)
	elif resource is KiwiAudioDocument:
		open_audio(path)
	elif resource is KiwiImageDocument:
		open_image(path)
	elif resource is KiwiModelDocument:
		open_model(path)
	elif resource is KiwiTransformationImage2D:
		open_transformation(path)


func _show_new_tab_menu() -> void:
	_switching = true
	current_tab = maxi(0, _active_index)
	_switching = false
	var popup := PopupPanel.new()
	add_child(popup)
	popup.add_theme_stylebox_override("panel", _tab_style(Color("101a24"), Color("48657a")))
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(320, 0)
	column.add_theme_constant_override("separation", 8)
	popup.add_child(column)
	var title := Label.new()
	title.text = "CREATE NEW TAB"
	title.add_theme_color_override("font_color", Color("74dec7"))
	column.add_child(title)
	var scene := _new_tab_choice("▣  Scene", "Edit actors, animation, timeline, and export")
	column.add_child(scene)
	scene.pressed.connect(func(): popup.queue_free(); new_scene())
	var shader := _new_tab_choice("◆  Shader Editor", "Write shaders with a live mesh and environment preview")
	column.add_child(shader)
	shader.pressed.connect(func(): popup.queue_free(); new_shader())
	var image_button := _new_tab_choice("▣  Image Editor", "Draw, crop, transform, and save project images")
	column.add_child(image_button)
	image_button.pressed.connect(func(): popup.queue_free(); new_image())
	var audio_button := _new_tab_choice("♫  Audio Workspace", "Edit waveforms, arrange music, record, mix, and export")
	column.add_child(audio_button)
	audio_button.pressed.connect(func(): popup.queue_free(); new_audio())
	var model_button := _new_tab_choice("◇  3D Modeling", "Create and edit mesh geometry, components, and modifiers")
	column.add_child(model_button)
	model_button.pressed.connect(func(): popup.queue_free(); new_model())
	var transformation_button := _new_tab_choice("◈  Transformation Image 2D", "Draw independent states, morph, and animate components")
	column.add_child(transformation_button); transformation_button.pressed.connect(func(): popup.queue_free(); new_transformation())
	popup.popup_centered(Vector2i(380, 450))


func _new_tab_choice(label: String, description: String) -> Button:
	var button := Button.new()
	button.text = label + "\n" + description
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 58
	button.add_theme_stylebox_override("normal", _tab_style(Color("172633"), Color("334e62")))
	button.add_theme_stylebox_override("hover", _tab_style(Color("235045"), Color("68ddc4")))
	return button


func _shader_identity(source: Variant) -> String:
	if source is String: return str(source).replace("\\", "/").simplify_path()
	if source is Shader: return "embedded:" + str(source.get_instance_id())
	return ""


func _image_identity(value: Variant) -> String:
	if value is String:
		var normalized := str(value).replace("\\", "/").simplify_path()
		if FileAccess.file_exists(normalized + ".image.tres"): normalized += ".image.tres"
		return ProjectSettings.globalize_path(normalized).replace("\\", "/").simplify_path()
	if value is Object: return "embedded:" + str(value.get_instance_id())
	return ""


func _active_image_changed() -> void:
	if _switching or _active_index < 0 or _active_index >= documents.size(): return
	var document := documents[_active_index]
	if str(document.get("type", "")) != "image": return
	document.dirty = true
	documents[_active_index] = document
	_refresh_titles()


func _image_saved(source: Variant) -> void:
	if _active_index < 0 or _active_index >= documents.size(): return
	var document := documents[_active_index]
	if str(document.get("type", "")) != "image": return
	document.source = source
	document.path = str(source) if source is String else ""
	document.identity = _image_identity(source)
	document.name = document.path.get_file() if not document.path.is_empty() else "Embedded Image"
	document.dirty = false
	documents[_active_index] = document
	_refresh_titles()
	# Actor image objects resolve file paths when evaluated. Re-evaluate and
	# refresh the inspector so both viewport textures and thumbnails update.
	var refreshed_source: Variant = image_workspace.document.output_path if not image_workspace.document.output_path.is_empty() else source
	get_tree().call_group("actor_shader_runtimes", "refresh_saved_image", refreshed_source)
	if timeline != null:
		timeline._evaluate_runtimes()
		if timeline.inspector != null:
			timeline.inspector.refresh()
			if refreshed_source is String:
				for child in timeline.inspector.fields.get_children():
					if child is ActorMediaPreview and ProjectSettings.globalize_path(str(child.path)).replace("\\", "/") == ProjectSettings.globalize_path(str(refreshed_source)).replace("\\", "/"):
						var bitmap := Image.load_from_file(str(refreshed_source))
						if bitmap != null: child.image.texture = ImageTexture.create_from_image(bitmap)


func _active_shader_changed() -> void:
	if _switching or _active_index < 0 or _active_index >= documents.size(): return
	var document := documents[_active_index]
	if str(document.get("type", "scene")) != "shader": return
	document.dirty = true
	documents[_active_index] = document
	_refresh_titles()


func _shader_saved(source: Variant) -> void:
	if _active_index < 0 or _active_index >= documents.size(): return
	var document := documents[_active_index]
	if str(document.get("type", "scene")) != "shader": return
	document.source = source
	document.path = str(source) if source is String else ""
	document.identity = _shader_identity(source)
	document.name = str(source).get_file() if source is String else shader_workspace._document_title()
	document.dirty = false
	documents[_active_index] = document
	_refresh_titles()
	for candidate in get_tree().get_nodes_in_group("shader_code_editor"):
		if candidate is ShaderCodeEditor and not (candidate as ShaderCodeEditor).dedicated_mode:
			var compact := candidate as ShaderCodeEditor
			var same_source: bool = (source is Shader and compact.current_shader == source) \
				or (source is String and compact.current_path.replace("\\", "/").simplify_path() == str(source).replace("\\", "/").simplify_path())
			if same_source:
				compact.open_shader(source)
	get_tree().call_group("actor_timeline_editors", "refresh_saved_shader", source)


func _tab_style(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	return style


func new_audio() -> void:
	open_audio(KiwiAudioDocument.from_source(null))

func open_audio(value: Variant, binding: Dictionary = {}) -> bool:
	if audio_workspace == null or not (value is String or value is AudioStream or value is KiwiAudioDocument): return false
	var origin := _audio_scene_id
	if _active_index >= 0 and _active_index < documents.size():
		var active := documents[_active_index]
		if str(active.get("type", "scene")) == "scene": origin = str(active.get("id", ""))
		elif str(active.get("type", "")) == "audio": origin = str(active.get("scene_id", origin))
	if not binding.is_empty():
		binding = binding.duplicate(true)
		if str(binding.get("scene_id", "")).is_empty(): binding.scene_id = origin
		origin = str(binding.get("scene_id", origin))
	var identity := _audio_identity(value)
	for index in documents.size():
		if str(documents[index].get("type", "")) == "audio" and str(documents[index].get("identity", "")) == identity:
			_capture_current()
			if str(documents[index].get("id", "")).is_empty(): documents[index].id = ActorData.new_id()
			if not binding.is_empty(): documents[index].binding = binding
			if not origin.is_empty(): documents[index].scene_id = origin
			_open_index(index)
			if not binding.is_empty(): _set_audio_scene_association(str(documents[index].id), origin, str(binding.get("actor_id", "")))
			return true
	var path := str(value) if value is String else ""
	var initial_state := {}
	if value is KiwiAudioDocument or (value is String and path.get_extension().to_lower() in ["tres", "res"]):
		var resolved := KiwiAudioWorkspace.resolve_document(value)
		if not str(resolved.get("error", "")).is_empty():
			audio_workspace.notice(str(resolved.error)); return false
		var edit_session := KiwiAudioEditSession.new()
		edit_session.open(resolved.document)
		initial_state = {"session": edit_session, "path": path, "document_path": path}
	_capture_current()
	var title: String = path.get_file() if not path.is_empty() else (value.title if value is KiwiAudioDocument else "Untitled Audio")
	documents.append({"id":ActorData.new_id(), "scene_id":origin, "type":"audio", "source":value, "identity":identity, "path":path, "name":title, "state":initial_state, "binding":binding, "dirty":false})
	_switching = true
	add_tab(title)
	if tab_count > documents.size(): move_tab(tab_count - 1, documents.size() - 1)
	_ensure_new_tab(); _switching = false; _open_index(documents.size() - 1)
	if not binding.is_empty(): _set_audio_scene_association(str(documents[_active_index].id), origin, str(binding.get("actor_id", "")))
	return true

func _audio_identity(value: Variant) -> String:
	if value is String: return _association_path(str(value))
	if value is Object: return "embedded:" + str(value.get_instance_id())
	return ""

func _background_audio_changed(changed_session: KiwiAudioEditSession) -> void:
	for document in documents:
		if str(document.get("type", "")) == "audio" and document.get("state", {}).get("session") == changed_session:
			document.dirty = changed_session.dirty
	_refresh_titles()

func _active_audio_changed() -> void:
	if _switching or _active_index < 0 or _active_index >= documents.size(): return
	var document := documents[_active_index]
	if str(document.get("type", "")) != "audio": return
	document.dirty = audio_workspace._dirty
	audio_workspace.set_scene_binding(not audio_workspace.session.document.scene_binding.is_empty())
	documents[_active_index] = document
	_refresh_titles()

func _audio_saved(value: Variant) -> void:
	if _active_index < 0 or _active_index >= documents.size(): return
	var document := documents[_active_index]
	if str(document.get("type", "")) != "audio": return
	document.source = value; document.path = str(value) if value is String else ""
	document.identity = _audio_identity(value)
	document.name = document.path.get_file() if not document.path.is_empty() else "Audio Composition"
	document.dirty = false
	documents[_active_index] = document
	_refresh_titles()

func _audio_document_index(id: String) -> int:
	if id.is_empty(): return -1
	for index in documents.size():
		if str(documents[index].get("id", "")) == id: return index
	return -1

func _audio_scene_index_for_id(id: String) -> int:
	var index := _audio_document_index(id)
	return index if index >= 0 and str(documents[index].get("type", "scene")) == "scene" else -1

func _confirm_audio_close(index: int) -> void:
	if index < 0 or index >= documents.size(): return
	if str(documents[index].get("id", "")).is_empty(): documents[index].id = ActorData.new_id()
	var document_id := str(documents[index].id)
	var dialog := ConfirmationDialog.new()
	dialog.title = "Unsaved audio composition"
	dialog.dialog_text = str(documents[index].name) + " has unsaved changes."
	dialog.ok_button_text = "Save"
	dialog.add_button("Discard", false, "discard")
	add_child(dialog)
	dialog.confirmed.connect(func():
		var current := _audio_document_index(document_id)
		if current < 0: dialog.queue_free(); return
		_capture_current(); _open_index(current)
		var saving_session: KiwiAudioEditSession = audio_workspace.session
		await audio_workspace.save()
		current = _audio_document_index(document_id)
		if current >= 0 and saving_session != null and not saving_session.dirty: close_scene(current, true)
		dialog.queue_free())
	dialog.custom_action.connect(func(action: StringName):
		var current := _audio_document_index(document_id)
		if action == &"discard" and current >= 0: close_scene(current, true)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(440, 150))

func _audio_to_scene(stream: AudioStream, label: String) -> void:
	if timeline == null or stream == null: return
	if _active_index < 0 or _active_index >= documents.size() or str(documents[_active_index].get("type", "")) != "audio":
		audio_workspace.notice("Return to the source audio document and send it to Scene again."); return
	var source_document := documents[_active_index]
	if str(source_document.get("id", "")).is_empty(): source_document.id = ActorData.new_id()
	var source_id := str(source_document.id)
	var association: Dictionary = audio_workspace.session.document.scene_binding
	var scene_id := str(source_document.get("scene_id", ""))
	var binding := {}
	if not association.is_empty():
		var destination := _scene_index_for_association(association)
		if destination < 0:
			var saved_path := str(association.get("scene_path", ""))
			var detail := "Open the saved destination scene and send again to update its original actor." if not saved_path.is_empty() else "The original unsaved destination scene is no longer open."
			_choose_audio_destination(stream, label, source_id, detail + (" Saved destination: " + saved_path if not saved_path.is_empty() else ""))
			return
		scene_id = str(documents[destination].id)
		if not str(association.get("actor_id", "")).is_empty(): binding = {"actor_id": str(association.actor_id)}
	if _audio_scene_index_for_id(scene_id) < 0:
		_choose_audio_destination(stream, label, source_id, "The original destination scene is closed or was never selected. Choose where to add the rendered audio.")
		return
	_place_audio_in_scene(stream, label, source_id, scene_id, binding)

func _choose_audio_destination(stream: AudioStream, label: String, source_id: String, reason: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Choose audio destination"
	dialog.ok_button_text = "Add rendered audio"
	add_child(dialog)
	var column := VBoxContainer.new(); dialog.add_child(column)
	var detail := Label.new(); detail.text = reason + " A new audio actor will be created; no actor in another scene will be replaced."
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; detail.custom_minimum_size.x = 430; column.add_child(detail)
	var choice := OptionButton.new(); column.add_child(choice)
	choice.add_item("Create a new scene"); choice.set_item_metadata(0, "")
	for document in documents:
		if str(document.get("type", "scene")) != "scene": continue
		var item := choice.item_count
		choice.add_item(str(document.get("name", "Scene")) + " [" + str(document.get("id", "")).right(6) + "]")
		choice.set_item_metadata(item, str(document.get("id", "")))
	dialog.confirmed.connect(func():
		var scene_id := str(choice.get_item_metadata(choice.selected))
		if scene_id.is_empty():
			new_scene()
			if _active_index < 0 or _active_index >= documents.size(): dialog.queue_free(); return
			scene_id = str(documents[_active_index].get("id", ""))
		_place_audio_in_scene(stream, label, source_id, scene_id, {}, true)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(500, 220))

func _place_audio_in_scene(stream: AudioStream, label: String, source_id: String, scene_id: String, binding: Dictionary, _rebind: bool = false) -> void:
	if _audio_document_index(source_id) < 0:
		audio_workspace.notice("The source audio tab was closed. No scene actor was changed."); return
	var index := _audio_scene_index_for_id(scene_id)
	if index < 0:
		audio_workspace.notice("The selected destination scene was closed. The rendered source has not replaced any actor. Send it again to choose a destination."); return
	_capture_current(); _open_index(index)
	if not binding.is_empty():
		var actor: ActorData = timeline.model.actor_for_id(str(binding.get("actor_id", "")))
		if actor == null or actor.type_id != &"audio":
			_choose_audio_destination(stream, label, source_id, "The original audio actor no longer exists in its source scene."); return
		var before: Dictionary = timeline.model.audio_snapshot(actor)
		if before.is_empty() or not before.get("clip") is ActorClip:
			audio_workspace.notice("The bound audio actor no longer has an editable clip. No source was replaced."); return
		var after := before.duplicate(true)
		after.values = actor.values.duplicate(true)
		after.values[&"audio"] = stream
		var editable_path := _audio_saved_document_path(source_id)
		if not editable_path.is_empty(): after.values[&"audio_workspace_document"] = editable_path
		else: after.values.erase(&"audio_workspace_document")
		after.offset = 0.0
		after.duration = stream.get_length() / maxf(0.05, before.clip.playback_speed)
		timeline.model.history.create_action("Update from Audio Workspace")
		timeline.model.history.add_do_method(timeline.model.restore_audio.bind(after))
		timeline.model.history.add_undo_method(timeline.model.restore_audio.bind(before))
		timeline.model.history.commit_action()
		return
	var definition := timeline.registry.get_definition(&"audio")
	if definition == null:
		audio_workspace.notice("The scene audio actor definition is unavailable."); return
	var initial_values := {&"audio": stream}
	var editable_path := _audio_saved_document_path(source_id)
	if not editable_path.is_empty(): initial_values[&"audio_workspace_document"] = editable_path
	var clip: ActorClip = timeline.model.create_actor(definition, timeline.canvas.playhead, initial_values)
	if clip != null:
		timeline.model.actor_for_id(clip.actor_id).display_name = label
		timeline.model.changed.emit()
		var source_index := _audio_document_index(source_id)
		if source_index >= 0:
			documents[source_index].scene_id = scene_id
			_set_audio_scene_association(source_id, scene_id, clip.actor_id)

# Associations persist only stable IDs and a path. A saved resource never causes
# an implicit file open or an update to a merely similarly named actor/scene.
static func _association_path(path: String) -> String:
	if path.is_empty(): return ""
	var normalized := ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path()
	return normalized.to_lower() if OS.get_name() == "Windows" else normalized

func _audio_session_for_index(index: int) -> KiwiAudioEditSession:
	if index < 0 or index >= documents.size() or str(documents[index].get("type", "")) != "audio": return null
	if index == _active_index and audio_workspace != null: return audio_workspace.session
	return documents[index].get("state", {}).get("session") as KiwiAudioEditSession

func _scene_index_for_association(association: Dictionary) -> int:
	var uid := str(association.get("scene_uid", ""))
	if uid.is_empty(): return -1
	var path := _association_path(str(association.get("scene_path", "")))
	var found := -1
	for index in documents.size():
		var candidate := documents[index]
		if str(candidate.get("type", "scene")) != "scene" or str(candidate.get("persistent_id", "")) != uid: continue
		if not path.is_empty() and _association_path(str(candidate.get("path", ""))) != path: continue
		if found >= 0: return -1 # Duplicated scene IDs must not pick an arbitrary tab.
		found = index
	return found

func _set_audio_scene_association(source_id: String, scene_id: String, actor_id: String) -> void:
	var source_index := _audio_document_index(source_id)
	var scene_index := _audio_scene_index_for_id(scene_id)
	var edit_session := _audio_session_for_index(source_index)
	if scene_index < 0 or edit_session == null: return
	var destination := documents[scene_index]
	var association := {"version": 1, "scene_uid": str(destination.get("persistent_id", "")),
		"scene_path": _stored_scene_path(str(destination.get("path", ""))), "actor_id": actor_id}
	if str(association.scene_uid).is_empty(): return
	if edit_session.document.scene_binding != association:
		edit_session.action("Link audio to scene", func(): edit_session.document.scene_binding = association.duplicate(true))
	documents[source_index].scene_id = scene_id
	# A pre-existing scene without the identity metadata must be saved as well.
	if not bool(destination.get("persistent_saved", false)): documents[scene_index].dirty = true
	if source_index == _active_index: audio_workspace.set_scene_binding(true)
	_refresh_titles()

func _relocate_audio_associations(uid: String, previous_path: String, destination: String) -> void:
	if uid.is_empty(): return
	var old_path := _association_path(previous_path)
	var new_path := _association_path(destination)
	for index in documents.size():
		var edit_session := _audio_session_for_index(index)
		if edit_session == null: continue
		var association := edit_session.document.scene_binding
		if str(association.get("scene_uid", "")) != uid: continue
		if _association_path(str(association.get("scene_path", ""))) != old_path: continue
		if old_path == new_path: continue
		var updated := association.duplicate(true)
		updated.scene_path = _stored_scene_path(destination)
		edit_session.action("Update linked scene path", func(): edit_session.document.scene_binding = updated.duplicate(true))
		# Saving the scene does not silently overwrite any audio composition.
		documents[index].dirty = true

static func _stored_scene_path(path: String) -> String:
	if path.is_empty(): return ""
	return ProjectSettings.localize_path(ProjectSettings.globalize_path(path)).replace("\\", "/").simplify_path()

func _audio_saved_document_path(source_id: String) -> String:
	var index := _audio_document_index(source_id)
	if index < 0: return ""
	var path := str(audio_workspace.document_path) if index == _active_index else str(documents[index].get("state", {}).get("document_path", ""))
	if path.get_extension().to_lower() not in ["tres", "res"] or not FileAccess.file_exists(path): return ""
	return _stored_scene_path(path)

func open_audio_actor(actor: ActorData) -> bool:
	if actor == null or actor.type_id != &"audio": return false
	# An explicit Scene > Edit Audio command may reopen its saved editable
	# composition. Merely loading a scene never opens this referenced resource.
	var path := str(actor.values.get(&"audio_workspace_document", ""))
	if path.length() <= 4096 and path.get_extension().to_lower() in ["tres", "res"] and FileAccess.file_exists(path):
		if open_audio(path, {"actor_id": actor.id}): return true
	var opened := open_audio(actor.get_value(&"audio"), {"actor_id": actor.id})
	if opened and not path.is_empty(): audio_workspace.notice("The linked editable composition could not be opened. The rendered audio was opened instead; its original source has not been changed.")
	return opened
