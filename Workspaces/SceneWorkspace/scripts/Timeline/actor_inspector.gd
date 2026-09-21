class_name ActorInspector
extends ScrollContainer
## Inspector fields are generated from the selected actor's definition.

const IMAGE_FILE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "svg", "tga", "hdr", "exr"]

signal ui_state_changed

var model: ActorTimeline
var registry: ActorRegistry
var fields := VBoxContainer.new()
var _actor: ActorData
var _syncing: bool = false
var _updaters: Array[Callable] = []
var hints: InteractionHints
var ui_state: ActorInspectorState
var _restoring_scroll: bool = false
var _rebuild_queued: bool = false
var _animation_layout_signature: String = ""
var property_batch := ActorPropertyBatch.new()
var _inspecting_file := false
var _file_selection := ""


func setup(document: ActorTimeline, types: ActorRegistry, state: ActorInspectorState = null) -> void:
	model = document
	registry = types
	property_batch.model = model
	property_batch.registry = registry
	ui_state = state if state != null else ActorInspectorState.new()
	custom_minimum_size.x = 220
	fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_theme_constant_override("separation", 10)
	add_child(fields)
	model.changed.connect(refresh)
	model.selection_requested.connect(func():
		if not _inspecting_file: return
		_inspecting_file = false
		_actor = null
		for child in fields.get_children():
			fields.remove_child(child)
			child.queue_free())
	get_v_scroll_bar().value_changed.connect(_scroll_changed)
	ui_state.changed.connect(func(): ui_state_changed.emit())
	refresh()


func _edit_property(actor: ActorData, _definition: ActorDefinition, key: StringName, value: Variant) -> void:
	property_batch.edit(actor, key, value)

func _preview_property(actor: ActorData, _definition: ActorDefinition, key: StringName, value: Variant) -> void:
	property_batch.preview(actor, key, value)

func _commit_property_preview(actor: ActorData, _definition: ActorDefinition, key: StringName, original: Variant, value: Variant) -> void:
	property_batch.finish(actor, key, original, value)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and get_global_rect().has_point(event.position):
		FocusableKeyInput.current_focused_instance = null


func _inspect_media(path: String) -> bool:
	var extension := path.get_extension().to_lower()
	if not extension in IMAGE_FILE_EXTENSIONS + ["wav", "mp3", "ogg", "flac"] + ActorVideo.EXTENSIONS: return false
	_inspecting_file = true
	_file_selection = model.selected_id
	_actor = null
	_updaters.clear()
	for child in fields.get_children():
		fields.remove_child(child)
		child.queue_free()
	_label(path.get_file())
	if extension in IMAGE_FILE_EXTENSIONS:
		var edit_button := Button.new()
		edit_button.text = "Edit in Image Editor ↗"
		edit_button.pressed.connect(_open_image_workspace.bind(path))
		fields.add_child(edit_button)
	var preview := ActorMediaPreview.new()
	preview.path = path
	fields.add_child(preview)
	return true

func inspect_file_resource(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	if _inspect_media(path): return
	var object := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	if object == null:
		return
	var definition := registry.get_object_definition(object.type_id)
	if definition == null:
		return
	_inspecting_file = true
	_file_selection = model.selected_id
	_actor = null
	_updaters.clear()
	for child in fields.get_children():
		fields.remove_child(child)
		child.queue_free()
	_label("RESOURCE PROPERTIES")
	var title := Label.new()
	title.text = path.get_file()
	title.add_theme_font_size_override("font_size", 17)
	fields.add_child(title)
	var kind := Label.new()
	kind.text = definition.display_name + "  •  " + path
	kind.modulate = Color("819db4")
	kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fields.add_child(kind)
	if registry.object_type_matches(object.type_id, &"image"):
		_add_image_object_preview(object, fields)
		_add_image_editor_button(fields, object)
		if object.type_id == &"image":
			_prepare_buttons()
			return
	var current_group := ""
	var group: VBoxContainer
	var resource_state_id := "FileResource:" + path
	for property in definition.properties:
		var property_group := str(property.options.get("group", "Properties"))
		if property_group != current_group:
			current_group = property_group
			group = _stateful_category(current_group, resource_state_id, fields)
		_add_file_object_value(object, definition, property, group)
	_prepare_buttons()


func _add_file_object_value(object: ActorObjectData, definition: ActorObjectDefinition,
		property: ActorProperty, parent: VBoxContainer, save_owner: ActorObjectData = null) -> void:
	if property.options.get("system_font", false):
		_add_label(parent, property.label)
		var selector := _font_editor(parent, str(definition.value_for(object, property)), func(value: String):
			var before: Variant = definition.value_for(object, property)
			model.history.create_action("Change Font")
			model.history.add_do_method(func(): object.set_value(property.id, value); ResourceSaver.save(object, object.resource_path); model.changed.emit())
			model.history.add_undo_method(func(): object.set_value(property.id, before); ResourceSaver.save(object, object.resource_path); model.changed.emit())
			model.history.commit_action())
		_updaters.append(func(): selector.text = str(definition.value_for(object, property)))
		return
	if property.options.get("shader_uniforms", false):
		_add_file_shader_uniforms(object, parent)
		return
	var current_value: Variant = definition.value_for(object, property)
	var heading := HBoxContainer.new()
	parent.add_child(heading)
	var label := Label.new()
	label.text = property.label
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var reset := Button.new()
	reset.name = str(property.id) + "_reset"
	reset.text = "↺"
	reset.visible = not _same_value(current_value, property.create_default())
	heading.add_child(reset)
	var set_value := func(value: Variant):
		if not property.accepts(value):
			return
		if save_owner != null:
			var previous: Variant = ActorData.copy_value(object.get_value(property.id))
			if _same_value(previous, value):
				return
			var target := object if not object.resource_path.is_empty() else save_owner
			model.history.create_action("Change " + property.label)
			model.history.add_do_method(func():
				object.set_value(property.id, ActorData.copy_value(value))
				ResourceSaver.save(target, target.resource_path)
				model.changed.emit())
			model.history.add_undo_method(func():
				object.set_value(property.id, ActorData.copy_value(previous))
				ResourceSaver.save(target, target.resource_path)
				model.changed.emit())
			model.history.commit_action()
		else:
			object.set_value(property.id, value)
			ResourceSaver.save(object, object.resource_path)
		reset.visible = not _same_value(definition.value_for(object, property), property.create_default())
		for update in _updaters:
			update.call()
	reset.pressed.connect(func(): set_value.call(property.create_default()))
	if property.options.has("choices"):
		var choice := _choice_editor(parent, property, int(current_value))
		choice.item_selected.connect(func(index: int): set_value.call(index))
		return
	match property.value_type:
		TYPE_FLOAT, TYPE_INT:
			var input := _number_editor(parent, float(current_value), property)
			var normalize := func(value: float) -> Variant: return int(value) if property.value_type == TYPE_INT else value
			input.value_changed.connect(func(value: float): set_value.call(normalize.call(value)))
			input.preview_changed.connect(func(value: float): set_value.call(normalize.call(value)))
		TYPE_VECTOR2, TYPE_VECTOR3:
			var component_count := 2 if property.value_type == TYPE_VECTOR2 else 3
			for axis in component_count:
				var row := HBoxContainer.new()
				parent.add_child(row)
				var axis_label := Label.new()
				axis_label.text = ["X", "Y", "Z"][axis]
				axis_label.modulate = [Color("ee9e9e"), Color("9ed8b5"), Color("99bce8")][axis]
				row.add_child(axis_label)
				var input := _number(current_value[axis], float(property.options.get("step", 0.01)))
				input.name = str(property.id) + "_" + str(axis)
				row.add_child(input)
				input.value_changed.connect(func(value: float):
					var updated: Variant = definition.value_for(object, property)
					updated[axis] = value
					set_value.call(updated))
		TYPE_STRING, TYPE_STRING_NAME:
			if property.options.get("file_picker", false):
				var row := HBoxContainer.new()
				parent.add_child(row)
				var workspace_parameters := Callable()
				if property.id == &"shader_path" and definition.find_property(&"uniforms") != null:
					var read_file_parameters := func() -> Dictionary:
						return (definition.value_for(object, definition.find_property(&"uniforms")) as Dictionary).duplicate(true)
					var write_file_parameter := func(name: StringName, value: Variant, _mode: String, _original: Variant):
						var uniforms: Dictionary = read_file_parameters.call()
						uniforms[name] = ActorData.copy_value(value)
						object.set_value(&"uniforms", uniforms)
						ResourceSaver.save(object, object.resource_path)
						model.changed.emit()
					workspace_parameters = func() -> Dictionary:
						return {"values": read_file_parameters.call(), "reader": read_file_parameters, "writer": write_file_parameter}
				_add_file_resource_slot(row, property,
					func() -> Variant: return object.get_value(property.id), set_value,
					Callable(), workspace_parameters)
		TYPE_BOOL:
			var input := CheckButton.new()
			input.name = str(property.id)
			input.button_pressed = current_value
			parent.add_child(input)
			input.toggled.connect(func(value: bool): set_value.call(value))
		TYPE_COLOR:
			var input := LiveColorPickerButton.new()
			input.name = str(property.id)
			input.color = current_value
			parent.add_child(input)
			input.color_changed.connect(func(value: Color): set_value.call(value))


func _add_file_shader_uniforms(object: ActorObjectData, parent: VBoxContainer) -> void:
	var shader_source: Variant = object.get_value(&"shader_path", "")
	if shader_source == null or (shader_source is String and shader_source.is_empty()):
		_add_label(parent, "Choose a .gdshader file to expose its uniforms.")
		return
	var shader := _shader_from_value(shader_source)
	if shader == null:
		_add_label(parent, "The selected shader could not be loaded.")
		return
	var shown := 0
	for entry: Dictionary in _shader_uniform_layout(shader, parent, "FileResource:" + object.resource_path, "ShaderUniforms"):
		var info: Dictionary = entry.info
		var uniform_name := StringName(info.get("name", ""))
		if uniform_name.is_empty():
			continue
		var default_value: Variant = _shader_uniform_default(shader, uniform_name, int(info.get("type", TYPE_NIL)))
		var stored: Dictionary = object.get_value(&"uniforms", {})
		var value: Variant = stored.get(uniform_name, default_value)
		_add_file_shader_uniform_value(object, entry.parent, uniform_name, value, default_value, info)
		shown += 1
	if shown == 0:
		_add_label(parent, "This shader has no editable uniforms.")


func _add_file_shader_uniform_value(object: ActorObjectData, parent: VBoxContainer,
		uniform_name: StringName, value: Variant, default_value: Variant, info: Dictionary) -> void:
	var value_type := int(info.get("type", typeof(default_value)))
	if value_type == TYPE_OBJECT:
		default_value = ""
	var heading := HBoxContainer.new()
	parent.add_child(heading)
	var label := Label.new()
	label.text = str(uniform_name).capitalize()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var reset := Button.new()
	reset.name = str(uniform_name) + "_reset"
	reset.text = "↺"
	reset.visible = not _same_value(value, default_value)
	heading.add_child(reset)
	var set_value := func(updated: Variant):
		var uniforms: Dictionary = (object.get_value(&"uniforms", {}) as Dictionary).duplicate(true)
		uniforms[uniform_name] = ActorData.copy_value(updated)
		object.set_value(&"uniforms", uniforms)
		ResourceSaver.save(object, object.resource_path)
		reset.visible = not _same_value(updated, default_value)
		if value_type == TYPE_OBJECT:
			call_deferred("inspect_file_resource", object.resource_path)
	reset.pressed.connect(func():
		set_value.call(default_value)
		if not object.resource_path.is_empty():
			call_deferred("inspect_file_resource", object.resource_path))
	match value_type:
		TYPE_FLOAT, TYPE_INT:
			var property := ActorProperty.create(uniform_name, label.text, default_value)
			property.options.step = 0.01
			var range_parts := str(info.get("hint_string", "")).split(",")
			if int(info.get("hint", PROPERTY_HINT_NONE)) == PROPERTY_HINT_RANGE and range_parts.size() >= 2:
				property.options.min = float(range_parts[0])
				property.options.max = float(range_parts[1])
			var input := _number_editor(parent, float(value), property)
			input.value_changed.connect(func(number: float): set_value.call(int(number) if value_type == TYPE_INT else number))
			input.preview_changed.connect(func(number: float): set_value.call(int(number) if value_type == TYPE_INT else number))
		TYPE_BOOL:
			var input := CheckButton.new()
			input.button_pressed = bool(value)
			input.toggled.connect(set_value)
			parent.add_child(input)
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I:
			var count := 2 if value_type in [TYPE_VECTOR2, TYPE_VECTOR2I] else (3 if value_type in [TYPE_VECTOR3, TYPE_VECTOR3I] else 4)
			var integer_components := value_type in [TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I]
			for axis in count:
				var input := _number(float(value[axis]), 0.01)
				input.name = str(uniform_name) + "_" + str(axis)
				var update_component := func(number: float):
					var uniforms: Dictionary = object.get_value(&"uniforms", {})
					var updated: Variant = ActorData.copy_value(uniforms.get(uniform_name, value))
					updated[axis] = int(number) if integer_components else number
					set_value.call(updated)
				input.value_changed.connect(update_component)
				input.preview_changed.connect(update_component)
				input.drag_committed.connect(update_component)
				parent.add_child(input)
		TYPE_COLOR:
			var input := LiveColorPickerButton.new()
			input.color = value
			input.color_changed.connect(set_value)
			parent.add_child(input)
		TYPE_OBJECT:
			var property := ActorProperty.create(uniform_name, label.text, "")
			property.options = _shader_texture_options()
			_add_shader_texture_uniform(parent, property,
				func() -> Variant: return (object.get_value(&"uniforms", {}) as Dictionary).get(uniform_name, ""),
				set_value, null, object)
		_:
			var input := LineEdit.new()
			input.text = var_to_str(value)
			input.tooltip_text = "Edit this value using Godot Variant syntax, then press Enter."
			input.text_submitted.connect(func(text: String):
				var parsed: Variant = str_to_var(text)
				if typeof(parsed) == value_type:
					set_value.call(parsed))
			parent.add_child(input)


func refresh() -> void:
	if _inspecting_file:
		if model.selected_id == _file_selection:
			for update in _updaters: update.call()
			return
		_inspecting_file = false
	var selected := model.selected_actor()
	var layout_signature := _animated_layout_signature(selected)
	if selected == _actor and layout_signature != _animation_layout_signature:
		_actor = null
	_animation_layout_signature = layout_signature
	if selected == _actor and fields.get_child_count() > 0:
		_syncing = true
		for update in _updaters:
			update.call()
		_syncing = false
		return
	_actor = selected
	# Rebuilding the content temporarily drives ScrollContainer back to zero.
	# Suppress that layout-generated value change until this actor's saved scroll
	# has been restored, otherwise merely selecting it overwrites its own state.
	_restoring_scroll = _actor != null
	_updaters.clear()
	for child in fields.get_children():
		fields.remove_child(child)
		child.queue_free()
	_label("ACTOR PROPERTIES")
	if _actor == null:
		_restoring_scroll = false
		_label("Select an actor in the timeline.")
		return
	var actor := _actor
	var definition := registry.get_definition(_actor.type_id)
	if definition == null:
		_restoring_scroll = false
		_label("Unknown actor type")
		return
	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 10)
	fields.add_child(identity)
	var icon := TextureRect.new()
	icon.texture = definition.icon
	icon.custom_minimum_size = Vector2(42, 42)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	identity.add_child(icon)
	var identity_text := VBoxContainer.new()
	identity_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(identity_text)
	var actor_title := Label.new()
	actor_title.text = actor.display_name
	actor_title.add_theme_font_size_override("font_size", 17)
	identity_text.add_child(actor_title)
	var actor_type := Label.new()
	actor_type.text = definition.category + "  /  " + definition.display_name
	actor_type.modulate = Color("819db4")
	identity_text.add_child(actor_type)
	_updaters.append(func(): actor_title.text = actor.display_name)
	var general := _category("General", actor)
	_add_label(general, "Name")
	var name_input := LineEdit.new()
	name_input.name = "ActorName"
	name_input.text = actor.display_name
	general.add_child(name_input)
	var rename := func():
		model.rename_actor(actor, name_input.text)
		name_input.text = actor.display_name
	name_input.text_submitted.connect(func(_text: String): rename.call())
	name_input.focus_exited.connect(rename)
	_updaters.append(func(): name_input.text = actor.display_name)
	var reset_name := Button.new()
	reset_name.name = "ResetName"
	reset_name.text = "↺ Reset name"
	reset_name.tooltip_text = "Restore the actor type's original name"
	reset_name.visible = actor.display_name != definition.display_name
	general.add_child(reset_name)
	reset_name.pressed.connect(func(): model.rename_actor(actor, definition.display_name))
	_updaters.append(func(): reset_name.visible = actor.display_name != definition.display_name)
	var current_group := ""
	var group_container: VBoxContainer
	for property in definition.properties:
		if not _property_is_visible(property, actor):
			continue
		var property_group := str(property.options.get("group", "Properties"))
		if property_group != current_group:
			current_group = property_group
			group_container = _category(current_group, actor)
		_add_property(property, definition, group_container)
	_prepare_buttons()
	call_deferred("_restore_scroll", actor.id)


func _prepare_buttons() -> void:
	for node: Node in fields.find_children("*", "Button", true, false):
		var button := node as Button
		if button == null:
			continue
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 28.0)


func _font_editor(parent: Control, value: String, commit: Callable) -> Button:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var button := Button.new()
	button.name = "SystemFontPicker"
	button.text = value
	button.add_theme_font_override("font", ActorTextSettings.font({&"font": value}))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(button)
	var reset := Button.new()
	reset.name = "font_reset"
	reset.text = "↺"
	reset.tooltip_text = "Reset font"
	reset.visible = value != "Arial"
	row.add_child(reset)
	reset.pressed.connect(func():
		button.text = "Arial"
		button.add_theme_font_override("font", ActorTextSettings.font({&"font": "Arial"}))
		reset.hide()
		commit.call("Arial"))
	_updaters.append(func(): reset.visible = button.text != "Arial")
	button.pressed.connect(func():
		var popup := ActorFontPicker.new()
		button.add_child(popup)
		popup.setup(button.text)
		popup.font_chosen.connect(func(family: String):
			button.text = family
			button.add_theme_font_override("font", ActorTextSettings.font({&"font": family}))
			reset.visible = family != "Arial"
			commit.call(family))
		popup.popup_hide.connect(popup.queue_free)
		popup.popup_centered(Vector2i(470, 460))
		popup.search.grab_focus())
	return button

func _label(text: String) -> void:
	_add_label(fields, text)


func _add_label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)


func _category(text: String, actor: ActorData) -> VBoxContainer:
	return _stateful_category(text, actor.id, fields)


func _stateful_category(text: String, state_id: String, parent: VBoxContainer,
		state_key: String = "") -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	parent.add_child(section)
	var header := Button.new()
	var category_key := text if state_key.is_empty() else state_key + ":" + text
	header.name = ("Category_" + category_key).replace(":", "_").replace("/", "_")
	header.flat = true
	header.toggle_mode = true
	header.button_pressed = ui_state.category_expanded(state_id, category_key)
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.modulate = Color("80dbc4")
	section.add_child(header)
	var content := VBoxContainer.new()
	content.name = "Content"
	content.add_theme_constant_override("separation", 7)
	content.visible = header.button_pressed
	section.add_child(content)
	var update_header := func(expanded: bool):
		header.text = ("▾  " if expanded else "▸  ") + text.to_upper()
	update_header.call(header.button_pressed)
	header.toggled.connect(func(expanded: bool):
		content.visible = expanded
		update_header.call(expanded)
		ui_state.set_category_expanded(state_id, category_key, expanded))
	return content


func _scroll_changed(value: float) -> void:
	if not _restoring_scroll and _actor != null:
		ui_state.set_scroll(_actor.id, value)


func _restore_scroll(actor_id: String) -> void:
	# The newly generated controls need a layout pass before ScrollContainer
	# knows its range. Restoring sooner silently clamps a saved offset to zero.
	await get_tree().process_frame
	if _actor == null or _actor.id != actor_id:
		return
	_restoring_scroll = true
	scroll_vertical = int(ui_state.scroll_for(actor_id))
	_restoring_scroll = false


func _number(value: float, step: float) -> SpinBox:
	var input := DragNumber.new()
	input.allow_greater = true
	input.allow_lesser = true
	input.step = step
	input.value = value
	input.update_on_text_changed = false
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.interaction_started.connect(func():
		if hints != null:
			hints.begin(input, "Esc cancels drag"))
	input.interaction_ended.connect(func():
		if hints != null:
			hints.end(input))
	return input


func _number_editor(parent: Control, value: float, property: ActorProperty) -> DragNumber:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var input := _number(value, float(property.options.get("step", 1.0 if property.value_type == TYPE_INT else 0.01))) as DragNumber
	input.name = str(property.id) + "_value"
	var bounded := property.options.has("min") and property.options.has("max")
	if bounded:
		var slider := HSlider.new()
		slider.name = str(property.id) + "_slider"
		slider.min_value = float(property.options.min)
		slider.max_value = float(property.options.max)
		slider.step = input.step
		slider.value = value
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.tooltip_text = "%s to %s" % [slider.min_value, slider.max_value]
		row.add_child(slider)
		input.custom_minimum_size.x = 82
		input.size_flags_horizontal = Control.SIZE_SHRINK_END
		input.tooltip_text = "Slider: %s to %s. Drag or type to go outside that range." % [slider.min_value, slider.max_value]
		input.set_meta("range_slider", slider)
		var slider_dragging := {"active": false}
		slider.drag_started.connect(func():
			slider_dragging.active = true
			input.interaction_started.emit())
		slider.value_changed.connect(func(updated: float):
			input.set_value_no_signal(updated)
			if slider_dragging.active:
				input.preview_changed.emit(updated)
			else:
				input.value_changed.emit(updated))
		slider.drag_ended.connect(func(changed: bool):
			slider_dragging.active = false
			input.interaction_ended.emit()
			if changed:
				input.drag_committed.emit(input.value))
		input.preview_changed.connect(func(updated: float): slider.set_value_no_signal(updated))
		input.value_changed.connect(func(updated: float): slider.set_value_no_signal(updated))
	row.add_child(input)
	return input


func _set_number_silent(input: DragNumber, value: float) -> void:
	input.set_value_no_signal(value)
	var slider := input.get_meta("range_slider") as HSlider if input.has_meta("range_slider") else null
	if slider != null:
		slider.set_value_no_signal(value)


func _choice_editor(parent: Control, property: ActorProperty, selected: int) -> OptionButton:
	var choice := OptionButton.new()
	choice.name = str(property.id) + "_choice"
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for label: Variant in property.options.get("choices", []):
		choice.add_item(str(label))
	choice.select(clampi(selected, 0, maxi(0, choice.item_count - 1)))
	parent.add_child(choice)
	return choice


func _add_property(property: ActorProperty, definition: ActorDefinition, parent: VBoxContainer) -> void:
	if property.options.get("actor_reference", false):
		_add_actor_reference(property, definition, parent)
		return
	var actor := _actor
	var key := property.id
	var value: Variant = actor.get_value(key)
	if not property.object_type.is_empty():
		_add_object_reference(property, definition, parent)
		return
	var heading := HBoxContainer.new()
	parent.add_child(heading)
	var label := Label.new()
	label.text = property.label
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var reset := Button.new()
	reset.name = str(key) + "_reset"
	_add_keyframe_button(heading, actor, property, PackedStringArray([str(key)]))
	reset.text = "↺"
	var resolved_default := func() -> Variant: return property.create_default_for_actor(actor)
	reset.tooltip_text = "Reset to default: " + str(resolved_default.call())
	reset.visible = not _same_value(value, resolved_default.call())
	heading.add_child(reset)
	reset.pressed.connect(func():
		_edit_property(actor, definition, key, resolved_default.call())
		if property.options.get("refresh_inspector", false):
			call_deferred("_rebuild_selected"))
	_updaters.append(func():
		reset.visible = not _same_value(actor.get_value(key), resolved_default.call())
		reset.tooltip_text = "Reset to default: " + str(resolved_default.call()))
	var commit := func(updated: Variant):
		if not _syncing:
			_edit_property(actor, definition, key, updated)
	if property.options.has("choices"):
		var choice := _choice_editor(parent, property, int(value))
		choice.item_selected.connect(func(index: int):
			commit.call(index)
			if property.options.get("refresh_inspector", false):
				call_deferred("_rebuild_selected"))
		_updaters.append(func(): choice.select(int(actor.get_value(key))))
		return
	match property.value_type:
		TYPE_VECTOR2, TYPE_VECTOR3:
			var count := 3 if property.value_type == TYPE_VECTOR3 else 2
			var link := Button.new()
			link.name = str(key) + "_link"
			link.text = "🔗"
			link.toggle_mode = true
			link.button_pressed = ui_state.vector_linked(actor.id, key)
			link.tooltip_text = "Link components: changing one sets all to the same value"
			heading.add_child(link)
			link.toggled.connect(func(enabled: bool): ui_state.set_vector_linked(actor.id, key, enabled))
			for axis in count:
				var row := HBoxContainer.new()
				parent.add_child(row)
				var axis_label := Label.new()
				axis_label.text = ["X", "Y", "Z"][axis]
				axis_label.modulate = [Color("ee9e9e"), Color("9ed8b5"), Color("99bce8")][axis]
				row.add_child(axis_label)
				var input := _number(value[axis], float(property.options.get("step", 0.01)))
				input.name = str(key) + "_" + str(axis)
				row.add_child(input)
				var drag_state := {"origin": value}
				var make_value := func(number: float) -> Variant:
					var updated: Variant = actor.get_value(key)
					updated[axis] = number
					if link.button_pressed:
						for component in count:
							updated[component] = number
					return updated
				input.interaction_started.connect(func(): drag_state.origin = ActorData.copy_value(actor.get_value(key)))
				input.preview_changed.connect(func(number: float):
					_preview_property(actor, definition, key, make_value.call(number)))
				input.drag_committed.connect(func(number: float):
					_commit_property_preview(actor, definition, key, drag_state.origin, make_value.call(number)))
				input.drag_cancelled.connect(func():
					_preview_property(actor, definition, key, drag_state.origin))
				input.value_changed.connect(func(number: float): commit.call(make_value.call(number)))
				_updaters.append(func(): input.set_value_no_signal(actor.get_value(key)[axis]))
		TYPE_FLOAT, TYPE_INT:
			var input := _number_editor(parent, value, property)
			input.name = str(key)
			var normalize := func(number: float) -> Variant:
				if property.value_type == TYPE_INT:
					return int(number)
				return number
			var drag_state := {"origin": value}
			input.interaction_started.connect(func(): drag_state.origin = ActorData.copy_value(actor.get_value(key)))
			input.preview_changed.connect(func(number: float):
				_preview_property(actor, definition, key, normalize.call(number)))
			input.drag_committed.connect(func(number: float):
				_commit_property_preview(actor, definition, key, drag_state.origin, normalize.call(number)))
			input.drag_cancelled.connect(func():
				_preview_property(actor, definition, key, drag_state.origin))
			input.value_changed.connect(func(number: float): commit.call(normalize.call(number)))
			_updaters.append(func(): _set_number_silent(input, actor.get_value(key)))
		TYPE_BOOL:
			var input := CheckButton.new()
			input.button_pressed = value
			parent.add_child(input)
			input.toggled.connect(commit)
			_updaters.append(func(): input.set_pressed_no_signal(actor.get_value(key)))
		TYPE_STRING, TYPE_STRING_NAME:
			var row := HBoxContainer.new()
			parent.add_child(row)
			if property.options.get("file_picker", false):
				_add_file_resource_slot(row, property,
					func() -> Variant: return actor.get_value(key), commit)
			else:
				var input := LineEdit.new()
				input.name = str(key)
				input.text = str(value)
				input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				input.tooltip_text = input.text
				row.add_child(input)
				var typing := {"origin": ActorData.copy_value(value), "active": false}
				input.focus_entered.connect(func(): typing.origin = ActorData.copy_value(actor.get_value(key)); typing.active = true)
				input.text_changed.connect(func(text: String):
					if _syncing: return
					if not typing.active: typing.origin = ActorData.copy_value(actor.get_value(key)); typing.active = true
					_preview_property(actor, definition, key, StringName(text) if property.value_type == TYPE_STRING_NAME else text))
				var submit := func():
					if not typing.active: return
					typing.active = false
					_commit_property_preview(actor, definition, key, typing.origin, StringName(input.text) if property.value_type == TYPE_STRING_NAME else input.text)
				input.text_submitted.connect(func(_text: String): submit.call())
				input.focus_exited.connect(submit)
				_updaters.append(func():
					if not input.has_focus(): input.text = str(actor.get_value(key))
					input.tooltip_text = input.text)
		TYPE_COLOR:
			var input := LiveColorPickerButton.new()
			input.name = str(key)
			input.color = value
			parent.add_child(input)
			input.interaction_started.connect(func():
				if hints != null:
					hints.begin(input, "Esc cancels color drag"))
			input.interaction_ended.connect(func():
				if hints != null:
					hints.end(input))
			input.preview_changed.connect(func(updated: Color):
				_preview_property(actor, definition, key, updated))
			input.drag_committed.connect(func(original: Color, updated: Color):
				_commit_property_preview(actor, definition, key, original, updated))
			input.drag_cancelled.connect(func(original: Color):
				_preview_property(actor, definition, key, original))
			_updaters.append(func(): input.set_color_silent(actor.get_value(key)))
		_:
			_add_label(parent, "No editor for this property type yet.")


func _add_object_reference(property: ActorProperty, actor_definition: ActorDefinition,
		parent: VBoxContainer) -> void:
	var actor := _actor
	var reference := actor.get_value(property.id) as ActorObjectReference
	var base_definition := registry.get_object_definition(property.object_type)
	if base_definition == null:
		_add_label(parent, "Unknown resource type: " + str(property.object_type))
		return
	var object := _resolve_object(reference)
	var object_definition := registry.get_object_definition(object.type_id) if object != null else base_definition
	if object_definition == null:
		object_definition = base_definition
	var creatable_definitions := registry.object_definitions_for(property.object_type)
	var state_key := "Resource:" + str(property.id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := Label.new()
	label.text = property.label
	label.custom_minimum_size.x = 72
	row.add_child(label)
	var slot := ActorResourceSlot.new()
	slot.name = str(property.id) + "_resource"
	slot.toggle_mode = true
	slot.button_pressed = object != null and ui_state.category_expanded(actor.id, state_key)
	slot.alignment = HORIZONTAL_ALIGNMENT_LEFT
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.text = ("▾  " if slot.button_pressed else "▸  ") + object_definition.display_name + ("" if object != null else "  <empty>")
	slot.tooltip_text = reference.asset_id if reference != null and reference.source == ActorObjectReference.Source.ASSET else object_definition.display_name
	slot.accepts_file = _object_resource_path_allowed.bind(property)
	row.add_child(slot)
	if object != null and object.type_id == &"image":
		var edit_image := Button.new()
		edit_image.name = str(property.id) + "_open_image_workspace"
		edit_image.text = "Edit ↗"
		edit_image.tooltip_text = "Open this image in an image editor tab"
		edit_image.pressed.connect(func():
			var current := _resolve_object(actor.get_value(property.id) as ActorObjectReference)
			if current != null: _open_image_workspace(current.get_value(&"source", "")))
		row.add_child(edit_image)
	var editor := VBoxContainer.new()
	editor.visible = slot.button_pressed
	editor.add_theme_constant_override("separation", 8)
	parent.add_child(editor)
	var menu := PopupMenu.new()
	for index in creatable_definitions.size():
		menu.add_item("New " + creatable_definitions[index].display_name, 100 + index)
	menu.add_item("Load from project…", 1)
	menu.add_separator()
	menu.add_item("Make Unique", 2)
	menu.add_item("Save As…", 3)
	menu.add_separator()
	menu.add_item("Clear", 4)
	menu.set_item_disabled(menu.get_item_index(2), object == null)
	menu.set_item_disabled(menu.get_item_index(3), object == null)
	menu.set_item_disabled(menu.get_item_index(4), reference == null)
	slot.add_child(menu)
	slot.toggled.connect(func(expanded: bool):
		if object == null:
			slot.set_pressed_no_signal(false)
			menu.position = Vector2i(slot.get_screen_position() + Vector2(0, slot.size.y))
			menu.popup()
			return
		editor.visible = expanded
		slot.text = ("▾  " if expanded else "▸  ") + object_definition.display_name
		ui_state.set_category_expanded(actor.id, state_key, expanded))
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			menu.position = Vector2i(event.global_position)
			menu.popup()
			get_viewport().set_input_as_handled())
	slot.file_dropped.connect(func(path: String):
		_assign_object_resource_path(actor, actor_definition, property, path))
	menu.id_pressed.connect(_object_menu_action.bind(actor, actor_definition, property, object_definition, creatable_definitions))
	_updaters.append(func():
		if actor.get_value(property.id) != reference:
			call_deferred("_rebuild_selected"))
	if object == null:
		_add_label(editor, "Right-click the resource slot to create or load one.")
		return
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _resource_box())
	editor.add_child(panel)
	var resource_fields := VBoxContainer.new()
	resource_fields.add_theme_constant_override("separation", 7)
	panel.add_child(resource_fields)
	if registry.object_type_matches(object.type_id, &"image"):
		_add_image_object_preview(object, resource_fields)
		if object.type_id == &"image":
			return
	var current_group := ""
	var nested_group: VBoxContainer
	for nested_property in object_definition.properties:
		if not _property_is_visible(nested_property, object):
			continue
		var group := str(nested_property.options.get("group", "Properties"))
		if group != current_group:
			current_group = group
			nested_group = _stateful_category(current_group, actor.id, resource_fields, state_key)
		_add_object_value(actor, object, object_definition, nested_property, nested_group)


func _add_image_object_preview(object: ActorObjectData, parent: VBoxContainer) -> void:
	var preview_panel := PanelContainer.new()
	preview_panel.name = "ImageObjectPreview"
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color("091019")
	preview_style.border_color = Color("355568")
	preview_style.set_border_width_all(1)
	preview_style.set_corner_radius_all(8)
	preview_style.content_margin_left = 8
	preview_style.content_margin_top = 8
	preview_style.content_margin_right = 8
	preview_style.content_margin_bottom = 8
	preview_panel.add_theme_stylebox_override("panel", preview_style)
	parent.add_child(preview_panel)
	var preview := TextureRect.new()
	preview.name = "ImagePreviewTexture"
	preview.custom_minimum_size = Vector2(0, 190)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.tooltip_text = "Live preview of the image object"
	preview_panel.add_child(preview)
	var update_preview := func():
		preview.texture = ActorImageGenerator.texture_for_object(object)
		preview_panel.visible = preview.texture != null
	update_preview.call()
	_updaters.append(update_preview)


func _add_image_editor_button(parent: VBoxContainer, object: ActorObjectData) -> void:
	if object == null or object.type_id != &"image": return
	var source: Variant = object.get_value(&"source", "")
	if source == null or (source is String and source.is_empty()): return
	var button := Button.new()
	button.text = "Edit in Image Editor ↗"
	button.tooltip_text = "Open this image in a dedicated editing tab"
	button.pressed.connect(func(): _open_image_workspace(object.get_value(&"source", "")))
	parent.add_child(button)


func _open_image_workspace(value: Variant) -> void:
	if value is ActorObjectReference:
		var object := _resolve_object(value)
		if object == null or object.type_id != &"image": return
		value = object.get_value(&"source", "")
	if value == null or (value is String and value.is_empty()): return
	var tabs := get_tree().get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs
	if tabs != null: tabs.open_image(value)


func _object_menu_action(id: int, actor: ActorData, actor_definition: ActorDefinition,
		property: ActorProperty, object_definition: ActorObjectDefinition,
		creatable_definitions: Array[ActorObjectDefinition]) -> void:
	if id >= 100:
		var index := id - 100
		if index >= 0 and index < creatable_definitions.size():
			_edit_property(actor, actor_definition, property.id,
				ActorObjectReference.from_object(creatable_definitions[index].create_object()))
			_rebuild_selected()
		return
	match id:
		1:
			_choose_object_resource(actor, actor_definition, property, object_definition)
		2:
			var reference := actor.get_value(property.id) as ActorObjectReference
			var object := _resolve_object(reference)
			if object != null:
				_edit_property(actor, actor_definition, property.id, ActorObjectReference.from_object(object.copy_object()))
				_rebuild_selected()
		3:
			var reference := actor.get_value(property.id) as ActorObjectReference
			var object := _resolve_object(reference)
			if object != null:
				_save_object_resource(actor, actor_definition, property, object_definition, object)
		4:
			_edit_property(actor, actor_definition, property.id, null)
			_rebuild_selected()


func _choose_object_resource(actor: ActorData, actor_definition: ActorDefinition,
		property: ActorProperty, object_definition: ActorObjectDefinition) -> void:
	var path := await ActorProjectFilePicker.pick(self, _object_picker_property(property),
		"Choose " + object_definition.display_name)
	if path.is_empty():
		return
	_assign_object_resource_path(actor, actor_definition, property, path)


func _file_path_allowed(path: String, property: ActorProperty) -> bool:
	var extensions := PackedStringArray(property.options.get("extensions", []))
	if not ActorProjectFilePicker.is_allowed_path(ActorProjectFilePicker.root_directory(), path, extensions):
		return false
	var native_types := PackedStringArray(property.options.get("native_resource_types", []))
	if property.options.get("shader_texture", false) and path.get_extension().to_lower() in ["tres", "res"]:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		return resource is Texture2D or (resource is ActorObjectData and registry.object_type_matches(resource.type_id, &"image"))
	if native_types.is_empty() or path.get_extension().to_lower() not in ["tres", "res", "mesh"]:
		return true
	var load_path := path
	var godot_root := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	var normalized := path.replace("\\", "/")
	if normalized.begins_with(godot_root + "/"):
		load_path = "res://" + normalized.substr(godot_root.length() + 1)
	var resource := ResourceLoader.load(load_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	return (native_types.has("Mesh") and resource is Mesh) \
		or (native_types.has("PackedScene") and resource is PackedScene)


func _add_actor_reference(property: ActorProperty, definition: ActorDefinition, parent: VBoxContainer) -> void:
	var actor := _actor
	var heading := HBoxContainer.new()
	parent.add_child(heading)
	var label := Label.new()
	label.text = property.label
	heading.add_child(label)
	var slot := OptionButton.new()
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slot)
	var actor_ids: Array[String] = [""]
	slot.add_item("<empty>")
	var create := Button.new()
	create.text = "+ Create Audio"
	parent.add_child(create)
	var creates_video_audio := bool(property.options.get("create_video_audio", false))
	create.visible = false
	var update := func():
		actor_ids.assign([""])
		slot.clear()
		slot.add_item("<empty>")
		for candidate in model.actors:
			if candidate == actor or not _actor_reference_candidate(property, candidate): continue
			actor_ids.append(candidate.id)
			slot.add_item(candidate.display_name)
		var index := actor_ids.find(str(actor.values.get(property.id, "")))
		slot.select(maxi(0, index))
		create.visible = creates_video_audio and index <= 0
		if creates_video_audio:
			create.disabled = not ActorVideo.info(str(actor.values.get(&"video", ""))).get("audio", false)
			create.tooltip_text = "This video has no audio track" if create.disabled else "Extract a new linked audio child"
	update.call()
	_updaters.append(update)
	slot.item_selected.connect(func(index: int): _edit_property(actor, definition, property.id, actor_ids[index]))
	create.pressed.connect(func(): model.create_video_audio(actor))


func _actor_reference_candidate(property: ActorProperty, candidate: ActorData) -> bool:
	var allowed_types := PackedStringArray(property.options.get("actor_types", []))
	if not allowed_types.is_empty() and not allowed_types.has(str(candidate.type_id)):
		return false
	var dimension := str(property.options.get("actor_dimension", ""))
	if dimension.is_empty():
		return true
	var candidate_definition := registry.get_definition(candidate.type_id)
	var position := candidate_definition.find_property(&"position") if candidate_definition != null else null
	return position != null and ((dimension == "3d" and position.value_type == TYPE_VECTOR3)
		or (dimension == "2d" and position.value_type == TYPE_VECTOR2))

func _add_file_resource_slot(parent: Control, property: ActorProperty,
		get_value: Callable, set_value: Callable, expand_action: Callable = Callable(),
		workspace_parameters: Callable = Callable()) -> void:
	var slot := ActorResourceSlot.new()
	slot.name = str(property.id) + "_file"
	slot.alignment = HORIZONTAL_ALIGNMENT_LEFT
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.accepts_file = _file_path_allowed.bind(property)
	parent.add_child(slot)
	var edit_shader: Button
	var edit_image: Button
	if _is_shader_property(property):
		edit_shader = Button.new()
		edit_shader.name = str(property.id) + "_open_workspace"
		edit_shader.text = "Edit ↗"
		edit_shader.tooltip_text = "Open this shader in a full shader editor tab"
		edit_shader.custom_minimum_size.x = 66
		parent.add_child(edit_shader)
		edit_shader.pressed.connect(func():
			var source: Variant = get_value.call()
			if source != null and not (source is String and source.is_empty()):
				var parameters: Variant = workspace_parameters.call() if workspace_parameters.is_valid() else null
				_open_shader_resource(source, true, parameters))
	if not _is_shader_property(property) and PackedStringArray(property.options.get("extensions", [])).has("png"):
		edit_image = Button.new()
		edit_image.name = str(property.id) + "_open_image_workspace"
		edit_image.text = "Edit ↗"
		edit_image.tooltip_text = "Open this image in an image editor tab"
		edit_image.custom_minimum_size.x = 66
		parent.add_child(edit_image)
		edit_image.pressed.connect(func(): _open_image_workspace(get_value.call()))
	var menu := PopupMenu.new()
	slot.add_child(menu)
	var resource_type := _file_resource_type_name(property)
	menu.add_item("New " + resource_type, 0)
	var is_audio := PackedStringArray(property.options.get("extensions", [])).has("mp3") or PackedStringArray(property.options.get("extensions", [])).has("mp4")
	menu.set_item_disabled(menu.get_item_index(0), is_audio)
	if property.options.get("shader_texture", false): menu.add_item("New Noise Image", 5)
	menu.add_item("Load from project…", 1)
	menu.add_separator()
	menu.add_item("Make Unique", 2)
	menu.add_item("Save As…", 3)
	menu.add_separator()
	menu.add_item("Clear", 4)
	var update_slot := func():
		var value: Variant = get_value.call()
		var empty: bool = value == null or (value is String and value.is_empty())
		slot.text = "▸  " + resource_type + ("  <empty>" if empty else "  " + _file_resource_display_name(value))
		slot.tooltip_text = "Drop a compatible project file here" if empty else _file_resource_tooltip(value)
		menu.set_item_disabled(menu.get_item_index(2), is_audio or empty or value is Resource)
		menu.set_item_disabled(menu.get_item_index(3), empty)
		menu.set_item_disabled(menu.get_item_index(4), empty)
		if is_instance_valid(edit_shader): edit_shader.visible = not empty
		if is_instance_valid(edit_image):
			var supported_image := value is Texture2D or value is Image
			if value is String:
				supported_image = str(value).get_extension().to_lower() in IMAGE_FILE_EXTENSIONS
			if value is ActorObjectReference:
				var image_object := _resolve_object(value)
				supported_image = image_object != null and image_object.type_id == &"image" \
					and image_object.get_value(&"source", "") != null \
					and str(image_object.get_value(&"source", "")) != ""
			edit_image.visible = not empty and supported_image
	update_slot.call()
	var show_menu := func(position: Vector2):
		update_slot.call()
		menu.position = Vector2i(position)
		menu.popup()
	slot.pressed.connect(func():
		var value: Variant = get_value.call()
		if expand_action.is_valid() and expand_action.call():
			return
		if _is_shader_property(property) and value != null and not (value is String and value.is_empty()):
			_open_shader_resource(value)
		else:
			show_menu.call(slot.get_screen_position() + Vector2(0, slot.size.y)))
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			show_menu.call(event.global_position)
			get_viewport().set_input_as_handled())
	slot.file_dropped.connect(func(path: String):
		set_value.call(path)
		if _is_shader_property(property):
			_open_shader_resource(path))
	menu.id_pressed.connect(func(id: int):
		_file_resource_menu_action(id, property, get_value, set_value, update_slot))
	_updaters.append(update_slot)


func _shader_texture_options() -> Dictionary:
	return {"extensions": Array(IMAGE_FILE_EXTENSIONS) + ["tres", "res"],
		"raw_extensions": Array(IMAGE_FILE_EXTENSIONS),
		"accepted_object_types": ["image", "noise_image"],
		"native_resource_types": ["Texture2D"], "shader_texture": true,
		"file_picker": true}


func _noise_object_from_value(value: Variant) -> ActorObjectData:
	var object: ActorObjectData
	if value is ActorObjectReference:
		object = _resolve_object(value)
	elif value is String and value.get_extension().to_lower() in ["tres", "res"]:
		object = ResourceLoader.load(value, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	return object if object != null and object.type_id == &"noise_image" else null


func _add_shader_texture_uniform(parent: VBoxContainer, property: ActorProperty,
		get_value: Callable, set_value: Callable, actor: ActorData = null,
		file_owner: ActorObjectData = null) -> void:
	var noise := _noise_object_from_value(get_value.call())
	var state_id := actor.id if actor != null else "FileResource:" + file_owner.resource_path
	var state_key := "ShaderTexture:" + str(property.id)
	var editor := VBoxContainer.new()
	var expansion := {"value": noise != null and ui_state.category_expanded(state_id, state_key)}
	var row := HBoxContainer.new()
	parent.add_child(row)
	_add_file_resource_slot(row, property, get_value, set_value, func() -> bool:
		if noise == null:
			return false
		expansion.value = not expansion.value
		editor.visible = expansion.value
		ui_state.set_category_expanded(state_id, state_key, expansion.value)
		return true)
	parent.add_child(editor)
	editor.visible = expansion.value
	if noise == null:
		return
	var definition := registry.get_object_definition(&"noise_image")
	if definition == null:
		return
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _resource_box())
	editor.add_child(panel)
	var fields_box := VBoxContainer.new()
	fields_box.add_theme_constant_override("separation", 7)
	panel.add_child(fields_box)
	_add_image_object_preview(noise, fields_box)
	var current_group := ""
	var group: VBoxContainer
	for noise_property in definition.properties:
		var property_group := str(noise_property.options.get("group", "Properties"))
		if property_group != current_group:
			current_group = property_group
			group = _stateful_category(current_group, state_id, fields_box, state_key)
		if actor != null:
			_add_object_value(actor, noise, definition, noise_property, group)
		else:
			_add_file_object_value(noise, definition, noise_property, group, file_owner)


func _file_resource_menu_action(id: int, property: ActorProperty, get_value: Callable,
		set_value: Callable, update_slot: Callable) -> void:
	match id:
		5:
			var noise_definition := registry.get_object_definition(&"noise_image")
			if noise_definition != null: set_value.call(ActorObjectReference.from_object(noise_definition.create_object()))
		0:
			if _is_shader_property(property):
				var shader := Shader.new()
				shader.resource_name = "Shader"
				shader.code = str(property.options.get("new_file_template", "shader_type spatial;\n"))
				set_value.call(shader)
				_open_shader_resource(get_value.call())
			elif _is_mesh_property(property):
				var mesh := BoxMesh.new()
				mesh.resource_name = "Mesh"
				set_value.call(mesh)
			else:
				var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
				image.fill(Color.TRANSPARENT)
				var texture := ImageTexture.create_from_image(image)
				texture.resource_name = "Image"
				set_value.call(texture)
		1:
			var chosen := await ActorProjectFilePicker.pick(self, property, "Choose " + property.label)
			if not chosen.is_empty():
				set_value.call(chosen)
				if _is_shader_property(property):
					_open_shader_resource(chosen)
		2:
			var embedded := _file_resource_to_embedded(get_value.call(), property)
			if embedded != null:
				set_value.call(embedded)
				if _is_shader_property(property):
					_open_shader_resource(get_value.call())
		3:
			await _save_file_resource(property, get_value.call(), set_value)
		4:
			set_value.call(null)
	update_slot.call()


func _file_resource_type_name(property: ActorProperty) -> String:
	if PackedStringArray(property.options.get("extensions", [])).has("mp4"): return "Video"
	if PackedStringArray(property.options.get("extensions", [])).has("mp3"): return "Audio"
	if _is_shader_property(property):
		return "Shader"
	if _is_mesh_property(property):
		return "Mesh / 3D Model"
	return "Image"


func _is_shader_property(property: ActorProperty) -> bool:
	return PackedStringArray(property.options.get("extensions", [])).has("gdshader")


func _is_mesh_property(property: ActorProperty) -> bool:
	var extensions := PackedStringArray(property.options.get("extensions", []))
	return extensions.has("glb") or extensions.has("mesh")


func _file_resource_display_name(value: Variant) -> String:
	if value is ActorObjectReference:
		return "Noise Image" if value.object_type == &"noise_image" else "Image"
	if value is String:
		return value.get_file()
	if value is Resource and not value.resource_name.is_empty():
		return value.resource_name
	return "<embedded>"


func _file_resource_tooltip(value: Variant) -> String:
	return value if value is String else "Embedded resource"


func _file_resource_to_embedded(value: Variant, property: ActorProperty) -> Resource:
	if value is Resource:
		return value.duplicate(true)
	var path := str(value)
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	if _is_shader_property(property):
		var shader := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Shader
		return shader.duplicate(true) if shader != null else null
	if _is_mesh_property(property):
		var mesh_resource: Resource = FileOperations.load_3d_model(path) if path.get_extension().to_lower() in ["glb", "gltf", "fbx"] else ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		return mesh_resource.duplicate(true) if mesh_resource is Mesh or mesh_resource is PackedScene else null
	if PackedStringArray(property.options.get("extensions", [])).has("mp3"):
		return ActorAudio.source(path)
	if property.options.get("shader_texture", false) and path.get_extension().to_lower() in ["tres", "res"]:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource is Texture2D: return resource.duplicate(true)
		return ActorObjectReference.from_object(resource.copy_object()) if resource is ActorObjectData else null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	var texture := ImageTexture.create_from_image(image)
	texture.resource_name = path.get_file().get_basename()
	return texture


func _save_file_resource(property: ActorProperty, value: Variant, set_value: Callable) -> void:
	var extensions := PackedStringArray(property.options.get("extensions", []))
	if extensions.is_empty():
		return
	var extension := str(value).get_extension().to_lower() if value is String else extensions[0]
	if value is ActorObjectReference: extension = "tres"
	if not extensions.has(extension):
		extension = extensions[0]
	var suggested := _file_resource_display_name(value).get_basename()
	if suggested.begins_with("<"):
		suggested = _file_resource_type_name(property)
	var formats := ActorMediaExport.formats(property, value)
	if not formats.has(extension): extension = formats[0]
	var result := await ActorProjectResourceSaveDialog.pick(self, "Save " + _file_resource_type_name(property),
		suggested, extension, not extensions.has("mp4"), formats)
	if result.get("cancelled", true):
		return
	if result.get("embedded", false):
		var embedded := _file_resource_to_embedded(value, property)
		if embedded != null:
			set_value.call(embedded)
			if _is_shader_property(property):
				_open_shader_resource(embedded)
		return
	var path := str(result.get("path", ""))
	if _is_mesh_property(property):
		value = _file_resource_to_embedded(value, property)
	var media := extensions.has("mp4") or extensions.has("mp3") or extensions.has("png") or value is ActorObjectReference
	if path.is_empty() or not (await ActorMediaExport.write_async(self, value, path, property) if media else _write_file_resource(value, path)):
		return
	# Exporting audio/video must not replace the source and discard trims or the
	# owned audio child. Save As is an export; the original attachment stays intact.
	if not extensions.has("mp4") and not extensions.has("mp3"): set_value.call(path)
	if LocalProjectFilesystem.node != null:
		LocalProjectFilesystem.update_root_folder()
	if _is_shader_property(property):
		_open_shader_resource(path)


func _write_file_resource(value: Variant, path: String) -> bool:
	if value is ActorObjectReference:
		var object := ActorAnimation.resolve_reference(value)
		return object != null and ResourceSaver.save(object, path) == OK
	if value is String:
		var source: String = ProjectSettings.globalize_path(value) if value.begins_with("res://") else value
		return DirAccess.copy_absolute(source, path) == OK
	if value is Shader:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return false
		file.store_string(value.code)
		return true
	if value is Mesh or value is PackedScene:
		return ResourceSaver.save(value, path) == OK
	var image: Image = value.get_image() if value is Texture2D else value as Image
	return image != null and image.save_png(path) == OK


func _open_shader_resource(value: Variant, full_workspace: bool = false, parameters: Variant = null) -> void:
	if full_workspace:
		# Commit any pending mini-editor revision before the tab reads this source.
		for candidate in get_tree().get_nodes_in_group("shader_code_editor"):
			if candidate is ShaderCodeEditor and not (candidate as ShaderCodeEditor).dedicated_mode:
				var mini := candidate as ShaderCodeEditor
				var same_source: bool = (value is Shader and mini.current_shader == value) \
					or (value is String and mini.current_path.replace("\\", "/").simplify_path() == str(value).replace("\\", "/").simplify_path())
				if same_source:
					mini.save_timer.stop()
					mini.save()
		var tabs := get_tree().get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs
		if tabs != null:
			tabs.open_shader(value, parameters)
			return
	var editor: ShaderCodeEditor
	for candidate in get_tree().get_nodes_in_group("shader_code_editor"):
		if candidate is ShaderCodeEditor and not (candidate as ShaderCodeEditor).dedicated_mode:
			editor = candidate
			break
	if editor != null:
		if not editor.shader_changed.is_connected(_shader_code_changed):
			editor.shader_changed.connect(_shader_code_changed)
		editor.open_shader(value)


func _shader_code_changed(_source: Variant) -> void:
	# Shader code can change both the rendered program and the list/defaults of
	# uniforms, so refresh the runtime and reconstruct the nested inspector.
	model.changed.emit()
	call_deferred("_rebuild_selected")


func _same_value(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	return left == right


func _add_keyframe_button(parent: Control, actor: ActorData, property: ActorProperty,
		path: PackedStringArray, fallback: Variant = null) -> void:
	if not property.can_keyframe():
		return
	var button := Button.new()
	button.name = str(property.id) + "_keyframe"
	button.custom_minimum_size.x = 28
	button.toggle_mode = true
	var active_style := StyleBoxFlat.new()
	active_style.bg_color = Color("296c5b")
	active_style.border_color = Color("94efca")
	active_style.set_border_width_all(2)
	active_style.set_corner_radius_all(4)
	active_style.content_margin_left = 5
	active_style.content_margin_right = 5
	button.add_theme_stylebox_override("pressed", active_style)
	button.add_theme_stylebox_override("hover_pressed", active_style)
	parent.add_child(button)
	var insert := Button.new()
	insert.name = str(property.id) + "_insert_keyframe"
	insert.text = "+◆"
	insert.tooltip_text = "Insert a keyframe at the timeline playhead"
	parent.add_child(insert)
	var local_time := func() -> float:
		var clip := model.clip_for_actor_id(actor.id)
		return clip.local_time(model.playhead_time) if clip != null else 0.0
	var update := func():
		var track := actor.animation_track(path)
		var keyed := track != null and track.key_at(local_time.call()) != null
		button.text = "◆" if keyed else ("◈" if track != null else "◇")
		var active := model.overlay_actor_id == actor.id and model.overlay_path == path
		button.modulate = Color.WHITE if active else (Color("ffce80") if keyed else (Color("72cfb8") if track != null else Color.WHITE))
		button.set_pressed_no_signal(active)
		button.tooltip_text = "Show / hide %s keyframes on the actor. Only one property is shown at once. Right-click to remove keys." % property.label
	update.call()
	_updaters.append(update)
	var insert_key := func():
		var base: Variant = ActorAnimation.value_at_path(actor, path)
		if base == null:
			base = fallback if fallback != null else property.create_default()
		var value: Variant = ActorAnimation.sampled_value(actor, path, local_time.call(), base)
		var track_label := " / ".join(path.slice(0, path.size() - 1)) + " / " + property.label if path.size() > 1 else str(property.options.get("group", "Properties")) + " / " + property.label
		model.add_keyframe(actor, path, track_label, value, property.options.has("choices"))
		var track := actor.animation_track(path)
		var panel := get_tree().get_first_node_in_group("actor_keyframe_editors") as ActorKeyframeEditor
		if panel != null and track != null:
			panel.lanes.selected_keys.assign([track.key_at(local_time.call()).id])
			panel._build_details()
			panel.lanes.queue_redraw()
	insert.pressed.connect(insert_key)
	button.pressed.connect(func():
		var enabled := button.button_pressed
		model.overlay_actor_id = actor.id if enabled else ""
		model.overlay_path = path.duplicate() if enabled else PackedStringArray()
		if enabled and actor.animation_track(path) == null:
			insert_key.call()
		model.changed.emit())
	var menu := PopupMenu.new()
	button.add_child(menu)
	menu.add_item("Remove Key at Cursor", 0)
	menu.add_item("Remove Property Animation", 1)
	button.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			var track := actor.animation_track(path)
			menu.set_item_disabled(0, track == null or track.key_at(local_time.call()) == null)
			menu.set_item_disabled(1, track == null)
			menu.position = Vector2i(event.global_position)
			menu.popup()
			get_viewport().set_input_as_handled())
	menu.id_pressed.connect(func(id: int):
		var track := actor.animation_track(path)
		if track == null:
			return
		var ids: Array[String] = []
		for part in actor.animation_tracks:
			if part.path != path: continue
			for key in part.keys:
				if id == 1 or key == part.key_at(local_time.call()):
					ids.append(key.id)
		model.delete_keyframes(actor, ids))


func _object_resource_path_allowed(path: String, property: ActorProperty) -> bool:
	if not _file_path_allowed(path, _object_picker_property(property)):
		return false
	if _is_raw_image_path(path) and _property_accepts_image(property):
		return true
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	return loaded != null and property.accepts(ActorObjectReference.from_asset(path, loaded.type_id))


func _property_accepts_image(property: ActorProperty) -> bool:
	var accepted := PackedStringArray(property.options.get("accepted_object_types", [str(property.object_type)]))
	return accepted.has("image")


func _is_raw_image_path(path: String) -> bool:
	return IMAGE_FILE_EXTENSIONS.has(path.get_extension().to_lower())


func _object_picker_property(property: ActorProperty) -> ActorProperty:
	if not _property_accepts_image(property):
		return property
	var picker_property := property.duplicate(true) as ActorProperty
	var picker_options := property.options.duplicate(true)
	var extensions := PackedStringArray(picker_options.get("extensions", []))
	for extension in IMAGE_FILE_EXTENSIONS:
		if not extensions.has(extension):
			extensions.append(extension)
	picker_options["extensions"] = extensions
	picker_options["raw_extensions"] = IMAGE_FILE_EXTENSIONS
	picker_property.options = picker_options
	return picker_property


func _assign_object_resource_path(actor: ActorData, actor_definition: ActorDefinition,
		property: ActorProperty, path: String) -> void:
	if not _object_resource_path_allowed(path, property):
		return
	if _is_raw_image_path(path) and _property_accepts_image(property):
		var image_definition := registry.get_object_definition(&"image")
		if image_definition == null:
			return
		var image_object := image_definition.create_object()
		image_object.set_value(&"source", path)
		_edit_property(actor, actor_definition, property.id,
			ActorObjectReference.from_object(image_object))
		_rebuild_selected()
		return
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	_edit_property(actor, actor_definition, property.id, ActorObjectReference.from_asset(path, loaded.type_id))
	_rebuild_selected()


func _save_object_resource(actor: ActorData, actor_definition: ActorDefinition,
		property: ActorProperty, object_definition: ActorObjectDefinition, object: ActorObjectData) -> void:
	var suggested := actor.display_name + " " + object_definition.display_name
	var result := await ActorProjectResourceSaveDialog.pick(self, "Save " + object_definition.display_name, suggested,
		"tres", true, ActorMediaExport.formats(property, object))
	if result.get("cancelled", true):
		return
	if result.get("embedded", false):
		_edit_property(actor, actor_definition, property.id, ActorObjectReference.from_object(object.copy_object()))
		_rebuild_selected()
		return
	var path := str(result.get("path", ""))
	if path.is_empty():
		return
	var saved := object.copy_object()
	if await ActorMediaExport.write_async(self, saved, path, property):
		_assign_object_resource_path(actor, actor_definition, property, path)
		if LocalProjectFilesystem.node != null:
			LocalProjectFilesystem.update_root_folder()
		_rebuild_selected()


func _create_project_file(property: ActorProperty, title: String) -> String:
	var extensions := PackedStringArray(property.options.get("extensions", []))
	if extensions.is_empty():
		return ""
	var extension := extensions[0].trim_prefix(".").to_lower()
	var suggested := str(property.options.get("new_file_name", "New " + property.label))
	var result := await ActorProjectResourceSaveDialog.pick(self, title, suggested, extension, false)
	if result.get("cancelled", true):
		return ""
	var path := str(result.get("path", ""))
	if path.is_empty():
		return ""
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(str(property.options.get("new_file_template", "")))
	if LocalProjectFilesystem.node != null:
		LocalProjectFilesystem.update_root_folder()
	return path


func _resolve_object(reference: ActorObjectReference) -> ActorObjectData:
	if reference == null:
		return null
	return reference.resolve(func(path: String):
		return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData)


func _rebuild_selected() -> void:
	_actor = null
	refresh()


func _queue_rebuild_selected() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_finish_queued_rebuild")


func _finish_queued_rebuild() -> void:
	_rebuild_queued = false
	_rebuild_selected()


func refresh_shader_source(_source: Variant) -> void:
	# Shader code can add/remove uniforms and linked tabs can alter their values.
	# Rebuild the selected actor while retaining its inspector viewport state.
	_rebuild_selected()


func _resource_box() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("121c27")
	style.border_color = Color("38566a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 12
	return style


func _property_is_visible(property: ActorProperty, owner: Object) -> bool:
	var visible_when: Dictionary = property.options.get("visible_when", {})
	if not visible_when.is_empty():
		var dependency := StringName(visible_when.get("property", ""))
		var accepted_values: Array = visible_when.get("values", [])
		var value: Variant = owner.get_value(dependency)
		if owner is ActorObjectData and _actor != null:
			var path := model.object_animation_path(_actor, owner, dependency)
			var clip := model.clip_for_actor_id(_actor.id)
			if not path.is_empty() and clip != null:
				value = ActorAnimation.sampled_value(_actor, path, clip.local_time(model.playhead_time), value)
		return not dependency.is_empty() and accepted_values.has(value)
	if owner is ActorData:
		var definition := registry.get_definition((owner as ActorData).type_id)
		if definition != null:
			var group := str(property.options.get("group", "Properties"))
			for controller in definition.properties:
				var group_visibility: Dictionary = controller.options.get("controls_group_visibility", {})
				if group_visibility.has(group):
					var values: Array = group_visibility[group]
					return values.has((owner as ActorData).get_value(controller.id))
	return true


func _animated_layout_signature(actor: ActorData) -> String:
	if actor == null:
		return ""
	var clip := model.clip_for_actor_id(actor.id)
	if clip == null:
		return ""
	var parts := PackedStringArray()
	for track in actor.animation_tracks:
		var property: ActorProperty = null
		if track.path.size() == 1:
			var definition := registry.get_definition(actor.type_id)
			property = definition.find_property(StringName(track.path[0])) if definition != null else null
		else:
			var reference: Variant = ActorAnimation.value_at_path(actor, track.path.slice(0, track.path.size() - 1))
			if reference is ActorObjectReference:
				var object := ActorAnimation.resolve_reference(reference)
				var definition := registry.get_object_definition(object.type_id) if object != null else null
				property = definition.find_property(StringName(track.path[-1])) if definition != null else null
		if property != null and (property.options.get("refresh_inspector", false) or property.options.has("controls_group_visibility")):
			parts.append("%s=%s" % [" / ".join(track.path), str(track.sample(clip.local_time(model.playhead_time)))])
	return "|".join(parts)


func _add_nested_object_reference(actor: ActorData, owner: ActorObjectData,
		owner_definition: ActorObjectDefinition, property: ActorProperty,
		parent: VBoxContainer) -> void:
	var reference := owner.get_value(property.id) as ActorObjectReference
	var base_definition := registry.get_object_definition(property.object_type)
	if base_definition == null:
		_add_label(parent, "Unknown resource type: " + str(property.object_type))
		return
	var object := _resolve_object(reference)
	var object_definition := registry.get_object_definition(object.type_id) if object != null else base_definition
	if object_definition == null:
		object_definition = base_definition
	var creatable_definitions := registry.object_definitions_for(property.object_type)
	var state_key := "NestedResource:%s:%s" % [owner.type_id, property.id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := Label.new()
	label.text = property.label
	label.custom_minimum_size.x = 72
	row.add_child(label)
	var slot := ActorResourceSlot.new()
	slot.name = str(property.id) + "_resource"
	slot.toggle_mode = true
	slot.button_pressed = object != null and ui_state.category_expanded(actor.id, state_key)
	slot.alignment = HORIZONTAL_ALIGNMENT_LEFT
	slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slot.text = ("▾  " if slot.button_pressed else "▸  ") + object_definition.display_name + ("" if object != null else "  <empty>")
	slot.accepts_file = _object_resource_path_allowed.bind(property)
	row.add_child(slot)
	var editor := VBoxContainer.new()
	editor.visible = slot.button_pressed
	editor.add_theme_constant_override("separation", 8)
	parent.add_child(editor)
	var menu := PopupMenu.new()
	for index in creatable_definitions.size():
		menu.add_item("New " + creatable_definitions[index].display_name, 100 + index)
	menu.add_item("Load from project…", 1)
	menu.add_separator()
	menu.add_item("Make Unique", 2)
	menu.add_item("Save As…", 3)
	menu.add_separator()
	menu.add_item("Clear", 4)
	menu.set_item_disabled(menu.get_item_index(2), object == null)
	menu.set_item_disabled(menu.get_item_index(3), object == null)
	menu.set_item_disabled(menu.get_item_index(4), reference == null)
	slot.add_child(menu)
	slot.toggled.connect(func(expanded: bool):
		if object == null:
			slot.set_pressed_no_signal(false)
			menu.position = Vector2i(slot.get_screen_position() + Vector2(0, slot.size.y))
			menu.popup()
			return
		editor.visible = expanded
		slot.text = ("▾  " if expanded else "▸  ") + object_definition.display_name
		ui_state.set_category_expanded(actor.id, state_key, expanded))
	slot.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			menu.position = Vector2i(event.global_position)
			menu.popup()
			get_viewport().set_input_as_handled())
	slot.file_dropped.connect(_assign_nested_object_resource_path.bind(actor, owner, owner_definition, property))
	menu.id_pressed.connect(_nested_object_menu_action.bind(actor, owner, owner_definition,
		property, object_definition, creatable_definitions))
	_updaters.append(func():
		if owner.get_value(property.id) != reference:
			call_deferred("_rebuild_selected"))
	if object == null:
		return
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _resource_box())
	editor.add_child(panel)
	var resource_fields := VBoxContainer.new()
	resource_fields.add_theme_constant_override("separation", 7)
	panel.add_child(resource_fields)
	if registry.object_type_matches(object.type_id, &"image"):
		_add_image_object_preview(object, resource_fields)
	var current_group := ""
	var nested_group: VBoxContainer
	for nested_property in object_definition.properties:
		if not _property_is_visible(nested_property, object):
			continue
		var group := str(nested_property.options.get("group", "Properties"))
		if group != current_group:
			current_group = group
			nested_group = _stateful_category(current_group, actor.id, resource_fields, state_key)
		_add_object_value(actor, object, object_definition, nested_property, nested_group)


func _nested_object_menu_action(id: int, actor: ActorData, owner: ActorObjectData,
		owner_definition: ActorObjectDefinition, property: ActorProperty,
		object_definition: ActorObjectDefinition,
		creatable_definitions: Array[ActorObjectDefinition]) -> void:
	if id >= 100:
		var index := id - 100
		if index >= 0 and index < creatable_definitions.size():
			model.edit_object_property(actor, owner, owner_definition, property.id,
				ActorObjectReference.from_object(creatable_definitions[index].create_object()))
			_rebuild_selected()
		return
	match id:
		1:
			var path := await ActorProjectFilePicker.pick(self, _object_picker_property(property),
				"Choose " + object_definition.display_name)
			if not path.is_empty():
				_assign_nested_object_resource_path(path, actor, owner, owner_definition, property)
		2:
			var object := _resolve_object(owner.get_value(property.id) as ActorObjectReference)
			if object != null:
				model.edit_object_property(actor, owner, owner_definition, property.id,
					ActorObjectReference.from_object(object.copy_object()))
				_rebuild_selected()
		3:
			var object := _resolve_object(owner.get_value(property.id) as ActorObjectReference)
			if object != null:
				await _save_nested_object_resource(actor, owner, owner_definition, property, object_definition, object)
		4:
			model.edit_object_property(actor, owner, owner_definition, property.id, null)
			_rebuild_selected()


func _assign_nested_object_resource_path(path: String, actor: ActorData,
		owner: ActorObjectData, owner_definition: ActorObjectDefinition,
		property: ActorProperty) -> void:
	if not _object_resource_path_allowed(path, property):
		return
	if _is_raw_image_path(path) and _property_accepts_image(property):
		var image_definition := registry.get_object_definition(&"image")
		if image_definition == null:
			return
		var image_object := image_definition.create_object()
		image_object.set_value(&"source", path)
		model.edit_object_property(actor, owner, owner_definition, property.id,
			ActorObjectReference.from_object(image_object))
		_rebuild_selected()
		return
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	model.edit_object_property(actor, owner, owner_definition, property.id,
		ActorObjectReference.from_asset(path, loaded.type_id))
	_rebuild_selected()


func _save_nested_object_resource(actor: ActorData, owner: ActorObjectData,
		owner_definition: ActorObjectDefinition, property: ActorProperty,
		object_definition: ActorObjectDefinition, object: ActorObjectData) -> void:
	var result := await ActorProjectResourceSaveDialog.pick(self,
		"Save " + object_definition.display_name,
		actor.display_name + " " + object_definition.display_name, "tres", true, ActorMediaExport.formats(property, object))
	if result.get("cancelled", true):
		return
	if result.get("embedded", false):
		model.edit_object_property(actor, owner, owner_definition, property.id,
			ActorObjectReference.from_object(object.copy_object()))
		_rebuild_selected()
		return
	var path := str(result.get("path", ""))
	if not path.is_empty() and await ActorMediaExport.write_async(self, object.copy_object(), path, property):
		_assign_nested_object_resource_path(path, actor, owner, owner_definition, property)
		if LocalProjectFilesystem.node != null:
			LocalProjectFilesystem.update_root_folder()
		_rebuild_selected()


func _animated_object_value(actor: ActorData, object: ActorObjectData,
		definition: ActorObjectDefinition, property: ActorProperty) -> Variant:
	var base: Variant = definition.value_for(object, property)
	var path := model.object_animation_path(actor, object, property.id)
	var clip := model.clip_for_actor_id(actor.id)
	if clip == null or path.is_empty():
		return base
	var time := clip.local_time(model.playhead_time)
	if property.id == &"uniforms" and base is Dictionary:
		var uniforms: Dictionary = base.duplicate()
		for track in actor.animation_tracks:
			if track.path.size() == path.size() + 1 and track.path.slice(0, path.size()) == path:
				uniforms[StringName(track.path[-1])] = ActorAnimation.sampled_value(actor, track.path, time)
		return uniforms
	return ActorAnimation.sampled_value(actor, path, time, base)


## Shader workspaces can outlive the ActorData instances which created them.
## Scene-tab restoration replaces those instances, so the callbacks must resolve
## the current actor and nested object instead of retaining detached Resources.
func shader_workspace_parameter_binding(actor_id: String, object_path: PackedStringArray,
		origin_actor: ActorData = null) -> Dictionary:
	var origin_history := model.history
	var resolve_current := func() -> Dictionary:
		var current_actor := model.actor_for_id(actor_id)
		# Shader tabs are independent workspaces. Another scene can be loaded in
		# the shared timeline while this tab remains linked to its originating
		# scene, whose ActorData resource is still owned by that scene document.
		if current_actor == null and is_instance_valid(origin_actor) and origin_actor.id == actor_id:
			current_actor = origin_actor
		if current_actor == null:
			return {}
		var value: Variant = ActorAnimation.value_at_path(current_actor, object_path)
		if value is ActorObjectReference:
			value = ActorAnimation.resolve_reference(value)
		var current_object := value as ActorObjectData
		if current_object == null:
			return {}
		var current_definition := registry.get_object_definition(current_object.type_id)
		if current_definition == null:
			return {}
		return {"actor": current_actor, "object": current_object, "definition": current_definition}
	var read_parameters := func() -> Dictionary:
		var current: Dictionary = resolve_current.call()
		if current.is_empty():
			return {}
		var current_definition := current["definition"] as ActorObjectDefinition
		var uniforms_property := current_definition.find_property(&"uniforms")
		if uniforms_property == null:
			return {}
		var values: Variant = _animated_object_value(current["actor"], current["object"],
			current_definition, uniforms_property)
		return values.duplicate(true) if values is Dictionary else {}
	var write_parameter := func(name: StringName, value: Variant, mode: String, original: Variant):
		var current: Dictionary = resolve_current.call()
		if current.is_empty():
			return
		if model.actors.has(current["actor"]):
			model.edit_shader_uniform(current["actor"], current["object"], current["definition"],
				name, value, mode, original)
		else:
			_edit_detached_shader_uniform(current["object"], current["definition"],
				origin_history, name, value, mode, original)
		# A linked shader tab replaces nested resource references in the uniforms
		# dictionary. The inspector's old controls otherwise keep editing the
		# detached Noise Image and show stale parameters until actor reselection.
		if _actor != null and _actor.id == actor_id and (value is ActorObjectReference
				or value is ActorObjectData or value is Texture2D or value is String or value == null):
			_queue_rebuild_selected()
	return {"values": read_parameters.call(), "reader": read_parameters, "writer": write_parameter}


func _edit_detached_shader_uniform(object: ActorObjectData, definition: ActorObjectDefinition,
		history: UndoRedo, name: StringName, value: Variant, mode: String, original: Variant) -> void:
	var property := definition.find_property(&"uniforms")
	if property == null:
		return
	var before: Dictionary = definition.value_for(object, property).duplicate(true)
	var after := before.duplicate(true)
	after[name] = ActorData.copy_value(value)
	if mode == "preview":
		_set_detached_object_property(object, &"uniforms", after)
		return
	if mode == "commit" and original is Dictionary:
		for key: Variant in original:
			before[key] = ActorData.copy_value(original[key])
	if before == after:
		return
	history.create_action("Change " + property.label)
	history.add_do_method(_set_detached_object_property.bind(object, &"uniforms", after))
	history.add_undo_method(_set_detached_object_property.bind(object, &"uniforms", before))
	history.commit_action()


func _set_detached_object_property(object: ActorObjectData, key: StringName, value: Variant) -> void:
	object.set_value(key, ActorData.copy_value(value))
	if not object.resource_path.is_empty():
		ResourceSaver.save(object, object.resource_path)


func _add_object_value(actor: ActorData, object: ActorObjectData,
		definition: ActorObjectDefinition, property: ActorProperty, parent: VBoxContainer) -> void:
	if property.options.get("system_font", false):
		_add_label(parent, property.label)
		var selector := _font_editor(parent, str(definition.value_for(object, property)), func(value: String): model.edit_object_property(actor, object, definition, property.id, value))
		_updaters.append(func(): selector.text = str(definition.value_for(object, property)))
		return
	if property.options.get("shader_uniforms", false):
		_add_shader_uniforms(actor, object, definition, parent)
		return
	if not property.object_type.is_empty():
		_add_nested_object_reference(actor, object, definition, property, parent)
		return
	var current_value: Variant = _animated_object_value(actor, object, definition, property)
	var heading := HBoxContainer.new()
	parent.add_child(heading)
	var label := Label.new()
	label.text = property.label
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var animation_path := ActorAnimation.path_to_object(actor, object)
	if not animation_path.is_empty():
		animation_path.append(str(property.id))
		_add_keyframe_button(heading, actor, property, animation_path)
	var reset := Button.new()
	reset.name = str(property.id) + "_reset"
	reset.text = "↺"
	reset.visible = not _same_value(current_value, property.create_default())
	reset.pressed.connect(func():
		model.edit_object_property(actor, object, definition, property.id, property.create_default())
		if property.options.get("refresh_inspector", false):
			call_deferred("_rebuild_selected"))
	heading.add_child(reset)
	_updaters.append(func(): reset.visible = not _same_value(_animated_object_value(actor, object, definition, property), property.create_default()))
	if property.options.has("choices"):
		var choice := _choice_editor(parent, property, int(current_value))
		choice.item_selected.connect(func(index: int):
			model.edit_object_property(actor, object, definition, property.id, index)
			if property.options.get("refresh_inspector", false):
				call_deferred("_rebuild_selected"))
		_updaters.append(func(): choice.select(int(_animated_object_value(actor, object, definition, property))))
		return
	match property.value_type:
		TYPE_FLOAT, TYPE_INT:
			var input := _number_editor(parent, float(current_value), property)
			var normalize := func(value: float) -> Variant: return int(value) if property.value_type == TYPE_INT else value
			var state := {"origin": current_value}
			input.interaction_started.connect(func(): state.origin = _animated_object_value(actor, object, definition, property))
			input.preview_changed.connect(func(value: float): model.preview_object_property(actor, object, definition, property.id, normalize.call(value)))
			input.drag_committed.connect(func(value: float): model.commit_object_property_preview(actor, object, definition, property.id, state.origin, normalize.call(value)))
			input.drag_cancelled.connect(func(): model.preview_object_property(actor, object, definition, property.id, state.origin))
			input.value_changed.connect(func(value: float): model.edit_object_property(actor, object, definition, property.id, normalize.call(value)))
			_updaters.append(func(): _set_number_silent(input, _animated_object_value(actor, object, definition, property)))
		TYPE_VECTOR2, TYPE_VECTOR3:
			var component_count := 2 if property.value_type == TYPE_VECTOR2 else 3
			var link_key := StringName("Object:" + str(definition.type_id) + ":" + str(property.id))
			var link := Button.new()
			link.text = "🔗"
			link.toggle_mode = true
			link.button_pressed = ui_state.vector_linked(actor.id, link_key)
			link.tooltip_text = "Link components: changing one sets all to the same value"
			heading.add_child(link)
			link.toggled.connect(func(enabled: bool): ui_state.set_vector_linked(actor.id, link_key, enabled))
			for axis in component_count:
				var row := HBoxContainer.new()
				parent.add_child(row)
				var axis_label := Label.new()
				axis_label.text = ["X", "Y", "Z"][axis]
				axis_label.modulate = [Color("ee9e9e"), Color("9ed8b5"), Color("99bce8")][axis]
				row.add_child(axis_label)
				var input := _number(current_value[axis], float(property.options.get("step", 0.01)))
				input.name = str(property.id) + "_" + str(axis)
				row.add_child(input)
				var drag_state := {"origin": current_value}
				var make_value := func(number: float) -> Variant:
					var updated: Variant = ActorData.copy_value(_animated_object_value(actor, object, definition, property))
					updated[axis] = number
					if link.button_pressed:
						for component in component_count:
							updated[component] = number
					return updated
				input.interaction_started.connect(func(): drag_state.origin = ActorData.copy_value(_animated_object_value(actor, object, definition, property)))
				input.preview_changed.connect(func(number: float): model.preview_object_property(actor, object, definition, property.id, make_value.call(number)))
				input.drag_committed.connect(func(number: float): model.commit_object_property_preview(actor, object, definition, property.id, drag_state.origin, make_value.call(number)))
				input.drag_cancelled.connect(func(): model.preview_object_property(actor, object, definition, property.id, drag_state.origin))
				input.value_changed.connect(func(number: float): model.edit_object_property(actor, object, definition, property.id, make_value.call(number)))
				_updaters.append(func(): input.set_value_no_signal(_animated_object_value(actor, object, definition, property)[axis]))
		TYPE_STRING, TYPE_STRING_NAME:
			if property.options.get("file_picker", false):
				var row := HBoxContainer.new()
				parent.add_child(row)
				var set_path := func(resource: Variant):
					model.edit_object_property(actor, object, definition, property.id, resource)
					if property.options.get("refresh_inspector", false):
						_rebuild_selected()
				var workspace_parameters := Callable()
				if property.id == &"shader_path" and definition.find_property(&"uniforms") != null:
					var actor_id := actor.id
					var object_path := ActorAnimation.path_to_object(actor, object)
					workspace_parameters = func() -> Dictionary:
						return shader_workspace_parameter_binding(actor_id, object_path, actor)
				_add_file_resource_slot(row, property,
					func() -> Variant: return _animated_object_value(actor, object, definition, property), set_path,
					Callable(), workspace_parameters)
		TYPE_BOOL:
			var input := CheckButton.new()
			input.name = str(property.id)
			input.button_pressed = current_value
			parent.add_child(input)
			input.toggled.connect(func(value: bool): model.edit_object_property(actor, object, definition, property.id, value))
			_updaters.append(func(): input.set_pressed_no_signal(_animated_object_value(actor, object, definition, property)))
		TYPE_COLOR:
			var input := LiveColorPickerButton.new()
			input.name = str(property.id)
			input.color = current_value
			parent.add_child(input)
			input.interaction_started.connect(func():
				if hints != null:
					hints.begin(input, "Esc cancels color drag"))
			input.interaction_ended.connect(func():
				if hints != null:
					hints.end(input))
			input.preview_changed.connect(func(value: Color): model.preview_object_property(actor, object, definition, property.id, value))
			input.drag_committed.connect(func(original: Color, value: Color): model.commit_object_property_preview(actor, object, definition, property.id, original, value))
			input.drag_cancelled.connect(func(original: Color): model.preview_object_property(actor, object, definition, property.id, original))
			_updaters.append(func(): input.set_color_silent(_animated_object_value(actor, object, definition, property)))


func _add_shader_uniforms(actor: ActorData, object: ActorObjectData,
		definition: ActorObjectDefinition, parent: VBoxContainer) -> void:
	var shader_source: Variant = object.get_value(&"shader_path", "")
	if shader_source == null or (shader_source is String and shader_source.is_empty()):
		_add_label(parent, "Choose a .gdshader file to expose its uniforms.")
		return
	var shader := _shader_from_value(shader_source)
	if shader == null:
		_add_label(parent, "The selected shader could not be loaded.")
		return
	var stored: Dictionary = definition.value_for(object, definition.find_property(&"uniforms"))
	var shown := 0
	var object_path := ActorAnimation.path_to_object(actor, object)
	for entry: Dictionary in _shader_uniform_layout(shader, parent, actor.id, "ShaderUniforms:" + "/".join(object_path)):
		var info: Dictionary = entry.info
		var uniform_name := StringName(info.get("name", ""))
		if uniform_name.is_empty():
			continue
		var default_value: Variant = _shader_uniform_default(shader, uniform_name, int(info.get("type", TYPE_NIL)))
		var value: Variant = stored.get(uniform_name, default_value)
		_add_shader_uniform_value(actor, object, definition, entry.parent, uniform_name, value, default_value, info)
		shown += 1
	if shown == 0:
		_add_label(parent, "This shader has no editable uniforms.")


## Group markers are layout metadata, never shader parameters or animation paths.
func _shader_uniform_layout(shader: Shader, parent: VBoxContainer, state_id: String, scope: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var containers: Dictionary = {"": parent}
	var group := ""
	for info: Dictionary in shader.get_shader_uniform_list(true):
		if int(info.get("usage", 0)) & PROPERTY_USAGE_GROUP:
			group = str(info.get("name", ""))
			continue
		if str(info.get("name", "")).is_empty(): continue
		if not containers.has(group):
			var parts := group.split("::")
			var group_name := parts[0]
			if not containers.has(group_name):
				containers[group_name] = _stateful_category(group_name.capitalize(), state_id, parent, scope + ":" + group_name)
			if parts.size() > 1:
				containers[group] = _stateful_category(parts[1].capitalize(), state_id, containers[group_name], scope + ":" + group)
		result.append({"info": info, "parent": containers[group]})
	return result

func _shader_from_value(value: Variant) -> Shader:
	if value is Shader:
		return value
	var path := str(value)
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Shader if not path.is_empty() else null


func _shader_uniform_default(shader: Shader, uniform_name: StringName, value_type: int) -> Variant:
	if value_type == TYPE_OBJECT:
		return ""
	var value: Variant = RenderingServer.shader_get_parameter_default(shader.get_rid(), uniform_name)
	if value != null:
		return value
	match value_type:
		TYPE_FLOAT: return 0.0
		TYPE_INT: return 0
		TYPE_BOOL: return false
		TYPE_VECTOR2: return Vector2.ZERO
		TYPE_VECTOR3: return Vector3.ZERO
		TYPE_VECTOR4: return Vector4.ZERO
		TYPE_COLOR: return Color.WHITE
	return null


func _add_shader_uniform_value(actor: ActorData, object: ActorObjectData,
		definition: ActorObjectDefinition, parent: VBoxContainer, uniform_name: StringName,
		value: Variant, default_value: Variant, info: Dictionary) -> void:
	var value_type := int(info.get("type", typeof(default_value)))
	if value_type == TYPE_OBJECT:
		default_value = ""
	var heading := HBoxContainer.new()
	parent.add_child(heading)
	var label := Label.new()
	label.text = str(uniform_name).capitalize()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(label)
	var reset := Button.new()
	reset.name = str(uniform_name) + "_reset"
	reset.text = "↺"
	reset.visible = not _same_value(value, default_value)
	heading.add_child(reset)
	var uniform_property := ActorProperty.new()
	uniform_property.id = uniform_name
	uniform_property.label = label.text
	uniform_property.value_type = value_type
	uniform_property.options = {"default": default_value, "step": 0.01}
	var animation_path := ActorAnimation.path_to_object(actor, object)
	if not animation_path.is_empty():
		animation_path.append("uniforms")
		animation_path.append(str(uniform_name))
		_add_keyframe_button(heading, actor, uniform_property, animation_path, default_value)
	var hint_string := str(info.get("hint_string", ""))
	if int(info.get("hint", PROPERTY_HINT_NONE)) == PROPERTY_HINT_RANGE:
		var range_parts := hint_string.split(",")
		if range_parts.size() >= 2:
			uniform_property.options.min = float(range_parts[0])
			uniform_property.options.max = float(range_parts[1])
			if range_parts.size() >= 3 and range_parts[2].is_valid_float():
				uniform_property.options.step = float(range_parts[2])
	var uniforms_property := definition.find_property(&"uniforms")
	var current_uniforms := func() -> Dictionary:
		return (_animated_object_value(actor, object, definition, uniforms_property) as Dictionary).duplicate(true)
	_updaters.append(func():
		reset.visible = not _same_value(current_uniforms.call().get(uniform_name, default_value), default_value))
	var make_uniforms := func(updated: Variant) -> Dictionary:
		var values: Dictionary = current_uniforms.call()
		values[uniform_name] = ActorData.copy_value(updated)
		return values
	var commit := func(updated: Variant):
		model.edit_shader_uniform(actor, object, definition, uniform_name, updated)
		if value_type == TYPE_OBJECT:
			call_deferred("_rebuild_selected")
	reset.pressed.connect(func():
		commit.call(default_value)
		call_deferred("_rebuild_selected"))
	match uniform_property.value_type:
		TYPE_FLOAT, TYPE_INT:
			var input := _number_editor(parent, float(value), uniform_property)
			var normalize := func(number: float) -> Variant: return int(number) if uniform_property.value_type == TYPE_INT else number
			var drag_state := {"origin": current_uniforms.call()}
			input.interaction_started.connect(func(): drag_state.origin = current_uniforms.call())
			input.preview_changed.connect(func(number: float): model.edit_shader_uniform(actor, object, definition, uniform_name, normalize.call(number), "preview"))
			input.drag_committed.connect(func(number: float): model.edit_shader_uniform(actor, object, definition, uniform_name, normalize.call(number), "commit", drag_state.origin))
			input.drag_cancelled.connect(func(): model.edit_shader_uniform(actor, object, definition, uniform_name, drag_state.origin.get(uniform_name, default_value), "preview"))
			input.value_changed.connect(func(number: float): commit.call(normalize.call(number)))
			_updaters.append(func():
				_set_number_silent(input, float(current_uniforms.call().get(uniform_name, default_value))))
		TYPE_BOOL:
			var input := CheckButton.new()
			input.name = str(uniform_name) + "_value"
			input.button_pressed = bool(value)
			input.toggled.connect(commit)
			parent.add_child(input)
			_updaters.append(func():
				input.set_pressed_no_signal(bool(current_uniforms.call().get(uniform_name, default_value))))
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I:
			var component_count := 2 if uniform_property.value_type in [TYPE_VECTOR2, TYPE_VECTOR2I] else (3 if uniform_property.value_type in [TYPE_VECTOR3, TYPE_VECTOR3I] else 4)
			var integer_components := uniform_property.value_type in [TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I]
			for axis in component_count:
				var row := HBoxContainer.new()
				parent.add_child(row)
				var axis_label := Label.new()
				axis_label.text = ["X", "Y", "Z", "W"][axis]
				row.add_child(axis_label)
				var input := _number(value[axis], 0.01)
				input.name = str(uniform_name) + "_" + str(axis)
				var make_vector := func(number: float) -> Variant:
					var existing: Dictionary = current_uniforms.call()
					var updated: Variant = ActorData.copy_value(existing.get(uniform_name, value))
					updated[axis] = int(number) if integer_components else number
					return updated
				var drag_state := {"origin": current_uniforms.call()}
				input.interaction_started.connect(func(): drag_state.origin = current_uniforms.call())
				input.preview_changed.connect(func(number: float):
					model.edit_shader_uniform(actor, object, definition, uniform_name, make_vector.call(number), "preview"))
				input.drag_committed.connect(func(number: float):
					model.edit_shader_uniform(actor, object, definition, uniform_name, make_vector.call(number), "commit", drag_state.origin))
				input.drag_cancelled.connect(func(): model.edit_shader_uniform(actor, object, definition, uniform_name, drag_state.origin.get(uniform_name, default_value), "preview"))
				input.value_changed.connect(func(number: float): commit.call(make_vector.call(number)))
				_updaters.append(func():
					var uniforms: Dictionary = current_uniforms.call()
					input.set_value_no_signal(uniforms.get(uniform_name, default_value)[axis]))
				row.add_child(input)
		TYPE_COLOR:
			var input := LiveColorPickerButton.new()
			input.name = str(uniform_name) + "_value"
			input.color = value
			input.preview_changed.connect(func(updated: Color): model.edit_shader_uniform(actor, object, definition, uniform_name, updated, "preview"))
			input.drag_committed.connect(func(_original: Color, updated: Color): commit.call(updated))
			parent.add_child(input)
			_updaters.append(func():
				input.set_color_silent(current_uniforms.call().get(uniform_name, default_value)))
		TYPE_OBJECT:
			var texture_property := ActorProperty.new()
			texture_property.id = uniform_name
			texture_property.label = label.text
			texture_property.object_type = &"image"
			texture_property.options = _shader_texture_options()
			_add_shader_texture_uniform(parent, texture_property,
				func() -> Variant: return current_uniforms.call().get(uniform_name, ""), commit, actor)
		_:
			var input := LineEdit.new()
			input.name = str(uniform_name) + "_value"
			input.text = var_to_str(value)
			input.tooltip_text = "Edit this value using Godot Variant syntax, then press Enter."
			input.text_submitted.connect(func(text: String):
				var parsed: Variant = str_to_var(text)
				if typeof(parsed) == uniform_property.value_type:
					commit.call(parsed))
			parent.add_child(input)
			_updaters.append(func():
				input.text = var_to_str(current_uniforms.call().get(uniform_name, default_value)))
