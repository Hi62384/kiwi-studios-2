extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var editor := ActorTimelineEditor.new()
	root.add_child(editor)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	root.add_child(viewport)
	editor.runtime_holder = Node3D.new()
	viewport.add_child(editor.runtime_holder)
	var gizmo := ActorUIGizmo.new()
	gizmo.editor = editor
	viewport.add_child(gizmo)
	var model := editor.model
	var shape := editor.registry.get_definition(&"basic_shape_2d")
	var clip := model.create_actor(shape, 0)
	var actor := model.selected_actor()
	var runtime := editor._runtime_for_clip(clip.id) as ActorUIRuntime
	check(runtime != null and runtime.anchor.position.is_equal_approx(Vector2(400, 300)), "2D actors render centered in screen-space")
	check(runtime.visual.shape == 0, "2D shape starts as a rectangle")
	var canvas_definition := editor.registry.get_object_definition(&"canvas_shader_material")
	check(canvas_definition != null and canvas_definition.base_type == &"shader_material",
		"Canvas ShaderMaterial is registered as a shader material resource")
	check(canvas_definition.find_property(&"shader_path").options.new_file_template.contains("shader_type canvas_item"),
		"Creating a shader from a Canvas ShaderMaterial starts with a canvas_item shader")
	for type_id in [&"text_2d", &"image_2d", &"video_2d", &"basic_shape_2d", &"line_2d", &"particles_2d"]:
		var material_property := editor.registry.get_definition(type_id).find_property(&"material")
		check(material_property != null and material_property.object_type == &"canvas_shader_material",
			str(type_id) + " exposes a Canvas Shader property")
	var canvas_object := canvas_definition.create_object()
	actor.set_value(&"material", ActorObjectReference.from_object(canvas_object))
	runtime.evaluate_clip(clip, 0.0)
	check(runtime.visual.material == null,
		"A newly-created Canvas ShaderMaterial safely renders before its Shader is created")
	var canvas_shader := Shader.new()
	canvas_shader.code = "shader_type canvas_item;\nuniform vec4 tint : source_color = vec4(1.0);\nvoid fragment() { COLOR = texture(TEXTURE, UV) * tint; }\n"
	canvas_object.set_value(&"shader_path", canvas_shader)
	canvas_object.set_value(&"uniforms", {&"tint": Color(0.2, 0.7, 0.9, 1.0)})
	actor.set_value(&"material", ActorObjectReference.from_object(canvas_object))
	runtime.evaluate_clip(clip, 0.0)
	check(runtime.visual.material is ShaderMaterial
		and (runtime.visual.material as ShaderMaterial).shader.code.contains("shader_type canvas_item")
		and (runtime.visual.material as ShaderMaterial).get_shader_parameter(&"tint") == Color(0.2, 0.7, 0.9, 1.0),
		"Canvas shaders and their parameters are applied to 2D actor visuals")
	check(runtime.visual.solid_texture != null and runtime.visual.solid_texture.get_size() == Vector2(1, 1),
		"2D basic shapes provide a white sampling texture for CanvasItem shader TEXTURE and UV")
	var canvas_shader_path := "user://canvas_shape_" + ActorData.new_id() + ".gdshader"
	var shader_file := FileAccess.open(canvas_shader_path, FileAccess.WRITE)
	shader_file.store_string(canvas_shader.code)
	shader_file.close()
	canvas_object.set_value(&"shader_path", canvas_shader_path)
	runtime.evaluate_clip(clip, 0.0)
	check(runtime.visual.material is ShaderMaterial
		and (runtime.visual.material as ShaderMaterial).shader.code.contains("shader_type canvas_item"),
		"2D basic shapes also apply CanvasItem shaders loaded from .gdshader files")
	gizmo.begin_drag(&"position", Vector2(400, 300))
	gizmo.update_drag(Vector2(450, 280))
	check(actor.get_value(&"position") == Vector2(50, -20), "Move gizmo previews actor position live")
	gizmo.finish_drag()
	model.undo()
	check(actor.get_value(&"position") == Vector2.ZERO, "Move gesture undoes as one action")
	model.redo()
	check(actor.get_value(&"position") == Vector2(50, -20), "Move gesture redoes")
	gizmo.begin_drag(&"rotation", runtime.anchor.position + Vector2(100, 0))
	gizmo.update_drag(runtime.anchor.position + Vector2(0, 100))
	gizmo.finish_drag()
	check(is_equal_approx(actor.get_value(&"rotation"), 90), "Rotation gizmo changes rotation")
	model.undo()
	gizmo.begin_drag(&"scale", runtime.anchor.position + Vector2(100, 0))
	gizmo.update_drag(runtime.anchor.position + Vector2(200, 0))
	gizmo.finish_drag()
	check(actor.get_value(&"scale") == Vector2(2, 2), "Scale handles resize actors")
	model.undo()
	gizmo.begin_drag(&"position", runtime.anchor.position)
	gizmo.update_drag(runtime.anchor.position + Vector2(100, 0))
	gizmo.finish_drag(true)
	check(actor.get_value(&"position") == Vector2(50, -20), "Esc restores original transform")
	model.selected_layer = 3
	var parent_clip := model.create_actor(shape, 0, {&"position": Vector2(-100, 80), &"scale": Vector2(2, 2)})
	var parent := model.actor_for_id(parent_clip.actor_id)
	model.set_parent(actor.id, parent.id)
	check(model.world_transform_2d_for(actor.id).origin.is_equal_approx(Vector2(50, -20)), "2D parenting preserves screen-space position")
	check(runtime.anchor.position.is_equal_approx(Vector2(450, 280)), "Nested 2D runtime composes parent transforms")
	model.unparent(actor.id)
	check(actor.get_value(&"position").is_equal_approx(Vector2(50, -20)), "Unparent preserves 2D transform")
	model.undo()
	check(actor.parent_id == parent.id, "2D unparent supports undo")
	var text_settings := editor.registry.get_object_definition(&"text_settings")
	var settings := text_settings.create_object()
	settings.set_value(&"bold", true)
	settings.set_value(&"font_size", 64.0)
	settings.set_value(&"color", Color.CORAL)
	settings.set_value(&"shadow", true)
	var reference := ActorObjectReference.from_object(settings)
	model.selected_layer = 1
	var text_clip := model.create_actor(editor.registry.get_definition(&"text_2d"), 0, {&"text": "Hello", &"text_settings": reference})
	var text_runtime := editor._runtime_for_clip(text_clip.id) as ActorUIRuntime
	check(text_runtime.label.text == "Hello" and text_runtime.label.label_settings.font_size == 64, "2D text samples shared Text Settings")
	check(text_runtime.label.use_parent_material, "2D text inherits its actor Canvas Shader material")
	check((text_runtime.label.label_settings.font as SystemFont).font_weight == 700, "System fonts support bold")
	model.selected_layer = 2
	var spatial_clip := model.create_actor(editor.registry.get_definition(&"text_3d"), 0, {&"text_settings": reference})
	var spatial_runtime := editor._runtime_for_clip(spatial_clip.id)
	check(spatial_runtime.content.font_size == 64 and spatial_runtime.text_shadow.visible, "3D text uses the same settings and shadow")
	var path := ProjectSettings.globalize_path("res://text_settings_test_" + ActorData.new_id() + ".tres")
	ResourceSaver.save(settings, path)
	check(ActorFileImport.type_for_path(path) == &"text_3d", "Dropping Text Settings maps to a text actor")
	check(await FileOperations.get_file_thumbnail(path) != null, "Text Settings has a unique filesystem thumbnail")
	DirAccess.remove_absolute(path)
	var dialog := ActorDimensionDialog.new()
	root.add_child(dialog)
	dialog.build("Image")
	check(dialog.find_child("Choose2D", true, false) != null and dialog.find_child("Choose3D", true, false) != null, "Asset placement dialog offers both dimensions")
	dialog.free()
	model.history.clear_history()
	editor.free()
	viewport.free()
	DirAccess.remove_absolute(canvas_shader_path)
	await process_frame
	print("2D UI / shared text / gizmo checks: %d failures" % failures)
	quit(failures)
