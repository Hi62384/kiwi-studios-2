class_name ActorAnimationTrack
extends Resource
## Paths address actor values, object slots, and individual shader uniforms.

@export var path: PackedStringArray
@export var label: String = ""
@export var keys: Array[ActorKeyframe] = []
@export var component: int = -1
@export var component_base: Variant

func sort_keys() -> void:
	keys.sort_custom(func(a: ActorKeyframe, b: ActorKeyframe): return a.time < b.time)

func key_at(time: float) -> ActorKeyframe:
	for key in keys:
		if absf(key.time - time) < 0.00001:
			return key
	return null

func sample(time: float, fallback: Variant = null) -> Variant:
	if keys.is_empty():
		return fallback
	if time <= keys[0].time:
		return keys[0].value
	for index in range(1, keys.size()):
		var right := keys[index]
		var left := keys[index - 1]
		if time <= right.time:
			if time == right.time:
				return right.value
			var text_value := typeof(left.value) in [TYPE_STRING, TYPE_STRING_NAME]
			if (left.interpolation == ActorKeyframe.Interpolation.STEP and not text_value) or typeof(left.value) != typeof(right.value):
				return left.value
			var weight := (time - left.time) / maxf(0.000001, right.time - left.time)
			if left.value_curve != null:
				weight = left.value_curve.sample(weight)
			elif left.interpolation == ActorKeyframe.Interpolation.EASE:
				weight = ease(weight, left.attenuation)
			match typeof(left.value):
				TYPE_STRING, TYPE_STRING_NAME:
					var text := interpolate_text(str(left.value), str(right.value), weight)
					return StringName(text) if left.value is StringName else text
				TYPE_FLOAT: return lerpf(left.value, right.value, weight)
				TYPE_INT: return int(round(lerpf(float(left.value), float(right.value), weight)))
				TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_COLOR: return left.value.lerp(right.value, weight)
				TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I:
					var vector: Variant = left.value
					var count := 2 if vector is Vector2i else (3 if vector is Vector3i else 4)
					for axis in count:
						vector[axis] = int(round(lerpf(float(left.value[axis]), float(right.value[axis]), weight)))
					return vector
			return left.value
	return keys.back().value

static func interpolate_text(left: String, right: String, weight: float) -> String:
	var prefix := 0
	while prefix < mini(left.length(), right.length()) and left[prefix] == right[prefix]: prefix += 1
	var deleted := left.length() - prefix
	var added := right.length() - prefix
	var progress := int(floor(clampf(weight, 0.0, 1.0) * (deleted + added) + 0.000001))
	if progress <= deleted: return left.left(left.length() - progress)
	return right.left(prefix + progress - deleted)

func copy_track() -> ActorAnimationTrack:
	var result := ActorAnimationTrack.new()
	result.path = path.duplicate()
	result.label = label
	result.component = component
	result.component_base = ActorData.copy_value(component_base)
	for key in keys:
		result.keys.append(key.copy_key())
	return result
