class_name ActorPropertyBatch
extends RefCounted
## Inspector multi-edit gestures preserve each actor's original value and commit
## one history entry, including actor-owned animation tracks.

var model: ActorTimeline
var registry: ActorRegistry
var _before: Array[Dictionary] = []
var _key: StringName
var _primary_original: Variant

func targets(primary: ActorData, key: StringName, value: Variant) -> Array[ActorData]:
	var result: Array[ActorData] = []
	var candidates := model.selected_actors() if model.selected_actors().has(primary) else [primary]
	for actor: ActorData in candidates:
		var definition := registry.get_definition(actor.type_id)
		var property := definition.find_property(key) if definition != null else null
		if property != null and property.accepts(value): result.append(actor)
	return result

func capture(actors: Array[ActorData], key: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for actor in actors:
		result.append({"actor": actor, "key": key, "value": ActorData.copy_value(actor.values.get(key)), "tracks": model.animation_snapshot(actor)})
		if actor.type_id == &"audio" and key in [&"audio", &"speed"]:
			var clip := model.clip_for_actor_id(actor.id)
			result[-1]["timing"] = {"clip": clip, "duration": clip.duration, "offset": clip.source_offset, "speed": clip.playback_speed, "layer": clip.layer}
	return result

func restore(states: Array[Dictionary]) -> void:
	for state in states:
		model._audio_preview_before.erase(state.actor.id)
		if state.has("timing"):
			var timing: Dictionary = state.timing
			timing.clip.duration = timing.duration
			timing.clip.source_offset = timing.offset
			timing.clip.playback_speed = timing.speed
			timing.clip.layer = timing.layer
		state.actor.values[state.key] = ActorData.copy_value(state.value)
		state.actor.animation_previews.clear()
		model.restore_animation(state.actor, state.tracks)

func edit(primary: ActorData, key: StringName, value: Variant) -> void:
	if primary.type_id in [&"video", &"video_2d"] and key in [&"video", &"linked_audio_actor"]:
		model.edit_property(primary, registry.get_definition(primary.type_id), key, value)
		return
	var actors := targets(primary, key, value)
	var before := capture(actors, key)
	model.property_batch_active = true
	for actor in actors: model.edit_property(actor, registry.get_definition(actor.type_id), key, value)
	model.property_batch_active = false
	commit(before, capture(actors, key), key)

func preview(primary: ActorData, key: StringName, value: Variant) -> void:
	if _before.is_empty():
		_key = key
		_primary_original = ActorData.copy_value(primary.get_value(key))
		_before = capture(targets(primary, key, value), key)
	# Existing inspector cancellation callbacks restore the primary's origin.
	# Restore every actor's own origin instead of copying that value to all actors.
	if value == _primary_original:
		restore(_before)
		_before.clear()
		return
	for state in _before:
		model.preview_property(state.actor, registry.get_definition(state.actor.type_id), key, value)

func finish(primary: ActorData, key: StringName, original: Variant, value: Variant) -> void:
	if _before.is_empty():
		if original != value: edit(primary, key, value)
		return
	var before := _before
	_before = []
	model.property_batch_active = true
	for state in before:
		model.commit_property_preview(state.actor, registry.get_definition(state.actor.type_id), key,
			state.value, value)
	model.property_batch_active = false
	var actors: Array[ActorData] = []
	for state in before: actors.append(state.actor)
	commit(before, capture(actors, key), key)

func commit(before: Array[Dictionary], after: Array[Dictionary], key: StringName) -> void:
	if before.is_empty(): return
	var definition := registry.get_definition(before[0].actor.type_id)
	var property := definition.find_property(key)
	var label := property.label if property != null else str(key)
	model.history.create_action(("Change " if before.size() == 1 else "Change Selected Actors: ") + label)
	model.history.add_do_method(restore.bind(after))
	model.history.add_undo_method(restore.bind(before))
	model.history.commit_action()
