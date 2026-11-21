class_name KiwiPhysicsGeometry
extends RefCounted
const MAX_RENDER_VERTICES := 30000
static func primitive(runtime: ActorRuntime, values: Dictionary) -> PrimitiveMesh:
	return _native_geometry().primitive(runtime,values)

static func meshes(runtime: Node, physics_ids: Dictionary) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D]=[]
	result.assign(_native_geometry().meshes(runtime,physics_ids))
	return result

static func capture(runtime: ActorRuntime, physics_ids: Dictionary) -> Dictionary:
	return _native_geometry().capture(runtime,physics_ids)

static func prepare_collision(geometry: Dictionary) -> Dictionary:
	return _native_geometry().prepare_collision(geometry)

static func collider(geometry: Dictionary, settings: Dictionary) -> Dictionary:
	return _native_geometry().collider(geometry,settings)

static func particles(geometry: Dictionary, count: int, pose: Transform3D) -> Dictionary:
	return _native_geometry().particles(geometry,count,pose)

static func deform(data: Dictionary, points: PackedVector3Array, influence: float) -> void:
	_native_geometry().deform(data,points,influence)

static func rope_mesh(points: PackedVector3Array, inverse: Transform3D, radius: float, material: Material) -> ArrayMesh:
	return _native_geometry().rope_mesh(points,inverse,radius,material)

static func _native_geometry() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","physics_geometry")
