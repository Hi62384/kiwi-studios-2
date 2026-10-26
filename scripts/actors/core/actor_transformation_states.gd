class_name ActorTransformationStates
extends RefCounted
## Scene-owned state choices never modify the source transformation asset.

static var _assets: Dictionary = {}

static func source_path(actor: ActorData) -> String:
	var value: Variant = actor.values.get(&"transformation", "")
	return ProjectSettings.globalize_path(value).replace("\\", "/").simplify_path() if value is String and not value.is_empty() else ""

static func invalidate(path: String) -> void:
	_assets.erase(ProjectSettings.globalize_path(path).replace("\\", "/").simplify_path())

static func load_asset(actor: ActorData) -> Dictionary:
	var path := source_path(actor)
	if path.is_empty(): return {"document": null, "error": "Choose a Transformation Image 2D asset."}
	var now := Time.get_ticks_msec()
	var entry: Dictionary = _assets.get(path, {})
	var document: KiwiTransformationImage2D = entry.document.get_ref() if entry.get("document") is WeakRef else null
	# Inspector refreshes and scene samples share the same immutable document.
	var cached := not entry.is_empty() and (document != null or not str(entry.error).is_empty())
	if cached and now - int(entry.checked) < 250: return {"document": document, "error": entry.error}
	var stamp := FileAccess.get_modified_time(path)
	if cached and stamp == entry.stamp:
		entry.checked = now
		return {"document": document, "error": entry.error}
	var error := "Transformation asset is missing or invalid."
	if FileAccess.file_exists(path) and path.get_extension().to_lower() in ["tres", "res"]:
		document = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as KiwiTransformationImage2D
		if document != null:
			var errors := document.validate()
			if errors.is_empty(): error = ""
			else: error = errors[0]; document = null
	# Runtimes own their documents. Weak cache entries avoid retaining closed
	# scenes, without evicting active assets and reloading them every frame.
	entry = {"document": weakref(document) if document != null else null, "error": error, "stamp": stamp, "checked": now}
	if _assets.size() >= 64:
		for old_path in _assets.keys():
			var previous: Dictionary = _assets[old_path]
			if not previous.document is WeakRef or previous.document.get_ref() == null: _assets.erase(old_path)
	_assets[path] = entry
	return {"document": document, "error": error}

static func path_for(component_id: String) -> PackedStringArray:
	return PackedStringArray(["component_states", component_id])

static func current(actor: ActorData, item: KiwiTransformationComponent, time: float) -> String:
	var base: Dictionary = actor.values.get(&"component_states", {})
	var fallback := str(base.get(item.id, item.default_state_id))
	if not base.has(item.id) and actor.get_value(&"play_asset_animation", false):
		var keys := item.sorted_keys()
		for index in keys.size():
			if index == 0 or keys[index].time <= time: fallback = keys[index].state_id
			else: break
	var value: Variant = ActorAnimation.sampled_value(actor, path_for(item.id), time, fallback)
	return str(value) if item.state_for_id(str(value)) != null else item.default_state_id

static func property_for(item: KiwiTransformationComponent) -> ActorProperty:
	var property := ActorProperty.create(StringName("state_" + item.id), "Current state", item.default_state_id, true)
	property.options["track_label"] = "States / " + item.title
	return property

static func capture(model: RefCounted, actor: ActorData) -> Dictionary:
	return {"actor": actor, "states": ActorData.copy_value(actor.values.get(&"component_states", {})), "tracks": model.animation_snapshot(actor)}

static func restore(model: RefCounted, snapshots: Array[Dictionary]) -> void:
	for saved in snapshots:
		saved.actor.values[&"component_states"] = ActorData.copy_value(saved.states)
		saved.actor.animation_previews.clear()
		model.restore_animation(saved.actor, saved.tracks)

static func choose(model: RefCounted, actor: ActorData, item: KiwiTransformationComponent, state_id: String) -> void:
	if item.state_for_id(state_id) == null: return
	var targets: Array = model.selected_actors() if model.selected_actors().has(actor) else [actor]
	var before: Array[Dictionary] = []; var after: Array[Dictionary] = []
	for target: ActorData in targets:
		if target.type_id != &"transform_image_2d" or source_path(target) != source_path(actor): continue
		var clip: ActorClip = model.clip_for_actor_id(target.id)
		if clip == null: continue
		var path := path_for(item.id)
		var explicit_state: bool = (target.values.get(&"component_states", {}) as Dictionary).has(item.id) or target.animation_track(path) != null or not target.get_value(&"play_asset_animation", false)
		if explicit_state and current(target, item, clip.local_time(model.playhead_time)) == state_id: continue
		before.append(capture(model, target))
		if target.animation_track(path) != null:
			model.property_batch_active = true
			model.add_keyframe(target, path, "States / " + item.title, state_id)
			model.property_batch_active = false
		else:
			var states: Dictionary = target.values.get(&"component_states", {}).duplicate()
			states[item.id] = state_id
			target.values[&"component_states"] = states
		after.append(capture(model, target))
	if before.is_empty(): return
	model.history.create_action("Change Transformation State")
	model.history.add_do_method(restore.bind(model, after))
	model.history.add_undo_method(restore.bind(model, before))
	model.history.commit_action()

static func samples(actor: ActorData, document: KiwiTransformationImage2D, time: float, values: Dictionary) -> Dictionary:
	var result := {}
	var selected: Dictionary = actor.values.get(&"component_states", {})
	for item in document.components:
		var path := path_for(item.id)
		var track := actor.animation_track(path)
		var preview: Dictionary = actor.animation_previews.get(" / ".join(path), {})
		if track == null and not selected.has(item.id) and preview.is_empty() and values.get(&"play_asset_animation", false): continue
		var id := str(selected.get(item.id, item.default_state_id))
		var segment := {"from": id, "to": id, "weight": 0.0, "key": null}
		if track != null: segment = track.transition_at(time, id)
		if not preview.is_empty(): segment = {"from": str(preview.value), "to": str(preview.value), "weight": 0.0, "key": null}
		var a := item.state_for_id(str(segment.from)); var b := item.state_for_id(str(segment.to))
		if a == null: a = item.state_for_id(item.default_state_id)
		if b == null: b = a
		var outgoing := KiwiTransformationKey.new()
		# Guidance belongs to a particular pair, not every transition leaving A.
		# Reusing A->B control points for A->C would distort the unrelated target.
		var authored := item.sorted_keys()
		for index in range(authored.size() - 1):
			if a != null and b != null and authored[index].state_id == a.id and authored[index + 1].state_id == b.id:
				outgoing = authored[index].copy_key()
				break
		var mode := int(values.get(&"morph_mode", 0))
		if mode > 0: outgoing.mode = KiwiTransformationKey.MODES[clampi(mode - 1, 0, KiwiTransformationKey.MODES.size() - 1)]
		if segment.key != null and segment.key.interpolation == ActorKeyframe.Interpolation.STEP: outgoing.mode = "Step"
		result[item.id] = {"a": a, "b": b, "t": 0.0 if outgoing.mode == "Step" else clampf(float(segment.weight), 0.0, 1.0), "key": outgoing}
	return result
