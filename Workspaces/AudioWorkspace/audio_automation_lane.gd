class_name KiwiAudioAutomationLane
extends RefCounted
## A lane is a persistent view of an existing owner's curve. It never owns a
## second curve or changes playback routing; preview and export read the same data.
static var _definitions: Dictionary = {}

static func _effect_definition(type: String) -> Dictionary:
	if not _definitions.has(type): _definitions[type] = KiwiAudioEffects.definition(type)
	return _definitions[type]

static func is_lane(track: Dictionary) -> bool:
	return str(track.get("kind", "")) == "automation"

static func key(target: Dictionary) -> String:
	return var_to_str([target.get("owner_kind", ""), target.get("owner_id", ""), target.get("effect_id", ""), target.get("parameter", "")])

static func resolve(document: KiwiAudioDocument, target: Dictionary) -> Dictionary:
	var kind := str(target.get("owner_kind", ""))
	var id := str(target.get("owner_id", ""))
	var owner: Dictionary = {}
	var label := ""
	var offset := 0.0
	var length := maxf(1.0, document.duration())
	var locked := false
	match kind:
		"master": owner = document.master; label = "Master"
		"track":
			owner = document.track_for_id(id)
			if owner.is_empty() or is_lane(owner): return {}
			label = str(owner.get("name", "Track")); locked = bool(owner.get("locked", false))
		"clip":
			var clip := document.clip_for_id(id)
			var actor := document.actor_for_clip(id)
			if clip == null or actor == null: return {}
			owner = actor.values; label = actor.display_name
			offset = clip.start_time; length = clip.duration
			locked = bool(document.track_for_clip(id).get("locked", false))
		_: return {}
	var parameter := str(target.get("parameter", ""))
	var effect_id := str(target.get("effect_id", ""))
	var definition: Dictionary = {}
	if not effect_id.is_empty():
		var found: Dictionary = {}
		for effect in owner.get("effects", []):
			if str(effect.get("id", "")) == effect_id: found = effect; break
		if found.is_empty(): return {}
		owner = found
		var type := str(owner.get("type", ""))
		if not KiwiAudioEffects.automation_commands(type).has(parameter): return {}
		for field in _effect_definition(type).get("parameters", []):
			if str(field.get("id", "")) == parameter: definition = field; break
		if definition.is_empty(): return {}
		label += " / " + str(_effect_definition(type).get("label", type))
	else:
		var allowed: Array = ["volume_db"] if kind == "master" else (["volume_db", "pan", "pitch"] if kind == "clip" else ["volume_db", "pan"])
		if not allowed.has(parameter): return {}
		definition = {"min": 0.25 if parameter == "pitch" else (-1.0 if parameter == "pan" else -60.0), "max": 4.0 if parameter == "pitch" else (1.0 if parameter == "pan" else 12.0)}
	var fallback := float(owner.get("parameters", owner).get(parameter, 1.0 if parameter == "pitch" else 0.0))
	return {"target": target.duplicate(true), "owner": owner, "parameter": parameter, "label": label + " / " + parameter, "offset": offset, "duration": length, "minimum": float(definition.get("min", -60)), "maximum": float(definition.get("max", 12)), "fallback": fallback, "locked": locked}

static func lane_info(document: KiwiAudioDocument, lane_id: String) -> Dictionary:
	var lane := document.track_for_id(lane_id)
	if not is_lane(lane) or not lane.get("automation_target", {}) is Dictionary: return {}
	return resolve(document, lane.get("automation_target", {}))

static func editable(document: KiwiAudioDocument, lane_id: String) -> bool:
	var info := lane_info(document, lane_id)
	return not info.is_empty() and not bool(info.locked) and not bool(document.track_for_id(lane_id).get("locked", false))

static func points(info: Dictionary) -> Array:
	if info.is_empty(): return []
	return info.owner.get("automation", {}).get(str(info.parameter), [])

static func options(document: KiwiAudioDocument) -> Array[Dictionary]:
	var owners: Array[Dictionary] = [{"owner_kind": "master", "owner_id": ""}]
	for track in document.tracks:
		if not is_lane(track): owners.append({"owner_kind": "track", "owner_id": str(track.id)})
	for clip in document.clips: owners.append({"owner_kind": "clip", "owner_id": clip.id})
	var output: Array[Dictionary] = []
	for target in owners:
		var base := target.duplicate(true); base.parameter = "volume_db"
		var info := resolve(document, base)
		if info.is_empty(): continue
		var parameters: Array = ["volume_db"] if target.owner_kind == "master" else (["volume_db", "pan", "pitch"] if target.owner_kind == "clip" else ["volume_db", "pan"])
		for parameter in parameters:
			var item := target.duplicate(true); item.parameter = parameter; item.effect_id = ""
			output.append(resolve(document, item))
		for effect in info.owner.get("effects", []):
			var supported := KiwiAudioEffects.automation_commands(str(effect.get("type", "")))
			for field in _effect_definition(str(effect.get("type", ""))).get("parameters", []):
				if not supported.has(str(field.get("id", ""))): continue
				var item := target.duplicate(true); item.parameter = str(field.id); item.effect_id = str(effect.get("id", ""))
				var resolved := resolve(document, item)
				if not resolved.is_empty(): output.append(resolved)
	return output

static func value(points_value: Array, time: float, fallback: float) -> float:
	# Binary search avoids scanning a long curve once for each display pixel.
	if points_value.is_empty(): return fallback
	if time <= float(points_value[0].time): return float(points_value[0].value)
	var low := 0; var high := points_value.size() - 1
	while low < high:
		var middle := (low + high + 1) / 2
		if float(points_value[middle].time) <= time: low = middle
		else: high = middle - 1
	if low + 1 >= points_value.size(): return float(points_value.back().value)
	return KiwiAudioEditSession.automation_value([points_value[low], points_value[low + 1]], time, fallback)

static func binding_error(document: KiwiAudioDocument, lane_id: String) -> String:
	var lane := document.track_for_id(lane_id)
	if lane.is_empty(): return "The automation lane no longer exists."
	for actor in document.actors:
		if str(actor.values.get(&"track_id", "")) == lane_id: return "This legacy automation track contains audio clips. Move them to an audio track, or convert this lane back to audio first."
	if not str(lane.get("output", "")).is_empty() or not lane.get("sends", []).is_empty(): return "This legacy track has audio routing. Convert it back to an audio track to preserve that routing."
	if not lane.get("effects", []).is_empty() or not lane.get("automation", {}).is_empty() or bool(lane.get("solo", false)) or bool(lane.get("mute", false)):
		return "This legacy track has its own processing or mute/solo state. Convert it back to an audio track before creating a linked lane."
	for other in document.tracks:
		if str(other.get("output", "")) == lane_id: return "Audio is routed into this legacy track. Convert it back to an audio track before creating a linked lane."
		for send in other.get("sends", []):
			if str(send.get("target", "")) == lane_id: return "An audio send targets this legacy track. Convert it back to an audio track before creating a linked lane."
	return ""
