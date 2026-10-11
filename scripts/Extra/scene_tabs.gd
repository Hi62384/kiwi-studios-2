class_name ActorSceneTabs
extends TabBar
## Keeps multiple editable ActorSceneData documents alive in one workspace.

const ShaderWorkspaceScript = preload("res://Workspaces/ShaderWorkspace/shader_workspace.gd")
const ImageWorkspaceScript = preload("res://Workspaces/ImageWorkspace/image_workspace.gd")

var timeline: ActorTimelineEditor
var scene_workspace: Control
var shader_workspace: Control
var image_workspace: Control
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
	if not discard_changes and str(documents[index].get("type", "")) == "image" and bool(documents[index].get("dirty", false)):
		_confirm_image_close(index)
		return
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
	var error := ResourceSaver.save(scene, destination)
	if error != OK:
		return error
	document.path = destination
	document.name = destination.get_file().get_basename()
	document.dirty = false
	documents[_active_index] = document
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
	if str(document.get("type", "scene")) == "shader":
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
	else:
		if shader_workspace != null: shader_workspace.visible = false
		if image_workspace != null: image_workspace.visible = false
		if scene_workspace != null: scene_workspace.visible = true
		timeline.restore_scene_data(document.scene)
		timeline.model.history = document.history
	_active_index = index
	_switching = false
	_refresh_titles()


func _capture_current() -> void:
	if _switching or timeline == null or _active_index < 0 or _active_index >= documents.size():
		return
	var document := documents[_active_index]
	if str(document.get("type", "scene")) == "shader":
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
	else:
		document.scene = timeline.capture_scene_data(false)
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
	documents.append({"type": "scene", "scene": scene, "path": path, "name": title, "history": history, "dirty": false})
	_switching = true
	add_tab(title, preload("res://Workspaces/SceneWorkspace/Icon.png"))
	if tab_count > documents.size():
		move_tab(tab_count - 1, documents.size() - 1)
	_ensure_new_tab()
	_switching = false


func _ensure_new_tab() -> void:
	if tab_count == documents.size():
		add_tab("", preload("res://resources/Images/BasicImages/Plus.png"))
	set_tab_tooltip(documents.size(), "Create a scene, shader, or image editor tab")


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
	if path.get_extension().to_lower() in ImageWorkspaceScript.IMAGE_EXTENSIONS:
		open_image(path)
		return
	if path.get_extension().to_lower() not in ["tres", "res"]:
		return
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource is ActorSceneData:
		open_scene(path)
	elif resource is KiwiImageDocument:
		open_image(path)


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
	popup.popup_centered(Vector2i(360, 245))


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
