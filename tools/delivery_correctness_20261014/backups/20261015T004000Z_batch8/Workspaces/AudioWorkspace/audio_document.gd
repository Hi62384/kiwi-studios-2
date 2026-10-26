class_name KiwiAudioDocument
extends Resource
## Versioned composition. Source resources are immutable/shared by undo snapshots.
const CURRENT_VERSION := 1
@export var version: int = CURRENT_VERSION
@export var title: String = "Untitled Audio"
@export var actors: Array[ActorData] = []
@export var clips: Array[ActorClip] = []
@export var tracks: Array[Dictionary] = []
@export var tempo: float = 120.0
@export var time_signature: Vector2i = Vector2i(4, 4)
@export var tempo_points: Array[Dictionary] = []
@export var meter_points: Array[Dictionary] = []
# Zero sentinels keep old compositions compatible. Conductor edits pin these
# fallback source values without touching locked actors or immutable audio.
@export var note_base_tempo: float = 0.0
@export var note_base_meter: Vector2i = Vector2i.ZERO
@export var key: int = 0
@export var scale: String = "minor"
@export var markers: Array[Dictionary] = []
@export var sections: Array[Dictionary] = []
@export var chords: Array = []
@export var composer_settings: Dictionary = {}
@export var master: Dictionary = {"volume_db": -3.0, "effects": [], "automation": {}}
@export var loop_start: float = 0.0
@export var loop_end: float = 4.0
@export var loop_enabled: bool = false
@export var presets: Dictionary = {}
@export var takes: Array[Dictionary] = []
@export var workspace_state: Dictionary = {}
@export var output_path: String = ""
# Stable destination reference only. Never stores nodes, callable bindings or PCM.
@export var scene_binding: Dictionary = {}

func add_track(label: String = "Audio", kind: String = "audio") -> Dictionary:
	var palette := ["63d9bc", "80aaff", "e4b868", "d695ec", "ef8588", "73cddd"]
	var track := {"id": ActorData.new_id(), "name": label, "kind": kind, "color": Color(palette[tracks.size() % palette.size()]),
		"volume_db": 0.0, "pan": 0.0, "mute": false, "solo": false, "locked": false,
		"group": "", "output": "", "sends": [], "effects": [], "automation": {}, "instrument": {"id": "poly"}}
	tracks.append(track)
	return track

func track_for_id(id: String) -> Dictionary:
	for track in tracks:
		if str(track.get("id", "")) == id: return track
	return {}

func actor_for_clip(id: String) -> ActorData:
	for index in mini(clips.size(), actors.size()):
		if clips[index] != null and clips[index].id == id: return actors[index]
	return null

func clip_for_id(id: String) -> ActorClip:
	for clip in clips:
		if clip != null and clip.id == id: return clip
	return null

func track_for_clip(id: String) -> Dictionary:
	var actor := actor_for_clip(id)
	return track_for_id(str(actor.values.get(&"track_id", ""))) if actor != null else {}

func conductor() -> KiwiAudioConductor:
	return KiwiAudioConductor.new(tempo, time_signature, tempo_points, meter_points)

func note_tempo() -> float:
	return note_base_tempo if note_base_tempo > 0.0 else tempo

func note_meter() -> Vector2i:
	return note_base_meter if note_base_meter != Vector2i.ZERO else time_signature

func arrangement_tempo() -> float:
	return clampf(KiwiAudioSynthesis.finite(composer_settings.get("tempo", note_tempo()), note_tempo()), 20.0, 400.0)

func duration() -> float:
	var result := 0.0
	for clip in clips:
		if clip != null: result = maxf(result, clip.start_time + clip.duration)
	for section in sections: result = maxf(result, (float(section.get("start", 0)) + float(section.get("duration", 0))) * 60.0 / arrangement_tempo())
	return result

func snapshot() -> KiwiAudioDocument:
	var copy := KiwiAudioDocument.new()
	copy.version = version
	copy.title = title
	copy.tempo = tempo
	copy.time_signature = time_signature
	copy.tempo_points = tempo_points.duplicate(true)
	copy.meter_points = meter_points.duplicate(true)
	copy.note_base_tempo = note_base_tempo
	copy.note_base_meter = note_base_meter
	copy.key = key
	copy.scale = scale
	copy.tracks = tracks.duplicate(true)
	copy.markers = markers.duplicate(true)
	copy.sections = sections.duplicate(true)
	copy.chords = chords.duplicate(true)
	copy.composer_settings = composer_settings.duplicate(true)
	copy.master = master.duplicate(true)
	copy.loop_start = loop_start
	copy.loop_end = loop_end
	copy.loop_enabled = loop_enabled
	copy.presets = presets.duplicate(true)
	copy.takes = takes.duplicate(true)
	copy.workspace_state = workspace_state.duplicate(true)
	copy.output_path = output_path
	copy.scene_binding = scene_binding.duplicate(true)
	for actor in actors:
		var duplicate_actor := ActorData.new()
		duplicate_actor.id = actor.id
		duplicate_actor.type_id = actor.type_id
		duplicate_actor.display_name = actor.display_name
		duplicate_actor.parent_id = actor.parent_id
		duplicate_actor.section_id = actor.section_id
		duplicate_actor.show_timeline_children = actor.show_timeline_children
		duplicate_actor.link_timeline_children = actor.link_timeline_children
		duplicate_actor.schema_version = actor.schema_version
		duplicate_actor.values = actor.values.duplicate(true)
		# Dictionary.duplicate does not duplicate immutable audio Resources.
		for animation in actor.animation_tracks: duplicate_actor.animation_tracks.append(animation.copy_track())
		copy.actors.append(duplicate_actor)
	for clip in clips: copy.clips.append(clip.duplicate(false))
	return copy

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	var conductor_error := KiwiAudioConductor.validate(tempo, time_signature, tempo_points, meter_points)
	if not conductor_error.is_empty(): errors.append(conductor_error)
	if note_base_tempo != 0.0 and not _number_in(note_base_tempo, 20, 400): errors.append("Invalid fallback note-source tempo.")
	if note_base_meter != Vector2i.ZERO and not KiwiAudioConductor._meter(note_base_meter.x, note_base_meter.y): errors.append("Invalid fallback note-source meter.")
	if not scene_binding.is_empty():
		if scene_binding.size() > 4 or scene_binding.get("version", 0) != 1: errors.append("Unsupported scene association.")
		for field in ["scene_uid", "scene_path", "actor_id"]:
			if not scene_binding.get(field, "") is String or str(scene_binding.get(field, "")).length() > (4096 if field == "scene_path" else 128): errors.append("Invalid scene association field.")
		if str(scene_binding.get("scene_uid", "")).is_empty(): errors.append("Scene association identity is missing.")
	var midi_error := midi_timing_error()
	if not midi_error.is_empty(): errors.append(midi_error)
	if version < 1 or version > CURRENT_VERSION: errors.append("Unsupported audio document version.")
	if actors.size() != clips.size(): errors.append("Audio actors and clips have different lengths.")
	if not is_finite(tempo) or tempo < 20.0 or tempo > 400.0: errors.append("Tempo must be between 20 and 400 BPM.")
	if time_signature.x < 1 or time_signature.x > 32 or not time_signature.y in [1, 2, 4, 8, 16, 32]: errors.append("Invalid time signature.")
	if key < 0 or key > 11: errors.append("Invalid musical key.")
	if not is_finite(loop_start) or not is_finite(loop_end) or loop_start < 0 or loop_end < loop_start: errors.append("Invalid loop range.")
	_validate_owner(master, "Master", errors)
	var ids := {}
	var routes: Dictionary = {}
	for track in tracks:
		var id := str(track.get("id", ""))
		if id.is_empty() or ids.has(id): errors.append("Invalid or duplicate track identifier.")
		ids[id] = true
		_validate_owner(track, "Track", errors)
		if track.has("automation_target"):
			var target: Variant = track.automation_target
			if not target is Dictionary: errors.append("Automation lane target must be a dictionary.")
			elif not target.is_empty():
				if not str(target.get("owner_kind", "")) in ["clip", "track", "master"]: errors.append("Invalid automation lane owner kind.")
				for field in ["owner_id", "effect_id", "parameter"]:
					if not target.get(field, "") is String or str(target.get(field, "")).length() > 512: errors.append("Invalid automation lane target field.")
				if str(target.get("parameter", "")).is_empty(): errors.append("Automation lane parameter is missing.")
		var targets: Array[String] = []
		var output := str(track.get("output", ""))
		if not output.is_empty(): targets.append(output)
		if not track.get("sends", []) is Array: errors.append("Track sends must be an array.")
		else:
			for send in track.get("sends", []):
				if not send is Dictionary: errors.append("Invalid track send."); continue
				var target := str(send.get("target", ""))
				if target.is_empty(): errors.append("A track send target is missing.")
				else: targets.append(target)
				if not _number_in(send.get("volume_db", -12.0), -120, 24): errors.append("Invalid send level.")
		routes[id] = targets
	# Kahn's algorithm handles arbitrarily deep routing without recursive stack growth.
	var incoming := {}
	for id in ids: incoming[id] = 0
	for id in routes:
		for target in routes[id]:
			if not ids.has(target): errors.append("A track output or send target is missing.")
			else: incoming[target] += 1
	var ready: Array = []
	for id in incoming:
		if incoming[id] == 0: ready.append(id)
	var visited := 0
	while not ready.is_empty():
		var id: String = ready.pop_back()
		visited += 1
		for target in routes.get(id, []):
			if not incoming.has(target): continue
			incoming[target] -= 1
			if incoming[target] == 0: ready.append(target)
	if visited != ids.size(): errors.append("Track output or send routing contains a feedback cycle.")
	var clip_ids := {}
	var actor_ids := {}
	for index in mini(actors.size(), clips.size()):
		var clip := clips[index]
		var actor := actors[index]
		if clip == null or actor == null: errors.append("An audio clip or source actor is missing."); continue
		if clip_ids.has(clip.id) or clip.id.is_empty(): errors.append("Invalid or duplicate clip identifier.")
		clip_ids[clip.id] = true
		if actor_ids.has(actor.id) or actor.id.is_empty(): errors.append("Invalid or duplicate audio actor identifier.")
		actor_ids[actor.id] = true
		if clip.actor_id != actor.id: errors.append("Clip source reference does not match its actor.")
		if not ids.has(str(actor.values.get(&"track_id", ""))): errors.append("Clip track is missing.")
		if not is_finite(clip.start_time) or not is_finite(clip.duration) or clip.start_time < 0 or clip.duration <= 0: errors.append("Clip has an invalid time range.")
		if not is_finite(clip.source_offset) or clip.source_offset < 0: errors.append("Clip has an invalid source offset.")
		if not _number_in(actor.values.get(&"pitch", 1.0), 0.05, 16): errors.append("Invalid clip pitch.")
		if not is_finite(clip.playback_speed) or clip.playback_speed < 0.05 or clip.playback_speed > 16: errors.append("Invalid clip speed.")
		for field in [&"fade_in", &"fade_out"]:
			if not _number_in(actor.values.get(field, 0), 0, 86400): errors.append("Invalid clip fade.")
		_validate_owner(actor.values, "Clip", errors)
		var source: Variant = actor.values.get(&"audio")
		if source != null and not source is String and not source is AudioStream: errors.append("Unsupported audio source reference.")
		var notes: Variant = actor.values.get(&"notes", [])
		if not notes is Array: errors.append("Pattern notes must be an array.")
		else:
			for note in notes:
				if not note is Dictionary: errors.append("Invalid pattern note."); continue
				if not _number_in(note.get("start", 0), 0, 10000000) or not _number_in(note.get("duration", 0.25), 0.000001, 10000000) or not _number_in(note.get("pitch", 60), 0, 127) or not _number_in(note.get("velocity", 0.8), 0, 1): errors.append("Invalid note time, pitch or velocity.")
	for marker in markers:
		if not _number_in(marker.get("time", 0), 0, 10000000): errors.append("Invalid cue marker time.")
	for section in sections:
		if not _number_in(section.get("start", 0), 0, 10000000) or not _number_in(section.get("duration", 1), 0.000001, 10000000): errors.append("Invalid arrangement section.")
	return errors

func midi_timing_error(additional: Array = [], replaced_actor_id: String = "", legacy_override: Variant = null) -> String:
	# This gathers references only. Validate aggregate bounds before any
	# per-source map duplication, render copies, import action or preset apply.
	var sources: Array = []
	for actor in actors:
		if actor != null and (replaced_actor_id.is_empty() or actor.id != replaced_actor_id): sources.append(actor.values)
	sources.append_array(additional)
	var legacy: Dictionary = composer_settings if legacy_override == null else legacy_override
	return KiwiAudioTempoMap.validate_budget(sources, legacy)

static func _number_in(value: Variant, low: float, high: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= low and float(value) <= high

static func _validate_owner(owner: Dictionary, label: String, errors: PackedStringArray) -> void:
	if not _number_in(owner.get("volume_db", 0), -120, 60) or not _number_in(owner.get("pan", 0), -1, 1): errors.append(label + " has an invalid gain or pan.")
	_validate_automation(owner.get("automation", {}), label, errors)
	var effects: Variant = owner.get("effects", [])
	if not effects is Array: errors.append(label + " effects must be an array."); return
	var ids := {}
	for effect in effects:
		if not effect is Dictionary: errors.append(label + " contains an invalid effect."); continue
		var id := str(effect.get("id", ""))
		if id.is_empty() or ids.has(id): errors.append(label + " contains invalid or duplicate effect identifiers.")
		ids[id] = true
		if str(effect.get("type", "")).is_empty() or not effect.get("parameters", {}) is Dictionary: errors.append(label + " contains malformed effect parameters.")
		else:
			for value in effect.get("parameters", {}).values():
				if value is float and not is_finite(value): errors.append(label + " contains non-finite effect parameters.")
		_validate_automation(effect.get("automation", {}), label + " effect", errors)

static func _validate_automation(automation: Variant, label: String, errors: PackedStringArray) -> void:
	if not automation is Dictionary: errors.append(label + " automation must be a dictionary."); return
	for points in automation.values():
		if not points is Array: errors.append(label + " automation points must be an array."); continue
		if points.size() > 10000: errors.append(label + " automation has more than 10000 points per curve.")
		for point in points:
			if not point is Dictionary: errors.append(label + " contains an invalid automation point."); continue
			if not _number_in(point.get("time", 0), 0, 10000000) or not _number_in(point.get("value", 0), -10000000, 10000000): errors.append(label + " has invalid automation values.")
			if not str(point.get("curve", "linear")) in ["linear", "smooth", "hold"]: errors.append(label + " has an unknown automation curve.")

func playback_model() -> ActorTimeline:
	var model := ActorTimeline.new()
	model.actors = actors
	model.clips = clips
	return model

static func from_source(value: Variant, label: String = "") -> KiwiAudioDocument:
	var document := KiwiAudioDocument.new()
	document.title = label if not label.is_empty() else "Untitled Audio"
	var track := document.add_track("Audio")
	if value != null:
		if ActorAudio.file_duration(value) > 0.0:
			document.insert_source(value, track.id, 0.0, label)
	return document

func insert_source(value: Variant, track_id: String, at: float, label: String = "") -> ActorClip:
	if track_for_id(track_id).is_empty() or str(track_for_id(track_id).get("kind", "")) == "automation": return null
	var seconds := ActorAudio.file_duration(value)
	if not is_finite(seconds) or seconds <= 0.0: return null
	var actor := ActorData.new()
	actor.id = ActorData.new_id()
	actor.type_id = &"audio"
	actor.display_name = label if not label.is_empty() else (str(value).get_file() if value is String else "Audio")
	actor.values = {&"audio": value, &"track_id": track_id, &"volume_db": 0.0, &"pitch": 1.0, &"muted": false,
		&"fade_in": minf(0.003, seconds * 0.1), &"fade_out": minf(0.005, seconds * 0.1),
		&"pan": 0.0, &"effects": [], &"automation": {}, &"notes": [], &"generator": {}, &"reverse": false,
		&"loop": false, &"source_duration": seconds}
	var clip := ActorClip.create(actor, maxf(0.0, at), seconds)
	clip.layer = tracks.find(track_for_id(track_id))
	actors.append(actor)
	clips.append(clip)
	return clip

