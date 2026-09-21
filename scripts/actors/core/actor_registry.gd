class_name ActorRegistry
extends RefCounted
## Explicit registration keeps adding actors independent of editor UI code.

var _definitions: Dictionary = {}
var _object_definitions: Dictionary = {}


func register(definition: ActorDefinition) -> bool:
	if definition == null or definition.type_id.is_empty() or _definitions.has(definition.type_id):
		return false
	var property_ids: Dictionary = {}
	for property in definition.properties:
		if property == null or property.id.is_empty() or property_ids.has(property.id):
			return false
		if not property.accepts(property.options.get("default")):
			return false
		property_ids[property.id] = true
	_definitions[definition.type_id] = definition
	return true


func get_definition(type_id: StringName) -> ActorDefinition:
	return _definitions.get(type_id)


func get_definitions() -> Array[ActorDefinition]:
	var result: Array[ActorDefinition] = []
	for definition: ActorDefinition in _definitions.values():
		result.append(definition)
	return result


func register_object(definition: ActorObjectDefinition) -> bool:
	if definition == null or definition.type_id.is_empty() or _object_definitions.has(definition.type_id):
		return false
	_object_definitions[definition.type_id] = definition
	return true


func get_object_definition(type_id: StringName) -> ActorObjectDefinition:
	return _object_definitions.get(type_id)


func object_definitions_for(base_type: StringName) -> Array[ActorObjectDefinition]:
	var result: Array[ActorObjectDefinition] = []
	for definition: ActorObjectDefinition in _object_definitions.values():
		if definition.type_id == base_type or definition.base_type == base_type:
			result.append(definition)
	result.sort_custom(func(a: ActorObjectDefinition, b: ActorObjectDefinition):
		if a.type_id == base_type:
			return true
		if b.type_id == base_type:
			return false
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return result


func object_type_matches(type_id: StringName, base_type: StringName) -> bool:
	var definition := get_object_definition(type_id)
	return type_id == base_type or (definition != null and definition.base_type == base_type)
