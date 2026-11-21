class_name KiwiAudioAutomationRecording
extends RefCounted
## One armed owner/parameter, one bounded pass, one undo action. Capture stays
## outside the edit session until commit; an unrelated edit invalidates it.
## Only native mixer gain/pan has a temporary playback-only monitor overlay.
signal status_changed(message: String)
const MODES := ["Read", "Write", "Touch", "Latch"]
const SAMPLE_SECONDS := 1.0 / 30.0
const BOUNDARY_SECONDS := 0.0001
const MAX_PASS_POINTS := 2048
const MAX_SEGMENTS := 64
const MAX_CURVE_POINTS := 10000
const MAX_PASS_SECONDS := 3600.0
const SMOOTH_STEPS := 16
var session: KiwiAudioEditSession
var playback: KiwiAudioPlayback
var mode := "Read"
var target: Dictionary = {"owner_kind": "master", "owner_id": "", "effect_id": "", "parameter": "volume_db"}
var lane_id := ""
var control_value := -3.0
var touching := false
var active := false
var committing := false
var message := "Read: existing curves play. Choose a target and a mode to record."
var _document: KiwiAudioDocument
var _revision := -1
var _original: Array = []
var _segments: Array[Dictionary] = []
var _segment: Dictionary = {}
var _last_position := 0.0
var _started_at := 0.0
var _fallback := 0.0
var _tolerance := 0.001
var _monitor: KiwiAudioDocument
var _live_monitor := false
var _latched := false

func bind(edit_session: KiwiAudioEditSession, transport: KiwiAudioPlayback) -> void:
	_native().call("bind", self, edit_session, transport)

func info() -> Dictionary:
	return _native().call("info", self)

func editable() -> bool:
	return _native().call("editable", self)

func matches(candidate: Dictionary) -> bool:
	return _native().call("matches", self, candidate)

func choose(candidate: Dictionary, source_lane: String = "") -> void:
	_native().call("choose", self, candidate, source_lane)

func set_mode(value: String) -> void:
	_native().call("set_mode", self, value)

func read_value(seconds: float) -> float:
	return _native().call("read_value", self, seconds)

func display_value(seconds: float) -> float:
	return _native().call("display_value", self, seconds)

func transport_changed(playing: bool, seconds: float) -> void:
	_native().call("transport_changed", self, playing, seconds)

func touch(seconds: float) -> void:
	_native().call("touch", self, seconds)

func change(value: float, seconds: float) -> void:
	_native().call("change", self, value, seconds)

func release(seconds: float) -> void:
	_native().call("release", self, seconds)

func tick(seconds: float, playing: bool) -> void:
	_native().call("tick", self, seconds, playing)

func document_changed() -> void:
	_native().call("document_changed", self)

func has_pending() -> bool:
	return _native().call("has_pending", self)

func finish(reason: String = "Pass finished") -> bool:
	return _native().call("finish", self, reason)

func discard(reason: String) -> void:
	_native().call("discard", self, reason)

func announce(value: String) -> void:
	_native().call("announce", self, value)

func _begin_pass(seconds: float) -> bool:
	return _native().call("begin_pass", self, seconds)

func _start_segment(seconds: float) -> void:
	_native().call("start_segment", self, seconds)

func _sample(seconds: float, force: bool) -> void:
	_native().call("sample", self, seconds, force)

func _point_count() -> int:
	return _native().call("point_count", self)

func _end_segment(seconds: float) -> void:
	_native().call("end_segment", self, seconds)

func _monitor_value() -> void:
	_native().call("monitor_value", self)

func _restore_monitor() -> void:
	_native().call("restore_monitor", self)

func _splice(original: Array, segment: Dictionary) -> Array:
	return _native().call("splice", self, original, segment)

func _original_point(original: Array, seconds: float, curve: String) -> Dictionary:
	return _native().call("original_point", self, original, seconds, curve)

func _curve_at(points: Array, seconds: float) -> String:
	return _native().call("curve_at", points, seconds)

static func _native() -> RefCounted:
	return Engine.get_singleton("KiwiNativeServices").call("service", "audio_automation_recording")
