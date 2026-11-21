class_name KiwiFluidSurface
extends RefCounted
## Sparse implicit surface, reconstructed with marching tetrahedra. The solver
## supplies world-space samples; no simulation particles are rendered as nodes.
const CORNERS := [Vector3i(0,0,0),Vector3i(1,0,0),Vector3i(1,1,0),Vector3i(0,1,0),Vector3i(0,0,1),Vector3i(1,0,1),Vector3i(1,1,1),Vector3i(0,1,1)]
const TETS := [[0,5,1,6],[0,1,2,6],[0,2,3,6],[0,3,7,6],[0,7,4,6],[0,4,5,6]]
static func build(points: PackedVector3Array, foam: PackedFloat32Array, values: Dictionary) -> Dictionary:
	return Engine.get_singleton("KiwiNativeServices").call("service","fluid_surface").build(points,foam,values)

