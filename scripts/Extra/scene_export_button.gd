class_name ActorSceneExportButton
extends Button
## Scene-level MP4 export panel. The duration belongs to the editable scene.

const SceneExporter = preload("res://scripts/actors/core/actor_scene_exporter.gd")

var timeline: ActorTimelineEditor
var panel: PanelContainer
var overlay_layer: CanvasLayer
var duration_input: SpinBox
var duration_reset: Button
var resolution_input: OptionButton
var fps_input: OptionButton
var motion_input: OptionButton
var aa_input: OptionButton
var destination_label: Label
var status_label: Label
var export_button: Button
var project_button: Button
var computer_button: Button
var destination := ""
var destination_kind := ""
var busy := false
var _destination_tab := -1


func _ready() -> void:
	_native_export_ui().ready(self)

func _exit_tree() -> void:
	_native_export_ui().close(self)

func _open() -> void:
	_native_export_ui().open(self)

func _close() -> void:
	_native_export_ui().close(self)

func _field(parent: VBoxContainer, label_text: String, control: Control, hint: String = "") -> void:
	_native_export_ui().field(parent,label_text,control,hint)

func _choose_project() -> void:
	var suggested: String=_native_export_ui().suggested_name(self)
	var result := await ActorProjectResourceSaveDialog.pick(self,"Export video to project",suggested,"mp4",false)
	if not result.get("cancelled",true): _set_destination(str(result.get("path","")),"project")

func _choose_external() -> void:
	_native_export_ui().choose_external(self)

func _set_destination(path: String, kind: String = "") -> void:
	_native_export_ui().set_destination(self,path,kind)

func _update_destination_buttons() -> void:
	_native_export_ui().update_destination_buttons(self)

func _style_destination_button(button: Button, label: String, selected: bool) -> void:
	_native_export_ui().style_destination_button(button,label,selected)

func _sync_duration_ui() -> void:
	_native_export_ui().sync_duration_ui(self)

func _export() -> void:
	_native_export_ui().request_export(self)

func _render_to_destination() -> void:
	var plan: Dictionary=_native_export_ui().prepare_render(self)
	var error: String=await SceneExporter.render(timeline,plan.destination,plan.width,plan.height,plan.fps,_progress,plan.options)
	_native_export_ui().finish_render(self,plan,error)

func _progress(done: int, total: int, stage: String) -> void:
	_native_export_ui().progress(self,done,total,stage)

func _button(label_text: String, accent: bool) -> Button:
	return _native_export_ui().button(label_text,accent)

func _style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	return _native_export_ui().style(background,border,radius)


static func _native_export_ui() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("scene_export_button")
