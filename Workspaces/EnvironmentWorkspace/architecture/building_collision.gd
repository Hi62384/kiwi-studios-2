extends RefCounted
## Generated solid pieces retain separate topology. Reuse those convex cells for
## the existing offline compound-collider API, keeping doors and shafts open.
static func parts(mesh: KiwiModelMesh) -> Array:
	var parents:=PackedInt32Array(); parents.resize(mesh.vertices.size())
	for i in parents.size(): parents[i]=i
	for face in mesh.faces:
		if face.is_empty(): continue
		for index in range(1,face.size()):
			var a:=_root(parents,face[0]); var b:=_root(parents,face[index])
			if a!=b: parents[b]=a
	var groups: Dictionary={}
	for index in parents.size():
		var root:=_root(parents,index)
		if not groups.has(root): groups[root]=PackedVector3Array()
		var vertices: PackedVector3Array=groups[root]; vertices.append(mesh.vertices[index]); groups[root]=vertices
	var result: Array=[]
	for vertices: PackedVector3Array in groups.values():
		if vertices.size()>=4: result.append(vertices)
	return result
static func _root(parents: PackedInt32Array,index: int) -> int:
	while parents[index]!=index: index=parents[index]
	return index
