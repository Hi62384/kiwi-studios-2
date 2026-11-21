class_name KiwiFluidSolver
extends RefCounted
## Position-based density projection, Poly6 density and Spiky gradients (PBF).
## All time and collision queries are supplied by the shared timeline controller.
static func initialize(state: Dictionary,values: Dictionary,points: PackedVector3Array) -> void:
	_native_solver().initialize(state,values,points)

static func emit(state: Dictionary,values: Dictionary,pose: Transform3D,velocity: Vector3,local: float,dt: float) -> void:
	_native_solver().emit(state,values,pose,velocity,local,dt)

static func random(seed: int) -> float:
	return _native_solver().random(seed)

static func neighbors(points: PackedVector3Array,h: float) -> Dictionary:
	return _native_solver().neighbors(points,h)

static func kernel(distance_squared: float,h: float) -> float:
	return _native_solver().kernel(distance_squared,h)

static func gradient(delta: Vector3,h: float) -> Vector3:
	return _native_solver().gradient(delta,h)

static func step(state: Dictionary,values: Dictionary,gravity: Vector3,impulse: Vector3,dt: float,collide: Callable,compute: KiwiFluidCompute=null) -> void:
	_native_solver().step(state,values,gravity,impulse,dt,collide,compute)

static func _gpu_step(state: Dictionary,values: Dictionary,gravity: Vector3,impulse: Vector3,dt: float,collide: Callable,compute: KiwiFluidCompute) -> void:
	_native_solver().gpu_step(state,values,gravity,impulse,dt,collide,compute)

static func _native_solver() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","fluid_solver")

static func _invoke_collision(callback: Callable,from: Vector3,to: Vector3,radius: float,velocity: Vector3) -> Dictionary:
	return callback.call(from,to,radius,velocity)
