class_name KiwiVolumeSampler
extends RefCounted
## Shared solver-independent interior sampling. Never return a partial fill.
const MAX_CELLS := 200000
const MAX_TRIANGLES := 100000
static func failure(message: String) -> Dictionary:
	return {"points":PackedVector3Array(),"error":message}
static func closed_mesh(geometry: Dictionary) -> Dictionary:
	var faces:=PackedVector3Array(); var edges:={}; var fans:={}
	for item: Dictionary in geometry.get("meshes",[]):
		for arrays: Array in item.get("surfaces",[]):
			if arrays.size()!=Mesh.ARRAY_MAX or not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array: return failure("Unsupported mesh surface: triangle vertices are required.")
			var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var count:=indices.size() if not indices.is_empty() else vertices.size()
			if count%3!=0: return failure("The source contains an incomplete triangle surface.")
			if (faces.size()+count)/3>MAX_TRIANGLES: return failure("Source exceeds 100,000 triangles. Use a simpler closed source mesh.")
			for i in range(0,count,3):
				var points:=PackedVector3Array(); var keys:=[]
				for slot in 3:
					var index:=indices[i+slot] if not indices.is_empty() else i+slot
					if index<0 or index>=vertices.size(): return failure("The mesh has an invalid triangle index.")
					var p: Vector3=item.local*vertices[index]
					if not p.is_finite(): return failure("The mesh contains non-finite vertices.")
					points.append(p); keys.append(p.snapped(Vector3.ONE*.00001))
				if (points[1]-points[0]).cross(points[2]-points[0]).length_squared()<1e-16 or keys[0]==keys[1] or keys[1]==keys[2] or keys[2]==keys[0]: return failure("The source has degenerate triangles. Clean the mesh before filling.")
				for slot in 3:
					var a: Vector3=keys[slot]; var b: Vector3=keys[(slot+1)%3]; var previous: Vector3=keys[(slot+2)%3]
					var forward:=str(a)<str(b); var key:=str(a)+"|"+str(b) if forward else str(b)+"|"+str(a)
					if not edges.has(key): edges[key]=Vector2i.ZERO
					edges[key]+=Vector2i(1,1 if forward else -1)
					if not fans.has(a): fans[a]={}
					if fans[a].has(b): return failure("The source is nonmanifold or has duplicate faces.")
					fans[a][b]=previous
				faces.append_array(points)
	if faces.is_empty(): return failure("Choose an actor containing a closed triangle mesh; this source has no supported triangles.")
	for edge: Vector2i in edges.values():
		if edge.x!=2: return failure("The source mesh is open or nonmanifold. Close its surface before filling.")
		if edge.y!=0: return failure("The source has inconsistent triangle winding. Recalculate its face orientation before filling.")
	for fan: Dictionary in fans.values():
		var first: Variant=fan.keys()[0]; var current: Variant=first; var seen:={}
		while fan.has(current) and not seen.has(current):
			seen[current]=true; current=fan[current]
		if current!=first or seen.size()!=fan.size(): return failure("The source has a nonmanifold vertex. Separate touching shells before filling.")
	var mesh:=TriangleMesh.new(); mesh.create_from_faces(faces)
	var bounds:=AABB(faces[0],Vector3.ZERO)
	for p in faces: bounds=bounds.expand(p)
	return {"mesh":mesh,"bounds":bounds,"error":""}
static func inside(mesh: TriangleMesh,point: Vector3,distance: float) -> bool:
	var direction:=Vector3(1,.173,.317).normalized(); var from:=point; var count:=0
	for iteration in 256:
		var hit:=mesh.intersect_ray(from,point+direction*distance)
		if hit.is_empty(): return count%2==1
		count+=1; from=hit.position+direction*.00001
	return false
static func contains(point: Vector3,shape: int,size: Vector3,mesh: TriangleMesh,bounds: AABB) -> bool:
	if not bounds.has_point(point): return false
	var q:=point/(size*.5)
	if shape==1: return q.length_squared()<=1.0
	if shape==2: return Vector2(q.x,q.z).length_squared()<=1.0
	if shape==3: return inside(mesh,point,maxf(.001,bounds.size.length()*3))
	return true
static func generate(shape: int,size: Vector3,spacing: float,budget: int,pose: Transform3D,geometry: Dictionary={},jitter: float=0.0,seed: int=1) -> Dictionary:
	if shape not in [0,1,2,3]: return failure("Unsupported volume shape. Choose Box, Sphere, Cylinder or a closed mesh actor.")
	if not size.is_finite() or size.x<=0 or size.y<=0 or size.z<=0: return failure("Source dimensions must be positive and finite.")
	if not is_finite(spacing) or spacing<=0 or budget<1: return failure("Grain spacing and maximum count must be positive.")
	if not pose.origin.is_finite() or not pose.basis.is_finite() or absf(pose.basis.determinant())<1e-10: return failure("The source needs a finite, nonzero transform scale on every axis.")
	var bounds:=AABB(-size*.5,size); var mesh: TriangleMesh
	if shape==3:
		var closed:=closed_mesh(geometry)
		if not str(closed.error).is_empty(): return closed
		mesh=closed.mesh; bounds=closed.bounds
	var cells:=bounds.size/spacing
	if not cells.is_finite() or cells.x>MAX_CELLS or cells.y>MAX_CELLS or cells.z>MAX_CELLS: return failure("Source exceeds 200,000 sampling cells. Increase spacing or shrink the source.")
	var n:=Vector3i(ceil(cells.x),ceil(cells.y),ceil(cells.z))
	if n.x*n.y*n.z>MAX_CELLS: return failure("Source exceeds 200,000 sampling cells. Increase spacing or shrink the source.")
	var points:=PackedVector3Array(); var rng:=RandomNumberGenerator.new(); rng.seed=seed
	for x in n.x:
		for y in n.y:
			for z in n.z:
				var p:=bounds.position+(Vector3(x,y,z)+Vector3.ONE*.5)*spacing
				if not contains(p,shape,size,mesh,bounds): continue
				if jitter>0:
					var candidate:=p+Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1))*spacing*jitter
					if contains(candidate,shape,size,mesh,bounds): p=candidate
				if points.size()>=budget: return failure("Initial volume exceeds the grain/particle budget. Increase spacing or raise the maximum count; no partial fill was created.")
				points.append(pose*p)
	if points.is_empty(): return failure("No interior samples fit at this spacing. Decrease spacing or enlarge the source.")
	return {"points":points,"error":""}
