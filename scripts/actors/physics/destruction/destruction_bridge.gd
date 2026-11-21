class_name KiwiDestructionBridge
extends RefCounted
## Extends the existing timeline/query world. Geometry is immutable and cached;
## only fragment transforms/velocities live in checkpoint state.
var cache: Dictionary={}
var nodes: Dictionary={}
var collider_keys: Dictionary={}
var builds:=0
var elapsed_usec:=0
var interiors: Dictionary={}
var sources: Dictionary={}
var cache_bytes:=0
func reset(keep_prepared: bool=false) -> void:
	_native_bridge().reset(self,keep_prepared)

func source(controller: KiwiTimelinePhysics,id: String,state: Dictionary) -> Dictionary:
	return _native_bridge().source(self,controller,id,state)

func synchronize(controller: KiwiTimelinePhysics,time: float) -> void:
	_native_bridge().synchronize(self,controller,time)

func prepare(controller: KiwiTimelinePhysics,id: String,state: Dictionary,values: Dictionary,ops: Dictionary) -> Dictionary:
	return _native_bridge().prepare(self,controller,id,state,values,ops)

func mass(controller: KiwiTimelinePhysics,id: String,state: Dictionary,values: Dictionary,fallback: float) -> float:
	return _native_bridge().mass(self,controller,id,state,values,fallback)

func step(controller: KiwiTimelinePhysics,time: float,dt: float) -> void:
	_native_bridge().step(self,controller,time,dt)

func sync_actor_world(controller: KiwiTimelinePhysics,id: String,state: Dictionary,time: float) -> void:
	_native_bridge().sync_actor_world(self,controller,id,state,time)

func apply(controller: KiwiTimelinePhysics,time: float) -> void:
	_native_bridge().apply(self,controller,time)

func hide() -> void:
	_native_bridge().hide(self)

static func interpolate(result: Dictionary,left: Dictionary,right: Dictionary,fraction: float) -> void:
	_native_bridge().interpolate(result,left,right,fraction)


static func _native_bridge() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","destruction_bridge")
