class_name KiwiAudioRegionEdit
extends RefCounted
## Selection-sized PCM edits. Never decodes, rewrites or replaces the untouched
## source regions. Source references remain shared by document undo snapshots.
const MAX_WORKING_BYTES := 32 * 1024 * 1024
const OPERATIONS := ["copy", "cut", "paste", "trim", "silence", "amplify", "normalize", "reverse", "fade_in", "fade_out", "repair", "invert", "mono", "time_stretch", "pitch_shift", "set_amplitude"]
const EPSILON := 0.000000001

static func prepare(clip: ActorClip, actor: ActorData, stream: AudioStream, operation: String, selection: Vector2i, rate: int, amount: float = 0.0, channel: int = -1, clipboard: PackedVector2Array = PackedVector2Array(), clipboard_rate: int = 0, job: RefCounted = null) -> Dictionary:
	if clip == null or actor == null or stream == null: return _failure("The selected audio source is missing.")
	if operation not in OPERATIONS: return _failure("Unknown sample-selection operation.")
	if rate < 8000 or rate > 192000: return _failure("This source sample rate is not supported for sample-selection editing (8–192 kHz).")
	if channel < -1 or channel > 1 or not is_finite(amount): return _failure("Invalid sample-edit settings.")
	if operation == "set_amplitude" and (amount < -1. or amount > 1.): return _failure("Sample amplitude must be between -1 and 1.")
	if channel >= 0 and operation in ["cut", "paste", "trim", "time_stretch"]: return _failure("Choose Stereo for duration-changing edits so both channels stay aligned.")
	var reason := unsupported_reason(clip, actor, operation)
	if not reason.is_empty(): return _failure(reason)
	if _cancelled(job): return _failure("Cancelled.")
	var source_end := clip.source_offset + clip.duration * clip.playback_speed
	if source_end > stream.get_length() + 1.0 / rate: return _failure("The clip extends past its source. Trim or render it before sample editing.")
	# Selection coordinates are source frames, not timeline frames. Preserve any
	# fractional-frame geometry in untouched neighbors rather than rounding it.
	var minimum := int(ceil(clip.source_offset * rate - 0.000001))
	var maximum := int(floor(minf(source_end, stream.get_length()) * rate + 0.000001))
	if maximum < minimum: return _failure("The clip is shorter than one source sample.")
	if selection.y < selection.x or selection.x < minimum - 1 or selection.y > maximum + 1: return _failure("Select a region inside the opened clip before editing.")
	var first := clampi(selection.x, minimum, maximum)
	var last := clampi(selection.y, first, maximum)
	var count := last - first
	if count == 0 and operation != "paste": return _failure("Select audio to process.")
	if operation == "paste" and clipboard.is_empty(): return _failure("Copy or cut some audio before pasting.")
	var result := {"error": "", "operation": operation, "clip_id": clip.id, "source_reference": actor.values.get(&"audio"), "source_stream": stream,
		"start_time": clip.start_time, "source_offset": clip.source_offset, "duration": clip.duration, "playback_speed": clip.playback_speed,
		"first": first, "last": last, "rate": rate, "selection": Vector2i(first, last), "inserted_frames": 0, "working_bytes": 0}
	if operation == "trim": return result
	var output_count := count
	if operation == "cut" or operation == "copy": output_count = 0
	if operation == "paste":
		var from_rate := clipboard_rate if clipboard_rate > 0 else rate
		if from_rate < 8000 or from_rate > 192000: return _failure("The copied audio has an unsupported sample rate.")
		output_count = maxi(1, int(round(float(clipboard.size()) * rate / from_rate)))
	elif operation == "time_stretch": output_count = maxi(1, int(round(count * clampf(amount, 0.25, 4.0))))
	# Account conservatively for decode/edit/slice buffers, stereo WAV encoding,
	# clipboard retention and decoder chunks, before any selection allocation.
	var working_bytes := 0
	if operation in ["cut", "copy"]: working_bytes = (count + 2) * 8 + 65536
	elif operation == "paste": working_bytes = output_count * 24 + 65536
	else: working_bytes = (count + 2) * 32 + output_count * 24 + 65536
	if working_bytes > MAX_WORKING_BYTES: return _failure("This selection exceeds the 32 MiB sample-edit working budget. Select a shorter region; the untouched source can be any length.")
	result.working_bytes = working_bytes
	result.inserted_frames = output_count
	if job != null: job.update(0.1, "Processing selected samples only")
	if operation == "paste":
		var pasted := _resample(clipboard, clipboard_rate if clipboard_rate > 0 else rate, rate, output_count)
		if _cancelled(job): return _failure("Cancelled.")
		result.stream = KiwiAudioSourceCache.to_wav(pasted, rate, true)
		return result
	# Repair needs only one original sample on either side, never a full decode.
	var decode_first := maxi(0, first - 1) if operation == "repair" else first
	var decode_last := mini(int(round(stream.get_length() * rate)), last + 1) if operation == "repair" else last
	var decoded := KiwiAudioSourceCache.decode(stream, rate, float(decode_first) / rate, float(decode_last - decode_first) / rate, float(decode_last - decode_first + 1) / rate)
	if not str(decoded.get("error", "")).is_empty(): return decoded
	var samples: PackedVector2Array = decoded.samples
	if samples.size() != decode_last - decode_first: return _failure("The decoder returned an incomplete selection. No audio was changed.")
	if _cancelled(job): return _failure("Cancelled.")
	if operation in ["copy", "cut"]:
		result.clipboard = samples
		result.clipboard_rate = rate
		return result
	var output: PackedVector2Array
	if operation in ["time_stretch", "pitch_shift"]:
		var transformed := KiwiAudioAnalysis.transform_selection(samples, operation, 0, count, amount, channel, rate, job)
		if not str(transformed.get("error", "")).is_empty(): return transformed
		output = transformed.samples
		result.inserted_frames = int(transformed.inserted_frames)
	else:
		var local_first := first - decode_first
		output = KiwiAudioAnalysis.edit(samples, operation, local_first, local_first + count, amount, channel)
		if decode_first != first or decode_last != last: output = output.slice(local_first, local_first + count)
	if _cancelled(job): return _failure("Cancelled.")
	result.stream = KiwiAudioSourceCache.to_wav(output, rate, true)
	return result

static func unsupported_reason(clip: ActorClip, actor: ActorData, operation: String) -> String:
	if not is_finite(clip.start_time) or not is_finite(clip.source_offset) or not is_finite(clip.duration) or not is_finite(clip.playback_speed) or clip.start_time < 0 or clip.source_offset < 0 or clip.duration <= 0 or clip.playback_speed <= 0:
		return "The clip has invalid source geometry."
	# Raw-source copy does not rearrange clip playback or processing state.
	if operation == "copy": return ""
	if bool(actor.values.get(&"reverse", false)): return "Render the reversed clip in place before sample-selection editing."
	if bool(actor.values.get(&"loop", false)): return "Render the looped clip in place before sample-selection editing."
	if not (actor.values.get(&"effects", []) as Array).is_empty(): return "Render or remove the clip effects before sample-selection editing; splitting would restart their processing state. Track effects can remain."
	if not (actor.values.get(&"automation", {}) as Dictionary).is_empty() or not actor.animation_tracks.is_empty(): return "Render or remove clip automation before sample-selection editing so its timing is preserved."
	if not is_equal_approx(float(actor.values.get(&"pitch", 1.0)), 1.0): return "Render the pitch-processed clip in place before sample-selection editing."
	if KiwiAudioEditSession.is_note_source(actor): return "Render the instrument pattern in place before editing its audio samples."
	return ""

static func apply(session: KiwiAudioEditSession, result: Dictionary) -> Dictionary:
	if not str(result.get("error", "")).is_empty(): return result
	var id := str(result.get("clip_id", ""))
	if not session.can_edit(id): return _failure("The clip's track is locked or unavailable. No audio was changed.")
	var track := session.document.track_for_clip(id)
	if track.has("frozen_track") or track.has("frozen_source"): return _failure("Unfreeze the track before sample editing. No audio was changed.")
	var clip := session.document.clip_for_id(id)
	var actor := session.document.actor_for_clip(id)
	if clip == null or actor == null: return _failure("The edited clip no longer exists.")
	if session._before != null: return _failure("Finish the current adjustment and apply the selection edit again.")
	if actor.values.get(&"audio") != result.get("source_reference") or clip.start_time != float(result.start_time) or clip.source_offset != float(result.source_offset) or clip.duration != float(result.duration) or clip.playback_speed != float(result.playback_speed):
		return _failure("The clip or its source changed during processing. Apply the selection edit again.")
	if ActorAudio.source(actor.values.get(&"audio")) != result.get("source_stream"): return _failure("The source file changed during processing. Reopen the waveform before editing.")
	var operation := str(result.operation)
	var reason := unsupported_reason(clip, actor, operation)
	if not reason.is_empty(): return _failure(reason)
	if operation == "copy": return {"error": "", "focus_clip_id": id, "clip_ids": [id]}
	var rate := int(result.rate)
	var first := float(result.first) / rate
	var last := float(result.last) / rate
	if operation == "trim":
		session.action("Trim waveform selection", func():
			clip.source_offset = first
			clip.duration = (last - first) / clip.playback_speed
			# Trimming is geometry-only: source resource/path and audio bytes stay intact.
			session.selected_ids.assign([id]))
		session.selection_changed.emit()
		return {"error": "", "focus_clip_id": id, "clip_ids": [id]}
	var source_end := clip.source_offset + clip.duration * clip.playback_speed
	var parts: Array[Dictionary] = []
	var at := clip.start_time
	if first > clip.source_offset + EPSILON:
		parts.append(_piece(actor, clip, at, clip.source_offset, (first - clip.source_offset) / clip.playback_speed))
		at += float(parts.back().clip.duration)
	var focus_index := parts.size()
	if operation != "cut":
		var edited: AudioStreamWAV = result.get("stream") as AudioStreamWAV
		if edited == null or int(result.get("inserted_frames", 0)) <= 0: return _failure("The edit produced no audio. No source was changed.")
		var middle := _piece(actor, clip, at, 0.0, float(result.inserted_frames) / rate / clip.playback_speed)
		middle.actor.values[&"original_audio"] = actor.values.get(&"original_audio", actor.values.get(&"audio"))
		middle.actor.values[&"audio"] = edited
		middle.actor.values[&"source_duration"] = edited.get_length()
		middle.actor.values.erase(&"transients")
		middle.actor.values.erase(&"transients_source_identity")
		parts.append(middle)
		at += middle.clip.duration
	if last < source_end - EPSILON:
		parts.append(_piece(actor, clip, at, last, (source_end - last) / clip.playback_speed))
	# Do not invent fades at the new joins or restart an existing long fade.
	# Endpoint fades can stay only if wholly contained in the outer pieces.
	if not parts.is_empty():
		var fade_in := minf(float(actor.values.get(&"fade_in", 0.0)), clip.duration)
		var fade_out := minf(float(actor.values.get(&"fade_out", 0.0)), clip.duration)
		if parts.size() > 1 and (float(parts.front().clip.duration) + EPSILON < fade_in or float(parts.back().clip.duration) + EPSILON < fade_out):
			return _failure("This selection crosses a clip fade. Shorten or remove the clip fade, or render the clip in place before editing.")
		parts.front().actor.values[&"fade_in"] = fade_in
		parts.back().actor.values[&"fade_out"] = fade_out
		focus_index = mini(focus_index, parts.size() - 1)
		# Keeping the original ID on the focused piece makes undo selection stable.
		parts[focus_index].clip.id = clip.id
		parts[focus_index].clip.actor_id = actor.id
		parts[focus_index].actor.id = actor.id
	var ids: Array[String] = []
	for part in parts: ids.append(part.clip.id)
	var focus_id := ids[focus_index] if not ids.is_empty() else ""
	var index := session.document.clips.find(clip)
	if index < 0: return _failure("The selected clip is no longer in this document.")
	session.action("Edit waveform " + operation, func():
		session.document.clips.remove_at(index)
		session.document.actors.remove_at(index)
		for i in parts.size():
			session.document.clips.insert(index + i, parts[i].clip)
			session.document.actors.insert(index + i, parts[i].actor)
		session.selected_ids.clear()
		if not focus_id.is_empty(): session.selected_ids.append(focus_id))
	session.selection_changed.emit()
	return {"error": "", "focus_clip_id": focus_id, "clip_ids": ids}

static func _piece(actor: ActorData, clip: ActorClip, at: float, offset: float, duration: float) -> Dictionary:
	var copy := ActorData.new()
	copy.id = ActorData.new_id()
	copy.type_id = actor.type_id
	copy.display_name = actor.display_name
	copy.parent_id = actor.parent_id
	copy.section_id = actor.section_id
	copy.show_timeline_children = actor.show_timeline_children
	copy.link_timeline_children = actor.link_timeline_children
	copy.schema_version = actor.schema_version
	copy.values = actor.values.duplicate(true)
	copy.values[&"fade_in"] = 0.0
	copy.values[&"fade_out"] = 0.0
	var part: ActorClip = clip.duplicate(false)
	part.id = ActorData.new_id()
	part.actor_id = copy.id
	part.start_time = at
	part.source_offset = offset
	part.duration = duration
	return {"actor": copy, "clip": part}

static func _resample(samples: PackedVector2Array, from_rate: int, to_rate: int, count: int) -> PackedVector2Array:
	if from_rate == to_rate: return samples
	var output := PackedVector2Array()
	output.resize(count)
	for i in count:
		var source_position := float(i) * from_rate / to_rate
		var first := mini(int(floor(source_position)), samples.size() - 1)
		var second := mini(first + 1, samples.size() - 1)
		output[i] = samples[first].lerp(samples[second], source_position - first)
	return output

static func _cancelled(job: RefCounted) -> bool:
	return job != null and job.is_cancelled()

static func _failure(message: String) -> Dictionary:
	return {"error": message}
