class_name ActorAnimation
extends RefCounted
## Sampling makes private object overrides. No file-backed resource is mutated.

static func resolve_reference(reference: ActorObjectReference) -> ActorObjectData:
	return reference.resolve(func(path: String):
		return ResourceLoader.load(path) as ActorObjectData if ResourceLoader.exists(path) else null)

static func value_at_path(actor: ActorData, path: PackedStringArray) -> Variant:
	var value: Variant = actor.values
	for part in path:
		if value is ActorObjectReference:
			value = resolve_reference(value)
		if value is ActorObjectData:
			value = value.values
		if not value is Dictionary:
			return null
		value = value.get(StringName(part), value.get(part))
	return value

static func sampled_value(actor: ActorData, path: PackedStringArray, time: float, fallback: Variant = null) -> Variant:
	var preview: Dictionary = actor.animation_previews.get(" / ".join(path), {})
	if not preview.is_empty():
		return preview.value
	var track := actor.animation_track(path)
	if track != null and track.component >= 0:
		var combined: Variant = ActorData.copy_value(track.component_base)
		for part in actor.animation_tracks:
			if part.path == path and part.component >= 0:
				combined[part.component] = part.sample(time, combined[part.component])
		return combined
	return track.sample(time, fallback) if track != null else fallback

static func sampled_values(actor: ActorData, time: float) -> Dictionary:
	var values := actor.values.duplicate()
	var sampled_paths: Dictionary = {}
	for track in actor.animation_tracks:
		if not track.keys.is_empty():
			var path_id := " / ".join(track.path)
			if sampled_paths.has(path_id): continue
			sampled_paths[path_id] = true
			_set_path(values, track.path, sampled_value(actor, track.path, time, value_at_path(actor, track.path)))
	for preview: Dictionary in actor.animation_previews.values():
		_set_path(values, preview.path, preview.value)
	return values

static func _set_path(container: Dictionary, path: PackedStringArray, value: Variant, index: int = 0) -> void:
	if index >= path.size():
		return
	var key := StringName(path[index])
	if index == path.size() - 1:
		container[key] = ActorData.copy_value(value)
		return
	var child: Variant = container.get(key, container.get(str(key)))
	if child is ActorObjectReference:
		var object := resolve_reference(child)
		if object == null:
			return
		var private_object := ActorObjectData.new()
		private_object.type_id = object.type_id
		private_object.values = object.values.duplicate()
		container[key] = ActorObjectReference.from_object(private_object)
		_set_path(private_object.values, path, value, index + 1)
	elif child is Dictionary:
		var private_values: Dictionary = child.duplicate()
		container[key] = private_values
		_set_path(private_values, path, value, index + 1)

static func path_to_object(actor: ActorData, target: ActorObjectData) -> PackedStringArray:
	return _find_object(actor.values, target, PackedStringArray(), {})

static func _find_object(values: Dictionary, target: ActorObjectData, prefix: PackedStringArray, visited: Dictionary) -> PackedStringArray:
	for key: Variant in values:
		var next := prefix.duplicate()
		next.append(str(key))
		if values[key] is Dictionary:
			var nested := _find_object(values[key], target, next, visited)
			if not nested.is_empty():
				return nested
		var reference := values[key] as ActorObjectReference if values[key] is ActorObjectReference else null
		if reference == null:
			continue
		var object := resolve_reference(reference)
		if object == null:
			continue
		if object == target or (not target.resource_path.is_empty() and object.resource_path == target.resource_path):
			return next
		if visited.has(object.get_instance_id()):
			continue
		var branch := visited.duplicate()
		branch[object.get_instance_id()] = true
		var found := _find_object(object.values, target, next, branch)
		if not found.is_empty():
			return found
	return PackedStringArray()
