class_name ActorTimelineCanvas
extends Control

signal time_selected(time: float)
signal scroll_requested(time: float)
signal layer_scroll_requested(offset: float)
signal assets_dropped(paths: PackedStringArray, time: float, layer: int)
signal interaction_changed(hint: String)
signal context_requested(screen_position: Vector2, actor_clicked: bool, timeline_time: float, layer: int)

const HEADER: float = 34.0
const ROW: float = 48.0
const LABEL_WIDTH: float = 140.0

var model: ActorTimeline
var registry: ActorRegistry
var pixels_per_second: float = 65.0
var row_height: float = ROW
var scroll_time: float = 0.0
var scroll_rows: float = 0.0
var playhead: float = 0.0
var snap_enabled: bool = true
var magnet_enabled := false
var split_tool := false

func magnetic_delta(delta: float, moving_times: Array[float], exclude_clips: Array[String] = [], exclude_keys: Array[String] = [], keyframe_view: bool = false, include_playhead: bool = true) -> float:
	return _native_canvas().magnetic_delta(self,delta,moving_times,exclude_clips,exclude_keys,keyframe_view,include_playhead)

func snapped_playhead(time: float, bypass: bool = false, keyframe_view: bool = false) -> float:
	return _native_canvas().snapped_playhead(self,time,bypass,keyframe_view)

var drag_id: String = ""
var preview_time: float = 0.0
var _drag_offset: float = 0.0
var scrubbing: bool = false
var _scrub_origin: float = 0.0
var drag_mode: String = "move"
var preview_duration: float = 0.0
var preview_layer: int = 0
var preview_valid: bool = true
var _original_start: float = 0.0
var _original_end: float = 0.0
var _pointer_x: float = 0.0
var _bypass_snap: bool = false
var _drag_ids: Array[String] = []
var _drag_originals: Dictionary = {}
var _preview_states: Dictionary = {}
var box_selecting: bool = false
var _box_start: Vector2
var _box_current: Vector2
var _box_base_selection: Array[String] = []
var _fade_actor: ActorData
var _fade_key: StringName
var _fade_original := 0.0
var _fade_pointer := 0.0
var recording_preview: Dictionary = {}
var recording_peaks := PackedFloat32Array()
var _asset_paths := PackedStringArray()
var _asset_templates: Array[Dictionary] = []
var _asset_previews: Array[Dictionary] = []

func display_layer_count() -> int:
	return _native_canvas().display_layer_count(self)

func _clear_asset_drag() -> void:
	_native_canvas().clear_asset_drag(self)

func preview_assets(at_position: Vector2, paths: PackedStringArray) -> bool:
	return _native_canvas().preview_assets(self,at_position,paths)

func fade_handle(index: int, incoming: bool) -> Vector2:
	return _native_canvas().fade_handle(self,index,incoming)

func _draw_fades(index: int, rect: Rect2) -> void:
	_native_canvas().draw_fades(self,index,rect)

func _cancel_fade() -> void:
	_native_canvas().cancel_fade(self)

func _ready() -> void:
	_native_canvas().ready(self)

static func dropped_paths(data: Variant) -> PackedStringArray:
	return _native_canvas().dropped_paths(data)

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return _native_canvas().can_drop_data(self,at_position,data)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	_native_canvas().drop_data(self,at_position,data)

func time_at(x: float) -> float:
	return _native_canvas().time_at(self,x)

func clip_rect(index: int) -> Rect2:
	return _native_canvas().clip_rect(self,index)

func cancel_drag() -> void:
	_native_canvas().cancel_drag(self)

func _gui_input(event: InputEvent) -> void:
	_native_canvas().gui_input(self,event)

func _begin_box_select(position: Vector2, add: bool, subtract: bool) -> void:
	_native_canvas().begin_box_select(self,position,add,subtract)

func _selection_box() -> Rect2:
	return _native_canvas().selection_box(self)

func _update_box_selection(add: bool, subtract: bool) -> void:
	_native_canvas().update_box_selection(self,add,subtract)

func _clip_hit_index(position: Vector2) -> int:
	return _native_canvas().clip_hit_index(self,position)

func _expanded_hit_rect(rect: Rect2) -> Rect2:
	return _native_canvas().expanded_hit_rect(rect)

func layer_at(y: float) -> int:
	return _native_canvas().layer_at(self,y)

func _input(event: InputEvent) -> void:
	_native_canvas().input(self,event)

func update_drag(pointer_x: float, bypass_snap: bool = false) -> void:
	_native_canvas().update_drag(self,pointer_x,bypass_snap)

func _trim_delta_bounds(left_edge: bool) -> Vector2:
	return _native_canvas().trim_delta_bounds(self,left_edge)

func _process(delta: float) -> void:
	_native_canvas().process(self,delta)

func advance_auto_scroll(delta: float) -> void:
	_native_canvas().advance_auto_scroll(self,delta)

func finish_drag() -> void:
	_native_canvas().finish_drag(self)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_DRAG_END,NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_native_canvas().notify_canvas(self,what)

func _draw_video_frames(index: int, rect: Rect2, visible_rect: Rect2) -> void:
	_native_canvas().draw_video_frames(self,index,rect,visible_rect)

func _draw_waveform(index: int, rect: Rect2, visible_rect: Rect2) -> void:
	_native_canvas().draw_waveform(self,index,rect,visible_rect)

func _draw_media_preview(state: Dictionary, recording: bool = false) -> void:
	_native_canvas().draw_media_preview(self,state,recording)

func _draw() -> void:
	_native_canvas().draw(self)

static func _native_canvas() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("timeline_canvas")
