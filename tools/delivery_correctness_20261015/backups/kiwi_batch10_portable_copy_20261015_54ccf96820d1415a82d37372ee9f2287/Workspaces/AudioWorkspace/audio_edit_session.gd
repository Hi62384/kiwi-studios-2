class_name KiwiAudioEditSession
extends RefCounted
signal changed
signal selection_changed
var document: KiwiAudioDocument = KiwiAudioDocument.new()
var history := UndoRedo.new()
var history_limit := 64
var history_byte_budget := 256 * 1024 * 1024
const MAX_METADATA_ESTIMATE_VISITS := 250000
const MAX_METADATA_ESTIMATE_DEPTH := 24
var history_pruned_actions := 0
var _history_footprints: Array[Dictionary] = []
var _history_actions: Array[Dictionary] = []
var selected_ids: Array[String] = []
var selected_track: String = ""
var revision: int = 0
var dirty: bool = false
var _before: KiwiAudioDocument
var _label := ""
var _pending_preview := false
var _clipboard: Array[Dictionary] = []
var _effect_clipboard: Array = []
var last_action := Callable()

# An outer UI gesture owns one exact session/document/transaction. Late events
# may discard their own handle, but must never finish a replacement transaction.
class Gesture extends RefCounted:
	var owner: KiwiAudioEditSession
	var document: KiwiAudioDocument
	var before: KiwiAudioDocument
	func valid(current: KiwiAudioEditSession) -> bool:
		return owner != null and current == owner and current.document == document and before != null and current._before == before
	func clear() -> void:
		owner = null; document = null; before = null
	func begin(current: KiwiAudioEditSession, label: String) -> void:
		clear()
		if current._before != null: current.commit()
		current.begin(label)
		owner = current; document = current.document; before = current._before
	func finish(current: KiwiAudioEditSession, keep: bool = true) -> void:
		var target := owner
		var owns := valid(current)
		clear() # commit/cancel emit signals synchronously.
		if owns:
			if keep: target.commit()
			else: target.cancel()

func open(value: KiwiAudioDocument) -> void:
	_before = null
	_label = ""
	_pending_preview = false
	document = value
	if document.tracks.is_empty(): document.add_track()
	history.clear_history()
	_history_footprints.clear()
	_history_actions.clear()
	history_pruned_actions = 0
	selected_ids.clear()
	selected_track = str(document.workspace_state.get("selected_track", document.tracks[0].id))
	if not selected_track.is_empty() and document.track_for_id(selected_track).is_empty(): selected_track = document.tracks[0].id
	for id in document.workspace_state.get("selected_ids", []):
		if document.clip_for_id(str(id)) != null: selected_ids.append(str(id))
	revision += 1
	dirty = false
	changed.emit()

func begin(label: String) -> void:
	if _before != null: return
	_before = document.snapshot()
	_pending_preview = false
	_label = label

func preview() -> void:
	if _before != null: _pending_preview = true
	revision += 1
	changed.emit()

func commit() -> void:
	if _before == null: return
	var previous := _before
	_before = null
	var current := document.snapshot()
	var kept := history.get_current_action() + 1
	if kept < _history_footprints.size():
		_history_footprints.resize(maxi(0, kept))
		_history_actions.resize(maxi(0, kept))
	var estimate_limit := maxi(1, history_byte_budget + 1)
	var footprint := _source_footprint(previous, estimate_limit)
	footprint.merge(_source_footprint(current, estimate_limit), true)
	_history_footprints.append(footprint)
	_history_actions.append({"label": _label, "before": previous, "after": current})
	history.max_steps = maxi(1, history_limit)
	history.create_action(_label)
	history.add_do_method(KiwiAudioEditSession.restore_weak.bind(weakref(self), current))
	history.add_undo_method(KiwiAudioEditSession.restore_weak.bind(weakref(self), previous))
	history.commit_action(false)
	while _history_footprints.size() > history.get_history_count():
		_history_footprints.pop_front(); _history_actions.pop_front()
	var trimmed := false
	while _history_footprints.size() > 1:
		var unique := {}
		for item in _history_footprints: unique.merge(item, true)
		var bytes := 0
		for size in unique.values(): bytes += int(size)
		if bytes <= history_byte_budget: break
		_history_footprints.pop_front(); _history_actions.pop_front()
		history_pruned_actions += 1
		trimmed = true
	if trimmed:
		# Godot enforces max_steps only on a later commit. Rebuild the retained
		# callbacks now so dropped PCM and metadata references are released.
		history.clear_history(false)
		for entry in _history_actions:
			history.create_action(str(entry.label))
			history.add_do_method(KiwiAudioEditSession.restore_weak.bind(weakref(self), entry.after))
			history.add_undo_method(KiwiAudioEditSession.restore_weak.bind(weakref(self), entry.before))
			history.commit_action(false)
	dirty = true
	revision += 1
	changed.emit()

static func _source_footprint(value:KiwiAudioDocument,metadata_limit:int=268435457)->Dictionary:
	var sources := {}
	# Estimated accounting, not measured RSS. Snapshot dictionaries/arrays are
	# separate copies even when their audio Resources are shared. A string key
	# cannot collide with the integer instance IDs used for shared PCM below.
	sources["snapshot_metadata:" + str(value.get_instance_id())] = _metadata_estimate(value, metadata_limit)
	for actor in value.actors:
		if actor == null: continue
		for key in [&"audio", &"original_audio"]:
			var stream:Variant=actor.values.get(key)
			if stream is AudioStreamWAV: sources[stream.get_instance_id()] = stream.data.size()
		var instrument:Dictionary=actor.values.get(&"instrument", {})
		var sample:Variant=instrument.get("sample")
		if sample is AudioStreamWAV: sources[sample.get_instance_id()] = sample.data.size()
		for mapping in instrument.get("multisamples", []):
			sample=mapping.get("sample")
			if sample is AudioStreamWAV: sources[sample.get_instance_id()] = sample.data.size()
	return sources

static func _metadata_estimate(value:KiwiAudioDocument,limit:int)->int:
	# Conservative object/container/Variant allowances intentionally overcount
	# interned keys and aliased small values. Bound the walk; if it is too deep
	# or large to estimate, charge more than the configured history budget.
	# This also terminates cyclic Array/Dictionary data without traversing it
	# indefinitely. The newest action is still retained by the existing policy.
	var state:Array=[mini(limit,1024+value.actors.size()*1024+value.clips.size()*512),0,maxi(1,limit)]
	for entry:Variant in [value.title,value.tracks,value.markers,value.sections,value.chords,value.composer_settings,value.master,value.presets,value.takes,value.workspace_state,value.output_path,value.tempo_points,value.meter_points,value.get("scene_binding")]:
		_estimate_metadata_value(entry,state,0)
		if int(state[0])>=int(state[2]):return int(state[2])
	for actor in value.actors:
		if actor == null: continue
		for entry:Variant in [actor.id,actor.display_name,actor.parent_id,actor.section_id,actor.values,actor.animation_tracks]:
			_estimate_metadata_value(entry,state,0)
			if int(state[0])>=int(state[2]):return int(state[2])
	return int(state[0])

static func _estimate_metadata_value(value:Variant,state:Array,depth:int)->void:
	if int(state[0])>=int(state[2]):return
	state[1]=int(state[1])+1
	if int(state[1])>MAX_METADATA_ESTIMATE_VISITS or depth>MAX_METADATA_ESTIMATE_DEPTH:
		state[0]=state[2];return
	var bytes:=32
	if value is String or value is StringName:
		bytes=96+str(value).length()*4
	elif value is Dictionary:
		bytes=128+value.size()*96
	elif value is Array or value is PackedStringArray:
		bytes=64+value.size()*32
	elif value is PackedByteArray:bytes=64+value.size()
	elif value is PackedInt32Array or value is PackedFloat32Array:bytes=64+value.size()*4
	elif value is PackedInt64Array or value is PackedFloat64Array:bytes=64+value.size()*8
	elif value is PackedVector2Array:bytes=64+value.size()*16
	elif value is PackedVector3Array:bytes=64+value.size()*24
	elif value is PackedVector4Array:bytes=64+value.size()*32
	elif value is PackedColorArray:bytes=64+value.size()*16
	elif value is Object:bytes=64 # Shared Resource contents are not cloned here.
	state[0]=mini(int(state[2]),int(state[0])+bytes)
	if int(state[0])>=int(state[2]):return
	if value is Dictionary:
		for key:Variant in value:
			_estimate_metadata_value(key,state,depth+1)
			_estimate_metadata_value(value[key],state,depth+1)
			if int(state[0])>=int(state[2]):return
	elif value is Array or value is PackedStringArray:
		for entry:Variant in value:
			_estimate_metadata_value(entry,state,depth+1)
			if int(state[0])>=int(state[2]):return

func cancel() -> void:
	if _before != null:
		var previous := _before
		_before = null
		_restore(previous)

func action(label: String, callback: Callable) -> void:
	var nested := _before != null
	begin(label)
	callback.call()
	if not nested: commit()

static func restore_weak(owner: WeakRef, value: KiwiAudioDocument) -> void:
	var session := owner.get_ref() as KiwiAudioEditSession
	if session != null: session._restore(value)

func _restore(value: KiwiAudioDocument) -> void:
	document = value.snapshot()
	var valid: Array[String] = []
	for id in selected_ids:
		if document.clip_for_id(id) != null: valid.append(id)
	selected_ids = valid
	if not selected_track.is_empty() and document.track_for_id(selected_track).is_empty():
		selected_track = str(document.tracks[0].id) if not document.tracks.is_empty() else ""
	dirty = true
	revision += 1
	changed.emit()
	selection_changed.emit()

func undo() -> void:
	if _before != null:
		# Preserve a meaningful live edit as the newest redoable action. A click
		# with no preview is only a cancelled gesture, not an older Undo.
		if _pending_preview:
			commit()
			history.undo()
		else: cancel()
		return
	if history.has_undo(): history.undo()

func redo() -> void:
	# Redo during a live edit cancels that gesture first; it must not combine
	# a restored history snapshot with an old canvas/slider transaction.
	if _before != null:
		cancel()
		return
	if history.has_redo(): history.redo()

func select(id: String, additive: bool = false) -> void:
	if not additive: selected_ids.clear()
	if document.clip_for_id(id) != null:
		if additive and selected_ids.has(id): selected_ids.erase(id)
		else: selected_ids.append(id)
		selected_track = str(document.track_for_clip(id).get("id", ""))
	selection_changed.emit()

func select_all() -> void:
	selected_ids.clear()
	for clip in document.clips: selected_ids.append(clip.id)
	selection_changed.emit()

func primary_clip() -> ActorClip:
	return document.clip_for_id(selected_ids.back()) if not selected_ids.is_empty() else null

func primary_actor() -> ActorData:
	return document.actor_for_clip(selected_ids.back()) if not selected_ids.is_empty() else null

func can_edit(id: String) -> bool:
	var track := document.track_for_clip(id)
	return not track.is_empty() and not bool(track.get("locked", false))

func add_track(kind: String = "audio", label: String = "") -> void:
	action("Add track", func():
		var track := document.add_track(label if not label.is_empty() else kind.capitalize(), kind)
		selected_track = track.id)

func delete_track(id: String) -> void:
	var track := document.track_for_id(id)
	if track.is_empty() or bool(track.get("locked", false)): return
	action("Delete track", func():
		for i in range(document.clips.size() - 1, -1, -1):
			if str(document.actors[i].values.get(&"track_id", "")) == id:
				document.clips.remove_at(i)
				document.actors.remove_at(i)
		document.tracks.erase(track)
		for other in document.tracks:
			if str(other.get("output", "")) == id: other.output = ""
			other.sends = (other.get("sends", []) as Array).filter(func(send: Dictionary): return str(send.get("target", "")) != id)
		if document.tracks.is_empty(): document.add_track()
		selected_track = document.tracks[0].id)

func insert_source(value: Variant, at: float, track_id: String = "", label: String = "") -> ActorClip:
	var result: ActorClip
	var target := track_id if not track_id.is_empty() else selected_track
	if document.track_for_id(target).is_empty() or bool(document.track_for_id(target).get("locked",false)) or str(document.track_for_id(target).get("kind", "")) == "automation": return null
	var nested := _before != null
	begin("Import audio")
	result = document.insert_source(value, target, at, label)
	if result == null:
		if not nested: _before = null
		return null
	selected_ids.assign([result.id])
	selected_track = target
	if not nested: commit()
	selection_changed.emit()
	return result

func delete_selected(ripple: bool = false) -> void:
	if selected_ids.is_empty(): return
	action("Ripple delete clips" if ripple else "Delete clips", func():
		var removed: Array[Dictionary] = []
		for id in selected_ids:
			var clip := document.clip_for_id(id)
			if clip != null and can_edit(id):
				removed.append({"track": document.track_for_clip(id).id, "start": clip.start_time, "duration": clip.duration})
		removed.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.start) > float(b.start))
		for i in range(document.clips.size() - 1, -1, -1):
			if selected_ids.has(document.clips[i].id) and can_edit(document.clips[i].id):
				document.clips.remove_at(i)
				document.actors.remove_at(i)
		if ripple:
			for region in removed:
				for clip in document.clips:
					if str(document.track_for_clip(clip.id).get("id", "")) == str(region.track) and clip.start_time >= float(region.start) + float(region.duration) - 0.000001:
						clip.start_time = maxf(0.0, clip.start_time - float(region.duration))
		selected_ids.clear())
	selection_changed.emit()

func copy() -> void:
	_clipboard.clear()
	for id in selected_ids:
		var clip := document.clip_for_id(id)
		if clip != null:
			var source_actor := document.actor_for_clip(id)
			var copied_actor := ActorData.new()
			copied_actor.id = source_actor.id
			copied_actor.type_id = source_actor.type_id
			copied_actor.display_name = source_actor.display_name
			copied_actor.values = source_actor.values.duplicate(true)
			_clipboard.append({"clip": clip.duplicate(false), "actor": copied_actor})

func paste(at: float, target_track: String = "") -> void:
	if _clipboard.is_empty(): return
	action("Paste clips", func():
		var first := INF
		for entry in _clipboard: first = minf(first, entry.clip.start_time)
		selected_ids.clear()
		for entry in _clipboard:
			var target := target_track if not target_track.is_empty() else str(entry.actor.values.get(&"track_id", ""))
			var destination := document.track_for_id(target)
			if destination.is_empty() or bool(destination.get("locked", false)) or str(destination.get("kind", "")) == "automation": continue
			var actor := ActorData.new()
			actor.id = ActorData.new_id()
			actor.type_id = &"audio"
			actor.display_name = entry.actor.display_name + " copy"
			actor.values = entry.actor.values.duplicate(true)
			if not target_track.is_empty(): actor.values[&"track_id"] = target_track
			var clip: ActorClip = entry.clip.duplicate(false)
			clip.id = ActorData.new_id()
			clip.actor_id = actor.id
			clip.start_time = maxf(0.0, at + clip.start_time - first)
			document.actors.append(actor)
			document.clips.append(clip)
			selected_ids.append(clip.id))
	selection_changed.emit()

func duplicate_selected() -> void:
	if selected_ids.is_empty(): return
	var end := 0.0
	for id in selected_ids:
		var clip := document.clip_for_id(id)
		if clip != null: end = maxf(end, clip.start_time + clip.duration)
	copy()
	paste(end)

func split_selected(at: float) -> void:
	action("Split clips", func():
		var added: Array[String] = []
		for id in selected_ids:
			if not can_edit(id): continue
			var clip := document.clip_for_id(id)
			if clip == null or at <= clip.start_time + 0.00001 or at >= clip.start_time + clip.duration - 0.00001: continue
			var actor := document.actor_for_clip(id)
			var new_actor := ActorData.new()
			new_actor.id = ActorData.new_id()
			new_actor.type_id = &"audio"
			new_actor.display_name = actor.display_name
			new_actor.values = actor.values.duplicate(true)
			var right: ActorClip = clip.duplicate(false)
			right.id = ActorData.new_id()
			right.actor_id = new_actor.id
			right.start_time = at
			right.duration = clip.start_time + clip.duration - at
			if bool(actor.values.get(&"reverse", false)):
				# Reverse playback consumes the end of the source window first.
				# The left timeline piece keeps that end; the right keeps the start.
				clip.source_offset += right.duration * clip.playback_speed
			else:
				right.source_offset += (at - clip.start_time) * clip.playback_speed
			shift_owner_automation(new_actor.values, at - clip.start_time)
			clip.duration = at - clip.start_time
			actor.values[&"fade_out"] = minf(0.005, clip.duration * 0.1)
			new_actor.values[&"fade_in"] = minf(0.005, right.duration * 0.1)
			document.actors.append(new_actor)
			document.clips.append(right)
			added.append(right.id)
		selected_ids.append_array(added))

static func shifted_curve(points:Array,offset:float,fallback:float)->Array:
	if points.is_empty():return []
	var ordered:=points.duplicate(true);ordered.sort_custom(func(a:Dictionary,b:Dictionary):return float(a.time)<float(b.time))
	var active:Dictionary=ordered[0];var following:Dictionary={}
	for point in ordered:
		if float(point.time)<=offset:active=point
		else:following=point;break
	var output:Array=[{"time":0.0,"value":automation_value(ordered,offset,fallback),"curve":active.get("curve","linear")}]
	# A cropped smoothstep segment is not another whole smoothstep. Preserve its
	# shape with a short linear approximation, then keep later original curves.
	if str(active.get("curve","linear"))=="smooth" and not following.is_empty() and offset>float(active.time):
		output[0].curve="linear"
		for i in range(1,16):
			var time:=lerpf(offset,float(following.time),float(i)/16)
			output.append({"time":time-offset,"value":automation_value(ordered,time,fallback),"curve":"linear"})
	for point in ordered:
		if float(point.time)>offset:
			var copy:Dictionary=point.duplicate(true);copy.time=float(copy.time)-offset;output.append(copy)
	return output

static func shift_owner_automation(owner:Dictionary,offset:float)->void:
	var automation:Dictionary=owner.get("automation",{})
	for key in automation:automation[key]=shifted_curve(automation[key],offset,float(owner.get("parameters",owner).get(key,0)))
	owner["automation"]=automation
	for effect in owner.get("effects",[]):shift_owner_automation(effect,offset)

func edit_clip(id: String, changes: Dictionary) -> bool:
	if not can_edit(id): return false
	var clip := document.clip_for_id(id)
	var actor := document.actor_for_clip(id)
	if clip == null: return false
	var start := float(changes.get("start_time", clip.start_time))
	var duration := float(changes.get("duration", clip.duration))
	var offset := float(changes.get("source_offset", clip.source_offset))
	var speed := float(changes.get("playback_speed", clip.playback_speed))
	if not is_finite(start) or not is_finite(duration) or not is_finite(offset) or not is_finite(speed): return false
	if start < 0 or duration < 1.0 / 192000.0 or offset < 0 or speed < 0.05 or speed > 16: return false
	var source_length := float(actor.values.get(&"source_duration", 0.0))
	if not bool(actor.values.get(&"loop", false)) and source_length > 0 and offset + duration * speed > source_length + 0.0001: return false
	if changes.has("track_id"):
		var target := document.track_for_id(str(changes.track_id))
		if target.is_empty() or bool(target.get("locked", false)) or str(target.get("kind", "")) == "automation": return false
	clip.start_time = start
	clip.duration = duration
	clip.source_offset = offset
	clip.playback_speed = speed
	if changes.has("track_id") and not document.track_for_id(str(changes.track_id)).is_empty(): actor.values[&"track_id"] = str(changes.track_id)
	return true

func set_clip_value(key: StringName, value: Variant) -> void:
	action("Change " + str(key).capitalize(), func():
		for id in selected_ids:
			if can_edit(id): document.actor_for_clip(id).values[key] = value)

func move_selected(delta: float, track_delta: int = 0) -> void:
	var earliest := INF
	for id in selected_ids:
		if can_edit(id): earliest = minf(earliest, document.clip_for_id(id).start_time)
	if is_finite(earliest): delta = maxf(delta, -earliest)
	for id in selected_ids:
		if not can_edit(id): continue
		var clip := document.clip_for_id(id)
		var track := document.track_for_clip(id)
		var index := document.tracks.find(track)
		edit_clip(id, {"start_time": maxf(0.0, clip.start_time + delta),
			"track_id": document.tracks[clampi(index + track_delta, 0, document.tracks.size() - 1)].id})

func crossfade_selected(seconds: float = 0.04) -> void:
	action("Crossfade clips", func():
		for id in selected_ids:
			if not can_edit(id): continue
			var clip := document.clip_for_id(id)
			var actor := document.actor_for_clip(id)
			actor.values[&"fade_in"] = minf(seconds, clip.duration * 0.5)
			actor.values[&"fade_out"] = minf(seconds, clip.duration * 0.5)
			actor.values[&"fade_curve"] = "equal_power")

func set_track_value(id: String, key: String, value: Variant) -> bool:
	var track := document.track_for_id(id)
	if track.is_empty() or bool(track.get("locked", false)): return false
	if str(track.get("kind", "")) == "automation" and key in ["mute", "solo", "volume_db", "pan", "output", "sends"]: return false
	if key == "output" and str(document.track_for_id(str(value)).get("kind", "")) == "automation": return false
	if key == "sends" and value is Array:
		for send in value:
			if send is Dictionary and str(document.track_for_id(str(send.get("target", ""))).get("kind", "")) == "automation": return false
	var nested := _before != null
	begin("Change track " + key)
	var previous: Variant = track.get(key)
	track[key] = value
	if not document.validate().is_empty():
		track[key] = previous
		if not nested: _before = null
		return false
	if not nested: commit()
	return true

func add_automation(owner: Dictionary, parameter: String, at: float, value: float) -> void:
	var curves: Dictionary = owner.get("automation", {})
	var points: Array = curves.get(parameter, [])
	points.append({"time": maxf(0, at), "value": value, "curve": "linear"})
	points.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.time) < float(b.time))
	curves[parameter] = points
	owner["automation"] = curves

static func automation_value(points: Array, time: float, fallback: float) -> float:
	if points.is_empty(): return fallback
	if time <= float(points[0].time): return float(points[0].value)
	for index in range(1, points.size()):
		var a: Dictionary = points[index - 1]
		var b: Dictionary = points[index]
		if time < float(b.time):
			if str(a.get("curve", "linear")) == "hold": return float(a.value)
			var weight := clampf((time - float(a.time)) / maxf(0.000001, float(b.time) - float(a.time)), 0, 1)
			if str(a.get("curve", "linear")) == "smooth": weight = smoothstep(0.0, 1.0, weight)
			return lerpf(float(a.value), float(b.value), weight)
	return float(points.back().value)

func change_tempo(bpm: float) -> void:
	# The toolbar edits the project conductor only. Explicit source retiming
	# remains available through retime_note_sources() and its separate dialog.
	if not is_finite(bpm): return
	set_conductor(clampf(bpm, 20.0, 400.0), document.time_signature, document.tempo_points, document.meter_points)

func change_meter(signature: Vector2i) -> void:
	set_conductor(document.tempo, signature, document.tempo_points, document.meter_points)

func set_conductor(bpm: float, signature: Vector2i, tempos: Array, meters: Array) -> String:
	if _before != null: return "Finish the current edit before changing the conductor."
	var problem := KiwiAudioConductor.validate(bpm, signature, tempos, meters)
	if not problem.is_empty(): return problem
	if bpm == document.tempo and signature == document.time_signature and tempos == document.tempo_points and meters == document.meter_points: return ""
	# Validate before duplicating and do not retain aliases to the draft UI.
	var tempo_copy := tempos.duplicate(true)
	var meter_copy := meters.duplicate(true)
	action("Edit project conductor", func():
		if document.note_base_tempo == 0.0: document.note_base_tempo = document.tempo
		if document.note_base_meter == Vector2i.ZERO: document.note_base_meter = document.time_signature
		document.tempo = bpm; document.time_signature = signature
		document.tempo_points.assign(tempo_copy); document.meter_points.assign(meter_copy))
	return ""

func retime_note_sources(bpm: float) -> String:
	# This is the explicit legacy uniform-retime workflow, separate from
	# conductor-only editing. All changes, including source offsets, undo together.
	if _before != null: return "Finish the current edit before retiming sources."
	if not KiwiAudioConductor._number(bpm, 20.0, 400.0): return "Choose 20–400 BPM."
	var problem := document.midi_timing_error()
	if not problem.is_empty(): return problem
	problem = KiwiAudioConductor.validate(document.tempo, document.time_signature, document.tempo_points, document.meter_points)
	if not problem.is_empty(): return problem
	if bpm == document.tempo: return ""
	var ratio := document.tempo / bpm
	var tempos := document.tempo_points.duplicate(true)
	for point in tempos: point.bpm = float(point.bpm) / ratio
	problem = KiwiAudioConductor.validate(bpm, document.time_signature, tempos, document.meter_points)
	if not problem.is_empty(): return "Uniform retiming would put a conductor point outside 20–400 BPM."
	var operations: Array = []
	for index in document.clips.size():
		var clip := document.clips[index]; var actor := document.actors[index]
		if not is_note_source(actor): continue
		if not can_edit(clip.id) or document.track_for_clip(clip.id).has("frozen_track"): continue
		var mapped := actor.values.has(&"midi_tempos")
		var source_bpm := note_source_tempo(actor, document) / ratio
		var scale := float(actor.values.get(&"midi_tempo_scale", 1.0)) * ratio
		var pending := float(actor.values.get(&"notes_source_scale", 1.0)) * ratio
		if not KiwiAudioTempoMap._number_in(pending, KiwiAudioTempoMap.MIN_SCALE, KiwiAudioTempoMap.MAX_SCALE): return "The pending source-window scale is outside the supported range. Render the current notes before retiming again."
		if mapped:
			if not KiwiAudioTempoMap._number_in(scale, KiwiAudioTempoMap.MIN_SCALE, KiwiAudioTempoMap.MAX_SCALE): return "A MIDI source scale would leave the supported range."
		elif not KiwiAudioConductor._number(source_bpm, 20, 400): return "A note source would leave the supported 20–400 BPM range."
		var timing := KiwiAudioTempoMap.new(actor.values.get(&"midi_tempos", []), note_source_tempo(actor, document) if mapped else source_bpm, scale if mapped else 1.0)
		var last_beat := float(actor.values.get(&"pattern_beats", 0.0))
		for note in actor.values.get(&"notes", []): last_beat = maxf(last_beat, float(note.get("start", 0)) + float(note.get("duration", 0.25)))
		if not timing.error.is_empty() or timing.beat_to_seconds(last_beat) > KiwiAudioInstruments.MAX_SECONDS: return "Uniform retiming would exceed the 300-second editable note-source limit."
		operations.append({"clip": clip, "actor": actor, "mapped": mapped, "bpm": source_bpm, "scale": scale, "pending": pending})
	var arrangement_bpm := document.arrangement_tempo() / ratio
	if not document.sections.is_empty() and not KiwiAudioConductor._number(arrangement_bpm, 20, 400): return "The generated arrangement would leave the supported tempo range."
	action("Uniformly retime editable note sources", func():
		if document.note_base_tempo == 0.0: document.note_base_tempo = document.tempo
		if document.note_base_meter == Vector2i.ZERO: document.note_base_meter = document.time_signature
		for operation in operations:
			var clip: ActorClip = operation.clip; var actor: ActorData = operation.actor
			clip.start_time *= ratio; clip.duration *= ratio
			if bool(operation.mapped): actor.values[&"midi_tempo_scale"] = operation.scale
			else: actor.values[&"source_bpm"] = operation.bpm
			actor.values[&"notes_source_scale"] = operation.pending; actor.values[&"notes_dirty"] = true
		if not document.sections.is_empty(): document.composer_settings["tempo"] = arrangement_bpm
		document.tempo = bpm; document.tempo_points.assign(tempos))
	return ""

static func note_source_tempo(actor: ActorData, document: KiwiAudioDocument) -> float:
	return float(actor.values.get(&"source_bpm", document.note_tempo()))

static func note_source_meter(actor: ActorData, document: KiwiAudioDocument) -> Vector2i:
	var fallback := document.note_meter()
	var signature: Array = actor.values.get(&"source_meter", [fallback.x, fallback.y])
	return Vector2i(int(signature[0]), int(signature[1]))

static func is_note_source(actor: ActorData) -> bool:
	# Imported audio also carries an empty notes array; that alone must never
	# turn an ordinary recording into a silent synthesized pattern.
	return actor.values.has(&"pattern_beats") or actor.values.has(&"instrument") or not (actor.values.get(&"notes", []) as Array).is_empty()

static func apply_note_render(clip: ActorClip, actor: ActorData, stream: AudioStreamWAV, signature: String) -> void:
	# Notes are source-relative. Rerendering a split, slipped, trimmed or
	# stretched pattern must not reset its nondestructive timeline window.
	var scale := float(actor.values.get(&"notes_source_scale", 1.0))
	var old_length := float(actor.values.get(&"source_duration", 0.0)) * scale
	var offset := clip.source_offset * scale
	var full_source := offset < 0.00001 and absf(clip.duration * clip.playback_speed - old_length) < 0.001
	var length := stream.get_length()
	var frame := 1.0 / stream.mix_rate
	# A split/slipped loop may start after several source cycles. Keep that
	# offset rather than clamping it into the first cycle on every rerender.
	clip.source_offset = maxf(0.0, offset) if bool(actor.values.get(&"loop", false)) else clampf(offset, 0.0, maxf(0.0, length - frame))
	if full_source:
		clip.duration = length / clip.playback_speed
	elif not bool(actor.values.get(&"loop", false)):
		clip.duration = minf(clip.duration, maxf(frame, length - clip.source_offset) / clip.playback_speed)
	actor.values[&"audio"] = stream
	actor.values[&"source_duration"] = length
	actor.values[&"notes_dirty"] = false
	actor.values[&"rendered_signature"] = signature
	actor.values.erase(&"notes_source_scale")

func copy_effects(effects: Array) -> void:
	_effect_clipboard = effects.duplicate(true)

func pasted_effects() -> Array:
	return _effect_clipboard.duplicate(true)


func _notification(what: int) -> void:
	# UndoRedo is Object, not RefCounted; the session owns its lifetime.
	if what == NOTIFICATION_PREDELETE and is_instance_valid(history):
		history.clear_history()
		history.free()

static func note_signature(actor:ActorData,document:KiwiAudioDocument)->String:
	var track:=document.track_for_id(str(actor.values.get(&"track_id","")))
	var sustain:=bool(actor.values.get(&"midi_sustain",false))
	return var_to_str([actor.values.get(&"notes",[]),actor.values.get(&"instrument",track.get("instrument",{"id":"poly"})),note_source_tempo(actor,document),actor.values.get(&"pattern_beats",0),actor.values.get(&"step_settings",{}),actor.values.get(&"midi_tempos",[]),actor.values.get(&"midi_tempo_scale",1.0),sustain,actor.values.get(&"midi_events",[]) if sustain else []]).sha256_text()

static func render_note_source(notes:Array,instrument:Dictionary,bpm:float,step_settings:Dictionary,pattern_beats:float,tempos:Array=[],tempo_scale:float=1.0,job:RefCounted=null,sustain_events:Array=[])->AudioStreamWAV:
	# Shared by asynchronous editor previews and snapshot-based render/export.
	# Groove and ratchets remain beat-based, then the same instrument renderer
	# converts their note boundaries through the source's tempo map.
	var timing:=KiwiAudioTempoMap.new(tempos,bpm,tempo_scale)
	if not timing.error.is_empty():return null
	var seconds:=timing.beat_to_seconds(pattern_beats) if pattern_beats>0.0 else 0.0
	if seconds>KiwiAudioInstruments.MAX_SECONDS:return null
	if not sustain_events.is_empty():
		if not KiwiAudioTempoMap.validate_channel_events(sustain_events).is_empty():return null
		notes=KiwiAudioMIDI.sustain_copy(notes,sustain_events,pattern_beats,job)
		if job!=null and job.is_cancelled():return null
	var stream:=KiwiAudioInstruments.render_notes(KiwiAudioStepControls.render_copy(notes,step_settings,instrument),instrument,bpm,44100,job,tempos,tempo_scale)
	if stream!=null and pattern_beats>0.0:stream=KiwiAudioSourceCache.fit_pattern(stream,seconds)
	return stream

static func render_current_notes(document:KiwiAudioDocument,job:RefCounted=null)->String:
	var timing_error:=document.midi_timing_error()
	if not timing_error.is_empty():return timing_error
	# Call only with an owned snapshot. Derived PCM never rewrites source notes,
	# the live document, or an external source file.
	for i in document.clips.size():
		var actor:ActorData=document.actors[i]
		if not is_note_source(actor):continue
		var track:=document.track_for_clip(document.clips[i].id)
		if track.has("frozen_track"):continue
		var signature:=note_signature(actor,document)
		if not bool(actor.values.get(&"notes_dirty",false)) and str(actor.values.get(&"rendered_signature",""))==signature:continue
		if job!=null and job.is_cancelled():return "Cancelled."
		var instrument:Dictionary=actor.values.get(&"instrument",track.get("instrument",{"id":"poly"})).duplicate(true)
		var notes:Array=actor.values.get(&"notes",[]).duplicate(true)
		var sustain_events:Array=actor.values.get(&"midi_events",[]) if bool(actor.values.get(&"midi_sustain",false)) else []
		var stream:=render_note_source(notes,instrument,note_source_tempo(actor,document),actor.values.get(&"step_settings",{}),float(actor.values.get(&"pattern_beats",0)),actor.values.get(&"midi_tempos",[]),float(actor.values.get(&"midi_tempo_scale",1.0)),job,sustain_events)
		if stream==null:return "The current instrument notes could not be rendered. Check required samples and the 300-second source limit (including note releases). No output was saved."
		apply_note_render(document.clips[i],actor,stream,signature)
	return ""

func replace_rendered_clips(selection: Array, track_id: String, stream: AudioStream) -> String:
	if _before != null: return "Finish the current adjustment before replacing rendered clips."
	if selection.is_empty(): return "The rendered clip selection is empty. No clips were changed."
	var target := document.track_for_id(track_id)
	if target.is_empty() or bool(target.get("locked", false)) or str(target.get("kind", "")) == "automation":
		return "The replacement track is locked or unavailable. No clips were changed."
	var first := INF
	var ids: Dictionary = {}
	for value: Variant in selection:
		var id := str(value)
		var clip := document.clip_for_id(id)
		if clip == null or not can_edit(id) or str(document.track_for_clip(id).get("id", "")) != track_id:
			return "The rendered clips no longer share the intended unlocked track. No clips were changed."
		first = minf(first, clip.start_time)
		ids[id] = true
	if stream == null or not is_finite(stream.get_length()) or stream.get_length() <= 0.0:
		return "The rendered replacement has no playable audio. No clips were changed."
	begin("Render clips in place")
	# Insert successfully before removing any original. A failure rolls back
	# the complete snapshot; source Resources remain shared and untouched.
	var replacement := document.insert_source(stream, track_id, first, "Rendered selection")
	if replacement == null:
		cancel()
		return "The rendered audio could not be inserted. Original clips were preserved."
	var actor := document.actor_for_clip(replacement.id)
	# Clip fades are already baked; default import fades would apply them twice.
	actor.values[&"fade_in"] = 0.0
	actor.values[&"fade_out"] = 0.0
	for index in range(document.clips.size() - 1, -1, -1):
		if ids.has(document.clips[index].id):
			document.clips.remove_at(index)
			document.actors.remove_at(index)
	selected_ids.assign([replacement.id])
	selected_track = track_id
	commit()
	selection_changed.emit()
	return ""

# Active file references only: embedded edited PCM, original_audio provenance,
# sampler maps and generated note sources are deliberately not rebound here.
static func audio_source_key(value: Variant) -> String:
	if not value is String or value.is_empty(): return ""
	var key := ProjectSettings.globalize_path(value).replace("\\", "/").simplify_path()
	return key.to_lower() if OS.get_name() == "Windows" else key

func audio_source_clips(id: String) -> Array[String]:
	var result: Array[String] = []
	var actor := document.actor_for_clip(id)
	if actor == null: return result
	var key := audio_source_key(actor.values.get(&"audio"))
	if key.is_empty(): return result
	for clip in document.clips:
		var other := document.actor_for_clip(clip.id)
		if other != null and audio_source_key(other.values.get(&"audio")) == key: result.append(clip.id)
	return result

static func _relink_file_signature(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var result := {"bytes": file.get_length(), "modified": FileAccess.get_modified_time(path)}
	file.close()
	return result

static func probe_audio_relink(path: String, job: RefCounted = null) -> Dictionary:
	if path.is_empty() or path.get_extension().to_lower() not in ["wav", "mp3", "ogg", "flac"]:
		return {"error": "Choose a supported WAV, MP3, Ogg or FLAC source."}
	if job != null and job.is_cancelled(): return {"error": "Cancelled."}
	var signature := _relink_file_signature(path)
	if signature.is_empty() or int(signature.bytes) <= 0: return {"error": "The replacement source is missing, empty or unreadable."}
	var result := {"error": "", "path": path, "signature": signature, "seconds": 0.0}
	if job != null: job.update(0.1, "Checking replacement audio without changing the composition")
	# Bounded PCM inspection permits long WAVs without loading the whole source.
	if path.get_extension().to_lower() == "wav":
		var info := KiwiAudioPCMFile.inspect(path)
		if not str(info.get("error", "invalid")).is_empty(): return {"error": str(info.get("error", "Unsupported WAV replacement."))}
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null: return {"error": "The replacement WAV could not be read."}
		var first := KiwiAudioPCMFile.read_frames(file, info, 0, 1)
		var last := KiwiAudioPCMFile.read_frames(file, info, int(info.frames) - 1, 1)
		file.close()
		if first.size() != 1 or last.size() != 1: return {"error": "The replacement WAV is incomplete."}
		result.seconds = float(info.duration)
	else:
		if path.get_extension().to_lower() in ["mp3", "ogg"] and int(signature.bytes) > ActorAudio.MAX_NATIVE_WAV_BYTES:
			return {"error": "Compressed replacement validation is limited to 64 MiB encoded files. Convert this source to PCM WAV before relinking."}
		# Cached missing/duration results must not approve a newly replaced file.
		ActorAudio.invalidate(path)
		if ActorAudio.needs_file_preview(path): return {"error": "This compressed source exceeds the native validation limit. Convert it to PCM WAV before relinking; existing clips were preserved."}
		var stream := ActorAudio.source(path, job)
		if stream == null: return {"error": "The replacement cannot be decoded by the current audio backend."}
		result.seconds = stream.get_length()
		var decoder := stream.instantiate_playback()
		if decoder == null: return {"error": "The replacement decoder could not be initialized."}
		decoder.start(0.0)
		var samples := decoder.mix_audio(1.0, 32)
		decoder.stop()
		if samples.is_empty(): return {"error": "The replacement decoder returned no audio frames."}
		result.stream = stream # Validation handle only; never serialized into the document.
	if not is_finite(float(result.seconds)) or float(result.seconds) <= 0.0: return {"error": "The replacement has no valid audio duration."}
	if job != null and job.is_cancelled(): return {"error": "Cancelled."}
	if signature != _relink_file_signature(path): return {"error": "The replacement file changed while being checked. Choose it again."}
	return result

func audio_relink_problem(ids: Array, expected_source: String, replacement: Dictionary) -> String:
	if _before != null: return "Finish the current edit before relinking audio."
	if ids.is_empty(): return "No clips were selected for relinking."
	var key := audio_source_key(expected_source)
	if key.is_empty(): return "Only existing file-backed clip references can be relinked."
	if not str(replacement.get("error", "")).is_empty(): return str(replacement.error)
	var path: Variant = replacement.get("path")
	var seconds: Variant = replacement.get("seconds")
	if not path is String or path.is_empty() or path.get_extension().to_lower() not in ["wav", "mp3", "ogg", "flac"] or not (seconds is float or seconds is int):
		return "The replacement audio has not been validated."
	if not is_finite(float(seconds)) or float(seconds) <= 0.0: return "The replacement has no valid duration."
	var signature: Variant = replacement.get("signature")
	if not signature is Dictionary or signature.is_empty() or signature != _relink_file_signature(path):
		return "The replacement file is missing or changed. Choose it again."
	if path.get_extension().to_lower() == "wav":
		var info := KiwiAudioPCMFile.inspect(path)
		if not str(info.get("error", "invalid")).is_empty() or absf(float(info.get("duration", 0.0)) - float(seconds)) > 0.000001:
			return "The replacement WAV no longer matches its validation. Choose it again."
	else:
		var stream: Variant = replacement.get("stream")
		if not stream is AudioStream or absf(stream.get_length() - float(seconds)) > 0.000001:
			return "The replacement decoder is unavailable. Choose the source again."
	var seen := {}
	for value: Variant in ids:
		if not value is String or value.is_empty() or seen.has(value): return "The relink selection contains an invalid or duplicate clip."
		seen[value] = true
		var clip := document.clip_for_id(value)
		var actor := document.actor_for_clip(value)
		var track := document.track_for_clip(value)
		if clip == null or actor == null or track.is_empty(): return "A clip selected for relinking is missing. No clips were changed."
		if not can_edit(value) or track.has("frozen_track") or track.has("frozen_source"): return "A selected clip is locked or frozen. No clips were changed."
		if audio_source_key(actor.values.get(&"audio")) != key: return "A selected clip's source changed. Choose the replacement again."
		if is_note_source(actor): return "Generated note sources cannot be relinked as audio. Restore their instrument samples or render them separately."
		if not is_finite(clip.start_time) or clip.start_time < 0 or not is_finite(clip.source_offset) or clip.source_offset < 0 or not is_finite(clip.duration) or clip.duration <= 0 or not is_finite(clip.playback_speed) or clip.playback_speed < 0.05 or clip.playback_speed > 16:
			return "A selected clip has invalid source geometry. No clips were changed."
		if bool(actor.values.get(&"loop", false)):
			var period := float(actor.values.get(&"source_duration", 0.0))
			if not is_finite(period) or period <= 0.0 or absf(period - float(seconds)) > 0.000001:
				return "A looped clip requires the original source duration to preserve its loop period. No clips were changed."
		else:
			var end := clip.source_offset + clip.duration * clip.playback_speed
			if not is_finite(end) or end > float(seconds) + 0.000001:
				return "The replacement is too short for an existing source window. No clips were changed."
	return ""

func relink_audio_sources(ids: Array, expected_source: String, replacement: Dictionary) -> String:
	var problem := audio_relink_problem(ids, expected_source, replacement)
	if not problem.is_empty(): return problem
	var changes: Array[ActorData] = []
	for id: String in ids:
		var actor := document.actor_for_clip(id)
		if actor.values.get(&"audio") != replacement.path or float(actor.values.get(&"source_duration", 0.0)) != float(replacement.seconds) or actor.values.has(&"transients") or actor.values.has(&"transients_source_identity"): changes.append(actor)
	ActorAudio.invalidate(str(replacement.path))
	if changes.is_empty(): return ""
	# All references/windows were checked first. Never reconstruct a clip, reset
	# an offset, change duration/speed, or overwrite original_audio provenance.
	action("Relink audio sources", func():
		for actor in changes:
			actor.values[&"audio"] = replacement.path
			actor.values[&"source_duration"] = float(replacement.seconds)
			actor.values.erase(&"transients")
			actor.values.erase(&"transients_source_identity"))
	return ""

# Detection geometry is immutable. Review choices live outside the plan; applying
# consumes it only after every source, scope and piece has passed preflight.
class SilencePlan extends RefCounted:
	var _owner: WeakRef
	var _document: WeakRef
	var _revision: int
	var _clip_id: String
	var _identity: String
	var _geometry: Array
	var _values: Dictionary
	var _regions: Array[Dictionary] = []
	var _cuts: Array[Dictionary] = []
	var _source_duration: float
	var _closed := false
	func cancel() -> void: _closed = true
	func regions() -> Array[Dictionary]: return _regions.duplicate(true)
	func cuts() -> Array[Dictionary]: return _cuts.duplicate(true)
	func clip_id() -> String: return _clip_id
	func current(session: KiwiAudioEditSession) -> bool:
		if _closed or _owner.get_ref() != session or _document.get_ref() != session.document or _revision != session.revision or session._before != null: return false
		var clip := session.document.clip_for_id(_clip_id)
		var actor := session.document.actor_for_clip(_clip_id)
		return clip != null and actor != null and _geometry == KiwiAudioEditSession._silence_geometry(clip, actor) and _values == actor.values and _identity == KiwiAudioEditSession.silence_source_identity(actor)

static func silence_source_identity(actor: ActorData) -> String:
	if actor == null: return ""
	var value: Variant = actor.values.get(&"audio")
	if value is AudioStream: return actor.id + ":" + str(value.get_instance_id())
	if not value is String or value.is_empty(): return ""
	var file := FileAccess.open(value, FileAccess.READ)
	if file == null: return ""
	var size := file.get_length(); file.close()
	return actor.id + ":" + str(value) + ":" + str(FileAccess.get_modified_time(value)) + ":" + str(size)

static func _silence_geometry(clip: ActorClip, actor: ActorData) -> Array:
	return [clip.id, clip.actor_id, clip.start_time, clip.duration, clip.source_offset, clip.playback_speed, clip.layer,
		actor.id, actor.type_id, actor.display_name, actor.parent_id, actor.section_id, actor.show_timeline_children, actor.link_timeline_children, actor.schema_version]

func _silence_reason(id: String) -> String:
	var clip := document.clip_for_id(id); var actor := document.actor_for_clip(id)
	if clip == null or actor == null: return "The selected clip no longer exists."
	var track := document.track_for_clip(id)
	if not can_edit(id) or track.has("frozen_track") or track.has("frozen_source"): return "The selected clip is locked or frozen."
	var reason := KiwiAudioRegionEdit.unsupported_reason(clip, actor, "cut")
	if not reason.is_empty(): return reason
	for take in document.takes:
		if str(take.get("clip_id", "")) == id: return "This clip belongs to a recording take. Duplicate it to an ordinary audio clip before silence cleanup so take controls remain intact."
	for lane in document.tracks:
		var target: Dictionary = lane.get("automation_target", {})
		if str(target.get("owner_kind", "")) == "clip" and str(target.get("owner_id", "")) == id: return "Remove this clip's automation-lane binding before silence cleanup; a lane cannot target several resulting pieces."
	return ""

func create_silence_plan(id: String, silences: Array, source_duration: float, keep: float, identity: String) -> Dictionary:
	if _before != null: return {"error": "Finish the current adjustment before reviewing silence cleanup."}
	var reason := _silence_reason(id)
	if not reason.is_empty(): return {"error": reason}
	if not is_finite(source_duration) or source_duration <= 0 or source_duration > 600.001 or not is_finite(keep) or keep < 0 or keep > 10:
		return {"error": "Invalid silence settings. Whole-source analysis is limited to 600 seconds."}
	if silences.size() > 2048: return {"error": "More than 2048 quiet regions were detected. Increase the minimum pause duration and analyze again."}
	var clip := document.clip_for_id(id); var actor := document.actor_for_clip(id)
	if identity.is_empty() or identity != silence_source_identity(actor): return {"error": "The analyzed source changed or is missing. Analyze it again."}
	var end := clip.source_offset + clip.duration * clip.playback_speed
	if end > source_duration + 0.0001: return {"error": "The clip extends beyond the analyzed source. Trim or render it before silence cleanup."}
	var plan := SilencePlan.new()
	plan._owner = weakref(self); plan._document = weakref(document); plan._revision = revision
	plan._clip_id = id; plan._identity = identity; plan._source_duration = source_duration
	plan._geometry = _silence_geometry(clip, actor); plan._geometry.make_read_only()
	plan._values = actor.values.duplicate(true)
	var previous := -1.0
	for region: Variant in silences:
		if not region is Dictionary or not region.get("start") is float and not region.get("start") is int or not region.get("end") is float and not region.get("end") is int:
			return {"error": "Invalid quiet-region data. Analyze again."}
		var first := float(region.start); var last := float(region.end)
		if not is_finite(first) or not is_finite(last) or first < 0 or first < previous or last <= first or last > source_duration + 0.0001:
			return {"error": "Quiet regions overlap or have invalid boundaries. Analyze again."}
		previous = last
		var a := maxf(first, clip.source_offset); var b := minf(last, end)
		if b <= a: continue
		var retained := minf(keep * clip.playback_speed, b - a)
		var quiet := {"start": a, "end": b}; quiet.make_read_only()
		plan._regions.append(quiet)
		var cut := {"start": a + retained * 0.5, "end": b - retained * 0.5}; cut.make_read_only()
		plan._cuts.append(cut)
	plan._regions.make_read_only(); plan._cuts.make_read_only()
	return {"error": "", "plan": plan}

func preview_silence_plan(plan: SilencePlan, remove: Array, scope: String = "clip") -> Dictionary:
	if plan == null or not plan.current(self): return {"error": "This cleanup plan is stale or cancelled. Analyze and review again."}
	var reason := _silence_reason(plan._clip_id)
	if not reason.is_empty(): return {"error": reason}
	if scope not in ["clip", "track_following"]: return {"error": "Choose an explicit cleanup scope."}
	var clip := document.clip_for_id(plan._clip_id); var actor := document.actor_for_clip(plan._clip_id)
	var chosen := {}; var cuts: Array[Dictionary] = []
	for index: Variant in remove:
		if not index is int or index < 0 or index >= plan._cuts.size() or chosen.has(index): return {"error": "Invalid or duplicate review choice."}
		chosen[index] = true
	for i in plan._cuts.size():
		if chosen.has(i) and plan._cuts[i].end - plan._cuts[i].start > 0.000001: cuts.append(plan._cuts[i])
	var ranges: Array[Dictionary] = []; var cursor := clip.source_offset
	var end := clip.source_offset + clip.duration * clip.playback_speed; var removed := 0.0
	var fade_in := float(actor.values.get(&"fade_in", 0.0)); var fade_out := float(actor.values.get(&"fade_out", 0.0))
	if not is_finite(fade_in) or not is_finite(fade_out) or fade_in < 0 or fade_out < 0: return {"error": "Invalid clip fades."}
	for cut in cuts:
		if fade_in > 0 and cut.start < clip.source_offset + fade_in * clip.playback_speed - 0.000001 or fade_out > 0 and cut.end > end - fade_out * clip.playback_speed + 0.000001:
			return {"error": "A chosen removal intersects an existing clip fade. Keep that region or render the fade first."}
		if cut.start > cursor + 0.000001: ranges.append({"start": cursor, "end": cut.start})
		cursor = cut.end; removed += (cut.end - cut.start) / clip.playback_speed
	if cursor < end - 0.000001: ranges.append({"start": cursor, "end": end})
	if ranges.is_empty(): return {"error": "The entire clip would be removed. Keep at least one region, retain a pause, or delete the clip manually."}
	var moved: Array[String] = []; var old_end := clip.start_time + clip.duration
	var track_id := str(actor.values.get(&"track_id", ""))
	if scope == "track_following" and removed > 0:
		for other in document.clips:
			if other.id == clip.id or str(document.track_for_clip(other.id).get("id", "")) != track_id: continue
			if other.start_time < old_end - 0.000001 and other.start_time + other.duration > clip.start_time + 0.000001:
				return {"error": "Another clip overlaps this clip on the same track. Use selected-clip-only scope or resolve the overlap first."}
			if other.start_time >= old_end - 0.000001:
				var track := document.track_for_clip(other.id)
				if not can_edit(other.id) or track.has("frozen_track") or track.has("frozen_source"): return {"error": "A following clip is locked or frozen. No clips were changed."}
				moved.append(other.id)
	return {"error": "", "ranges": ranges, "cuts": cuts, "removed": removed, "remaining": clip.duration - removed, "moved_ids": moved, "scope": scope}

func apply_silence_plan(plan: SilencePlan, remove: Array, scope: String = "clip") -> Dictionary:
	var review := preview_silence_plan(plan, remove, scope)
	if not str(review.get("error", "")).is_empty(): return review
	if float(review.removed) <= 0.000001: return {"error": "", "changed": false, "removed": 0.0}
	var clip := document.clip_for_id(plan._clip_id); var actor := document.actor_for_clip(plan._clip_id)
	var index := document.clips.find(clip); var at := clip.start_time; var parts: Array[Dictionary] = []
	var end := clip.source_offset + clip.duration * clip.playback_speed
	for interval: Dictionary in review.ranges:
		var part := KiwiAudioRegionEdit._piece(actor, clip, at, interval.start, (interval.end - interval.start) / clip.playback_speed)
		# Preserve the original stable IDs on the first piece, all metadata and the
		# unmodified source reference. New boundaries get short non-overlap fades.
		if parts.is_empty(): part.actor.id = actor.id; part.clip.id = clip.id; part.clip.actor_id = actor.id
		part.actor.values[&"fade_in"] = float(actor.values.get(&"fade_in", 0.0)) if absf(interval.start - clip.source_offset) < 0.000001 else minf(0.003, part.clip.duration * 0.1)
		part.actor.values[&"fade_out"] = float(actor.values.get(&"fade_out", 0.0)) if absf(interval.end - end) < 0.000001 else minf(0.005, part.clip.duration * 0.1)
		parts.append(part); at += part.clip.duration
	plan.cancel() # Synchronous changed callbacks cannot apply it twice.
	action("Reviewed silence cleanup", func():
		document.clips.remove_at(index); document.actors.remove_at(index)
		selected_ids.clear()
		for i in parts.size():
			document.clips.insert(index + i, parts[i].clip); document.actors.insert(index + i, parts[i].actor)
			selected_ids.append(parts[i].clip.id)
		for id: String in review.moved_ids: document.clip_for_id(id).start_time -= float(review.removed))
	selection_changed.emit()
	return {"error": "", "changed": true, "removed": review.removed, "clip_ids": selected_ids.duplicate(), "moved_ids": review.moved_ids}

func silence_boundary(plan: SilencePlan, remove: Array, region: int) -> Dictionary:
	var review := preview_silence_plan(plan, remove)
	if not str(review.get("error", "")).is_empty(): return review
	if region < 0 or region >= plan._cuts.size() or not remove.has(region): return {"error": "Select a region marked Remove to audition its proposed boundary."}
	var cut := plan._cuts[region]
	if cut.end - cut.start <= 0.000001: return {"error": "This region removes no time with the retained-pause setting."}
	var clip := document.clip_for_id(plan._clip_id)
	var left := Vector2.ZERO; var right := Vector2.ZERO; var fade_out := 0.0; var fade_in := 0.0
	for interval: Dictionary in review.ranges:
		if absf(interval.end - cut.start) < 0.000001:
			left = Vector2(maxf(interval.start, interval.end - 0.35 * clip.playback_speed), interval.end)
			fade_out = minf(0.005, (interval.end - interval.start) / clip.playback_speed * 0.1)
		if absf(interval.start - cut.end) < 0.000001:
			right = Vector2(interval.start, minf(interval.end, interval.start + 0.35 * clip.playback_speed))
			fade_in = minf(0.003, (interval.end - interval.start) / clip.playback_speed * 0.1)
	if left == Vector2.ZERO and right == Vector2.ZERO: return {"error": "This boundary joins another removal. Audition an outside boundary instead."}
	return {"error": "", "left": left, "right": right, "speed": clip.playback_speed, "fade_in": fade_in, "fade_out": fade_out,
		"source": document.actor_for_clip(plan._clip_id).values.get(&"audio"), "fade_curve": str(document.actor_for_clip(plan._clip_id).values.get(&"fade_curve", "linear"))}
