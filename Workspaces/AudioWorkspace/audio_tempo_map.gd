class_name KiwiAudioTempoMap
extends RefCounted
## Source-relative, quarter-note MIDI timing. Build once per note source, then
## use binary lookup for note boundaries. MIDI microseconds are authoritative;
## saved source BPM is only the fallback for ordinary, unmapped instrument patterns.
## Same-beat events use file encounter order: the last event takes effect.
const MAX_EVENTS := 4096
const MAX_SOURCES := 128
const MAX_MAP_COPIES := 65536
const MAX_SOURCE_CHANNEL_EVENTS := 16384
const MAX_TOTAL_CHANNEL_EVENTS := 131072
const MAX_TOTAL_NOTES := 65536
const MAX_SOURCE_NOTES := 8192
const MAX_BEAT := 10000000.0
const MIN_SCALE := 0.000001
const MAX_SCALE := 1000000.0
var segments: Array[Dictionary] = []
var error := ""

func _init(tempos: Array = [], bpm: float = 120.0, time_scale: float = 1.0) -> void:
	error = validate_tempos(tempos)
	if error.is_empty() and not _number_in(time_scale, MIN_SCALE, MAX_SCALE): error = "MIDI tempo scale must be finite and between 0.000001 and 1000000."
	if not error.is_empty(): return
	var scale := KiwiAudioSynthesis.finite(time_scale, 1.0)
	if scale <= 0.0: scale = 1.0
	var events := canonical(tempos, bpm)
	var seconds := 0.0
	var previous_beat := 0.0
	var previous_rate := 0.5 * scale
	for event: Dictionary in events:
		var beat := float(event.beat)
		seconds += (beat - previous_beat) * previous_rate
		var rate := float(event.microseconds) / 1000000.0 * scale
		segments.append({"beat": beat, "seconds": seconds, "seconds_per_beat": rate})
		previous_beat = beat
		previous_rate = rate

static func canonical(tempos: Array, bpm: float = 120.0) -> Array[Dictionary]:
	if not validate_tempos(tempos).is_empty(): return []
	var sorted: Array[Dictionary] = []
	for i in tempos.size():
		var entry: Variant = tempos[i]
		if not entry is Dictionary: continue
		var beat := KiwiAudioSynthesis.finite(entry.get("beat", 0.0), 0.0)
		var rate := KiwiAudioSynthesis.finite(entry.get("microseconds", 0.0), 0.0)
		if rate <= 0.0:
			var event_bpm := KiwiAudioSynthesis.finite(entry.get("bpm", 120.0), 120.0)
			rate = 60000000.0 / maxf(0.000001, event_bpm)
		sorted.append({"beat": maxf(0.0, beat), "microseconds": rate, "order": i})
	sorted.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.beat) < float(b.beat) if float(a.beat) != float(b.beat) else int(a.order) < int(b.order))
	var result: Array[Dictionary] = []
	# SMF starts at 120 BPM before the first event. For an unmapped pattern,
	# retain the existing 20..400 source-BPM range.
	var initial := 60000000.0 / clampf(KiwiAudioSynthesis.finite(bpm, 120.0), 20.0, 400.0) if tempos.is_empty() else 500000.0
	result.append({"beat": 0.0, "microseconds": initial, "bpm": 60000000.0 / initial})
	for event: Dictionary in sorted:
		var point := {"beat": float(event.beat), "microseconds": float(event.microseconds), "bpm": 60000000.0 / float(event.microseconds)}
		if float(result.back().beat) == float(event.beat): result[result.size() - 1] = point
		else: result.append(point)
	var compact: Array[Dictionary] = []
	for point: Dictionary in result:
		if compact.is_empty() or float(compact.back().microseconds) != float(point.microseconds): compact.append(point)
	return compact

func beat_to_seconds(beat: float) -> float:
	if not error.is_empty(): return INF
	var target := maxf(0.0, KiwiAudioSynthesis.finite(beat, 0.0))
	var index := _segment(target, "beat")
	return float(segments[index].seconds) + (target - float(segments[index].beat)) * float(segments[index].seconds_per_beat)

func seconds_to_beat(seconds: float) -> float:
	if not error.is_empty(): return INF
	var target := maxf(0.0, KiwiAudioSynthesis.finite(seconds, 0.0))
	var index := _segment(target, "seconds")
	return float(segments[index].beat) + (target - float(segments[index].seconds)) / float(segments[index].seconds_per_beat)

func _segment(value: float, field: String) -> int:
	var low := 0
	var high := segments.size()
	while low + 1 < high:
		var middle := (low + high) / 2
		if float(segments[middle][field]) <= value: low = middle
		else: high = middle
	return low

static func scaled_events(tempos: Array, bpm: float, time_scale: float = 1.0) -> Array[Dictionary]:
	if not validate_tempos(tempos).is_empty() or not _number_in(time_scale, MIN_SCALE, MAX_SCALE): return []
	# Export retains the original event list, including redundant/same-beat
	# events; canonical() is only the effective timing lookup/comparison.
	var result: Array[Dictionary] = []
	for entry: Variant in tempos:
		if not entry is Dictionary: continue
		var point: Dictionary = entry.duplicate(true)
		var microseconds := KiwiAudioSynthesis.finite(point.get("microseconds", 0.0), 0.0)
		if microseconds <= 0.0: microseconds = 60000000.0 / maxf(0.000001, KiwiAudioSynthesis.finite(point.get("bpm", 120.0), 120.0))
		point["microseconds"] = microseconds
		result.append(point)
	if result.is_empty(): result = canonical([], bpm)
	var scale := maxf(0.000001, KiwiAudioSynthesis.finite(time_scale, 1.0))
	for event: Dictionary in result:
		event.microseconds = float(event.microseconds) * scale
		event.bpm = 60000000.0 / float(event.microseconds)
	return result

static func validate_tempos(value: Variant, allow_empty: bool = true) -> String:
	if not value is Array or value.size() > MAX_EVENTS: return "MIDI tempo maps must be arrays of at most 4096 events."
	if not allow_empty and value.is_empty(): return "The MIDI source tempo map is empty. Reimport the MIDI source."
	for point: Variant in value:
		if not point is Dictionary: return "Invalid MIDI tempo event."
		for key: Variant in point:
			if str(key) not in ["beat", "bpm", "microseconds"]: return "Unsupported MIDI tempo event field."
		if not _number_in(point.get("beat", 0.0), 0.0, MAX_BEAT): return "Invalid MIDI tempo event beat."
		if not point.has("microseconds") and not point.has("bpm"): return "MIDI tempo events need microseconds or BPM."
		if point.has("microseconds") and not _number_in(point.microseconds, 1.0, 0xffffff): return "MIDI tempo microseconds must be between 1 and 16777215."
		if point.has("bpm") and not _number_in(point.bpm, 60000000.0 / 0xffffff, 60000000.0): return "Invalid MIDI event BPM."
	return ""

static func validate_meters(value: Variant) -> String:
	if not value is Array or value.size() > MAX_EVENTS: return "MIDI meter maps must be arrays of at most 4096 events."
	for point: Variant in value:
		if not point is Dictionary: return "Invalid MIDI meter event."
		for key: Variant in point:
			if str(key) not in ["beat", "numerator", "denominator", "clocks_per_click", "thirty_seconds"]: return "Unsupported MIDI meter event field."
		if not _number_in(point.get("beat", 0.0), 0.0, MAX_BEAT): return "Invalid MIDI meter event beat."
		if not _integer_in(point.get("numerator", 4), 1, 255) or not _integer_in(point.get("denominator", 4), 1, 128): return "Invalid MIDI time signature."
		var denominator := int(point.get("denominator", 4))
		if (denominator & (denominator - 1)) != 0: return "MIDI meter denominators must be powers of two."
		for key in ["clocks_per_click", "thirty_seconds"]:
			if point.has(key) and not _integer_in(point[key], 0, 255): return "Invalid MIDI meter metadata."
	return ""

static func validate_channel_events(value: Variant) -> String:
	if not value is Array or value.size() > MAX_SOURCE_CHANNEL_EVENTS: return "Each MIDI source may contain at most 16384 channel events."
	for event: Variant in value:
		if not event is Dictionary: return "Invalid MIDI channel event."
		for key: Variant in event:
			if str(key) not in ["beat", "type", "controller", "value", "program", "pitch"]: return "Unsupported MIDI channel event field."
		if not _number_in(event.get("beat", 0.0), 0.0, MAX_BEAT): return "Invalid MIDI channel event beat."
		var kind := str(event.get("type", ""))
		if kind not in ["control_change", "program_change", "pitch_bend", "poly_pressure", "channel_pressure"]: return "Unsupported MIDI channel event type."
		for key in ["controller", "program", "pitch"]:
			if event.has(key) and not _integer_in(event[key], 0, 127): return "Invalid MIDI channel event data."
		if event.has("value") and not _integer_in(event.value, 0, 16383 if kind == "pitch_bend" else 127): return "Invalid MIDI channel event value."
	return ""

static func validate_source(owner: Dictionary) -> String:
	if owner.has("midi_sustain") and not owner["midi_sustain"] is bool: return "MIDI sustain-render policy must be a boolean."
	if owner.has("source_bpm") and not _number_in(owner["source_bpm"], 20.0, 400.0): return "Note-source BPM must be between 20 and 400."
	if owner.has("source_meter"):
		var meter: Variant = owner["source_meter"]
		if not meter is Array or meter.size() != 2: return "Invalid note-source meter."
		if not _integer_in(meter[0], 1, 32) or not _integer_in(meter[1], 1, 32): return "Invalid note-source meter."
		if int(meter[1]) not in [1, 2, 4, 8, 16, 32]: return "Invalid note-source meter denominator."
	if owner.has("midi_tempos"):
		var problem := validate_tempos(owner["midi_tempos"], false)
		if not problem.is_empty(): return problem
	if owner.has("midi_tempo_scale"):
		if not owner.has("midi_tempos"): return "A MIDI tempo scale needs a source tempo map."
		if not _number_in(owner["midi_tempo_scale"], MIN_SCALE, MAX_SCALE): return "MIDI tempo scale must be finite and between 0.000001 and 1000000."
	if owner.has("notes_source_scale") and not _number_in(owner["notes_source_scale"], MIN_SCALE, MAX_SCALE): return "Invalid pending note-source time scale."
	if owner.has("midi_time_signatures"):
		var problem := validate_meters(owner["midi_time_signatures"])
		if not problem.is_empty(): return problem
	if owner.has("midi_events"):
		var problem := validate_channel_events(owner["midi_events"])
		if not problem.is_empty(): return problem
	return ""

static func validate_budget(sources: Array, legacy: Dictionary = {}) -> String:
	var problem := validate_source(legacy)
	if not problem.is_empty(): return problem
	var map_copies := (legacy.get("midi_tempos", []) as Array).size() + (legacy.get("midi_time_signatures", []) as Array).size()
	var source_count := 0
	var note_count := 0
	var event_count := 0
	for source: Variant in sources:
		if not source is Dictionary: return "Invalid MIDI source metadata."
		problem = validate_source(source)
		if not problem.is_empty(): return problem
		if not source.has("midi_tempos") and not source.has("midi_events") and not source.has("midi_time_signatures"): continue
		source_count += 1
		map_copies += (source.get("midi_tempos", []) as Array).size() + (source.get("midi_time_signatures", []) as Array).size()
		event_count += (source.get("midi_events", []) as Array).size()
		var notes: Variant = source.get("notes", [])
		if not notes is Array or notes.size() > MAX_SOURCE_NOTES: return "Each MIDI source may contain at most 8192 notes."
		note_count += notes.size()
		if source_count > MAX_SOURCES: return "The composition exceeds the limit of 128 MIDI note sources."
		if map_copies > MAX_MAP_COPIES: return "The composition exceeds the limit of 65536 copied MIDI tempo/meter events."
		if note_count > MAX_TOTAL_NOTES: return "The composition exceeds the limit of 65536 imported MIDI notes."
		if event_count > MAX_TOTAL_CHANNEL_EVENTS: return "The composition exceeds the limit of 131072 MIDI channel events."
	return ""

static func _number_in(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _integer_in(value: Variant, low: int, high: int) -> bool:
	return _number_in(value, low, high) and float(value) == floor(float(value))
