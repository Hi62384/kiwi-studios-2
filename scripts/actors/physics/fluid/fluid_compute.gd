class_name KiwiFluidCompute
extends RefCounted
var device: RenderingDevice
var shader:=RID()
var pipeline:=RID()
var buffers: Array[RID]=[]
var uniforms:=RID()
var capacity:=-1
var error:=""
func _init() -> void:
	_native_compute().initialize(self)

func available() -> bool:
	return _native_compute().available(self)

func dispose() -> void:
	_native_compute().dispose(self)

func _allocate(n: int) -> void:
	_native_compute().allocate(self,n)

func project(state: Dictionary,settings: Dictionary,gravity: Vector3,dt: float) -> void:
	_native_compute().project(self,state,settings,gravity,dt)


static func _native_compute() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","fluid_compute")
