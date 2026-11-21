extends RefCounted
## CPU reference transport. Concentration uses conservative face fluxes; velocity
## uses advection/forces/projection. No renderer nodes, clocks or undo operations.
const MAX_RESOLUTION:=32
static var grids: Dictionary={}

static func grid(n: int) -> Dictionary:
	return _native().grid(n)

static func initialize(n: int,size: Vector3,density: PackedFloat32Array=PackedFloat32Array()) -> Dictionary:
	return _native().initialize(n,size,density)

static func total_mass(state: Dictionary) -> float:
	return _native().total_mass(state)

static func set_obstacles(state: Dictionary,solid: PackedByteArray,boundary_velocity: PackedVector3Array) -> void:
	_native().set_obstacles(state,solid,boundary_velocity)

static func inject(state: Dictionary,cells: PackedInt32Array,weights: PackedFloat32Array,mass: float,velocity: Vector3) -> void:
	_native().inject(state,cells,weights,mass,velocity)

static func velocity_sample(velocities: PackedVector3Array,solid: PackedByteArray,point: Vector3,size: Vector3,n: int) -> Vector3:
	return _native().velocity_sample(velocities,solid,point,size,n)

static func field_acceleration(fields: Array,point: Vector3,time: float) -> Vector3:
	return _native().field_acceleration(fields,point,time)

static func step(state: Dictionary,config: Dictionary,dt: float) -> void:
	_native().step(state,config,dt)

static func substep_state(state: Dictionary,config: Dictionary,dt: float) -> void:
	_native().substep_state(state,config,dt)

static func project(v: PackedVector3Array,solid: PackedByteArray,boundary: PackedVector3Array,neighbors: PackedInt32Array,h: Vector3,dt: float,iterations: int,closed: bool,state: Dictionary) -> PackedVector3Array:
	return _native().project(v,solid,boundary,neighbors,h,dt,iterations,closed,state)

static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_transport")
