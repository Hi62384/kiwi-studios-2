class_name ActorCatalog
extends Resource
## Editable, saveable collection of actor types available to the editor.

@export var definitions: Array[ActorDefinition] = []
@export var object_definitions: Array[ActorObjectDefinition] = []


func register_into(registry: ActorRegistry) -> bool:
	for object_definition in object_definitions:
		if not registry.register_object(object_definition):
			return false
	for definition in definitions:
		if not registry.register(definition):
			return false
	return true
