class_name KiwiImageWorkspace
extends Control
## A project image editor. Edits stay in memory until Save/Save As.

signal document_changed
signal image_saved(source: Variant)

const IMAGE_EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp", "tga", "hdr", "exr"]
const SAVE_FORMATS := ["png", "jpg", "webp"]

var image: Image
var source: Variant
var path := ""
var canvas := TextureRect.new()
var canvas_frame := CenterContainer.new()
var scroll := ScrollContainer.new()
var color_picker := ColorPickerButton.new()
var brush_size := SpinBox.new()
var zoom_label := Label.new()
var size_label := Label.new()
var status := Label.new()
var tool_label := Label.new()
var tool := "brush"
var zoom := 1.0
var _painting := false
var _drag_start := Vector2i.ZERO
var _drag_end := Vector2i.ZERO
var _before_stroke: Image
var _undo: Array[Image] = []
var _redo: Array[Image] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	if image == null: open_source(null)


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("0c141d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 7)
	root.add_child(toolbar)
	var heading := Label.new()
	heading.text = "▣  IMAGE EDITOR"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_color_override("font_color", Color("75e2ce"))
	toolbar.add_child(heading)
	_add_button(toolbar, "Load…", _choose_image, "Open an image from the project")
	_add_button(toolbar, "Save", save, "Save to the current file · Ctrl+S")
	_add_button(toolbar, "Save As…", save_as, "Save a new PNG, JPEG, or WebP · Ctrl+Shift+S")
	_add_button(toolbar, "Undo", undo, "Undo image edit · Ctrl+Z")
	_add_button(toolbar, "Redo", redo, "Redo image edit · Ctrl+Y")
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	root.add_child(body)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 166
	sidebar.add_theme_constant_override("separation", 6)
	body.add_child(sidebar)
	var tools_title := Label.new()
	tools_title.text = "TOOLS"
	tools_title.add_theme_color_override("font_color", Color("93abbc"))
	sidebar.add_child(tools_title)
	for entry in [
		["Brush", "brush"], ["Eraser", "eraser"], ["Fill", "fill"],
		["Pick color", "picker"], ["Crop rectangle", "crop"]]:
		var button := _add_button(sidebar, entry[0], func(): _set_tool(entry[1]))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tool_label.text = "Brush"
	tool_label.add_theme_color_override("font_color", Color("75e2ce"))
	sidebar.add_child(tool_label)
	var color_caption := Label.new()
	color_caption.text = "COLOR"
	sidebar.add_child(color_caption)
	color_picker.color = Color.WHITE
	color_picker.custom_minimum_size.y = 32
	sidebar.add_child(color_picker)
	var size_caption := Label.new()
	size_caption.text = "BRUSH SIZE"
	sidebar.add_child(size_caption)
	brush_size.min_value = 1
	brush_size.max_value = 128
	brush_size.value = 12
	brush_size.rounded = true
	sidebar.add_child(brush_size)
	var operations := Label.new()
	operations.text = "TRANSFORM"
	operations.add_theme_color_override("font_color", Color("93abbc"))
	sidebar.add_child(operations)
	_add_button(sidebar, "Resize…", _resize_dialog)
	_add_button(sidebar, "Rotate 90°", func(): _change_image(func(): image.rotate_90(CLOCKWISE)))
	_add_button(sidebar, "Flip horizontal", func(): _change_image(func(): image.flip_x()))
	_add_button(sidebar, "Flip vertical", func(): _change_image(func(): image.flip_y()))
	_add_button(sidebar, "Grayscale", func(): _change_image(func(): image.convert(Image.FORMAT_RGBA8); _map_pixels(func(c: Color): return Color(c.get_luminance(), c.get_luminance(), c.get_luminance(), c.a))))
	_add_button(sidebar, "Invert RGB", func(): _change_image(func(): _map_pixels(func(c: Color): return Color(1.0 - c.r, 1.0 - c.g, 1.0 - c.b, c.a))))
	_add_button(sidebar, "Brightness…", func(): _adjust_dialog("Brightness", -1.0, 1.0, 0.0,
		func(c: Color, amount: float): return Color(clampf(c.r + amount, 0.0, 1.0), clampf(c.g + amount, 0.0, 1.0), clampf(c.b + amount, 0.0, 1.0), c.a)))
	_add_button(sidebar, "Contrast…", func(): _adjust_dialog("Contrast", 0.0, 3.0, 1.0,
		func(c: Color, amount: float): return Color(clampf((c.r - 0.5) * amount + 0.5, 0.0, 1.0), clampf((c.g - 0.5) * amount + 0.5, 0.0, 1.0), clampf((c.b - 0.5) * amount + 0.5, 0.0, 1.0), c.a)))
	_add_button(sidebar, "Saturation…", func(): _adjust_dialog("Saturation", 0.0, 3.0, 1.0,
		func(c: Color, amount: float): return Color(clampf(lerpf(c.get_luminance(), c.r, amount), 0.0, 1.0), clampf(lerpf(c.get_luminance(), c.g, amount), 0.0, 1.0), clampf(lerpf(c.get_luminance(), c.b, amount), 0.0, 1.0), c.a)))
	_add_button(sidebar, "Clear canvas", func(): _change_image(func(): image.fill(Color.TRANSPARENT)))
	var stage := VBoxContainer.new()
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(stage)
	var stage_tools := HBoxContainer.new()
	stage.add_child(stage_tools)
	_add_button(stage_tools, "−", func(): _set_zoom(zoom / 1.25))
	zoom_label.custom_minimum_size.x = 60
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stage_tools.add_child(zoom_label)
	_add_button(stage_tools, "+", func(): _set_zoom(zoom * 1.25))
	_add_button(stage_tools, "Fit", _fit_zoom)
	size_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stage_tools.add_child(size_label)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	stage.add_child(scroll)
	canvas_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(canvas_frame)
	canvas.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	canvas.stretch_mode = TextureRect.STRETCH_SCALE
	canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.gui_input.connect(_canvas_input)
	canvas.draw.connect(_draw_canvas_overlay)
	canvas_frame.add_child(canvas)
	status.text = "Brush, erase, fill, pick colors, or drag a crop rectangle. Changes are saved only when you choose Save."
	status.add_theme_color_override("font_color", Color("9bb5c4"))
	stage.add_child(status)


func _add_button(parent: Node, caption: String, action: Callable, tip: String = "") -> Button:
	var button := Button.new()
	button.text = caption
	button.tooltip_text = tip
	button.custom_minimum_size.y = 31
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func open_source(value: Variant, state: Dictionary = {}) -> void:
	source = value
	path = str(value) if value is String else ""
	if state.get("image") is Image:
		image = (state.image as Image).duplicate()
	elif value is Texture2D:
		image = value.get_image()
	elif value is Image:
		image = value.duplicate()
	elif value is String and not value.is_empty():
		image = Image.load_from_file(_disk_path(path))
		if image == null or image.is_empty():
			var imported := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Texture2D
			if imported != null: image = imported.get_image()
	else:
		image = Image.create(512, 512, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
	if image == null or image.is_empty():
		image = Image.create(512, 512, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
	_undo.clear()
	_redo.clear()
	zoom = float(state.get("zoom", 1.0))
	_refresh_canvas()
	status.text = "Editing " + (path.get_file() if not path.is_empty() else "untitled image")


func capture_state() -> Dictionary:
	return {"image": image.duplicate() if image != null else null, "zoom": zoom}


func _disk_path(value: String) -> String:
	return ProjectSettings.globalize_path(value) if value.begins_with("res://") or value.begins_with("user://") else value


func _refresh_canvas() -> void:
	if image == null: return
	canvas.texture = ImageTexture.create_from_image(image)
	canvas.custom_minimum_size = Vector2(image.get_size()) * zoom
	canvas.size = canvas.custom_minimum_size
	zoom_label.text = "%d%%" % roundi(zoom * 100.0)
	size_label.text = "%d × %d px" % [image.get_width(), image.get_height()]
	canvas.queue_redraw()


func _set_zoom(value: float) -> void:
	zoom = clampf(value, 0.05, 32.0)
	_refresh_canvas()


func _fit_zoom() -> void:
	if image == null: return
	_set_zoom(minf((scroll.size.x - 40.0) / image.get_width(), (scroll.size.y - 40.0) / image.get_height()))


func _set_tool(value: String) -> void:
	tool = value
	tool_label.text = value.capitalize()
	status.text = "Drag on the image to crop" if value == "crop" else "Selected tool: " + tool_label.text


func _image_position(local: Vector2) -> Vector2i:
	return Vector2i(clampi(floori(local.x / zoom), 0, image.get_width() - 1),
		clampi(floori(local.y / zoom), 0, image.get_height() - 1))


func _canvas_input(event: InputEvent) -> void:
	if image == null: return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_zoom(zoom * 1.25)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_zoom(zoom / 1.25)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag_start = _image_position(event.position)
				_drag_end = _drag_start
				if tool == "picker":
					color_picker.color = image.get_pixelv(_drag_start)
					return
				_before_stroke = image.duplicate()
				_painting = true
				if tool == "fill":
					_fill(_drag_start)
					_finish_stroke()
				elif tool != "crop":
					_paint(_drag_start)
			else:
				if _painting and tool == "crop": _crop()
				if _painting: _finish_stroke()
	elif event is InputEventMouseMotion and _painting:
		var point := _image_position(event.position)
		if tool == "crop":
			_drag_end = point
			canvas.queue_redraw()
		elif tool == "brush" or tool == "eraser":
			var from := Vector2(_drag_end)
			var to := Vector2(point)
			var count := maxi(1, ceili(from.distance_to(to)))
			for step in range(count + 1): _paint(Vector2i(from.lerp(to, float(step) / count)), false)
			_drag_end = point
			_refresh_canvas()


func _paint(point: Vector2i, refresh: bool = true) -> void:
	var radius := maxi(0, roundi(brush_size.value / 2.0))
	for y in range(maxi(0, point.y - radius), mini(image.get_height(), point.y + radius + 1)):
		for x in range(maxi(0, point.x - radius), mini(image.get_width(), point.x + radius + 1)):
			if Vector2(x - point.x, y - point.y).length_squared() > radius * radius: continue
			image.set_pixel(x, y, Color.TRANSPARENT if tool == "eraser" else color_picker.color)
	if refresh: _refresh_canvas()


func _fill(start: Vector2i) -> void:
	var old := image.get_pixelv(start)
	var replacement := color_picker.color
	if old == replacement: return
	var pending: Array[Vector2i] = [start]
	while not pending.is_empty():
		var at: Vector2i = pending.pop_back()
		if at.x < 0 or at.y < 0 or at.x >= image.get_width() or at.y >= image.get_height(): continue
		if image.get_pixelv(at) != old: continue
		var left := at.x
		while left > 0 and image.get_pixel(left - 1, at.y) == old: left -= 1
		var right := at.x
		while right < image.get_width() - 1 and image.get_pixel(right + 1, at.y) == old: right += 1
		for x in range(left, right + 1):
			image.set_pixel(x, at.y, replacement)
			if at.y > 0 and image.get_pixel(x, at.y - 1) == old: pending.append(Vector2i(x, at.y - 1))
			if at.y < image.get_height() - 1 and image.get_pixel(x, at.y + 1) == old: pending.append(Vector2i(x, at.y + 1))
	_refresh_canvas()


func _crop() -> void:
	var low := Vector2i(mini(_drag_start.x, _drag_end.x), mini(_drag_start.y, _drag_end.y))
	var high := Vector2i(maxi(_drag_start.x, _drag_end.x), maxi(_drag_start.y, _drag_end.y))
	if high == low: return
	image = image.get_region(Rect2i(low, high - low + Vector2i.ONE))
	_refresh_canvas()


func _draw_canvas_overlay() -> void:
	if _painting and tool == "crop":
		var low := Vector2i(mini(_drag_start.x, _drag_end.x), mini(_drag_start.y, _drag_end.y))
		var high := Vector2i(maxi(_drag_start.x, _drag_end.x), maxi(_drag_start.y, _drag_end.y))
		canvas.draw_rect(Rect2(Vector2(low) * zoom, Vector2(high - low + Vector2i.ONE) * zoom), Color("63e9cf"), false, 2.0)


func _finish_stroke() -> void:
	_painting = false
	canvas.queue_redraw()
	if _before_stroke != null and image.get_data() != _before_stroke.get_data():
		_undo.append(_before_stroke)
		if _undo.size() > 30: _undo.pop_front()
		_redo.clear()
		document_changed.emit()
	_before_stroke = null


func _change_image(operation: Callable) -> void:
	if image == null: return
	_before_stroke = image.duplicate()
	operation.call()
	_refresh_canvas()
	_finish_stroke()


func _map_pixels(operation: Callable) -> void:
	for y in image.get_height():
		for x in image.get_width(): image.set_pixel(x, y, operation.call(image.get_pixel(x, y)))


func _resize_dialog() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Resize Image"
	add_child(dialog)
	var row := HBoxContainer.new()
	dialog.add_child(row)
	var width := SpinBox.new()
	width.min_value = 1
	width.max_value = 16384
	width.value = image.get_width()
	row.add_child(width)
	var spacer := Label.new()
	spacer.text = " × "
	row.add_child(spacer)
	var height := SpinBox.new()
	height.min_value = 1
	height.max_value = 16384
	height.value = image.get_height()
	row.add_child(height)
	dialog.confirmed.connect(func(): _change_image(func(): image.resize(int(width.value), int(height.value), Image.INTERPOLATE_LANCZOS)))
	dialog.popup_centered(Vector2i(320, 110))
	dialog.popup_hide.connect(dialog.queue_free)


func _adjust_dialog(title_text: String, minimum: float, maximum: float, starting: float,
		operation: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title_text
	add_child(dialog)
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 280
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.01
	slider.value = starting
	dialog.add_child(slider)
	dialog.confirmed.connect(func(): _change_image(func(): _map_pixels(func(c: Color): return operation.call(c, slider.value))))
	dialog.popup_centered(Vector2i(340, 110))
	dialog.popup_hide.connect(dialog.queue_free)


func undo() -> void:
	if _undo.is_empty(): return
	_redo.append(image.duplicate())
	image = _undo.pop_back()
	_refresh_canvas()
	document_changed.emit()


func redo() -> void:
	if _redo.is_empty(): return
	_undo.append(image.duplicate())
	image = _redo.pop_back()
	_refresh_canvas()
	document_changed.emit()


func _choose_image() -> void:
	var property := ActorProperty.new()
	property.id = &"image_file"
	property.label = "Image"
	property.options = {"extensions": IMAGE_EXTENSIONS, "file_picker": true}
	var chosen := await ActorProjectFilePicker.pick(self, property, "Load image from project")
	if chosen.is_empty(): return
	var tabs := get_tree().get_first_node_in_group("actor_scene_tabs")
	if tabs != null: tabs.open_image(chosen)
	else: open_source(chosen)


func save() -> void:
	if image == null: return
	if path.is_empty():
		if source is ImageTexture:
			(source as ImageTexture).set_image(image)
			image_saved.emit(source)
			status.text = "Saved embedded image"
			return
		await save_as()
		return
	if path.get_extension().to_lower() not in ["png", "jpg", "jpeg", "webp"]:
		await save_as()
		return
	var result := _write_image(path)
	if result != OK:
		status.text = "Save failed (%s)" % result
		return
	image_saved.emit(path)
	status.text = "Saved · " + path.get_file()
	if LocalProjectFilesystem.node != null: LocalProjectFilesystem.update_root_folder()


func save_as() -> void:
	if image == null: return
	var result := await ActorProjectResourceSaveDialog.pick(self, "Save image to project",
		path.get_file().get_basename() if not path.is_empty() else "Untitled Image", "png", false, PackedStringArray(SAVE_FORMATS))
	if result.get("cancelled", true): return
	var destination := str(result.get("path", ""))
	if destination.is_empty(): return
	var error := _write_image(destination)
	if error != OK:
		status.text = "Save failed (%s)" % error
		return
	path = destination
	source = destination
	image_saved.emit(path)
	status.text = "Saved · " + path.get_file()
	if LocalProjectFilesystem.node != null: LocalProjectFilesystem.update_root_folder()


func _write_image(destination: String) -> Error:
	match destination.get_extension().to_lower():
		"png": return image.save_png(_disk_path(destination))
		"jpg", "jpeg": return image.save_jpg(_disk_path(destination), 0.92)
		"webp": return image.save_webp(_disk_path(destination), false, 0.9)
	return ERR_FILE_UNRECOGNIZED


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.ctrl_pressed and event.keycode == KEY_S:
		if event.shift_pressed: save_as()
		else: save()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_Z:
		undo()
		get_viewport().set_input_as_handled()
	elif event.ctrl_pressed and event.keycode == KEY_Y:
		redo()
		get_viewport().set_input_as_handled()
