class_name KiwiFluidVolume
extends RefCounted
## Liquids and powder share geometric containment, never solver state.
static func generate(values: Dictionary,pose: Transform3D,geometry: Dictionary={}) -> Dictionary:
	var spacing: float=values.spacing
	var size: Vector3=values.get(&"fluid_dimensions",Vector3.ONE)
	return KiwiVolumeSampler.generate(int(values.get(&"fluid_shape",0)),size.abs().max(Vector3.ONE*spacing),spacing,int(values.budget),pose,geometry)
static func inside(mesh: TriangleMesh,point: Vector3,distance: float) -> bool:
	return KiwiVolumeSampler.inside(mesh,point,distance)
