class_name KiwiModelGeometry
extends RefCounted
## Operations return fresh topology, keeping document snapshots immutable.
static func remove_faces(mesh: KiwiModelMesh,selected: PackedInt32Array) -> KiwiModelMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_geometry").remove_faces(mesh,selected)

static func compact(mesh: KiwiModelMesh) -> KiwiModelMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_geometry").compact(mesh)

static func extrude(mesh: KiwiModelMesh,selected: PackedInt32Array,distance: float,individual: bool=false) -> Dictionary:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_geometry").extrude(mesh,selected,distance,individual)

static func inset(mesh: KiwiModelMesh,selected: PackedInt32Array,width: float) -> Dictionary:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_geometry").inset(mesh,selected,width)

static func subdivide(mesh: KiwiModelMesh,selected: PackedInt32Array=PackedInt32Array()) -> KiwiModelMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_geometry").subdivide(mesh,selected)

static func subdivide_edges(mesh: KiwiModelMesh,selected: PackedInt32Array) -> KiwiModelMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_geometry").subdivide_edges(mesh,selected)

static func smooth_mesh(mesh: KiwiModelMesh,strength: float=.5,iterations: int=1) -> KiwiModelMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_geometry").smooth_mesh(mesh,strength,iterations)

static func clip_plane(mesh: KiwiModelMesh,normal: Vector3,distance: float) -> KiwiModelMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_geometry").clip_plane(mesh,normal,distance)

static func convex(mesh: KiwiModelMesh) -> bool:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_geometry").convex(mesh)

static func bevel(mesh: KiwiModelMesh,selected_edges: PackedInt32Array,width: float) -> KiwiModelMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_geometry").bevel(mesh,selected_edges,width)

static func weld(mesh: KiwiModelMesh,distance: float=.0001) -> KiwiModelMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_geometry").weld(mesh,distance)
