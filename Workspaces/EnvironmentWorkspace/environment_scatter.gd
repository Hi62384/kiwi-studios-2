class_name KiwiEnvironmentScatter
extends Resource
## Authored rules, not one model/component per generated instance.
@export var terrain_id:=""
@export var palette: Array[Dictionary]=[] # source path and relative weight
@export var region:=Rect2(-8,-8,16,16)
@export var density:=.25
@export var minimum_distance:=1.
@export var seed:=1
@export var scale_range:=Vector2(.8,1.2)
@export var yaw_range:=Vector2(-180,180)
@export var align_normal:=true
@export var height_range:=Vector2(-10000,10000)
@export var slope_range:=Vector2(0,60)
@export var budget:=10000
@export var paint_regions: Array[Vector3]=[] # local x, z, radius
@export var erase_regions: Array[Vector3]=[]
@export var exclude_polygons: Array[PackedVector2Array]=[] # terrain-local development / protected masks
@export var include_polygons: Array[PackedVector2Array]=[]
@export var exclusion_margin:=0.
@export var patch_scale:=0. # zero keeps the original uniform distribution
@export var patch_strength:=0.
@export var use_anchors:=false
@export var anchor_points: Array[Transform3D]=[] # same terrain-local frame as scatter
@export var anchor_ids:=PackedStringArray()
@export_enum("Terrain height","Offset from terrain","Authored anchor height") var anchor_height_mode:=0
@export var collisions:=false
@export var render_cluster_size:=0. # zero retains one batch per source mesh
@export var render_distance:=0. # zero retains unlimited rendering
@export var lod_enabled:=false
@export var lod_bias:=1.
@export var stream_instances:=false # camera-dependent instance buffers; source poses remain cached
@export var biome_ids:=PackedStringArray()
@export var minimum_biome_weight:=.05
@export var cluster_count:=0
@export var cluster_radius:=4.
@export var temperature_range:=Vector2(-10000,10000)
@export var humidity_range:=Vector2(0,1)
@export var shore_range:=Vector2(0,1000000)
@export var water_depth_range:=Vector2(0,1000000)
@export var overrides: Dictionary={} # stable candidate ID -> deleted / transform / palette
@export_enum("Terrain","Cave floor","Cave ceiling","Cave wall") var surface_domain:=0

static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_scatter")
func signature() -> int: return _native().call("signature",self)
func validate() -> PackedStringArray: return _native().call("validate",self)
func render_signature() -> int: return _native().call("render_signature",self)
func generate(terrain: KiwiEnvironmentTerrain,cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("generate",self,terrain,state)
	state.clear()
	return result
func _mask_index() -> Dictionary: return _native().call("mask_index",self)
func _unique_anchor_count() -> int: return _native().call("unique_anchor_count",self)
func _excluded(point: Vector2,index: Dictionary) -> bool: return _native().call("excluded",self,point,index)
func _cave_surface(terrain: KiwiEnvironmentTerrain,rng: RandomNumberGenerator,caves: Array[KiwiTerrainCave]) -> Dictionary:
	return _native().call("cave_surface",self,terrain,rng,caves)
static func _cave_distance(point: Vector3,caves: Array[KiwiTerrainCave]) -> float: return _native().call("cave_distance",point,caves)
