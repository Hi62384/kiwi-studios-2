class_name KiwiPhysicsGeometry
extends RefCounted
const MAX_RENDER_VERTICES := 30000
static func primitive(runtime: ActorRuntime, values: Dictionary) -> PrimitiveMesh:
	var mesh: PrimitiveMesh
	match int(values.get(&"shape",0)):
		1: mesh=SphereMesh.new()
		2: mesh=CylinderMesh.new()
		3: mesh=CapsuleMesh.new()
		4: mesh=PlaneMesh.new()
		5: mesh=PrismMesh.new()
		6: mesh=QuadMesh.new()
		7: mesh=TorusMesh.new()
		_: mesh=BoxMesh.new()
	runtime._apply_shape_properties(mesh,values)
	return mesh
static func meshes(runtime: Node, physics_ids: Dictionary) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	for child in runtime.get_children():
		if child is ActorRuntime and physics_ids.has(child.actor.id): continue
		if child is MeshInstance3D and child.mesh != null and (child.layers & 1) != 0: result.append(child)
		result.append_array(meshes(child, physics_ids))
	return result
static func capture(runtime: ActorRuntime, physics_ids: Dictionary) -> Dictionary:
	var inverse := runtime.remote_transform().affine_inverse()
	var items := []; var points := PackedVector3Array(); var bounds := AABB(); var first := true
	for node in meshes(runtime, physics_ids):
		var owner: Node = node.get_parent()
		while owner != null and not owner is ActorRuntime: owner = owner.get_parent()
		var local: Transform3D = inverse * node.global_transform
		var mesh: Mesh = node.mesh
		var original:=mesh
		var is_primitive: bool=owner is ActorRuntime and owner.actor.type_id==&"basic_shape" and node==owner.content
		if is_primitive: mesh=primitive(owner,owner.actor.values)
		var box: AABB = local * mesh.get_aabb()
		bounds = box if first else bounds.merge(box); first = false
		var arrays := []; var materials := []
		for surface in mesh.get_surface_count():
			if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
			var data := mesh.surface_get_arrays(surface)
			if data.size() != Mesh.ARRAY_MAX: continue
			arrays.append(data); materials.append(node.get_active_material(surface))
			for vertex: Vector3 in data[Mesh.ARRAY_VERTEX]: points.append(local * vertex)
		items.append({"node": node, "original": original, "skin": node.skin, "local": local, "surfaces": arrays, "materials": materials, "visible": node.visible,"primitive":is_primitive,
			"actor_id":owner.actor.id if owner is ActorRuntime else runtime.actor.id,"owner_local":owner.remote_transform().affine_inverse()*node.global_transform if owner is ActorRuntime else local})
	if first: bounds = AABB(Vector3(-.5,-.5,-.5),Vector3.ONE)
	return {"meshes": items, "points": points, "bounds": bounds}
static func collider(geometry: Dictionary, settings: Dictionary) -> Dictionary:
	var bounds: AABB = geometry.bounds; var size := bounds.size.max(Vector3.ONE * .005)
	var choice := int(settings.shape); var shape: Shape3D; var offset := Transform3D(Basis.IDENTITY, bounds.get_center())
	match choice:
		2:
			var sphere := SphereShape3D.new(); sphere.radius = maxf(size.x,maxf(size.y,size.z))*.5; shape = sphere
		3:
			var capsule := CapsuleShape3D.new(); capsule.radius = maxf(size.x,size.z)*.5; capsule.height = maxf(size.y,capsule.radius*2.0); shape = capsule
		4:
			var cylinder := CylinderShape3D.new(); cylinder.radius = maxf(size.x,size.z)*.5; cylinder.height = size.y; shape = cylinder
		5:
			if geometry.points.size() >= 4:
				var hull := ConvexPolygonShape3D.new(); hull.points = geometry.points; shape = hull; offset = Transform3D.IDENTITY
		6:
			if int(settings.body_mode) == 1:
				var faces := PackedVector3Array()
				for item: Dictionary in geometry.meshes:
					for arrays: Array in item.surfaces:
						var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
						var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
						for index in (indices.size() if not indices.is_empty() else vertices.size()): faces.append(item.local * vertices[indices[index] if not indices.is_empty() else index])
				if not faces.is_empty():
					var concave := ConcavePolygonShape3D.new(); concave.set_faces(faces); concave.backface_collision = true; shape = concave; offset = Transform3D.IDENTITY
	if shape == null:
		var box := BoxShape3D.new(); box.size = size; shape = box
	return {"shape": shape, "offset": offset}
static func particles(geometry: Dictionary, count: int, pose: Transform3D) -> Dictionary:
	if geometry.points.size() > MAX_RENDER_VERTICES: return {"error": "Deformation supports up to 30,000 render vertices per actor. Use a lower-resolution simulation model."}
	var unique := {}; var source: PackedVector3Array = geometry.points
	for point in source: unique[point.snapped(Vector3.ONE * .0001)] = point
	var values := unique.values(); var local := PackedVector3Array()
	var stride := maxi(1, ceili(float(values.size()) / clampi(count, 8, 256)))
	for i in range(0, values.size(), stride): local.append(values[i])
	if local.size() < 3: return {"error": "This actor needs a triangle mesh with at least three distinct vertices."}
	var points := PackedVector3Array()
	for p in local: points.append(pose * p)
	var links := {}; var bindings := []
	for item: Dictionary in geometry.meshes:
		var surfaces := []
		for arrays: Array in item.surfaces:
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]; var ids := []; var weights := []; var rest := PackedVector3Array()
			for vertex in vertices:
				var p: Vector3 = item.local * vertex; var nearest := [-1,-1,-1]; var distances := [INF,INF,INF]
				for i in local.size():
					var d := p.distance_squared_to(local[i])
					for slot in 3:
						if d < distances[slot]:
							for shift in range(2,slot,-1): distances[shift] = distances[shift-1]; nearest[shift] = nearest[shift-1]
							distances[slot] = d; nearest[slot] = i; break
				var w := Vector3(1.0/maxf(.0000001,distances[0]),1.0/maxf(.0000001,distances[1]),1.0/maxf(.0000001,distances[2])); w /= w.x+w.y+w.z
				ids.append(Vector3i(nearest[0],nearest[1],nearest[2])); weights.append(w); rest.append(pose*p)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var n := indices.size() if not indices.is_empty() else vertices.size()
			for triangle in range(0,n-2,3):
				for edge in 3:
					var a: int = ids[indices[triangle+edge] if not indices.is_empty() else triangle+edge].x
					var b: int = ids[indices[triangle+(edge+1)%3] if not indices.is_empty() else triangle+(edge+1)%3].x
					if a != b: links[Vector2i(mini(a,b),maxi(a,b))] = true
			surfaces.append({"ids": ids, "weights": weights, "rest": rest})
		bindings.append({"item": item, "surfaces": surfaces})
	var edges := []
	for pair: Vector2i in links: edges.append([pair.x,pair.y,points[pair.x].distance_to(points[pair.y]),false])
	# Second-ring distances provide bend resistance without fixing cloth flat.
	var neighbours := {}
	for pair: Vector2i in links:
		if not neighbours.has(pair.x): neighbours[pair.x] = []
		if not neighbours.has(pair.y): neighbours[pair.y] = []
		neighbours[pair.x].append(pair.y); neighbours[pair.y].append(pair.x)
	for center in neighbours:
		var adjacent: Array = neighbours[center]
		for i in adjacent.size():
			for j in range(i+1,adjacent.size()):
				var pair := Vector2i(mini(adjacent[i],adjacent[j]),maxi(adjacent[i],adjacent[j]))
				if not links.has(pair): links[pair] = true; edges.append([pair.x,pair.y,points[pair.x].distance_to(points[pair.y]),true])
	return {"error": "", "local": local, "rest": points, "edges": edges, "bindings": bindings}
static func deform(data: Dictionary, points: PackedVector3Array, influence: float) -> void:
	for binding: Dictionary in data.bindings:
		var item: Dictionary = binding.item; var node: MeshInstance3D = item.node
		if not is_instance_valid(node): continue
		var mesh := ArrayMesh.new(); mesh.set_meta("kiwi_physics_mesh",true); var inverse := node.global_transform.affine_inverse()
		for surface in item.surfaces.size():
			var arrays: Array = item.surfaces[surface].duplicate(true); var source: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var mapping: Dictionary = binding.surfaces[surface]; var positions := PackedVector3Array()
			for i in source.size():
				var ids: Vector3i = mapping.ids[i]; var w: Vector3 = mapping.weights[i]
				var delta: Vector3 = (points[ids.x]-data.rest[ids.x])*w.x+(points[ids.y]-data.rest[ids.y])*w.y+(points[ids.z]-data.rest[ids.z])*w.z
				positions.append(inverse * (node.global_transform*source[i]).lerp(mapping.rest[i]+delta,influence))
			arrays[Mesh.ARRAY_VERTEX] = positions
			var normals := PackedVector3Array(); normals.resize(positions.size()); normals.fill(Vector3.ZERO)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for index in range(0,(indices.size() if not indices.is_empty() else positions.size())-2,3):
				var a := indices[index] if not indices.is_empty() else index; var b := indices[index+1] if not indices.is_empty() else index+1; var c := indices[index+2] if not indices.is_empty() else index+2
				var normal := (positions[b]-positions[a]).cross(positions[c]-positions[a]).normalized(); normals[a]+=normal; normals[b]+=normal; normals[c]+=normal
			for i in normals.size(): normals[i] = normals[i].normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals; arrays[Mesh.ARRAY_TANGENT] = null
			arrays[Mesh.ARRAY_BONES] = null; arrays[Mesh.ARRAY_WEIGHTS] = null
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); mesh.surface_set_material(surface,item.materials[surface])
		node.mesh = mesh; node.skin = null
static func rope_mesh(points: PackedVector3Array, inverse: Transform3D, radius: float, material: Material) -> ArrayMesh:
	var vertices := PackedVector3Array(); var normals := PackedVector3Array(); var uvs := PackedVector2Array(); var indices := PackedInt32Array(); var sides := 8
	for i in points.size():
		var tangent := (points[mini(i+1,points.size()-1)]-points[maxi(0,i-1)]).normalized()
		var axis := tangent.cross(Vector3.UP if absf(tangent.dot(Vector3.UP))<.95 else Vector3.RIGHT).normalized(); var other := tangent.cross(axis).normalized()
		for j in sides:
			var n := axis*cos(TAU*j/sides)+other*sin(TAU*j/sides)
			vertices.append(inverse*(points[i]+n*radius)); normals.append(inverse.basis*n); uvs.append(Vector2(float(j)/sides,float(i)/maxi(1,points.size()-1)))
		if i > 0:
			for j in sides:
				var a := (i-1)*sides+j; var b := (i-1)*sides+(j+1)%sides; var c := i*sides+j; var d := i*sides+(j+1)%sides
				indices.append_array(PackedInt32Array([a,c,b,b,c,d]))
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX); arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_NORMAL]=normals; arrays[Mesh.ARRAY_TEX_UV]=uvs; arrays[Mesh.ARRAY_INDEX]=indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); mesh.surface_set_material(0,material); return mesh
