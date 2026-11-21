class_name ActorKeyframeEditor
extends Control

signal close_requested

var model: ActorTimeline
var timeline: ActorTimelineCanvas
var hints: RefCounted
var lanes: ActorKeyframeCanvas
var details: HBoxContainer
var heading: Label
var ruler: ActorKeyframeCanvas
var track_scroll: ScrollContainer
var detail_scroll: ScrollContainer
var header_panel: PanelContainer
var _actor: ActorData
var _editing := false
var _before: Array[ActorAnimationTrack] = []
var _details_signature: String = ""
var _detail_updaters: Array[Callable] = []
var curve_popup: PopupPanel

func _ready() -> void:
	_native_editor().ready(self)

func _layout_editor() -> void:
	_native_editor().layout_editor(self)

func refresh() -> void:
	_native_editor().refresh(self)

func cancel_interaction() -> void:
	_native_editor().cancel_interaction(self)

func _move_keys(ids: Array[String], timeline_delta: float) -> void:
	_native_editor().move_keys(self,ids,timeline_delta)

func _key_move_plan(ids: Array[String], timeline_delta: float, source: Array[ActorAnimationTrack]) -> Dictionary:
	return _native_editor().key_move_plan(self,ids,timeline_delta,source)

func _build_details() -> void:
	_native_editor().build_details(self)

func _add_state_value(track: ActorAnimationTrack, key: ActorKeyframe) -> void:
	_native_editor().add_state_value(self,track,key)

func _add_curve_button(key: ActorKeyframe) -> void:
	_native_editor().add_curve_button(self,key)

func _open_curve_menu(key_id: String) -> void:
	_native_editor().open_curve_menu(self,key_id)

func _number(label: String, value: float, make_changes: Callable) -> void:
	_native_editor().number(self,label,value,make_changes)

func _change_keys(primary_id: String, changes: Dictionary, preview: bool = false, axis: int = -1) -> void:
	_native_editor().change_keys(self,primary_id,changes,preview,axis)

func _begin_edit() -> void:
	_native_editor().begin_edit(self)

func _finish_edit() -> void:
	_native_editor().finish_edit(self)

func _cancel_edit() -> void:
	_native_editor().cancel_edit(self)

static func _native_editor() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("keyframe_editor")

func _invoke_number_changes(callback: Callable, number: float) -> Dictionary:
	return callback.call(number)

func _run_detail_updaters() -> void:
	for update in _detail_updaters:
		update.call()
