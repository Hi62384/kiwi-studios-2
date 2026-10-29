class_name KiwiEnvironmentDocument
extends KiwiModelDocument
## Reuses Kiwi model components and their hierarchy. Environment-specific authored
## generators live alongside them; generated renderer nodes are disposable.
@export var environment_id:=ActorData.new_id()
@export var title:="Untitled Environment"
@export var component_settings: Dictionary={}
@export var random_seed:=1
@export var atmosphere: ActorObjectReference
@export var environment_source:=""
@export var sunlight: Dictionary={"enabled":true,"rotation":Vector3(-45,-30,0),"energy":1.5,"color":Color.WHITE}
@export var climate: Resource=preload("res://Workspaces/EnvironmentWorkspace/environment_climate.gd").new()

func validate() -> PackedStringArray:
	var errors:=super.validate()
	if version>1 or version<1: errors.append("Unsupported environment schema version: %d"%version)
	if climate!=null and climate.has_method("validate"): errors.append_array(climate.validate())
	for id: String in component_settings:
		if component(id)==null: errors.append("Environment settings refer to a missing component: "+id)
		if component_settings[id].get("kind","")=="building":
			var item:=component(id); var source: Resource=item.parameters.get("architecture_source") if item!=null else null
			if source==null or source.get_script()!=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd"): errors.append("Streamed building settings require an authored building source.")
			else: errors.append_array(source.validate())
		var terrain:=component_settings[id].get("terrain") as KiwiEnvironmentTerrain
		if terrain!=null: errors.append_array(terrain.validate())
		var scatter:=component_settings[id].get("scatter") as KiwiEnvironmentScatter
		if scatter!=null:
			errors.append_array(scatter.validate())
			if self.terrain(scatter.terrain_id)==null: errors.append("Scatter has a missing terrain dependency.")
	return errors

func snapshot() -> KiwiModelDocument:
	var result:=KiwiEnvironmentDocument.new(); result.version=version; result.environment_id=environment_id; result.title=title; result.random_seed=random_seed; result.preview=preview; result.preview_png=preview_png; result.workspace_state=workspace_state.duplicate(true); result.sunlight=sunlight.duplicate(true); result.atmosphere=atmosphere.copy_reference() if atmosphere!=null else null; result.climate=climate.copy_climate() if climate!=null and climate.has_method("copy_climate") else climate.duplicate(true) if climate!=null else null
	result.environment_source=environment_source
	for item in components: result.components.append(item.copy_component())
	result.component_settings=component_settings.duplicate(true)
	for id: String in component_settings:
		var terrain:=component_settings[id].get("terrain") as KiwiEnvironmentTerrain
		if terrain!=null: result.component_settings[id].terrain=terrain.duplicate(true)
		var scatter:=component_settings[id].get("scatter") as KiwiEnvironmentScatter
		if scatter!=null: result.component_settings[id].scatter=scatter.duplicate(true)
	return result

func terrain(id: String) -> KiwiEnvironmentTerrain: return component_settings.get(id,{}).get("terrain") as KiwiEnvironmentTerrain
func _component_geometry_errors(item: KiwiModelComponent) -> PackedStringArray:
	# Terrain mesh data is a generated bounds/authoring proxy. Validate its storage,
	# but spend full polygon validation on actual authored Model geometry instead.
	return item.mesh.validate(component_kind(item.id)!="terrain")
func water_at(world_point: Vector3,environment_pose: Transform3D=Transform3D.IDENTITY) -> Dictionary:
	for item in components:
		var source:=terrain(item.id)
		if source==null or source.hydrology==null or not visible_component(item): continue
		var pose:=environment_pose*world_transform(item)
		if absf(pose.basis.determinant())<.000001: continue
		var result:=source.water_at(pose.affine_inverse()*world_point)
		if result.is_empty(): continue
		var local_surface: Vector3=result.surface; var bottom:=pose*Vector3(local_surface.x,float(result.bottom),local_surface.z)
		result["local_depth"]=result.depth; result["local_bottom"]=result.bottom; result.surface=pose*local_surface; result.depth=(result.surface as Vector3).distance_to(bottom); result.bottom=bottom.y; result["bottom_position"]=bottom; result["normal"]=(pose.basis*Vector3.UP).normalized(); result.flow=pose.basis*(result.flow as Vector3); result["terrain_id"]=item.id; result["physics"]=source.hydrology.water_physics; result["density"]=source.hydrology.water_density; result["drag"]=source.hydrology.water_drag; return result
	return {}
func component_kind(id: String) -> String: return str(component_settings.get(id,{}).get("kind","asset"))

func references_asset(path: String) -> bool:
	var normalized:=ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()
	var seen:={}
	for item in components:
		if item.parameters.get("module_linked",false) and _references(item.parameters.get("architecture_module_source",""),normalized,seen): return true
	return _references(component_settings,normalized,seen) or _references(environment_source,normalized,seen) or _references(atmosphere,normalized,seen)
static func _references(value: Variant,target: String,seen: Dictionary,depth: int=0) -> bool:
	if depth>16 or seen.size()>4096: return false
	if value is String or value is StringName:
		var path:=str(value)
		if path.is_empty() or not (path.is_absolute_path() or path.begins_with("res://") or path.begins_with("user://")): return false
		if ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()==target: return true
		if seen.has(path) or not path.get_extension().to_lower() in ["tres","res","mesh","material"] or not ResourceLoader.exists(path): return false
		seen[path]=true; return _references(ResourceLoader.load(path),target,seen,depth+1)
	if value is Array:
		for entry in value:
			if _references(entry,target,seen,depth+1): return true
	elif value is Dictionary:
		for entry in value.values():
			if _references(entry,target,seen,depth+1): return true
	elif value is Resource and not value is Script:
		var id: int=value.get_instance_id()
		if seen.has(id): return false
		seen[id]=true
		if _references(value.resource_path,target,seen,depth+1): return true
		for property in value.get_property_list():
			if (int(property.usage)&PROPERTY_USAGE_STORAGE)==0 or str(property.name) in ["script","code","text","title","label","resource_path"]: continue
			if _references(value.get(property.name),target,seen,depth+1): return true
	return false

func add_terrain(settings: KiwiEnvironmentTerrain=null) -> KiwiModelComponent:
	var item:=KiwiModelComponent.new(); item.id=ActorData.new_id(); item.title="Terrain"; var source:=settings if settings!=null else KiwiEnvironmentTerrain.new(); source.prepare(); item.mesh=source.editable_mesh(); components.append(item); component_settings[item.id]={"kind":"terrain","terrain":source,"collision":true}; return item

func add_group(name: String="Group") -> KiwiModelComponent:
	var item:=KiwiModelComponent.new(); item.id=ActorData.new_id(); item.title=name; components.append(item); component_settings[item.id]={"kind":"group"}; return item
