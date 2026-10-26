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
# Empty on ordinary compositions. Portable copies persist only contained tokens.
@export var portable_media: Dictionary = {}
var _portable_root: String = ""

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
	copy.portable_media = portable_media.duplicate(true)
	copy._portable_root = _portable_root
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
		if actor.values.has(&"drum_instances") or actor.values.has(&"drum_patterns"):
			var linked_error:=preload("res://Workspaces/AudioWorkspace/audio_linked_patterns.gd").validate(actor.values.get(&"drum_patterns",{}),actor.values.get(&"drum_instances",[]))
			if not linked_error.is_empty():errors.append(linked_error)
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


# Recovery is an internal, non-executable Variant format. It never loads a saved
# script or writes to a source composition. PCM lives in a shared blob store.
class Recovery extends RefCounted:
	const FORMAT := 1
	const MAGIC := "KIWIREC1"
	const MAX_METADATA := 4 * 1024 * 1024
	const MAX_BLOB := 256 * 1024 * 1024
	const MAX_STORE := 512 * 1024 * 1024
	const MAX_VISITS := 100000
	const KEEP_PER_SESSION := 3
	const KEEP_TOTAL := 24
	static var _store_mutex := Mutex.new()
	var directory := "user://audio_workspace/recovery_v1"
	var metadata_limit := MAX_METADATA
	var blob_limit := MAX_BLOB
	var store_limit := MAX_STORE
	var keep_per_session := KEEP_PER_SESSION
	var keep_total := KEEP_TOTAL
	var _error := ""
	var _visits := 0
	var _estimated := 0
	var _nodes: Array = []
	var _seen: Dictionary = {}
	var _active: Dictionary = {}
	var _blobs: Dictionary = {}
	var _assets: Dictionary = {}
	var _streams: Dictionary = {}
	var _audio_cache: Dictionary = {}
	var _work: RefCounted
	var _pending_bytes := 0

	static func freeze(document: KiwiAudioDocument) -> Dictionary:
		# Freeze all editable resource metadata on the main thread. Audio streams
		# alone follow the workspace's existing immutable-source convention.
		var codec := Recovery.new()
		codec._reset()
		var result: Variant = codec._freeze(document, 0)
		if result is KiwiAudioDocument and document != null: result._portable_root = document._portable_root
		return {"error": codec._error, "document": result}

	func _freeze(value: Variant, depth: int) -> Variant:
		_visits += 1
		if depth > 32 or _visits > MAX_VISITS or _estimated > metadata_limit: return _fail("Recovery metadata exceeds its bounded size/depth limit.")
		if not _error.is_empty(): return null
		_estimated += 16
		if value is AudioStream:
			if (not value is AudioStreamWAV and not value is AudioStreamMP3) or value.get_script() != null: return _fail("Recovery supports unscripted embedded WAV/MP3 audio only. Save this composition manually.")
			return value
		if value is Resource:
			var id: int = value.get_instance_id()
			if _active.has(id): return _fail("Recovery does not support cyclic resource metadata.")
			if _seen.has(id): return _seen[id]
			var copy := _new_resource(_kind(value))
			if copy == null or value.get_script() != copy.get_script(): return _fail("Recovery encountered unsupported embedded resource metadata; save manually.")
			_seen[id] = copy; _active[id] = true
			for field in _properties(value):
				var item: Variant = _freeze(value.get(field), depth + 1)
				if not _error.is_empty(): return null
				copy.set(field, item)
			_active.erase(id)
			return copy
		if value is Object or typeof(value) in [TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]: return _fail("Recovery encountered unsupported live object metadata; save manually.")
		if value is Array:
			var copy: Array = value.duplicate()
			for index in value.size():
				var item: Variant = _freeze(value[index], depth + 1)
				if not _error.is_empty(): return null
				copy[index] = item
			return copy
		if value is Dictionary:
			var copy: Dictionary = value.duplicate()
			for key in value:
				if key is Object or key is Array or key is Dictionary: return _fail("Recovery encountered an unsupported metadata key.")
				var item: Variant = _freeze(value[key], depth + 1)
				if not _error.is_empty(): return null
				copy[key] = item
			return copy
		if value is String or value is StringName: _estimated += str(value).length() * 4
		elif typeof(value) >= TYPE_PACKED_BYTE_ARRAY: _estimated += value.size() * 32
		return value

	static func _hex(value: String, length: int) -> bool:
		if value.length() != length: return false
		for character in value:
			if character not in "0123456789abcdef": return false
		return true

	func _root() -> String:
		return ProjectSettings.globalize_path(directory).simplify_path()

	func _cancelled() -> bool:
		return _work != null and _work.has_method("is_cancelled") and _work.is_cancelled()

	func _fail(message: String) -> Variant:
		if _error.is_empty(): _error = message
		return null

	func _reset(work: RefCounted = null) -> void:
		_error = ""; _visits = 0; _estimated = 0; _pending_bytes = 0
		_nodes = []; _seen = {}; _active = {}; _blobs = {}; _assets = {}; _streams = {}; _work = work

	static func _properties(value: Resource) -> Array[String]:
		var result: Array[String] = []
		for property in value.get_property_list():
			var field := str(property.name)
			if int(property.usage) & PROPERTY_USAGE_STORAGE and field not in ["script", "resource_path"]: result.append(field)
		return result

	static func _kind(value: Resource) -> String:
		if value is KiwiAudioDocument: return "document"
		if value is ActorData: return "actor"
		if value is ActorClip: return "clip"
		if value is ActorAnimationTrack: return "animation"
		if value is ActorKeyframe: return "key"
		if value is ActorObjectData: return "object"
		if value is ActorObjectReference: return "reference"
		if value is Curve: return "curve"
		if value is AudioStreamWAV: return "wav"
		if value is AudioStreamMP3: return "mp3"
		return ""

	static func _new_resource(kind: String) -> Resource:
		match kind:
			"document": return KiwiAudioDocument.new()
			"actor": return ActorData.new()
			"clip": return ActorClip.new()
			"animation": return ActorAnimationTrack.new()
			"key": return ActorKeyframe.new()
			"object": return ActorObjectData.new()
			"reference": return ActorObjectReference.new()
			"curve": return Curve.new()
			"wav": return AudioStreamWAV.new()
			"mp3": return AudioStreamMP3.new()
		return null

	func _wav_blob(stream: AudioStreamWAV) -> String:
		if stream.format not in [AudioStreamWAV.FORMAT_8_BITS, AudioStreamWAV.FORMAT_16_BITS]: _fail("Recovery supports PCM 8/16-bit embedded WAV only; save this source manually."); return ""
		var root := _root(); var id := stream.get_instance_id()
		var signature := "%d:%d:%s" % [stream.format, stream.mix_rate, stream.stereo]
		var cached: Dictionary = _audio_cache.get(id, {})
		if not cached.is_empty() and cached.owner.get_ref() == stream and str(cached.signature) == signature:
			if int(cached.bytes) > blob_limit: _fail("Embedded audio exceeds the recovery per-source limit; save manually."); return ""
			var location := root.path_join("blobs").path_join(str(cached.digest) + ".blob")
			if _file_size(location) == int(cached.bytes) and FileAccess.get_sha256(location) == str(cached.digest):
				_blobs[cached.digest] = int(cached.bytes); return str(cached.digest)
			if FileAccess.file_exists(location): _fail("Previously preserved recovery audio is corrupt; save manually."); return ""
			_audio_cache.erase(id) # A retained Undo source can outlive blob retention; preserve it again.
		# AudioStreamWAV.data copies the complete native PCM buffer. Native WAV
		# saving avoids that getter; the bounded worker hashes the resulting file.
		var estimate := int(round(stream.get_length() * stream.mix_rate)) * (2 if stream.stereo else 1) * (1 if stream.format == AudioStreamWAV.FORMAT_8_BITS else 2) + 1024
		var used := _used_bytes(root)
		if estimate > blob_limit: _fail("Embedded audio exceeds the recovery per-source limit; save manually."); return ""
		if used < 0 or used + estimate + metadata_limit > store_limit: _fail("Recovery storage is full. Prior checkpoints are intact; save manually."); return ""
		var temporary := root.path_join("blobs").path_join("wav.part-" + ActorData.new_id() + ".wav")
		if _cancelled(): _fail("Recovery checkpoint was cancelled."); return ""
		var error := stream.save_to_wav(temporary)
		var size := _file_size(temporary)
		if error != OK or size < 44 or size > blob_limit or _cancelled():
			if FileAccess.file_exists(temporary): DirAccess.remove_absolute(temporary)
			_fail("Recovery WAV preservation failed or was cancelled; save manually."); return ""
		var digest := FileAccess.get_sha256(temporary)
		var location := root.path_join("blobs").path_join(digest + ".blob")
		if not _hex(digest, 64) or _cancelled(): DirAccess.remove_absolute(temporary); _fail("Recovery WAV checksum failed or was cancelled."); return ""
		if FileAccess.file_exists(location):
			DirAccess.remove_absolute(temporary)
			if _file_size(location) != size or FileAccess.get_sha256(location) != digest: _fail("Existing recovery audio is corrupt."); return ""
		elif DirAccess.rename_absolute(temporary, location) != OK:
			DirAccess.remove_absolute(temporary); _fail("Recovery WAV could not be published."); return ""
		_audio_cache[id] = {"owner": weakref(stream), "signature": signature, "digest": digest, "bytes": size}
		# Weak identities never retain source audio; cap obsolete cache metadata.
		if _audio_cache.size() > 1024:
			for key in _audio_cache.keys():
				if _audio_cache[key].owner.get_ref() == null: _audio_cache.erase(key)
			for key in _audio_cache.keys():
				if _audio_cache.size() <= 1024: break
				if key != id: _audio_cache.erase(key)
		_blobs[digest] = size
		return digest

	func _encode(value: Variant, depth: int = 0) -> Variant:
		_visits += 1
		if depth > 32 or _visits > MAX_VISITS or _estimated > metadata_limit: return _fail("Recovery metadata exceeds its bounded size/depth limit.")
		if not _error.is_empty() or _cancelled(): return _fail("Recovery checkpoint was cancelled.")
		_estimated += 16
		if value is Resource:
			var id: int = value.get_instance_id()
			if _active.has(id): return _fail("Recovery does not support cyclic resource metadata.")
			if _seen.has(id): return ["resource", _seen[id]]
			var kind := _kind(value)
			if kind.is_empty() or value.get_script() != _new_resource(kind).get_script(): return _fail("Recovery cannot safely preserve embedded resource type %s. Save this composition manually." % value.get_class())
			var index := _nodes.size(); _seen[id] = index; _active[id] = true; _nodes.append({})
			var fields := {}
			for field in _properties(value):
				if field == "data" and kind == "wav":
					var digest := _wav_blob(value)
					if digest.is_empty(): return null
					fields[field] = ["wav_file", digest]
				elif field == "data" and kind == "mp3":
					var bytes: PackedByteArray = value.get(field)
					if bytes.size() > blob_limit: return _fail("Embedded audio exceeds the recovery per-source limit; save manually.")
					var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256)
					# Chunk hashing/writing never materializes a second full PCM buffer.
					for offset in range(0, bytes.size(), 65536):
						if _cancelled(): return _fail("Recovery checkpoint was cancelled.")
						hash.update(bytes.slice(offset, mini(offset + 65536, bytes.size())))
					var digest := hash.finish().hex_encode()
					_blobs[digest] = bytes.size(); _streams[digest] = bytes
					fields[field] = ["blob", digest]
				else: fields[field] = _encode(value.get(field), depth + 1)
			_nodes[index] = {"kind": kind, "fields": fields}
			_active.erase(id)
			return ["resource", index]
		if value is Object or typeof(value) in [TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]: return _fail("Recovery encountered unsupported live object metadata; save manually.")
		if value is Dictionary:
			var entries: Array = []
			for key in value:
				if str(key) in ["audio", "original_audio", "sample", "impulse_path"] and value[key] is String and str(value[key]).get_extension().to_lower() in ["wav", "mp3", "ogg", "flac"]: _assets[str(value[key])] = true
				entries.append([_encode(key, depth + 1), _encode(value[key], depth + 1)])
			return ["dictionary", entries]
		if value is Array:
			var items: Array = []
			for item in value: items.append(_encode(item, depth + 1))
			return ["array", items]
		if value is String or value is StringName:
			_estimated += str(value).length() * 4
			var path := str(value)
			if path.get_extension().to_lower() in ["wav", "mp3", "ogg", "flac"] and (path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path()): _assets[path] = true
		elif typeof(value) >= TYPE_PACKED_BYTE_ARRAY: _estimated += value.size() * 32
		return ["value", value]

	func checkpoint(document: KiwiAudioDocument, session_id: String, revision: int, source_path: String = "", work: RefCounted = null) -> Dictionary:
		_store_mutex.lock()
		var result := _checkpoint(document, session_id, revision, source_path, work)
		_reset()
		_store_mutex.unlock()
		return result

	func _checkpoint(document: KiwiAudioDocument, session_id: String, revision: int, source_path: String, work: RefCounted) -> Dictionary:
		_reset(work)
		if document == null or not _hex(session_id, 32) or revision < 0: return {"error": "Invalid recovery checkpoint identity."}
		var issues := document.validate()
		if not issues.is_empty(): return {"error": "Recovery skipped invalid composition: " + "; ".join(issues)}
		var root := _root()
		if DirAccess.make_dir_recursive_absolute(root.path_join("blobs")) != OK: return {"error": "Recovery directory could not be created."}
		var encoded: Variant = _encode(document)
		if not _error.is_empty(): return {"error": _error}
		var envelope := {"format": FORMAT, "session": session_id, "revision": revision, "time": Time.get_unix_time_from_system(), "title": document.title, "source_path": source_path, "document": encoded, "nodes": _nodes, "blobs": _blobs, "assets": _assets.keys()}
		var payload := var_to_bytes(envelope)
		if payload.size() > metadata_limit: return {"error": "Recovery metadata exceeds its size limit; save manually."}
		# Account for every file, including interrupted/unknown files. Never prune
		# the previous good checkpoint merely to make a failed new save fit.
		var used := _used_bytes(root)
		_pending_bytes = payload.size() + 72
		for digest in _blobs:
			var location := root.path_join("blobs").path_join(str(digest) + ".blob")
			if FileAccess.file_exists(location):
				if _file_size(location) != int(_blobs[digest]) or FileAccess.get_sha256(location) != digest: return {"error": "An existing recovery audio blob is corrupt; prior checkpoints were preserved."}
			else: _pending_bytes += int(_blobs[digest])
		if used < 0 or used + _pending_bytes > store_limit: return {"error": "Recovery storage is full. Prior checkpoints are intact; save manually or review recovery storage."}
		for digest in _blobs:
			var location := root.path_join("blobs").path_join(str(digest) + ".blob")
			if not FileAccess.file_exists(location):
				var problem := _atomic_bytes(location, _streams[digest])
				if not problem.is_empty(): return {"error": problem}
		if _cancelled(): return {"error": "Recovery checkpoint was cancelled."}
		var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(payload)
		var bytes := MAGIC.to_ascii_buffer(); bytes.append_array(hash.finish().hex_encode().to_ascii_buffer()); bytes.append_array(payload)
		var id := session_id + "-" + ActorData.new_id() + ".krec"
		var problem := _atomic_bytes(root.path_join(id), bytes)
		if not problem.is_empty(): return {"error": problem}
		_prune(id)
		return {"error": "", "id": id, "revision": revision, "session": session_id, "metadata_bytes": bytes.size(), "audio_blobs": _blobs.size()}

	func _atomic_bytes(destination: String, bytes: PackedByteArray) -> String:
		var temporary := destination + ".part-" + ActorData.new_id()
		var file := FileAccess.open(temporary, FileAccess.WRITE)
		if file == null: return "Could not write recovery data; prior checkpoints are intact."
		for offset in range(0, bytes.size(), 65536):
			if _cancelled():
				file.close(); DirAccess.remove_absolute(temporary); return "Recovery checkpoint was cancelled."
			file.store_buffer(bytes.slice(offset, mini(offset + 65536, bytes.size())))
		file.flush()
		var error := file.get_error(); file.close()
		if error != OK or _file_size(temporary) != bytes.size() or _cancelled():
			DirAccess.remove_absolute(temporary); return "Recovery write did not complete; prior checkpoints are intact."
		if DirAccess.rename_absolute(temporary, destination) != OK:
			DirAccess.remove_absolute(temporary); return "Recovery checkpoint could not be published; prior checkpoints are intact."
		return ""

	static func _file_size(path: String) -> int:
		var file := FileAccess.open(path, FileAccess.READ)
		return file.get_length() if file != null else -1

	func _used_bytes(root: String) -> int:
		var total := 0
		for folder in [root, root.path_join("blobs")]:
			var dir := DirAccess.open(folder)
			if dir == null: return -1
			for file in dir.get_files():
				var size := _file_size(folder.path_join(file))
				if size < 0: return -1
				total += size
		return total

	func _read(id: String) -> Dictionary:
		if id.get_file() != id or id.length() != 70 or id.substr(32, 1) != "-" or not _hex(id.left(32), 32) or not _hex(id.substr(33, 32), 32) or not id.ends_with(".krec"): return {"error": "Invalid recovery filename."}
		var file := FileAccess.open(_root().path_join(id), FileAccess.READ)
		if file == null: return {"error": "Recovery checkpoint is missing or unreadable."}
		if file.get_length() < 72 or file.get_length() > metadata_limit + 72: return {"error": "Recovery checkpoint size is invalid."}
		if file.get_buffer(8).get_string_from_ascii() != MAGIC: return {"error": "Unsupported recovery file format."}
		var expected := file.get_buffer(64).get_string_from_ascii(); var payload := file.get_buffer(file.get_length() - 72)
		var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(payload)
		if hash.finish().hex_encode() != expected: return {"error": "Recovery checksum failed; this checkpoint will not be restored."}
		var envelope: Variant = bytes_to_var(payload) # allow_objects=false: never execute serialized scripts.
		if not envelope is Dictionary or envelope.get("format") != FORMAT or envelope.get("session") != id.left(32) or not envelope.get("nodes") is Array or not envelope.get("blobs") is Dictionary or not envelope.get("assets") is Array or not envelope.get("title") is String or not envelope.get("source_path") is String or not (envelope.get("time") is float or envelope.get("time") is int) or not is_finite(float(envelope.time)) or not envelope.get("revision") is int: return {"error": "Recovery metadata is invalid or from an unsupported version."}
		for digest in envelope.blobs:
			if not digest is String or not _hex(digest, 64) or not envelope.blobs[digest] is int or int(envelope.blobs[digest]) < 0 or int(envelope.blobs[digest]) > blob_limit: return {"error": "Recovery audio manifest is invalid."}
		return {"error": "", "envelope": envelope, "id": id}

	func discover() -> Array[Dictionary]:
		_store_mutex.lock()
		var result := _discover()
		_store_mutex.unlock()
		return result

	func _discover() -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		var dir := DirAccess.open(_root())
		if dir == null: return result
		for id in dir.get_files():
			if not id.ends_with(".krec"): continue # interrupted .part files are never candidates.
			var entry := _read(id)
			entry.id = id
			if entry.error.is_empty():
				var data: Dictionary = entry.envelope
				entry.title = data.title; entry.time = data.time; entry.source_path = data.source_path; entry.revision = data.revision; entry.session = data.session
				var missing := PackedStringArray()
				for asset in data.assets:
					if asset is String and not FileAccess.file_exists(asset): missing.append(asset)
				entry.missing_assets = missing
				for digest in data.blobs:
					if _file_size(_root().path_join("blobs").path_join(str(digest) + ".blob")) != int(data.blobs[digest]): entry.error = "Recovery embedded audio is missing or has the wrong size."; break
			entry.erase("envelope"); result.append(entry)
		result.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("time", 0)) > float(b.get("time", 0)))
		return result

	func _prune(newest: String) -> void:
		var counts := {}; var kept := 0
		var entries := _discover()
		entries.sort_custom(func(a: Dictionary, b: Dictionary): return true if a.id == newest else (false if b.id == newest else float(a.get("time", 0)) > float(b.get("time", 0))))
		for entry in entries:
			if not str(entry.error).is_empty(): continue # damaged checkpoints remain reviewable.
			var key := str(entry.session); counts[key] = int(counts.get(key, 0)) + 1; kept += 1
			if int(counts[key]) > maxi(1, keep_per_session) or kept > maxi(1, keep_total): DirAccess.remove_absolute(_root().path_join(entry.id))
		# If any checkpoint is unreadable, its blob reachability is unknowable.
		# Keep all blobs rather than destroy a possibly recoverable source.
		var referenced := {}
		for entry in _discover():
			var read := _read(entry.id)
			if not str(read.error).is_empty(): return
			referenced.merge(read.envelope.blobs)
		var dir := DirAccess.open(_root().path_join("blobs"))
		if dir == null: return
		for file in dir.get_files():
			if file.ends_with(".blob") and _hex(file.get_basename(), 64) and not referenced.has(file.get_basename()): DirAccess.remove_absolute(_root().path_join("blobs").path_join(file))

	func restore(id: String) -> Dictionary:
		_store_mutex.lock()
		var result := _restore(id)
		_reset()
		_store_mutex.unlock()
		return result

	func _restore(id: String) -> Dictionary:
		_reset()
		var read := _read(id)
		if not str(read.error).is_empty(): return read
		var envelope: Dictionary = read.envelope
		_blobs = envelope.blobs
		var total_audio := 0
		for size in _blobs.values(): total_audio += int(size)
		if total_audio > MAX_STORE: return {"error": "Recovery audio exceeds the total restore limit."}
		var states := {}
		if not _graph_value(envelope.get("document"), envelope.nodes, states, 0): return {"error": _error}
		if states.size() != envelope.nodes.size(): return {"error": "Recovery contains unreachable resource metadata."}
		_visits = 0
		var resources: Array[Resource] = []
		if envelope.nodes.size() > MAX_VISITS: return {"error": "Recovery object count exceeds its limit."}
		for node in envelope.nodes:
			if not node is Dictionary or not node.get("kind") is String or not node.get("fields") is Dictionary: return {"error": "Recovery object metadata is invalid."}
			var resource := _new_resource(node.kind)
			if node.kind == "wav":
				var audio: Variant = node.fields.get("data")
				if not audio is Array or audio.size() != 2 or audio[0] != "wav_file" or not audio[1] is String or not _blobs.has(audio[1]): return {"error": "Recovery WAV reference is invalid."}
				var location := _root().path_join("blobs").path_join(str(audio[1]) + ".blob")
				if _file_size(location) != int(_blobs[audio[1]]) or FileAccess.get_sha256(location) != audio[1]: return {"error": "Recovery WAV is missing or its checksum failed."}
				resource = AudioStreamWAV.load_from_file(location)
			if resource == null: return {"error": "Unsupported recovery object type."}
			resources.append(resource)
		for index in resources.size():
			var resource := resources[index]; var fields: Dictionary = envelope.nodes[index].fields; var allowed := _properties(resource)
			# Older v1 checkpoints predate the optional portable-media manifest.
			var expected_fields := allowed.size() - (1 if resource is KiwiAudioDocument and not fields.has("portable_media") else 0)
			if fields.size() != expected_fields: return {"error": "Recovery fields do not match this version."}
			for field in fields:
				if resource is AudioStreamWAV and field == "data": continue
				if field not in allowed: return {"error": "Unsupported recovery field."}
				var value: Variant = _decode(fields[field], resources, 0)
				if not _error.is_empty(): return {"error": _error}
				if resource is ActorKeyframe and field == "value_curve" and value != null and not value is Curve: return {"error": "Recovery animation curve type mismatch."}
				if resource is ActorObjectReference and field == "embedded" and value != null and not value is ActorObjectData: return {"error": "Recovery embedded object type mismatch."}
				var existing: Variant = resource.get(field)
				if existing is Array and existing.is_typed():
					if not value is Array: return {"error": "Invalid recovery array."}
					var typed: Array = existing.duplicate(); typed.clear()
					for item in value:
						if existing.get_typed_builtin() != typeof(item): return {"error": "Recovery array element type mismatch."}
						if item is Resource and existing.get_typed_script() != null and item.get_script() != existing.get_typed_script(): return {"error": "Recovery resource array type mismatch."}
						typed.append(item)
					value = typed
				elif existing != null and typeof(existing) != typeof(value): return {"error": "Recovery field type mismatch."}
				resource.set(field, value)
		var document: Variant = _decode(envelope.get("document"), resources, 0)
		if not _error.is_empty() or not document is KiwiAudioDocument: return {"error": "Recovery document is invalid. " + _error}
		var issues: PackedStringArray = document.validate()
		if not issues.is_empty(): return {"error": "Recovery document validation failed: " + "; ".join(issues)}
		var missing := PackedStringArray()
		for asset in envelope.assets:
			if asset is String and not FileAccess.file_exists(asset): missing.append(asset)
		# No original destination is ever adopted. Restore is a new unsaved copy.
		document.title += " (Recovered)"
		return {"error": "", "document": document, "missing_assets": missing, "source_path": envelope.source_path, "id": id}

	func _graph_value(encoded: Variant, nodes: Array, states: Dictionary, depth: int) -> bool:
		_visits += 1
		if depth > 32 or _visits > MAX_VISITS or not encoded is Array or encoded.size() != 2: _fail("Invalid or excessive recovery graph."); return false
		var kind: Variant = encoded[0]; var value: Variant = encoded[1]
		if kind == "resource":
			if not value is int or value < 0 or value >= nodes.size(): _fail("Invalid recovery object reference."); return false
			if int(states.get(value, 0)) == 1: _fail("Cyclic recovery resource metadata is unsupported."); return false
			if int(states.get(value, 0)) == 2: return true
			var node: Variant = nodes[value]
			if not node is Dictionary or not node.get("fields") is Dictionary: _fail("Invalid recovery object fields."); return false
			states[value] = 1
			for field in node.fields:
				if not _graph_value(node.fields[field], nodes, states, depth + 1): return false
			states[value] = 2
		elif kind == "array":
			if not value is Array: _fail("Invalid recovery array."); return false
			for item in value:
				if not _graph_value(item, nodes, states, depth + 1): return false
		elif kind == "dictionary":
			if not value is Array: _fail("Invalid recovery dictionary."); return false
			for pair in value:
				if not pair is Array or pair.size() != 2: _fail("Invalid recovery dictionary entry."); return false
				if not _graph_value(pair[0], nodes, states, depth + 1) or not _graph_value(pair[1], nodes, states, depth + 1): return false
		elif kind in ["blob", "wav_file"]:
			if not value is String or not _blobs.has(value): _fail("Invalid recovery audio reference."); return false
		elif kind == "value":
			if value is Object or value is Array or value is Dictionary or typeof(value) in [TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]: _fail("Unsafe recovery scalar."); return false
		else: _fail("Unsupported recovery value type."); return false
		return true

	func _decode(encoded: Variant, resources: Array[Resource], depth: int) -> Variant:
		_visits += 1
		if depth > 32 or _visits > MAX_VISITS or not encoded is Array or encoded.size() != 2: return _fail("Invalid or excessive recovery metadata.")
		var kind: Variant = encoded[0]; var value: Variant = encoded[1]
		match kind:
			"value":
				if value is Object or value is Array or value is Dictionary or typeof(value) in [TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]: return _fail("Unsafe recovery scalar.")
				return value
			"resource":
				if not value is int or value < 0 or value >= resources.size(): return _fail("Invalid recovery resource reference.")
				return resources[value]
			"array":
				if not value is Array: return _fail("Invalid recovery array.")
				var items: Array = []
				for item in value: items.append(_decode(item, resources, depth + 1))
				return items
			"dictionary":
				if not value is Array: return _fail("Invalid recovery dictionary.")
				var dictionary := {}
				for pair in value:
					if not pair is Array or pair.size() != 2: return _fail("Invalid recovery dictionary entry.")
					var key: Variant = _decode(pair[0], resources, depth + 1)
					if key is Resource or key is Array or key is Dictionary: return _fail("Unsupported recovery dictionary key.")
					if dictionary.has(key): return _fail("Duplicate recovery dictionary key.")
					dictionary[key] = _decode(pair[1], resources, depth + 1)
				return dictionary
			"blob":
				if not value is String or not _blobs.has(value): return _fail("Recovery audio reference is missing.")
				if _streams.has(value): return _streams[value]
				var location := _root().path_join("blobs").path_join(value + ".blob")
				if _file_size(location) != int(_blobs[value]) or FileAccess.get_sha256(location) != value: return _fail("Recovery audio checksum failed or the source is missing.")
				var file := FileAccess.open(location, FileAccess.READ)
				if file == null: return _fail("Recovery audio could not be read.")
				var bytes := file.get_buffer(file.get_length())
				_streams[value] = bytes
				return bytes
		return _fail("Unsupported recovery value type.")

## Portable composition copies use opaque media tokens on disk, absolute paths
## at runtime, and a strictly contained, versioned manifest. No source is edited.
class PortableCopy extends RefCounted:
	const FORMAT := 1
	const TOKEN := "kiwi-media://"
	const CHUNK := 65536
	const MAX_FILES := 2048
	const MAX_FILE_BYTES := 512 * 1024 * 1024
	const MAX_EXTERNAL_BYTES := 2 * 1024 * 1024 * 1024
	const MAX_STREAM_BYTES := 64 * 1024 * 1024
	const MAX_EMBEDDED_BYTES := 128 * 1024 * 1024
	const MAX_DOCUMENT_BYTES := MAX_EMBEDDED_BYTES + 16 * 1024 * 1024
	const MEDIA_KEYS := ["audio", "original_audio", "sample", "impulse", "impulse_path"]
	const EXTENSIONS := ["wav", "mp3", "ogg", "flac"]
	static var _publish_mutex := Mutex.new()
	var _error := ""
	var _visits := 0
	var _seen: Dictionary = {}
	var _active: Dictionary = {}
	var _references: Array[Dictionary] = []
	var _streams: Dictionary = {}
	var _embedded_bytes := 0

	# Cancelled jobs suppress their completion signal. The lease therefore owns
	# cleanup independently of UI callbacks, including abandoned queued results.
	class Stage extends RefCounted:
		var final_folder := ""
		var path := ""
		var asset_count := 0
		var total_bytes := 0
		var _directory := ""
		var _id := ""
		var _files: PackedStringArray = []
		var _sources: Array[Dictionary] = []
		var _staged_signatures: Dictionary = {}
		var _ready := false
		var _owned := false
		func _notification(what: int) -> void:
			if what == NOTIFICATION_PREDELETE: release()
		func release() -> void:
			if not _owned: return
			_owned = false; _ready = false
			# Never recurse through arbitrary or newly introduced files/links.
			if not KiwiAudioDocument.Recovery._hex(_id, 32) or _directory.get_file() != ".kiwi-copy-" + _id + ".partial" or _directory.get_base_dir() != final_folder.get_base_dir(): return
			var access := DirAccess.open(_directory.get_base_dir())
			if access == null or access.is_link(_directory.get_file()): return
			access = DirAccess.open(_directory)
			if access == null: return
			var media: DirAccess = DirAccess.open(_directory.path_join("media")) if not access.is_link("media") else null
			for relative in _files:
				if relative == "composition.res" or relative == ".owner":
					if not access.is_link(relative): DirAccess.remove_absolute(_directory.path_join(relative))
				elif relative.begins_with("media/") and relative.get_file() == relative.substr(6) and media != null:
					if not media.is_link(relative.get_file()): DirAccess.remove_absolute(_directory.path_join(relative))
			if media != null: DirAccess.remove_absolute(_directory.path_join("media"))
			DirAccess.remove_absolute(_directory)

	static func freeze(document: KiwiAudioDocument) -> Dictionary:
		var result := Recovery.freeze(document)
		if not str(result.get("error", "")).is_empty(): result.error = "Portable copy cannot freeze this metadata: " + str(result.error)
		return result

	static func _cancelled(work: RefCounted) -> bool:
		return work != null and work.is_cancelled()

	static func _canonical(path: String) -> String:
		if path.is_empty() or path.length() > 4096 or path.to_utf8_buffer().has(0): return ""
		if not path.is_absolute_path() and not path.begins_with("res://") and not path.begins_with("user://"): return ""
		return ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path().trim_suffix("/")

	static func _signature(path: String) -> Dictionary:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null: return {"bytes": -1, "modified": 0}
		var bytes := file.get_length(); file.close()
		return {"bytes": bytes, "modified": FileAccess.get_modified_time(path)}

	static func _hash_file(path: String, expected: Dictionary, work: RefCounted = null, destination: String = "") -> Dictionary:
		if _cancelled(work): return {"error": "Portable copy cancelled."}
		if _signature(path) != expected: return {"error": "Source changed since review: " + path}
		var input := FileAccess.open(path, FileAccess.READ)
		if input == null: return {"error": "Source is missing or unreadable: " + path}
		var output: FileAccess
		if not destination.is_empty():
			if FileAccess.file_exists(destination): input.close(); return {"error": "A staged media filename already exists."}
			output = FileAccess.open(destination, FileAccess.WRITE)
			if output == null: input.close(); return {"error": "Could not write a copied source. Check available space and folder permissions."}
		var hash := HashingContext.new()
		if hash.start(HashingContext.HASH_SHA256) != OK: input.close(); return {"error": "Could not initialize the media checksum."}
		var remaining := int(expected.bytes)
		var problem := ""
		while remaining > 0:
			if _cancelled(work): problem = "Portable copy cancelled."; break
			var amount := mini(CHUNK, remaining)
			var bytes := input.get_buffer(amount)
			if bytes.size() != amount: problem = "Source became unreadable while copying: " + path; break
			if hash.update(bytes) != OK: problem = "Media checksum failed."; break
			if output != null:
				output.store_buffer(bytes)
				if output.get_error() != OK: problem = "Could not finish writing copied media. Check free disk space."; break
			remaining -= amount
		input.close()
		if output != null:
			output.flush()
			if output.get_error() != OK and problem.is_empty(): problem = "Could not flush copied media to disk."
			output.close()
		if problem.is_empty() and _signature(path) != expected: problem = "Source changed while being copied: " + path
		if problem.is_empty() and not destination.is_empty() and int(_signature(destination).bytes) != int(expected.bytes): problem = "Copied media has an unexpected length."
		if not problem.is_empty(): return {"error": problem}
		return {"error": "", "sha256": hash.finish().hex_encode()}

	func _fail(message: String) -> void:
		if _error.is_empty(): _error = message

	func _reference(container: Variant, key: Variant, value: Variant, label: String) -> void:
		if value == null or (value is String and value.is_empty()): return
		if value is String:
			_references.append({"container": container, "key": key, "value": value, "label": label})
			return
		if not value is AudioStream or value.get_script() != null or (not value is AudioStreamWAV and not value is AudioStreamMP3):
			_fail("Unsupported media reference at " + label + ". Only file WAV/MP3/Ogg/FLAC and unscripted embedded WAV/MP3 are portable."); return
		var id: int = value.get_instance_id()
		_references.append({"container": container, "key": key, "value": value, "label": label})
		if _streams.has(id): _streams[id].references += 1; return
		if _streams.size() >= MAX_FILES: _fail("Embedded audio exceeds the 2048-source count limit."); return
		var seconds: float = value.get_length()
		if not is_finite(seconds) or seconds <= 0: _fail("Embedded audio has an invalid or empty duration at " + label); return
		var estimate: int
		if value is AudioStreamWAV:
			if value.mix_rate < 1 or value.mix_rate > 384000: _fail("Embedded WAV has an unsupported sample rate."); return
			# Conservative decoded-size estimate. Never call AudioStreamWAV.data.
			estimate = int(ceil(seconds * value.mix_rate)) * (2 if value.stereo else 1) * 4 + 4096
		else:
			# MP3.data is compressed, but even that whole-array getter is avoided.
			# Valid MPEG audio tops out below this conservative 1 Mbit/s allowance.
			estimate = int(ceil(seconds * 128000.0)) + 1024 * 1024
		if estimate > MAX_STREAM_BYTES: _fail("An embedded source exceeds the conservative 64 MiB portable-save limit. Export it to an audio file first."); return
		_embedded_bytes += estimate
		if _embedded_bytes > MAX_EMBEDDED_BYTES: _fail("Embedded audio exceeds the conservative 128 MiB portable-save budget. Export large sources to files first."); return
		_streams[id] = {"kind": "embedded", "source": "Embedded " + ("WAV" if value is AudioStreamWAV else "MP3"), "label": label, "bytes": estimate, "references": 1, "status": "ready", "sha256": "", "stream": value}

	func _walk(value: Variant, label: String = "Composition", depth: int = 0) -> void:
		_visits += 1
		if depth > 32 or _visits > Recovery.MAX_VISITS: _fail("Portable metadata exceeds the depth or entry budget."); return
		if not _error.is_empty(): return
		if value is AudioStream: _fail("Audio resource appears outside a supported media field at " + label); return
		if value is Resource:
			var kind := Recovery._kind(value)
			var blank := Recovery._new_resource(kind)
			if blank == null or value.get_script() != blank.get_script(): _fail("Unsupported resource schema at " + label); return
			if value is ActorObjectReference and value.source == ActorObjectReference.Source.ASSET: _fail("A project asset-ID reference cannot be made portable. Embed or remove that reference first."); return
			var id: int = value.get_instance_id()
			if _active.has(id): _fail("Cyclic resource metadata is unsupported."); return
			if _seen.has(id): return
			_seen[id] = true; _active[id] = true
			for field in Recovery._properties(value):
				# These are destination/association metadata, not media dependencies.
				if value is KiwiAudioDocument and field in ["portable_media", "output_path", "scene_binding"]: continue
				_walk(value.get(field), label + "." + field, depth + 1)
			_active.erase(id)
		elif value is Dictionary:
			for key in value:
				if key is Object or key is Array or key is Dictionary: _fail("Unsupported metadata dictionary key."); return
				if str(key) in MEDIA_KEYS: _reference(value, key, value[key], label + "." + str(key))
				elif value[key] is String and not str(value[key]).is_empty() and (str(key) in ["path", "file", "source"] or str(key).ends_with("_path") or str(key).ends_with("_file")):
					_fail("Unrecognized file-reference field at " + label + "." + str(key) + ". Portable copy will not guess its schema.")
				else: _walk(value[key], label + "." + str(key), depth + 1)
		elif value is Array or value is PackedStringArray:
			for index in value.size(): _walk(value[index], label + "[" + str(index) + "]", depth + 1)
		elif value is String or value is StringName:
			var text := str(value)
			if text.begins_with(TOKEN) or text.begins_with("res://") or text.begins_with("user://") or text.is_absolute_path() or (text.get_extension().to_lower() in EXTENSIONS and text.contains("/")):
				_fail("Unrecognized path-bearing metadata at " + label + ". Portable copy will not guess its schema.")
		elif value is Object or typeof(value) in [TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]: _fail("Unsupported live metadata at " + label)

	static func _manifest_error(manifest: Dictionary) -> String:
		if manifest.size() != 2 or not manifest.get("version") is int or manifest.get("version") != FORMAT or not manifest.get("assets") is Array: return "Unsupported or corrupt portable media manifest."
		if manifest.assets.size() > MAX_FILES: return "Portable media manifest exceeds the file-count limit."
		var ids := {}; var total := 0
		for entry in manifest.assets:
			if not entry is Dictionary or entry.size() != 4: return "Invalid portable media manifest entry."
			if not entry.get("id") is String or not entry.get("path") is String or not entry.get("sha256") is String or not entry.get("bytes") is int: return "Invalid portable media manifest field type."
			var id: String = entry.id; var extension := id.get_extension()
			if extension not in EXTENSIONS or id != str(entry.sha256) + "." + extension or not Recovery._hex(entry.sha256, 64): return "Invalid portable media identity."
			if entry.path != "media/" + id or ids.has(id) or int(entry.bytes) <= 0 or int(entry.bytes) > MAX_FILE_BYTES: return "Unsafe, duplicate, or oversized portable media path."
			ids[id] = true; total += int(entry.bytes)
			if total > MAX_EXTERNAL_BYTES: return "Portable media exceeds the 2 GiB copy budget."
		return ""

	static func _manifest_map(manifest: Dictionary) -> Dictionary:
		var result := {}
		for entry in manifest.get("assets", []): result[str(entry.id)] = entry
		return result

	static func _inside_state(root: String, relative: String) -> String:
		# Exact media/<hash>.<ext> shape is already checked by the manifest.
		var access := DirAccess.open(root)
		if access == null: return "missing"
		if access.is_link("media"): return "blocked"
		if not access.dir_exists("media"): return "missing"
		access = DirAccess.open(root.path_join("media"))
		if access == null: return "missing"
		if access.is_link(relative.get_file()): return "blocked"
		return "ready" if access.file_exists(relative.get_file()) else "missing"

	static func _reference_id(value: String, entries: Dictionary, root: String) -> String:
		if value.begins_with(TOKEN):
			var id := value.substr(TOKEN.length())
			return id if entries.has(id) else ""
		var canonical := _canonical(value)
		if root.is_empty() or canonical.is_empty(): return ""
		var id := canonical.get_file()
		return id if entries.has(id) and canonical == root.path_join(str(entries[id].path)) else ""

	static func _infer_root(references: Array[Dictionary], entries: Dictionary) -> String:
		var root := ""
		for reference in references:
			if not reference.value is String or str(reference.value).begins_with(TOKEN): continue
			var path := _canonical(reference.value); var id := path.get_file()
			if path.is_empty() or not entries.has(id) or path.get_base_dir().get_file() != "media": continue
			var candidate := path.get_base_dir().get_base_dir()
			if not root.is_empty() and candidate != root: return ""
			root = candidate
		return root

	static func resolve(document: KiwiAudioDocument, composition_path: String, allow_uncollected_sources: bool = false) -> Dictionary:
		if document == null: return {"error": "Composition is missing.", "missing_assets": PackedStringArray()}
		if document.portable_media.is_empty(): return {"error": "", "missing_assets": PackedStringArray(), "warnings": PackedStringArray()}
		var problem := _manifest_error(document.portable_media)
		if not problem.is_empty(): return {"error": problem, "missing_assets": PackedStringArray()}
		var composition := _canonical(composition_path)
		var entries := _manifest_map(document.portable_media)
		var scan := PortableCopy.new(); scan._walk(document)
		if not scan._error.is_empty(): return {"error": scan._error, "missing_assets": PackedStringArray()}
		var old_root := document._portable_root
		if old_root.is_empty(): old_root = _infer_root(scan._references, entries)
		var root := composition.get_base_dir() if not composition.is_empty() else old_root
		if root.is_empty() and not entries.is_empty() and not allow_uncollected_sources: return {"error": "Open this portable composition from its composition.res file so media can be resolved safely. Recovered edits remain in the recovery checkpoint.", "missing_assets": PackedStringArray()}
		var replacements: Array[Dictionary] = []
		var uncollected := PackedStringArray()
		for reference in scan._references:
			if not reference.value is String: continue
			var id := _reference_id(reference.value, entries, old_root)
			if id.is_empty():
				var external := _canonical(reference.value)
				# Opt-in is only for already-loaded/in-memory recovery snapshots.
				# Never accept unresolved tokens or arbitrary relative references.
				if allow_uncollected_sources and not str(reference.value).begins_with(TOKEN) and not external.is_empty() and external.get_extension().to_lower() in EXTENSIONS:
					uncollected.append(external); continue
				return {"error": "Portable composition contains an unlisted or invalid media reference. Create a fresh portable copy from the working document.", "missing_assets": PackedStringArray()}
			if root.is_empty(): return {"error": "A collected media token cannot be restored without its owned folder. Reopen the collected composition first; the recovery checkpoint is preserved.", "missing_assets": PackedStringArray()}
			replacements.append({"reference": reference, "path": root.path_join(str(entries[id].path))})
		var missing := PackedStringArray()
		var warnings := PackedStringArray()
		if not uncollected.is_empty(): warnings.append("Restored edits include uncollected external media. Create a fresh portable copy before saving it as portable.")
		if root.is_empty() and not entries.is_empty(): warnings.append("The earlier collected folder could not be inferred. New external references were preserved; collect a fresh copy before saving.")
		for external in uncollected:
			if int(_signature(external).bytes) <= 0 and not missing.has(external): missing.append(external)
		for entry in entries.values():
			if root.is_empty(): continue # Only uncollected/embedded references remain.
			var state := _inside_state(root, entry.path)
			if state == "blocked": return {"error": "Portable media contains a symbolic link. Refusing to resolve outside its owned folder.", "missing_assets": missing}
			var asset_path := root.path_join(str(entry.path))
			if state != "ready" or int(_signature(asset_path).bytes) != int(entry.bytes): missing.append(asset_path)
		# Mutate only after every reference and containment rule passes.
		for item in replacements: item.reference.container[item.reference.key] = item.path
		document._portable_root = root
		if not missing.is_empty(): warnings.append("Missing or size-mismatched media must be restored before collecting a new portable copy.")
		return {"error": "", "missing_assets": missing, "warnings": warnings}

	static func for_save(document: KiwiAudioDocument, destination_path: String) -> Dictionary:
		if document == null: return {"error": "Composition is missing."}
		if document.portable_media.is_empty(): return {"error": "", "document": document}
		var problem := _manifest_error(document.portable_media)
		if not problem.is_empty(): return {"error": problem}
		var frozen := freeze(document)
		if not str(frozen.error).is_empty(): return frozen
		var copy: KiwiAudioDocument = frozen.document
		var scan := PortableCopy.new(); scan._walk(copy)
		if not scan._error.is_empty(): return {"error": scan._error}
		var entries := _manifest_map(copy.portable_media)
		var root := copy._portable_root
		if root.is_empty(): root = _infer_root(scan._references, entries)
		var destination := _canonical(destination_path)
		if destination.is_empty(): return {"error": "Choose an absolute composition destination."}
		if destination.get_extension().to_lower() != "res": return {"error": "Portable compositions use binary .res files. Save a .res in the collected folder, or create a new portable copy."}
		if root.is_empty() and entries.is_empty(): root = destination.get_base_dir()
		if root.is_empty() or destination.get_base_dir() != root: return {"error": "To save this portable composition in another folder, create a new portable copy so its media travels with it."}
		for reference in scan._references:
			if not reference.value is String: continue
			var id := _reference_id(reference.value, entries, root)
			if id.is_empty(): return {"error": "This composition has a new external media source. Create a new portable copy to collect it before saving."}
			reference.container[reference.key] = TOKEN + id
		copy._portable_root = root
		# Native shallow duplication can still allocate internally; no zero-copy
		# guarantee is made. We do not call the explicit copying WAV.data getter.
		# Shared streams with a resource_path must not escape as dependencies.
		_embed_streams(scan._references)
		return {"error": "", "document": copy}

	static func _embed_streams(references: Array[Dictionary]) -> void:
		var clones := {}
		for reference in references:
			if not reference.value is AudioStream: continue
			var id: int = reference.value.get_instance_id()
			if not clones.has(id):
				# Already embedded immutable streams need no duplicate. Loaded or
				# imported streams are cloned so clearing a path never edits sources.
				var clone: Resource = reference.value
				if not clone.resource_path.is_empty():
					clone = clone.duplicate(false)
					clone.resource_path = ""
				clones[id] = clone
			reference.container[reference.key] = clones[id]

	static func inventory(document: KiwiAudioDocument, composition_path: String = "", work: RefCounted = null) -> Dictionary:
		# Caller owns a main-thread freeze. Never hand a mutable live document to
		# a worker. This function reads that frozen metadata without PCM decoding.
		if document == null: return {"error": "Composition is missing.", "entries": []}
		if _cancelled(work): return {"error": "Portable copy cancelled.", "entries": []}
		var issues := document.validate()
		if not issues.is_empty(): return {"error": "Composition is invalid: " + "; ".join(issues), "entries": []}
		if not document.portable_media.is_empty():
			var problem := _manifest_error(document.portable_media)
			if not problem.is_empty(): return {"error": problem, "entries": []}
		var scan := PortableCopy.new(); scan._walk(document)
		var result := {"error": scan._error, "document": document, "entries": [], "reference_count": scan._references.size(), "external_bytes": 0, "embedded_bytes": scan._embedded_bytes, "total_bytes": scan._embedded_bytes + Recovery.MAX_METADATA, "missing_assets": PackedStringArray(), "warnings": PackedStringArray(), "composition_path": composition_path}
		if not scan._error.is_empty(): return result
		var files := {}; var content := {}; var total := 0
		var manifest := _manifest_map(document.portable_media)
		var root := document._portable_root
		if root.is_empty() and not composition_path.is_empty(): root = _canonical(composition_path).get_base_dir()
		if root.is_empty(): root = _infer_root(scan._references, manifest)
		for reference in scan._references:
			if not reference.value is String: continue
			var source: String = reference.value
			if source.begins_with(TOKEN):
				var id := _reference_id(source, manifest, root)
				if id.is_empty() or root.is_empty(): result.error = "An unresolved portable media token has no valid source folder."; return result
				source = root.path_join(str(manifest[id].path))
			var path := _canonical(source)
			if path.is_empty() or path.get_extension().to_lower() not in EXTENSIONS:
				result.entries.append({"kind": "file", "source": source, "label": reference.label, "bytes": 0, "references": 1, "status": "unsupported", "sha256": ""})
				result.error = "Unsupported or relative media path: " + source; continue
			if files.has(path): files[path].references += 1; continue
			if files.size() >= MAX_FILES: result.error = "Portable copy exceeds the 2048-source limit."; break
			var signature := _signature(path)
			var entry := {"kind": "file", "source": path, "label": path.get_file(), "bytes": int(signature.bytes), "references": 1, "status": "ready", "sha256": "", "signature": signature}
			files[path] = entry; result.entries.append(entry)
			if int(signature.bytes) <= 0:
				entry.status = "missing"; result.missing_assets.append(path); result.error = "One or more media files are missing, empty, or unreadable."; continue
			if int(signature.bytes) > MAX_FILE_BYTES: entry.status = "unsupported"; result.error = "A media source exceeds the 512 MiB per-file copy limit."; continue
			if work != null: work.update(0.05, "Reviewing " + path.get_file())
			var hashed := _hash_file(path, signature, work)
			if not str(hashed.error).is_empty(): result.error = hashed.error; entry.status = "unsupported"; continue
			entry.sha256 = str(hashed.sha256)
			entry.id = entry.sha256 + "." + path.get_extension().to_lower()
			if not content.has(entry.id): content[entry.id] = true; total += int(entry.bytes)
			if total > MAX_EXTERNAL_BYTES: result.error = "Portable media exceeds the 2 GiB copy budget."; break
		for entry in scan._streams.values():
			var display: Dictionary = entry.duplicate(); display.erase("stream"); result.entries.append(display)
		result.external_bytes = total; result.total_bytes = total + scan._embedded_bytes + Recovery.MAX_METADATA
		if scan._embedded_bytes > 0: result.warnings.append("Embedded audio stays in composition.res with its stream metadata. Native resource saving is synchronous and cannot be interrupted inside the save call.")
		if not document.output_path.is_empty() or not document.scene_binding.is_empty(): result.warnings.append("Scene link and export destination are detached in the new copy; originals stay unchanged. Linked scene files are not collected.")
		return result

	static func prepare(review: Dictionary, destination_folder: String, work: RefCounted = null) -> Dictionary:
		if not str(review.get("error", "Invalid media review.")).is_empty() or not review.get("document") is KiwiAudioDocument: return {"error": "Complete a valid media review before copying."}
		if _cancelled(work): return {"error": "Portable copy cancelled."}
		var final_folder := _canonical(destination_folder)
		if final_folder.is_empty() or final_folder == final_folder.get_base_dir() or final_folder.get_file().begins_with("."): return {"error": "Choose a new, named portable-copy folder."}
		var parent := DirAccess.open(final_folder.get_base_dir())
		if parent == null: return {"error": "The destination parent folder is missing or unreadable."}
		if parent.dir_exists(final_folder.get_file()) or parent.file_exists(final_folder.get_file()) or parent.is_link(final_folder.get_file()): return {"error": "The destination already exists. Choose a new folder; nothing is overwritten."}
		var frozen := freeze(review.document)
		if not str(frozen.error).is_empty(): return frozen
		var document: KiwiAudioDocument = frozen.document
		var scan := PortableCopy.new(); scan._walk(document)
		if not scan._error.is_empty(): return {"error": scan._error}
		var stage := Stage.new(); stage.final_folder = final_folder; stage.path = final_folder.path_join("composition.res"); stage._id = ActorData.new_id()
		stage._directory = final_folder.get_base_dir().path_join(".kiwi-copy-" + stage._id + ".partial")
		if DirAccess.make_dir_absolute(stage._directory) != OK: return {"error": "Could not create a new private staging folder."}
		stage._owned = true; stage._files.append(".owner")
		var owner := FileAccess.open(stage._directory.path_join(".owner"), FileAccess.WRITE)
		if owner == null: return {"error": "Could not create the staging ownership marker."}
		owner.store_string(stage._id); owner.close()
		if DirAccess.make_dir_absolute(stage._directory.path_join("media")) != OK: return {"error": "Could not create the copied media folder."}
		var manifest_entries: Array = []; var copied := {}; var by_source := {}; var total := 0
		for entry in review.get("entries", []):
			if entry.get("kind") != "file": continue
			if entry.get("status") != "ready" or not entry.get("signature") is Dictionary or not entry.get("sha256") is String: return {"error": "The reviewed media list is incomplete. Review it again."}
			var path := _canonical(str(entry.source)); var id := str(entry.sha256) + "." + path.get_extension().to_lower()
			if path.is_empty() or path.get_extension().to_lower() not in EXTENSIONS or not Recovery._hex(str(entry.sha256), 64) or int(entry.get("bytes", 0)) <= 0 or int(entry.bytes) > MAX_FILE_BYTES: return {"error": "The reviewed media identity is invalid."}
			by_source[path] = id
			var destination := "" if copied.has(id) else stage._directory.path_join("media/" + id)
			if not destination.is_empty(): stage._files.append("media/" + id)
			if work != null: work.update(0.1 + 0.6 * float(by_source.size()) / maxf(1.0, float(review.entries.size())), "Collecting " + path.get_file())
			var hashed := _hash_file(path, entry.signature, work, destination)
			if not str(hashed.error).is_empty(): return hashed
			if hashed.sha256 != entry.sha256: return {"error": "Source contents changed since review: " + path}
			stage._sources.append({"path": path, "signature": entry.signature.duplicate(), "sha256": entry.sha256})
			if copied.has(id): continue
			copied[id] = true; total += int(entry.bytes)
			if copied.size() > MAX_FILES or total > MAX_EXTERNAL_BYTES: return {"error": "Portable copy exceeds its file-count or 2 GiB media budget."}
			var checked := _hash_file(destination, _signature(destination), work)
			if not str(checked.error).is_empty() or checked.get("sha256", "") != entry.sha256: return {"error": "A copied media checksum did not match. No copy was published."}
			stage._staged_signatures["media/" + id] = _signature(destination)
			manifest_entries.append({"id": id, "path": "media/" + id, "bytes": int(entry.bytes), "sha256": entry.sha256})
		var old_manifest := _manifest_map(document.portable_media)
		var old_root := document._portable_root
		if old_root.is_empty(): old_root = _infer_root(scan._references, old_manifest)
		if old_root.is_empty() and not str(review.get("composition_path", "")).is_empty(): old_root = _canonical(review.composition_path).get_base_dir()
		for reference in scan._references:
			if not reference.value is String: continue
			var source: String = reference.value
			if source.begins_with(TOKEN):
				var old_id := _reference_id(source, old_manifest, old_root)
				if old_id.is_empty() or old_root.is_empty(): return {"error": "A portable source could not be resolved from its reviewed folder."}
				source = old_root.path_join(str(old_manifest[old_id].path))
			var key := _canonical(source)
			if not by_source.has(key): return {"error": "Composition references changed after the media review. Review again."}
			reference.container[reference.key] = TOKEN + str(by_source[key])
		_embed_streams(scan._references)
		document.portable_media = {"version": FORMAT, "assets": manifest_entries}
		document.output_path = ""; document.scene_binding = {}
		document._portable_root = final_folder
		if _cancelled(work): return {"error": "Portable copy cancelled."}
		if work != null: work.update(0.75, "Saving the collected composition")
		stage._files.append("composition.res")
		# Godot's native serializer is synchronous and not allocation-bounded.
		# Conservative embedded limits above bound the accepted workload; final
		# output length is checked before any public folder is created.
		var save_error := ResourceSaver.save(document, stage._directory.path_join("composition.res"))
		var document_bytes := int(_signature(stage._directory.path_join("composition.res")).bytes)
		if save_error != OK or document_bytes <= 0 or document_bytes > MAX_DOCUMENT_BYTES: return {"error": "Composition serialization failed or exceeded its 144 MiB limit. No copy was published."}
		if _cancelled(work): return {"error": "Portable copy cancelled."}
		stage._staged_signatures["composition.res"] = _signature(stage._directory.path_join("composition.res"))
		# Full source recheck happens on the worker; publication is a short gate.
		for source in stage._sources:
			var checked := _hash_file(source.path, source.signature, work)
			if not str(checked.error).is_empty() or checked.get("sha256", "") != source.sha256: return {"error": "A source changed during preparation. Review again; no copy was published."}
		stage.total_bytes = total + document_bytes; stage.asset_count = copied.size() + scan._streams.size(); stage._ready = true
		if work != null: work.update(1.0, "Portable copy is ready to publish")
		return {"error": "", "staged": stage}

	static func discard(stage: Stage) -> void:
		if stage != null: stage.release()

	static func publish(stage: Stage, work: RefCounted = null) -> Dictionary:
		# Call on the main thread only after the session/revision/token gate.
		# No checksum scans or serialization happen inside this final commit.
		if stage == null or not stage._owned or not stage._ready: return {"error": "The prepared portable copy is no longer available."}
		if _cancelled(work): stage.release(); return {"error": "Portable copy cancelled."}
		_publish_mutex.lock()
		var result := _publish_ready(stage, work)
		_publish_mutex.unlock()
		if not str(result.get("error", "")).is_empty(): stage.release()
		return result

	static func _publish_ready(stage: Stage, work: RefCounted) -> Dictionary:
		if not Recovery._hex(stage._id, 32) or stage._directory.get_file() != ".kiwi-copy-" + stage._id + ".partial" or stage._directory.get_base_dir() != stage.final_folder.get_base_dir() or stage.path != stage.final_folder.path_join("composition.res"): return {"error": "Invalid portable staging ownership."}
		var parent := DirAccess.open(stage.final_folder.get_base_dir())
		if parent == null or parent.is_link(stage._directory.get_file()): return {"error": "The staging folder is missing or unsafe."}
		var marker := FileAccess.open(stage._directory.path_join(".owner"), FileAccess.READ)
		if marker == null or marker.get_length() != 32 or marker.get_as_text() != stage._id: return {"error": "The staging ownership marker changed."}
		marker.close()
		var folder := DirAccess.open(stage._directory)
		if folder == null or folder.is_link("composition.res") or folder.is_link("media"): return {"error": "Staged copy paths changed before publication."}
		for relative in stage._staged_signatures:
			if relative != "composition.res" and _inside_state(stage._directory, relative) != "ready": return {"error": "Staged media is missing or unsafe."}
			if _signature(stage._directory.path_join(relative)) != stage._staged_signatures[relative]: return {"error": "Staged copy changed before publication."}
		for source in stage._sources:
			if _signature(source.path) != source.signature: return {"error": "Source changed before publication: " + str(source.path)}
		if parent.dir_exists(stage.final_folder.get_file()) or parent.file_exists(stage.final_folder.get_file()) or parent.is_link(stage.final_folder.get_file()): return {"error": "The destination now exists. Nothing was overwritten."}
		if _cancelled(work): return {"error": "Portable copy cancelled."}
		# The final destination has a UI-generated random suffix. Godot lacks a
		# cross-process rename-no-replace primitive: check + process mutex avoids
		# our own races, not adversarial changes by unrelated filesystem writers.
		if DirAccess.rename_absolute(stage._directory, stage.final_folder) != OK: return {"error": "Could not publish the complete portable folder. No existing destination was intentionally replaced."}
		stage._owned = false; stage._ready = false
		DirAccess.remove_absolute(stage.final_folder.path_join(".owner"))
		return {"error": "", "path": stage.path, "folder": stage.final_folder, "asset_count": stage.asset_count, "total_bytes": stage.total_bytes}
