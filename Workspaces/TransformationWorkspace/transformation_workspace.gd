class_name KiwiTransformationWorkspace
extends Control
signal document_changed
signal asset_saved(path: String, saved_session: KiwiTransformationSession)
var session := KiwiTransformationSession.new()
var path := ""
var canvas := KiwiTransformationCanvas.new()
var edit_renderer := KiwiImageRenderer.new()
var animation_renderer := KiwiTransformationRenderer.new()
var timeline := KiwiTransformationTimeline.new()
var components := KiwiTransformationComponents.new()
var properties := VBoxContainer.new()
var key_fields := HBoxContainer.new()
var header := Label.new()
var mode_label := Label.new()
var status := Label.new()
var play_button := Button.new()
var time_control: DragNumber
var tool_context := HBoxContainer.new()
var tools: Dictionary={}
var previewing := false
var playing := false
var loop := true
var onion := false
var shape_kind := "rectangle"
var edit_document := KiwiImageDocument.new()
var _render_pending := true
var _ui_pending := true
var _syncing := false
var _gesture := false
var _number_drag := false
var _component_panel := VBoxContainer.new()
var _property_panel := ScrollContainer.new()
var _split: HSplitContainer
var _right_split := HSplitContainer.new()
var _before_art: Dictionary={}
var _state_name: LineEdit
func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_workspace")
func _draw() -> void: _native().call("draw", self)
func _ready() -> void: _native().call("ready", self)
func _theme() -> void: _native().call("theme", self)
func button(parent: Node, text: String, action: Callable, hint: String="") -> Button: return _native().call("button", self, parent, text, action, hint)
func label(parent: Node, text: String) -> Label: return _native().call("label", parent, text)
func clear(parent: Node) -> void: _native().call("clear", parent)
func style_popup(popup: PopupPanel) -> void: _native().call("style_popup", popup)
func choice(parent: Node, options: Array, current: String, callback: Callable) -> OptionButton: return _native().call("choice", self, parent, options, current, callback)
func number(parent: Node, caption: String, value: float, minimum: float, maximum: float, step: float, setter: Callable, state_edit: bool=false, undoable: bool=true) -> DragNumber: return _native().call("number", self, parent, caption, value, minimum, maximum, step, setter, state_edit, undoable)
func _finish_number_transaction(owner_session: KiwiTransformationSession) -> void: _native().call("finish_number_transaction", self, owner_session)
func _commit_number(caption: String, state_edit: bool) -> bool: return _native().call("commit_number", self, caption, state_edit)
func _build() -> void: _native().call("build", self)
func _changed() -> void: _native().call("changed", self)
func _process(delta: float) -> void: _native().call("process", self, delta)
func _sync_edit_document() -> void: _native().call("sync_edit_document", self)
func _begin_gesture() -> void: _native().call("begin_gesture", self)
func _capture_art() -> void: _native().call("capture_art", self)
func _preview_gesture() -> void: _native().call("preview_gesture", self)
func _finish_gesture() -> void: _native().call("finish_gesture", self)
func _cancel_gesture() -> void: _native().call("cancel_gesture", self)
func touch_states() -> void: _native().call("touch_states", self)
func finish_pending() -> void: _native().call("finish_pending", self)
func edit_mode() -> void: _native().call("edit_mode", self)
func set_tool(value: String) -> void:
	var job: Object = _native().call("job", self, "tool", value)
	if not job.finished: await job.completed
func seek(value: float) -> void: _native().call("seek", self, value)
func toggle_play() -> void: _native().call("toggle_play", self)
func _key_selected() -> void: _native().call("key_selected", self)
func selected_key() -> Dictionary: return _native().call("selected_key", self)
func edit_key_state() -> void: _native().call("edit_key_state", self)
func _refresh() -> void: _native().call("refresh", self)
func _refresh_components() -> void: _native().call("refresh_components", self)
func icon(kind: String, active: bool) -> Texture2D: return _native().call("icon", kind, active)
func _tree_selected(row: TreeItem, _column: int, selected: bool) -> void: _native().call("tree_selected", self, row, selected)
func _rename_component() -> void: _native().call("rename_component", self)
func _component_button(row: TreeItem, _column: int, id: int, _mouse: int) -> void: _native().call("component_button", self, row, id)
func _refresh_properties() -> void: _native().call("refresh_properties", self)
func _refresh_tools() -> void: _native().call("refresh_tools", self)
func _refresh_keys() -> void: _native().call("refresh_keys", self)
func change_keys(title: String, operation: Callable) -> void: _native().call("change_keys", self, title, operation)
func state_menu() -> void: _native().call("state_menu", self)
func component_menu() -> void: _native().call("component_menu", self)
func menu(title: String, options: Array, callback: Callable) -> void: _native().call("menu", self, title, options, callback)
func duration_dialog() -> void: _native().call("duration_dialog", self)
func canvas_size_dialog() -> void: _native().call("canvas_size_dialog", self)
func _shape_created(kind: String, bounds: Rect2, _points: PackedVector2Array) -> void: _native().call("shape_created", self, kind, bounds)
func extract_selection() -> void: _native().call("extract_selection", self)
func detach_at_playhead() -> void: _native().call("detach_at_playhead", self)
func merge_at_playhead() -> void:
	var job: Object = _native().call("job", self, "merge", "")
	if not job.finished: await job.completed
func events_dialog() -> void: _native().call("events_dialog", self)
func remove_component_event(id: String) -> void: _native().call("remove_component_event", self, id)
func import_dialog() -> void:
	var job: Object = _native().call("job", self, "import", "")
	if not job.finished: await job.completed
func import_image(source: String) -> void: _native().call("import_image", self, source)
func _add_reveal_point(value: Vector2) -> void: _native().call("add_reveal_point", self, value)
func morph_options() -> void: _native().call("morph_options", self)
func curve_dialog() -> void: _native().call("curve_dialog", self)
func match_dialog() -> void: _native().call("match_dialog", self)
static func resolve(value: Variant) -> Dictionary: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_workspace").call("resolve", value)
func open_source(value: Variant, state: Dictionary={}) -> bool: return _native().call("open_source", self, value, state)
static func view_number(ui: Dictionary, name: String, fallback: float) -> float: return Engine.get_singleton("KiwiNativeServices").call("service", "transformation_workspace").call("view_number", ui, name, fallback)
func capture_state() -> Dictionary: return _native().call("capture_state", self)
func ui_state() -> Dictionary: return _native().call("ui_state", self)
func open_dialog() -> void:
	var job: Object = _native().call("job", self, "open", "")
	if not job.finished: await job.completed
func open_example(title: String) -> void: _native().call("open_example", self, title)
func save() -> void:
	var job: Object = _native().call("job", self, "save", path)
	if not job.finished: await job.completed
func save_as() -> void:
	var job: Object = _native().call("job", self, "save_as", "")
	if not job.finished: await job.completed
func save_to(destination: String) -> Error:
	var job: Object = _native().call("job", self, "save", destination)
	if not job.finished: await job.completed
	return job.result
func _unhandled_key_input(event: InputEvent) -> void: _native().call("unhandled_key_input", self, event)
func _examples_menu() -> void: _native().call("examples_menu", self)

func _dispatch_native_callback(binding: Object, arguments: Array) -> Variant:
	var callback: Callable = binding.get_meta("native_callback")
	return callback.callv(arguments) if callback.is_valid() else null
