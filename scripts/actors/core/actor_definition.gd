class_name ActorDefinition
extends Resource
## Register one definition per actor type. Property IDs are persistent save keys.

@export var type_id: StringName
@export var display_name: String
@export var category: String = "General"
@export var description: String = ""
@export var icon: Texture2D
@export var schema_version: int = 1
@export var properties: Array[ActorProperty] = []
## Root must extend ActorRuntime. Child nodes can be any Godot node type.
@export var runtime_scene: PackedScene


func find_property(property_id: StringName) -> ActorProperty:
	for property in properties:
		if property != null and property.id == property_id:
			return property
	return null


func create_actor(initial_values: Dictionary = {}) -> ActorData:
	var actor := ActorData.new()
	actor.id = ActorData.new_id()
	actor.type_id = type_id
	actor.display_name = display_name
	actor.schema_version = schema_version
	for property in properties:
		actor.values[property.id] = property.create_default()
	for property in properties:
		if initial_values.has(property.id) and property.accepts(initial_values[property.id]):
			actor.values[property.id] = ActorData.copy_value(initial_values[property.id])
	# Resolve actor-dependent defaults only after source properties such as the
	# selected image path have been installed.
	for property in properties:
		if not initial_values.has(property.id):
			actor.values[property.id] = property.create_default_for_actor(actor)
	return actor


## Shared entry point for inspector edits and commands. Undo is added by caller.
func set_property_value(actor: ActorData, property_id: StringName, value: Variant) -> bool:
	var property := find_property(property_id)
	if actor.type_id != type_id or property == null or not property.accepts(value):
		return false
	actor.set_value(property_id, value)
	return true


func create_runtime(actor: ActorData) -> ActorRuntime:
	if runtime_scene == null or actor.type_id != type_id:
		return null
	var instance := runtime_scene.instantiate()
	if not instance is ActorRuntime:
		instance.free()
		push_error("Actor runtime scene root must extend ActorRuntime: " + str(type_id))
		return null
	instance.bind(actor)
	return instance
