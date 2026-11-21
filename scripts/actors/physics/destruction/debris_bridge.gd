class_name KiwiDebrisBridge
extends RefCounted
var bodies: Dictionary={}
var renderers: Dictionary={}
var meshes: Dictionary={}
var elapsed_usec:=0
func reset() -> void:
	_native_debris().reset(self)

func refresh(controller: KiwiTimelinePhysics,time: float) -> void:
	_native_debris().refresh(self,controller,time)

func lookup(controller: KiwiTimelinePhysics,id: String) -> Dictionary:
	return _native_debris().lookup(self,controller,id)

func settings(controller: KiwiTimelinePhysics,id: String,time: float) -> Dictionary:
	return _native_debris().settings(self,controller,id,time)

func emit(controller: KiwiTimelinePhysics,owner: String,source: String,kind: String,time: float,point: Vector3,normal: Vector3,velocity: Vector3,energy: float) -> void:
	_native_debris().emit(self,controller,owner,source,kind,time,point,normal,velocity,energy)

func step(controller: KiwiTimelinePhysics,time: float,dt: float) -> void:
	_native_debris().step(self,controller,time,dt)

func secondary(controller: KiwiTimelinePhysics,entry: Dictionary,parent: Dictionary,hit: Dictionary,energy: float,time: float) -> Array:
	return _native_debris().secondary(self,controller,entry,parent,hit,energy,time)


static func _native_debris() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","debris_bridge")
