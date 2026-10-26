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
	discard("Read: choose a target and a mode to record.")
	session = edit_session
	playback = transport
	target = {"owner_kind": "master", "owner_id": "", "effect_id": "", "parameter": "volume_db"}
	lane_id = ""
	control_value = read_value(transport.position)

func info() -> Dictionary:
	return KiwiAudioAutomationLane.resolve(session.document, target) if session != null else {}

func editable() -> bool:
	var resolved := info()
	if resolved.is_empty() or bool(resolved.locked): return false
	if not lane_id.is_empty():
		if not KiwiAudioAutomationLane.editable(session.document, lane_id): return false
		if KiwiAudioAutomationLane.key(session.document.track_for_id(lane_id).get("automation_target", {})) != KiwiAudioAutomationLane.key(target): return false
	return true

func matches(candidate: Dictionary) -> bool:
	return KiwiAudioAutomationLane.key(candidate) == KiwiAudioAutomationLane.key(target)

func choose(candidate: Dictionary, source_lane: String = "") -> void:
	finish("Target changed")
	target = candidate.duplicate(true)
	lane_id = source_lane
	control_value = read_value(playback.position if playback != null else 0.0)
	announce("Read: %s. Choose Write, Touch or Latch to arm this parameter." % str(info().get("label", "Target unavailable")))

func set_mode(value: String) -> void:
	if not MODES.has(value): return
	finish("Mode changed")
	if value != "Read" and not editable():
		announce("Read: unlock the owner and linked lane before recording automation.")
		return
	mode = value
	if mode == "Read": announce("Read: existing curves play; no automation is recorded.")
	else:
		announce("%s armed for %s. Returns to Read after the pass." % [mode, str(info().get("label", "parameter"))])
		if playback != null and playback.playing: transport_changed(true, playback.position)

func read_value(seconds: float) -> float:
	var resolved := info()
	if resolved.is_empty(): return control_value
	return KiwiAudioAutomationLane.value(KiwiAudioAutomationLane.points(resolved), maxf(0.0, seconds - float(resolved.offset)), float(resolved.fallback))

func display_value(seconds: float) -> float:
	if mode != "Read" and (touching or not _segment.is_empty() or not playback.playing): return control_value
	return read_value(seconds)

func transport_changed(playing: bool, seconds: float) -> void:
	if not playing:
		if active: finish("Transport stopped")
		return
	if mode != "Read" and not active and (mode == "Write" or touching or _latched):
		if _begin_pass(seconds): _start_segment(seconds)

func touch(seconds: float) -> void:
	if mode == "Read" or not editable(): return
	if playback != null and playback.playing and (mode == "Touch" or (mode == "Latch" and not _latched)):
		control_value = read_value(seconds)
	touching = true
	if mode == "Latch": _latched = true
	if playback == null or not playback.playing: return
	if not active and not _begin_pass(seconds): return
	if _segment.is_empty(): _start_segment(seconds)

func change(value: float, seconds: float) -> void:
	if mode == "Read" or not is_finite(value) or not editable(): return
	var resolved := info()
	if playback != null and playback.playing and (not touching or not active): touch(seconds)
	if mode == "Read": return
	control_value = clampf(value, float(resolved.minimum), float(resolved.maximum))
	if playback == null or not playback.playing:
		announce("%s armed: start value %.3f. Press Play to record." % [mode, control_value])
		return
	if active and not _segment.is_empty():
		_sample(seconds, false)
		_monitor_value()

func release(seconds: float) -> void:
	touching = false
	if not active: return
	if mode == "Touch":
		_end_segment(seconds)
		_restore_monitor()
		announce("Touch: released to the original curve; the pending pass saves on Stop.")
	elif mode == "Latch": announce("Latch: holding %.3f until Stop." % control_value)

func tick(seconds: float, playing: bool) -> void:
	if not active:
		if playing and mode == "Write": transport_changed(true, seconds)
		return
	if session.document != _document or session.revision != _revision or not editable():
		discard("Read: pending automation cancelled because the document, target or lock changed.")
		return
	if not playing:
		finish("Transport stopped")
		return
	if seconds + BOUNDARY_SECONDS < _last_position:
		finish("Loop wrap or backward seek ended the pass")
		return
	if seconds - _started_at >= MAX_PASS_SECONDS:
		finish("One-hour pass limit reached")
		return
	_last_position = seconds
	if _segment.is_empty() and (mode == "Write" or touching or _latched): _start_segment(seconds)
	if not _segment.is_empty():
		_sample(seconds, false)
		if active: _monitor_value()

func document_changed() -> void:
	if committing: return
	if active: discard("Read: another edit cancelled the pending automation pass; that edit was preserved.")
	elif mode != "Read" and not editable(): discard("Read: automation target is locked or unavailable.")

func has_pending() -> bool:
	return active and not _segments.is_empty()

func finish(reason: String = "Pass finished") -> bool:
	if not active:
		var was_armed := mode != "Read"
		touching = false; _latched = false
		mode = "Read"
		_restore_monitor()
		if was_armed: announce("Read: %s. No automation changes to save." % reason)
		return false
	if session.document != _document or session.revision != _revision or not editable() or session._before != null:
		discard("Read: pending automation cancelled because another edit or lock changed its target.")
		return false
	_end_segment(_last_position)
	var result := _original.duplicate(true)
	for segment in _segments: result = _splice(result, segment)
	var label := str(info().get("label", "parameter"))
	var recorded_mode := mode
	var changed := not _segments.is_empty() and result != _original
	_restore_monitor()
	active = false; touching = false; _latched = false; mode = "Read"
	_segments.clear(); _segment = {}; _document = null; _original = []
	if result.size() > MAX_CURVE_POINTS:
		announce("Read: pass was not saved because it would exceed 10,000 points. Simplify this curve first.")
		return false
	if changed:
		var resolved := info()
		committing = true
		session.action("Record %s automation: %s" % [recorded_mode, label], func():
			var curves: Dictionary = resolved.owner.get("automation", {})
			curves[str(resolved.parameter)] = result
			resolved.owner["automation"] = curves)
		committing = false
		announce("Read: %s. Saved %s as one undo action; replay to hear the committed curve." % [reason, label])
	else: announce("Read: %s. No automation changes to save." % reason)
	return changed

func discard(reason: String) -> void:
	# Stop callbacks must see an inactive recorder before invalidation stops audio.
	active = false; touching = false; _latched = false; mode = "Read"
	_restore_monitor()
	_segments.clear(); _segment = {}; _document = null; _original = []
	announce(reason)

func announce(value: String) -> void:
	message = value
	status_changed.emit(value)

func _begin_pass(seconds: float) -> bool:
	if not editable() or session._before != null:
		discard("Read: finish the current edit and unlock the target before recording automation.")
		return false
	var resolved := info()
	_original = KiwiAudioAutomationLane.points(resolved).duplicate(true)
	_original.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.time) < float(b.time))
	if _original.size() > MAX_CURVE_POINTS - 2 * SMOOTH_STEPS - 4:
		discard("Read: this curve is too dense to record safely. Simplify it before another pass.")
		return false
	_document = session.document; _revision = session.revision
	_fallback = float(resolved.fallback)
	_tolerance = maxf(0.00001, (float(resolved.maximum) - float(resolved.minimum)) * 0.0005)
	_segments.clear(); _segment = {}
	_last_position = seconds; _started_at = seconds; active = true
	_live_monitor = not playback.exact_preview_active and not playback.exact_pending and not playback.exact_required and str(target.get("effect_id", "")).is_empty() and str(target.owner_kind) in ["track", "master"]
	announce("%s recording %s. %s" % [mode, str(resolved.label), "Native mixer monitoring is live." if _live_monitor else "Capture only: the current rendered/clip/effect audio stays unchanged until replay."])
	return true

func _start_segment(seconds: float) -> void:
	var resolved := info()
	var local := seconds - float(resolved.offset)
	if local < 0.0: return
	if local > float(resolved.duration):
		finish("Target range ended")
		return
	if _segments.size() >= MAX_SEGMENTS:
		finish("64-gesture limit reached")
		return
	if _point_count() + 2 > mini(MAX_PASS_POINTS, MAX_CURVE_POINTS - _original.size() - (_segments.size() + 1) * (2 * SMOOTH_STEPS + 2)):
		finish("Safe curve point budget reached")
		return
	_segment = {"points": [{"time": local, "value": control_value, "curve": "linear"}]}
	_segments.append(_segment)
	_last_position = seconds
	_monitor_value()

func _sample(seconds: float, force: bool) -> void:
	if _segment.is_empty():
		# Write and latched gestures can start when transport enters a clip.
		return
	var resolved := info()
	var local := seconds - float(resolved.offset)
	if local < 0.0: return
	local = minf(local, float(resolved.duration))
	var points: Array = _segment.points
	var last: Dictionary = points.back()
	if local < float(last.time): return
	var target_ended := seconds - float(resolved.offset) >= float(resolved.duration)
	if not force and not target_ended and local - float(last.time) < SAMPLE_SECONDS: return
	var point := {"time": local, "value": control_value, "curve": "linear"}
	if absf(local - float(last.time)) <= 0.0000001:
		points[points.size() - 1] = point
		return
	if points.size() >= 2:
		var previous: Dictionary = points[points.size() - 2]
		var fraction := (float(last.time) - float(previous.time)) / maxf(0.000001, local - float(previous.time))
		var expected := lerpf(float(previous.value), control_value, fraction)
		if absf(expected - float(last.value)) <= _tolerance:
			points[points.size() - 1] = point
		else: points.append(point)
	else: points.append(point)
	if not force:
		var limit := mini(MAX_PASS_POINTS, MAX_CURVE_POINTS - _original.size() - _segments.size() * (2 * SMOOTH_STEPS + 2))
		if _point_count() >= limit - 1: finish("Safe curve point budget reached")
		elif seconds - float(resolved.offset) >= float(resolved.duration): finish("Target range ended")

func _point_count() -> int:
	var count := 0
	for segment in _segments: count += (segment.points as Array).size()
	return count

func _end_segment(seconds: float) -> void:
	if _segment.is_empty(): return
	_sample(seconds, true)
	_segment = {}

func _monitor_value() -> void:
	if not _live_monitor or not active or _segment.is_empty(): return
	if _monitor == null: _monitor = _document.snapshot()
	var resolved := KiwiAudioAutomationLane.resolve(_monitor, target)
	if resolved.is_empty(): return
	var curves: Dictionary = resolved.owner.get("automation", {})
	curves[str(resolved.parameter)] = [{"time": 0.0, "value": control_value, "curve": "hold"}]
	resolved.owner["automation"] = curves
	playback.document = _monitor
	playback.synchronize()

func _restore_monitor() -> void:
	var previous_monitor := _monitor
	_monitor = null
	if playback == null: return
	var invalidated := _document != null and session != null and (session.document != _document or session.revision != _revision)
	if invalidated:
		# Undo/another edit may replace the document before the deferred UI
		# refresh rebuilds runtime sources and recomputes exact_required.
		# Never briefly synchronize that old native model as playing.
		playback.document = session.document
		playback.stop(false)
	elif previous_monitor != null and playback.document == previous_monitor:
		playback.document = session.document if session != null else _document
		playback.synchronize()

func _splice(original: Array, segment: Dictionary) -> Array:
	var captured: Array = segment.points
	if captured.is_empty(): return original
	var start := float(captured.front().time)
	var end := float(captured.back().time)
	var left := maxf(0.0, start - BOUNDARY_SECONDS)
	var right := end + BOUNDARY_SECONDS
	var result: Array = []
	for point in original:
		if float(point.time) < left: result.append(point.duplicate(true))
	if start > 0.0:
		# Splitting a smoothstep cannot be represented by another smoothstep.
		# Subdivide only the affected outside segment; untouched points retain
		# their interpolation. Guards use a 0.1 ms transition at punch boundaries.
		if not result.is_empty() and str(result.back().get("curve", "linear")) == "smooth":
			var previous := float(result.back().time)
			result.back().curve = "linear"
			for i in range(1, SMOOTH_STEPS):
				var time := lerpf(previous, left, float(i) / SMOOTH_STEPS)
				result.append(_original_point(original, time, "linear"))
		result.append(_original_point(original, left, "hold"))
	result.append_array(captured.duplicate(true))
	result.back().curve = "hold"
	var curve := _curve_at(original, right)
	result.append(_original_point(original, right, "linear" if curve == "smooth" else curve))
	var next := -1.0
	for point in original:
		if float(point.time) > right:
			next = float(point.time)
			break
	if curve == "smooth" and next > right:
		for i in range(1, SMOOTH_STEPS):
			var time := lerpf(right, next, float(i) / SMOOTH_STEPS)
			result.append(_original_point(original, time, "linear"))
	for point in original:
		if float(point.time) > right: result.append(point.duplicate(true))
	return result

func _original_point(original: Array, seconds: float, curve: String) -> Dictionary:
	return {"time": seconds, "value": KiwiAudioAutomationLane.value(original, seconds, _fallback), "curve": curve}

func _curve_at(points: Array, seconds: float) -> String:
	if points.is_empty() or seconds < float(points.front().time): return "hold"
	for i in range(1, points.size()):
		if seconds < float(points[i].time): return str(points[i - 1].get("curve", "linear"))
	return "hold"
