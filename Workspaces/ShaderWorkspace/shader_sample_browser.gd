extends HSplitContainer
## Shared Samples/Templates page embedded alongside the existing documentation.
## Two viewports total: the selected live material and a serial thumbnail worker.
signal open_requested(entry: Dictionary)
const Catalog = preload("res://Workspaces/ShaderWorkspace/library/shader_sample_catalog.gd")
const Preview = preload("res://Workspaces/ShaderWorkspace/shader_sample_preview.gd")
const Application = preload("res://Workspaces/ShaderWorkspace/shader_sample_application.gd")
const PREFS := "user://shader_library.cfg"
const CACHE := "user://shader_library_previews/"
const CACHE_VERSION := "6"
var templates_only := false
var preferences_path := PREFS
var entries: Array[Dictionary] = []
var favorites := PackedStringArray()
var recent := PackedStringArray()
var selected: Dictionary = {}
var search := LineEdit.new()
var type_filter := OptionButton.new()
var category_filter := OptionButton.new()
var collection_filter := OptionButton.new()
var grid := GridContainer.new()
var card_scroll := ScrollContainer.new()
var count := Label.new()
var heading := Label.new()
var description := Label.new()
var source := CodeEdit.new()
var preview_display := TextureRect.new()
var preview_error := Label.new()
var uniforms := VBoxContainer.new()
var geometry := OptionButton.new()
var favorite: Button
var apply: Button
var status := Label.new()
var live: SubViewport
var thumbnail: SubViewport
var _cards: Dictionary = {}
var _textures: Dictionary = {}
var _failures: Dictionary = {}
var _thumbnail_busy := false
var _selection_revision := 0
var _selection_busy := false
var _apply_timer := 0.0

func _ready() -> void:
	name = "ShaderTemplates" if templates_only else "ShaderSamples"
	var browser_theme := Theme.new()
	browser_theme.default_font_size = 13
	browser_theme.set_color("font_color", "Label", Color("d7e4ec"))
	browser_theme.set_stylebox("normal", "Button", _box(Color("182936"), Color("304958")))
	browser_theme.set_stylebox("hover", "Button", _box(Color("223d46"), Color("67cbb4")))
	browser_theme.set_stylebox("pressed", "Button", _box(Color("254b48"), Color("7be0c6")))
	theme = browser_theme
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_offset = 195
	entries = Catalog.get_entries()
	_load_preferences()
	_build_sidebar()
	_build_content()
	live = Preview.new()
	live.name = "LibraryLivePreview"
	add_child(live)
	live.size = Vector2i(640, 384)
	thumbnail = Preview.new()
	thumbnail.name = "LibraryThumbnailWorker"
	add_child(thumbnail)
	thumbnail.size = Vector2i(256, 160)
	preview_display.texture = live.get_texture()
	visibility_changed.connect(_visibility_changed)
	refresh()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("101923"))

func _box(background: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(7)
	return style

func _build_sidebar() -> void:
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 155
	side.add_theme_constant_override("separation", 9)
	add_child(side)
	search.placeholder_text = "Search shaders..."
	search.clear_button_enabled = true
	search.text_changed.connect(func(_text: String): refresh())
	side.add_child(search)
	for label in ["All shader types", "2D", "3D", "Sky", "Fog", "Particles"]:
		type_filter.add_item(label)
	type_filter.item_selected.connect(func(_index: int): refresh())
	side.add_child(type_filter)
	category_filter.add_item("All categories")
	var categories := PackedStringArray()
	for entry in entries:
		if bool(entry.get("template", false)) == templates_only and not categories.has(str(entry.category)):
			categories.append(str(entry.category))
	categories.sort()
	for category in categories: category_filter.add_item(category)
	category_filter.item_selected.connect(func(_index: int): refresh())
	side.add_child(category_filter)
	for label in ["All", "Favorites", "Recently used"]:
		collection_filter.add_item(label)
	collection_filter.item_selected.connect(func(_index: int): refresh())
	side.add_child(collection_filter)
	count.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(count)
	var help := Label.new()
	help.text = "Actual shader renders\n\nDrag the large preview to orbit. Use the wheel to zoom. Uniform changes are temporary."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_color_override("font_color", Color("91a6b5"))
	side.add_child(help)

func _build_content() -> void:
	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.split_offset = 440
	add_child(split)
	card_scroll.custom_minimum_size.x = 180
	card_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(card_scroll)
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	card_scroll.add_child(grid)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size.x = 300
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(detail_scroll)
	var detail := VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(detail)
	heading.add_theme_font_size_override("font_size", 20)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(heading)
	preview_display.custom_minimum_size.y = 185
	preview_display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview_display.gui_input.connect(_preview_input)
	detail.add_child(preview_display)
	preview_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_error.add_theme_color_override("font_color", Color("ff9b8e"))
	preview_error.hide()
	detail.add_child(preview_error)
	var tools := HBoxContainer.new()
	detail.add_child(tools)
	for label in ["Sphere", "Plane", "Cube"]: geometry.add_item(label)
	geometry.item_selected.connect(func(index: int): live.set_geometry(["sphere", "plane", "cube"][index]))
	tools.add_child(geometry)
	var reset := _button("Reset preview", func(): _select(selected))
	tools.add_child(reset)
	favorite = _button("Favorite", _toggle_favorite)
	favorite.toggle_mode = true
	tools.add_child(favorite)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 12)
	detail.add_child(description)
	var uniform_scroll := ScrollContainer.new()
	uniform_scroll.custom_minimum_size.y = 95
	uniform_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail.add_child(uniform_scroll)
	uniforms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uniform_scroll.add_child(uniforms)
	source.editable = false
	source.gutters_draw_line_numbers = true
	source.size_flags_vertical = Control.SIZE_EXPAND_FILL
	source.custom_minimum_size.y = 110
	source.add_theme_font_size_override("font_size", 12)
	var highlighter := CodeHighlighter.new()
	highlighter.number_color = Color("b5cea8")
	highlighter.function_color = Color("dcdcaa")
	for keyword in ["shader_type", "render_mode", "uniform", "varying", "group_uniforms", "if", "else", "for", "return", "discard"]:
		highlighter.add_keyword_color(keyword, Color("c792ea"))
	for type_name in ["float", "int", "bool", "vec2", "vec3", "vec4", "mat3", "mat4", "void", "sampler2D"]:
		highlighter.add_keyword_color(type_name, Color("62d6ca"))
	highlighter.add_color_region("//", "", Color("6a9955"), true)
	highlighter.add_color_region("/*", "*/", Color("6a9955"), false)
	source.syntax_highlighter = highlighter
	detail.add_child(source)
	var actions := HFlowContainer.new()
	detail.add_child(actions)
	actions.add_child(_button("Copy Code", _copy))
	actions.add_child(_button("Open in Editor", _open))
	actions.add_child(_button("Create Shader File", _save_file))
	apply = _button("Apply to Selected Actor", _apply)
	actions.add_child(apply)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 12)
	detail.add_child(status)

static func matches(entry: Dictionary, query: String, kind: String, category: String,
		templates: bool, collection: int, favorite_ids: PackedStringArray, recent_ids: PackedStringArray) -> bool:
	if bool(entry.get("template", false)) != templates: return false
	if not kind.is_empty() and str(entry.get("shader_type", "")) != kind: return false
	if not category.is_empty() and str(entry.get("category", "")) != category: return false
	if collection == 1 and not favorite_ids.has(str(entry.id)): return false
	if collection == 2 and not recent_ids.has(str(entry.id)): return false
	var haystack := (str(entry.get("name", "")) + " " + str(entry.get("description", "")) + " " + str(entry.get("category", "")) + " " + " ".join(entry.get("tags", []))).to_lower()
	for word in query.to_lower().split(" ", false):
		if not haystack.contains(word): return false
	return true

func refresh() -> void:
	if not is_node_ready(): return
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	_cards.clear()
	var kinds := ["", "canvas_item", "spatial", "sky", "fog", "particles"]
	var category := "" if category_filter.selected == 0 else category_filter.get_item_text(category_filter.selected)
	var filtered: Array[Dictionary] = []
	for entry in entries:
		if matches(entry, search.text, kinds[type_filter.selected], category, templates_only,
				collection_filter.selected, favorites, recent): filtered.append(entry)
	if collection_filter.selected == 2:
		filtered.sort_custom(func(a: Dictionary, b: Dictionary): return recent.find(str(a.id)) < recent.find(str(b.id)))
	for entry in filtered: _add_card(entry)
	count.text = "%d %s" % [filtered.size(), "templates" if templates_only else "samples"]
	if selected.is_empty() and not filtered.is_empty(): _select(filtered[0])
	elif filtered.is_empty(): status.text = "No matches. Try another category or search."

func _add_card(entry: Dictionary) -> void:
	var card := Button.new()
	card.custom_minimum_size = Vector2(162, 176)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.tooltip_text = str(entry.description)
	card.toggle_mode = true
	card.set_pressed_no_signal(str(selected.get("id", "")) == str(entry.id))
	card.pressed.connect(_select.bind(entry))
	grid.add_child(card)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 7)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var image := TextureRect.new()
	image.custom_minimum_size.y = 99
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(image)
	var label := Label.new()
	label.text = str(entry.name)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)
	var caption := Label.new()
	caption.text = str(entry.shader_type).replace("canvas_item", "2D").replace("spatial", "3D") + " | " + str(entry.description)
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.add_theme_font_size_override("font_size", 11)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(caption)
	var message := Label.new()
	message.text = "Preview queued"
	message.add_theme_font_size_override("font_size", 10)
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(message)
	_cards[str(entry.id)] = {"entry": entry, "card": card, "image": image, "message": message}
	var key := _cache_key(entry)
	if _textures.has(key):
		image.texture = _textures[key]
		message.text = "Rendered preview"
	elif _failures.has(key): message.text = _failures[key]
	elif FileAccess.file_exists(CACHE + key + ".png"):
		var cached := Image.load_from_file(CACHE + key + ".png")
		if cached != null and not cached.is_empty():
			image.texture = ImageTexture.create_from_image(cached)
			_textures[key] = image.texture
			message.text = "Rendered preview"

func set_templates(value: bool) -> void:
	templates_only = value
	selected = {}
	if not is_node_ready(): return
	_load_preferences()
	category_filter.clear()
	category_filter.add_item("All categories")
	var categories := PackedStringArray()
	for entry in entries:
		if bool(entry.get("template", false)) == templates_only and not categories.has(str(entry.category)):
			categories.append(str(entry.category))
	categories.sort()
	for category in categories: category_filter.add_item(category)
	refresh()

func _select(entry: Dictionary) -> void:
	if entry.is_empty(): return
	selected = entry.duplicate(true)
	for id in _cards:
		_cards[id].card.set_pressed_no_signal(str(id) == str(entry.id))
	selected.source = Catalog.get_code(entry)
	_selection_revision += 1
	var revision := _selection_revision
	_selection_busy = true
	heading.text = str(entry.name)
	description.text = str(entry.description) + "\nSupports: " + str(entry.get("targets", entry.shader_type))
	source.text = selected.source
	favorite.set_pressed_no_signal(favorites.has(str(entry.id)))
	geometry.visible = str(entry.shader_type) == "spatial"
	geometry.select(maxi(0, ["sphere", "plane", "cube"].find(str(entry.get("preview_mesh", "sphere")))))
	preview_error.hide()
	preview_display.show()
	status.text = ""
	# Serialize shader compilation against thumbnail work so diagnostic ownership
	# remains unambiguous even when rendering uses a background thread.
	while _thumbnail_busy:
		await get_tree().process_frame
		if revision != _selection_revision: return
	var error: String = live.show_entry(selected)
	live.set_active(is_visible_in_tree() and error.is_empty())
	for _frame in 3: await get_tree().process_frame
	if revision != _selection_revision: return
	error = live.check_errors()
	if not error.is_empty():
		preview_error.text = error
		preview_error.show()
		preview_display.hide()
	_build_uniforms()
	_refresh_apply()
	live.finish_compilation()
	_selection_busy = false

func _build_uniforms() -> void:
	for child in uniforms.get_children():
		uniforms.remove_child(child)
		child.queue_free()
	if not live.error_text.is_empty(): return
	for info in live.shader.get_shader_uniform_list():
		var value_type := int(info.get("type", TYPE_NIL))
		if value_type not in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_COLOR, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4]: continue
		var uniform_name := StringName(info.name)
		var row := HBoxContainer.new()
		uniforms.add_child(row)
		var label := Label.new()
		label.text = str(uniform_name).capitalize()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var initial: Variant = RenderingServer.shader_get_parameter_default(live.shader.get_rid(), uniform_name)
		if value_type == TYPE_BOOL:
			var check := CheckButton.new()
			check.set_pressed_no_signal(bool(initial))
			check.toggled.connect(func(value: bool): live.material.set_shader_parameter(uniform_name, value))
			row.add_child(check)
		elif value_type == TYPE_COLOR:
			var color := ColorPickerButton.new()
			color.custom_minimum_size = Vector2(70, 25)
			color.color = initial if initial is Color else Color.WHITE
			color.color_changed.connect(func(value: Color): live.material.set_shader_parameter(uniform_name, value))
			row.add_child(color)
		elif value_type in [TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4]:
			var vector_value: Variant = initial
			var components := 2 if value_type == TYPE_VECTOR2 else (3 if value_type == TYPE_VECTOR3 else 4)
			for axis in components:
				var component := SpinBox.new()
				component.min_value = -100
				component.max_value = 100
				component.step = 0.05
				component.value = vector_value[axis] if vector_value != null else 0
				component.custom_minimum_size.x = 56
				component.value_changed.connect(func(value: float):
					var vector: Variant = live.material.get_shader_parameter(uniform_name)
					if vector == null: vector = initial
					vector[axis] = value
					live.material.set_shader_parameter(uniform_name, vector))
				row.add_child(component)
		else:
			var number := SpinBox.new()
			var range_parts := str(info.get("hint_string", "")).split(",")
			number.min_value = float(range_parts[0]) if int(info.get("hint", 0)) == PROPERTY_HINT_RANGE and range_parts.size() >= 2 else -100.0
			number.max_value = float(range_parts[1]) if int(info.get("hint", 0)) == PROPERTY_HINT_RANGE and range_parts.size() >= 2 else 100.0
			number.step = 1.0 if value_type == TYPE_INT else 0.01
			number.value = float(initial) if initial != null else 0.0
			number.value_changed.connect(func(value: float): live.material.set_shader_parameter(uniform_name, int(value) if value_type == TYPE_INT else value))
			row.add_child(number)

func _process(delta: float) -> void:
	if not is_node_ready() or not is_visible_in_tree(): return
	grid.columns = maxi(1, int(card_scroll.size.x / 181.0))
	_apply_timer += delta
	if _apply_timer > 0.7:
		_apply_timer = 0.0
		_refresh_apply()
	if _thumbnail_busy or _selection_busy: return
	for card_info: Dictionary in _cards.values():
		var card: Button = card_info.card
		if card_info.image.texture != null or _failures.has(_cache_key(card_info.entry)): continue
		if card.get_global_rect().intersects(card_scroll.get_global_rect()):
			_render_thumbnail(card_info.entry)
			break

func _render_thumbnail(entry: Dictionary) -> void:
	_thumbnail_busy = true
	var key := _cache_key(entry)
	var render_entry := entry.duplicate()
	render_entry.source = Catalog.get_code(entry)
	var error: String = thumbnail.show_entry(render_entry)
	if error.is_empty():
		for _frame in 4: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		error = thumbnail.check_errors()
		if error.is_empty():
			var result := thumbnail.get_texture().get_image()
			if result != null and not result.is_empty():
				_textures[key] = ImageTexture.create_from_image(result)
				DirAccess.make_dir_recursive_absolute(CACHE)
				result.save_png(CACHE + key + ".png")
			else: error = "Renderer returned no image."
	thumbnail.set_active(false)
	if not error.is_empty(): _failures[key] = error
	if _cards.has(str(entry.id)):
		var card: Dictionary = _cards[str(entry.id)]
		if _textures.has(key): card.image.texture = _textures[key]
		card.message.text = "Rendered preview" if error.is_empty() else "Preview unavailable"
		card.card.tooltip_text = str(entry.description) if error.is_empty() else error
	_thumbnail_busy = false

func _cache_key(entry: Dictionary) -> String:
	return (CACHE_VERSION + str(entry.id) + Catalog.get_code(entry) + str(entry.get("preview_mesh", "")) + RenderingServer.get_current_rendering_method()).sha256_text()

func _visibility_changed() -> void:
	if live != null: live.set_active(is_visible_in_tree() and not selected.is_empty() and live.error_text.is_empty())
	if thumbnail != null and not is_visible_in_tree(): thumbnail.set_active(false)

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		live.orbit(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: live.zoom(0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: live.zoom(1.1)

func _copy() -> void:
	if selected.is_empty(): return
	DisplayServer.clipboard_set(str(selected.source))
	_mark_used()
	status.text = "Complete shader copied."

func _open() -> void:
	if selected.is_empty(): return
	_mark_used()
	open_requested.emit(selected.duplicate(true))

func _save_file() -> void:
	if selected.is_empty(): return
	var entry := selected.duplicate(true)
	var result := await ActorProjectResourceSaveDialog.pick(self, "Create shader copy", str(entry.id), "gdshader", false)
	if result.get("cancelled", true): return
	var path := str(result.get("path", ""))
	if path.is_empty(): return
	var error := write_shader_copy(path, str(entry.source))
	if error != OK:
		status.text = "Could not create shader file: " + error_string(error)
		return
	_mark_used()
	status.text = "Created " + path

static func write_shader_copy(path: String, code: String) -> Error:
	if path.get_extension().to_lower() != "gdshader": return ERR_INVALID_PARAMETER
	if ProjectSettings.localize_path(path).begins_with("res://Workspaces/ShaderWorkspace/library/"):
		return ERR_UNAUTHORIZED
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(code)
	file.flush()
	var error := file.get_error()
	file.close()
	return error

func _refresh_apply() -> void:
	if selected.is_empty():
		apply.disabled = true
		return
	var target := Application.target_for(get_tree(), str(selected.shader_type))
	apply.disabled = not target.has("actor") or not live.error_text.is_empty()
	apply.tooltip_text = "Apply a new material copy to " + str(target.label) if target.has("actor") else str(target.get("reason", ""))

func _apply() -> void:
	var entry := selected.duplicate(true)
	var target := Application.target_for(get_tree(), str(entry.shader_type))
	if not target.has("actor"):
		status.text = str(target.get("reason", "No target selected."))
		return
	if bool(target.get("existing", false)):
		var confirmation := ConfirmationDialog.new()
		confirmation.title = "Replace selected material?"
		confirmation.dialog_text = "Apply %s to %s?\nThe current slot will be replaced with a separate copy. Undo restores the previous material." % [entry.name, target.label]
		confirmation.confirmed.connect(func(): _commit_apply(target, entry); confirmation.queue_free())
		confirmation.canceled.connect(confirmation.queue_free)
		add_child(confirmation)
		confirmation.popup_centered()
	else: _commit_apply(target, entry)

func _commit_apply(target: Dictionary, entry: Dictionary) -> void:
	var error := Application.apply_to_target(target, str(entry.source), str(entry.name))
	status.text = error if not error.is_empty() else "Applied to " + str(target.label) + ". Undo is available in the scene."
	if error.is_empty(): _mark_used()

func _toggle_favorite() -> void:
	if selected.is_empty(): return
	_load_preferences()
	var id := str(selected.id)
	if favorites.has(id): favorites.remove_at(favorites.find(id))
	else: favorites.append(id)
	favorite.set_pressed_no_signal(favorites.has(id))
	_save_preferences()
	if collection_filter.selected == 1: refresh()

func _mark_used() -> void:
	_load_preferences()
	var id := str(selected.id)
	if recent.has(id): recent.remove_at(recent.find(id))
	recent.insert(0, id)
	if recent.size() > 32: recent.resize(32)
	_save_preferences()

func _load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(preferences_path) == OK:
		favorites = PackedStringArray(config.get_value("library", "favorites", []))
		recent = PackedStringArray(config.get_value("library", "recent", []))

func _save_preferences() -> void:
	# Merge with the sibling Samples/Templates page, which shares this file.
	var config := ConfigFile.new()
	config.load(preferences_path)
	config.set_value("library", "favorites", favorites)
	config.set_value("library", "recent", recent)
	config.save(preferences_path)

func _button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	return button
