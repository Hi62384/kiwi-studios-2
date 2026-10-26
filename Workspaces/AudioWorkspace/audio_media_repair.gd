extends RefCounted
## Reuse the portable-media schema walker; never guess at arbitrary strings.
## Review results carry identities, not captured mutable dictionaries.
static func scan(document: KiwiAudioDocument) -> Dictionary:
	var walker := KiwiAudioDocument.PortableCopy.new(); walker._walk(document)
	if not walker._error.is_empty(): return {"error":walker._error,"entries":[]}
	var groups: Dictionary = {}
	for reference in walker._references:
		if not reference.value is String or str(reference.key)=="original_audio": continue
		var index := _actor_index(str(reference.label))
		if index >= 0 and str(reference.label).ends_with(".values.audio") and KiwiAudioEditSession.is_note_source(document.actors[index]): continue
		var value := str(reference.value); var key := KiwiAudioEditSession.audio_source_key(value)
		if key.is_empty(): continue
		if not groups.has(key): groups[key] = {"key":key,"source":value,"labels":[],"count":0,"missing":false}
		var entry: Dictionary = groups[key]; entry.labels.append(str(reference.label)); entry.count += 1
		var file := FileAccess.open(value,FileAccess.READ)
		entry.missing = file == null
		if file != null: entry.missing = file.get_length() <= 0; file.close()
	return {"error":"","entries":groups.values()}

static func _actor_index(label: String) -> int:
	if not label.begins_with("Composition.actors["): return -1
	var text := label.trim_prefix("Composition.actors[").get_slice("]",0)
	return int(text) if text.is_valid_int() else -1

static func apply(session: KiwiAudioEditSession, owner: KiwiAudioDocument, revision: int, source: String, replacement: Dictionary) -> String:
	if session.document != owner or session.revision != revision or session._before != null: return "The composition changed. Review missing media again."
	if not str(replacement.get("error","")).is_empty(): return str(replacement.error)
	var path := str(replacement.get("path","")); var seconds := float(replacement.get("seconds",0.))
	if path.is_empty() or not is_finite(seconds) or seconds <= 0 or replacement.get("signature",{}) != KiwiAudioEditSession._relink_file_signature(path): return "The replacement is missing, changed or has not been validated."
	var key := KiwiAudioEditSession.audio_source_key(source)
	var walker := KiwiAudioDocument.PortableCopy.new(); walker._walk(owner)
	if not walker._error.is_empty(): return walker._error
	var references: Array[Dictionary] = []; var clips: Array[String] = []; var dirty_actors: Dictionary = {}; var dirty_tracks: Dictionary = {}
	for reference in walker._references:
		if not reference.value is String or str(reference.key)=="original_audio" or KiwiAudioEditSession.audio_source_key(str(reference.value))!=key: continue
		var label := str(reference.label); var actor_index := _actor_index(label)
		if actor_index >= 0:
			if actor_index >= owner.actors.size(): return "The media owner changed."
			var actor := owner.actors[actor_index]; var clip := owner.clips[actor_index]; var track := owner.track_for_clip(clip.id)
			if label.ends_with(".values.audio") and KiwiAudioEditSession.is_note_source(actor): continue
			if not session.can_edit(clip.id) or track.has("frozen_track") or track.has("frozen_source"): return "A media owner is locked or frozen. No references were changed."
			if str(reference.key)=="audio" and label.ends_with(".values.audio"): clips.append(clip.id)
			if label.contains(".instrument.") or label.contains(".generator."): dirty_actors[actor.id] = true
		elif label.begins_with("Composition.tracks["):
			var index := int(label.trim_prefix("Composition.tracks[").get_slice("]",0)); var track: Dictionary = owner.tracks[index]
			if bool(track.get("locked",false)) or track.has("frozen_track") or track.has("frozen_source"): return "A media-owning track is locked or frozen. No references were changed."
			if label.contains(".instrument."): dirty_tracks[str(track.id)] = true
		# Explicit sampler loop bounds must continue to fit the replacement.
		if str(reference.key)=="sample" and reference.container is Dictionary:
			var settings: Dictionary = reference.container
			if float(settings.get("loop_start",0.))>=seconds or float(settings.get("loop_end",-1.))>seconds: return "The replacement is too short for an existing sampler loop."
		references.append(reference)
	if references.is_empty(): return "No active references to this source remain."
	if not clips.is_empty():
		var problem := session.audio_relink_problem(clips,source,replacement)
		if not problem.is_empty(): return problem
	ActorAudio.invalidate(path)
	session.action("Repair linked media",func():
		for reference in references: reference.container[reference.key] = path
		for id in clips:
			var actor := owner.actor_for_clip(id); actor.values[&"source_duration"] = seconds
			actor.values.erase(&"transients"); actor.values.erase(&"transients_source_identity")
		for actor in owner.actors:
			if (dirty_actors.has(actor.id) or dirty_tracks.has(str(actor.values.get(&"track_id","")))) and KiwiAudioEditSession.is_note_source(actor): actor.values[&"notes_dirty"] = true; actor.values.erase(&"rendered_signature"))
	return ""
