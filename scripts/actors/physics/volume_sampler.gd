class_name KiwiVolumeSampler
extends RefCounted
## Shared solver-independent interior sampling. Never return a partial fill.
const MAX_CELLS := 200000
const MAX_TRIANGLES := 100000
static func failure(message: String) -> Dictionary:
	return _native_volume().failure(message)

static func closed_mesh(geometry: Dictionary) -> Dictionary:
	return _native_volume().closed_mesh(geometry)

static func inside(mesh: TriangleMesh,point: Vector3,distance: float) -> bool:
	return _native_volume().inside(mesh,point,distance)

static func contains(point: Vector3,shape: int,size: Vector3,mesh: TriangleMesh,bounds: AABB) -> bool:
	return _native_volume().contains(point,shape,size,mesh,bounds)

static func generate(shape: int,size: Vector3,spacing: float,budget: int,pose: Transform3D,geometry: Dictionary={},jitter: float=0.0,seed: int=1) -> Dictionary:
	return _native_volume().generate(shape,size,spacing,budget,pose,geometry,jitter,seed)


static func _native_volume() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","volume_sampler")
