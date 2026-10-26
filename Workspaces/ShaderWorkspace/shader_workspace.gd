class_name KiwiShaderWorkspace
extends Control
## Full-document shader authoring workspace used by top-level editor tabs.

signal document_changed
signal shader_saved(source: Variant)

var editor := ShaderCodeEditor.new()
var viewport := SubViewport.new()
var viewport_display := TextureRect.new()
var preview_root := Node3D.new()
var mesh_holder := Node3D.new()
var camera_rig := Node3D.new()
var camera := Camera3D.new()
var environment_node := WorldEnvironment.new()
var preview_shader := Shader.new()
var spatial_material := ShaderMaterial.new()
var sky_material := ShaderMaterial.new()
var canvas_material := ShaderMaterial.new()
var fog_preview_material := ShaderMaterial.new()
var fog_preview := FogVolume.new()
var particle_preview := GPUParticles3D.new()
var particle_material := ShaderMaterial.new()
var fog_preview_guide := MeshInstance3D.new()
var canvas_preview := TextureRect.new()
var canvas_preview_background := TextureRect.new()
var current_source: Variant
var current_path := ""
var shader_kind := "spatial"
var shape_picker := OptionButton.new()
var mesh_label := Label.new()
var mesh_group: VBoxContainer
var environment_group: VBoxContainer
var canvas_image_group: VBoxContainer
var canvas_image_label := Label.new()
var shader_type_label := Label.new()
var save_button: Button
var save_as_button: Button
var load_shader_button: Button
var status := Label.new()
var parameters_panel := PanelContainer.new()
var parameters_list := VBoxContainer.new()
var parameter_code_split := VSplitContainer.new()
var parameter_values: Dictionary = {}
var parameter_link := CheckButton.new()
var linked_parameter_reader: Callable
var linked_parameter_writer: Callable
var parameters_linked := false
var parameter_expanded: Dictionary = {}
var registry := ActorRegistry.new()
var _loading := false
var _looking := false
var _last_mouse := Vector2.ZERO
var _mesh_mode := "shape"
var _mesh_path := ""
var _environment_path := ""
var _canvas_image_path := ""
var requires_path := false
var camera_speed := 3.0
var _studio_panorama_texture: Texture2D

const STUDIO_PANORAMA_PATH := "res://resources/environments/ShaderStudioPanorama.png"


func _ready() -> void:
	BasicActors.register_all(registry)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_build_preview()
	visibility_changed.connect(_sync_preview_visibility)
	_sync_preview_visibility()
	set_process(true)


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0c141d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var root := VBoxContainer.new()
	root.name = "ShaderWorkspaceRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var toolbar := PanelContainer.new()
	toolbar.add_theme_stylebox_override("panel", _box(Color("15222e"), Color("355064"), 9))
	root.add_child(toolbar)
	var toolbar_row := HBoxContainer.new()
	toolbar_row.add_theme_constant_override("separation", 8)
	toolbar.add_child(toolbar_row)
	var mark := Label.new()
	mark.text = "◆  SHADER WORKSPACE"
	mark.add_theme_color_override("font_color", Color("72e0c8"))
	mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar_row.add_child(mark)
	shader_type_label.text = "SPATIAL"
	shader_type_label.add_theme_color_override("font_color", Color("9cb7c9"))
	toolbar_row.add_child(shader_type_label)
	var library_button := _button("Shader Library", false)
	library_button.tooltip_text = "Browse rendered shader samples and starter templates"
	library_button.pressed.connect(func(): editor.documentation.open_samples())
	toolbar_row.add_child(library_button)
	load_shader_button = _button("Load Shader…", false)
	load_shader_button.tooltip_text = "Open a .gdshader file from the project"
	load_shader_button.pressed.connect(_choose_shader_file)
	toolbar_row.add_child(load_shader_button)
	save_button = _button("Save", true)
	save_button.tooltip_text = "Save shader  ·  Ctrl+S"
	save_button.pressed.connect(save)
	toolbar_row.add_child(save_button)
	save_as_button = _button("Save As…", false)
	save_as_button.tooltip_text = "Save a copy  ·  Ctrl+Shift+S"
	save_as_button.pressed.connect(save_as)
	toolbar_row.add_child(save_as_button)
	var clipboard_button:=_button("Clipboard ▾",false); toolbar_row.add_child(clipboard_button)
	var clipboard_menu:=PopupMenu.new(); clipboard_button.add_child(clipboard_menu); clipboard_menu.add_item("Save shader to Super Clipboard",0); clipboard_menu.add_item("Open Super Clipboard · F8",1)
	clipboard_button.pressed.connect(func(): clipboard_menu.position=Vector2i(clipboard_button.get_screen_position()+Vector2(0,clipboard_button.size.y)); clipboard_menu.popup())
	clipboard_menu.id_pressed.connect(func(id: int):
		if id==0:
			var shader:=Shader.new(); shader.code=editor.code.text; KiwiSuperClipboardService.instance.quick_save(shader,_document_title())
		else: KiwiSuperClipboardService.instance.toggle())
	var preview_tools := PanelContainer.new()
	preview_tools.name = "PreviewSettings"
	preview_tools.custom_minimum_size.y = 82
	preview_tools.add_theme_stylebox_override("panel", _box(Color("121d27"), Color("2e4558"), 8))
	root.add_child(preview_tools)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 12)
	preview_tools.add_child(tools)
	mesh_group = VBoxContainer.new()
	mesh_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mesh_group.add_theme_constant_override("separation", 4)
	tools.add_child(mesh_group)
	var mesh_title := Label.new()
	mesh_title.text = "PREVIEW MESH"
	mesh_title.add_theme_color_override("font_color", Color("8caabc"))
	mesh_group.add_child(mesh_title)
	var mesh_row := HBoxContainer.new()
	mesh_row.add_theme_constant_override("separation", 7)
	mesh_group.add_child(mesh_row)
	shape_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label in ["Sphere", "Box", "Cylinder", "Plane", "Capsule", "Prism", "Torus"]: shape_picker.add_item(label)
	shape_picker.item_selected.connect(func(_index: int): _mesh_mode = "shape"; _rebuild_mesh(); document_changed.emit())
	mesh_row.add_child(shape_picker)
	var load_mesh := _button("Load mesh…", false)
	load_mesh.pressed.connect(_choose_mesh)
	mesh_row.add_child(load_mesh)
	mesh_label.text = "Basic shape · Sphere"
	mesh_label.custom_minimum_size.x = 160
	mesh_label.clip_text = true
	mesh_label.add_theme_color_override("font_color", Color("a6bdca"))
	mesh_row.add_child(mesh_label)
	var divider := VSeparator.new()
	tools.add_child(divider)
	environment_group = VBoxContainer.new()
	environment_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	environment_group.add_theme_constant_override("separation", 4)
	tools.add_child(environment_group)
	var environment_title := Label.new()
	environment_title.text = "PREVIEW ENVIRONMENT"
	environment_title.add_theme_color_override("font_color", Color("8caabc"))
	environment_group.add_child(environment_title)
	var environment_row := HBoxContainer.new()
	environment_row.add_theme_constant_override("separation", 7)
	environment_group.add_child(environment_row)
	var studio := _button("Studio HDRI", false)
	studio.pressed.connect(func(): _environment_path = ""; _apply_environment(); document_changed.emit())
	environment_row.add_child(studio)
	var load_environment := _button("Load environment…", false)
	load_environment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_environment.pressed.connect(_choose_environment)
	environment_row.add_child(load_environment)
	canvas_image_group = VBoxContainer.new()
	canvas_image_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_image_group.add_theme_constant_override("separation", 4)
	canvas_image_group.hide()
	tools.add_child(canvas_image_group)
	var canvas_title := Label.new()
	canvas_title.text = "CANVAS PREVIEW IMAGE"
	canvas_title.add_theme_color_override("font_color", Color("8caabc"))
	canvas_image_group.add_child(canvas_title)
	var canvas_row := HBoxContainer.new()
	canvas_row.add_theme_constant_override("separation", 7)
	canvas_image_group.add_child(canvas_row)
	var default_canvas := _button("Default image", false)
	default_canvas.pressed.connect(func():
		_canvas_image_path = ""
		_update_canvas_texture()
		document_changed.emit())
	canvas_row.add_child(default_canvas)
	var load_canvas := _button("Load image…", true)
	load_canvas.pressed.connect(_choose_canvas_image)
	canvas_row.add_child(load_canvas)
	canvas_image_label.text = "Built-in color test image"
	canvas_image_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_image_label.clip_text = true
	canvas_image_label.add_theme_color_override("font_color", Color("a6bdca"))
	canvas_row.add_child(canvas_image_label)
	var split := HSplitContainer.new()
	split.name = "ShaderWorkspaceSplit"
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 820
	root.add_child(split)
	var preview_column := VBoxContainer.new()
	preview_column.name = "ViewportColumn"
	preview_column.custom_minimum_size.x = 560
	preview_column.add_theme_constant_override("separation", 8)
	split.add_child(preview_column)
	viewport_display.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	viewport_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	viewport_display.texture = viewport.get_texture()
	viewport_display.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport_display.focus_mode = Control.FOCUS_ALL
	viewport_display.gui_input.connect(_viewport_input)
	viewport_display.tooltip_text = "Right-drag to look · WASD move · Q/E down/up · wheel changes speed"
	preview_column.add_child(viewport_display)
	status.text = _viewport_help()
	status.add_theme_color_override("font_color", Color("7897aa"))
	preview_column.add_child(status)
	parameter_code_split.name = "ShaderSideColumn"
	parameter_code_split.custom_minimum_size.x = 390
	parameter_code_split.split_offset = 185
	split.add_child(parameter_code_split)
	_build_parameters_section(parameter_code_split)
	var code_panel := PanelContainer.new()
	code_panel.name = "ShaderCodePanel"
	code_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code_panel.add_theme_stylebox_override("panel", _box(Color("101923"), Color("30495c"), 9))
	parameter_code_split.add_child(code_panel)
	editor.auto_save_enabled = false
	editor.dedicated_mode = true
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code_panel.add_child(editor)
	editor.code.text_changed.connect(_code_changed)
	editor.save_shortcut_requested.connect(func(save_as_requested: bool):
		if save_as_requested: save_as()
		else: save())
	editor.code.placeholder_text = "Write a spatial, canvas_item, sky, fog, or particles shader."


func _build_preview() -> void:
	viewport.name = "ShaderPreviewViewport"
	viewport.size = Vector2i(960, 540)
	# A private World3D is essential: otherwise this preview's mesh and
	# environment leak into whichever scene tab shares the parent viewport.
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	viewport.add_child(preview_root)
	canvas_preview_background.name = "ScreenShaderInputImage"
	canvas_preview_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	canvas_preview_background.stretch_mode = TextureRect.STRETCH_SCALE
	canvas_preview_background.size = Vector2(viewport.size)
	canvas_preview_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_preview_background.hide()
	viewport.add_child(canvas_preview_background)
	canvas_preview.name = "CanvasPreviewImage"
	canvas_preview.position = Vector2.ZERO
	canvas_preview.size = Vector2(viewport.size)
	canvas_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	canvas_preview.stretch_mode = TextureRect.STRETCH_SCALE
	canvas_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_preview.hide()
	viewport.add_child(canvas_preview)
	preview_root.add_child(mesh_holder)
	fog_preview.name = "FogShaderPreviewVolume"
	fog_preview.shape = 3
	fog_preview.size = Vector3(3.6, 3.6, 3.6)
	fog_preview.visible = false
	preview_root.add_child(fog_preview)
	particle_preview.name = "ParticleShaderPreview"
	particle_preview.amount = 180
	particle_preview.lifetime = 3.0
	particle_preview.preprocess = 1.8
	particle_preview.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	particle_preview.draw_pass_1 = preload("res://Workspaces/ShaderWorkspace/shader_sample_preview.gd").particle_draw_mesh()
	particle_preview.visible = false
	particle_preview.emitting = false
	preview_root.add_child(particle_preview)
	var guide_mesh := ImmediateMesh.new()
	var guide_paint := StandardMaterial3D.new()
	guide_paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	guide_paint.albedo_color = Color("79d9e8")
	guide_paint.no_depth_test = true
	guide_mesh.surface_begin(Mesh.PRIMITIVE_LINES, guide_paint)
	for axis in 3:
		for first in [-1.0, 1.0]:
			for second in [-1.0, 1.0]:
				var a := Vector3.ZERO
				var b := Vector3.ZERO
				a[axis] = -1.8
				b[axis] = 1.8
				a[(axis + 1) % 3] = first * 1.8
				b[(axis + 1) % 3] = first * 1.8
				a[(axis + 2) % 3] = second * 1.8
				b[(axis + 2) % 3] = second * 1.8
				guide_mesh.surface_add_vertex(a)
				guide_mesh.surface_add_vertex(b)
	guide_mesh.surface_end()
	fog_preview_guide.name = "FogPreviewBounds"
	fog_preview_guide.mesh = guide_mesh
	fog_preview_guide.visible = false
	preview_root.add_child(fog_preview_guide)
	camera_rig.position = Vector3(0, 0.45, 4.2)
	preview_root.add_child(camera_rig)
	camera_rig.add_child(camera)
	camera.current = true
	camera.fov = 50
	preview_root.add_child(environment_node)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -35, 0)
	key.light_energy = 2.2
	key.shadow_enabled = true
	preview_root.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(35, 145, 0)
	fill.light_energy = 0.75
	fill.light_color = Color("9dc9ff")
	preview_root.add_child(fill)
	spatial_material.shader = preview_shader
	sky_material.shader = preview_shader
	canvas_material.shader = preview_shader
	fog_preview_material.shader = preview_shader
	particle_material.shader = preview_shader
	_update_canvas_texture()
	_apply_environment()
	_rebuild_mesh()


func open_source(source: Variant, state: Dictionary = {}, binding: Dictionary = {}) -> void:
	_loading = true
	current_source = source
	current_path = str(state.get("path", source if source is String else ""))
	requires_path = bool(state.get("requires_path", false))
	load_shader_button.visible = requires_path and current_path.is_empty()
	if state.has("code"):
		editor.code.text = str(state.code)
	elif source is Shader:
		editor.code.text = source.code
	else:
		var file := FileAccess.open(current_path, FileAccess.READ)
		editor.code.text = file.get_as_text() if file != null else "shader_type spatial;\n\nvoid fragment() {\n    ALBEDO = vec3(0.7);\n}\n"
	editor.current_shader = source as Shader if source is Shader else null
	editor.current_path = current_path
	editor.title.text = _document_title()
	shape_picker.select(clampi(int(state.get("shape", 0)), 0, shape_picker.item_count - 1))
	_mesh_mode = str(state.get("mesh_mode", "shape"))
	_mesh_path = str(state.get("mesh_path", ""))
	_environment_path = str(state.get("environment_path", ""))
	_canvas_image_path = str(state.get("canvas_image_path", ""))
	linked_parameter_reader = binding.get("reader", Callable()) as Callable
	linked_parameter_writer = binding.get("writer", Callable()) as Callable
	parameter_link.visible = linked_parameter_reader.is_valid() and linked_parameter_writer.is_valid()
	parameters_linked = parameter_link.visible and bool(state.get("parameters_linked", true))
	parameter_link.set_pressed_no_signal(parameters_linked)
	if parameters_linked:
		var linked_values: Variant = linked_parameter_reader.call()
		parameter_values = linked_values.duplicate(true) if linked_values is Dictionary else {}
	else:
		parameter_values = (state.get("parameters", {}) as Dictionary).duplicate(true)
	parameter_code_split.split_offset = int(state.get("parameter_split", 185))
	if state.has("camera_transform"): camera_rig.transform = state.camera_transform
	_loading = false
	_apply_environment()
	_rebuild_mesh()
	_code_changed()
	editor.code.grab_focus()


func capture_state() -> Dictionary:
	return {"code": editor.code.text, "path": current_path, "source": current_source,
		"shape": shape_picker.selected, "mesh_mode": _mesh_mode, "mesh_path": _mesh_path,
		"environment_path": _environment_path, "camera_transform": camera_rig.transform,
		"canvas_image_path": _canvas_image_path,
		"parameter_split": parameter_code_split.split_offset,
		"parameters": parameter_values.duplicate(true), "parameters_linked": parameters_linked,
		"requires_path": requires_path}


func save() -> void:
	if requires_path:
		await save_as()
		return
	_commit_linked_parameters()
	if current_path.is_empty():
		if current_source is Shader:
			current_source.code = editor.code.text
			current_source.emit_changed()
			shader_saved.emit(current_source)
			status.text = "Saved embedded shader"
			return
		await save_as()
		return
	var file := FileAccess.open(current_path, FileAccess.WRITE)
	if file == null:
		status.text = "Could not write shader file."
		return
	file.store_string(editor.code.text)
	file.flush()
	file.close()
	ResourceLoader.load(current_path, "", ResourceLoader.CACHE_MODE_REPLACE)
	shader_saved.emit(current_path)
	status.text = "Saved · " + current_path.get_file()


func _commit_linked_parameters() -> void:
	if not parameters_linked or not linked_parameter_writer.is_valid():
		return
	# Individual controls normally write live. Saving deliberately flushes the
	# complete snapshot as well, covering controls which still own keyboard focus
	# and scene restoration which may have replaced their original material.
	for key: Variant in parameter_values:
		linked_parameter_writer.call(StringName(key), ActorData.copy_value(parameter_values[key]), "edit", null)


func save_as() -> void:
	var clipboard_shader:=Shader.new(); clipboard_shader.code=editor.code.text
	var result := await ActorProjectResourceSaveDialog.pick(self, "Save shader to project",
		_document_title().get_basename(), "gdshader", false,PackedStringArray(),clipboard_shader)
	if result.get("cancelled", true): return
	# Save As creates a filesystem copy, but an actor-owned embedded shader must
	# still receive the code the user just saved.
	if current_source is Shader:
		current_source.code = editor.code.text
		current_source.emit_changed()
	current_path = str(result.get("path", ""))
	if current_path.is_empty(): return
	current_source = current_path
	requires_path = false
	load_shader_button.hide()
	editor.current_shader = null
	editor.current_path = current_path
	editor.title.text = current_path.get_file()
	await save()


func _code_changed() -> void:
	if _loading: return
	shader_kind = _shader_type(editor.code.text)
	shader_type_label.text = shader_kind.to_upper() + " SHADER"
	# Replacing both Shader and ShaderMaterial is deliberate. It forces the
	# renderer to discard a failed/old program and makes a corrected spatial
	# shader visible immediately instead of waiting for another property edit.
	preview_shader = Shader.new()
	preview_shader.code = editor.code.text
	_rebind_preview_materials()
	_update_preview_mode()
	_apply_environment()
	_apply_materials()
	call_deferred("_rebuild_parameters")
	document_changed.emit()


func _rebind_preview_materials() -> void:
	spatial_material = ShaderMaterial.new()
	spatial_material.shader = preview_shader
	sky_material = ShaderMaterial.new()
	sky_material.shader = preview_shader
	canvas_material = ShaderMaterial.new()
	canvas_material.shader = preview_shader
	fog_preview_material = ShaderMaterial.new()
	fog_preview_material.shader = preview_shader
	particle_material = ShaderMaterial.new()
	particle_material.shader = preview_shader
	for name: Variant in parameter_values:
		var value: Variant = _preview_parameter_value(parameter_values[name])
		spatial_material.set_shader_parameter(StringName(name), value)
		sky_material.set_shader_parameter(StringName(name), value)
		canvas_material.set_shader_parameter(StringName(name), value)
		fog_preview_material.set_shader_parameter(StringName(name), value)
		particle_material.set_shader_parameter(StringName(name), value)


func _preview_parameter_value(value: Variant) -> Variant:
	if value is Texture2D:
		return value
	if value is ActorObjectReference:
		var object := (value as ActorObjectReference).resolve(func(path: String):
			return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData)
		return ActorImageGenerator.texture_for_object(object)
	if value is ActorObjectData:
		return ActorImageGenerator.texture_for_object(value)
	if value is String and not value.is_empty():
		var resource := ResourceLoader.load(value, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource is Texture2D:
			return resource
		if resource is ActorObjectData:
			return ActorImageGenerator.texture_for_object(resource)
	return value


func _shader_type(source: String) -> String:
	var found := RegEx.create_from_string("(?m)^\\s*shader_type\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*;").search(source)
	return found.get_string(1) if found != null else "spatial"


func _apply_materials() -> void:
	for node in mesh_holder.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = spatial_material if shader_kind == "spatial" else null
	canvas_preview.material = canvas_material if shader_kind == "canvas_item" else null
	fog_preview.material = fog_preview_material if shader_kind == "fog" else null
	particle_preview.process_material = particle_material if shader_kind == "particles" else null


func _update_preview_mode() -> void:
	var canvas_mode := shader_kind == "canvas_item"
	var fog_mode := shader_kind == "fog"
	preview_root.visible = not canvas_mode
	mesh_holder.visible = shader_kind == "spatial"
	particle_preview.visible = shader_kind == "particles"
	particle_preview.emitting = shader_kind == "particles"
	fog_preview.visible = fog_mode
	fog_preview_guide.visible = fog_mode
	canvas_preview.visible = canvas_mode
	canvas_preview_background.visible = canvas_mode and editor.code.text.contains("hint_screen_texture")
	mesh_group.visible = shader_kind == "spatial"
	environment_group.visible = not canvas_mode
	canvas_image_group.visible = canvas_mode
	viewport_display.tooltip_text = "Canvas shader preview" if canvas_mode else "Fog volume preview · fly around its bounds" if fog_mode else "Right-drag to look · WASD move · Q/E down/up · wheel changes speed"
	status.text = "CanvasItem preview · choose any project image above" if canvas_mode else "Fog volume preview · volumetric fog enabled" if fog_mode else _viewport_help()
	if canvas_mode:
		_update_canvas_texture()
	elif shader_kind == "particles":
		status.text = "Particle process shader preview - drag to inspect the simulated particles"
	_sync_preview_visibility()


func _sync_preview_visibility() -> void:
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	particle_preview.speed_scale = 1.0 if is_visible_in_tree() else 0.0


func _apply_environment() -> void:
	var environment: Environment
	if not _environment_path.is_empty():
		environment = ResourceLoader.load(_environment_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Environment
	if environment == null:
		environment = Environment.new()
		environment.background_mode = Environment.BG_SKY
		var sky := Sky.new()
		var panorama := PanoramaSkyMaterial.new()
		panorama.panorama = _studio_panorama()
		panorama.energy_multiplier = 0.9
		sky.sky_material = panorama
		environment.sky = sky
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
		environment.ambient_light_energy = 0.7
	if shader_kind == "fog":
		# Do not mutate a selected project Environment resource just to make the
		# authoring preview render local fog.
		environment = environment.duplicate(true)
		environment.volumetric_fog_enabled = true
		environment.volumetric_fog_density = 0.0
	if shader_kind == "sky":
		var shader_sky := Sky.new()
		shader_sky.sky_material = sky_material
		environment.sky = shader_sky
		environment.background_mode = Environment.BG_SKY
	environment_node.environment = environment


func _studio_panorama() -> Texture2D:
	if _studio_panorama_texture != null:
		return _studio_panorama_texture
	var texture: Texture2D
	if ResourceLoader.exists(STUDIO_PANORAMA_PATH, "Texture2D"):
		texture = ResourceLoader.load(STUDIO_PANORAMA_PATH, "Texture2D", ResourceLoader.CACHE_MODE_REUSE) as Texture2D
	if texture != null:
		_studio_panorama_texture = texture
		return _studio_panorama_texture
	# Also works on the first editor run before Godot has finished importing the
	# newly-added PNG into its cache.
	var image := Image.load_from_file(ProjectSettings.globalize_path(STUDIO_PANORAMA_PATH))
	_studio_panorama_texture = ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
	return _studio_panorama_texture


func _rebuild_mesh() -> void:
	for child in mesh_holder.get_children(): child.queue_free()
	if _mesh_mode == "file" and not _mesh_path.is_empty():
		var resource: Resource
		if _mesh_path.get_extension().to_lower() in ["glb", "gltf", "fbx", "obj"]:
			resource = FileOperations.load_3d_model(_mesh_path)
		else:
			resource = ResourceLoader.load(_mesh_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource is PackedScene:
			mesh_holder.add_child(resource.instantiate())
		elif resource is Mesh:
			var instance := MeshInstance3D.new()
			instance.mesh = resource
			mesh_holder.add_child(instance)
		mesh_label.text = "Project mesh · " + _mesh_path.get_file()
	else:
		_mesh_mode = "shape"
		var mesh: Mesh
		match shape_picker.selected:
			1: mesh = BoxMesh.new()
			2: mesh = CylinderMesh.new()
			3: mesh = PlaneMesh.new()
			4: mesh = CapsuleMesh.new()
			5: mesh = PrismMesh.new()
			6: mesh = TorusMesh.new()
			_: mesh = SphereMesh.new()
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		mesh_holder.add_child(instance)
		mesh_label.text = "Basic shape · " + shape_picker.get_item_text(shape_picker.selected)
	_apply_materials()


func _choose_mesh() -> void:
	var property := ActorProperty.new()
	property.id = &"preview_mesh"
	property.label = "Preview Mesh"
	property.options = {"extensions": ["glb", "gltf", "fbx", "obj", "mesh", "tres", "res"],
		"native_resource_types": ["Mesh", "PackedScene"], "file_picker": true}
	var path := await ActorProjectFilePicker.pick(self, property, "Choose preview mesh")
	if path==ActorProjectFilePicker.EMPTY_RESOURCE:
		_mesh_mode="shape"; _mesh_path=""; _rebuild_mesh(); document_changed.emit(); return
	if path.is_empty(): return
	_mesh_mode = "file"
	_mesh_path = path
	_rebuild_mesh()
	document_changed.emit()


func _choose_shader_file() -> void:
	var property := ActorProperty.new()
	property.id = &"shader_file"
	property.label = "Shader"
	property.options = {"extensions": ["gdshader"], "file_picker": true}
	var path := await ActorProjectFilePicker.pick(self, property, "Load shader from project")
	if path.is_empty() or path==ActorProjectFilePicker.EMPTY_RESOURCE: return
	var tabs := get_tree().get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs
	if tabs != null: tabs.load_shader_into_current_tab(path)


func _choose_environment() -> void:
	var property := ActorProperty.new()
	property.id = &"preview_environment"
	property.label = "Environment"
	property.options = {"extensions": ["tres", "res"], "native_resource_types": ["Environment"], "file_picker": true}
	var path := await ActorProjectFilePicker.pick(self, property, "Choose preview environment")
	if path==ActorProjectFilePicker.EMPTY_RESOURCE:
		_environment_path=""; _apply_environment(); document_changed.emit(); return
	if path.is_empty(): return
	_environment_path = path
	_apply_environment()
	document_changed.emit()


func _choose_canvas_image() -> void:
	var property := ActorProperty.new()
	property.id = &"canvas_preview_image"
	property.label = "Canvas Preview Image"
	property.options = {"extensions": ["png", "jpg", "jpeg", "webp", "bmp", "svg", "tga", "hdr", "exr", "tres", "res"],
		"native_resource_types": ["Texture2D"], "file_picker": true}
	var path := await ActorProjectFilePicker.pick(self, property, "Choose canvas preview image")
	if path==ActorProjectFilePicker.EMPTY_RESOURCE:
		_canvas_image_path=""; _update_canvas_texture(); document_changed.emit(); return
	if path.is_empty():
		return
	_canvas_image_path = path
	_update_canvas_texture()
	document_changed.emit()


func _update_canvas_texture() -> void:
	var texture: Texture2D
	if not _canvas_image_path.is_empty():
		var load_path := _godot_project_path(_canvas_image_path)
		texture = ResourceLoader.load(load_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
		if texture == null:
			var disk_path := ProjectSettings.globalize_path(load_path) if load_path.begins_with("res://") or load_path.begins_with("user://") else _canvas_image_path
			var image := Image.load_from_file(disk_path)
			if image != null and not image.is_empty():
				texture = ImageTexture.create_from_image(image)
	canvas_preview.texture = texture if texture != null else _default_canvas_texture()
	canvas_preview_background.texture = canvas_preview.texture
	_fit_canvas_preview()
	canvas_image_label.text = "Project image · " + _canvas_image_path.get_file() if texture != null else "Built-in color test image"


func _fit_canvas_preview() -> void:
	if canvas_preview.texture == null:
		return
	if editor.code.text.contains("hint_screen_texture"):
		canvas_preview.size = Vector2(viewport.size)
		canvas_preview.position = Vector2.ZERO
		return
	var source_size := canvas_preview.texture.get_size()
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return
	var available := Vector2(viewport.size) - Vector2(72, 72)
	var fit := minf(available.x / source_size.x, available.y / source_size.y)
	var fitted := source_size * fit
	canvas_preview.size = fitted
	canvas_preview.position = (Vector2(viewport.size) - fitted) * 0.5


func _godot_project_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return path
	var normalized := path.replace("\\", "/")
	var root := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	return "res://" + normalized.trim_prefix(root).trim_prefix("/") if normalized.begins_with(root + "/") else path


func _default_canvas_texture() -> Texture2D:
	if canvas_preview.has_meta("default_texture"):
		return canvas_preview.get_meta("default_texture") as Texture2D
	var image := Image.create(640, 360, false, Image.FORMAT_RGBA8)
	for y in image.get_height():
		for x in image.get_width():
			var uv := Vector2(float(x) / 639.0, float(y) / 359.0)
			var checker := 0.08 if int(x / 48 + y / 48) % 2 == 0 else 0.0
			var color := Color(0.08 + uv.x * 0.62 + checker,
				0.12 + (1.0 - uv.y) * 0.52 + checker, 0.3 + uv.y * 0.48, 1.0)
			var center := uv - Vector2(0.5, 0.5)
			if center.length() < 0.22:
				color = Color(0.94, 0.78 + center.y * 0.5, 0.24 + center.x * 0.6, 1.0)
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	canvas_preview.set_meta("default_texture", texture)
	return texture


func _build_parameters_section(parent: Control) -> void:
	parameters_panel.name = "TestParameters"
	parameters_panel.custom_minimum_size.y = 132
	parameters_panel.add_theme_stylebox_override("panel", _box(Color("121d27"), Color("2e4558"), 8))
	parent.add_child(parameters_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	parameters_panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title_label := Label.new()
	title_label.text = "TEST PARAMETERS"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_color_override("font_color", Color("8de0cb"))
	header.add_child(title_label)
	parameter_link.text = "🔗 Link material"
	parameter_link.tooltip_text = "Synchronize these preview values with the ShaderMaterial that opened this tab"
	parameter_link.visible = false
	parameter_link.toggled.connect(_parameter_link_toggled)
	header.add_child(parameter_link)
	var reset := _button("Reset", false)
	reset.custom_minimum_size.y = 26
	reset.tooltip_text = "Restore every preview uniform to its shader default"
	reset.pressed.connect(_reset_all_preview_parameters)
	header.add_child(reset)
	var scroll := ScrollContainer.new()
	scroll.name = "ParameterScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	parameters_list.name = "ParameterList"
	parameters_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parameters_list.add_theme_constant_override("separation", 4)
	scroll.add_child(parameters_list)
	var empty := Label.new()
	empty.text = "Add a uniform to test it here."
	empty.add_theme_color_override("font_color", Color("718b9e"))
	parameters_list.add_child(empty)


func _rebuild_parameters() -> void:
	if not is_instance_valid(parameters_list) or preview_shader == null:
		return
	for child in parameters_list.get_children():
		parameters_list.remove_child(child)
		child.queue_free()
	var uniforms := preview_shader.get_shader_uniform_list()
	for info: Dictionary in uniforms:
		var name := StringName(info.get("name", ""))
		var value_type := int(info.get("type", TYPE_NIL))
		if name.is_empty() or value_type == TYPE_NIL:
			continue
		_add_parameter_row(name, value_type, str(info.get("hint_string", "")))
	# Never delete values here. While the user is typing, the shader may be
	# briefly invalid or a multiline uniform declaration may be incomplete, so
	# Godot reports an empty/partial uniform list. Pruning at that point made a
	# single code edit reset every test and linked material parameter. Values for
	# genuinely removed uniforms are harmless and remain available if restored.
	if parameters_list.get_child_count() == 0:
		var empty := Label.new()
		empty.text = "No editable uniforms in this shader."
		empty.add_theme_color_override("font_color", Color("718b9e"))
		parameters_list.add_child(empty)


func _add_parameter_row(name: StringName, value_type: int, hint: String) -> void:
	var field := VBoxContainer.new()
	field.name = "Uniform_" + str(name)
	field.add_theme_constant_override("separation", 3)
	parameters_list.add_child(field)
	var heading := HBoxContainer.new()
	heading.name = "Heading"
	field.add_child(heading)
	var label := Label.new()
	label.text = str(name).replace("_", " ").capitalize()
	label.tooltip_text = str(name)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	heading.add_child(label)
	var default_value: Variant = _shader_uniform_default(name, value_type)
	var value: Variant = parameter_values.get(name, default_value)
	var reset := Button.new()
	reset.name = str(name) + "_reset"
	reset.text = "↺"
	reset.tooltip_text = "Reset to shader default: " + str(default_value)
	reset.visible = parameter_values.has(name) and parameter_values[name] != default_value
	reset.pressed.connect(_reset_preview_parameter.bind(name))
	heading.add_child(reset)
	match value_type:
		TYPE_BOOL:
			var check := CheckButton.new()
			check.button_pressed = bool(value)
			check.toggled.connect(func(enabled: bool): _set_preview_parameter(name, enabled))
			field.add_child(check)
		TYPE_INT, TYPE_FLOAT:
			_add_parameter_number(field, name, float(value), value_type, hint)
		TYPE_COLOR:
			var color := LiveColorPickerButton.new()
			color.custom_minimum_size.y = 32
			color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			color.color = value
			field.add_child(color)
			_style_parameter_color(color, value)
			var color_drag := {"origin": {}}
			color.interaction_started.connect(func(): color_drag.origin = _current_parameter_values())
			color.preview_changed.connect(func(next: Color):
				_style_parameter_color(color, next)
				_set_preview_parameter(name, next, "preview"))
			color.drag_committed.connect(func(_original: Color, next: Color):
				_style_parameter_color(color, next)
				_set_preview_parameter(name, next, "commit", color_drag.origin))
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4:
			var count := 2 if value_type == TYPE_VECTOR2 else (3 if value_type == TYPE_VECTOR3 else 4)
			for component in count:
				var row := HBoxContainer.new()
				field.add_child(row)
				var axis := Label.new()
				axis.text = ["X", "Y", "Z", "W"][component]
				axis.custom_minimum_size.x = 18
				axis.modulate = [Color("ee9e9e"), Color("9ed8a8"), Color("91b9ed"), Color("d7a5ed")][component]
				row.add_child(axis)
				var number := DragNumber.new()
				number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				number.allow_greater = true
				number.allow_lesser = true
				number.step = 0.01
				number.value = float(value[component])
				var vector_drag := {"origin": {}}
				number.interaction_started.connect(func(): vector_drag.origin = _current_parameter_values())
				number.preview_changed.connect(_vector_parameter_changed.bind(name, component, value_type, "preview", null))
				number.drag_committed.connect(func(next: float):
					_vector_parameter_changed(next, name, component, value_type, "commit", vector_drag.origin))
				number.value_changed.connect(_vector_parameter_changed.bind(name, component, value_type, "edit", null))
				row.add_child(number)
		TYPE_OBJECT:
			_add_texture_parameter(field, name, value)
		_:
			var unsupported := Label.new()
			unsupported.text = "Unsupported preview type"
			unsupported.add_theme_color_override("font_color", Color("718b9e"))
			field.add_child(unsupported)


func _add_texture_parameter(parent: VBoxContainer, name: StringName, value: Variant) -> void:
	var noise := _noise_from_parameter(value)
	var row := HBoxContainer.new()
	parent.add_child(row)
	var slot := ActorResourceSlot.new()
	slot.name = str(name) + "_texture_slot"
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(slot)
	var menu := PopupMenu.new()
	slot.add_child(menu)
	menu.add_item("Create Noise Image", 0)
	menu.add_item("Load from project…", 1)
	menu.add_item("Load from Super Clipboard…",7); menu.add_item("Copy to Super Clipboard",6)
	if value != null:
		menu.add_separator()
		menu.add_item("Clear", 2)
	var update_slot := func():
		var current: Variant = parameter_values.get(name)
		var current_noise := _noise_from_parameter(current)
		if current_noise != null:
			slot.text = ("▾  " if bool(parameter_expanded.get(name, false)) else "▸  ") + "Noise Image"
			slot.tooltip_text = "Click to expand the generated image · right-click for options"
		elif current is String and not current.is_empty():
			slot.text = "▣  " + str(current).get_file()
			slot.tooltip_text = str(current)
		elif current is Texture2D:
			slot.text = "▣  " + (current.resource_name if not current.resource_name.is_empty() else "Image")
		else:
			slot.text = "◇  Empty image"
			slot.tooltip_text = "Click to create a Noise Image or load an image from the project"
	update_slot.call()
	var open_menu := func(position: Vector2):
		menu.position = Vector2i(position)
		menu.popup()
	slot.pressed.connect(func():
		if _noise_from_parameter(parameter_values.get(name)) != null:
			parameter_expanded[name] = not bool(parameter_expanded.get(name, false))
			_rebuild_parameters()
		else:
			open_menu.call(slot.get_screen_position() + Vector2(0, slot.size.y)))
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			open_menu.call(event.global_position)
			get_viewport().set_input_as_handled())
	slot.accepts_file = func(path: String) -> bool:
		return path.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "bmp", "svg", "tga", "hdr", "exr", "tres", "res"]
	slot.file_dropped.connect(func(path: String): _set_parameter_image_path(name, path))
	var menu_action := func(id: int):
		match id:
			0:
				var definition := registry.get_object_definition(&"noise_image")
				if definition != null:
					parameter_expanded[name] = true
					_set_preview_parameter(name, ActorObjectReference.from_object(definition.create_object()))
					_rebuild_parameters()
			1,7: await _choose_parameter_texture(name,id==7)
			6: KiwiSuperClipboardService.instance.quick_save(parameter_values.get(name),str(name))
			2:
				parameter_expanded.erase(name)
				_set_preview_parameter(name, null)
				_rebuild_parameters()
	menu.id_pressed.connect(menu_action)
	if noise == null or not bool(parameter_expanded.get(name, false)):
		return
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Color("0f1922"), Color("3b5c70"), 7))
	parent.add_child(panel)
	var contents := VBoxContainer.new()
	contents.add_theme_constant_override("separation", 6)
	panel.add_child(contents)
	var preview := TextureRect.new()
	preview.name = str(name) + "_noise_preview"
	preview.custom_minimum_size = Vector2(0, 110)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture = ActorImageGenerator.texture_for_object(noise)
	contents.add_child(preview)
	var definition := registry.get_object_definition(&"noise_image")
	if definition == null:
		return
	var groups: Dictionary = {}
	for property in definition.properties:
		var group_name := str(property.options.get("group", "Properties"))
		if not groups.has(group_name):
			var group := VBoxContainer.new()
			group.add_theme_constant_override("separation", 5)
			contents.add_child(group)
			var group_label := Label.new()
			group_label.text = group_name.to_upper()
			group_label.add_theme_color_override("font_color", Color("78cdb9"))
			group.add_child(group_label)
			groups[group_name] = group
		_add_noise_property(groups[group_name], name, noise, definition, property, preview)


func _add_noise_property(parent: VBoxContainer, parameter_name: StringName, noise: ActorObjectData,
		definition: ActorObjectDefinition, property: ActorProperty, preview: TextureRect) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = property.label
	label.custom_minimum_size.x = 104
	row.add_child(label)
	var current: Variant = definition.value_for(noise, property)
	var restore := func(original: Variant):
		if not original is Dictionary or not (original as Dictionary).has(parameter_name):
			return
		var restored_reference: Variant = ActorData.copy_value((original as Dictionary)[parameter_name])
		parameter_values[parameter_name] = restored_reference
		var restored_noise := _noise_from_parameter(restored_reference)
		preview.texture = ActorImageGenerator.texture_for_object(restored_noise)
		_set_preview_parameter(parameter_name, restored_reference, "preview")
	var apply := func(next: Variant, mode: String = "edit", original: Variant = null,
			working_reference: Variant = null):
		# Keep one owned reference alive for a complete pointer interaction. Making
		# a fresh nested resource on every mouse-motion event made the preview,
		# linked material and inspector race between different Noise Image copies.
		var next_reference: Variant = working_reference
		if next_reference == null:
			next_reference = ActorData.copy_value(parameter_values.get(parameter_name))
		var next_noise := _noise_from_parameter(next_reference)
		if next_noise == null:
			return
		next_noise.set_value(property.id, ActorData.copy_value(next))
		if not next_noise.resource_path.is_empty():
			ResourceSaver.save(next_noise, next_noise.resource_path)
		parameter_values[parameter_name] = next_reference
		preview.texture = ActorImageGenerator.texture_for_object(next_noise)
		_set_preview_parameter(parameter_name, next_reference, mode, original)
	if property.options.has("choices"):
		var choice := OptionButton.new()
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for option: Variant in property.options.choices: choice.add_item(str(option))
		choice.select(int(current))
		choice.item_selected.connect(func(index: int): apply.call(index))
		row.add_child(choice)
		return
	match property.value_type:
		TYPE_BOOL:
			var toggle := CheckButton.new()
			toggle.button_pressed = bool(current)
			toggle.toggled.connect(func(next: bool): apply.call(next))
			row.add_child(toggle)
		TYPE_FLOAT, TYPE_INT:
			var number := DragNumber.new()
			number.name = str(parameter_name) + "_noise_" + str(property.id)
			number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			number.allow_greater = true
			number.allow_lesser = true
			number.step = float(property.options.get("step", 1.0 if property.value_type == TYPE_INT else 0.01))
			number.value = float(current)
			var drag := {"origin": {}, "working": null}
			number.interaction_started.connect(func():
				drag.origin = ActorData.copy_value(_current_parameter_values())
				drag.working = ActorData.copy_value(parameter_values.get(parameter_name)))
			var normalize := func(next: float) -> Variant: return int(next) if property.value_type == TYPE_INT else next
			number.preview_changed.connect(func(next: float):
				apply.call(normalize.call(next), "preview", null, drag.working))
			number.drag_committed.connect(func(next: float):
				apply.call(normalize.call(next), "commit", drag.origin, drag.working)
				drag.working = null)
			number.drag_cancelled.connect(func():
				restore.call(drag.origin)
				drag.working = null)
			number.value_changed.connect(func(next: float): apply.call(normalize.call(next)))
			row.add_child(number)
		TYPE_COLOR:
			var color := LiveColorPickerButton.new()
			color.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			color.color = current
			var drag := {"origin": {}, "working": null}
			color.interaction_started.connect(func():
				drag.origin = ActorData.copy_value(_current_parameter_values())
				drag.working = ActorData.copy_value(parameter_values.get(parameter_name)))
			color.preview_changed.connect(func(next: Color): apply.call(next, "preview", null, drag.working))
			color.drag_committed.connect(func(_before: Color, next: Color):
				apply.call(next, "commit", drag.origin, drag.working)
				drag.working = null)
			color.drag_cancelled.connect(func(_original: Color):
				restore.call(drag.origin)
				drag.working = null)
			row.add_child(color)


func _noise_from_parameter(value: Variant) -> ActorObjectData:
	if value is ActorObjectReference:
		var object := (value as ActorObjectReference).resolve(func(path: String):
			var localized := _godot_project_path(path)
			return ResourceLoader.load(localized, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData if ResourceLoader.exists(localized) else null)
		return object if object != null and object.type_id == &"noise_image" else null
	return null


func _set_parameter_image_path(name: StringName, path: String) -> void:
	var localized := _godot_project_path(path)
	if path.get_extension().to_lower() in ["tres", "res"]:
		var object := ResourceLoader.load(localized, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
		if object != null and object.type_id == &"noise_image":
			parameter_expanded[name] = true
			_set_preview_parameter(name, ActorObjectReference.from_asset(localized, &"noise_image"))
			_rebuild_parameters()
			return
	_set_preview_parameter(name, localized)
	_rebuild_parameters()


func _shader_uniform_default(name: StringName, value_type: int) -> Variant:
	if value_type == TYPE_OBJECT:
		return null
	# Runtime-created Shader RIDs can report a zero placeholder for a frame
	# before compilation. Read literal declarations first so the UI is correct
	# immediately while typing, then fall back to RenderingServer for expressions.
	var declared := _declared_uniform_default(name, value_type)
	if declared.found:
		return declared.value
	var value: Variant = RenderingServer.shader_get_parameter_default(preview_shader.get_rid(), name)
	if value != null:
		return value
	match value_type:
		TYPE_BOOL: return false
		TYPE_INT: return 0
		TYPE_FLOAT: return 0.0
		TYPE_VECTOR2: return Vector2.ZERO
		TYPE_VECTOR3: return Vector3.ZERO
		TYPE_VECTOR4: return Vector4.ZERO
		TYPE_COLOR: return Color.WHITE
	return null


func _declared_uniform_default(name: StringName, value_type: int) -> Dictionary:
	var pattern := "(?m)\\buniform\\s+[A-Za-z_][A-Za-z0-9_]*\\s+" + str(name) \
		+ "(?:\\s*:[^=;]+)?\\s*=\\s*([^;]+);"
	var found := RegEx.create_from_string(pattern).search(editor.code.text)
	if found == null:
		return {"found": false}
	var expression := found.get_string(1).strip_edges()
	match value_type:
		TYPE_BOOL:
			if expression in ["true", "false"]:
				return {"found": true, "value": expression == "true"}
		TYPE_INT:
			var clean_int := expression.trim_suffix("u")
			if clean_int.is_valid_int():
				return {"found": true, "value": clean_int.to_int()}
		TYPE_FLOAT:
			var clean_float := expression.trim_suffix("f")
			if clean_float.is_valid_float():
				return {"found": true, "value": clean_float.to_float()}
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR:
			var constructor := RegEx.create_from_string("^(?:vec[234]|ivec[234]|uvec[234])\\s*\\((.*)\\)$").search(expression)
			if constructor != null:
				var count := 2 if value_type == TYPE_VECTOR2 else (3 if value_type == TYPE_VECTOR3 else 4)
				var pieces := constructor.get_string(1).split(",")
				var numbers: Array[float] = []
				for piece in pieces:
					var clean := str(piece).strip_edges().trim_suffix("f")
					if not clean.is_valid_float():
						return {"found": false}
					numbers.append(clean.to_float())
				if numbers.size() == 1:
					while numbers.size() < count: numbers.append(numbers[0])
				if numbers.size() == count:
					if value_type == TYPE_VECTOR2: return {"found": true, "value": Vector2(numbers[0], numbers[1])}
					if value_type == TYPE_VECTOR3: return {"found": true, "value": Vector3(numbers[0], numbers[1], numbers[2])}
					if value_type == TYPE_VECTOR4: return {"found": true, "value": Vector4(numbers[0], numbers[1], numbers[2], numbers[3])}
					return {"found": true, "value": Color(numbers[0], numbers[1], numbers[2], numbers[3])}
	return {"found": false}


func _add_parameter_number(parent: Control, name: StringName, value: float, value_type: int, hint: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	parent.add_child(row)
	var number := DragNumber.new()
	number.name = str(name) + "_value"
	number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	number.allow_greater = true
	number.allow_lesser = true
	number.step = 1.0 if value_type == TYPE_INT else 0.01
	number.value = value
	var drag_state := {"origin": {}}
	number.interaction_started.connect(func(): drag_state.origin = _current_parameter_values())
	var range := _hint_range(hint)
	if not range.is_empty():
		var slider := HSlider.new()
		slider.min_value = range[0]
		slider.max_value = range[1]
		slider.step = number.step
		slider.value = value
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(slider)
		number.custom_minimum_size.x = 82
		number.size_flags_horizontal = Control.SIZE_SHRINK_END
		var slider_drag := {"active": false, "origin": {}}
		slider.drag_started.connect(func():
			slider_drag.active = true
			slider_drag.origin = _current_parameter_values())
		slider.value_changed.connect(func(next: float):
			number.set_value_no_signal(next)
			_set_preview_parameter(name, int(next) if value_type == TYPE_INT else next,
				"preview" if slider_drag.active else "edit"))
		slider.drag_ended.connect(func(changed: bool):
			slider_drag.active = false
			if changed:
				_set_preview_parameter(name, int(slider.value) if value_type == TYPE_INT else slider.value,
					"commit", slider_drag.origin))
		number.preview_changed.connect(func(next: float): slider.set_value_no_signal(next))
		number.value_changed.connect(func(next: float): slider.set_value_no_signal(next))
	var normalize := func(next: float) -> Variant: return int(next) if value_type == TYPE_INT else next
	number.preview_changed.connect(func(next: float): _set_preview_parameter(name, normalize.call(next), "preview"))
	number.drag_committed.connect(func(next: float): _set_preview_parameter(name, normalize.call(next), "commit", drag_state.origin))
	number.value_changed.connect(func(next: float): _set_preview_parameter(name, normalize.call(next), "edit"))
	row.add_child(number)


func _hint_range(hint: String) -> PackedFloat32Array:
	var pieces := hint.split(",")
	if pieces.size() >= 2 and pieces[0].is_valid_float() and pieces[1].is_valid_float():
		return PackedFloat32Array([pieces[0].to_float(), pieces[1].to_float()])
	return PackedFloat32Array()


func _vector_parameter_changed(next: float, name: StringName, component: int, value_type: int,
		mode: String = "edit", original: Variant = null) -> void:
	var value: Variant = parameter_values.get(name, spatial_material.get_shader_parameter(name))
	if value == null:
		value = _shader_uniform_default(name, value_type)
	value[component] = next
	_set_preview_parameter(name, value, mode, original)


func _set_preview_parameter(name: StringName, value: Variant, mode: String = "edit", original: Variant = null) -> void:
	parameter_values[name] = value
	var preview_value: Variant = _preview_parameter_value(value)
	spatial_material.set_shader_parameter(name, preview_value)
	sky_material.set_shader_parameter(name, preview_value)
	canvas_material.set_shader_parameter(name, preview_value)
	fog_preview_material.set_shader_parameter(name, preview_value)
	particle_material.set_shader_parameter(name, preview_value)
	var reset := parameters_list.find_child(str(name) + "_reset", true, false) as Button
	if reset != null:
		reset.visible = value != _shader_uniform_default(name, typeof(value))
	if parameters_linked and linked_parameter_writer.is_valid():
		linked_parameter_writer.call(name, ActorData.copy_value(value), mode, original)


func _reset_preview_parameter(name: StringName) -> void:
	var default_value: Variant = _shader_uniform_default(name, _uniform_type(name))
	if parameters_linked:
		_set_preview_parameter(name, default_value)
	else:
		parameter_values.erase(name)
		_rebind_preview_materials()
		_apply_environment()
		_apply_materials()
	_rebuild_parameters()


func _uniform_type(name: StringName) -> int:
	for info: Dictionary in preview_shader.get_shader_uniform_list():
		if StringName(info.get("name", "")) == name:
			return int(info.get("type", TYPE_NIL))
	return TYPE_NIL


func _current_parameter_values() -> Dictionary:
	if parameters_linked and linked_parameter_reader.is_valid():
		var values: Variant = linked_parameter_reader.call()
		if values is Dictionary:
			return values.duplicate(true)
	return parameter_values.duplicate(true)


func _parameter_link_toggled(enabled: bool) -> void:
	parameters_linked = enabled and linked_parameter_reader.is_valid() and linked_parameter_writer.is_valid()
	if parameters_linked:
		parameter_values = _current_parameter_values()
	_rebind_preview_materials()
	_apply_environment()
	_apply_materials()
	_rebuild_parameters()


func _reset_all_preview_parameters() -> void:
	if parameters_linked:
		for info: Dictionary in preview_shader.get_shader_uniform_list():
			var name := StringName(info.get("name", ""))
			if not name.is_empty():
				_set_preview_parameter(name, _shader_uniform_default(name, int(info.get("type", TYPE_NIL))))
	else:
		parameter_values.clear()
		_rebind_preview_materials()
		_apply_environment()
		_apply_materials()
	_rebuild_parameters()


func _style_parameter_color(button: ColorPickerButton, value: Color) -> void:
	button.text = "  " + value.to_html(value.a < 1.0).to_upper()
	var border := Color.WHITE if value.get_luminance() < 0.45 else Color("1b2a35")
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, _box(value, border, 6))
	button.add_theme_color_override("font_color", Color.WHITE if value.get_luminance() < 0.45 else Color("101820"))


func _choose_parameter_texture(name: StringName,from_clipboard: bool=false) -> void:
	var property := ActorProperty.new()
	property.id = name
	property.label = str(name)
	property.object_type = &"image"
	property.options = {"extensions": ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga", "hdr", "exr", "tres", "res"],
		"raw_extensions": ["png", "jpg", "jpeg", "webp", "svg", "bmp", "tga", "hdr", "exr"],
		"accepted_object_types": ["image", "noise_image"],
		"native_resource_types": ["Texture2D"], "file_picker": true}
	var path := await ActorProjectFilePicker.pick(self, property, "Choose preview texture",from_clipboard)
	if path==ActorProjectFilePicker.EMPTY_RESOURCE: _set_preview_parameter(name,null); return
	if path.is_empty():
		return
	_set_parameter_image_path(name, path)


func _viewport_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		viewport_display.grab_focus()
		editor.code.release_focus()
	if shader_kind == "canvas_item":
		viewport_display.accept_event()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed
		_last_mouse = event.position
		viewport_display.accept_event()
	elif event is InputEventMouseMotion and _looking:
		var delta: Vector2 = event.position - _last_mouse
		_last_mouse = event.position
		camera_rig.rotation.y -= delta.x * 0.006
		camera.rotation.x = clampf(camera.rotation.x - delta.y * 0.006, -1.5, 1.5)
		viewport_display.accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		camera_speed = clampf(camera_speed * (1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else (1.0 / 1.2)), 0.1, 100.0)
		status.text = _viewport_help()
		viewport_display.accept_event()
	elif event is InputEventKey and viewport_display.has_focus() and event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E]:
		# Keep navigation keys owned by the viewport instead of allowing the
		# previously-focused CodeEdit to type them into shader source.
		viewport_display.accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.ctrl_pressed and event.keycode == KEY_S:
		if event.shift_pressed:
			save_as()
		else:
			save()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible or not _looking or shader_kind == "canvas_item": return
	var velocity := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): velocity -= camera_rig.transform.basis.z
	if Input.is_key_pressed(KEY_S): velocity += camera_rig.transform.basis.z
	if Input.is_key_pressed(KEY_A): velocity -= camera_rig.transform.basis.x
	if Input.is_key_pressed(KEY_D): velocity += camera_rig.transform.basis.x
	if Input.is_key_pressed(KEY_Q): velocity -= Vector3.UP
	if Input.is_key_pressed(KEY_E): velocity += Vector3.UP
	if not velocity.is_zero_approx(): camera_rig.position += velocity.normalized() * delta * camera_speed


func _viewport_help() -> String:
	return "Speed %.1f m/s  ·  Wheel changes speed  ·  Right-drag + WASD/QE to fly" % camera_speed


func _document_title() -> String:
	if not current_path.is_empty(): return current_path.get_file()
	if current_source is Shader and not current_source.resource_name.is_empty(): return current_source.resource_name
	return "Untitled Shader"


func _button(text: String, accent: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 32
	button.add_theme_stylebox_override("normal", _box(Color("20544e") if accent else Color("1d2f3e"), Color("69d8c1") if accent else Color("3c586b"), 7))
	button.add_theme_stylebox_override("hover", _box(Color("2d6e63") if accent else Color("29495d"), Color("91f0d9"), 7))
	return button


func _box(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 9
	style.content_margin_right = 9
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style
