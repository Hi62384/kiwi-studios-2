class_name ActorData
extends Resource
## Saved state only. Never store live Nodes in this resource.

@export var id: String = ""
@export var type_id: StringName
@export var display_name: String
@export var parent_id: String = ""
@export var section_id: String = "default"
@export var show_timeline_children: bool = true
@export var link_timeline_children: bool = false
@export var schema_version: int = 1
@export var values: Dictionary = {}
@export var animation_tracks: Array[ActorAnimationTrack] = []
var animation_time: float = NAN
var animation_previews: Dictionary = {}

func animation_track(path: PackedStringArray) -> ActorAnimationTrack:
	for track in animation_tracks:
		if track.path == path:
			return track
	return null


static func new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


func set_value(property_id: StringName, value: Variant) -> void:
	values[property_id] = value
	emit_changed()


func get_value(property_id: StringName, fallback: Variant = null) -> Variant:
	var base: Variant = values.get(property_id, fallback)
	var path := PackedStringArray([str(property_id)])
	var preview: Dictionary = animation_previews.get(" / ".join(path), {})
	if not preview.is_empty():
		return preview.value
	if not is_nan(animation_time):
		return ActorAnimation.sampled_value(self, path, animation_time, base)
	return base


## Copies owned resources and containers; asset references retain their asset ID.
static func copy_value(value: Variant) -> Variant:
	if value is ActorObjectReference:
		return value.copy_reference()
	if value is ActorObjectData:
		return value.copy_object()
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = copy_value(value[key])
		return result
	if value is Array:
		var result: Array = value.duplicate()
		for index in result.size():
			result[index] = copy_value(result[index])
		return result
	if value is Resource:
		return value.duplicate(true)
	return value


func copy_actor() -> ActorData:
	var result := ActorData.new()
	result.id = new_id()
	result.type_id = type_id
	result.display_name = display_name
	result.parent_id = parent_id
	result.section_id = section_id
	result.show_timeline_children = show_timeline_children
	result.link_timeline_children = link_timeline_children
	result.schema_version = schema_version
	result.values = copy_value(values)
	for track in animation_tracks:
		result.animation_tracks.append(track.copy_track())
	return result
