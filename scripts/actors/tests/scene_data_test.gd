extends SceneTree
const SceneExporter = preload("res://scripts/actors/core/actor_scene_exporter.gd")
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var outer := VBoxContainer.new()
	var tabs := ActorSceneTabs.new()
	tabs.name = "Tabs"
	outer.add_child(tabs)
	var workspace_container := ColorRect.new()
	workspace_container.name = "WorkspaceContainer"
	outer.add_child(workspace_container)
	var workspace := Control.new()
	workspace.name = "SceneWorkspace"
	workspace_container.add_child(workspace)
	var world := Node.new()
	world.name = "World"
	workspace.add_child(world)
	var viewport := SubViewport.new()
	viewport.name = "SubViewport"
	viewport.size = Vector2i(64, 64)
	world.add_child(viewport)
	var camera := load("res://CustomNodes/Freecam/Freecam.tscn").instantiate() as Node3D
	viewport.add_child(camera)
	var layout := VBoxContainer.new()
	layout.name = "VBoxContainer"
	workspace.add_child(layout)
	var toolbar := HBoxContainer.new()
	toolbar.name = "HBoxContainer"
	layout.add_child(toolbar)
	var menu := ActorSceneMenuButton.new()
	toolbar.add_child(menu)
	var split := HSplitContainer.new()
	split.name = "HSplitContainer"
	layout.add_child(split)
	var vertical := VSplitContainer.new()
	vertical.name = "VSplitContainer2"
	split.add_child(vertical)
	var file_column := VSplitContainer.new()
	file_column.name = "VSplitContainer"
	split.add_child(file_column)
	var mock_filesystem := Node.new()
	mock_filesystem.name = "FileSystem"
	mock_filesystem.add_user_signal("file_resource_opened", [{"name": "path", "type": TYPE_STRING}])
	mock_filesystem.add_user_signal("shader_file_opened", [{"name": "path", "type": TYPE_STRING}])
	file_column.add_child(mock_filesystem)
	var editor := load("res://Workspaces/SceneWorkspace/Timeline.tscn").instantiate() as ActorTimelineEditor
	vertical.add_child(editor)
	root.add_child(outer)
	await process_frame
	check(menu.timeline == editor and menu.scene_tabs == tabs,
		"Scene menu resolves the active timeline and scene tabs")
	check(tabs.shader_workspace != null and not tabs.shader_workspace.visible,
		"Dedicated shader workspace is created beside the scene workspace")
	var original_tab_count := tabs.documents.size()
	tabs.new_shader()
	await process_frame
	check(tabs.documents.size() == original_tab_count + 1
		and tabs.documents[tabs.current_tab].type == "shader"
		and tabs.shader_workspace.visible and not workspace.visible,
		"New Shader Editor creates a first-class shader tab and switches workspaces")
	var shader_workspace = tabs.shader_workspace
	check(shader_workspace.viewport != null and shader_workspace.editor.code.text.contains("shader_type spatial")
		and shader_workspace.mesh_holder.get_child_count() > 0,
		"Shader tab has a live mesh viewport and main code editor")
	check(shader_workspace.viewport.own_world_3d,
		"Shader preview owns an isolated 3D world and cannot leak into scene tabs")
	check(shader_workspace.editor.dedicated_mode
		and not shader_workspace.editor.workspace_picker.visible
		and not shader_workspace.editor.scene_tree.visible
		and shader_workspace.editor.shader_workspace.visible,
		"Dedicated shader tabs contain no scene-tree workspace UI")
	check(shader_workspace.get_node("ShaderWorkspaceRoot/ShaderWorkspaceSplit/ViewportColumn") != null
		and shader_workspace.get_node("ShaderWorkspaceRoot/PreviewSettings") != null
		and shader_workspace.get_node("ShaderWorkspaceRoot/ShaderWorkspaceSplit/ShaderSideColumn/ShaderCodePanel") != null,
		"Preview settings form a full-width top strip while the viewport remains dominant")
	check(shader_workspace.get_node("ShaderWorkspaceRoot/ShaderWorkspaceSplit/ShaderSideColumn") is VSplitContainer,
		"Shader parameters and code are separated by a draggable resize divider")
	check(shader_workspace.environment_node.environment.sky.sky_material is PanoramaSkyMaterial
		and shader_workspace.environment_node.environment.sky.sky_material.panorama != null,
		"Studio environment uses the textured panorama rather than a color gradient")
	shader_workspace.editor.code.text = "shader_type spatial;\nuniform vec4 preview_tint : source_color = vec4(1.0, 0.1, 0.05, 1.0);\nuniform float preview_strength = 0.65;\nvoid fragment() { ALBEDO = preview_tint.rgb * preview_strength; }\n"
	shader_workspace.editor.code.text_changed.emit()
	await process_frame
	var preview_meshes: Array[Node] = shader_workspace.mesh_holder.find_children("*", "MeshInstance3D", true, false)
	var preview_mesh := preview_meshes[0] as MeshInstance3D if not preview_meshes.is_empty() else null
	check(preview_mesh != null and preview_mesh.material_override == shader_workspace.spatial_material
		and (preview_mesh.material_override as ShaderMaterial).shader.code.contains("ALBEDO = preview_tint.rgb"),
		"Spatial shader is force-applied to the preview model")
	check(shader_workspace.parameters_list.find_child("Uniform_preview_tint", true, false) != null,
		"Shader uniforms appear in the compact test-parameters section")
	var default_strength := shader_workspace.parameters_list.find_child("preview_strength_value", true, false) as DragNumber
	check(default_strength != null and is_equal_approx(default_strength.value, 0.65),
		"Shader test parameters display their declared defaults instead of zero")
	shader_workspace._set_preview_parameter(&"preview_tint", Color(0.1, 0.8, 0.3, 1.0))
	check(shader_workspace.spatial_material.get_shader_parameter(&"preview_tint") == Color(0.1, 0.8, 0.3, 1.0),
		"Test parameter controls update the live preview material")
	shader_workspace.editor.code.text = "shader_type canvas_item;\nuniform float amount = 0.75;\nvoid fragment() { COLOR = texture(TEXTURE, UV) * amount; }\n"
	shader_workspace.editor.code.text_changed.emit()
	await process_frame
	check(shader_workspace.shader_kind == "canvas_item" and shader_workspace.canvas_preview.visible
		and not shader_workspace.preview_root.visible and shader_workspace.canvas_image_group.visible
		and not shader_workspace.mesh_group.visible and not shader_workspace.environment_group.visible,
		"Canvas shaders replace the 3D mesh/environment controls with a 2D image preview")
	check(shader_workspace.canvas_preview.texture != null
		and shader_workspace.canvas_preview.material == shader_workspace.canvas_material
		and shader_workspace.canvas_material.shader.code.contains("shader_type canvas_item"),
		"Canvas shader workspace uses a default image with the live CanvasItem material")
	var canvas_source_size: Vector2 = shader_workspace.canvas_preview.texture.get_size()
	var canvas_rect_size: Vector2 = shader_workspace.canvas_preview.size
	check(is_equal_approx(canvas_source_size.x / canvas_source_size.y,
		canvas_rect_size.x / canvas_rect_size.y),
		"Canvas shader preview fits its image without stretching the aspect ratio")
	var portrait_image := Image.create(120, 300, false, Image.FORMAT_RGBA8)
	shader_workspace.canvas_preview.texture = ImageTexture.create_from_image(portrait_image)
	shader_workspace._fit_canvas_preview()
	check(is_equal_approx(shader_workspace.canvas_preview.size.x / shader_workspace.canvas_preview.size.y, 0.4),
		"Canvas shader preview preserves a non-widescreen project image aspect ratio")
	shader_workspace._update_canvas_texture()
	shader_workspace.editor.code.text = "shader_type canvas_item;\nuniform sampler2D generated_noise;\nvoid fragment() { COLOR = texture(generated_noise, UV); }\n"
	shader_workspace.editor.code.text_changed.emit()
	await process_frame
	await process_frame
	var empty_noise_slot := shader_workspace.parameters_list.find_child("generated_noise_texture_slot", true, false) as ActorResourceSlot
	check(empty_noise_slot != null and empty_noise_slot.text.contains("Empty"),
		"Shader sampler parameters expose an image resource slot")
	var noise_definition := editor.registry.get_object_definition(&"noise_image")
	shader_workspace.parameter_expanded[&"generated_noise"] = true
	shader_workspace._set_preview_parameter(&"generated_noise",
		ActorObjectReference.from_object(noise_definition.create_object()))
	shader_workspace._rebuild_parameters()
	var noise_frequency := shader_workspace.parameters_list.find_child("generated_noise_noise_frequency", true, false) as DragNumber
	check(noise_frequency != null
		and shader_workspace.parameters_list.find_child("generated_noise_noise_preview", true, false) is TextureRect,
		"Noise Image sampler resources expand to editable properties and a preview")
	if noise_frequency != null:
		noise_frequency.value_changed.emit(0.12)
		var noise_reference := shader_workspace.parameter_values[&"generated_noise"] as ActorObjectReference
		var edited_noise := ActorAnimation.resolve_reference(noise_reference)
		check(is_equal_approx(float(edited_noise.get_value(&"frequency")), 0.12)
			and shader_workspace.canvas_material.get_shader_parameter(&"generated_noise") is Texture2D,
			"Editing Noise Image properties regenerates the live shader texture")
	shader_workspace.editor.code.text = "shader_type spatial;\nuniform vec4 preview_tint : source_color = vec4(1.0, 0.1, 0.05, 1.0);\nuniform float preview_strength = 0.65;\nvoid fragment() { ALBEDO = preview_tint.rgb * preview_strength; }\n"
	shader_workspace.editor.code.text_changed.emit()
	await process_frame
	shader_workspace.editor.code.grab_focus()
	await process_frame
	var viewport_press := InputEventMouseButton.new()
	viewport_press.button_index = MOUSE_BUTTON_RIGHT
	viewport_press.pressed = true
	shader_workspace._viewport_input(viewport_press)
	check(shader_workspace.viewport_display.has_focus() and not shader_workspace.editor.code.has_focus(),
		"Entering shader viewport navigation removes keyboard focus from the code editor")
	viewport_press.pressed = false
	shader_workspace._viewport_input(viewport_press)
	var old_speed: float = shader_workspace.camera_speed
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	shader_workspace._viewport_input(wheel)
	check(shader_workspace.camera_speed > old_speed,
		"Shader viewport mouse wheel adjusts fly speed")
	var environment_picker := ActorProjectFilePicker.new()
	environment_picker.project_root = ProjectSettings.globalize_path("res://").simplify_path()
	environment_picker.allowed_extensions = PackedStringArray(["tres", "res"])
	environment_picker.allowed_native_types = PackedStringArray(["Environment"])
	check(environment_picker._path_allowed(ProjectSettings.globalize_path("res://resources/environments/DefaultEnvironment.tres")),
		"Environment asset picker includes native Environment resources")
	var mini_shader_editor := ShaderCodeEditor.new()
	workspace.add_child(mini_shader_editor)
	await process_frame
	var document_count_before_mini := tabs.documents.size()
	mini_shader_editor._workspace_selected(1)
	check(mini_shader_editor.workspace_picker.selected == 1 and mini_shader_editor.shader_workspace.visible
		and not mini_shader_editor.scene_tree.visible and tabs.documents.size() == document_count_before_mini,
		"Scene workspace keeps its compact shader editor instead of creating a shader tab")
	shader_workspace.editor.code.text = "shader_type sky;\nvoid sky() { COLOR = vec3(0.15, 0.3, 0.7); }\n"
	shader_workspace.editor.code.text_changed.emit()
	check(shader_workspace.shader_kind == "sky"
		and shader_workspace.environment_node.environment.sky.sky_material == shader_workspace.sky_material,
		"Shader type is detected from code and sky shaders drive the preview sky: %s / %s" % [shader_workspace.shader_kind, shader_workspace.environment_node.environment.sky.sky_material])
	shader_workspace.editor.code.text = "shader_type fog;\nuniform float density = 0.8;\nvoid fog() { DENSITY = density; ALBEDO = vec3(0.7, 0.85, 1.0); }\n"
	shader_workspace.editor.code.text_changed.emit()
	check(not shader_workspace.editor.diagnostics.visible,
		"Fog shader built-ins such as DENSITY are accepted by the shader editor validator")
	check(shader_workspace.shader_kind == "fog" and shader_workspace.fog_preview.visible
		and not shader_workspace.mesh_holder.visible and not shader_workspace.mesh_group.visible
		and shader_workspace.fog_preview.material == shader_workspace.fog_preview_material
		and shader_workspace.environment_node.environment.volumetric_fog_enabled,
		"Fog shader tab previews a real large FogVolume in a volumetric environment")
	shader_workspace._set_preview_parameter(&"density", 0.45)
	check(is_equal_approx(float(shader_workspace.fog_preview_material.get_shader_parameter(&"density")), 0.45),
		"Fog shader parameters update the live volume preview")
	shader_workspace.editor.code.text = "shader_type sky;\nvoid sky() { COLOR = vec3(0.15, 0.3, 0.7); }\n"
	shader_workspace.editor.code.text_changed.emit()
	var preview_mesh_path := "user://shader_preview_mesh_" + ActorData.new_id() + ".tres"
	check(ResourceSaver.save(BoxMesh.new(), preview_mesh_path) == OK, "Create a preview mesh resource")
	shader_workspace._mesh_mode = "file"
	shader_workspace._mesh_path = preview_mesh_path
	shader_workspace._rebuild_mesh()
	check(shader_workspace.mesh_holder.get_children().any(func(node: Node): return node is MeshInstance3D)
		and shader_workspace.mesh_label.text.contains(preview_mesh_path.get_file()),
		"Shader workspace can preview a Mesh resource loaded from the project filesystem")
	var shader_tab := tabs.current_tab
	tabs.current_tab = 0
	check(workspace.visible and not tabs.shader_workspace.visible,
		"Returning to a scene tab restores the scene workspace")
	tabs.current_tab = shader_tab
	check(tabs.shader_workspace.editor.code.text.begins_with("shader_type sky"),
		"Shader tabs preserve their code and preview state while switching")
	var shader_path := "user://workspace_shader_" + ActorData.new_id() + ".gdshader"
	shader_workspace.current_path = shader_path
	shader_workspace.current_source = shader_path
	shader_workspace.requires_path = false
	shader_workspace.editor.current_path = shader_path
	await shader_workspace.save()
	check(FileAccess.file_exists(shader_path), "Shader workspace saves its current shader file")
	check(not tabs.documents[tabs.current_tab].dirty and not tabs.get_tab_title(tabs.current_tab).contains("•"),
		"Saving a shader clears the tab's unsaved indicator")
	var synchronized_code := "shader_type spatial;\nuniform float synced_gain = 0.25;\nuniform vec4 synced_color : source_color = vec4(0.1, 0.7, 0.3, 1.0);\nuniform sampler2D synced_noise;\nvoid fragment() { ALBEDO = synced_color.rgb * synced_gain; }\n"
	var synchronized_file := FileAccess.open(shader_path, FileAccess.WRITE)
	synchronized_file.store_string(synchronized_code)
	synchronized_file.close()
	tabs.current_tab = 0
	tabs._external_shader_changed(shader_path)
	var linked_store := {&"synced_gain": 0.8, &"synced_color": Color(0.8, 0.2, 0.55, 1.0)}
	var linked_reader := func() -> Dictionary: return linked_store.duplicate(true)
	var linked_writer := func(name: StringName, value: Variant, _mode: String, _original: Variant): linked_store[name] = value
	tabs.open_shader(shader_path, {"values": linked_reader.call(), "reader": linked_reader, "writer": linked_writer})
	await process_frame
	check(shader_workspace.editor.code.text == synchronized_code,
		"Scene-editor shader changes replace stale code cached by an existing shader tab")
	check(is_equal_approx(float(shader_workspace.spatial_material.get_shader_parameter(&"synced_gain")), 0.8)
		and is_equal_approx(float(shader_workspace.parameter_values[&"synced_gain"]), 0.8),
		"Opening an actor shader tab carries its ShaderMaterial parameter values into the preview")
	check(shader_workspace.parameter_link.visible and shader_workspace.parameter_link.button_pressed,
		"Material-opened shader tabs expose an enabled parameter-link toggle")
	shader_workspace._set_preview_parameter(&"synced_gain", 0.6)
	check(is_equal_approx(float(linked_store[&"synced_gain"]), 0.6),
		"Linked parameter changes in the shader tab update the scene ShaderMaterial")
	linked_store[&"synced_gain"] = 0.35
	var linked_shader_tab := tabs.current_tab
	tabs.current_tab = 0
	tabs.current_tab = linked_shader_tab
	check(is_equal_approx(float(shader_workspace.parameter_values[&"synced_gain"]), 0.35),
		"Linked ShaderMaterial changes in the scene are pulled into the shader tab")
	shader_workspace.parameter_link.button_pressed = false
	shader_workspace._set_preview_parameter(&"synced_gain", 0.9)
	check(is_equal_approx(float(linked_store[&"synced_gain"]), 0.35),
		"Disabling the link keeps shader-tab test parameters independent")
	shader_workspace.parameter_link.button_pressed = true
	# Simulate a value still owned by a focused editor when Save is pressed.
	# Save must flush the full linked snapshot even if no final UI signal fired.
	shader_workspace.parameter_values[&"synced_gain"] = 0.72
	print("EXPECTED_SHADER_COMPILER_ERROR_BEGIN")
	shader_workspace.editor.code.text = "shader_type spatial;\nuniform float synced_gain"
	shader_workspace.editor.code.text_changed.emit()
	await process_frame
	await process_frame
	print("EXPECTED_SHADER_COMPILER_ERROR_END")
	shader_workspace.editor.code.text = synchronized_code
	shader_workspace.editor.code.text_changed.emit()
	await process_frame
	await process_frame
	var preserved_gain := shader_workspace.parameters_list.find_child("synced_gain_value", true, false) as DragNumber
	check(is_equal_approx(float(shader_workspace.parameter_values[&"synced_gain"]), 0.72)
		and preserved_gain != null and is_equal_approx(preserved_gain.value, 0.72),
		"Temporarily invalid shader edits do not erase linked parameter values")
	await shader_workspace.save()
	check(is_equal_approx(float(linked_store[&"synced_gain"]), 0.72),
		"Saving a linked shader tab flushes its current parameter values to the ShaderMaterial")
	var color_buttons: Array[Node] = shader_workspace.parameters_list.find_children("*", "LiveColorPickerButton", true, false)
	var color_button := color_buttons[0] as ColorPickerButton if not color_buttons.is_empty() else null
	var color_style := color_button.get_theme_stylebox("normal") as StyleBoxFlat if color_button != null else null
	check(color_style != null and color_style.bg_color.is_equal_approx(Color(0.8, 0.2, 0.55, 1.0)),
		"Color uniforms render a swatch using their actual value instead of a gray bar")
	shader_workspace.editor.code.text += "// shortcut save\n"
	shader_workspace.editor.code.text_changed.emit()
	var save_key := InputEventKey.new()
	save_key.keycode = KEY_S
	save_key.ctrl_pressed = true
	save_key.pressed = true
	shader_workspace.editor._code_input(save_key)
	var saved_shader_file := FileAccess.open(shader_path, FileAccess.READ)
	check(saved_shader_file != null and saved_shader_file.get_as_text().contains("shortcut save"),
		"Ctrl+S saves the current full shader tab")
	var shortcut_editor := ShaderCodeEditor.new()
	shortcut_editor.dedicated_mode = true
	workspace.add_child(shortcut_editor)
	var shortcut_kind := {"save_as": false}
	shortcut_editor.save_shortcut_requested.connect(func(requested: bool): shortcut_kind.save_as = requested)
	var save_as_key := InputEventKey.new()
	save_as_key.keycode = KEY_S
	save_as_key.ctrl_pressed = true
	save_as_key.shift_pressed = true
	save_as_key.pressed = true
	shortcut_editor._code_input(save_as_key)
	check(shortcut_kind.save_as, "Ctrl+Shift+S requests Save As in a full shader editor")
	var tabs_before_filesystem_open := tabs.documents.size()
	mock_filesystem.emit_signal("shader_file_opened", shader_path)
	check(tabs.current_tab < tabs.documents.size() and tabs.documents[tabs.current_tab].type == "shader"
		and tabs.documents.size() == tabs_before_filesystem_open,
		"Double-clicking an existing .gdshader focuses its full shader-editor tab")
	check(await FileOperations.get_file_thumbnail(shader_path) == FileOperations.SHADER_TEXTURE,
		".gdshader files use the dedicated shader thumbnail")
	var shader_document_count := tabs.documents.size()
	tabs.open_shader(shader_path)
	check(tabs.documents.size() == shader_document_count,
		"Opening a shader already represented by a tab focuses it instead of duplicating it")
	# Exercise the real scene -> inspector binding -> shader tab -> save -> scene
	# lifecycle rather than only a synthetic parameter callback.
	tabs.current_tab = 0
	var scene_before_link_test := editor.capture_scene_data(true)
	var linked_definition := editor.registry.get_definition(&"image_3d")
	var linked_material_definition := editor.registry.get_object_definition(&"shader_material")
	editor.model.create_actor(linked_definition, 0.0)
	var linked_actor := editor.model.selected_actor()
	var linked_material := linked_material_definition.create_object()
	var linked_noise := noise_definition.create_object()
	linked_material.set_value(&"shader_path", shader_path)
	linked_material.set_value(&"uniforms", {&"synced_gain": 0.18,
		&"synced_color": Color(0.8, 0.2, 0.55, 1.0),
		&"synced_noise": ActorObjectReference.from_object(linked_noise)})
	linked_actor.set_value(&"material", ActorObjectReference.from_object(linked_material))
	var linked_path := ActorAnimation.path_to_object(linked_actor, linked_material)
	var binding_inspector := ActorInspector.new()
	root.add_child(binding_inspector)
	binding_inspector.setup(editor.model, editor.registry, ActorInspectorState.new())
	var real_binding := binding_inspector.shader_workspace_parameter_binding(linked_actor.id, linked_path, linked_actor)
	tabs.open_shader(shader_path, real_binding)
	shader_workspace._set_preview_parameter(&"synced_gain", 0.64)
	shader_workspace.parameter_expanded[&"synced_noise"] = true
	shader_workspace._rebuild_parameters()
	var linked_frequency := shader_workspace.parameters_list.find_child("synced_noise_noise_frequency", true, false) as DragNumber
	check(linked_frequency != null, "Linked Noise Image exposes editable properties in the shader tab")
	if linked_frequency != null:
		linked_frequency.interaction_started.emit()
		linked_frequency.preview_changed.emit(0.09)
		var preview_uniforms: Dictionary = linked_material.get_value(&"uniforms")
		var preview_noise := ActorAnimation.resolve_reference(preview_uniforms[&"synced_noise"])
		check(is_equal_approx(float(preview_noise.get_value(&"frequency")), 0.09),
			"Noise Image drag previews synchronize live to the linked ShaderMaterial")
		linked_frequency.drag_committed.emit(0.12)
		var committed_uniforms: Dictionary = linked_material.get_value(&"uniforms")
		var committed_noise := ActorAnimation.resolve_reference(committed_uniforms[&"synced_noise"])
		check(is_equal_approx(float(committed_noise.get_value(&"frequency")), 0.12),
			"Noise Image drag commits preserve the final linked value")
		editor.model.undo()
		var undone_uniforms: Dictionary = linked_material.get_value(&"uniforms")
		var undone_noise := ActorAnimation.resolve_reference(undone_uniforms[&"synced_noise"])
		check(is_equal_approx(float(undone_noise.get_value(&"frequency")),
			float(noise_definition.find_property(&"frequency").create_default())),
			"Linked Noise Image edits undo as one interaction")
		editor.model.redo()
		await process_frame
		await process_frame
		var scene_noise_control := binding_inspector.find_child("frequency_value", true, false) as DragNumber
		check(scene_noise_control != null and is_equal_approx(scene_noise_control.value, 0.12),
			"Shader-tab Noise Image edits refresh the linked scene inspector without reselection")
	await shader_workspace.save()
	tabs.current_tab = 0
	var restored_link_actor := editor.model.actor_for_id(linked_actor.id)
	var restored_link_reference := restored_link_actor.get_value(&"material") as ActorObjectReference
	var restored_link_material := ActorAnimation.resolve_reference(restored_link_reference)
	check(is_equal_approx(float((restored_link_material.get_value(&"uniforms") as Dictionary)[&"synced_gain"]), 0.64),
		"Saving in a shader tab updates the linked ShaderMaterial after returning to its scene tab")
	await process_frame
	await process_frame
	var scene_frequency := binding_inspector.find_child("frequency_value", true, false) as DragNumber
	check(scene_frequency != null, "Scene inspector exposes linked Noise Image settings")
	if scene_frequency != null:
		scene_frequency.value_changed.emit(0.21)
		var scene_uniforms: Dictionary = restored_link_material.get_value(&"uniforms")
		var scene_noise := ActorAnimation.resolve_reference(scene_uniforms[&"synced_noise"])
		check(is_equal_approx(float(scene_noise.get_value(&"frequency")), 0.21),
			"Scene inspector edits the current linked Noise Image rather than a detached copy")
		tabs.current_tab = linked_shader_tab
		var tab_noise := ActorAnimation.resolve_reference(shader_workspace.parameter_values[&"synced_noise"])
		check(is_equal_approx(float(tab_noise.get_value(&"frequency")), 0.21),
			"Scene-side Noise Image edits synchronize back to the linked shader tab")
		tabs.current_tab = 0
	binding_inspector.free()
	editor.restore_scene_data(scene_before_link_test)
	DirAccess.remove_absolute(shader_path)
	DirAccess.remove_absolute(preview_mesh_path)
	tabs.current_tab = 0
	camera.position = Vector3(4, 5, 6)
	camera.get_node("Head").rotation = Vector3(0.2, 0.3, 0.0)
	editor.set_video_duration(2.75)
	editor.undo()
	check(is_equal_approx(editor.video_duration, 10.0), "Video duration change can be undone")
	editor.redo()
	check(is_equal_approx(editor.video_duration, 2.75), "Video duration change can be redone")
	var parent_clip := editor.model.create_actor(editor.registry.get_definition(&"point_3d"), 2.0)
	var parent := editor.model.selected_actor()
	parent.display_name = "Saved Parent"
	var child_clip := editor.model.create_actor(editor.registry.get_definition(&"text_3d"), 4.0)
	var child := editor.model.selected_actor()
	child.parent_id = parent.id
	var track := ActorAnimationTrack.new()
	track.path = PackedStringArray(["position"])
	var key := ActorKeyframe.new()
	key.time = 1.25
	key.value = Vector3(3, 2, 1)
	track.keys.append(key)
	child.animation_tracks.append(track)
	editor.canvas.scroll_time = 6.5
	editor.canvas.scroll_rows = 72.0
	editor.canvas.pixels_per_second = 93.0
	editor.canvas.row_height = 61.0
	editor.canvas.playhead = 8.25
	editor.inspector_ui_state.set_scroll(child.id, 88.0)
	editor.inspector_ui_state.set_category_expanded(child.id, "Transform", false)
	editor.set_keyframe_view(true)
	var saved := editor.capture_scene_data()
	var path := "user://scene_data_test_" + ActorData.new_id() + ".tres"
	check(ResourceSaver.save(saved, path) == OK, "Complete editable scene saves as .tres")
	check(FileOperations.get_type_of_file(path) == FileOperations.FileType.SCENE,
		"Project filesystem recognizes editable scene files")
	check(await FileOperations.get_file_thumbnail(path) != null,
		"Editable scene files have a filesystem thumbnail")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	check(loaded != null and loaded.actors.size() == 2 and loaded.clips.size() == 2, "Scene reloads actors and clips")
	check(loaded.actors[1].parent_id == loaded.actors[0].id, "Scene reloads nested parenting")
	check(loaded.actors[1].animation_tracks.size() == 1 and loaded.actors[1].animation_tracks[0].keys.size() == 1,
		"Scene reloads keyframe tracks")
	check(is_equal_approx(float(loaded.timeline_section_states["default"].x), 6.5)
		and is_equal_approx(float(loaded.timeline_section_states["default"].zoom_y), 61.0),
		"Scene reloads timeline scroll and scale")
	check(is_equal_approx(loaded.inspector_state.scroll_for(child.id), 88.0)
		and not loaded.inspector_state.category_expanded(child.id, "Transform"),
		"Scene reloads per-actor inspector state")
	editor.restore_scene_data(loaded)
	check(editor.model.actors.size() == 2 and editor.model.selected_id == child_clip.id,
		"Editor restores scene selection and model")
	check(editor.keyframe_view.visible, "Editor restores keyframe workspace state")
	check(is_equal_approx(editor.video_duration, saved.video_duration), "Scene restores video duration")
	check(tabs.save_current(path) == OK and tabs.current_scene_path() == path,
		"Active scene acquires its saved path")
	menu._save()
	check(tabs.current_scene_path() == path,
		"Saving an existing scene uses its path without Save As")
	check(editor.get_node("../../../../World/SubViewport/Freecam").position.is_equal_approx(Vector3(4, 5, 6))
		and is_equal_approx(editor.get_node("../../../../World/SubViewport/Freecam/Head").rotation.y, 0.3),
		"Scene restores the viewport camera transform")
	var instance_model := ActorTimeline.new()
	var instance := instance_model.instantiate_scene(loaded, editor.registry.get_definition(&"point_3d"), 10.0, 0, "Nested Scene")
	check(instance != null and instance_model.actors.size() == 3, "Single-section scene instantiates beneath one point")
	var source_start := minf(loaded.clips[0].start_time, loaded.clips[1].start_time)
	var source_end := maxf(loaded.clips[0].start_time + loaded.clips[0].duration,
		loaded.clips[1].start_time + loaded.clips[1].duration)
	check(is_equal_approx(instance.duration, source_end - source_start), "Instance point spans source clip range")
	check(not instance_model.actors[0].show_timeline_children and instance_model.actors[0].link_timeline_children,
		"Instance point hides and links descendants by default")
	check(instance_model.actors[1].parent_id == instance_model.actors[0].id
		and instance_model.actors[2].parent_id == instance_model.actors[1].id,
		"Instance preserves remapped nested parents")
	check(instance_model.actors[2].animation_tracks.size() == 1,
		"Instance preserves source keyframes")
	instance_model.undo()
	check(instance_model.actors.is_empty(), "Instantiation undoes as one action")
	instance_model.redo()
	check(instance_model.actors.size() == 3, "Instantiation redoes as one action")
	var multi := loaded.duplicate(true) as ActorSceneData
	var other_section := ActorSection.new()
	other_section.id = "other"
	other_section.display_name = "Section Two"
	multi.sections.append(other_section)
	multi.actors[1].section_id = other_section.id
	var multi_model := ActorTimeline.new()
	multi_model.instantiate_scene(multi, editor.registry.get_definition(&"point_3d"), 0.0, 0, "Multiple Sections")
	check(multi_model.actors.size() == 5 and multi_model.actors[1].parent_id == multi_model.actors[0].id
		and multi_model.actors[2].parent_id == multi_model.actors[0].id,
		"Multiple sections become named point children")
	editor.reset_video_duration()
	var actor_end := 0.0
	for clip in editor.model.clips: actor_end = maxf(actor_end, clip.start_time + clip.duration)
	check(not editor.video_duration_is_custom() and is_equal_approx(editor.video_duration, actor_end),
		"Automatic video duration follows the rightmost actor")
	var camera_clip := editor.model.create_actor(editor.registry.get_definition(&"camera_3d"), 0.0)
	var camera_runtime := editor._runtime_for_clip(camera_clip.id)
	var actor_camera := camera_runtime.get("content") as Camera3D
	var camera_effect := editor.registry.get_object_definition(&"canvas_shader_material").create_object()
	var camera_effect_shader := Shader.new()
	camera_effect_shader.code = "shader_type canvas_item;\nvoid fragment() { COLOR = texture(TEXTURE, UV); }\n"
	camera_effect.set_value(&"shader_path", camera_effect_shader)
	editor.model.actor_for_id(camera_clip.actor_id).set_value(&"material", ActorObjectReference.from_object(camera_effect))
	editor._evaluate_runtimes()
	var guide := actor_camera.get_node_or_null("EditorCameraGuide") as MeshInstance3D
	check(guide != null and guide.layers == 2 and actor_camera.cull_mask == 1,
		"Camera actor has an editor-only shape that cannot appear in rendered footage")
	editor.canvas.playhead = camera_clip.start_time + 0.5
	editor._evaluate_runtimes()
	await process_frame
	check(editor.viewport_gizmo.preview_active and editor.viewport_gizmo.preview_lens.cull_mask == 1,
		"Selecting a camera shows its render-only view in the viewport overlay")
	check(editor.viewport_gizmo.camera_preview.find_world_3d() == viewport.find_world_3d(),
		"Camera preview uses the scene viewport's actual 3D world")
	check(editor.viewport_gizmo.preview_shader_overlay.visible
		and editor.viewport_gizmo.preview_shader_overlay.material == camera_runtime.camera_shader_material
		and camera_runtime.camera_overlay.size.is_equal_approx(Vector2(viewport.size)),
		"Selected camera preview and full-frame output share the Canvas post-process")
	check(SceneExporter._render_camera_for_time(editor, viewport, camera.get_node("Head/Camera3D"), editor.canvas.playhead) == actor_camera,
		"Export selects an active camera actor")
	editor._update_camera_overlays()
	check(camera_runtime.camera_overlay.visible,
		"Export camera selection activates only its full-frame shader pass")
	check(SceneExporter._render_camera_for_time(editor, viewport, camera.get_node("Head/Camera3D"), 999.0) == camera.get_node("Head/Camera3D"),
		"Export falls back to the editor camera when no camera actor is active")
	editor._update_camera_overlays()
	check(not camera_runtime.camera_overlay.visible,
		"Camera shader pass hides when a different camera is rendering")
	editor._evaluate_runtimes()
	var particles_clip := editor.model.create_actor(editor.registry.get_definition(&"particles_3d"), 0.0)
	editor.canvas.playhead = particles_clip.start_time + 1.0
	editor._evaluate_runtimes()
	var particle_runtime := editor._runtime_for_clip(particles_clip.id)
	var particles := particle_runtime.get("content") as GPUParticles3D
	var seek_state: Dictionary = editor._particle_seek_states.get(particles_clip.id, {})
	check(not seek_state.is_empty() and is_zero_approx(particles.speed_scale) and particles.use_fixed_seed,
		"Paused particle emitters seek to the playhead and do not keep simulating")
	editor._evaluate_runtimes()
	check(editor._particle_seek_states.get(particles_clip.id, {}) == seek_state,
		"Repeated evaluation at the same playhead does not restart particles")
	editor.canvas.playhead += 0.25
	editor._evaluate_runtimes()
	check(float(editor._particle_seek_states.get(particles_clip.id, {}).get("time", 0.0)) > float(seek_state.time),
		"Scrubbing advances particles to the new local time")
	var particles_2d_clip := editor.model.create_actor(editor.registry.get_definition(&"particles_2d"), 0.0)
	editor.canvas.playhead = particles_2d_clip.start_time + 0.5
	editor._evaluate_runtimes()
	var particles_2d_runtime := editor._runtime_for_clip(particles_2d_clip.id)
	var particles_2d := particles_2d_runtime.get("particles_2d") as GPUParticles2D
	check(particles_2d != null and is_zero_approx(particles_2d.speed_scale) and particles_2d.use_fixed_seed
		and editor._particle_seek_states.has(particles_2d_clip.id),
		"2D particle emitters use the same paused seek behavior")
	particles_2d_clip.start_time = camera_clip.start_time
	editor.canvas.playhead = camera_clip.start_time + 0.5
	editor.model.select(camera_clip.id)
	editor._evaluate_runtimes()
	await process_frame
	check(editor.viewport_gizmo.preview_clones.has(particles_2d_clip.id),
		"Selected-camera preview includes screen-space 2D actors")
	if DisplayServer.get_name() != "headless":
		var shape_clip := editor.model.create_actor(editor.registry.get_definition(&"basic_shape_2d"), camera_clip.start_time)
		shape_clip.start_time = camera_clip.start_time
		editor.model.actor_for_id(shape_clip.actor_id).set_value(&"color", Color.RED)
		editor.canvas.playhead = camera_clip.start_time + 0.5
		editor.model.select(camera_clip.id)
		editor._evaluate_runtimes()
		await process_frame
		await RenderingServer.frame_post_draw
		var preview_image := editor.viewport_gizmo.camera_preview.get_texture().get_image()
		var center_pixel := preview_image.get_pixel(preview_image.get_width() / 2, preview_image.get_height() / 2)
		check(center_pixel.r > 0.7 and center_pixel.g < 0.3,
			"Camera preview actually renders a 2D actor, rather than an empty gray viewport")
		shape_clip.start_time = 100.0
		var marker := MeshInstance3D.new()
		marker.mesh = BoxMesh.new()
		var marker_material := StandardMaterial3D.new()
		marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker_material.albedo_color = Color.GREEN
		marker.material_override = marker_material
		viewport.add_child(marker)
		marker.global_position = actor_camera.global_position - actor_camera.global_transform.basis.z * 3.0
		editor._evaluate_runtimes()
		await process_frame
		await RenderingServer.frame_post_draw
		preview_image = editor.viewport_gizmo.camera_preview.get_texture().get_image()
		center_pixel = preview_image.get_pixel(preview_image.get_width() / 2, preview_image.get_height() / 2)
		check(center_pixel.g > 0.7 and center_pixel.g > center_pixel.r + 0.3,
			"Camera preview renders 3D scene geometry from the same world: " + str(center_pixel))
		marker.queue_free()
		particles_2d_clip.start_time = 100.0
		particles_clip.start_time = 100.0
		var background := WorldEnvironment.new()
		var background_resource := Environment.new()
		background_resource.background_mode = Environment.BG_COLOR
		background_resource.background_color = Color.BLUE
		background.environment = background_resource
		viewport.add_child(background)
		editor._evaluate_runtimes()
		await process_frame
		await RenderingServer.frame_post_draw
		preview_image = editor.viewport_gizmo.camera_preview.get_texture().get_image()
		center_pixel = preview_image.get_pixel(preview_image.get_width() / 2, preview_image.get_height() / 2)
		check(center_pixel.b > center_pixel.r + 0.3 and center_pixel.b > center_pixel.g + 0.3,
			"Camera preview follows the scene environment instead of using a gray default: " + str(center_pixel))
		background.queue_free()
	if not ActorVideo.executable("ffmpeg").is_empty():
		var audio_actor := editor.registry.get_definition(&"audio").create_actor()
		audio_actor.values[&"pitch"] = 1.25
		audio_actor.values[&"fade_in"] = 0.1
		var audio_clip := ActorClip.create(audio_actor, 0.2, 0.5)
		audio_clip.playback_speed = 1.5
		var filter: String = SceneExporter._audio_filter(audio_actor, audio_clip, 0, 0.5)
		var ffmpeg_output: Array = []
		var ffmpeg_error := OS.execute(ActorVideo.executable("ffmpeg"), PackedStringArray([
			"-nostdin", "-v", "error", "-f", "lavfi", "-i", "color=s=16x16:r=24:d=1",
			"-f", "lavfi", "-i", "sine=d=1", "-filter_complex", filter,
			"-map", "[a0]", "-f", "null", "-"]), ffmpeg_output, true)
		check(ffmpeg_error == 0, "Export audio filter handles trim, pitch, speed, gain and fade: " + "".join(ffmpeg_output))
	if DisplayServer.get_name() != "headless" and not ActorVideo.executable("ffmpeg").is_empty():
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.stereo = true
		wav.mix_rate = 44100
		var pcm := PackedByteArray()
		pcm.resize(4410 * 4)
		for sample in 4410:
			var amplitude := roundi(sin(float(sample) * TAU * 440.0 / 44100.0) * 10000.0)
			pcm.encode_s16(sample * 4, amplitude)
			pcm.encode_s16(sample * 4 + 2, amplitude)
		wav.data = pcm
		editor.model.create_actor(editor.registry.get_definition(&"audio"), 0.0, {&"audio": wav})
		editor.set_video_duration(0.08)
		var video_path := "user://scene_export_test_" + ActorData.new_id() + ".mp4"
		var export_error: String = await SceneExporter.render(editor, video_path, 64, 64, 24)
		check(export_error.is_empty() and FileAccess.file_exists(video_path),
			"Scene exports viewport frames to MP4: " + export_error)
		if FileAccess.file_exists(video_path):
			check(bool(ActorVideo.info(video_path).get("audio", false)), "Exported MP4 contains the mixed audio actor")
		if FileAccess.file_exists(video_path): DirAccess.remove_absolute(video_path)
	var export_menu := ActorSceneExportButton.new()
	toolbar.add_child(export_menu)
	export_menu.timeline = editor
	export_menu._open()
	check(export_menu.panel != null and export_menu.panel.visible,
		"Video export settings open as a persistent in-editor panel")
	var save_picker := PopupPanel.new()
	export_menu.add_child(save_picker)
	save_picker.popup_centered(Vector2i(180, 90))
	save_picker.hide()
	export_menu._set_destination("res://Exports/Scene.mp4")
	check(export_menu.panel.visible and export_menu.destination_label.text.contains("Scene.mp4")
		and export_menu.destination_label.text.contains("Exports")
		and export_menu.status_label.text.contains("Ready to export"),
		"Choosing a location keeps export settings open and confirms the selected path")
	export_menu._choose_project()
	await process_frame
	var project_save_dialog: ActorProjectResourceSaveDialog
	for child_node in export_menu.get_children():
		if child_node is ActorProjectResourceSaveDialog:
			project_save_dialog = child_node
			break
	check(project_save_dialog != null, "Project export location opens the project save browser")
	if project_save_dialog != null:
		project_save_dialog._resolve({"cancelled": false, "embedded": false, "path": "res://Exports/Chosen.mp4"})
		await process_frame
		check(export_menu.panel.visible and export_menu.destination_label.text.contains("Chosen.mp4")
			and export_menu.project_button.text.begins_with("✓")
			and not export_menu.computer_button.text.begins_with("✓"),
			"Returning from the real project save browser keeps export settings and confirms the chosen file")
	export_menu._set_destination("C:/Videos/Scene.mp4", "anywhere")
	check(export_menu.computer_button.text.begins_with("✓")
		and not export_menu.project_button.text.begins_with("✓"),
		"Choosing a computer location highlights Anywhere instead of Project files")
	export_menu._choose_project()
	await process_frame
	for child_node in export_menu.get_children():
		if child_node is ActorProjectResourceSaveDialog and child_node.visible:
			child_node._resolve({"cancelled": true, "embedded": false, "path": ""})
			break
	await process_frame
	check(export_menu.computer_button.text.begins_with("✓") and not export_menu.project_button.text.begins_with("✓"),
		"Canceling a location picker preserves the previously chosen destination")
	export_menu._close()
	var image_path := "user://image_workspace_" + ActorData.new_id() + ".png"
	var starting_image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	starting_image.fill(Color.RED)
	check(starting_image.save_png(image_path) == OK, "Create image editor test file")
	check(tabs.open_image(image_path) and tabs.image_workspace.visible
		and tabs.image_workspace.document.canvas_size.x == 8,
		"Opening a project image creates a dedicated image workspace tab")
	var image_tab_count := tabs.documents.size()
	tabs.open_image(image_path)
	check(tabs.documents.size() == image_tab_count,
		"Opening the same image again activates its existing tab")
	tabs.image_workspace._action(func():
		var edited := Image.create(8,8,false,Image.FORMAT_RGBA8)
		edited.fill(Color.BLUE)
		tabs.image_workspace.document.layers[0].texture=ImageTexture.create_from_image(edited))
	check(bool(tabs.documents[tabs.current_tab].dirty), "Image edits mark the image tab unsaved")
	tabs.image_workspace.undo()
	check(tabs.image_workspace.document.layers[0].texture.get_image().get_pixel(0, 0) == Color.RED, "Image editor undo restores pixels")
	tabs.image_workspace.redo()
	check(tabs.image_workspace.document.layers[0].texture.get_image().get_pixel(0, 0) == Color.BLUE,
		"Image editor redo restores the edited layer")
	var image_document_path := "user://image_document_" + ActorData.new_id() + ".tres"
	check(ResourceSaver.save(tabs.image_workspace.document,image_document_path)==OK,"Save native image composition")
	tabs._filesystem_resource_opened(image_document_path)
	check(tabs.image_workspace.visible and tabs.image_workspace.path==image_document_path,
		"Double-clicking a native image document opens Image Studio")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(image_document_path))
	var source_path := "user://shader_workspace_load_" + ActorData.new_id() + ".gdshader"
	var source_file := FileAccess.open(source_path, FileAccess.WRITE)
	source_file.store_string("shader_type canvas_item;\nvoid fragment() { COLOR = vec4(0.2, 0.4, 0.8, 1.0); }\n")
	source_file.close()
	tabs.new_shader()
	check(tabs.shader_workspace.load_shader_button.visible, "Unsaved shader tab offers Load Shader")
	var before_load_count := tabs.documents.size()
	tabs.load_shader_into_current_tab(source_path)
	check(tabs.documents.size() == before_load_count and tabs.shader_workspace.current_path == source_path
		and tabs.shader_workspace.editor.code.text.contains("shader_type canvas_item")
		and not tabs.shader_workspace.load_shader_button.visible,
		"Load Shader replaces the unsaved shader in its current tab")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(source_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(image_path))
	DirAccess.remove_absolute(path)
	outer.free()
	await process_frame
	print("Scene data checks: %d failures" % failures)
	quit(failures)
