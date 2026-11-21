class_name ActorKeyframeCanvas
extends Control

signal selection_changed
signal move_requested(ids: Array[String], timeline_delta: float)
signal move_preview_requested(ids: Array[String], timeline_delta: float)
signal delete_requested(ids: Array[String])
signal interaction_changed(text: String)

const ROW := 30.0
const HEADER := 56.0
var model: ActorTimeline
var timeline: ActorTimelineCanvas
var actor: ActorData
var selected_keys: Array[String] = []
var _dragging := false
var _drag_origin: float
var _delta := 0.0
var _original_times: Dictionary = {}
var overlay_mode := false
var overlay_path := PackedStringArray()
var _scrubbing := false
var _scrub_origin := 0.0
var show_ruler := true
var ruler_only := false
var box_selecting := false
var _box_start: Vector2
var _box_end: Vector2
var _box_base: Array[String] = []

func track_height() -> float:
	return _native_keys().track_height(self)

func header_height() -> float:
	return _native_keys().header_height(self)

func _selection_box() -> Rect2:
	return _native_keys().selection_box(self)

func _update_box(add: bool, subtract: bool) -> void:
	_native_keys().update_box(self,add,subtract)

func displayed_tracks() -> Array[ActorAnimationTrack]:
	if actor==null: return []
	return _native_keys().displayed_tracks(self)

func overlay_rect() -> Rect2:
	return _native_keys().overlay_rect(self)

func _ready() -> void:
	_native_keys().ready(self)

func cancel_drag() -> void:
	_native_keys().cancel_drag(self)

func key_position(key: ActorKeyframe, row: int) -> Vector2:
	return _native_keys().key_position(self,key,row)

func _get_tooltip(at_position: Vector2) -> String:
	return _native_keys().tooltip(self,at_position)

func _draw() -> void:
	_native_keys().draw(self)

func _draw_ruler(font: Font) -> void:
	_native_keys().draw_ruler(self,font)

func _clip_style() -> StyleBoxFlat:
	return _native_keys().clip_style()

func _gui_input(event: InputEvent) -> void:
	_native_keys().gui_input(self,event)

func _input(event: InputEvent) -> void:
	_native_keys().input(self,event)

static func _native_keys() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("keyframe_canvas")
