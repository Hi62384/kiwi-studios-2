class_name KiwiGrowthPhysics
extends RefCounted
## Typed API retained while timeline controller and actor schemas migrate.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","growth_physics")
static func data(actor: ActorData) -> KiwiSurfaceGrowthData: return _native().call("data",actor)
static func points(controller: KiwiTimelinePhysics,id: String,time: float) -> PackedVector3Array: return _native().call("points",controller,id,time)
static func world(controller: KiwiTimelinePhysics,id: String,time: float) -> Transform3D: return _native().call("world",controller,id,time)
static func initialize(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,time: float) -> void: _native().call("initialize",controller,id,state,config,time)
static func targets(controller: KiwiTimelinePhysics,id: String,time: float) -> Dictionary: return _native().call("targets",controller,id,time)
static func pins(controller: KiwiTimelinePhysics,id: String,time: float) -> Dictionary: return _native().call("pins",controller,id,time)
static func apply(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,time: float) -> void: _native().call("apply",controller,id,state,config,time)
