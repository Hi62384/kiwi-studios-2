class_name ActorImageGenerator
extends RefCounted
## Resolves file-backed Image objects and generates procedural Noise Image data.

const RESOLUTIONS := [64, 128, 256, 512]
static var _noise_image_cache: Dictionary = {}
static var _noise_texture_cache: Dictionary = {}


static func image_for_object(object: ActorObjectData) -> Image:
	if object == null:
		return null
	match object.type_id:
		&"image":
			return image_from_value(object.get_value(&"source", ""))
		&"noise_image":
			return generate_noise(object)
	return null


static func texture_for_object(object: ActorObjectData) -> Texture2D:
	if object != null and object.type_id == &"noise_image":
		var cache_key := var_to_str(object.values)
		var cached: Variant = _noise_texture_cache.get(cache_key)
		if cached is Texture2D and is_instance_valid(cached):
			return cached
		var noise_image := generate_noise(object)
		if noise_image == null or noise_image.is_empty():
			return null
		var noise_texture := ImageTexture.create_from_image(noise_image)
		# A shader workspace, its inline thumbnail, and one or more actors often
		# request the exact same noise revision. Sharing the texture keeps every
		# consumer on the same generated result and avoids several GPU uploads for
		# every drag tick.
		if _noise_texture_cache.size() >= 16:
			_noise_texture_cache.clear()
		_noise_texture_cache[cache_key] = noise_texture
		return noise_texture
	var image := image_for_object(object)
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null


static func image_from_value(value: Variant) -> Image:
	if value is Texture2D:
		return value.get_image()
	if value is Image:
		return value
	var path := str(value)
	if path.is_empty():
		return null
	if path.begins_with("res://") or path.begins_with("user://"):
		path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(path):
		return null
	return Image.load_from_file(path)


static func generate_noise(object: ActorObjectData) -> Image:
	var cache_key := var_to_str(object.values)
	if _noise_image_cache.has(cache_key):
		return _noise_image_cache[cache_key]
	var noise := FastNoiseLite.new()
	noise.noise_type = clampi(int(object.get_value(&"noise_type", FastNoiseLite.TYPE_SIMPLEX_SMOOTH)), 0, 5)
	noise.seed = int(object.get_value(&"seed", 0))
	noise.frequency = clampf(float(object.get_value(&"frequency", 0.015)), 0.0001, 1.0)
	noise.fractal_type = clampi(int(object.get_value(&"fractal_type", FastNoiseLite.FRACTAL_FBM)), 0, 3)
	noise.fractal_octaves = clampi(int(object.get_value(&"octaves", 5)), 1, 10)
	noise.fractal_lacunarity = clampf(float(object.get_value(&"lacunarity", 2.0)), 0.01, 8.0)
	noise.fractal_gain = clampf(float(object.get_value(&"gain", 0.5)), 0.0, 2.0)
	var resolution_index := clampi(int(object.get_value(&"resolution", 2)), 0, RESOLUTIONS.size() - 1)
	var size: int = RESOLUTIONS[resolution_index]
	var invert := bool(object.get_value(&"invert", false))
	var seamless := bool(object.get_value(&"seamless", true))
	var source := noise.get_seamless_image(size, size, invert, false, 0.1) if seamless \
		else noise.get_image(size, size, invert, false, true)
	if source == null or source.is_empty():
		return null
	var low: Color = object.get_value(&"low_color", Color.BLACK)
	var high: Color = object.get_value(&"high_color", Color.WHITE)
	var contrast := clampf(float(object.get_value(&"contrast", 1.0)), 0.01, 4.0)
	var result := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var amount := source.get_pixel(x, y).r
			amount = clampf((amount - 0.5) * contrast + 0.5, 0.0, 1.0)
			result.set_pixel(x, y, low.lerp(high, amount))
	if bool(object.get_value(&"as_normal_map", false)):
		result.bump_map_to_normal_map()
	# Runtime and inspector often request the same revision in one frame. Share
	# that generated image while bounding retained procedural revisions.
	if _noise_image_cache.size() >= 16:
		_noise_image_cache.clear()
	_noise_image_cache[cache_key] = result
	return result
