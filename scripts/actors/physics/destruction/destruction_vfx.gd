class_name KiwiDestructionVFX
extends RefCounted
## Render-only adapter from saved physical events to Godot particle draw meshes.
## Analytic event age replaces free-running GPU process time, so seeks/export FPS
## cannot change emission. No second physics or volumetric solver runs here.
const LIMIT:=8192
var nodes: Dictionary={}
var resources: Dictionary={}
var particle_count:=0
func reset() -> void:
	_native_vfx().reset(self)

static func rules(values: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	result.assign(_native_vfx().rules(values))
	return result

static func particles(event: Dictionary,rule: Dictionary,values: Dictionary,time: float,limit: int=512) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	result.assign(_native_vfx().particles(event,rule,values,time,limit))
	return result

func mesh(style: int) -> Mesh:
	return _native_vfx().mesh(self,style)

func apply(controller: KiwiTimelinePhysics,time: float) -> void:
	_native_vfx().apply(self,controller,time)


static func _native_vfx() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","destruction_vfx")
