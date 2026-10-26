extends VBoxContainer
## Small scene adapter for the shared material browser. Edits remain local to
## this ActorObjectData; saving a reusable preset is an explicit browser action.

const NaturalEngine = preload("res://scripts/materials/natural_material_engine.gd")
const Render = preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd")

var _reader: Callable
var _writer: Callable
var _settings: Dictionary = {}
var _original: Dictionary = {}
var _pending := false
var _syncing := false
var _browser: Control
var _swatch := ColorRect.new()
var _title := Label.new()
var _mapping := OptionButton.new()
var _relief := SpinBox.new()
var _metallic := SpinBox.new()
var _automatic_metallic := CheckButton.new()
var _commit_timer := Timer.new()


func setup(reader: Callable, writer: Callable, edit_context: String = "local") -> void:
	_reader = reader
	_writer = writer
	name = "NaturalMaterialEditor"
	add_theme_constant_override("separation", 6)
	_swatch.name = "NaturalMaterialPreview"
	_swatch.custom_minimum_size = Vector2(160, 90)
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_swatch)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_title)
	var browse := Button.new()
	browse.name = "natural_material_browse"
	browse.text = "Browse & edit material…"
	browse.tooltip_text = "Uses the same materials and saved presets as Brush and Bucket. Changes appear immediately on this surface."
	browse.pressed.connect(_open_browser)
	add_child(browse)
	var explanation := Label.new()
	explanation.name = "NaturalMaterialOwnership"
	explanation.text = "Local instance • save shared presets in the browser"
	if edit_context == "linked":
		explanation.text = "Linked resource • edits update this file. Use Make Unique in the material slot for a local copy."
	elif edit_context == "saved":
		explanation.text = "Saved resource • edits update actors that use this file."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.modulate = Color("819db4")
	add_child(explanation)
	var advanced := VBoxContainer.new()
	advanced.visible = false
	var toggle := CheckButton.new()
	toggle.text = "3D surface settings"
	toggle.toggled.connect(func(value: bool): advanced.visible = value)
	add_child(toggle)
	add_child(advanced)
	_mapping.name = "natural_material_mapping"
	_mapping.add_item("UV mapping")
	_mapping.add_item("Triplanar mapping")
	advanced.add_child(_mapping)
	_mapping.item_selected.connect(func(index: int): _change("mapping", "triplanar" if index == 1 else "uv"))
	_number(advanced, "Relief strength", _relief, 0.0, 2.0, 0.01)
	_relief.name = "natural_material_relief"
	_relief.value_changed.connect(func(value: float): _change("relief", value))
	_automatic_metallic.text = "Use material's metallic response"
	_automatic_metallic.toggled.connect(func(value: bool):
		_change("metallic", -1.0 if value else _metallic.value))
	advanced.add_child(_automatic_metallic)
	_number(advanced, "Metallic response", _metallic, 0.0, 1.0, 0.01)
	_metallic.name = "natural_material_metallic"
	_metallic.value_changed.connect(func(value: float): _change("metallic", value))
	_commit_timer.one_shot = true
	_commit_timer.wait_time = 0.3
	_commit_timer.timeout.connect(_finish_edit)
	add_child(_commit_timer)
	sync_from_source()


func _number(parent: VBoxContainer, title: String, input: SpinBox, minimum: float, maximum: float, step: float) -> void:
	var label := Label.new()
	label.text = title
	parent.add_child(label)
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(input)


func sync_from_source() -> void:
	if not _reader.is_valid():
		return
	var settings := NaturalEngine.normalize(_reader.call())
	if settings == _settings:
		return
	# An external undo or scene update wins over a debounced local preview.
	if _pending:
		_commit_timer.stop()
		_pending = false
	_settings = settings
	_update_controls()
	if is_instance_valid(_browser) and not bool(_browser.call("is_closed")):
		_browser.call("set_material_value", NaturalEngine.material_from_settings(_settings))


func _update_controls() -> void:
	_syncing = true
	var material := NaturalEngine.material_from_settings(_settings)
	_swatch.material = Render.material(material, Vector2(160, 90))
	_title.text = str(_settings.get("label", material.material_id))
	_mapping.select(1 if _settings.get("mapping", "uv") == "triplanar" else 0)
	_relief.set_value_no_signal(float(_settings.get("relief", 0.0)))
	var metallic := float(_settings.get("metallic", -1.0))
	_automatic_metallic.set_pressed_no_signal(metallic < 0.0)
	_metallic.editable = metallic >= 0.0
	_metallic.set_value_no_signal(maxf(0.0, metallic))
	_syncing = false


func _change(key: String, value: Variant) -> void:
	if _syncing:
		return
	var updated := _settings.duplicate(true)
	updated[key] = value
	_edit(updated)


func _edit(settings: Dictionary) -> void:
	if not _writer.is_valid():
		return
	if not _pending:
		_original = (_reader.call() as Dictionary).duplicate(true)
		_pending = true
	_settings = NaturalEngine.normalize(settings)
	_writer.call(_settings.duplicate(true), "preview", _original)
	_update_controls()
	_commit_timer.start()


func _finish_edit() -> void:
	if not _pending:
		return
	_pending = false
	if _writer.is_valid():
		_writer.call(_settings.duplicate(true), "commit", _original)


func _input(event: InputEvent) -> void:
	# Finish the preview before the workspace handles its ordinary Undo shortcut.
	if _pending and event is InputEventKey and event.pressed and not event.echo \
			and (event.ctrl_pressed or event.meta_pressed) and event.keycode in [KEY_Z, KEY_Y]:
		_finish_edit()


func _open_browser() -> void:
	_finish_edit()
	if is_instance_valid(_browser) and not _browser.is_queued_for_deletion() and not bool(_browser.call("is_closed")):
		_browser.show()
		return
	var host: Node = self
	var ancestor := get_parent()
	while ancestor != null and not ancestor is Window:
		if ancestor is Control:
			host = ancestor
			# Keep the dock within the scene tab's visibility and layout lifetime.
			if ancestor.name == &"SceneWorkspace":
				break
		ancestor = ancestor.get_parent()
	var browser_script = load("res://Workspaces/ImageWorkspace/texture_material_browser.gd")
	_browser = browser_script.open_for_material(host, NaturalEngine.material_from_settings(_settings),
		func(value: KiwiTextureMaterial): _edit(NaturalEngine.settings_from_material(value)))
	_browser.connect("edit_committed", _finish_edit)


func _exit_tree() -> void:
	_finish_edit()
	if is_instance_valid(_browser) and not _browser.is_queued_for_deletion():
		_browser.call("close")
