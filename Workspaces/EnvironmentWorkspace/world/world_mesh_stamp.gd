extends RefCounted
static func value(mesh: KiwiModelMesh,version: int=2) -> int:
	if mesh==null: return 0
	return hash([mesh.vertices,mesh.faces,mesh.uv,mesh.materials]) if version>=2 else hash([mesh.vertices,mesh.faces])
