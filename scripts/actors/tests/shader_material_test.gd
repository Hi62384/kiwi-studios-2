extends SceneTree

var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var registry := ActorRegistry.new()
	BasicActors.register_all(registry)
	var image_definition := registry.get_definition(&"image_3d")
	var shader_definition := registry.get_object_definition(&"shader_material")
	check(shader_definition != null, "ShaderMaterial definition is registered")
	check(shader_definition.base_type == &"material", "ShaderMaterial is creation-compatible with Material")
	check(shader_definition.find_property(&"shader_path").options.extensions == ["gdshader"], "Shader property only accepts gdshader files")
	check(shader_definition.find_property(&"shader_path").options.get("create_file", false), "Shader property allows creating a new gdshader file")
	var embedded_shader := Shader.new()
	embedded_shader.code = "shader_type spatial;"
	check(shader_definition.find_property(&"shader_path").accepts(embedded_shader), "Shader property accepts an embedded Shader resource")
	var empty_shader_actor := image_definition.create_actor()
	empty_shader_actor.set_value(&"material", ActorObjectReference.from_object(shader_definition.create_object()))
	var empty_shader_runtime := image_definition.create_runtime(empty_shader_actor)
	root.add_child(empty_shader_runtime)
	empty_shader_runtime.evaluate_clip(ActorClip.create(empty_shader_actor), 0.0)
	var empty_shader_mesh := empty_shader_runtime.get_child(0) as MeshInstance3D
	check(empty_shader_mesh.material_override is ShaderMaterial and (empty_shader_mesh.material_override as ShaderMaterial).shader == null, "A new ShaderMaterial safely renders before a Shader is assigned")
	empty_shader_runtime.free()
	var actor := image_definition.create_actor()
	var shader_object := shader_definition.create_object()
	shader_object.set_value(&"shader_path", "res://scripts/actors/tests/fixtures/uniforms_test.gdshader")
	shader_object.set_value(&"uniforms", {&"strength": 2.5, &"tint": Vector3(0.2, 0.4, 0.8)})
	var reference := ActorObjectReference.from_object(shader_object)
	check(image_definition.find_property(&"material").accepts(reference), "Material slot accepts ShaderMaterial")
	actor.set_value(&"material", reference)
	var runtime := image_definition.create_runtime(actor)
	root.add_child(runtime)
	runtime.evaluate_clip(ActorClip.create(actor), 0.0)
	var mesh := runtime.get_child(0) as MeshInstance3D
	check(mesh.material_override is ShaderMaterial, "Image actor uses ShaderMaterial in the viewport")
	var live_material := mesh.material_override as ShaderMaterial
	check(is_equal_approx(float(live_material.get_shader_parameter(&"strength")), 2.5), "Float uniform reaches runtime ShaderMaterial")
	check(live_material.get_shader_parameter(&"tint") == Vector3(0.2, 0.4, 0.8), "Vector uniform reaches runtime ShaderMaterial")
	var model := ActorTimeline.new()
	model.create_actor(image_definition, 0.0)
	model.selected_actor().set_value(&"material", ActorObjectReference.from_object(shader_object))
	var inspector := ActorInspector.new()
	root.add_child(inspector)
	inspector.size = Vector2(320, 220)
	inspector.setup(model, registry, ActorInspectorState.new())
	var material_slot := inspector.find_child("material_resource", true, false) as ActorResourceSlot
	check(material_slot != null and material_slot.text.contains("ShaderMaterial"), "Material slot identifies its concrete ShaderMaterial")
	var strength_input := inspector.find_child("strength_value", true, false) as DragNumber
	var tint_x := inspector.find_child("tint_0", true, false) as DragNumber
	var mask_slot := inspector.find_child("mask_texture_file", true, false) as ActorResourceSlot
	check(strength_input != null and tint_x != null and mask_slot != null, "Shader uniforms generate number, vector, and texture controls")
	if tint_x != null:
		var tint_default: Variant = inspector._shader_uniform_default(ResourceLoader.load("res://scripts/actors/tests/fixtures/uniforms_test.gdshader") as Shader, &"tint", TYPE_VECTOR3)
		tint_x.interaction_started.emit()
		tint_x.preview_changed.emit(0.65)
		check(is_equal_approx(float((shader_object.get_value(&"uniforms") as Dictionary)[&"tint"].x), 0.65), "Dragging a vector component previews and stores the new value")
		tint_x.drag_committed.emit(0.65)
		model.undo()
		check(is_equal_approx(float((shader_object.get_value(&"uniforms") as Dictionary)[&"tint"].x), 0.2), "Vector uniform drag creates one undo action")
		tint_x.value_changed.emit(0.9)
		var tint_reset := inspector.find_child("tint_reset", true, false) as Button
		check(tint_reset != null and tint_reset.visible, "Changed vector uniform can be reset")
		if tint_reset != null:
			tint_reset.pressed.emit()
			await process_frame
			check((shader_object.get_value(&"uniforms") as Dictionary)[&"tint"] == tint_default, "Vector uniform reset persists its shader default")
	var shader_slot := inspector.find_child("shader_path_file", true, false) as ActorResourceSlot
	var open_workspace := inspector.find_child("shader_path_open_workspace", true, false) as Button
	check(open_workspace != null and open_workspace.visible and open_workspace.text.contains("Edit"),
		"Every populated shader property exposes an explicit full-workspace editor button")
	var shader_menu := shader_slot.get_child(0) as PopupMenu if shader_slot != null else null
	check(shader_menu != null and shader_menu.get_item_text(shader_menu.get_item_index(0)) == "New Shader" and shader_menu.get_item_text(shader_menu.get_item_index(1)) == "Load from project…" and shader_menu.get_item_text(shader_menu.get_item_index(2)) == "Make Unique" and shader_menu.get_item_text(shader_menu.get_item_index(3)) == "Save As…" and shader_menu.get_item_text(shader_menu.get_item_index(4)) == "Clear", "Shader uses the unified resource menu")
	if strength_input != null:
		strength_input.value_changed.emit(3.25)
		check(is_equal_approx(float((shader_object.get_value(&"uniforms") as Dictionary)[&"strength"]), 3.25), "Uniform editing updates ShaderMaterial data")
		model.undo()
		check(is_equal_approx(float((shader_object.get_value(&"uniforms") as Dictionary)[&"strength"]), 2.5), "Uniform edits participate in undo")
		var selected_material_actor := model.selected_actor()
		var selected_material_path := ActorAnimation.path_to_object(selected_material_actor, shader_object)
		var live_binding := inspector.shader_workspace_parameter_binding(
			selected_material_actor.id, selected_material_path, selected_material_actor)
		(live_binding["writer"] as Callable).call(&"strength", 4.75, "edit", null)
		check(is_equal_approx(strength_input.value, 4.75),
			"Linked shader-tab parameter edits refresh the visible scene inspector immediately")
		model.undo()
	var editor := ShaderCodeEditor.new()
	root.add_child(editor)
	check(editor.workspace_picker.item_count == 2
		and editor.workspace_picker.get_item_text(0) == "Scene Tree"
		and editor.workspace_picker.get_item_text(1) == "Shader Editor"
		and editor.workspace_picker.selected == 0 and editor.scene_tree.visible,
		"Right editor starts in the Scene Tree workspace")
	shader_slot.pressed.emit()
	check(editor.current_path.ends_with("uniforms_test.gdshader"), "Clicking a populated Shader slot opens that shader in the code editor")
	check(editor.workspace_picker.selected == 1 and editor.shader_workspace.visible,
		"Opening a shader switches to the Shader Editor workspace")
	check(editor.code.text.contains("uniform float strength"), "Shader editor opens gdshader source")
	var file_material_before_notification := mesh.material_override as ShaderMaterial
	editor._notify_shader_changed(editor.current_path)
	check(mesh.material_override != file_material_before_notification,
		"Saving a filesystem shader directly refreshes live actor runtimes")
	editor.code.code_completion_requested.emit()
	check(editor.code.code_completion_enabled and editor.code.gutters_draw_line_numbers, "Shader editor enables completion and line numbers")
	check(editor.find_children("*", "Button", true, false).all(func(button: Button): return button.text != "Save"), "Shader editor has no manual Save control")
	check(editor.documentation_button.text.contains("Shader docs"), "Shader editor offers documentation instead of an insert-code menu")
	check(editor.documentation != null and editor.documentation.TOPICS.size() >= 18, "Shader documentation has a substantial reference and sample library")
	var documentation_titles := PackedStringArray(editor.documentation.TOPICS.map(func(topic: Dictionary): return str(topic.title)))
	check(documentation_titles.has("Spatial vertex()") and documentation_titles.has("Spatial fragment()")
		and documentation_titles.has("Spatial light()") and documentation_titles.has("Global constants and values")
		and documentation_titles.has("Texture lookup"),
		"Shader documentation covers processor functions, built-ins, constants, and function families")
	check(not documentation_titles.has("Types and uniforms") and not documentation_titles.has("Shader anatomy"),
		"Shader documentation omits elementary language primers")
	editor.documentation.open()
	await process_frame
	check(editor.documentation.visible and editor.documentation.search != null, "Shader documentation opens with searchable topic navigation")
	editor.documentation._select_topic(0)
	await process_frame
	check(editor.documentation.find_child("CopyShaderSample", true, false) is Button, "Documentation code samples can be copied")
	editor.documentation.hide()
	# Reproduce the Windows failure exactly: save invalid filesystem source, then
	# immediately save corrected source and require the runtime to see it without
	# a uniform/property edit forcing a later reevaluation.
	var recovery_path := "user://actor_shader_save_recovery.gdshader"
	var recovery_file := FileAccess.open(recovery_path, FileAccess.WRITE)
	recovery_file.store_string("shader_type spatial;\nvoid fragment() { ALBEDO = vec3(0.2); }\n")
	recovery_file.close()
	shader_object.set_value(&"shader_path", recovery_path)
	runtime.evaluate_clip(ActorClip.create(actor), 0.0)
	editor.open_shader(recovery_path)
	editor.code.text = "shader_type spatial;\nvoid fragment() { BROKEN_SHADER }\n"
	editor.save()
	var failed_file_material := mesh.material_override as ShaderMaterial
	editor.code.text = "shader_type spatial;\nuniform float file_recovered = 0.6;\nvoid fragment() { ALBEDO = vec3(file_recovered); }\n"
	editor.save()
	var recovered_file_material := mesh.material_override as ShaderMaterial
	check(recovered_file_material != failed_file_material
		and recovered_file_material.shader.code.contains("file_recovered"),
		"Corrected filesystem shader is flushed, closed, and refreshed immediately")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(recovery_path))
	shader_object.set_value(&"shader_path", "res://scripts/actors/tests/fixtures/uniforms_test.gdshader")
	runtime.evaluate_clip(ActorClip.create(actor), 0.0)
	editor.open_shader("res://scripts/actors/tests/fixtures/uniforms_test.gdshader")
	var other_focus := FocusableKeyInput.new()
	FocusableKeyInput.current_focused_instance = other_focus
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	editor._code_input(click)
	check(FocusableKeyInput.current_focused_instance == null, "Clicking the shader editor releases filesystem keyboard focus")
	other_focus.free()
	# Shader save notifications rebuild the inspector asynchronously; the docs UI
	# test above yields frames, so reacquire the current resource menu.
	shader_slot = inspector.find_child("shader_path_file", true, false) as ActorResourceSlot
	shader_menu = shader_slot.get_child(0) as PopupMenu if shader_slot != null else null
	shader_menu.id_pressed.emit(0)
	var newly_created_shader := shader_object.get_value(&"shader_path") as Shader
	check(newly_created_shader != null and editor.current_shader == newly_created_shader and editor.current_path.is_empty(), "New Shader creates and opens an embedded Shader without a save dialog")
	runtime.evaluate_clip(ActorClip.create(actor), 0.0)
	var material_before_live_edit := mesh.material_override as ShaderMaterial
	editor.code.text = "shader_type spatial;\nuniform float live_amount = 0.75;\nvoid fragment() { ALBEDO = vec3(live_amount); }\n"
	editor.save()
	await process_frame
	await process_frame
	check(inspector.find_child("live_amount_value", true, false) is DragNumber, "Editing shader code rebuilds the exposed uniform parameters")
	check(mesh.material_override != material_before_live_edit and (mesh.material_override as ShaderMaterial).shader.code == newly_created_shader.code and newly_created_shader.code.contains("live_amount"), "Embedded Shader resources directly refresh their live actor runtime")
	var uniforms_heading_reset := inspector.find_children("*", "Button", true, false).any(func(button: Button): return button.text == "↺" and button.get_parent().get_child(0) is Label and (button.get_parent().get_child(0) as Label).text == "Uniforms")
	check(not uniforms_heading_reset, "Uniforms heading does not display an irrelevant reset button")
	var live_input := inspector.find_child("live_amount_value", true, false) as DragNumber
	if live_input != null:
		var declared_default := live_input.value
		live_input.value_changed.emit(2.0)
		var live_reset := inspector.find_child("live_amount_reset", true, false) as Button
		check(live_reset != null and live_reset.visible, "Changed shader uniform displays its reset button")
		if live_reset != null:
			live_reset.pressed.emit()
			await process_frame
			check(is_equal_approx(float((shader_object.get_value(&"uniforms") as Dictionary).get(&"live_amount", -1.0)), declared_default), "Resetting a shader uniform restores its declared value in the resource")
			var reset_input := inspector.find_child("live_amount_value", true, false) as DragNumber
			check(reset_input != null and is_equal_approx(reset_input.value, declared_default), "Resetting a shader uniform refreshes its inspector control immediately")
	editor.code.text = "shader_type spatial;\nuniform float broken\nvoid fragment() { ALBEDO = vec3(1.0);\n"
	editor._validate_syntax()
	check(editor.diagnostics.visible and editor.diagnostics.text.contains("Line"), "Shader syntax errors are shown with line diagnostics")
	editor.code.text = "shader_type spatial;\nuniform float repeated;\nuniform float repeated;\nrandom_letters\nvoid fragment() { ALBEDO = vec3(1.0); }\n"
	editor._validate_syntax()
	check(editor.diagnostics.text.contains("already declared") and editor.diagnostics.text.contains("Unexpected token"), "Diagnostics catch duplicate variables and stray text")
	editor.code.text = "shader_type spatial;\nfloat scoped_value(float input_value) {\n\tfloat result = input_value;\n\treturn result;\n}\nfloat another_scope(float input_value) {\n\tfloat result = input_value;\n\treturn result;\n}\nvoid fragment() {\n\tfloat result = 1.0;\n\tALBEDO = vec3(result);\n}\n"
	editor._validate_syntax()
	check(not editor.diagnostics.text.contains("already declared"), "Shader diagnostics allow the same variable name in different function scopes")
	editor.code.text = "shader_type spatial;\nstruct Sample { vec3 color; };\nfloat blend(float input_value) {\n\tfloat blend = input_value;\n\tfor (int i = 0; i < 3; i++) {\n\t\tif (i == 1) { break; }\n\t}\n\tfloat other = 2.0;\n\treturn blend *\n\t\tother;\n}\nvoid fragment() {\n\tSample sample = Sample(vec3(blend(1.0)));\n\tALBEDO = sample.color;\n}\n"
	editor._validate_syntax()
	check(not editor.diagnostics.visible, "Structs, break, function-name locals, and multiline expressions are valid shader syntax")
	editor.code.text = "shader_type spatial;\nstruct SurfaceData\n{\n\tvec3 color;\n};\nvoid fragment() {\n\tSurfaceData surface = SurfaceData(vec3(1.0));\n\tALBEDO = surface.color;\n}\n"
	editor._validate_syntax()
	check(not editor.diagnostics.visible, "Struct declarations also work with a brace on the following line: " + editor.diagnostics.text)
	editor.save()
	await process_frame
	await process_frame
	var failed_runtime_material := mesh.material_override as ShaderMaterial
	editor.code.text = "shader_type spatial;\nuniform float recovered = 0.4;\nvoid fragment() { ALBEDO = vec3(recovered); }\n"
	editor.save()
	await process_frame
	await process_frame
	var recovered_uniform := newly_created_shader.get_shader_uniform_list().any(func(info: Dictionary): return str(info.get("name", "")) == "recovered")
	var recovered_material := mesh.material_override as ShaderMaterial
	check(recovered_uniform and recovered_material != failed_runtime_material and recovered_material.shader.code == newly_created_shader.code, "Fixing invalid shader code creates a fresh runtime material and restores the visual shader")
	# Shader tabs persist while scene tabs restore fresh ActorData resources. A
	# linked parameter binding must follow the stable actor ID/object path rather
	# than continuing to edit the detached material instance it first opened.
	var replacement_model := ActorTimeline.new()
	replacement_model.create_actor(image_definition, 0.0)
	var replaceable_actor := replacement_model.selected_actor()
	var replaceable_material := shader_definition.create_object()
	replaceable_material.set_value(&"shader_path", embedded_shader)
	replaceable_material.set_value(&"uniforms", {&"strength": 1.0})
	replaceable_actor.set_value(&"material", ActorObjectReference.from_object(replaceable_material))
	var replacement_inspector := ActorInspector.new()
	root.add_child(replacement_inspector)
	replacement_inspector.setup(replacement_model, registry, ActorInspectorState.new())
	var material_path := ActorAnimation.path_to_object(replaceable_actor, replaceable_material)
	var replacement_binding := replacement_inspector.shader_workspace_parameter_binding(replaceable_actor.id, material_path, replaceable_actor)
	var restored_actor := replaceable_actor.copy_actor()
	restored_actor.id = replaceable_actor.id
	replacement_model.actors[replacement_model.actors.find(replaceable_actor)] = restored_actor
	(replacement_binding["writer"] as Callable).call(&"strength", 6.5, "edit", null)
	var restored_reference := restored_actor.get_value(&"material") as ActorObjectReference
	var restored_material := ActorAnimation.resolve_reference(restored_reference)
	check(is_equal_approx(float((restored_material.get_value(&"uniforms") as Dictionary)[&"strength"]), 6.5),
		"A linked shader tab writes parameters into the live restored material instance")
	check(is_equal_approx(float((replaceable_material.get_value(&"uniforms") as Dictionary)[&"strength"]), 1.0),
		"A linked shader tab does not write into its detached original material")
	replacement_model.actors.clear()
	(replacement_binding["writer"] as Callable).call(&"strength", 4.25, "edit", null)
	check(is_equal_approx(float((replaceable_material.get_value(&"uniforms") as Dictionary)[&"strength"]), 4.25),
		"A shader tab remains linked to its originating scene while another scene is loaded")
	# Layout-driven scrollbar resets must not overwrite the per-actor position
	# while selection is moving between actors.
	await process_frame
	await process_frame
	var first_actor_id := model.selected_id
	var scroll_bar := inspector.get_v_scroll_bar()
	var available_scroll := maxf(0.0, scroll_bar.max_value - scroll_bar.page)
	var remembered_scroll := minf(90.0, available_scroll)
	inspector.scroll_vertical = int(remembered_scroll)
	await process_frame
	model.create_actor(image_definition, 7.0)
	model.select(first_actor_id)
	await process_frame
	await process_frame
	check(remembered_scroll <= 0.0 or absf(float(inspector.scroll_vertical) - remembered_scroll) <= 1.0,
		"Selecting another actor and returning preserves the inspector scroll position")
	replacement_inspector.free()
	runtime.free()
	inspector.free()
	editor.free()
	await process_frame
	print("Shader material checks: ", failures, " failures")
	quit(1 if failures else 0)
