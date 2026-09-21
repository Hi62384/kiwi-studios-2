class_name ActorObjectDefinition
extends Resource
## Use the same property descriptions for file assets and embedded objects.

@export var type_id: StringName
## Creation compatibility only; properties are never inherited.
@export var base_type: StringName
@export var display_name: String
@export var schema_version: int = 1
@export var properties: Array[ActorProperty] = []


func find_property(property_id: StringName) -> ActorProperty:
	for property in properties:
		if property != null and property.id == property_id:
			return property
	return null


## Saved resources can predate newly added schema fields. Missing or invalid
## values read as the current definition default without rewriting the file.
func value_for(object: ActorObjectData, property: ActorProperty) -> Variant:
	if object != null and object.values.has(property.id):
		var value: Variant = object.values[property.id]
		if property.accepts(value):
			return value
	return property.create_default()


func create_object() -> ActorObjectData:
	var object := ActorObjectData.new()
	object.type_id = type_id
	object.schema_version = schema_version
	for property in properties:
		object.values[property.id] = property.create_default()
	return object


func set_property_value(object: ActorObjectData, property_id: StringName, value: Variant) -> bool:
	if object.type_id != type_id:
		return false
	for property in properties:
		if property.id == property_id and property.accepts(value):
			object.set_value(property_id, value)
			return true
	return false
