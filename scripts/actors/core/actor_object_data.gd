class_name ActorObjectData
extends Resource
## A typed property collection, embedded in an actor or saved as a .tres asset.
## Embedded objects form an ownership tree; use asset IDs for shared references.

@export var type_id: StringName
@export var schema_version: int = 1
@export var values: Dictionary = {}


func set_value(property_id: StringName, value: Variant) -> void:
	values[property_id] = value
	emit_changed()


func get_value(property_id: StringName, fallback: Variant = null) -> Variant:
	return values.get(property_id, fallback)


func copy_object() -> ActorObjectData:
	var result := ActorObjectData.new()
	result.type_id = type_id
	result.schema_version = schema_version
	result.values = ActorData.copy_value(values)
	return result
