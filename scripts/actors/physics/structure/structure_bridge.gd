class_name KiwiStructureBridge
extends RefCounted
## Timeline-only XPBD rigid joints. Reaction estimates are artistic approximations,
## not engineering-certified stress/FEM. No parenting-derived constraints.
const MAX_ELEMENTS:=512
const MAX_LINKS:=1024
var nodes: Dictionary={}
var edges: Array[Dictionary]=[]
var islands: Dictionary={}
var graph_key:=0
var graph_builds:=0
var elapsed_usec:=0
var enabled:=false
var excluded: Dictionary={}
var excluded_time:=NAN
func reset() -> void:
	_native_structure().reset(self)

func exclusions(controller: KiwiTimelinePhysics,id: String,time: float) -> Array[String]:
	var result: Array[String]=[]
	result.assign(_native_structure().exclusions(self,controller,id,time))
	return result

func add_node(controller: KiwiTimelinePhysics,id: String,owner: String,state: Dictionary,config: Dictionary,role: int,bounds: AABB,mass: float,locked: bool=false) -> void:
	_native_structure().add_node(self,controller,id,owner,state,config,role,bounds,mass,locked)

func endpoint(owner: String,local: Vector3) -> Dictionary:
	return _native_structure().endpoint(self,owner,local)

func step(controller: KiwiTimelinePhysics,time: float,dt: float) -> void:
	_native_structure().step(self,controller,time,dt)

func rotate(node: Dictionary,delta: Vector3) -> void:
	_native_structure().rotate(node,delta)

func solve(edge: Dictionary,dt: float) -> void:
	_native_structure().solve(self,edge,dt)

func assess(controller: KiwiTimelinePhysics,edge: Dictionary,time: float,dt: float) -> void:
	_native_structure().assess(self,controller,edge,time,dt)

func update_islands(controller: KiwiTimelinePhysics) -> void:
	_native_structure().update_islands(self,controller)

static func _native_structure() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","structure_bridge")
