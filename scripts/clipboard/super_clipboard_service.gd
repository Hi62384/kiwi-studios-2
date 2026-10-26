class_name KiwiSuperClipboardService
extends Node
## App-wide lifetime. Metadata only is read at startup; assets remain lazy.
static var instance: KiwiSuperClipboardService
var store: KiwiClipboardStore
var window: Control
var layer: CanvasLayer
var toast: Label
var toast_panel:=PanelContainer.new()
var toast_timer:=Timer.new()
func _ready() -> void:
	instance=self; store=KiwiClipboardStore.new()
	if not InputMap.has_action("super_clipboard"):
		InputMap.add_action("super_clipboard"); var key:=InputEventKey.new(); key.physical_keycode=KEY_F8; InputMap.action_add_event("super_clipboard",key)
	layer=CanvasLayer.new(); layer.layer=1200; add_child(layer)
	toast_panel.mouse_filter=Control.MOUSE_FILTER_IGNORE; layer.add_child(toast_panel)
	var style:=StyleBoxFlat.new(); style.bg_color=Color("152b31"); style.border_color=Color("427b71"); style.set_border_width_all(1); style.set_corner_radius_all(6); style.set_content_margin_all(8); toast_panel.add_theme_stylebox_override("panel",style)
	toast=Label.new(); toast.name="ClipboardNotification"; toast.mouse_filter=Control.MOUSE_FILTER_IGNORE; toast.add_theme_font_size_override("font_size",12); toast_panel.add_child(toast); toast_panel.hide()
	toast_timer.one_shot=true; add_child(toast_timer); toast_timer.timeout.connect(toast_panel.hide)
	if not store.error.is_empty(): notify(store.error,true)
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("super_clipboard") and not event.is_echo(): toggle(); get_viewport().set_input_as_handled()
func toggle() -> void:
	if not is_instance_valid(window):
		window=load("res://scripts/clipboard/clipboard_window.gd").new(); layer.add_child(window); window.configure(self)
	elif window.visible: window._close()
	else: window.show()
	if window.visible: window.move_to_front(); window.search.grab_focus()
func notify(message: String,failed: bool=false) -> void:
	toast.text=message; toast.add_theme_color_override("font_color",Color("ffab99") if failed else Color("8ce8ce")); toast_panel.position=Vector2(20,get_viewport().get_visible_rect().size.y-44); toast_panel.show(); toast_panel.move_to_front()
	toast_timer.start(5)
func quick_save(value: Variant,title: String="Resource",folder: String="default") -> String:
	var id:=store.save(value,title,folder)
	notify("Saved to Super Clipboard · "+title if not id.is_empty() else store.error,id.is_empty())
	return id
func import_item(id: String) -> String:
	if StaticData.loaded_project==null: store.error="Open a project to use a clipboard resource."; notify(store.error,true); return ""
	var path:=store.materialize(id,ActorProjectFilePicker.root_directory())
	if path.is_empty(): notify(store.error,true)
	return path
func drag_payload(ids: PackedStringArray) -> Dictionary:
	if StaticData.loaded_project==null: return {"type":"super_clipboard","clipboard_ids":ids} if not ids.is_empty() else {}
	var paths:=PackedStringArray()
	for id in ids:
		var path:=import_item(id)
		if path.is_empty(): return {}
		paths.append(path)
	if paths.is_empty(): return {}
	return {"type":"project_files","source":"super_clipboard","clipboard_ids":ids,"paths":paths,"path":paths[0]}
func save_active_document() -> void:
	var tabs:=get_tree().get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs
	if tabs==null or tabs._active_index<0 or tabs._active_index>=tabs.documents.size(): notify("Open a document first.",true); return
	var document: Dictionary=tabs.documents[tabs._active_index]; var value: Variant
	match str(document.get("type","scene")):
		"image": tabs.image_workspace._finish_pending(); value=tabs.image_workspace.document.snapshot()
		"model": tabs.model_workspace.canvas.finish_transform(); value=tabs.model_workspace.session.document.snapshot()
		"transformation": tabs.transformation_workspace.finish_pending(); value=tabs.transformation_workspace.session.document.snapshot()
		"audio": tabs.audio_workspace.capture_state(); value=tabs.audio_workspace.session.document.snapshot()
		"shader": var shader:=Shader.new(); shader.code=tabs.shader_workspace.editor.code.text; value=shader
		_: value=tabs.timeline.capture_scene_data()
	quick_save(value,str(document.get("name","Document")))
func _exit_tree() -> void:
	if store!=null: store.close()
	if instance==self: instance=null
