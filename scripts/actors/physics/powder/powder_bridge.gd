class_name KiwiPowderBridge
extends RefCounted
## Timeline adapter. Future granular solver consumes the packed state after emission.
var volumes: Dictionary={}
var generation_count:=0
var solver:=KiwiPowderSolver.new()
var reactions: Dictionary={}
func reset() -> void:
	_native_powder().reset(self)

static func values(controller: KiwiTimelinePhysics,id: String,time: float) -> Dictionary:
	return _native_powder().values(controller,id,time)

static func source(controller: KiwiTimelinePhysics,id: String,config: Dictionary,time: float) -> Transform3D:
	return _native_powder().source(controller,id,config,time)

func initialize(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,time: float) -> void:
	_native_powder().initialize(self,controller,id,state,config,time)

func step(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,time: float,dt: float) -> void:
	_native_powder().step(self,controller,id,state,config,time,dt)

func simulate(controller: KiwiTimelinePhysics,steps: Dictionary,time: float,dt: float,old_poses: Dictionary) -> void:
	_native_powder().simulate(self,controller,steps,time,dt,old_poses)

static func _native_powder() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","powder_bridge")
