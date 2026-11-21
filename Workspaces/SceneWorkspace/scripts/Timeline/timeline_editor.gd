class_name ActorTimelineEditor
extends VBoxContainer

const MENU_HEADER := 100
const MENU_DUPLICATE := 101
const MENU_COPY := 102
const MENU_PASTE := 103
const MENU_PARENT := 104
const MENU_UNPARENT := 105
const MENU_DELETE := 106
const MENU_DELETE_SECTION := 107
const MENU_FOCUS_ACTOR := 108
const MENU_TIMING := 109

var model := ActorTimeline.new()
var registry := ActorRegistry.new()
var canvas: ActorTimelineCanvas
var add_button: Button
var actor_picker: ActorPicker
var undo_button: Button
var redo_button: Button
var context_menu: PopupMenu
var start_input: DragNumber
var end_input: DragNumber
var x_zoom: HSlider
var y_zoom: HSlider
var time_label: Label
var h_scroll: HScrollBar
var v_scroll: VScrollBar
var _definitions: Array[ActorDefinition] = []
var inspector: ActorInspector
const InteractionHintsNative=preload("res://Workspaces/SceneWorkspace/scripts/Timeline/InteractionHints.cs")
var hints: RefCounted = InteractionHintsNative.new()
var hint_label: Label
var runtime_holder: Node3D
var _runtimes: Dictionary = {}
var physics := KiwiTimelinePhysics.new()
var _particle_seek_states: Dictionary = {}
var viewport_gizmo: ActorUIGizmo
var inspector_ui_state := ActorInspectorState.new()
var _ui_save_revision: int = 0
var _displayed_section_id: String = ""
var _displayed_focus_id: String = ""
var breadcrumb_row: HBoxContainer
var _breadcrumb_signature: String = ""
var _timeline_section_states: Dictionary = {}
var snap_button: CheckButton
var keyframe_editor: ActorKeyframeEditor
var keyframes_button: Button
var keyframe_view: Control
var breadcrumb_panel: PanelContainer
var actor_view: HBoxContainer
var property_overlay: ActorKeyframeCanvas
var play_button: Button
var magnet_button: Button
var split_button: Button
var playing := false
var exporting := false
var _video_duration_override := -1.0
var video_duration: float:
	get: return _native_editor().video_duration(self)


func video_duration_is_custom() -> bool:
	return _video_duration_override > 0.0


func set_video_duration(value: float) -> void:
	_native_editor().set_video_duration(self,value)

func reset_video_duration() -> void:
	_native_editor().reset_video_duration(self)

func _apply_video_duration(value: float) -> void:
	_video_duration_override = value
	model.changed.emit()
var audio_system: ActorAudioSystem
var audio_recorder: ActorAudioRecorder
var mic_button: Button
var mic_options_button: Button
var screen_button: Button
var screen_recorder: ActorScreenRecorder
var _record_start := 0.0
var _record_elapsed := 0.0
var _record_layer := 0
var _record_busy := false
var _recording_viewport: SubViewport
var _saved_viewport_update := 0
var _saved_scene_process := 0
var timing_dialog: AcceptDialog
var _actor_clipboard: Array[Dictionary] = []
var _context_time: float = 0.0
var _context_layer: int = 0
var _context_on_actor: bool = false
var _context_section_id: String = ""
var _timing_drag_original: Dictionary = {}
var _timing_drag_kind: String = ""


func _exit_tree() -> void:
	physics.dispose()
	_flush_ui_state_save()
	_pause_recording_scene(false)
	if is_instance_valid(viewport_gizmo): viewport_gizmo.queue_free()
	# Undo callables retain the model; release their references when closing the UI.
	if is_instance_valid(model.history):
		model.history.clear_history()
		model.history.free()
	if is_instance_valid(runtime_holder):
		runtime_holder.queue_free()
	_runtimes.clear()
	_particle_seek_states.clear()


func _ready() -> void:
	_native_editor().ready(self)

func _inspect_project_resource(path: String) -> void:
	_native_editor().inspect_project_resource(self,path)

func _toolbar_icon(kind: String) -> Texture2D:
	return _native_editor().toolbar_icon(kind)

func _pause_recording_scene(paused: bool) -> void:
	_native_editor().pause_recording_scene(self,paused)

func _active_recording_audio() -> ActorAudioRecorder:
	return _native_editor().active_recording_audio(self)

func _recording_timeline_audio() -> bool:
	return _native_editor().recording_timeline_audio(self)

func _route_timeline_audio() -> void:
	_native_editor().route_timeline_audio(self)

func toggle_recording() -> void:
	var operation: int=_native_editor().begin_audio_recording_toggle(self)
	if operation==1:
		var error: String=await audio_recorder.start()
		_native_editor().audio_recording_started(self,error)
	elif operation==2:
		var stream: AudioStreamWAV=await audio_recorder.stop()
		_native_editor().audio_recording_stopped(self,stream)

func _create_recording(stream: AudioStreamWAV) -> ActorClip:
	return _native_editor().create_recording(self,stream)

func _audio_notice(message: String) -> void:
	_native_editor().audio_notice(self,message)

func toggle_playback() -> void:
	_native_editor().toggle_playback(self)

func _process(delta: float) -> void:
	_native_editor().process(self,delta)

func _start_screen_recording(options: Dictionary, target: Dictionary) -> void:
	if not _native_editor().begin_screen_recording(self): return
	var error: String=await screen_recorder.start(options,target)
	_native_editor().screen_recording_started(self,error)

func _stop_screen_recording() -> void:
	if not _native_editor().begin_screen_stop(self): return
	var path: String=await screen_recorder.stop()
	_native_editor().screen_recording_stopped(self,path)
	if not path.is_empty():
		var dimension: StringName = await ActorDimensionDialog.choose(self,"Screen Recording")
		_native_editor().create_screen_recording(self,path,dimension)

func set_keyframe_view(enabled: bool) -> void:
	_native_editor().set_keyframe_view(self,enabled)

func _button(parent: Control, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _timing_input(parent: Control, label_text: String) -> DragNumber:
	return _native_editor().timing_input(parent,label_text)

func _zoom_slider(parent: Control, axis: String, minimum: float, maximum: float,
		initial: float, tooltip: String) -> HSlider:
	return _native_editor().zoom_slider(parent,axis,minimum,maximum,initial,tooltip)

func _connect_timing_input(input: DragNumber, kind: String) -> void:
	_native_editor().connect_timing_input(self,input,kind)

func _capture_clip_states() -> Dictionary:
	return _native_editor().capture_clip_states(self)

func _timing_states(value: float, kind: String, originals: Dictionary) -> Dictionary:
	return _native_editor().timing_states(self,value,kind,originals)

func create_actor(type_index: int) -> void:
	var plan: Dictionary=_native_editor().prepare_actor_creation(self,type_index)
	if plan.is_empty(): return
	for prompt: Dictionary in plan.prompts:
		var chosen:=await ActorProjectFilePicker.pick(self,prompt.picker,prompt.title)
		if not _native_editor().actor_creation_choice(self,plan,prompt,chosen): return
	_native_editor().finish_actor_creation(self,plan)

func _create_dropped_actors(paths: PackedStringArray, time: float, layer: int) -> void:
	canvas.cancel_drag()
	for path in paths:
		var plan: Dictionary=_native_editor().prepare_drop(self,path,time,layer)
		if plan.is_empty(): continue
		var dimension: StringName=&""
		if plan.dimension: dimension=await ActorDimensionDialog.choose(self,plan.title)
		_native_editor().finish_drop(self,path,time,layer,plan,dimension)
	_native_editor().finish_drops(self)

func delete_selected() -> void:
	_native_editor().delete_selected(self)

func unparent_selected() -> void:
	_native_editor().unparent_selected(self)

func parent_selected() -> void:
	_native_editor().parent_selected(self)

func copy_selected() -> void:
	_native_editor().copy_selected(self)

func duplicate_selected() -> void:
	_native_editor().duplicate_selected(self)

func paste_copied(as_children: bool, time: float, layer: int) -> void:
	_native_editor().paste_copied(self,as_children,time,layer)

func _capture_selected_snapshots() -> Array[Dictionary]:
	return _native_editor().capture_selected_snapshots(self)

const MENU_EDIT_AUDIO := 90721

func _show_context_menu(screen_position: Vector2, actor_clicked: bool = true,
		timeline_time: float = -1.0, layer: int = -1, root_label: String = "", section_id: String = "") -> void:
	_native_editor().show_context_menu(self,screen_position,actor_clicked,timeline_time,layer,root_label,section_id)

func _context_action_selected(id: int) -> void:
	_native_editor().context_action_selected(self,id)

func focus_selected_actor() -> void:
	_native_editor().focus_selected_actor(self)

func _update_breadcrumbs() -> void:
	_native_editor().update_breadcrumbs(self)

func _confirm_delete_section(section_id: String) -> void:
	_native_editor().confirm_delete_section(self,section_id)

func undo() -> void:
	_native_editor().undo(self)

func redo() -> void:
	_native_editor().redo(self)

func capture_scene_data(duplicate_resources: bool = true) -> ActorSceneData:
	return _native_editor().capture_scene_data(self,duplicate_resources)

func restore_scene_data(scene: ActorSceneData, retain_previous_history: bool = false) -> void:
	_native_editor().restore_scene_data(self,scene,retain_previous_history)

func _setup_runtime_holder() -> void:
	_native_editor().setup_runtime_holder(self)

func _connect_shader_editor() -> void:
	_native_editor().connect_shader_editor(self)

func _on_shader_source_changed(_source: Variant) -> void:
	_recreate_runtimes()


func refresh_saved_shader(source: Variant) -> void:
	_native_editor().refresh_saved_shader(self,source)

func _recreate_runtimes() -> void:
	_native_editor().recreate_runtimes(self)

func _on_model_changed() -> void:
	_native_editor().on_model_changed(self)

func _sync_runtimes() -> void:
	_native_editor().sync_runtimes(self)

func _runtime_for_clip(clip_id: String) -> ActorRuntime:
	return _native_editor().runtime_for_clip(self,clip_id)

func _evaluate_runtimes() -> void:
	_native_editor().evaluate_runtimes(self)

func _update_camera_overlays() -> void:
	_native_editor().update_camera_overlays(self)

func _sync_particle_seeks() -> void:
	_native_editor().sync_particle_seeks(self)

func _apply_remote_transforms() -> void:
	_native_editor().apply_remote_transforms(self)

func _actor_depth(actor: ActorData) -> int:
	return _native_editor().actor_depth(self,actor)

var _ui_state_save_timer: Timer
var _ui_state_save_project: Project

func _flush_ui_state_save() -> void:
	_native_editor().flush_ui_state_save(self)

func _schedule_ui_state_save() -> void:
	_native_editor().schedule_ui_state_save(self)

func _input(event: InputEvent) -> void:
	_native_editor().input(self,event)

func _unhandled_key_input(event: InputEvent) -> void:
	_native_editor().unhandled_key_input(self,event)

func handle_actor_shortcut(event: InputEventKey, selection_shortcuts: bool = true) -> bool:
	return _native_editor().handle_actor_shortcut(self,event,selection_shortcuts)

func _refresh() -> void:
	_native_editor().refresh(self)

func _update_idle_hint() -> void:
	_native_editor().update_idle_hint(self)

func _box(background: Color, border: Color) -> StyleBoxFlat:
	return _native_editor().box(background,border)

func _style_context_menu() -> void:
	_native_editor().style_context_menu(self)

func _apply_theme() -> void:
	_native_editor().apply_theme(self)

static func _native_editor() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("timeline_editor")

func _sync_property_overlay() -> void:
	_native_editor().sync_property_overlay(self)

func _set_hint_text(text: String) -> void:
	hint_label.text=text
