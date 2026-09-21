extends SceneTree
var failures: int = 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func tree_has_path(item: TreeItem, suffix: String) -> bool:
	var current := item
	while current != null:
		if str(current.get_metadata(0)).ends_with(suffix):
			return true
		if tree_has_path(current.get_first_child(), suffix):
			return true
		current = current.get_next()
	return false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var editor := load("res://Workspaces/SceneWorkspace/Timeline.tscn").instantiate() as ActorTimelineEditor
	root.add_child(editor)
	var definitions := editor.registry.get_definitions()
	check(definitions.size() == 23, "Catalog includes the core actors and useful 2D/3D primitives")
	check(editor.registry.get_object_definition(&"material") != null, "Material resource type is registered from catalog")
	var shader_material_definition := editor.registry.get_object_definition(&"shader_material")
	check(shader_material_definition != null and shader_material_definition.base_type == &"material", "ShaderMaterial is registered as a creation-compatible Material type")
	check(editor.registry.object_definitions_for(&"material").size() == 2, "Material slots offer Material and ShaderMaterial creation")
	var image_object_definition := editor.registry.get_object_definition(&"image")
	var noise_image_definition := editor.registry.get_object_definition(&"noise_image")
	check(image_object_definition != null and noise_image_definition != null and noise_image_definition.base_type == &"image",
		"Image and Noise Image object types are registered")
	check(editor.registry.object_definitions_for(&"image").size() == 2, "Image slots offer Image and Noise Image creation")
	check(BasicActors.CATALOG.resource_path.ends_with("basic_actor_catalog.tres"), "Types load from saveable catalog")
	var saved_catalog_path := "user://actor_catalog_test_" + ActorData.new_id() + ".tres"
	check(ResourceSaver.save(BasicActors.CATALOG.duplicate(true), saved_catalog_path) == OK, "Save actor catalog resource")
	var loaded_catalog := ResourceLoader.load(saved_catalog_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorCatalog
	check(loaded_catalog != null and loaded_catalog.definitions.size() == definitions.size(), "Reload actor catalog resource")
	DirAccess.remove_absolute(saved_catalog_path)
	var icon_paths: Dictionary = {}
	var image_test_path := "user://image_actor_test_" + ActorData.new_id() + ".png"
	var test_image := Image.create(4, 3, false, Image.FORMAT_RGBA8)
	test_image.fill(Color(0.2, 0.8, 0.6, 0.75))
	check(test_image.save_png(image_test_path) == OK, "Create temporary image actor source")
	check(ActorProperty.image_ratio_scale(image_test_path).is_equal_approx(Vector3(1.0, 0.75, 1.0)), "Landscape image produces bounded aspect-ratio scale")
	for definition in definitions:
		check(definition.icon != null, definition.display_name + " has an icon")
		if definition.icon != null:
			check(not icon_paths.has(definition.icon.resource_path), definition.display_name + " icon is unique")
			icon_paths[definition.icon.resource_path] = true
		for property in definition.properties:
			check(not str(property.options.get("group", "")).is_empty(), property.label + " has an inspector category")
	for index in definitions.size():
		var definition := definitions[index]
		var initial_values := {}
		if definition.type_id == &"image_3d":
			var source_image := image_object_definition.create_object()
			source_image.set_value(&"source", image_test_path)
			initial_values[&"image_path"] = ActorObjectReference.from_object(source_image)
		var actor := definition.create_actor(initial_values)
		var runtime := definition.create_runtime(actor)
		check(runtime != null, "Create runtime " + definition.display_name)
		root.add_child(runtime)
		runtime.evaluate_clip(ActorClip.create(actor), 1.0)
		check(runtime.active, "Evaluate " + definition.display_name)
		if definition.type_id == &"image_3d":
			var mesh := runtime.get_child(0) as MeshInstance3D
			var material_property := definition.find_property(&"material")
			check(definition.find_property(&"color") == null and material_property != null, "Image actor replaces Color with Material")
			check(material_property.file_resource_mode() == ActorProperty.FileResourceMode.EDITABLE, "Material is an editable file resource property")
			check(actor.get_value(&"material") == null, "New image defaults to no Material")
			var material_object := editor.registry.get_object_definition(&"material").create_object()
			actor.set_value(&"material", ActorObjectReference.from_object(material_object))
			check(actor.get_value(&"scale").is_equal_approx(Vector3(1.0, 0.75, 1.0)), "Image actor stores aspect ratio as its dynamic Scale default")
			check(definition.find_property(&"scale").create_default_for_actor(actor).is_equal_approx(Vector3(1.0, 0.75, 1.0)), "Reset resolves the current image aspect ratio")
			check(mesh != null and (mesh.material_override as StandardMaterial3D).albedo_texture != null, "Image actor loads its selected project image")
			check(mesh.mesh is QuadMesh and (mesh.mesh as QuadMesh).size == Vector2.ONE, "Image actor has a one-by-one-meter base size")
			check(mesh.layers == 1, "Image actor uses the main viewport visibility layer")
			material_object.set_value(&"tint", Color.RED)
			material_object.set_value(&"normal_map", image_test_path)
			material_object.set_value(&"normal_strength", 2.5)
			material_object.set_value(&"uv_scale", Vector2(2.0, 3.0))
			material_object.set_value(&"uv_offset", Vector2(0.25, 0.5))
			material_object.set_value(&"roughness_map", image_test_path)
			material_object.set_value(&"metallic_map", image_test_path)
			material_object.set_value(&"specular_map", image_test_path)
			material_object.set_value(&"emission_enabled", true)
			material_object.set_value(&"emission_map", image_test_path)
			material_object.set_value(&"emission_operator", 1)
			runtime.evaluate_clip(ActorClip.create(actor), 1.0)
			check((mesh.material_override as StandardMaterial3D).albedo_color == Color.RED, "Image runtime evaluates nested Material properties")
			var runtime_material := mesh.material_override as StandardMaterial3D
			check(runtime_material.normal_enabled and runtime_material.normal_texture != null and is_equal_approx(runtime_material.normal_scale, 2.5), "Material evaluates normal map and strength")
			check(runtime_material.uv1_scale == Vector3(2.0, 3.0, 1.0) and runtime_material.uv1_offset == Vector3(0.25, 0.5, 0.0), "Material evaluates UV scale and offset")
			check(runtime_material.roughness_texture != null and runtime_material.metallic_texture != null, "Material evaluates roughness and metallic maps")
			check(runtime_material.get_meta("specular_texture") != null, "Material retains its specular map for the rendering backend")
			check(runtime_material.emission_texture != null and runtime_material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY, "Material evaluates emission map and blend operator")
			check(runtime_material.shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL, "Materials are shaded by default")
			material_object.set_value(&"metallic", 1.75)
			material_object.set_value(&"roughness", -0.5)
			runtime.evaluate_clip(ActorClip.create(actor), 1.0)
			check(runtime_material.metallic == 1.75 and runtime_material.roughness == -0.5, "Runtime preserves values outside inspector slider ranges")
		runtime.free()
		# Audio requires a chosen source; audio_test exercises creation and its picker schema.
		if definition.type_id in [&"audio", &"video", &"video_2d"]: continue
		if definition.type_id == &"image_3d":
			var image_property := definition.find_property(&"image_path")
			check(image_property != null and image_property.options.get("prompt_on_create", false), "Image actor prompts for its file on creation")
			var created_image := image_object_definition.create_object()
			created_image.set_value(&"source", "C:/example/image.png")
			editor.model.create_actor(definition, 0.0, {&"image_path": ActorObjectReference.from_object(created_image)})
			var created_reference := editor.model.selected_actor().get_value(&"image_path") as ActorObjectReference
			check(created_reference != null and created_reference.embedded.get_value(&"source") == "C:/example/image.png", "Creation stores initial Image object in one actor action")
			var selected_image := editor.model.selected_actor()
			check(selected_image.get_value(&"material") == null, "Timeline-created image has an empty Material slot")
			var material_definition := editor.registry.get_object_definition(&"material")
			var selected_material := material_definition.create_object()
			selected_image.set_value(&"material", ActorObjectReference.from_object(selected_material))
			editor.model.edit_object_property(selected_image, selected_material, material_definition, &"tint", Color.BLUE)
			check(selected_material.get_value(&"tint") == Color.BLUE, "Nested Material edit changes actor resource")
			editor.model.undo()
			check(selected_material.get_value(&"tint") == Color.WHITE, "Nested Material edit participates in actor undo")
		elif definition.type_id == &"image_2d":
			editor.model.create_actor(definition, 0.0)
		else:
			editor.actor_picker.choose(index)
			check(editor.model.selected_actor().type_id == definition.type_id, "Picker creates correct type")
		editor.undo()
		check(editor.model.clips.is_empty(), "Undo new actor")
	DirAccess.remove_absolute(image_test_path)
	var image_definition := editor.registry.get_definition(&"image_3d")
	var source_property := image_object_definition.find_property(&"source")
	var image_extensions: PackedStringArray = source_property.options.get("extensions", [])
	check(ActorProjectFilePicker.is_allowed_path(ActorProjectFilePicker.root_directory(), ProjectSettings.globalize_path("res://resources/Images/ActorIcons/Image3D.svg"), image_extensions), "Project image picker accepts supported files inside project")
	check(not ActorProjectFilePicker.is_allowed_path(ActorProjectFilePicker.root_directory(), image_test_path, image_extensions), "Project image picker rejects files outside project")
	var asset_picker := ActorProjectFilePicker.new()
	root.add_child(asset_picker)
	asset_picker._build(source_property, "Choose asset")
	check(tree_has_path(asset_picker.folders.get_root(), "Image3D.svg"), "Filtered folder tree includes matching files")
	for item_index in asset_picker.files.item_count:
		if not asset_picker.files.is_item_disabled(item_index):
			check(image_extensions.has(str(asset_picker.files.get_item_metadata(item_index)).get_extension().to_lower()), "Asset grid contains only requested file types")
	asset_picker.search.text = "Image3D"
	asset_picker._refresh_files()
	await process_frame
	check(asset_picker.files.size_flags_horizontal == Control.SIZE_EXPAND_FILL, "Asset file grid receives the available browser width")
	check(asset_picker.files.item_count == 1 and str(asset_picker.files.get_item_metadata(0)).ends_with("Image3D.svg"), "Asset picker shows matching filtered project files")
	check(asset_picker.files.get_item_icon(0) != FileOperations.FILE_COLORED_TEXTURE, "Asset picker generates a file thumbnail")
	check(ActorProjectFilePicker.is_allowed_path(ActorProjectFilePicker.root_directory(), ProjectSettings.globalize_path("res://project.godot"), PackedStringArray()), "Empty extension filter supports any project file type")
	asset_picker.free()
	var dropped_material_path := ProjectSettings.globalize_path("res://actor_drop_test_" + ActorData.new_id() + ".tres")
	var dropped_material := editor.registry.get_object_definition(&"material").create_object()
	check(ResourceSaver.save(dropped_material, dropped_material_path) == OK, "Create temporary project Material for drag-and-drop")
	var save_dialog := ActorProjectResourceSaveDialog.new()
	root.add_child(save_dialog)
	save_dialog._build("Save Material", "New Material", "tres")
	check(save_dialog.filename != null and save_dialog.filename.text == "New Material", "Resource Save As dialog initializes its filename before validation")
	check(save_dialog.embedded_toggle != null and save_dialog.embedded_toggle.visible, "Resource Save As dialog offers an Embedded resource destination")
	check(save_dialog.folders.get_selected() != null and save_dialog.selected_directory == save_dialog.project_root, "Resource Save As dialog starts at the project root")
	check(not save_dialog.save_button.disabled and FileOperations.is_path_inside(save_dialog.project_root, save_dialog._target_path()), "Resource Save As destination stays inside the project")
	check(tree_has_path(save_dialog.folders.get_root(), dropped_material_path.get_file()), "Save As project tree displays existing resource files")
	save_dialog.filename.text = dropped_material_path.get_file().get_basename()
	save_dialog._validate()
	check(save_dialog.save_button.disabled and save_dialog.status.text.contains("already exists"), "Save As clearly reports duplicate file names")
	save_dialog.free()
	var embedded_dialog := ActorProjectResourceSaveDialog.new()
	root.add_child(embedded_dialog)
	embedded_dialog._build("Save Material", "New Material", "tres")
	embedded_dialog.embedded_toggle.button_pressed = true
	embedded_dialog._validate()
	check(not embedded_dialog.save_button.disabled and embedded_dialog.save_button.text == "Use embedded" and embedded_dialog.destination.text.contains("inside this actor"), "Embedded destination bypasses file naming and clearly describes where the resource is stored")
	var embedded_result := {"value": {}}
	embedded_dialog.finished.connect(func(result: Dictionary): embedded_result.value = result)
	embedded_dialog._save()
	check(embedded_result.value.get("embedded", false) and str(embedded_result.value.get("path", "")).is_empty(), "Embedded Save As resolves without creating a filesystem path")
	embedded_dialog.free()
	var drag_source := ProjectFileDragButton.new()
	root.add_child(drag_source)
	drag_source.drag_paths_provider = func(): return PackedStringArray([dropped_material_path])
	var drag_payload: Dictionary = drag_source._get_drag_data(Vector2.ZERO)
	check(drag_payload.get("type") == "project_files" and drag_payload.get("path") == dropped_material_path, "Project filesystem files publish a reusable drag payload")
	drag_source.free()
	var ui_model := ActorTimeline.new()
	var ui_image_definition := editor.registry.get_definition(&"image_3d")
	var ui_image_object := image_object_definition.create_object()
	ui_image_object.set_value(&"source", "C:/missing.png")
	ui_model.create_actor(ui_image_definition, 0.0, {&"image_path": ActorObjectReference.from_object(ui_image_object)})
	ui_image_object = (ui_model.selected_actor().get_value(&"image_path") as ActorObjectReference).embedded
	var legacy_material := ActorObjectData.new()
	legacy_material.type_id = &"material"
	legacy_material.values = {&"tint": Color.WHITE}
	var inspector_material_definition := editor.registry.get_object_definition(&"material")
	var roughness_property := inspector_material_definition.find_property(&"roughness")
	check(inspector_material_definition.value_for(legacy_material, roughness_property) == roughness_property.create_default(), "Older Materials use schema defaults for missing properties")
	check(inspector_material_definition.find_property(&"normal_map") != null and inspector_material_definition.find_property(&"normal_strength") != null, "Material schema includes normal map and strength")
	check(inspector_material_definition.find_property(&"uv_scale") != null
		and inspector_material_definition.find_property(&"uv_offset") != null
		and inspector_material_definition.find_property(&"uv_triplanar") != null
		and inspector_material_definition.find_property(&"uv_world_triplanar") != null,
		"Material schema includes UV transform and triplanar options")
	check(float(roughness_property.options.min) == 0.0 and float(roughness_property.options.max) == 1.0, "Roughness declares its zero-to-one range")
	check(inspector_material_definition.find_property(&"unshaded").create_default() == false, "Materials are shaded by default")
	check(inspector_material_definition.find_property(&"albedo_map") != null
		and inspector_material_definition.find_property(&"roughness_map") != null
		and inspector_material_definition.find_property(&"metallic_map") != null
		and inspector_material_definition.find_property(&"specular_map") != null
		and inspector_material_definition.find_property(&"emission_map") != null,
		"Material schema includes Albedo and all supporting texture maps")
	ui_model.selected_actor().set_value(&"material", ActorObjectReference.from_object(legacy_material))
	var resource_inspector := ActorInspector.new()
	root.add_child(resource_inspector)
	resource_inspector.setup(ui_model, editor.registry, ActorInspectorState.new())
	var material_slot := resource_inspector.find_child("material_resource", true, false) as ActorResourceSlot
	check(material_slot != null and material_slot.text.contains("Material") and not material_slot.text.contains("Embedded"), "Actor shows a generic Material resource slot")
	var image_slot := resource_inspector.find_child("image_path_resource", true, false) as ActorResourceSlot
	var image_menu := image_slot.get_child(0) as PopupMenu if image_slot != null else null
	check(image_menu != null and image_menu.get_item_text(image_menu.get_item_index(100)) == "New Image"
		and image_menu.get_item_text(image_menu.get_item_index(101)) == "New Noise Image",
		"Image resource menu offers file-backed and procedural Image objects")
	var saved_noise_path := ProjectSettings.globalize_path("res://actor_noise_picker_test_" + ActorData.new_id() + ".tres")
	check(ResourceSaver.save(noise_image_definition.create_object(), saved_noise_path) == OK,
		"Create temporary saved Noise Image")
	var mixed_image_picker := ActorProjectFilePicker.new()
	root.add_child(mixed_image_picker)
	mixed_image_picker._build(resource_inspector._object_picker_property(ui_image_definition.find_property(&"image_path")),
		"Choose Image")
	check(tree_has_path(mixed_image_picker.folders.get_root(), "Image3D.svg")
		and tree_has_path(mixed_image_picker.folders.get_root(), saved_noise_path.get_file())
		and not tree_has_path(mixed_image_picker.folders.get_root(), dropped_material_path.get_file()),
		"Image picker shows raster files and saved Noise Images while filtering unrelated resources")
	mixed_image_picker.free()
	DirAccess.remove_absolute(saved_noise_path)
	var project_image_path := ProjectSettings.globalize_path("res://resources/Images/ActorIcons/Image3D.svg")
	var image_payload := {"type": "project_files", "paths": PackedStringArray([project_image_path])}
	var material_payload := {"type": "project_files", "paths": PackedStringArray([dropped_material_path])}
	check(image_slot != null and image_slot._can_drop_data(Vector2.ZERO, image_payload),
		"The outer Image slot accepts compatible project image drags")
	check(not image_slot._can_drop_data(Vector2.ZERO, material_payload),
		"The outer Image slot rejects non-image resource drags")
	image_slot._drop_data(Vector2.ZERO, image_payload)
	var dropped_image_reference := ui_model.selected_actor().get_value(&"image_path") as ActorObjectReference
	check(dropped_image_reference != null and dropped_image_reference.object_type == &"image"
		and dropped_image_reference.embedded.get_value(&"source") == project_image_path,
		"Choosing a raw image wraps it in a file-backed Image object")
	ui_model.undo()
	check((ui_model.selected_actor().get_value(&"image_path") as ActorObjectReference).embedded.get_value(&"source") == "C:/missing.png",
		"Image file assignment participates in undo")
	resource_inspector._rebuild_selected()
	check(resource_inspector.find_child("ImageObjectPreview", true, false) != null
		and resource_inspector.find_child("source_file", true, false) == null
		and resource_inspector.find_child("EmptyImageChooser", true, false) == null,
		"Expanded file-backed Images are preview-only and do not expose a recursive Source editor")
	image_slot = resource_inspector.find_child("image_path_resource", true, false) as ActorResourceSlot
	image_menu = image_slot.get_child(0) as PopupMenu if image_slot != null else null
	image_menu.id_pressed.emit(101)
	var noise_reference := ui_model.selected_actor().get_value(&"image_path") as ActorObjectReference
	check(noise_reference != null and noise_reference.object_type == &"noise_image", "Image menu assigns the procedural subtype")
	resource_inspector._rebuild_selected()
	check(resource_inspector.find_child("ImageObjectPreview", true, false) != null
		and resource_inspector.find_child("ImagePreviewTexture", true, false) is TextureRect,
		"Noise Image displays a live preview in the inspector")
	var noise_object := noise_reference.embedded
	var generated_noise := ActorImageGenerator.image_for_object(noise_object)
	check(generated_noise != null and generated_noise.get_width() == 256 and generated_noise.get_height() == 256,
		"Noise Image generates its selected resolution")
	check(noise_image_definition.find_property(&"as_normal_map") != null,
		"Noise Image exposes a normal-map preview option")
	noise_object.set_value(&"as_normal_map", true)
	var normal_noise := ActorImageGenerator.image_for_object(noise_object)
	check(normal_noise != null and normal_noise.get_pixel(128, 128).b > 0.5
		and normal_noise.get_pixel(128, 128) != generated_noise.get_pixel(128, 128),
		"Noise Image can display its generated height field as a normal map")
	ui_model.undo()
	resource_inspector._rebuild_selected()
	image_slot = resource_inspector.find_child("image_path_resource", true, false) as ActorResourceSlot
	check(material_slot._can_drop_data(Vector2.ZERO, material_payload), "Editable Material slot accepts Material resource drags")
	check(not material_slot._can_drop_data(Vector2.ZERO, image_payload), "Material slot rejects image drags")
	material_slot._drop_data(Vector2.ZERO, material_payload)
	var dropped_reference := ui_model.selected_actor().get_value(&"material") as ActorObjectReference
	check(dropped_reference != null and dropped_reference.source == ActorObjectReference.Source.ASSET and dropped_reference.asset_id == dropped_material_path, "Dropping a Material assigns the filesystem resource")
	ui_model.undo()
	check((ui_model.selected_actor().get_value(&"material") as ActorObjectReference).source == ActorObjectReference.Source.EMBEDDED, "Material file drop participates in undo")
	resource_inspector._rebuild_selected()
	material_slot = resource_inspector.find_child("material_resource", true, false) as ActorResourceSlot
	var active_material := (ui_model.selected_actor().get_value(&"material") as ActorObjectReference).embedded
	var material_row := material_slot.get_parent()
	var material_editor := material_row.get_parent().get_child(material_row.get_index() + 1) as VBoxContainer
	check(material_editor != null and material_editor.visible, "Material resource editor starts expanded")
	check(material_editor.find_children("*", "PanelContainer", true, false).size() >= 1, "Material properties are visually enclosed in a resource box")
	var roughness_slider := material_editor.find_child("roughness_slider", true, false) as HSlider
	check(roughness_slider != null and roughness_slider.min_value == 0.0 and roughness_slider.max_value == 1.0, "Bounded Material floats display a range slider")
	if roughness_slider != null:
		roughness_slider.drag_started.emit()
		roughness_slider.value = 0.35
		check(is_equal_approx(float(active_material.get_value(&"roughness")), 0.35), "Material slider previews its value live")
		roughness_slider.drag_ended.emit(true)
		ui_model.undo()
		check(is_equal_approx(float(active_material.get_value(&"roughness")), 1.0), "A Material slider gesture is one undoable edit")
	var roughness_input := material_editor.find_child("roughness_value", true, false) as DragNumber
	check(roughness_input != null and roughness_input.allow_greater and roughness_input.allow_lesser, "Ranged number text remains unrestricted")
	if roughness_input != null:
		roughness_input.value = 1.75
		check(is_equal_approx(float(active_material.get_value(&"roughness")), 1.75) and roughness_slider.value == 1.0, "Typed values can exceed the slider maximum while the slider stays capped")
		ui_model.undo()
		roughness_input.interaction_started.emit()
		roughness_input.set_value_no_signal(-0.5)
		roughness_input.preview_changed.emit(-0.5)
		check(is_equal_approx(float(active_material.get_value(&"roughness")), -0.5) and roughness_slider.value == 0.0, "Number dragging can go below the slider minimum")
		roughness_input.drag_committed.emit(-0.5)
		ui_model.undo()
	var normal_map_slot := material_editor.find_child("normal_map_resource", true, false) as ActorResourceSlot
	var albedo_map_slot := material_editor.find_child("albedo_map_resource", true, false) as ActorResourceSlot
	var albedo_map_menu := albedo_map_slot.get_child(0) as PopupMenu if albedo_map_slot != null else null
	check(albedo_map_menu != null
		and albedo_map_menu.get_item_text(albedo_map_menu.get_item_index(100)) == "New Image"
		and albedo_map_menu.get_item_text(albedo_map_menu.get_item_index(101)) == "New Noise Image",
		"Material Albedo map offers Image and Noise Image creation")
	var normal_map_menu := normal_map_slot.get_child(0) as PopupMenu if normal_map_slot != null else null
	check(normal_map_menu != null
		and normal_map_menu.get_item_text(normal_map_menu.get_item_index(100)) == "New Image"
		and normal_map_menu.get_item_text(normal_map_menu.get_item_index(101)) == "New Noise Image",
		"Image-valued Material properties directly offer Image and Noise Image creation")
	if normal_map_slot != null:
		normal_map_menu.id_pressed.emit(101)
		var normal_reference := active_material.get_value(&"normal_map") as ActorObjectReference
		check(normal_reference != null and normal_reference.object_type == &"noise_image",
			"Creating Noise Image from an Image slot assigns the subtype")
		ui_model.undo()
	var uv_scale_x := material_editor.find_child("uv_scale_0", true, false) as DragNumber
	var uv_offset_y := material_editor.find_child("uv_offset_1", true, false) as DragNumber
	var uv_triplanar := material_editor.find_child("uv_triplanar", true, false) as CheckButton
	var uv_world_triplanar := material_editor.find_child("uv_world_triplanar", true, false) as CheckButton
	check(uv_scale_x != null and uv_offset_y != null and uv_triplanar != null and uv_world_triplanar != null,
		"UV exposes Scale, Offset, Triplanar, and World Triplanar controls")
	var emission_operator := material_editor.find_child("emission_operator_choice", true, false) as OptionButton
	check(emission_operator != null and emission_operator.item_count == 2 and emission_operator.get_item_text(0) == "Add" and emission_operator.get_item_text(1) == "Multiply", "Emission exposes Add and Multiply choices")
	var normal_category := material_editor.find_child("Category_Resource_material_Normal Map", true, false) as Button
	check(normal_category != null and normal_category.button_pressed, "Material object categories are expandable")
	if normal_category != null:
		normal_category.button_pressed = false
		check(not (normal_category.get_parent().get_child(1) as Control).visible, "Material category collapses its properties")
		check(not resource_inspector.ui_state.category_expanded(ui_model.selected_actor().id, "Resource:material:Normal Map"), "Material category collapse state is saved")
	var expanded_buttons := material_editor.find_children("*", "Button", true, false)
	check(expanded_buttons.all(func(button: Button): return button.text != "Make Unique" and button.text != "Save As…"), "Resource actions are absent from expanded properties")
	material_slot.button_pressed = false
	check(not material_editor.visible, "Material resource slot collapses nested properties")
	material_slot.button_pressed = true
	check(material_editor.visible, "Material resource slot expands nested properties")
	var resource_menu := material_slot.get_child(0) as PopupMenu
	check(resource_menu != null and resource_menu.get_item_text(resource_menu.get_item_index(100)) == "New Material" and resource_menu.get_item_text(resource_menu.get_item_index(101)) == "New ShaderMaterial" and resource_menu.get_item_text(resource_menu.get_item_index(1)) == "Load from project…" and resource_menu.get_item_text(resource_menu.get_item_index(2)) == "Make Unique" and resource_menu.get_item_text(resource_menu.get_item_index(3)) == "Save As…" and resource_menu.get_item_text(resource_menu.get_item_index(4)) == "Clear", "Material context menu provides both compatible creation types and resource actions")
	var ui_actor := ui_model.selected_actor()
	var material_property := ui_image_definition.find_property(&"material")
	check(material_property.accepts(null), "Editable resource property can be cleared")
	ui_model.edit_property(ui_actor, ui_image_definition, &"material", null)
	check(ui_actor.get_value(&"material") == null, "Clear removes the Material resource")
	ui_model.undo()
	check(ui_actor.get_value(&"material") is ActorObjectReference, "Undo restores a cleared Material")
	ui_model.history.clear_history()
	resource_inspector.free()
	DirAccess.remove_absolute(dropped_material_path)
	var picker := editor.actor_picker
	picker.search.text = "basic shape"
	picker.rebuild()
	check(picker._matches.size() == 2 and definitions[picker._matches[0]].type_id == &"basic_shape", "Search includes 2D and 3D basic shapes")
	var shape_card := picker.cards.find_child("Actor_basic_shape", true, false)
	check(shape_card != null and shape_card.find_children("*", "TextureRect", true, false).size() == 1, "Picker card displays actor icon")
	picker.category = "Lighting"
	picker.search.text = ""
	picker.rebuild()
	var lighting_types := picker._matches.map(func(index: int): return definitions[index].type_id)
	check(picker._matches.size() == 5 and lighting_types.has(&"light_3d") and lighting_types.has(&"directional_light")
		and lighting_types.has(&"world_environment") and lighting_types.has(&"fog_volume")
		and lighting_types.has(&"reflection_probe"), "Category filter")
	picker.search.text = "no-such-actor"
	picker.rebuild()
	check(picker._matches.is_empty(), "Empty search results")
	editor.free()
	await process_frame
	print("Actor picker checks: ", failures, " failures")
	quit(1 if failures else 0)
