class_name KiwiTerrainErosion
extends Resource
## Conservative grid transport. Geometry, suspended sediment and derived flow
## are real CPU fields; this operation never substitutes a shader for erosion.
@export var operation_id:=ActorData.new_id()
@export var enabled:=true
@export_enum("Hydraulic","Thermal") var mode:=0
@export var iterations:=40
@export var rainfall:=.02
@export var strength:=.25
@export var sediment_capacity:=4.
@export var deposition_rate:=.25
@export var evaporation:=.08
@export var flow_rate:=.5
@export var minimum_slope:=.01
@export var talus_angle:=35.
@export var mobility:=.5
@export var seed:=1
@export var mask: Dictionary={}
const DIRECTIONS:=[Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]
func signature() -> int: return preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_data_hash.gd").value([operation_id,enabled,mode,iterations,rainfall,strength,sediment_capacity,deposition_rate,evaporation,flow_rate,minimum_slope,talus_angle,mobility,seed,mask])
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","terrain_erosion")
static func _cancel_requested(state: Dictionary) -> bool:
	var callback: Callable=state.get("callback",Callable())
	return callback.is_valid() and callback.call()
func apply(source: PackedFloat32Array,n: int,dimensions: Vector2,cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("apply",self,source,n,dimensions,state)
	state.clear()
	return result
func _thermal(heights: PackedFloat32Array,n: int,spacing: Vector2,weights: PackedFloat32Array,eroded: PackedFloat32Array,deposited: PackedFloat32Array) -> void:
	var result: Dictionary=_native().call("thermal",self,heights,n,spacing,weights,eroded,deposited)
	for index in heights.size():
		heights[index]=result.heights[index]; eroded[index]=result.erosion[index]; deposited[index]=result.deposition[index]
