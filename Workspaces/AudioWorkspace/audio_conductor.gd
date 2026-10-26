class_name KiwiAudioConductor
extends RefCounted
## Project musical reference. Seconds remain the authoritative clip coordinate.
## Tempo points are steps; each meter point starts a new bar, even mid-bar.
const MAX_POINTS := 1024
const MAX_BEAT := 10000000.0
const MIN_GAP := 0.000001
var timing: KiwiAudioTempoMap
var meters: Array[Dictionary] = []
var error := ""

func _init(bpm: float = 120.0, signature: Vector2i = Vector2i(4, 4), tempos: Array = [], signatures: Array = []) -> void:
	error = validate(bpm, signature, tempos, signatures)
	if not error.is_empty(): return
	var events: Array = [{"beat": 0.0, "bpm": bpm}]
	events.append_array(tempos)
	timing = KiwiAudioTempoMap.new(events, bpm)
	meters.append({"beat": 0.0, "numerator": signature.x, "denominator": signature.y, "bar": 1})
	for point: Dictionary in signatures:
		var previous: Dictionary = meters.back()
		var length := float(previous.numerator) * 4.0 / float(previous.denominator)
		var bars := maxi(1, ceili((float(point.beat) - float(previous.beat)) / length - 0.00000001))
		meters.append({"beat": float(point.beat), "numerator": int(point.numerator), "denominator": int(point.denominator), "bar": int(previous.bar) + bars})

static func validate(bpm: float, signature: Vector2i, tempos: Variant, signatures: Variant) -> String:
	if not _number(bpm, 20.0, 400.0): return "Project tempo must be between 20 and 400 BPM."
	if not _meter(signature.x, signature.y): return "Project meter must be 1–32 over 1, 2, 4, 8, 16 or 32."
	for kind in ["tempo", "meter"]:
		var points: Variant = tempos if kind == "tempo" else signatures
		if not points is Array or points.size() > MAX_POINTS: return "Each project conductor lane supports at most 1024 points."
		var previous := 0.0
		for point: Variant in points:
			if not point is Dictionary: return "Invalid project conductor point."
			var allowed := ["beat", "bpm"] if kind == "tempo" else ["beat", "numerator", "denominator"]
			for key: Variant in point:
				if str(key) not in allowed: return "Unsupported project conductor point field."
			if not _number(point.get("beat"), MIN_GAP, MAX_BEAT): return "Conductor points need a finite quarter-note beat after zero."
			if float(point.beat) - previous < MIN_GAP: return "Conductor points must be ordered with distinct beats. Edit the initial value separately."
			previous = float(point.beat)
			if kind == "tempo":
				if not _number(point.get("bpm"), 20.0, 400.0): return "Conductor tempo must be between 20 and 400 BPM."
			elif not _meter(point.get("numerator"), point.get("denominator")): return "Invalid conductor meter."
	return ""

static func _number(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _meter(numerator: Variant, denominator: Variant) -> bool:
	return _number(numerator, 1, 32) and float(numerator) == floor(float(numerator)) and _number(denominator, 1, 32) and float(denominator) == floor(float(denominator)) and int(denominator) in [1, 2, 4, 8, 16, 32]

func beat_to_seconds(beat: float) -> float:
	return timing.beat_to_seconds(beat) if timing != null else 0.0

func seconds_to_beat(seconds: float) -> float:
	return timing.seconds_to_beat(seconds) if timing != null else 0.0

func tempo_at(seconds: float) -> float:
	if timing == null: return 120.0
	var index := timing._segment(maxf(0.0, seconds), "seconds")
	return 60.0 / float(timing.segments[index].seconds_per_beat)

func beat_info(beat: float) -> Dictionary:
	if meters.is_empty(): return {"bar": 1, "beat": 1, "phase": 0.0, "downbeat": true, "key": "0:0", "unit": 1.0, "quarter": 0.0, "origin": 0.0, "end": INF, "numerator": 4, "denominator": 4}
	beat = maxf(0.0, beat)
	var low := 0
	var high := meters.size()
	while low + 1 < high:
		var middle := (low + high) / 2
		if float(meters[middle].beat) <= beat: low = middle
		else: high = middle
	var point: Dictionary = meters[low]
	var unit := 4.0 / float(point.denominator)
	var ticks := maxf(0.0, (beat - float(point.beat)) / unit)
	var tick := floori(ticks + 0.000000001)
	var within := tick % int(point.numerator)
	return {"bar": int(point.bar) + floori(float(tick) / float(point.numerator)), "beat": within + 1, "phase": maxf(0.0, ticks - tick), "downbeat": within == 0, "key": str(low) + ":" + str(tick), "unit": unit, "quarter": float(point.beat) + tick * unit, "origin": float(point.beat), "end": float(meters[low + 1].beat) if low + 1 < meters.size() else INF, "numerator": int(point.numerator), "denominator": int(point.denominator)}

func position_text(seconds: float) -> String:
	var point := beat_info(seconds_to_beat(seconds))
	return "%d.%d.%03d" % [int(point.bar), int(point.beat), mini(999, floori(float(point.phase) * 1000.0))]

func snap_seconds(seconds: float, step: float) -> float:
	if not is_finite(step) or step <= 0.0: return maxf(0.0, seconds)
	var beat := seconds_to_beat(seconds)
	var meter := beat_info(beat)
	var lower := float(meter.origin) + floorf((beat - float(meter.origin)) / step) * step
	var a := beat_to_seconds(maxf(float(meter.origin), lower))
	var b := beat_to_seconds(minf(lower + step, float(meter.end)))
	# Nearest in seconds, including intervals that straddle a tempo point.
	return maxf(0.0, a if absf(seconds - a) <= absf(seconds - b) else b)

func grid(first: float, last: float, pixels_per_second: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_finite(first) or not is_finite(last) or not is_finite(pixels_per_second) or pixels_per_second <= 0.0: return result
	first = maxf(0.0, first)
	if last <= first or timing == null: return result
	var first_beat := seconds_to_beat(first)
	var last_beat := seconds_to_beat(last)
	# One shared viewport budget, not a fresh budget for every meter segment.
	# Retain visible meter starts, then distribute ordinary ticks across the
	# entire window so early segments cannot exhaust the right-hand grid.
	var maximum := clampi(ceili(minf(2048.0, (last - first) * pixels_per_second / 6.0)), 16, 2048)
	var spans: Array[Dictionary] = []
	var total_width := 0.0
	for i in meters.size():
		var meter: Dictionary = meters[i]
		var next := float(meters[i + 1].beat) if i + 1 < meters.size() else INF
		if next <= first_beat or float(meter.beat) > last_beat: continue
		var unit := 4.0 / float(meter.denominator)
		var first_tick := maxi(0, ceili((first_beat - float(meter.beat)) / unit))
		var last_tick := floori((minf(last_beat, next) - float(meter.beat)) / unit)
		if float(meter.beat) + last_tick * unit >= next: last_tick -= 1
		if first_tick > last_tick: continue
		if first_tick == 0:
			var info := beat_info(float(meter.beat))
			info["seconds"] = beat_to_seconds(float(meter.beat))
			result.append(info)
			first_tick = 1
		if first_tick > last_tick: continue
		var start := maxf(first, beat_to_seconds(float(meter.beat)))
		var end := minf(last, beat_to_seconds(next)) if is_finite(next) else last
		var width := maxf(0.0, end - start)
		if width <= 0.0: continue
		spans.append({"meter": meter, "unit": unit, "first": first_tick, "last": last_tick, "width": width})
		total_width += width
	# At most 1025 meter starts exist. Reserve a small ordinary-tick allowance
	# even when dense changes already exceed the pixel-based soft limit.
	var budget := mini(2048 - result.size(), maxi(16, maximum - result.size()))
	var cumulative_width := 0.0
	var allocated := 0
	for index in spans.size():
		var span: Dictionary = spans[index]
		cumulative_width += float(span.width)
		var cumulative := budget if index == spans.size() - 1 else mini(budget, floori(budget * cumulative_width / total_width))
		var allowance := cumulative - allocated
		allocated = cumulative
		if allowance <= 0: continue
		var meter: Dictionary = span.meter
		var first_tick := int(span.first)
		var last_tick := int(span.last)
		var count := last_tick - first_tick + 1
		var stride := 1
		if count > allowance: stride = int(meter.numerator) * maxi(1, ceili(float(count) / allowance / float(meter.numerator)))
		first_tick = ceili(float(first_tick) / stride) * stride
		var before := result.size()
		for tick in range(first_tick, last_tick + 1, stride):
			var beat := float(meter.beat) + tick * float(span.unit)
			var seconds := beat_to_seconds(beat)
			var info := beat_info(beat)
			info["seconds"] = seconds
			result.append(info)
		# Bar-aligned thinning can otherwise leave nearly a whole stride blank
		# at a segment's right edge. Keep its final visible bar (or beat when
		# there is no full bar) within this segment's existing allowance.
		var final_tick := last_tick
		if stride > 1:
			var final_bar := floori(float(last_tick) / float(meter.numerator)) * int(meter.numerator)
			if final_bar >= int(span.first): final_tick = final_bar
		var final_beat := float(meter.beat) + final_tick * float(span.unit)
		var final_seconds := beat_to_seconds(final_beat)
		if result.size() == before or float(result.back().seconds) < final_seconds:
			var info := beat_info(final_beat)
			info["seconds"] = final_seconds
			if result.size() - before >= allowance: result[result.size() - 1] = info
			else: result.append(info)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.seconds) < float(b.seconds))
	return result
