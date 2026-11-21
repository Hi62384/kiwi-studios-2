class_name KiwiFluidVolume
extends RefCounted
## Liquids and powder share geometric containment, never solver state.
static func generate(values: Dictionary,pose: Transform3D,geometry: Dictionary={}) -> Dictionary:
	return _native_volume().generate(values,pose,geometry)

static func inside(mesh: TriangleMesh,point: Vector3,distance: float) -> bool:
	return _native_volume().inside(mesh,point,distance)


static func _native_volume() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","fluid_volume")
