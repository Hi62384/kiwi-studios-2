class_name KiwiTerrainHydrology
extends Resource
## Shared height/drainage/water data. No independent fluid simulation or scene
## nodes: generated channel geometry and water regions consume the same terrain.
const DRY:=-1.0e20
const DIRECTIONS:=[Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1),Vector2i(1,-1),Vector2i(-1,1)]
@export var enabled:=true
@export var automatic_rivers:=true
@export var catchment_threshold:=20.
@export var river_width:=1.
@export var river_depth:=1.
@export var flow_speed:=1.
@export var rainfall:=1.
@export var rainfall_variation:=.2
@export var minimum_river_slope:=.002
@export var maximum_rivers:=64
@export var mesh_vertex_budget:=500000
@export var waterfall_drop:=2.
@export var automatic_lakes:=true
@export var lake_minimum_depth:=.4
@export var ocean_enabled:=false
@export var sea_level:=0.
@export var moisture_radius:=8.
@export var manual_rivers: Array[Dictionary]=[]
@export var manual_lakes: Array[Dictionary]=[]
@export var water_color:=Color(.12,.46,.8,.9)
@export var roughness:=.16
@export var wave_strength:=.03
@export var wave_scale:=1.
@export var wave_direction:=Vector2(.8,.3)
@export var material_asset:=""
@export var water_physics:=true
@export var water_density:=1000.
@export var water_drag:=1.
@export var foam_color:=Color(.94,.98,1.,1.)
@export var foam_amount:=.45
@export var waterfall_spray:=true
@export var spray_per_fall:=24
@export var spray_size:=.12
@export var spray_lifetime:=1.2
var _n:=0
var _dimensions:=Vector2.ONE
var _spacing:=Vector2.ONE
var _ground:=PackedFloat32Array()
var _vertices:=PackedVector3Array()
var _normals:=PackedVector3Array()
var _uv:=PackedVector2Array()
var _uv2:=PackedVector2Array()
var _colors:=PackedColorArray()
var _indices:=PackedInt32Array()
var _mesh_error:=""
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","terrain_hydrology")
static func _cancel_state(cancel: Callable) -> Dictionary: return {"enabled":cancel.is_valid(),"callback":cancel}
func geometry_signature() -> int: return _native().call("geometry_signature",self)
func signature() -> int: return _native().call("signature",self)
func validate() -> PackedStringArray: return _native().call("validate",self)
func generate(source: PackedFloat32Array,n: int,dimensions: Vector2,seed: int,cancel: Callable=Callable()) -> Dictionary:
	var state:=_cancel_state(cancel)
	var result: Dictionary=_native().call("generate",self,source,n,dimensions,seed,state)
	state.clear()
	return result
func _point(index: int) -> Vector3: return _native().call("point",self,index)
func _cell(point: Vector2) -> int: return _native().call("cell",self,point)
func _sample(values: PackedFloat32Array,point: Vector2) -> float: return _native().call("sample",self,values,point)
static func _push(heap: Array[Vector2],item: Vector2) -> void: _native().call("push",heap,item)
static func _pop(heap: Array[Vector2]) -> Vector2: return _native().call("pop",heap)
func _flood_water(seeds: PackedInt32Array,level: float,ground: PackedFloat32Array,levels: PackedFloat32Array,kinds: PackedByteArray,kind: int,cancel: Callable) -> void:
	var state:=_cancel_state(cancel)
	var result: Dictionary=_native().call("flood_water",self,seeds,level,ground,levels,kinds,kind,state)
	state.clear()
	for index in levels.size(): levels[index]=result.levels[index]; kinds[index]=result.kinds[index]
func _rivers(source: PackedFloat32Array,filled: PackedFloat32Array,downstream: PackedInt32Array,accumulation: PackedFloat32Array,levels: PackedFloat32Array,cancel: Callable) -> Array[Dictionary]:
	var state:=_cancel_state(cancel)
	var result: Array[Dictionary]=[]
	result.assign(_native().call("rivers",self,source,filled,downstream,accumulation,levels,state))
	state.clear()
	return result
func _carve(path: Dictionary,source: PackedFloat32Array,delta: PackedFloat32Array,levels: PackedFloat32Array,flow: PackedVector2Array,waterfalls: Array[Dictionary]) -> void:
	var result: Dictionary=_native().call("carve",self,path,source,delta,levels,flow,waterfalls)
	for index in delta.size(): delta[index]=result.delta[index]; levels[index]=result.levels[index]; flow[index]=result.flow[index]
func _distance(wet: PackedByteArray,to_water: bool,cancel: Callable) -> PackedFloat32Array:
	var state:=_cancel_state(cancel)
	var result: PackedFloat32Array=_native().call("distance",self,wet,to_water,state)
	state.clear()
	return result
func _build_water(paths: Array[Dictionary],ground: PackedFloat32Array,levels: PackedFloat32Array,kinds: PackedByteArray,cancel: Callable) -> void:
	var state:=_cancel_state(cancel)
	_native().call("build_water",self,paths,ground,levels,kinds,state)
	state.clear()
static func _clip(polygon: Array[Vector3],level: float) -> Array[Vector3]:
	var result: Array[Vector3]=[]
	result.assign(Array(_native().call("clip",PackedVector3Array(polygon),level)))
	return result
