class_name KiwiTerrainGenerator
extends Resource
## Pure terrain-coordinate sampling. Authored landforms are ordered independently
## of sculpt edits; derived erosion, drainage and biome fields consume this base.
const PROFILES:=["Flat","Rolling Hills","Mountainous","Island","Archipelago","Desert","Canyon","Plateau","Coastal","Custom"]
const LANDFORMS:=["Mountain range","Mountain","Ridge","Valley","Canyon","Cliff","Plateau","Mesa","Hill","Basin","Crater","Dunes"]
@export var profile:=1
@export_enum("Simplex","Perlin","Ridged","Cellular","Domain warped") var noise_type:=0
@export var octaves:=4
@export var lacunarity:=2.
@export var gain:=.5
@export var medium_weight:=.3
@export var fine_weight:=.06
@export var warp_strength:=0.
@export var sharpness:=2.
@export var direction:=0.
@export var island_radius:=.8
@export var transition:=.25
@export var layers: Array[Dictionary]=[]
@export var foundation_edits:=PackedFloat32Array()
var _noise: Array[FastNoiseLite]=[]
var _warp: FastNoiseLite
var _key:=0
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","terrain_generation")
func validate() -> PackedStringArray: return _native().call("validate",self)
func signature() -> int: return _native().call("signature",self)
func prepare(seed: int,frequency: float) -> void: _native().call("prepare",self,seed,frequency)
func value(point: Vector2,dimensions: Vector2,amplitude: float,base_height: float) -> float:
	return _native().call("value",self,point,dimensions,amplitude,base_height)
func apply_foundations(heights: PackedFloat32Array,resolution: int,dimensions: Vector2,cancel: Callable=Callable()) -> PackedFloat32Array:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: PackedFloat32Array=_native().call("apply_foundations",self,heights,resolution,dimensions,state)
	state.clear()
	return result
static func mask(point: Vector2,settings: Dictionary) -> float: return _native().call("mask",point,settings)
static func _landform(point: Vector2,settings: Dictionary) -> float: return _native().call("landform",point,settings)
static func preset(index: int) -> KiwiTerrainGenerator: return _native().call("preset",index)
