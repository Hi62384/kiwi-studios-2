class_name KiwiFluidBridge
extends RefCounted
## Boundary adapter; fluid remains independent of actor/editor nodes.
var proxies:=KiwiPhysicsCollisionWorld.new()
var proxy_owners:={}
var compute: KiwiFluidCompute
var environment_documents: Dictionary={}
var environment_water: Array[Dictionary]=[]
func reset() -> void:
	_native_fluid().reset(self)

func ensure_compute() -> void:
	_native_fluid().ensure_compute(self)

func prepare_environment(controller: KiwiTimelinePhysics,time: float) -> void:
	_native_fluid().prepare_environment(self,controller,time)

func environment_at(point: Vector3) -> Dictionary:
	return _native_fluid().environment_at(self,point)

func rigid_water_acceleration(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,h: float) -> Vector3:
	return _native_fluid().rigid_water_acceleration(self,controller,id,state,config,h)

static func values(controller: KiwiTimelinePhysics,id: String,time: float) -> Dictionary:
	return _native_fluid().values(controller,id,time)

static func source(controller: KiwiTimelinePhysics,id: String,config: Dictionary,time: float) -> Transform3D:
	return _native_fluid().source(controller,id,config,time)

static func initialize(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,time: float) -> void:
	_native_fluid().initialize(controller,id,state,config,time)

func update_proxies(controller: KiwiTimelinePhysics,time: float) -> void:
	_native_fluid().update_proxies(self,controller,time)

func _proxy(key: String,owner: String,pose: Transform3D,radius: float,layer: int=1,mask: int=1) -> void:
	_native_fluid().proxy(self,key,owner,pose,radius,layer,mask)

func step(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,time: float,dt: float) -> void:
	_native_fluid().step(self,controller,id,state,config,time,dt)

static func _native_fluid() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","fluid_bridge")
