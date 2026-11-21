extends RefCounted
## Local projection of integrated concentration toward the real sun.
## Bounded decal approximation; not native volume-to-surface shadows.
const Fog=preload("res://scripts/actors/fog/fog_actor.gd")
const Field=preload("res://scripts/actors/fog/fog_field.gd")
static func grid_sample(grid: Dictionary,unit: Vector3) -> float:
	return _native().grid_sample(grid,unit)

static func sample_density(world: Vector3,pose: Transform3D,size: Vector3,source: Dictionary,grid: Dictionary) -> float:
	return _native().sample_density(world,pose,size,source,grid)

static func interval(origin: Vector3,direction: Vector3,pose: Transform3D,size: Vector3) -> Vector2:
	return _native().interval(origin,direction,pose,size)

static func sync(runtime: Node,sun: DirectionalLight3D,scene_time: float,exact: bool=false) -> void:
	_native().sync(runtime,sun,scene_time,exact)

static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("fog_cloud_shadow")
