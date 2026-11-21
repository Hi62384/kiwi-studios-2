class_name KiwiRigWeighting
extends RefCounted
const MAX_VERTICES := 100000
const MAX_PAIRS := 3000000
## Independent CPU algorithms. No scene nodes or rendering resources are changed.
const GeometryNative=preload("res://Workspaces/ModelWorkspace/rig/RigGeometry.cs")
static func geometry(source: Mesh, transform: Transform3D) -> Dictionary:
	return GeometryNative.new().geometry(source,transform)

const WeightingNative=preload("res://Workspaces/ModelWorkspace/rig/RigWeighting.cs")
static func compute(source: Mesh, bones: Array, transform: Transform3D, method: String="Smooth", count: int=4, iterations: int=8, cancellation: RefCounted=null) -> KiwiRigBinding:
	return WeightingNative.new().compute(source,bones,transform,method,count,iterations,cancellation)

static func corrected(binding: KiwiRigBinding, surface: int, vertex: int, bone: int, mode: String, amount: float, neighbor_values: Dictionary={}) -> Dictionary:
	return WeightingNative.new().corrected(binding,surface,vertex,bone,mode,amount,neighbor_values)
