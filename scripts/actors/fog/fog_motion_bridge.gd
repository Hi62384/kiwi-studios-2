extends RefCounted
## Timeline adapter. Authoring resources are never mutated by the solver.
const Solver=preload("res://scripts/actors/fog/fog_transport_solver.gd")
const Definition=preload("res://scripts/actors/fog/fog_motion_definition.gd")
const Field=preload("res://scripts/actors/fog/fog_field.gd")
const ActorFog=preload("res://scripts/actors/fog/fog_actor.gd")
const Render=preload("res://scripts/actors/fog/fog_motion_render.gd")

static func values(controller: RefCounted,id: String,time: float) -> Dictionary:
	return _native().values(controller,id,time)

static func initialize(controller: RefCounted,id: String,state: Dictionary,_config: Dictionary,time: float) -> void:
	_native().initialize(controller,id,state,_config,time)

static func mask_value(source: Dictionary,unit: Vector3,world: Vector3) -> float:
	return _native().mask_value(source,unit,world)

static func source_pose(controller: RefCounted,id: String,v: Dictionary,time: float) -> Transform3D:
	return _native().source_pose(controller,id,v,time)

static func emit_sources(controller: RefCounted,id: String,state: Dictionary,v: Dictionary,time: float,dt: float) -> void:
	_native().emit_sources(controller,id,state,v,time,dt)

static func contains(shape: Shape3D,p: Vector3,padding: Vector3) -> bool:
	return _native().contains(shape,p,padding)

static func bounds(shape: Shape3D) -> AABB:
	return _native().bounds(shape)

static func obstacles(controller: RefCounted,id: String,state: Dictionary,v: Dictionary,dt: float) -> void:
	_native().obstacles(controller,id,state,v,dt)

static func step(controller: RefCounted,id: String,state: Dictionary,config: Dictionary,time: float,dt: float) -> void:
	_native().step(controller,id,state,config,time,dt)

static func apply(controller: RefCounted,id: String,state: Dictionary,time: float) -> void:
	_native().apply(controller,id,state,time)

static func interpolate(result: Dictionary,left: Dictionary,right: Dictionary,fraction: float) -> void:
	_native().interpolate(result,left,right,fraction)

static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_motion_bridge")
