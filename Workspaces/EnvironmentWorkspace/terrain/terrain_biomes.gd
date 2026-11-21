class_name KiwiTerrainBiomes
extends Resource
## Continuous environmental fields and normalized suitability, never interpolated
## categorical IDs. The climate stage consumes completed ground and water data.
const NAMES:=["Grassland","Forest","Desert","Tropical","Jungle","Savanna","Swamp","Snow / tundra","Alpine","Rocky mountains","Badlands","Volcanic","Coastal beach","Rocky coast"]
const FORMAT_VERSION:=4
const CAVE_NAMES:=["Dry cave","Damp cave","Flooded cave","Cold cave","Limestone cave","Volcanic cave"]
@export var definitions: Array[Dictionary]=[]
@export var fallback_id:="grassland"
@export var cave_fallback_id:="cave_dry"
@export var sea_temperature:=24.
@export var latitude_range:=Vector2(-30,30)
@export var altitude_lapse:=.0065
@export var base_humidity:=.45
@export var climate_region_size:=100.
@export var paint_masks: Dictionary={}
class BaseField extends Resource:
	var resolution: int
	var dimensions: Vector2
	var water_data: Dictionary={}
	var geology:=0
	var values: PackedFloat32Array
	func height(x: int,z: int) -> float: return KiwiTerrainBiomes._native().call("base_height",self,x,z)
	func position(x: int,z: int) -> Vector3: return KiwiTerrainBiomes._native().call("base_position",self,x,z)
	func normal(x: int,z: int) -> Vector3: return KiwiTerrainBiomes._native().call("base_normal",self,x,z)
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","terrain_biomes")
func landform_signature() -> int: return _native().call("landform_signature",self)
func apply_landforms(heights: PackedFloat32Array,n: int,dimensions: Vector2,seed: int,cancel: Callable=Callable(),geology: int=0) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("apply_landforms",self,heights,n,dimensions,seed,state,geology)
	state.clear()
	return result
func signature() -> int: return _native().call("signature",self)
func climate_signature() -> int: return _native().call("climate_signature",self)
static func starter(index: int) -> Dictionary: return _native().call("starter",index)
static func cave_starter(index: int) -> Dictionary: return _native().call("cave_starter",index)
func validate() -> PackedStringArray: return _native().call("validate",self)
func generate(terrain: Resource,seed: int,cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("generate",self,terrain,seed,state)
	state.clear()
	return result
func noise_fields(seed: int,domain: String="surface") -> Dictionary: return _native().call("noise_fields",self,seed,domain)
func _weights_sample(point: Vector2,elevation: float,slope: float,temperature: float,humidity: float,shore: float,roughness: float,index: int,n: int,noises: Dictionary,features: Dictionary={}) -> Dictionary:
	return _native().call("weights_sample",self,point,elevation,slope,temperature,humidity,shore,roughness,index,n,noises,features)
func refresh_samples(terrain: Resource,indices: Array,noises: Dictionary) -> void: _native().call("refresh_samples",self,terrain,indices,noises)
func has_cave_rules() -> bool: return _native().call("has_cave_rules",self)
static func _range(value: float,limits: Vector2,transition: float) -> float: return _native().call("range",value,limits,transition)
static func _mask_at(mask: PackedFloat32Array,x: int,z: int,n: int) -> float: return _native().call("mask_at",mask,x,z,n)
