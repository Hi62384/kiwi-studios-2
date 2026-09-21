class_name ActorProperty
extends Resource
## Describes a property for both actors and reusable objects.

@export var id: StringName
@export var label: String
@export var value_type: int = TYPE_NIL
@export var animatable: bool = false
@export var object_type: StringName
## Inspector hints, e.g. default, min, max, step, suffix, group.
@export var options: Dictionary = {}

enum FileResourceMode { NONE, UNEDITABLE, EDITABLE }

func can_keyframe() -> bool:
	if options.get("no_keyframes", false) or options.get("file_picker", false) or not object_type.is_empty():
		return false
	return value_type in [TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME,
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I, TYPE_COLOR]


func file_resource_mode() -> FileResourceMode:
	match str(options.get("file_resource_mode", "")):
		"uneditable": return FileResourceMode.UNEDITABLE
		"editable": return FileResourceMode.EDITABLE
	return FileResourceMode.NONE


static func create(key: StringName, display_label: String, default: Variant,
		can_animate: bool = false) -> ActorProperty:
	var property := ActorProperty.new()
	property.id = key
	property.label = display_label
	property.value_type = typeof(default)
	property.animatable = can_animate
	property.options = {"default": default}
	return property


func accepts(value: Variant) -> bool:
	if not object_type.is_empty():
		if value == null:
			return true
		if not value is ActorObjectReference:
			return false
		var accepted := PackedStringArray(options.get("accepted_object_types", [str(object_type)]))
		return accepted.has(str(value.object_type))
	if options.get("file_picker", false):
		if value == null or value is String:
			return true
		var extensions := PackedStringArray(options.get("extensions", []))
		if extensions.has("mp3"):
			return value is AudioStream
		if extensions.has("gdshader"):
			return value is Shader
		if extensions.has("glb") or extensions.has("mesh"):
			return value is Mesh or value is PackedScene
		return value is Texture2D or value is Image
	return typeof(value) == value_type


func create_default() -> Variant:
	return ActorData.copy_value(options.get("default"))


## Some defaults depend on another saved actor property. This keeps Reset and
## creation on the same path instead of baking a one-time value into the UI.
func create_default_for_actor(actor: ActorData) -> Variant:
	var image_property: StringName = options.get("aspect_ratio_from_image", &"")
	if actor != null and not image_property.is_empty() and value_type == TYPE_VECTOR3:
		return image_ratio_scale(actor.get_value(image_property, ""))
	return create_default()


static func image_ratio_scale(source: Variant) -> Vector3:
	var image: Image
	if source is ActorObjectReference:
		image = ActorImageGenerator.image_for_object(ActorAnimation.resolve_reference(source))
	elif source is ActorObjectData:
		image = ActorImageGenerator.image_for_object(source)
	elif source is Texture2D:
		image = source.get_image()
	elif source is Image:
		image = source
	else:
		var path := str(source)
		if path.is_empty() or not FileAccess.file_exists(path):
			return Vector3.ONE
		image = Image.load_from_file(path)
	if image == null or image.is_empty():
		return Vector3.ONE
	var width := float(image.get_width())
	var height := float(image.get_height())
	var longest_side := maxf(width, height)
	if longest_side <= 0.0:
		return Vector3.ONE
	return Vector3(width / longest_side, height / longest_side, 1.0)
