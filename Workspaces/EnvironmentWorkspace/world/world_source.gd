extends Resource
## Authored world coordinates are meters in the owning group's local space.
@export var world_id:=ActorData.new_id()
@export var seed:=1
@export var dimensions:=Vector2(256.,256.)
@export var region_size:=128.
@export var terrain_id:=""
@export var owned_terrain_id:=""
@export var regions: Array[Dictionary]=[]
@export var nodes: Dictionary={}
@export var roads: Array[Dictionary]=[]
@export var settlements: Array[Dictionary]=[]
@export var connect_settlements:=true
@export var connection_bridges:=true
@export var connection_road_type:="Rural Road"
@export var connection_overrides: Dictionary={}
@export var forests: Array[Dictionary]=[]
@export var prop_rules: Array[Dictionary]=[]
@export var exclusions: Array[Dictionary]=[]
@export var occupied: Array[Dictionary]=[] # captured native object footprints in world-local XZ
@export var respect_existing_objects:=true
@export var auto_update_dependencies:=true
@export var plot_overrides: Dictionary={}
@export var render_distance:=1000.
@export var max_building_plots:=4096
@export var eager_building_limit:=128
@export var building_detail_distance:=180.
@export var max_active_buildings:=64
@export var building_cache_mb:=128
@export var road_material: Material
@export var shoulder_material: Material
@export var road_materials: Dictionary={}
@export var terrain_dependency_key:=0
var terrain_field: RefCounted
func copy() -> Resource:
	var result: Resource=get_script().new()
	for field in ["world_id","seed","dimensions","region_size","terrain_id","owned_terrain_id","regions","nodes","roads","settlements","connect_settlements","connection_bridges","connection_road_type","connection_overrides","forests","prop_rules","exclusions","occupied","respect_existing_objects","auto_update_dependencies","plot_overrides","render_distance","max_building_plots","eager_building_limit","building_detail_distance","max_active_buildings","building_cache_mb","road_material","shoulder_material","road_materials","terrain_dependency_key"]:
		var value: Variant=get(field); result.set(field,value.duplicate(true) if value is Dictionary or value is Array else value)
	result.terrain_field=terrain_field
	return result
func configure_regions() -> void:
	var previous: Dictionary={}
	for region in regions: previous[str(region.id)]=region
	regions=[]; var count:=Vector2i((dimensions/region_size).ceil())
	for z in count.y:
		for x in count.x:
			var id:="%s:region:%d:%d"%[world_id,x,z]; var start:=Vector2(x,z)*region_size-dimensions*.5
			var region: Dictionary=previous.get(id,{"id":id,"name":"Region %d · %d"%[x+1,z+1],"enabled":true,"locked":false,"seed":hash([seed,id])}).duplicate(true); region.cell=Vector2i(x,z); region.bounds=Rect2(start,Vector2.ONE*region_size).intersection(Rect2(-dimensions*.5,dimensions)); regions.append(region)
func validate() -> PackedStringArray:
	var errors:=PackedStringArray(); var seen: Dictionary={}
	if not is_finite(render_distance) or render_distance<0. or render_distance>100000.: errors.append("World render distance must be between zero and 100000 meters.")
	if max_building_plots<1 or max_building_plots>8192 or eager_building_limit<0 or eager_building_limit>512 or max_active_buildings<1 or max_active_buildings>512 or building_cache_mb<16 or building_cache_mb>1024: errors.append("World plot, active-building and cache budgets are outside their supported ranges.")
	if not is_finite(building_detail_distance) or building_detail_distance<10. or building_detail_distance>10000.: errors.append("Building detail distance must be between 10 and 10000 meters.")
	if not dimensions.is_finite() or dimensions.x<16. or dimensions.y<16. or dimensions.x>16384. or dimensions.y>16384.: errors.append("World dimensions must be between 16 and 16384 meters.")
	if not is_finite(region_size) or region_size<16. or region_size>4096.: errors.append("Region size must be between 16 and 4096 meters.")
	if regions.size()>4096 or roads.size()>2048 or nodes.size()>4096: errors.append("This world exceeds its editable region or road graph budget.")
	for region in regions:
		var id:=str(region.get("id","")); var bounds: Rect2=region.get("bounds",Rect2())
		if id.is_empty() or seen.has(id) or not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x<=0. or bounds.size.y<=0.: errors.append("World regions need unique IDs and positive finite bounds.")
		seen[id]=true
	for id in nodes:
		if not nodes[id] is Vector3 or not (nodes[id] as Vector3).is_finite(): errors.append("Road nodes need finite 3D positions.")
	seen.clear()
	for road in roads:
		errors.append_array(preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").validate(road))
		var id:=str(road.get("id","")); var width:=float(road.get("width",6.)); var points: PackedVector3Array=road.get("points",PackedVector3Array())
		if id.is_empty() or seen.has(id) or not nodes.has(str(road.get("from",""))) or not nodes.has(str(road.get("to",""))): errors.append("Each road needs a unique ID and existing endpoint nodes.")
		seen[id]=true
		if not is_finite(width) or width<.5 or width>40. or points.size()<2 or points.size()>512: errors.append("Road width or control-point count is outside the supported range.")
		if str(road.get("mode","Ground")) not in ["Ground","Bridge","Tunnel"]: errors.append("Choose Ground, Bridge or Tunnel for road crossings.")
		if nodes.has(str(road.get("from",""))) and nodes.has(str(road.get("to",""))) and (nodes[road.from] as Vector3).distance_to(nodes[road.to])<.1: errors.append("Road endpoints must be distinct and at least 0.1 meters apart.")
		for point in points:
			if not point.is_finite(): errors.append("Road control points must be finite.")
	seen.clear()
	if settlements.size()>8: errors.append("Generate at most eight settlements in one editable world source.")
	if connection_road_type not in preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").TYPES: errors.append("Choose a supported settlement-connection road type.")
	for settlement: Dictionary in settlements:
		errors.append_array(preload("res://Workspaces/EnvironmentWorkspace/world/world_districts.gd").validate(settlement))
		if settlement.has("road_type") and settlement.road_type not in preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").TYPES: errors.append("Choose a supported settlement road type.")
		var id:=str(settlement.get("id","")); var center: Vector3=settlement.get("center",Vector3.ZERO); var radius:=float(settlement.get("radius",48.))
		if id.is_empty() or seen.has(id) or not center.is_finite() or not is_finite(radius) or radius<8. or radius>512.: errors.append("Settlements need unique IDs, finite centers and a radius from 8 to 512 meters.")
		seen[id]=true
		if str(settlement.get("profile","Town")) not in ["Town","Village","City"]: errors.append("Choose a supported town, village or city profile.")
		if str(settlement.get("layout_mode","Grid")) not in ["Grid","Road network"]: errors.append("Choose a grid layout or blocks from the road network.")
	if forests.size()>16: errors.append("A world supports up to sixteen editable forest sources.")
	seen.clear()
	for forest: Dictionary in forests:
		var id:=str(forest.get("id","")); var bounds: Rect2=forest.get("bounds",Rect2()); var density:=float(forest.get("density",1.))
		if id.is_empty() or seen.has(id) or not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x<=0. or bounds.size.y<=0.: errors.append("Forests need unique IDs and positive finite bounds.")
		seen[id]=true
		if not is_finite(density) or density<0. or density>4.: errors.append("Forest density must be between zero and four.")
		if forest.get("profile","") not in preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd").PROFILES: errors.append("Choose a supported forest profile.")
	if prop_rules.size()>32: errors.append("A world supports up to thirty-two editable object-placement rules.")
	seen.clear()
	for rule: Dictionary in prop_rules:
		var id:=str(rule.get("id","")); var spacing:=float(rule.get("spacing",12.)); var bounds: Rect2=rule.get("bounds",Rect2())
		if id.is_empty() or seen.has(id) or not is_finite(spacing) or spacing<.5 or spacing>1000.: errors.append("Placement rules need unique IDs and spacing between 0.5 and 1000 meters.")
		seen[id]=true
		if str(rule.get("mode","")) not in ["Roadside","Region","Clusters","Grid","Anchors"] or not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.x<=0. or bounds.size.y<=0.: errors.append("Choose a supported placement mode and positive finite region.")
		var model: Variant=rule.get("model","")
		var path: bool=(model is String or model is StringName) and not str(model).is_empty()
		if model is KiwiEnvironmentDocument or not (model is KiwiModelDocument or path): errors.append("Choose a reusable model for object placement.")
	return errors
func signature() -> int:
	return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").value([world_id,seed,dimensions,region_size,terrain_id,owned_terrain_id,regions,nodes,roads,settlements,connect_settlements,connection_bridges,connection_road_type,connection_overrides,forests,prop_rules,exclusions,occupied,respect_existing_objects,auto_update_dependencies,plot_overrides,render_distance,max_building_plots,eager_building_limit,building_detail_distance,max_active_buildings,building_cache_mb,road_material,shoulder_material,road_materials,terrain_dependency_key])
func development_signature() -> int:
	return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").value([world_id,seed,dimensions,region_size,terrain_id,owned_terrain_id,regions,nodes,roads,settlements,connect_settlements,connection_bridges,connection_road_type,connection_overrides,exclusions,occupied,respect_existing_objects,plot_overrides,max_building_plots,eager_building_limit,render_distance,road_material,shoulder_material,road_materials,terrain_dependency_key])
func geometry_signature() -> int:
	return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").value([world_id,seed,dimensions,region_size,terrain_id,owned_terrain_id,regions,nodes,roads,settlements,connect_settlements,connection_bridges,connection_road_type,connection_overrides,forests,prop_rules,exclusions,occupied,respect_existing_objects,plot_overrides,max_building_plots,eager_building_limit,terrain_dependency_key])
func region_at(point: Vector2) -> String:
	for region in regions:
		if (region.bounds as Rect2).has_point(point): return str(region.id)
	return ""
