class_name KiwiPowderFluid
extends RefCounted
## Kernel-sampled drag/buoyancy and mass-weighted, two-way positional exclusion.
## Fluid keeps its own PBF solver. No pressure constraint is applied to grains.
static func fluids(controller: KiwiTimelinePhysics,batch: Dictionary,time: float) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	result.assign(_native_fluid().fluids(controller,batch,time))
	return result

static func near(fluid: Dictionary,point: Vector3) -> PackedInt32Array:
	return _native_fluid().near(fluid,point)

static func forces(controller: KiwiTimelinePhysics,batches: Array[Dictionary],time: float) -> void:
	_native_fluid().forces(controller,batches,time)

static func contacts(controller: KiwiTimelinePhysics,batches: Array[Dictionary],time: float) -> void:
	_native_fluid().contacts(controller,batches,time)


static func _native_fluid() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","powder_fluid")
