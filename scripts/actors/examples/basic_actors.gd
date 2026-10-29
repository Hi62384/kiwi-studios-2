class_name BasicActors
extends RefCounted
## Compatibility entry point. Actor data lives in the editable catalog resource.

const CATALOG = preload("res://scripts/actors/examples/basic_actor_catalog.tres")

static func register_all(registry: ActorRegistry) -> bool:
	var ok:=true
	var catalog: Resource=ResourceLoader.load("res://scripts/actors/examples/basic_actor_catalog.tres","",ResourceLoader.CACHE_MODE_REUSE)
	if catalog==null: return false
	for object_definition: ActorObjectDefinition in catalog.get("object_definitions"):
		ok=registry.register_object(object_definition) and ok
	for definition: ActorDefinition in catalog.get("definitions"):
		ok=registry.register(definition) and ok
	ok=registry.register_object(KiwiPowderMaterial.definition()) and registry.register_object(KiwiDestructionMaterial.definition()) and registry.register_object(KiwiDestructionMaterial.region_definition()) and registry.register(KiwiFluidDefinition.create()) and registry.register(KiwiPowderDefinition.create()) and ok
	if registry.get_definition(&"environment_asset")==null: ok=registry.register(preload("res://Workspaces/EnvironmentWorkspace/environment_actor_definition.gd").create(registry.get_definition(&"point_3d"))) and ok
	for definition in registry.get_definitions():
		KiwiDestructionDefinition.extend_actor(definition)
		KiwiStructure.extend_actor(definition)
		KiwiDebris.extend_actor(definition)
		KiwiDestructionAuthoring.extend_actor(definition)
		KiwiGrowthActor.extend_actor(definition)
		preload("res://scripts/actors/fog/fog_actor.gd").extend_actor(definition)
		preload("res://scripts/actors/fog/fog_motion_definition.gd").extend_actor(definition)
		preload("res://scripts/actors/fog/fog_lighting.gd").extend_actor(definition)
	preload("res://scripts/actors/fog/fog_lighting.gd").extend_environment(registry.get_object_definition(&"environment"))
	ok=registry.register_object(preload("res://scripts/actors/fog/fog_appearance.gd").definition()) and ok
	ok=registry.register_object(preload("res://scripts/actors/fog/fog_field.gd").definition()) and ok
	ok=registry.register_object(preload("res://scripts/actors/fog/fog_motion_definition.gd").emitter_definition()) and ok
	ok=registry.register_object(preload("res://scripts/actors/fog/fog_motion_definition.gd").velocity_definition()) and ok
	if registry.get_definition(&"global_fog")==null:
		ok=registry.register(preload("res://scripts/actors/fog/fog_actor.gd").global_definition(registry.get_definition(&"fog_volume"))) and ok
	ok=registry.register_object(KiwiDebris.preset_definition()) and ok
	ok=registry.register_object(KiwiDestructionAuthoring.definition()) and ok
	for type: StringName in [&"material",&"shader_material",&"natural_material"]:
		var object:=registry.get_object_definition(type)
		if object!=null and object.find_property(&"damage_material")==null:
			var p:=ActorProperty.create(&"damage_material","Associated physical damage material",null); p.object_type=&"destruction_material"; p.options.group="Physical association"; object.properties.append(p)
	return ok
