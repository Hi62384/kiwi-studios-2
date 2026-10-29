class_name ActorTimeline
extends RefCounted
## Clips share layers, with non-overlapping time intervals within each layer.

signal changed
signal selection_requested

const MIN_DURATION: float = 0.1

var actors: Array[ActorData] = []
var clips: Array[ActorClip] = []
## Every selected clip. The final entry is the primary selection.
var selected_ids: Array[String] = []
var selected_id: String = ""
var selected_layer: int = 0
var history := UndoRedo.new()
var sections: Array[ActorSection] = [ActorSection.new()]
var selected_section_id: String = "default"
## Timeline navigation only; does not change transform parenting or viewport visibility.
var focused_actor_id: String = ""
var playhead_time: float = 0.0
## Inspector diamond overlay selection is editor navigation, not saved animation.
var overlay_actor_id: String = ""
var overlay_path := PackedStringArray()
var property_batch_active := false
var _audio_preview_before: Dictionary = {}


func audio_snapshot(actor: ActorData) -> Dictionary:
	var clip := clip_for_actor_id(actor.id)
	return {"actor": actor, "values": actor.values.duplicate(true), "clip": clip, "duration": clip.duration,
		"offset": clip.source_offset, "speed": clip.playback_speed, "layer": clip.layer}

func restore_audio(state: Dictionary) -> void:
	state.actor.values = state.values.duplicate(true)
	state.clip.duration = state.duration
	state.clip.source_offset = state.offset
	state.clip.playback_speed = state.speed
	state.clip.layer = state.layer
	state.actor.emit_changed()
	changed.emit()

func minimum_duration(clip: ActorClip) -> float:
	var actor := actor_for_id(clip.actor_id)
	var length := ActorAudio.length(actor) if actor != null and actor.type_id in [&"audio", &"video", &"video_2d"] else 0.0
	return minf(MIN_DURATION, minf(clip.duration, length / clip.playback_speed)) if length > 0.0 else MIN_DURATION

func linked_clip_ids(ids: Array[String]) -> Array[String]:
	var result: Array[String] = ids.duplicate()
	var cursor := 0
	while cursor < result.size():
		var index := _index_of(result[cursor])
		cursor += 1
		if index < 0 or not actors[index].link_timeline_children: continue
		for actor in actors:
			if actor.parent_id != actors[index].id: continue
			var child := clip_for_actor_id(actor.id)
			if child != null and not result.has(child.id): result.append(child.id)
	return result

func set_timeline_children_linked(actor_id: String, linked: bool) -> void:
	var actor := actor_for_id(actor_id)
	if actor == null or actor.link_timeline_children == linked: return
	history.create_action("Link Children" if linked else "Unlink Children")
	history.add_do_method(_set_children_link.bind(actor, linked))
	history.add_undo_method(_set_children_link.bind(actor, actor.link_timeline_children))
	history.commit_action()

func _set_children_link(actor: ActorData, linked: bool) -> void:
	actor.link_timeline_children = linked
	actor.emit_changed()
	changed.emit()

## Structural media commands preserve identities and timing as one undo step.
func media_snapshot() -> Dictionary:
	var actor_states: Array[Dictionary] = []
	for actor in actors:
		actor_states.append({"actor": actor, "values": actor.values.duplicate(), "parent": actor.parent_id,
			"visible": actor.show_timeline_children, "linked": actor.link_timeline_children})
	var timings: Dictionary = {}
	for clip in clips:
		timings[clip.id] = {"start": clip.start_time, "duration": clip.duration, "offset": clip.source_offset, "layer": clip.layer}
	return {"actors": actors.duplicate(), "clips": clips.duplicate(), "states": actor_states, "timings": timings,
		"selection": selected_ids.duplicate(), "primary": selected_id, "layer": selected_layer}

func restore_media(state: Dictionary) -> void:
	actors.assign(state.actors)
	clips.assign(state.clips)
	for entry in state.states:
		entry.actor.values = entry.values.duplicate()
		entry.actor.parent_id = entry.parent
		entry.actor.show_timeline_children = entry.visible
		entry.actor.link_timeline_children = entry.linked
		entry.actor.emit_changed()
	for clip in clips:
		var timing: Dictionary = state.timings[clip.id]
		clip.start_time = timing.start
		clip.duration = timing.duration
		clip.source_offset = timing.offset
		clip.layer = timing.layer
	selected_ids.assign(state.selection)
	selected_id = state.primary
	selected_layer = state.layer
	changed.emit()

func commit_media(before: Dictionary, label: String) -> void:
	var after := media_snapshot()
	history.create_action(label)
	history.add_do_method(restore_media.bind(after))
	history.add_undo_method(restore_media.bind(before))
	history.commit_action()

func configure_video_audio(actor: ActorData) -> void:
	var source := ActorVideo.audio(str(actor.values.get(&"video", "")))
	actor.values[&"linked_audio_actor"] = ""
	if source == null: return
	var definition := load("res://scripts/actors/examples/audio_actor.tres") as ActorDefinition
	var audio_actor := definition.create_actor({&"audio": source})
	audio_actor.display_name = actor.display_name + " Audio"
	audio_actor.parent_id = actor.id
	audio_actor.section_id = actor.section_id
	var video_clip := clip_for_actor_id(actor.id)
	var audio_clip := ActorClip.create(audio_actor, video_clip.start_time, video_clip.duration)
	audio_clip.source_offset = video_clip.source_offset
	audio_clip.layer = video_clip.layer + 1
	actors.append(audio_actor)
	clips.append(audio_clip)
	while not can_place(audio_clip.id, audio_clip.start_time, audio_clip.duration, audio_clip.layer): audio_clip.layer += 1
	actor.values[&"linked_audio_actor"] = audio_actor.id

func create_video_audio(actor: ActorData) -> void:
	if not actors.has(actor) or actor.type_id not in [&"video", &"video_2d"] or actor_for_id(str(actor.values.get(&"linked_audio_actor", ""))) != null: return
	var before := media_snapshot()
	configure_video_audio(actor)
	if str(actor.values.get(&"linked_audio_actor", "")).is_empty(): return
	commit_media(before, "Create Linked Video Audio")

func edit_video_property(actor: ActorData, key: StringName, value: Variant) -> void:
	var source := ActorVideo.info(str(value)) if key == &"video" and value != null and str(value) != "" else {}
	if key == &"video" and str(value) != "" and value != null and source.is_empty(): return
	if key == &"linked_audio_actor" and str(value) != "":
		var target := actor_for_id(str(value))
		if target == null or target.type_id != &"audio" or not can_set_parent(target.id, actor.id): return
	var before := media_snapshot()
	var previous := actor_for_id(str(actor.values.get(&"linked_audio_actor", "")))
	if key == &"video":
		if previous != null:
			for child in actors:
				if child.parent_id == previous.id: child.parent_id = previous.parent_id
			var index := actors.find(previous)
			selected_ids.erase(clips[index].id)
			actors.remove_at(index)
			clips.remove_at(index)
		actor.values[&"video"] = value if value != null else ""
		var clip := clip_for_actor_id(actor.id)
		clip.source_offset = 0.0
		clip.duration = float(source.get("duration", MIN_DURATION))
		while not can_place(clip.id, clip.start_time, clip.duration, clip.layer): clip.layer += 1
		configure_video_audio(actor)
	else:
		# Clearing ownership extracts the existing audio instead of deleting it.
		if previous != null and previous.parent_id == actor.id:
			previous.parent_id = actor.parent_id
			var previous_clip := clip_for_actor_id(previous.id)
			while not can_place(previous_clip.id, previous_clip.start_time, previous_clip.duration, previous_clip.layer): previous_clip.layer += 1
		actor.values[key] = str(value)
		var replacement := actor_for_id(str(value))
		if replacement != null:
			replacement.parent_id = actor.id
			replacement.section_id = actor.section_id
			var replacement_clip := clip_for_actor_id(replacement.id)
			while not can_place(replacement_clip.id, replacement_clip.start_time, replacement_clip.duration, replacement_clip.layer): replacement_clip.layer += 1
	commit_media(before, "Change Video" if key == &"video" else "Change Linked Audio Actor")


func object_animation_path(actor: ActorData, object: ActorObjectData, key: StringName) -> PackedStringArray:
	var path := ActorAnimation.path_to_object(actor, object)
	if not path.is_empty():
		path.append(str(key))
	return path


func preview_animation_value(actor: ActorData, path: PackedStringArray, value: Variant) -> void:
	actor.animation_previews.erase(" / ".join(path))
	var track := actor.animation_track(path)
	var clip := clip_for_actor_id(actor.id)
	if track != null and clip != null and ActorAnimation.sampled_value(actor, path, clip.local_time(playhead_time)) == value:
		actor.animation_previews.erase(" / ".join(path))
	else:
		actor.animation_previews[" / ".join(path)] = {"path": path.duplicate(), "value": ActorData.copy_value(value)}
	actor.emit_changed()
	changed.emit()


func commit_animation_value(actor: ActorData, path: PackedStringArray, value: Variant) -> void:
	actor.animation_previews.erase(" / ".join(path))
	var clip := clip_for_actor_id(actor.id)
	var track := actor.animation_track(path)
	if track != null and clip != null:
		if ActorAnimation.sampled_value(actor, path, clip.local_time(playhead_time)) == value:
			changed.emit()
			return
		add_keyframe(actor, path, track.label, value, track.keys[0].interpolation == ActorKeyframe.Interpolation.STEP, true)


func _animated_object_edit(actor: ActorData, object: ActorObjectData, key: StringName,
		value: Variant, preview: bool) -> bool:
	var path := object_animation_path(actor, object, key)
	if path.is_empty():
		return false
	if actor.animation_track(path) != null:
		if preview: preview_animation_value(actor, path, value)
		else: commit_animation_value(actor, path, value)
		return true
	return false


func edit_shader_uniform(actor: ActorData, object: ActorObjectData, definition: ActorObjectDefinition,
		uniform_name: StringName, value: Variant, mode: String = "edit", original: Variant = null) -> void:
	var path := object_animation_path(actor, object, &"uniforms")
	path.append(str(uniform_name))
	if actor.animation_track(path) != null:
		if mode == "preview": preview_animation_value(actor, path, value)
		else: commit_animation_value(actor, path, value)
		return
	var property := definition.find_property(&"uniforms")
	var uniforms: Dictionary = definition.value_for(object, property).duplicate(true)
	uniforms[uniform_name] = ActorData.copy_value(value)
	if mode == "preview":
		preview_object_property(actor, object, definition, &"uniforms", uniforms)
	elif mode == "commit":
		var original_values: Dictionary = original.duplicate(true) if original is Dictionary else {}
		var parent_path := object_animation_path(actor, object, &"uniforms")
		var stored: Dictionary = definition.value_for(object, property)
		for track in actor.animation_tracks:
			if track.path.size() == parent_path.size() + 1 and track.path.slice(0, parent_path.size()) == parent_path:
				var animated_name := StringName(track.path[-1])
				if stored.has(animated_name): original_values[animated_name] = stored[animated_name]
				else: original_values.erase(animated_name)
		commit_object_property_preview(actor, object, definition, &"uniforms", original_values, uniforms)
	else:
		edit_object_property(actor, object, definition, &"uniforms", uniforms)


func animation_snapshot(actor: ActorData) -> Array[ActorAnimationTrack]:
	var result: Array[ActorAnimationTrack] = []
	for track in actor.animation_tracks:
		result.append(track.copy_track())
	return result


func add_keyframe(actor: ActorData, path: PackedStringArray, label: String, value: Variant,
		stepped: bool = false, changed_only: bool = false) -> void:
	var clip := clip_for_actor_id(actor.id) if actor != null else null
	if clip == null or path.is_empty() or not typeof(value) in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL,
		TYPE_STRING, TYPE_STRING_NAME, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4,
		TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I, TYPE_COLOR]:
		return
	var before := animation_snapshot(actor)
	var after := animation_snapshot(actor)
	if actor.animation_track(path) != null and actor.animation_track(path).component >= 0:
		for part in after:
			if part.path != path: continue
			if changed_only and part.sample(clip.local_time(playhead_time)) == value[part.component]: continue
			var part_key := part.key_at(clip.local_time(playhead_time))
			if part_key == null:
				part_key = ActorKeyframe.new()
				part_key.id = ActorData.new_id()
				part_key.time = clip.local_time(playhead_time)
				part.keys.append(part_key)
			part_key.value = value[part.component]
			part.sort_keys()
		commit_animation_edit(actor, before, after, "Set Component Keyframes")
		return
	var track: ActorAnimationTrack = null
	for candidate in after:
		if candidate.path == path:
			track = candidate
			break
	if track == null:
		track = ActorAnimationTrack.new()
		track.path = path.duplicate()
		track.label = label
		after.append(track)
	var time := clip.local_time(playhead_time)
	var key := track.key_at(time)
	if key == null:
		key = ActorKeyframe.new()
		key.id = ActorData.new_id()
		key.time = time
		track.keys.append(key)
	key.value = ActorData.copy_value(value)
	if stepped or typeof(value) in [TYPE_BOOL, TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I]:
		key.interpolation = ActorKeyframe.Interpolation.STEP
	track.sort_keys()
	after.sort_custom(func(a: ActorAnimationTrack, b: ActorAnimationTrack):
		if a.path == b.path: return a.component < b.component
		return a.label.naturalnocasecmp_to(b.label) < 0)
	commit_animation_edit(actor, before, after, "Set Keyframe")


func keyframe_for_id(actor: ActorData, key_id: String) -> ActorKeyframe:
	for track in actor.animation_tracks:
		for key in track.keys:
			if key.id == key_id:
				return key
	return null

func track_for_key(actor: ActorData, key_id: String) -> ActorAnimationTrack:
	for track in actor.animation_tracks:
		for key in track.keys:
			if key.id == key_id: return track
	return null

func separate_track(actor: ActorData, path: PackedStringArray) -> void:
	var source := actor.animation_track(path)
	if source == null or source.component >= 0 or source.keys.is_empty(): return
	var value: Variant = source.keys[0].value
	var count := component_count(value)
	if count == 0: return
	var before := animation_snapshot(actor)
	var after := animation_snapshot(actor)
	for index in range(after.size() - 1, -1, -1):
		if after[index].path == path: after.remove_at(index)
	var track_index := actor.animation_tracks.find(source)
	for axis in count:
		var part := source.copy_track()
		part.component = axis
		part.component_base = ActorData.copy_value(value)
		part.label += " / " + (["R", "G", "B", "A"][axis] if value is Color else ["X", "Y", "Z", "W"][axis])
		for key in part.keys:
			key.id = ActorData.new_id()
			key.value = value_component(key.value, axis)
		after.insert(track_index + axis, part)
	commit_animation_edit(actor, before, after, "Separate Keyframe Components")

func unseparate_track(actor: ActorData, path: PackedStringArray) -> void:
	var source := actor.animation_track(path)
	if source == null or source.component < 0: return
	var before := animation_snapshot(actor)
	var after: Array[ActorAnimationTrack] = []
	var times: Array[float] = []
	for track in before:
		if track.path != path:
			after.append(track)
		else:
			for key in track.keys:
				if not times.has(key.time): times.append(key.time)
	times.sort()
	var joined := ActorAnimationTrack.new()
	joined.path = path.duplicate()
	joined.label = source.label.substr(0, maxi(0, source.label.length() - 4))
	for time in times:
		var key := ActorKeyframe.new()
		key.id = ActorData.new_id()
		key.time = time
		key.value = ActorAnimation.sampled_value(actor, path, time)
		var original := source.key_at(time)
		if original != null:
			key.value_curve = original.value_curve.duplicate() as Curve if original.value_curve != null else null
			key.curve_template = original.curve_template
			key.curve_adjustment = original.curve_adjustment
			key.interpolation = original.interpolation
			key.attenuation = original.attenuation
		joined.keys.append(key)
	after.append(joined)
	commit_animation_edit(actor, before, after, "Unseparate Keyframe Components")

static func component_count(value: Variant) -> int:
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR2I: return 2
		TYPE_VECTOR3, TYPE_VECTOR3I: return 3
		TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_COLOR: return 4
	return 0

static func value_component(value: Variant, axis: int) -> Variant:
	return value[axis]


func preview_keyframe(actor: ActorData, key_id: String, changes: Dictionary) -> bool:
	var key := keyframe_for_id(actor, key_id)
	if key == null:
		return false
	if changes.has("value") and typeof(changes.value) != typeof(key.value):
		return false
	if changes.has("attenuation") and not is_finite(float(changes.attenuation)):
		return false
	if changes.has("time"):
		var time := float(changes.time)
		if not is_finite(time):
			return false
		for track in actor.animation_tracks:
			if track.keys.has(key):
				var occupied := track.key_at(time)
				if occupied != null and occupied != key:
					return false
		key.time = time
	if changes.has("value"):
		if typeof(changes.value) != typeof(key.value):
			return false
		key.value = ActorData.copy_value(changes.value)
	if changes.has("value_curve"):
		key.value_curve = changes.value_curve.duplicate() as Curve if changes.value_curve != null else null
		key.interpolation = ActorKeyframe.Interpolation.LINEAR
		key.curve_template = changes.get("curve_template", "")
	if changes.has("curve_adjustment"): key.curve_adjustment = float(changes.curve_adjustment)
	if changes.has("interpolation"):
		key.interpolation = clampi(int(changes.interpolation), 0, 2) as ActorKeyframe.Interpolation
	if changes.has("attenuation"):
		if not is_finite(float(changes.attenuation)):
			return false
		key.attenuation = float(changes.attenuation)
	for track in actor.animation_tracks:
		track.sort_keys()
	actor.emit_changed()
	changed.emit()
	return true


func edit_keyframe(actor: ActorData, key_id: String, changes: Dictionary) -> void:
	var before := animation_snapshot(actor)
	if preview_keyframe(actor, key_id, changes):
		commit_animation_edit(actor, before, animation_snapshot(actor), "Edit Keyframe")


func delete_keyframes(actor: ActorData, ids: Array[String]) -> void:
	var before := animation_snapshot(actor)
	var after := animation_snapshot(actor)
	for track in after:
		for index in range(track.keys.size() - 1, -1, -1):
			if ids.has(track.keys[index].id):
				track.keys.remove_at(index)
	for index in range(after.size() - 1, -1, -1):
		if after[index].keys.is_empty():
			after.remove_at(index)
	commit_animation_edit(actor, before, after, "Delete Keyframes")


func commit_animation_edit(actor: ActorData, before: Array[ActorAnimationTrack],
		after: Array[ActorAnimationTrack], action: String) -> void:
	if not actors.has(actor):
		return
	if property_batch_active:
		restore_animation(actor, after)
		return
	history.create_action(action)
	history.add_do_method(restore_animation.bind(actor, after))
	history.add_undo_method(restore_animation.bind(actor, before))
	history.commit_action()


func restore_animation(actor: ActorData, tracks: Array[ActorAnimationTrack]) -> void:
	actor.animation_tracks.clear()
	for track in tracks:
		actor.animation_tracks.append(track.copy_track())
	actor.emit_changed()
	changed.emit()
var _section_navigation: Dictionary = {}


func navigation_state() -> Dictionary:
	return _section_navigation.duplicate(true)


func restore_navigation_state(value: Dictionary) -> void:
	_section_navigation = value.duplicate(true)


func validate_focus() -> void:
	var actor := actor_for_id(focused_actor_id)
	if actor == null or actor.section_id != selected_section_id:
		focused_actor_id = ""


func focus_actor(actor_id: String) -> void:
	var actor := actor_for_id(actor_id)
	if actor == null or actor.section_id != selected_section_id:
		return
	if focused_actor_id == actor_id:
		focus_parent()
		return
	focused_actor_id = actor.id
	_set_single_selection(clip_for_actor_id(actor.id).id)
	selected_layer = selected_clip().layer
	changed.emit()


func leave_actor_focus() -> void:
	focused_actor_id = ""
	selected_ids.clear()
	selected_id = ""
	changed.emit()


func focus_parent() -> void:
	validate_focus()
	var actor := actor_for_id(focused_actor_id)
	if actor == null:
		return
	if actor.parent_id.is_empty():
		leave_actor_focus()
	else:
		focus_actor(actor.parent_id)


func focus_path() -> Array[ActorData]:
	validate_focus()
	var result: Array[ActorData] = []
	var actor := actor_for_id(focused_actor_id)
	var visited: Dictionary = {}
	while actor != null and not visited.has(actor.id):
		visited[actor.id] = true
		result.push_front(actor)
		actor = actor_for_id(actor.parent_id)
	return result


func section_for_id(id: String) -> ActorSection:
	for section in sections:
		if section.id == id:
			return section
	return null


func select_section(id: String) -> void:
	if section_for_id(id) == null:
		return
	if id == selected_section_id:
		changed.emit()
		return
	_section_navigation[selected_section_id] = {"focus": focused_actor_id,
		"selection": selected_ids.duplicate(), "layer": selected_layer}
	selected_section_id = id
	var state: Dictionary = _section_navigation.get(id, {})
	focused_actor_id = str(state.get("focus", ""))
	validate_focus()
	selected_ids.clear()
	for clip_id: String in state.get("selection", []):
		var index := _index_of(clip_id)
		if index >= 0 and actors[index].section_id == id:
			selected_ids.append(clip_id)
	selected_id = selected_ids.back() if not selected_ids.is_empty() else ""
	selected_layer = int(state.get("layer", 0))
	changed.emit()


func create_section() -> ActorSection:
	var section := ActorSection.new()
	section.id = ActorData.new_id()
	section.display_name = "Section %d" % (sections.size() + 1)
	history.create_action("Create Section")
	history.add_do_method(_insert_section.bind(section))
	history.add_undo_method(_remove_section.bind(section, selected_section_id))
	history.commit_action()
	return section


func _insert_section(section: ActorSection) -> void:
	sections.append(section)
	select_section(section.id)


func _remove_section(section: ActorSection, previous: String) -> void:
	sections.erase(section)
	select_section(previous)


func rename_section(id: String, name: String) -> void:
	var section := section_for_id(id)
	name = name.strip_edges()
	if section == null or name.is_empty() or name == section.display_name:
		return
	history.create_action("Rename Section")
	history.add_do_method(_set_section_name.bind(section, name))
	history.add_undo_method(_set_section_name.bind(section, section.display_name))
	history.commit_action()


func _set_section_name(section: ActorSection, name: String) -> void:
	section.display_name = name
	section.emit_changed()
	changed.emit()


func clip_is_visible(index: int) -> bool:
	if index < 0 or index >= actors.size() or actors[index].section_id != selected_section_id:
		return false
	validate_focus()
	if actors[index].id == focused_actor_id:
		return true
	var ancestor := actor_for_id(actors[index].parent_id)
	var visited: Dictionary = {}
	while ancestor != null and not visited.has(ancestor.id):
		# Override only the focused actor's toggle. Nested branches keep theirs.
		if ancestor.id == focused_actor_id:
			return true
		if not ancestor.show_timeline_children:
			return false
		visited[ancestor.id] = true
		ancestor = actor_for_id(ancestor.parent_id)
	return focused_actor_id.is_empty()


## Hidden children still occupy their time intervals. Visibility is only UI state.
func section_clips() -> Array[ActorClip]:
	var result: Array[ActorClip] = []
	for index in clips.size():
		if actors[index].section_id == selected_section_id:
			result.append(clips[index])
	return result


func _visibility_domain(actor: ActorData) -> String:
	var ancestor := actor_for_id(actor.parent_id)
	var visited: Dictionary = {}
	while ancestor != null and not visited.has(ancestor.id):
		if not ancestor.show_timeline_children:
			return ancestor.id
		visited[ancestor.id] = true
		ancestor = actor_for_id(ancestor.parent_id)
	return "section:" + actor.section_id


func _actor_in_focus(actor: ActorData) -> bool:
	if focused_actor_id.is_empty():
		return false
	var visited: Dictionary = {}
	while actor != null and not visited.has(actor.id):
		if actor.id == focused_actor_id:
			return true
		visited[actor.id] = true
		actor = actor_for_id(actor.parent_id)
	return false


func _visible_in_focused_branch(actor: ActorData) -> bool:
	if focused_actor_id.is_empty():
		return false
	if actor.id == focused_actor_id:
		return true
	var ancestor := actor_for_id(actor.parent_id)
	var visited: Dictionary = {}
	while ancestor != null and not visited.has(ancestor.id):
		if ancestor.id == focused_actor_id:
			return true
		if not ancestor.show_timeline_children:
			return false
		visited[ancestor.id] = true
		ancestor = actor_for_id(ancestor.parent_id)
	return false


func _is_focus_ancestor(actor: ActorData) -> bool:
	var focus := actor_for_id(focused_actor_id)
	var ancestor := actor_for_id(focus.parent_id) if focus != null else null
	var visited: Dictionary = {}
	while ancestor != null and not visited.has(ancestor.id):
		if ancestor.id == actor.id:
			return true
		visited[ancestor.id] = true
		ancestor = actor_for_id(ancestor.parent_id)
	return false


func _is_actor_ancestor(ancestor_id: String, actor: ActorData) -> bool:
	var parent := actor_for_id(actor.parent_id)
	var visited: Dictionary = {}
	while parent != null and not visited.has(parent.id):
		if parent.id == ancestor_id:
			return true
		visited[parent.id] = true
		parent = actor_for_id(parent.parent_id)
	return false


## Include the first hidden node, but never traverse beyond it. Endpoints are
## included: hiding an actor's children must still reserve their immediate clips.
func _unbroken_relative_path(ancestor_id: String, actor: ActorData) -> bool:
	var parent := actor_for_id(actor.parent_id)
	var visited: Dictionary = {}
	while parent != null and not visited.has(parent.id):
		if parent.id == ancestor_id:
			return true
		if not parent.show_timeline_children:
			return false
		visited[parent.id] = true
		parent = actor_for_id(parent.parent_id)
	return false


## Actors separated by a hidden-children boundary occupy independent spaces.
## Focusing combines only the visible branch, not unrelated hidden branches.
func actors_obstruct(a: ActorData, b: ActorData) -> bool:
	if a == null or b == null or a.section_id != b.section_id:
		return false
	# Relative obstructions stop at hidden subtree boundaries in both directions.
	if _is_actor_ancestor(a.id, b):
		return _unbroken_relative_path(a.id, b)
	if _is_actor_ancestor(b.id, a):
		return _unbroken_relative_path(b.id, a)
	if a.section_id == selected_section_id:
		# The focused actor itself still shares its overview space with siblings.
		# Only its hidden descendants occupy a separate visibility domain.
		if _visible_in_focused_branch(a) and _visible_in_focused_branch(b):
			return true
	return _visibility_domain(a) == _visibility_domain(b)


func hidden_clip_obstructs_view(index: int) -> bool:
	if index < 0 or index >= clips.size() or clip_is_visible(index):
		return false
	var displayed_count := 0
	var blocks_every_displayed := true
	for other_index in clips.size():
		if not clip_is_visible(other_index):
			continue
		displayed_count += 1
		var blocks := actors_obstruct(actors[index], actors[other_index])
		if blocks and is_selected(clips[other_index].id):
			return true
		blocks_every_displayed = blocks_every_displayed and blocks
	# Without selection, show only obstruction context shared by the entire view.
	# Never expose unrelated boxes just because they obstruct one unselected actor.
	return selected_ids.is_empty() and displayed_count > 0 and blocks_every_displayed


func set_timeline_children_visible(actor_id: String, visible: bool) -> void:
	var actor := actor_for_id(actor_id)
	if actor == null or actor.show_timeline_children == visible:
		return
	var original_visible := actor.show_timeline_children
	var before: Dictionary = {}
	var after: Dictionary = {}
	if visible:
		# Plan against the revealed visibility domains, without publishing a preview.
		# Keep existing actors and all timing intact; newly revealed clips move to
		# the nearest free layer at or below their current layer.
		actor.show_timeline_children = true
		var reserved: Array[Dictionary] = []
		var descendants: Array[ActorClip] = []
		for index in clips.size():
			if actors[index].section_id != actor.section_id:
				continue
			if _is_actor_ancestor(actor.id, actors[index]):
				descendants.append(clips[index])
			else:
				reserved.append({"actor": actors[index], "clip": clips[index], "layer": clips[index].layer})
		for clip in descendants:
			var descendant := actor_for_id(clip.actor_id)
			var layer := clip.layer
			while not _revealed_layer_fits(descendant, clip, layer, reserved):
				layer += 1
			reserved.append({"actor": descendant, "clip": clip, "layer": layer})
			if layer != clip.layer:
				before[clip.id] = clip.layer
				after[clip.id] = layer
		actor.show_timeline_children = original_visible
	history.create_action("Show Timeline Children" if visible else "Hide Timeline Children")
	history.add_do_method(_set_timeline_children_visible.bind(actor, visible, after))
	history.add_undo_method(_set_timeline_children_visible.bind(actor, original_visible, before))
	history.commit_action()


func _revealed_layer_fits(actor: ActorData, clip: ActorClip, layer: int, reserved: Array[Dictionary]) -> bool:
	for entry in reserved:
		var other := entry.clip as ActorClip
		if int(entry.layer) == layer and actors_obstruct(actor, entry.actor) \
				and clip.start_time < other.start_time + other.duration - 0.000001 \
				and clip.start_time + clip.duration > other.start_time + 0.000001:
			return false
	return true


func _set_timeline_children_visible(actor: ActorData, visible: bool, layers: Dictionary = {}) -> void:
	actor.show_timeline_children = visible
	for id: String in layers:
		var index := _index_of(id)
		if index >= 0:
			clips[index].layer = int(layers[id])
			clips[index].emit_changed()
	if selected_clip() != null:
		selected_layer = selected_clip().layer
	actor.emit_changed()
	changed.emit()


## Deletes the section and its contents together. Undo restores the exact branch.
func delete_section(id: String) -> void:
	var section := section_for_id(id)
	if section == null:
		return
	var entries: Array[Dictionary] = []
	for index in actors.size():
		if actors[index].section_id == id:
			entries.append({"actor": actors[index], "clip": clips[index], "index": index})
	var replacement: ActorSection = null
	if sections.size() == 1:
		replacement = ActorSection.new()
		replacement.id = ActorData.new_id()
	var selection := selected_ids.duplicate()
	history.create_action("Delete Section")
	history.add_do_method(_delete_section_state.bind(section, entries, replacement))
	history.add_undo_method(_restore_section_state.bind(section, sections.find(section), entries,
		replacement, selected_section_id, selection))
	history.commit_action()


func _delete_section_state(section: ActorSection, entries: Array[Dictionary], replacement: ActorSection) -> void:
	for entry in entries:
		var index := _index_of((entry.clip as ActorClip).id)
		if index >= 0:
			actors.remove_at(index)
			clips.remove_at(index)
	sections.erase(section)
	if replacement != null:
		sections.append(replacement)
	if selected_section_id == section.id:
		select_section(sections[0].id)
	else:
		changed.emit()


func _restore_section_state(section: ActorSection, index: int, entries: Array[Dictionary],
		replacement: ActorSection, previous_section: String, selection: Array[String]) -> void:
	if replacement != null:
		sections.erase(replacement)
	sections.insert(index, section)
	for entry in entries:
		actors.insert(int(entry.index), entry.actor)
		clips.insert(int(entry.index), entry.clip)
	selected_section_id = previous_section
	selected_ids.assign(selection)
	selected_id = selected_ids.back() if not selected_ids.is_empty() else ""
	if selected_clip() != null:
		selected_layer = selected_clip().layer
	changed.emit()


func visible_clips() -> Array[ActorClip]:
	var result: Array[ActorClip] = []
	for index in clips.size():
		if clip_is_visible(index):
			result.append(clips[index])
	return result


func move_to_section(actor_ids: Array[String], section_id: String) -> void:
	if section_for_id(section_id) == null:
		return
	var states: Dictionary = {}
	var roots := actor_ids.duplicate()
	for id in actor_ids:
		var ancestor := actor_for_id(actor_for_id(id).parent_id) if actor_for_id(id) != null else null
		while ancestor != null:
			if actor_ids.has(ancestor.id):
				roots.erase(id)
				break
			ancestor = actor_for_id(ancestor.parent_id)
	for actor in actors:
		var current := actor
		while current != null:
			if actor_ids.has(current.id):
				states[actor.id] = {"old_section": actor.section_id, "old_parent": actor.parent_id, "old_layer": clip_for_actor_id(actor.id).layer,
					"old_values": _transform_values(actor), "new_parent": "" if roots.has(actor.id) else actor.parent_id,
					"new_values": _values_for_preserved_world(actor, "") if roots.has(actor.id) else _transform_values(actor)}
				break
			current = actor_for_id(current.parent_id)
	if states.is_empty():
		return
	history.create_action("Move Actors to Section")
	history.add_do_method(_apply_section_move.bind(states, section_id, true))
	history.add_undo_method(_apply_section_move.bind(states, selected_section_id, false))
	history.commit_action()


func _apply_section_move(states: Dictionary, section_id: String, forward: bool) -> void:
	for id: String in states:
		var actor := actor_for_id(id)
		if actor == null:
			continue
		var state: Dictionary = states[id]
		actor.section_id = section_id if forward else str(state.old_section)
		var clip := clip_for_actor_id(id)
		clip.layer = int(state.old_layer)
		if forward:
			while not can_place(clip.id, clip.start_time, clip.duration, clip.layer):
				clip.layer += 1
		_apply_parent_state_silent(actor, state.new_parent if forward else state.old_parent,
			state.new_values if forward else state.old_values)
	select_section(section_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(history):
		history.free()


func create_actor(definition: ActorDefinition, time: float, initial_values: Dictionary = {}) -> ActorClip:
	# Model files are editable node hierarchies, not one opaque mesh actor.
	# This shared entry point covers timeline drops and Modeling → To Scene.
	var model_source: Variant=initial_values.get(&"mesh_path","")
	if definition.type_id==&"basic_mesh" and (model_source is Resource or (model_source is String and not model_source.is_empty())):
		var path: String=model_source.resource_path if model_source is Resource else str(model_source)
		var document := KiwiModelImport.load_document(model_source)
		if not document.components.is_empty() and document.validate().is_empty():
			return instantiate_model(document,path,time)
	var actor := definition.create_actor(initial_values)
	actor.section_id = selected_section_id
	validate_focus()
	actor.parent_id = focused_actor_id
	var clip := ActorClip.create(actor, maxf(time, 0.0))
	if actor.type_id == &"transform_image_2d":
		var asset := ActorTransformationStates.load_asset(actor)
		if asset.document != null: clip.duration = maxf(MIN_DURATION, asset.document.duration)
	if actor.type_id in [&"video", &"video_2d"]:
		var source := ActorVideo.info(str(actor.values.get(&"video", "")))
		if source.is_empty(): return null
		clip.duration = source.duration
		actor.show_timeline_children = false
		actor.link_timeline_children = true
	if actor.type_id == &"audio":
		clip.playback_speed = clampf(float(actor.values.get(&"speed", 1.0)), 0.25, 4.0)
		clip.duration = ActorAudio.length(actor) / clip.playback_speed
		if clip.duration <= 0.0: return null
	clip.layer = selected_layer
	# If the cursor is occupied, use the next available gap on the chosen layer.
	var neighbors: Array[ActorClip] = []
	for other in section_clips():
		if other.layer == clip.layer and actors_obstruct(actor, actor_for_id(other.actor_id)):
			neighbors.append(other)
	neighbors.sort_custom(func(a: ActorClip, b: ActorClip): return a.start_time < b.start_time)
	for other in neighbors:
		if clip.start_time < other.start_time + other.duration and clip.start_time + clip.duration > other.start_time:
			clip.start_time = other.start_time + other.duration
	var previous_selection := selected_id
	if actor.type_id in [&"video", &"video_2d"]:
		var before := media_snapshot()
		actors.append(actor)
		clips.append(clip)
		configure_video_audio(actor)
		select(clip.id)
		commit_media(before, "Create Video")
		return clip
	history.create_action("Create " + definition.display_name)
	history.add_do_method(_insert.bind(actor, clip, clips.size(), clip.id))
	history.add_undo_method(_remove.bind(clip.id, previous_selection))
	history.commit_action()
	changed.emit()
	return clip


func instantiate_model(document: KiwiModelDocument, source_path: String, start: float) -> ActorClip:
	var registry := ActorRegistry.new(); BasicActors.register_all(registry)
	var scene := document.actor_scene(registry,source_path)
	if scene.actors.is_empty(): return null
	validate_focus()
	return instantiate_scene(scene,registry.get_definition(&"point_3d"),start,selected_layer,source_path.get_file().get_basename() if not source_path.is_empty() else "Model","Instantiate Model")


## Flatten an editable scene into this scene while preserving its actor ancestry,
## animation resources and clip offsets. One undo action owns the entire import.
func instantiate_scene(scene: ActorSceneData, point_definition: ActorDefinition,
		start: float, layer: int, name: String = "Scene", action_label: String = "Instantiate Scene") -> ActorClip:
	if scene == null or point_definition == null or point_definition.type_id != &"point_3d":
		return null
	var first := INF
	var last := -INF
	var lowest_layer := 2147483647
	for clip in scene.clips:
		first = minf(first, clip.start_time)
		last = maxf(last, clip.start_time + clip.duration)
		lowest_layer = mini(lowest_layer, clip.layer)
	if not is_finite(first): first = 0.0
	var length := maxf(last - first, MIN_DURATION) if is_finite(last) else 5.0
	var root := point_definition.create_actor()
	root.display_name = name if not name.is_empty() else "Scene"
	root.section_id = selected_section_id
	root.parent_id = focused_actor_id
	root.show_timeline_children = false
	root.link_timeline_children = true
	var root_clip := ActorClip.create(root, maxf(start, 0.0), length)
	root_clip.layer = maxi(0, layer)
	while not can_place("", root_clip.start_time, root_clip.duration, root_clip.layer):
		var next := root_clip.start_time + MIN_DURATION
		for existing in section_clips():
			if existing.layer == root_clip.layer and existing.start_time < root_clip.start_time + root_clip.duration and existing.start_time + existing.duration > root_clip.start_time:
				next = maxf(next, existing.start_time + existing.duration)
		root_clip.start_time = next
	var entries: Array[Dictionary] = [{"actor": root, "clip": root_clip}]
	var id_map: Dictionary = {}
	for source_actor in scene.actors:
		id_map[source_actor.id] = ActorData.new_id()
	var section_parents: Dictionary = {}
	if scene.sections.size() > 1:
		for source_section in scene.sections:
			var section_actor := point_definition.create_actor()
			section_actor.display_name = source_section.display_name
			section_actor.section_id = selected_section_id
			section_actor.parent_id = root.id
			section_actor.show_timeline_children = true
			section_actor.link_timeline_children = true
			var section_clip := ActorClip.create(section_actor, root_clip.start_time, root_clip.duration)
			section_clip.layer = root_clip.layer + 1 + section_parents.size()
			section_parents[source_section.id] = section_actor.id
			entries.append({"actor": section_actor, "clip": section_clip})
	for index in mini(scene.actors.size(), scene.clips.size()):
		var source_actor := scene.actors[index]
		var source_clip := scene.clips[index]
		var actor := source_actor.copy_actor()
		actor.id = id_map[source_actor.id]
		for track in actor.animation_tracks:
			for key in track.keys:
				key.id = ActorData.new_id()
		actor.section_id = selected_section_id
		actor.parent_id = str(id_map.get(source_actor.parent_id,
			section_parents.get(source_actor.section_id, root.id)))
		for key in [&"linked_audio_actor", &"remote_actor", &"model_skeleton_actor", &"model_component_instance_id"]:
			if actor.values.has(key):
				actor.values[key] = str(id_map.get(str(actor.values[key]), ""))
		if actor.values.has(&"model_component_bind_transform") and str(actor.values.get(&"model_component_instance_id","")).is_empty(): actor.values[&"model_component_instance_id"]=root.id
		if actor.values.get(&"physics") is Dictionary: actor.values[&"physics"] = KiwiPhysicsSettings.remap(actor.values[&"physics"],id_map)
		if actor.values.has(&"structure_connections"): KiwiStructure.remap_actor(actor,id_map)
		preload("res://scripts/actors/fog/fog_motion_definition.gd").remap_actor(actor,id_map,true)
		if actor.values.has(&"fluid_mesh_actor"): actor.values[&"fluid_mesh_actor"]=id_map.get(str(actor.values[&"fluid_mesh_actor"]),actor.values[&"fluid_mesh_actor"])
		if actor.values.has(&"powder_mesh_actor"): actor.values[&"powder_mesh_actor"]=id_map.get(str(actor.values[&"powder_mesh_actor"]),actor.values[&"powder_mesh_actor"])
		var clip := source_clip.duplicate(true) as ActorClip
		clip.id = ActorData.new_id()
		clip.actor_id = actor.id
		clip.start_time = root_clip.start_time + source_clip.start_time - first
		clip.layer = root_clip.layer + scene.sections.size() + 1 + source_clip.layer - lowest_layer
		if actor.values.get(&"physics",{}).get("bake",{}).get("portable",false):
			actor.values.physics.bake.portable_root=root.id; actor.values.physics.bake.owner=actor.id; actor.values.physics.bake.portable_authored=KiwiBakeEditing.portable_signature(actor)
		entries.append({"actor": actor, "clip": clip})
	var ids: Array[String] = []
	for entry in entries:
		ids.append(entry.clip.id)
	var previous_selection := selected_ids.duplicate()
	var root_selection: Array[String] = [root_clip.id]
	history.create_action(action_label)
	history.add_do_method(_insert_copies.bind(entries, root_selection))
	history.add_undo_method(_remove_copies.bind(ids, previous_selection))
	history.commit_action()
	return root_clip


func delete_selected() -> void:
	var primary := selected_actor()
	if primary != null and primary.type_id in [&"video", &"video_2d"] and actor_for_id(str(primary.values.get(&"linked_audio_actor", ""))) != null:
		_delete_selected_group()
		return
	if selected_ids.size() > 1:
		_delete_selected_group()
		return
	var index := _index_of(selected_id)
	if index < 0:
		return
	var clip := clips[index]
	var actor := actors[index]
	# Promote direct children to the deleted actor's parent. This preserves a
	# deep hierarchy instead of unexpectedly throwing a whole branch at the root.
	# Each promoted child receives a new local transform that keeps its world pose.
	var child_states: Dictionary = {}
	for candidate in actors:
		if candidate.parent_id == actor.id:
			child_states[candidate.id] = {
				"old_parent": candidate.parent_id,
				"old_values": _transform_values(candidate),
				"new_parent": actor.parent_id,
				"new_values": _values_for_preserved_world(candidate, actor.parent_id)
			}
	history.create_action("Delete " + actor.display_name)
	history.add_do_method(_remove_with_child_states.bind(clip.id, "", child_states, true))
	history.add_undo_method(_insert_with_child_states.bind(actor, clip, index, clip.id, child_states))
	history.commit_action()
	changed.emit()


func _delete_selected_group() -> void:
	var ids := selected_ids.duplicate()
	var original_selection := selected_ids.duplicate()
	for id in selected_ids:
		var index := _index_of(id)
		if index < 0 or actors[index].type_id not in [&"video", &"video_2d"]: continue
		var owned := clip_for_actor_id(str(actors[index].values.get(&"linked_audio_actor", "")))
		if owned != null and not ids.has(owned.id): ids.append(owned.id)
	var removed: Array[Dictionary] = []
	var removed_actor_ids: Dictionary = {}
	for id in ids:
		var index := _index_of(id)
		if index >= 0:
			removed.append({"actor": actors[index], "clip": clips[index], "index": index})
			removed_actor_ids[actors[index].id] = true
	if removed.is_empty():
		return
	var child_states: Dictionary = {}
	for actor in actors:
		if removed_actor_ids.has(actor.id) or not removed_actor_ids.has(actor.parent_id):
			continue
		var next_parent := actor_for_id(actor.parent_id)
		while next_parent != null and removed_actor_ids.has(next_parent.id):
			next_parent = actor_for_id(next_parent.parent_id)
		var next_parent_id := next_parent.id if next_parent != null else ""
		child_states[actor.id] = {
			"old_parent": actor.parent_id,
			"old_values": _transform_values(actor),
			"new_parent": next_parent_id,
			"new_values": _values_for_preserved_world(actor, next_parent_id)
		}
	history.create_action("Delete Actors")
	history.add_do_method(_remove_many.bind(ids, child_states))
	history.add_undo_method(_insert_many.bind(removed, original_selection, child_states))
	history.commit_action()
	changed.emit()


func move_clip(id: String, time: float, layer: int = -1) -> void:
	var index := _index_of(id)
	if index < 0 or not is_finite(time):
		return
	var clip := clips[index]
	var linked := linked_clip_ids([id])
	if linked.size() > 1:
		var layer_delta := 0 if layer < 0 else layer - clip.layer
		var delta := nearest_free_group_delta(linked, time - clip.start_time, layer_delta)
		var states: Dictionary = {}
		for child_id in linked:
			var child := clips[_index_of(child_id)]
			states[child_id] = {"start": child.start_time + delta, "duration": child.duration, "offset": child.source_offset, "layer": child.layer + layer_delta}
		commit_clip_states(states, "Move Linked Actors", id)
		return
	var target := maxf(time, 0.0)
	var target_layer := clip.layer if layer < 0 else layer
	target = nearest_free_start(id, target, clip.duration, target_layer)
	if not can_place(id, target, clip.duration, target_layer):
		return
	if is_equal_approx(target, clip.start_time) and target_layer == clip.layer:
		return
	history.create_action("Move Actor")
	history.add_do_method(_set_start.bind(clip, target, target_layer))
	history.add_undo_method(_set_start.bind(clip, clip.start_time, clip.layer))
	history.commit_action()
	changed.emit()


func select(id: String, additive: bool = false) -> void:
	selection_requested.emit()
	var selected_index := _index_of(id)
	if selected_index >= 0 and actors[selected_index].section_id != selected_section_id:
		select_section(actors[selected_index].section_id)
	if _index_of(id) < 0:
		selected_ids.clear()
		selected_id = ""
	else:
		if not additive:
			selected_ids.clear()
			selected_ids.append(id)
		else:
			# Reinsert it at the end so an already-selected actor can still become
			# the primary selection without dropping the rest of the selection.
			selected_ids.erase(id)
			selected_ids.append(id)
		selected_id = id
		selected_layer = clips[_index_of(id)].layer
	changed.emit()


func select_all() -> void:
	selection_requested.emit()
	var previous_primary := selected_id
	selected_ids.clear()
	for clip in visible_clips():
		if clip.id != previous_primary:
			selected_ids.append(clip.id)
	if clip_is_visible(_index_of(previous_primary)):
		selected_ids.append(previous_primary)
		selected_id = previous_primary
	elif not selected_ids.is_empty():
		selected_id = selected_ids.back()
		selected_layer = selected_clip().layer
	else:
		selected_id = ""
	changed.emit()


func set_selection(ids: Array[String], primary_id: String = "") -> void:
	selection_requested.emit()
	selected_ids.clear()
	for id in ids:
		if _index_of(id) >= 0 and actors[_index_of(id)].section_id == selected_section_id and not selected_ids.has(id):
			selected_ids.append(id)
	if selected_ids.has(primary_id):
		selected_ids.erase(primary_id)
		selected_ids.append(primary_id)
	selected_id = selected_ids.back() if not selected_ids.is_empty() else ""
	if selected_clip() != null:
		selected_layer = selected_clip().layer
	changed.emit()


func toggle_selection(id: String) -> void:
	if _index_of(id) < 0:
		return
	var next := selected_ids.duplicate()
	if next.has(id):
		next.erase(id)
		set_selection(next, next.back() if not next.is_empty() else "")
	else:
		next.append(id)
		set_selection(next, id)


func is_selected(id: String) -> bool:
	return selected_ids.has(id)


func selected_actors() -> Array[ActorData]:
	var result: Array[ActorData] = []
	for id in selected_ids:
		var index := _index_of(id)
		if index >= 0:
			result.append(actors[index])
	return result

func split_clip(id: String, time: float) -> ActorClip:
	var index := _index_of(id)
	if index < 0: return null
	var left := clips[index]
	var length := time - left.start_time
	if length < MIN_DURATION or left.duration - length < MIN_DURATION: return null
	var actor := actors[index].copy_actor()
	actor.id = ActorData.new_id()
	var right := ActorClip.create(actor, time, left.duration - length)
	right.layer = left.layer
	right.playback_speed = left.playback_speed
	right.source_offset = left.source_offset + length * left.playback_speed
	var old_duration := left.duration
	var old_selection := selected_ids.duplicate()
	var old_focus := focused_actor_id
	var new_focus := actors[index].parent_id if old_focus == left.actor_id else old_focus
	history.create_action("Split Actor")
	history.add_do_method(_apply_split.bind(left, length, actor, right, new_focus))
	history.add_undo_method(_undo_split.bind(left, old_duration, right.id, old_selection, old_focus))
	history.commit_action()
	return right

func _apply_split(left: ActorClip, length: float, actor: ActorData, right: ActorClip, focus: String) -> void:
	left.duration = length
	focused_actor_id = focus
	left.emit_changed()
	_insert_copies([{"actor": actor, "clip": right}], [right.id])

func _undo_split(left: ActorClip, duration: float, right_id: String, selection: Array[String], focus: String) -> void:
	left.duration = duration
	focused_actor_id = focus
	left.emit_changed()
	_remove_copies([right_id], selection)


## Instantiates copied actor/clip snapshots as one undoable operation. With
## target parents, one complete copy is made for each target and its copied root
## actors are parented to that target.
func paste_snapshots(snapshots: Array[Dictionary], time: float, preferred_layer: int,
		target_parent_ids: Array[String] = [], action_name: String = "Paste Actors",
		preserve_external_parents: bool = false) -> Array[ActorClip]:
	if snapshots.is_empty():
		return []
	var targets := target_parent_ids.duplicate()
	if targets.is_empty():
		validate_focus()
		targets.append(focused_actor_id)
	var source_start := INF
	var source_layer := 2147483647
	for snapshot in snapshots:
		source_start = minf(source_start, float(snapshot.start))
		source_layer = mini(source_layer, int(snapshot.layer))
	var entries: Array[Dictionary] = []
	for target_parent_id in targets:
		if not target_parent_id.is_empty() and actor_for_id(target_parent_id) == null:
			continue
		var actor_map: Dictionary = {}
		var group: Array[Dictionary] = []
		for snapshot in snapshots:
			var template := snapshot.actor as ActorData
			if template == null:
				continue
			var actor := template.copy_actor()
			actor.section_id = selected_section_id
			actor.display_name = _copy_name(template.display_name)
			actor_map[str(snapshot.source_id)] = actor
			var clip := ActorClip.new()
			clip.id = ActorData.new_id()
			clip.actor_id = actor.id
			clip.start_time = maxf(0.0, time + float(snapshot.start) - source_start)
			clip.duration = float(snapshot.duration)
			clip.source_offset = float(snapshot.offset)
			clip.playback_speed = float(snapshot.speed)
			clip.layer = int(snapshot.layer) - source_layer
			group.append({"actor": actor, "clip": clip, "snapshot": snapshot})
		for entry in group:
			var actor: ActorData = entry.actor
			var snapshot: Dictionary = entry.snapshot
			var fog_ids:={}
			for source_id in actor_map: fog_ids[source_id]=(actor_map[source_id] as ActorData).id
			preload("res://scripts/actors/fog/fog_motion_definition.gd").remap_actor(actor,fog_ids)
			if actor.values.has(&"structure_connections"):
				var structure_ids:={}
				for source_id in actor_map: structure_ids[source_id]=(actor_map[source_id] as ActorData).id
				KiwiStructure.remap_actor(actor,structure_ids)
			if actor.values.get(&"physics") is Dictionary:
				var physics_ids:={}
				for source_id in actor_map: physics_ids[source_id]=(actor_map[source_id] as ActorData).id
				actor.values[&"physics"]=KiwiPhysicsSettings.remap(actor.values[&"physics"],physics_ids)
				if actor.values.has(&"fluid_mesh_actor"): actor.values[&"fluid_mesh_actor"]=physics_ids.get(str(actor.values[&"fluid_mesh_actor"]),actor.values[&"fluid_mesh_actor"])
				if actor.values.has(&"powder_mesh_actor"): actor.values[&"powder_mesh_actor"]=physics_ids.get(str(actor.values[&"powder_mesh_actor"]),actor.values[&"powder_mesh_actor"])
			if actor.type_id in [&"video", &"video_2d"]:
				var source_audio := str(actor.values.get(&"linked_audio_actor", ""))
				# A copy must never own the original video's audio child.
				actor.values[&"linked_audio_actor"] = (actor_map[source_audio] as ActorData).id if actor_map.has(source_audio) else ""
			var source_parent := str(snapshot.source_parent)
			var source_skeleton := str(actor.values.get(&"model_skeleton_actor",""))
			if actor_map.has(source_skeleton): actor.values[&"model_skeleton_actor"]=(actor_map[source_skeleton] as ActorData).id
			if actor_map.has(source_parent):
				actor.parent_id = (actor_map[source_parent] as ActorData).id
			elif preserve_external_parents and actor_for_id(source_parent) != null:
				actor.parent_id = source_parent
			else:
				actor.parent_id = target_parent_id
		var target_clip := clip_for_actor_id(target_parent_id)
		var group_preferred_layer := target_clip.layer if target_clip != null else preferred_layer
		var base_layer := _find_free_paste_layer(group, entries, maxi(0, group_preferred_layer))
		for entry in group:
			(entry.clip as ActorClip).layer += base_layer
			entries.append(entry)
	if entries.is_empty():
		return []
	var previous_selection := selected_ids.duplicate()
	var pasted_ids: Array[String] = []
	var pasted_clips: Array[ActorClip] = []
	for entry in entries:
		pasted_ids.append((entry.clip as ActorClip).id)
		pasted_clips.append(entry.clip)
	history.create_action(action_name)
	history.add_do_method(_insert_copies.bind(entries, pasted_ids))
	history.add_undo_method(_remove_copies.bind(pasted_ids, previous_selection))
	history.commit_action()
	changed.emit()
	return pasted_clips


func _copy_name(original: String) -> String:
	return original + " Copy"


func _find_free_paste_layer(group: Array[Dictionary], pending: Array[Dictionary], preferred: int) -> int:
	var base := preferred
	while not _paste_group_fits(group, pending, base):
		base += 1
	return base


func _paste_group_fits(group: Array[Dictionary], pending: Array[Dictionary], base: int) -> bool:
	for index in group.size():
		var clip := group[index].clip as ActorClip
		var layer := clip.layer + base
		for other in section_clips():
			if not actors_obstruct(group[index].actor, actor_for_id(other.actor_id)):
				continue
			if other.layer == layer and clip.start_time < other.start_time + other.duration - 0.000001 \
					and clip.start_time + clip.duration > other.start_time + 0.000001:
				return false
		for entry in pending:
			var other := entry.clip as ActorClip
			if other.layer == layer and clip.start_time < other.start_time + other.duration - 0.000001 \
					and clip.start_time + clip.duration > other.start_time + 0.000001:
				return false
		for other_index in range(index + 1, group.size()):
			var other := group[other_index].clip as ActorClip
			if other.layer + base == layer and clip.start_time < other.start_time + other.duration - 0.000001 \
					and clip.start_time + clip.duration > other.start_time + 0.000001:
				return false
	return true


func layer_count() -> int:
	var count := maxi(3, selected_layer + 2)
	for clip in visible_clips():
		count = maxi(count, clip.layer + 2)
	for index in clips.size():
		if hidden_clip_obstructs_view(index):
			count = maxi(count, clips[index].layer + 2)
	return count


func can_place(id: String, start: float, duration: float, layer: int) -> bool:
	var minimum := minimum_duration(clips[_index_of(id)]) if _index_of(id) >= 0 else MIN_DURATION
	if layer < 0 or start < 0 or duration < minimum - 0.000001 or not is_finite(start) or not is_finite(duration):
		return false
	for other in clips:
		var section_id := actors[_index_of(id)].section_id if _index_of(id) >= 0 else selected_section_id
		if actors[_index_of(other.id)].section_id != section_id:
			continue
		var actor := actors[_index_of(id)] if _index_of(id) >= 0 else null
		if actor != null and not actors_obstruct(actor, actor_for_id(other.actor_id)):
			continue
		if other.id != id and other.layer == layer:
			# Touching edges are allowed; half-open intervals do not overlap.
			if start < other.start_time + other.duration - 0.000001 and start + duration > other.start_time + 0.000001:
				return false
	return true


## The nearest valid gap is bounded by zero or another clip's edge.
## Consider all boundaries so snapping never pushes a clip into a second neighbor.
func nearest_free_start(id: String, desired: float, duration: float, layer: int) -> float:
	desired = maxf(0.0, desired)
	if can_place(id, desired, duration, layer):
		return desired
	var candidates: Array[float] = [0.0]
	for other in section_clips():
		if not actors_obstruct(actor_for_id(clips[_index_of(id)].actor_id), actor_for_id(other.actor_id)):
			continue
		if other.id != id and other.layer == layer:
			candidates.append(other.start_time - duration)
			candidates.append(other.start_time + other.duration)
	var best := INF
	var distance := INF
	for candidate in candidates:
		if can_place(id, candidate, duration, layer):
			var delta := absf(candidate - desired)
			if delta < distance or (is_equal_approx(delta, distance) and candidate < best):
				best = candidate
				distance = delta
	return desired if is_inf(best) else best


func can_place_group(states: Dictionary) -> bool:
	for index in clips.size():
		var clip := clips[index]
		var state: Dictionary = states.get(clip.id, {})
		var start: float = state.get("start", clip.start_time)
		var duration: float = state.get("duration", clip.duration)
		var layer: int = state.get("layer", clip.layer)
		if not ActorAudio.valid(actors[index], clip, duration, float(state.get("offset", clip.source_offset))):
			return false
		if start < 0.0 or duration < minimum_duration(clip) - 0.000001 or layer < 0:
			return false
		for other_index in range(index + 1, clips.size()):
			if not states.is_empty() and not states.has(clip.id) and not states.has(clips[other_index].id):
				continue
			if not actors_obstruct(actors[index], actors[other_index]):
				continue
			var other := clips[other_index]
			var other_state: Dictionary = states.get(other.id, {})
			var other_start: float = other_state.get("start", other.start_time)
			var other_duration: float = other_state.get("duration", other.duration)
			var other_layer: int = other_state.get("layer", other.layer)
			if layer == other_layer and start < other_start + other_duration - 0.000001 \
					and start + duration > other_start + 0.000001:
				return false
	return true


func nearest_free_group_delta(ids: Array[String], desired_delta: float, layer_delta: int) -> float:
	var candidates: Array[float] = [desired_delta]
	var minimum_delta := -INF
	for id in ids:
		var index := _index_of(id)
		var clip := clips[index] if index >= 0 else null
		if clip == null:
			continue
		minimum_delta = maxf(minimum_delta, -clip.start_time)
		for other in section_clips():
			if not actors_obstruct(actor_for_id(clip.actor_id), actor_for_id(other.actor_id)):
				continue
			if ids.has(other.id) or other.layer != clip.layer + layer_delta:
				continue
			candidates.append(other.start_time + other.duration - clip.start_time)
			candidates.append(other.start_time - clip.duration - clip.start_time)
	desired_delta = maxf(desired_delta, minimum_delta)
	candidates.append(minimum_delta)
	var best := desired_delta
	var best_distance := INF
	for candidate in candidates:
		candidate = maxf(candidate, minimum_delta)
		var states: Dictionary = {}
		for id in ids:
			var index := _index_of(id)
			var clip := clips[index] if index >= 0 else null
			if clip != null:
				states[id] = {"start": clip.start_time + candidate, "duration": clip.duration,
					"layer": clip.layer + layer_delta, "offset": clip.source_offset}
		if can_place_group(states):
			var distance := absf(candidate - desired_delta)
			if distance < best_distance:
				best = candidate
				best_distance = distance
	return best


func commit_clip_states(states: Dictionary, action_name: String, primary_id: String) -> void:
	if states.is_empty() or not can_place_group(states):
		return
	# Canvas preview dictionaries are cleared as soon as the gesture ends. UndoRedo
	# must own a deep snapshot rather than retaining that mutable UI container.
	var committed: Dictionary = states.duplicate(true)
	var original: Dictionary = {}
	var changed_state := false
	for id: String in committed:
		var index := _index_of(id)
		if index < 0:
			return
		var clip := clips[index]
		original[id] = {"start": clip.start_time, "duration": clip.duration,
			"layer": clip.layer, "offset": clip.source_offset}
		var state: Dictionary = committed[id]
		changed_state = changed_state or not is_equal_approx(clip.start_time, state.start) \
			or not is_equal_approx(clip.duration, state.duration) or clip.layer != state.layer \
			or not is_equal_approx(clip.source_offset, state.offset)
	if not changed_state:
		return
	history.create_action(action_name)
	history.add_do_method(_set_clip_states.bind(committed, primary_id))
	history.add_undo_method(_set_clip_states.bind(original, primary_id))
	history.commit_action()
	changed.emit()


func preview_clip_states(states: Dictionary, primary_id: String) -> bool:
	if states.is_empty() or not can_place_group(states):
		return false
	_set_clip_states(states, primary_id)
	return true


func commit_clip_state_preview(original: Dictionary, final_states: Dictionary,
		action_name: String, primary_id: String) -> void:
	if original.is_empty() or final_states.is_empty() or not can_place_group(final_states):
		return
	var before := original.duplicate(true)
	var after := final_states.duplicate(true)
	history.create_action(action_name)
	history.add_do_method(_set_clip_states.bind(after, primary_id))
	history.add_undo_method(_set_clip_states.bind(before, primary_id))
	history.commit_action()
	changed.emit()


func _set_clip_states(states: Dictionary, primary_id: String) -> void:
	for id: String in states:
		var index := _index_of(id)
		if index < 0:
			continue
		var clip := clips[index]
		var state: Dictionary = states[id]
		clip.start_time = state.start
		clip.duration = state.duration
		clip.layer = state.layer
		clip.source_offset = state.offset
		clip.emit_changed()
	_make_primary(primary_id)
	if selected_clip() != null:
		selected_layer = selected_clip().layer
	changed.emit()


func selected_actor() -> ActorData:
	var index := _index_of(selected_id)
	return actors[index] if index >= 0 else null


func rename_actor(actor: ActorData, name: String) -> void:
	name = name.strip_edges()
	if not actors.has(actor) or name.is_empty() or name == actor.display_name:
		return
	history.create_action("Rename Actor")
	history.add_do_method(_set_name.bind(actor, name))
	history.add_undo_method(_set_name.bind(actor, actor.display_name))
	history.commit_action()
	changed.emit()


## Assigns a logical parent. A parent must exist in this timeline and cannot be
## the actor itself or one of its descendants.
func set_parent(child_id: String, parent_id: String, preserve_world: bool = true) -> void:
	var child := actor_for_id(child_id)
	if child == null or child.parent_id == parent_id or not can_set_parent(child_id, parent_id):
		return
	var previous_parent := child.parent_id
	var previous_values := _transform_values(child)
	var next_values := _values_for_preserved_world(child, parent_id) if preserve_world else previous_values
	history.create_action("Parent Actor" if not parent_id.is_empty() else "Unparent Actor")
	history.add_do_method(_set_parent_state.bind(child, parent_id, next_values))
	history.add_undo_method(_set_parent_state.bind(child, previous_parent, previous_values))
	history.commit_action()
	changed.emit()


func unparent(child_id: String) -> void:
	set_parent(child_id, "")


func parent_many(child_actor_ids: Array[String], parent_id: String) -> void:
	var parent := actor_for_id(parent_id)
	if parent == null:
		return
	var child_lookup: Dictionary = {}
	for child_id in child_actor_ids:
		if child_id != parent_id and actor_for_id(child_id) != null and actor_for_id(child_id).section_id == parent.section_id:
			child_lookup[child_id] = true
	if child_lookup.is_empty():
		return
	var states: Dictionary = {}
	var ancestor := actor_for_id(parent.parent_id)
	if ancestor != null and child_lookup.has(ancestor.id):
		while ancestor != null and child_lookup.has(ancestor.id):
			ancestor = actor_for_id(ancestor.parent_id)
		var external_parent := ancestor.id if ancestor != null else ""
		states[parent.id] = {
			"old_parent": parent.parent_id,
			"old_values": _transform_values(parent),
			"new_parent": external_parent,
			"new_values": _values_for_preserved_world(parent, external_parent)
		}
	for child_id: String in child_lookup:
		var child := actor_for_id(child_id)
		states[child_id] = {
			"old_parent": child.parent_id,
			"old_values": _transform_values(child),
			"new_parent": parent_id,
			"new_values": _values_for_preserved_world(child, parent_id)
		}
	_commit_parent_states(states, "Parent Actors")


func unparent_many(actor_ids: Array[String]) -> void:
	var states: Dictionary = {}
	for actor_id in actor_ids:
		var actor := actor_for_id(actor_id)
		if actor != null and not actor.parent_id.is_empty():
			states[actor_id] = {
				"old_parent": actor.parent_id,
				"old_values": _transform_values(actor),
				"new_parent": "",
				"new_values": _values_for_preserved_world(actor, "")
			}
	_commit_parent_states(states, "Unparent Actors")


func _commit_parent_states(states: Dictionary, action_name: String) -> void:
	if states.is_empty():
		return
	history.create_action(action_name)
	history.add_do_method(_apply_parent_states.bind(states, true))
	history.add_undo_method(_apply_parent_states.bind(states, false))
	history.commit_action()
	changed.emit()


func _apply_parent_states(states: Dictionary, use_new_state: bool) -> void:
	for actor_id: String in states:
		var actor := actor_for_id(actor_id)
		if actor != null:
			var state: Dictionary = states[actor_id]
			_apply_parent_state_silent(actor,
				str(state.new_parent if use_new_state else state.old_parent),
				state.new_values if use_new_state else state.old_values)
	changed.emit()


func can_set_parent(child_id: String, parent_id: String) -> bool:
	var child := actor_for_id(child_id)
	if child == null:
		return false
	if parent_id.is_empty():
		return true
	if parent_id == child_id or actor_for_id(parent_id) == null:
		return false
	if child.section_id != actor_for_id(parent_id).section_id:
		return false
	var ancestor := actor_for_id(parent_id)
	while ancestor != null:
		if ancestor.id == child_id:
			return false
		ancestor = actor_for_id(ancestor.parent_id)
	return true


func actor_for_id(id: String) -> ActorData:
	for actor in actors:
		if actor.id == id:
			return actor
	return null


func clip_for_actor_id(actor_id: String) -> ActorClip:
	for index in actors.size():
		if actors[index].id == actor_id:
			return clips[index]
	return null


func actor_path(actor_id: String) -> String:
	var names := PackedStringArray()
	var current := actor_for_id(actor_id)
	var visited: Dictionary = {}
	while current != null and not visited.has(current.id):
		visited[current.id] = true
		names.insert(0, current.display_name)
		current = actor_for_id(current.parent_id)
	return " / ".join(names)


func _set_parent_state(actor: ActorData, parent_id: String, transform_values: Dictionary) -> void:
	_apply_parent_state_silent(actor, parent_id, transform_values)
	changed.emit()


func _apply_parent_state_silent(actor: ActorData, parent_id: String, transform_values: Dictionary) -> void:
	actor.parent_id = parent_id
	for key: Variant in transform_values:
		actor.values[key] = ActorData.copy_value(transform_values[key])
	actor.emit_changed()


func _transform_values(actor: ActorData) -> Dictionary:
	var result: Dictionary = {}
	for key: StringName in [&"position", &"rotation", &"scale", &"model_basis_residual"]:
		if actor.values.has(key):
			result[key] = ActorData.copy_value(actor.values[key])
	return result


func _local_transform(actor: ActorData) -> Transform3D:
	if actor.type_id.ends_with("_2d"): return Transform3D.IDENTITY
	var position: Vector3 = actor.get_value(&"position", Vector3.ZERO)
	var degrees: Vector3 = actor.get_value(&"rotation", Vector3.ZERO)
	var radians := Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))
	var actor_scale: Vector3 = actor.get_value(&"scale", Vector3.ONE)
	return Transform3D(Basis.from_euler(radians)*Basis.from_scale(actor_scale)*actor.values.get(&"model_basis_residual",Basis.IDENTITY), position)


func world_transform_for(actor_id: String) -> Transform3D:
	return _world_transform_for(actor_id, {})


func _world_transform_for(actor_id: String, visited: Dictionary) -> Transform3D:
	var actor := actor_for_id(actor_id)
	if actor == null or visited.has(actor_id):
		return Transform3D.IDENTITY
	visited[actor_id] = true
	var local := _local_transform(actor)
	if actor.parent_id.is_empty():
		return local
	return _world_transform_for(actor.parent_id, visited) * local


func world_transform_2d_for(actor_id: String) -> Transform2D:
	return _world_transform_2d_for(actor_id, {})

func _world_transform_2d_for(actor_id: String, visited: Dictionary) -> Transform2D:
	var actor := actor_for_id(actor_id)
	if actor == null or not actor.type_id.ends_with("_2d") or visited.has(actor_id): return Transform2D.IDENTITY
	visited[actor_id] = true
	var local := Transform2D(deg_to_rad(float(actor.get_value(&"rotation", 0.0))), actor.get_value(&"scale", Vector2.ONE), 0.0, actor.get_value(&"position", Vector2.ZERO))
	return _world_transform_2d_for(actor.parent_id, visited) * local

func _values_for_preserved_world(actor: ActorData, new_parent_id: String) -> Dictionary:
	var original := _transform_values(actor)
	if actor.type_id.ends_with("_2d"):
		var parent := world_transform_2d_for(new_parent_id)
		if absf(parent.determinant()) <= 0.000001: return original
		var local := parent.affine_inverse() * world_transform_2d_for(actor.id)
		return {&"position": local.origin, &"rotation": rad_to_deg(local.get_rotation()), &"scale": local.get_scale()}
	if original.is_empty():
		return original
	var world := world_transform_for(actor.id)
	var parent_world := Transform3D.IDENTITY if new_parent_id.is_empty() else world_transform_for(new_parent_id)
	if absf(parent_world.basis.determinant()) <= 0.000001:
		return original
	var local := parent_world.affine_inverse() * world
	if actor.values.has(&"model_basis_residual"):
		return KiwiModelDocument.transform_values(local)
	var local_scale := local.basis.get_scale()
	var rotation_basis := local.basis.orthonormalized()
	var radians := rotation_basis.get_euler()
	if actor.values.has(&"position"):
		original[&"position"] = local.origin
	if actor.values.has(&"rotation"):
		original[&"rotation"] = Vector3(rad_to_deg(radians.x), rad_to_deg(radians.y), rad_to_deg(radians.z))
	if actor.values.has(&"scale"):
		original[&"scale"] = local_scale
	return original


func _set_name(actor: ActorData, name: String) -> void:
	actor.display_name = name
	actor.emit_changed()
	changed.emit()


## Left trimming preserves the source time at the unchanged right edge.
func trim_clip(id: String, start: float, duration: float) -> void:
	var index := _index_of(id)
	if index < 0 or not is_finite(start) or not is_finite(duration):
		return
	var clip := clips[index]
	start = maxf(0.0, start)
	duration = maxf(minimum_duration(clip), duration)
	var linked := linked_clip_ids([id])
	if linked.size() > 1:
		var left_delta := start - clip.start_time
		var right_delta := start + duration - clip.start_time - clip.duration
		var states: Dictionary = {}
		for child_id in linked:
			var child := clips[_index_of(child_id)]
			states[child_id] = {"start": child.start_time + left_delta, "duration": child.duration + right_delta - left_delta,
				"offset": child.source_offset + left_delta * child.playback_speed, "layer": child.layer}
		commit_clip_states(states, "Trim Linked Actors", id)
		return
	if not can_place(id, start, duration, clip.layer):
		return
	if is_equal_approx(start, clip.start_time) and is_equal_approx(duration, clip.duration):
		return
	var offset := clip.source_offset + (start - clip.start_time) * clip.playback_speed
	if not ActorAudio.valid(actors[index], clip, duration, offset): return
	history.create_action("Trim Actor")
	history.add_do_method(_set_timing.bind(clip, start, duration, offset))
	history.add_undo_method(_set_timing.bind(clip, clip.start_time, clip.duration, clip.source_offset))
	history.commit_action()
	changed.emit()


func _set_timing(clip: ActorClip, start: float, duration: float, offset: float) -> void:
	clip.start_time = start
	clip.duration = duration
	clip.source_offset = offset
	clip.emit_changed()
	_make_primary(clip.id)
	selected_layer = clip.layer
	changed.emit()


func edit_property(actor: ActorData, definition: ActorDefinition, key: StringName, value: Variant) -> void:
	var property: ActorProperty = definition.find_property(key)
	if not actors.has(actor) or property == null or not property.accepts(value) or actor.type_id != definition.type_id:
		return
	var path := PackedStringArray([str(key)])
	if actor.animation_track(path) != null:
		commit_animation_value(actor, path, value)
		return
	if _values_equal(actor.get_value(key), value):
		return
	if actor.type_id in [&"video", &"video_2d"] and key in [&"video", &"linked_audio_actor"]:
		edit_video_property(actor, key, value)
		return
	if actor.type_id == &"audio" and key in [&"speed", &"audio"] and not property_batch_active:
		var before := audio_snapshot(actor)
		_set_property(actor, key, value)
		var after := audio_snapshot(actor)
		history.create_action("Change " + property.label)
		history.add_do_method(restore_audio.bind(after))
		history.add_undo_method(restore_audio.bind(before))
		history.commit_action()
		return
	if property_batch_active:
		_set_property(actor, key, value)
		return
	history.create_action("Change " + property.label)
	history.add_do_method(_set_property.bind(actor, key, ActorData.copy_value(value)))
	history.add_undo_method(_set_property.bind(actor, key, ActorData.copy_value(actor.get_value(key))))
	history.commit_action()
	changed.emit()


## Used during a pointer gesture so runtimes update without filling undo history.
func preview_property(actor: ActorData, definition: ActorDefinition, key: StringName, value: Variant) -> void:
	var property := definition.find_property(key)
	if actors.has(actor) and property != null and property.accepts(value) and actor.type_id == definition.type_id:
		if actor.type_id == &"audio" and key in [&"speed", &"audio"] and not _audio_preview_before.has(actor.id):
			_audio_preview_before[actor.id] = audio_snapshot(actor)
		var path := PackedStringArray([str(key)])
		if actor.animation_track(path) != null:
			preview_animation_value(actor, path, value)
			return
		_set_property(actor, key, value)


## Adds one undo entry after live previews have already applied the final value.
func commit_property_preview(actor: ActorData, definition: ActorDefinition, key: StringName,
		original: Variant, final_value: Variant) -> void:
	var property := definition.find_property(key)
	var path := PackedStringArray([str(key)])
	if actors.has(actor) and property != null and property.accepts(final_value) and actor.animation_track(path) != null:
		commit_animation_value(actor, path, final_value)
		return
	if not actors.has(actor) or property == null or not property.accepts(final_value) or _values_equal(original, final_value):
		return
	if property_batch_active:
		_set_property(actor, key, final_value)
		_audio_preview_before.erase(actor.id)
		return
	if actor.type_id == &"audio" and _audio_preview_before.has(actor.id):
		var before: Dictionary = _audio_preview_before[actor.id]
		_audio_preview_before.erase(actor.id)
		_set_property(actor, key, final_value)
		history.create_action("Change " + property.label)
		history.add_do_method(restore_audio.bind(audio_snapshot(actor)))
		history.add_undo_method(restore_audio.bind(before))
		history.commit_action()
		return
	history.create_action("Change " + property.label)
	history.add_do_method(_set_property.bind(actor, key, ActorData.copy_value(final_value)))
	history.add_undo_method(_set_property.bind(actor, key, ActorData.copy_value(original)))
	history.commit_action()
	changed.emit()


func _set_property(actor: ActorData, key: StringName, value: Variant) -> void:
	if actor.type_id == &"audio" and key in [&"speed", &"audio"]:
		var clip := clip_for_actor_id(actor.id)
		if clip != null:
			if key == &"speed":
				if not is_finite(float(value)): return
				value = clampf(float(value), 0.25, 4.0)
				clip.duration *= clip.playback_speed / float(value)
				clip.playback_speed = float(value)
			else:
				var stream := ActorAudio.source(value)
				if stream == null and value != null and str(value) != "": return
				clip.source_offset = 0.0
				clip.duration = stream.get_length() / clip.playback_speed if stream != null else MIN_DURATION
			# A slower clip may need a new layer; never silently overlap a neighbor.
			while not can_place(clip.id, clip.start_time, clip.duration, clip.layer):
				clip.layer += 1
	actor.set_value(key, ActorData.copy_value(value))
	changed.emit()


func edit_object_property(actor: ActorData, object: ActorObjectData,
		definition: ActorObjectDefinition, key: StringName, value: Variant) -> void:
	if not actors.has(actor) or object == null or definition == null:
		return
	var property: ActorProperty = definition.find_property(key)
	if property != null and property.accepts(value) and _animated_object_edit(actor, object, key, value, false):
		return
	if property == null or not property.accepts(value) or _values_equal(definition.value_for(object, property), value):
		return
	var original: Variant = ActorData.copy_value(definition.value_for(object, property))
	history.create_action("Change " + property.label)
	history.add_do_method(_set_object_property.bind(object, key, ActorData.copy_value(value)))
	history.add_undo_method(_set_object_property.bind(object, key, original))
	history.commit_action()
	changed.emit()


func _values_equal(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	return left == right


func preview_object_property(actor: ActorData, object: ActorObjectData,
		definition: ActorObjectDefinition, key: StringName, value: Variant) -> void:
	var property: ActorProperty = definition.find_property(key) if definition != null else null
	if actors.has(actor) and object != null and property != null and property.accepts(value):
		if _animated_object_edit(actor, object, key, value, true):
			return
		_set_object_property(object, key, value)


func commit_object_property_preview(actor: ActorData, object: ActorObjectData,
		definition: ActorObjectDefinition, key: StringName, original: Variant, final_value: Variant) -> void:
	var property: ActorProperty = definition.find_property(key) if definition != null else null
	if actors.has(actor) and object != null and property != null and property.accepts(final_value) \
			and _animated_object_edit(actor, object, key, final_value, false):
		return
	if not actors.has(actor) or object == null or property == null or not property.accepts(final_value) or original == final_value:
		return
	history.create_action("Change " + property.label)
	history.add_do_method(_set_object_property.bind(object, key, ActorData.copy_value(final_value)))
	history.add_undo_method(_set_object_property.bind(object, key, ActorData.copy_value(original)))
	history.commit_action()
	changed.emit()


func _set_object_property(object: ActorObjectData, key: StringName, value: Variant) -> void:
	object.set_value(key, ActorData.copy_value(value))
	if not object.resource_path.is_empty():
		var path:=object.resource_path.get_slice("::",0)
		var root:=ResourceLoader.load(path) as ActorObjectData if object.resource_path.contains("::") else object
		if root!=null: root.emit_changed(); ResourceSaver.save(root,path)
	changed.emit()


func selected_clip() -> ActorClip:
	var index := _index_of(selected_id)
	return clips[index] if index >= 0 else null


func undo() -> void:
	if history.has_undo():
		history.undo()
	changed.emit()


func redo() -> void:
	if history.has_redo():
		history.redo()
	changed.emit()


func _index_of(id: String) -> int:
	for index in clips.size():
		if clips[index].id == id:
			return index
	return -1


func _insert(actor: ActorData, clip: ActorClip, index: int, selection: String) -> void:
	actors.insert(index, actor)
	clips.insert(index, clip)
	_set_single_selection(selection)
	selected_layer = clip.layer
	changed.emit()


func _remove(id: String, selection: String) -> void:
	var index := _index_of(id)
	if index >= 0:
		actors.remove_at(index)
		clips.remove_at(index)
	selected_ids.erase(id)
	if _index_of(selection) >= 0:
		_set_single_selection(selection)
	elif not selected_ids.is_empty():
		selected_id = selected_ids.back()
	else:
		selected_id = ""
	changed.emit()


func _remove_many(ids: Array[String], child_states: Dictionary) -> void:
	for child_id: String in child_states:
		var child := actor_for_id(child_id)
		if child != null:
			var state: Dictionary = child_states[child_id]
			_apply_parent_state_silent(child, str(state.new_parent), state.new_values)
	var indices: Array[int] = []
	for id in ids:
		var index := _index_of(id)
		if index >= 0:
			indices.append(index)
	indices.sort()
	indices.reverse()
	for index in indices:
		actors.remove_at(index)
		clips.remove_at(index)
	selected_ids.clear()
	selected_id = ""
	changed.emit()


func _insert_many(removed: Array[Dictionary], selection: Array[String], child_states: Dictionary) -> void:
	removed.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.index) < int(b.index))
	for entry in removed:
		actors.insert(int(entry.index), entry.actor)
		clips.insert(int(entry.index), entry.clip)
	for child_id: String in child_states:
		var child := actor_for_id(child_id)
		if child != null:
			var state: Dictionary = child_states[child_id]
			_apply_parent_state_silent(child, str(state.old_parent), state.old_values)
	selected_ids.clear()
	for id in selection:
		if _index_of(id) >= 0:
			selected_ids.append(id)
	selected_id = selected_ids.back() if not selected_ids.is_empty() else ""
	changed.emit()


func _insert_copies(entries: Array[Dictionary], selection: Array[String]) -> void:
	for entry in entries:
		actors.append(entry.actor)
		clips.append(entry.clip)
	selected_ids.clear()
	for id in selection:
		if _index_of(id) >= 0:
			selected_ids.append(id)
	selected_id = selected_ids.back() if not selected_ids.is_empty() else ""
	if selected_clip() != null:
		selected_layer = selected_clip().layer
	changed.emit()


func _remove_copies(ids: Array[String], previous_selection: Array[String]) -> void:
	var indices: Array[int] = []
	for id in ids:
		var index := _index_of(id)
		if index >= 0:
			indices.append(index)
	indices.sort()
	indices.reverse()
	for index in indices:
		actors.remove_at(index)
		clips.remove_at(index)
	selected_ids.clear()
	for id in previous_selection:
		if _index_of(id) >= 0:
			selected_ids.append(id)
	selected_id = selected_ids.back() if not selected_ids.is_empty() else ""
	changed.emit()


func _remove_with_child_states(id: String, selection: String, child_states: Dictionary,
		use_new_state: bool) -> void:
	for child_id: String in child_states:
		var child := actor_for_id(child_id)
		if child != null:
			var state: Dictionary = child_states[child_id]
			_set_parent_state(child,
				str(state.new_parent if use_new_state else state.old_parent),
				state.new_values if use_new_state else state.old_values)
	_remove(id, selection)


func _insert_with_child_states(actor: ActorData, clip: ActorClip, index: int,
		selection: String, child_states: Dictionary) -> void:
	_insert(actor, clip, index, selection)
	for child_id: String in child_states:
		var child := actor_for_id(child_id)
		if child != null:
			var state: Dictionary = child_states[child_id]
			_set_parent_state(child, str(state.old_parent), state.old_values)


func _set_start(clip: ActorClip, time: float, layer: int) -> void:
	clip.start_time = time
	clip.layer = layer
	clip.emit_changed()
	_make_primary(clip.id)
	selected_layer = layer
	changed.emit()


func _set_single_selection(id: String) -> void:
	selected_ids.clear()
	if _index_of(id) >= 0:
		selected_ids.append(id)
		selected_id = id
	else:
		selected_id = ""


func _make_primary(id: String) -> void:
	if _index_of(id) < 0:
		return
	selected_ids.erase(id)
	selected_ids.append(id)
	selected_id = id
