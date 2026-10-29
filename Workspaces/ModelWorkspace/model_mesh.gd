class_name KiwiModelMesh
extends Resource
## Polygon topology is authoritative. Rendering may duplicate corners for UV seams
## and hard normals without splitting the editable vertices.
@export var vertices := PackedVector3Array()
@export var faces: Array[PackedInt32Array] = []
@export var uv: Array[PackedVector2Array] = []
@export var materials := PackedInt32Array()
@export var smooth := false
var _edge_signature := -1
var _edge_cache: Array[Dictionary] = []

func copy_mesh() -> KiwiModelMesh:
	var result := KiwiModelMesh.new()
	result.vertices = vertices.duplicate()
	for face in faces: result.faces.append(face.duplicate())
	for corners in uv: result.uv.append(corners.duplicate())
	result.materials = materials.duplicate(); result.smooth = smooth
	return result

func add_face(indices: PackedInt32Array, corners := PackedVector2Array(), material: int = 0) -> int:
	faces.append(indices); materials.append(material)
	if corners.size() != indices.size():
		corners = PackedVector2Array()
		var dominant := normal(faces.size()-1).abs().max_axis_index()
		for index in indices:
			var p := vertices[index]
			corners.append(Vector2(p.z,p.y) if dominant==0 else (Vector2(p.x,p.z) if dominant==1 else Vector2(p.x,p.y)))
	uv.append(corners)
	return faces.size() - 1

func center(face: int) -> Vector3:
	var result := Vector3.ZERO
	for index in faces[face]: result += vertices[index]
	return result / max(1, faces[face].size())

func normal(face: int) -> Vector3:
	# Newell's polygon normal with Godot's clockwise front-face convention.
	var result := Vector3.ZERO; var indices := faces[face]
	for i in indices.size():
		var a := vertices[indices[i]]; var b := vertices[indices[(i + 1) % indices.size()]]
		result += Vector3((a.y-b.y)*(a.z+b.z), (a.z-b.z)*(a.x+b.x), (a.x-b.x)*(a.y+b.y))
	return -result.normalized()

func edges() -> Array[Dictionary]:
	var signature := hash(faces)
	if signature==_edge_signature: return _edge_cache
	var lookup := {}; var result: Array[Dictionary] = []
	for face_index in faces.size():
		var face := faces[face_index]
		for i in face.size():
			var a := face[i]; var b := face[(i+1)%face.size()]; var key := edge_key(a,b)
			if not lookup.has(key):
				lookup[key] = result.size(); result.append({"a":mini(a,b),"b":maxi(a,b),"faces":PackedInt32Array()})
			var edge: Dictionary = result[lookup[key]]; var adjacent: PackedInt32Array = edge.faces
			adjacent.append(face_index); edge.faces = adjacent
	_edge_signature=signature; _edge_cache=result
	return result

static func edge_key(a: int, b: int) -> String: return "%d:%d" % [mini(a,b),maxi(a,b)]

func triangles(face_index: int) -> PackedInt32Array:
	var face := faces[face_index]; var points := PackedVector2Array(); var n := normal(face_index)
	var u := n.cross(Vector3.UP if absf(n.y)<.9 else Vector3.RIGHT).normalized(); var v := n.cross(u)
	for index in face: points.append(Vector2(vertices[index].dot(u),vertices[index].dot(v)))
	var result := Geometry2D.triangulate_polygon(points)
	for i in range(0,result.size(),3):
		var a := vertices[face[result[i]]]; var b := vertices[face[result[i+1]]]; var c := vertices[face[result[i+2]]]
		if (c-a).cross(b-a).dot(n)<0:
			var temp := result[i+1]; result[i+1] = result[i+2]; result[i+2] = temp
	return result

func uv_at(face: int, point: Vector3) -> Vector2:
	var indices := triangles(face); var fallback := Vector2.ZERO
	for i in range(0,indices.size(),3):
		var a := vertices[faces[face][indices[i]]]; var u := vertices[faces[face][indices[i+1]]]-a; var v := vertices[faces[face][indices[i+2]]]-a; var p := point-a
		var denominator := u.dot(u)*v.dot(v)-u.dot(v)*u.dot(v)
		if absf(denominator)<.000000001: continue
		var y := (v.dot(v)*p.dot(u)-u.dot(v)*p.dot(v))/denominator; var z := (u.dot(u)*p.dot(v)-u.dot(v)*p.dot(u))/denominator
		var result := uv[face][indices[i]]*(1.-y-z)+uv[face][indices[i+1]]*y+uv[face][indices[i+2]]*z
		fallback=result
		if y>=-.0001 and z>=-.0001 and y+z<=1.0001: return result
	return fallback

func validate(thorough: bool=true) -> PackedStringArray:
	var errors := PackedStringArray()
	for vertex in vertices:
		if not vertex.is_finite(): errors.append("Non-finite vertex"); break
	if uv.size()!=faces.size() or materials.size()!=faces.size(): errors.append("Missing face surface data")
	for f in faces.size():
		var face := faces[f]; var valid := face.size()>=3
		for index in face:
			if index<0 or index>=vertices.size(): valid=false
		if not valid: errors.append("Invalid face %d"%f); continue
		if thorough and (normal(f).length_squared()<.5 or triangles(f).is_empty()): errors.append("Degenerate face %d"%f)
		if f<uv.size() and uv[f].size()!=face.size(): errors.append("Invalid UV corners")
	return errors

func render_mesh(surface_materials: Array[Material] = []) -> ArrayMesh:
	var result := ArrayMesh.new()
	if faces.is_empty(): return result
	var normals := PackedVector3Array(); normals.resize(vertices.size()); normals.fill(Vector3.ZERO)
	if smooth:
		for f in faces.size():
			var n := normal(f)
			for vertex in faces[f]: normals[vertex] += n
	var groups := {}
	for f in faces.size():
		var mat := materials[f] if f<materials.size() else 0
		if not groups.has(mat): groups[mat]=[]
		groups[mat].append(f)
	for mat in groups:
		var positions := PackedVector3Array(); var face_normals := PackedVector3Array(); var texcoords := PackedVector2Array()
		for f: int in groups[mat]:
			for corner in triangles(f):
				var index := faces[f][corner]; positions.append(vertices[index])
				face_normals.append(normals[index].normalized() if smooth else normal(f))
				texcoords.append(uv[f][corner] if f<uv.size() else Vector2.ZERO)
		if positions.is_empty(): continue
		# Generate tangents from CPU vertices before the one native upload. Creating
		# an intermediate ArrayMesh and reading it back stalls once per surface.
		var builder:=SurfaceTool.new(); builder.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in positions.size():
			builder.set_normal(face_normals[index]); builder.set_uv(texcoords[index]); builder.add_vertex(positions[index])
		builder.generate_tangents(); builder.commit(result)
		if mat>=0 and mat<surface_materials.size(): result.surface_set_material(result.get_surface_count()-1,surface_materials[mat])
	return result

static func from_mesh(source: Mesh) -> KiwiModelMesh:
	var result := KiwiModelMesh.new(); var lookup := {}
	if source == null: return result
	for surface in source.get_surface_count():
		if source is ArrayMesh and source.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: continue
		var arrays := source.surface_get_arrays(surface)
		if arrays.is_empty(): continue
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]; var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var texcoords: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
		var count := indices.size() if not indices.is_empty() else points.size()
		for i in range(0,count-2,3):
			var face := PackedInt32Array(); var corners := PackedVector2Array()
			for j in 3:
				var index := indices[i+j] if not indices.is_empty() else i+j; var p := points[index]
				var key := Vector3i(roundi(p.x*100000),roundi(p.y*100000),roundi(p.z*100000))
				if not lookup.has(key): lookup[key]=result.vertices.size(); result.vertices.append(p)
				face.append(lookup[key]); corners.append(texcoords[index] if index<texcoords.size() else Vector2.ZERO)
			if face[0]!=face[1] and face[1]!=face[2] and face[0]!=face[2]: result.add_face(face,corners,surface)
	return result

func append_mesh(other: KiwiModelMesh, transform := Transform3D.IDENTITY, material_offset: int = 0) -> void:
	var offset := vertices.size()
	for vertex in other.vertices: vertices.append(transform*vertex)
	for f in other.faces.size():
		var face := other.faces[f].duplicate(); var corners := other.uv[f].duplicate()
		for i in face.size(): face[i]+=offset
		if transform.basis.determinant()<0: face.reverse(); corners.reverse()
		add_face(face,corners,other.materials[f]+material_offset)

func bounds() -> AABB:
	var result := AABB(vertices[0],Vector3.ZERO) if not vertices.is_empty() else AABB()
	for vertex in vertices: result=result.expand(vertex)
	return result
