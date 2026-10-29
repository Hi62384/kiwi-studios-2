extends RefCounted
## Shared identity remapping for copied native hierarchies and their source metadata.
static func component(item: KiwiModelComponent,mapping: Dictionary) -> void:
	var original_parameters:=item.parameters.duplicate(true); original_parameters.erase("_module_bindings")
	if item.parameters.get("_module_bindings") is Dictionary:
		var remapped: Dictionary={}
		for owner in item.parameters._module_bindings:
			if not mapping.has(str(owner)): continue
			var binding: Dictionary=item.parameters._module_bindings[owner].duplicate(true); binding.parent=mapping.get(str(binding.get("parent","")),binding.get("parent","")); remapped[mapping[str(owner)]]=binding
		item.parameters._module_bindings=remapped
	item.skeleton_id=mapping.get(item.skeleton_id,item.skeleton_id)
	if item.growth!=null: item.growth.source_id=mapping.get(item.growth.source_id,item.growth.source_id)
	_structure(item.structural,mapping)
	if item.parameters.get("_architecture_structure") is Dictionary: _structure(item.parameters._architecture_structure,mapping)
	if item.parameters.has("architecture_owner"):
		var owner:=str(item.parameters.architecture_owner)
		if mapping.has(owner): item.parameters.architecture_owner=mapping[owner]
		elif item.parameters.has("architecture_key"):
			# A copied wall/door is an ordinary extra component, not a second source
			# instance with the same procedural key inside the original building.
			item.parameters.erase("architecture_key"); item.parameters.erase("architecture_owner"); item.parameters.erase("architecture_material_slot"); item.parameters.erase("architecture_material_slots")
			if item.structural.has(&"structure_assembly"): item.structural[&"structure_assembly"]=item.id
	var source: Variant=item.parameters.get("architecture_source")
	if source is Resource and source.get_script()==preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd"):
		var copied: Resource=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd").copy(source); copied.source_id=item.id; item.parameters.architecture_source=copied
	var world: Variant=item.parameters.get("world_source")
	if world is Resource and world.get_script()==preload("res://Workspaces/EnvironmentWorkspace/world/world_source.gd"):
		var copied: Resource=world.copy(); var previous:=str(copied.world_id); copied.world_id=item.id; copied.terrain_id=mapping.get(str(copied.terrain_id),copied.terrain_id); copied.owned_terrain_id=mapping.get(str(copied.owned_terrain_id),"")
		for region: Dictionary in copied.regions: region.id=str(region.id).replace(previous+":region:",item.id+":region:")
		item.parameters.world_source=copied
	if item.parameters.has("world_owner"):
		var owner:=str(item.parameters.world_owner)
		if mapping.has(owner):
			item.parameters.world_owner=mapping[owner]
			if item.parameters.has("world_parent"): item.parameters.world_parent=mapping.get(str(item.parameters.world_parent),item.parameters.world_parent)
			if item.parameters.has("world_region"): item.parameters.world_region=str(item.parameters.world_region).replace(owner+":region:",str(mapping[owner])+":region:")
		else:
			for key in ["world_owner","world_generated","world_key","world_mesh_key","world_mesh_version","world_global_pose","world_parent","world_manual_parent","world_generated_visible"]: item.parameters.erase(key)
	for binding: Dictionary in item.parameters.get("_module_bindings",{}).values():
		_structure(binding.get("structure",{}),mapping)
		if binding.get("parameters",{})==original_parameters:
			var current:=item.parameters.duplicate(true); current.erase("_module_bindings"); binding.parameters=current
		else:
			var baseline:=KiwiModelComponent.new(); baseline.id=item.id; baseline.parameters=binding.get("parameters",{}).duplicate(true); component(baseline,mapping); binding.parameters=baseline.parameters
static func _structure(settings: Dictionary,mapping: Dictionary) -> void:
	for link: Dictionary in settings.get(&"structure_connections",{}).values(): link.target=mapping.get(str(link.get("target","")),"")
	if settings.has(&"structure_assembly"): settings[&"structure_assembly"]=mapping.get(str(settings[&"structure_assembly"]),settings[&"structure_assembly"])
static func terrain(source: KiwiEnvironmentTerrain,mapping: Dictionary) -> void:
	if source==null: return
	for cave: KiwiTerrainCave in source.caves:
		if not cave.has_meta("world_road_owner"): continue
		var owner:=str(cave.get_meta("world_road_owner"))
		if mapping.has(owner): cave.set_meta("world_road_owner",mapping[owner]); cave.cave_id=cave.cave_id.replace(owner+":tunnel:",str(mapping[owner])+":tunnel:")
		else: cave.remove_meta("world_road_owner")
	if source.generation==null: return
	for layer in source.generation.layers:
		if layer.get("type","")=="Foundation" and mapping.has(str(layer.get("foundation_owner",""))): layer.foundation_owner=mapping[str(layer.foundation_owner)]; layer.id="foundation:"+str(layer.foundation_owner)
		if mapping.has(str(layer.get("world_road_owner",""))): layer.world_road_owner=mapping[str(layer.world_road_owner)]
