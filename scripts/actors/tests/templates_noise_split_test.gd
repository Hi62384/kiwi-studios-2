extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for name in ["Linear", "Ease", "Smoothstep", "Sin wave", "Step"]:
		var curve := ActorValueCurve.template(name, 4 if name == "Step" else 1)
		check(is_zero_approx(curve.sample(0)) and is_equal_approx(curve.sample(1), 1), "%s starts at zero and ends at one" % name)
	check(is_equal_approx(ActorValueCurve.template("Ease", 0).sample(0.5), 0.5), "Zero ease is linear")
	check(ActorValueCurve.template("Ease", 2).sample(0.5) > 0.5 and ActorValueCurve.template("Ease", -2).sample(0.5) < 0.5,
		"Signed ease rounds in opposite directions")
	check(is_equal_approx(ActorValueCurve.template("Smoothstep", 0).sample(0.25), 0.25), "Smoothstep strength zero is linear")
	check(ActorValueCurve.template("Smoothstep", 1).sample(0.25) < 0.25, "Smoothstep adjustment controls rounding")
	check(absf(ActorValueCurve.template("Sin wave", 1).sample(0.125) - ActorValueCurve.template("Sin wave", 2).sample(0.125)) > 0.02,
		"Sin wave frequency changes its waveform")
	check(is_equal_approx(ActorValueCurve.template("Step", 4).sample(0.3), 0.25), "Step template creates adjustable stairs")
	var editor := ActorTimelineEditor.new()
	editor.size = Vector2(1100, 350)
	root.add_child(editor)
	var model := editor.model
	var clip := model.create_actor(editor.registry.get_definition(&"point_3d"), 10)
	clip.source_offset = 3
	clip.playback_speed = 2
	var actor := model.selected_actor()
	model.playhead_time = 10
	model.add_keyframe(actor, PackedStringArray(["position"]), "Position", Vector3.ONE)
	var right := model.split_clip(clip.id, 12)
	check(right != null and clip.duration == 2 and right.duration == 3 and right.start_time == 12,
		"Split divides actor duration at clicked timeline time")
	check(right.source_offset == 7 and right.playback_speed == 2 and right.layer == clip.layer, "Right split preserves source time, speed, and layer")
	check(model.actor_for_id(right.actor_id).animation_tracks.size() == 1, "Split retains animation data")
	model.undo()
	check(model.actors.size() == 1 and clip.duration == 5, "Split undoes in one action")
	model.redo()
	check(model.actors.size() == 2 and clip.duration == 2, "Split redo restores both parts")
	check(model.split_clip(right.id, right.start_time) == null, "Split rejects cuts that would create an empty clip")
	check(editor.magnet_button.icon != null and editor.undo_button.icon != null and editor.redo_button.icon != null and editor.split_button.icon != null,
		"Toolbar tools have actual icon textures")
	var image_def := editor.registry.get_definition(&"image_3d")
	var shader_def := editor.registry.get_object_definition(&"shader_material")
	var shader_object := shader_def.create_object()
	shader_object.set_value(&"shader_path", "res://scripts/actors/tests/fixtures/uniforms_test.gdshader")
	var noise := editor.registry.get_object_definition(&"noise_image").create_object()
	shader_object.set_value(&"uniforms", {&"mask_texture": ActorObjectReference.from_object(noise)})
	var image_actor := image_def.create_actor()
	image_actor.set_value(&"material", ActorObjectReference.from_object(shader_object))
	var runtime := image_def.create_runtime(image_actor)
	root.add_child(runtime)
	runtime.evaluate_clip(ActorClip.create(image_actor), 0)
	var mesh := runtime.get_child(0) as MeshInstance3D
	check((mesh.material_override as ShaderMaterial).get_shader_parameter(&"mask_texture") is Texture2D,
		"Shader sampler accepts an embedded Noise Image")
	var noise_path := "res://noise_sampler_test_" + ActorData.new_id() + ".tres"
	check(ResourceSaver.save(noise, noise_path) == OK, "Create noise file for sampler test")
	check(runtime._texture_for_value(noise_path) is Texture2D, "Shader sampler resolves Noise Image files")
	var inspector := ActorInspector.new()
	root.add_child(inspector)
	inspector.setup(model, editor.registry)
	model.create_actor(image_def, 20)
	var selected := model.selected_actor()
	selected.set_value(&"material", ActorObjectReference.from_object(shader_object))
	inspector._rebuild_selected()
	var noise_slot := inspector.find_child("mask_texture_file", true, false) as ActorResourceSlot
	check(noise_slot != null, "Shader texture uniform has a resource slot")
	if noise_slot != null:
		check(noise_slot.text.contains("Noise Image"), "Embedded noise texture is shown in its shader uniform slot")
		check(inspector.find_child("ImageObjectPreview", true, false) != null, "Noise uniform exposes its preview and editable properties")
		var noise_row := noise_slot.get_parent()
		var noise_editor := noise_row.get_parent().get_child(noise_row.get_index() + 1) as VBoxContainer
		noise_slot.pressed.emit()
		check(noise_editor != null and not noise_editor.visible, "Clicking the noise slot collapses its properties")
		noise_slot.pressed.emit()
		check(noise_editor != null and noise_editor.visible, "Clicking the noise slot expands its properties")
		var frequency := inspector.find_child("frequency_value", true, false) as DragNumber
		check(frequency != null, "Noise uniform exposes its frequency field")
		if frequency != null:
			frequency.value_changed.emit(0.075)
			check(is_equal_approx(float(noise.get_value(&"frequency")), 0.075), "Noise uniform property edits apply immediately")
			model.undo()
			check(not is_equal_approx(float(noise.get_value(&"frequency")), 0.075), "Noise uniform property edits support undo")
	model.edit_shader_uniform(selected, shader_object, shader_def, &"mask_texture", null)
	await process_frame
	noise_slot = inspector.find_child("mask_texture_file", true, false) as ActorResourceSlot
	if noise_slot != null:
		var noise_menu := noise_slot.get_child(0) as PopupMenu
		noise_menu.id_pressed.emit(5)
		await process_frame
		var created_value: Variant = (shader_object.get_value(&"uniforms") as Dictionary).get(&"mask_texture")
		check(created_value is ActorObjectReference and created_value.object_type == &"noise_image", "New Noise Image creates a shader sampler resource")
		check(inspector.find_child("frequency_value", true, false) != null, "A newly created shader noise image expands to editable properties")
		if created_value is ActorObjectReference:
			check(not ActorAnimation.path_to_object(selected, created_value.embedded).is_empty(), "Nested shader noise properties retain an animation path")
	var texture_property := ActorProperty.new()
	texture_property.object_type = &"image"
	texture_property.options = {"extensions": ["tres", "res"], "shader_texture": true}
	check(inspector._file_path_allowed(ProjectSettings.globalize_path(noise_path), texture_property), "Shader picker accepts noise resource file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(noise_path))
	runtime.queue_free()
	inspector.queue_free()
	editor.queue_free()
	await process_frame
	print("Templates/noise/split checks: %d failures" % failures)
	quit(failures)
