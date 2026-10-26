class_name KiwiFluidVolume
extends RefCounted
static func generate(values: Dictionary,pose: Transform3D,geometry: Dictionary={}) -> Dictionary:
	var spacing: float=values.spacing; var shape:=int(values.get(&"fluid_shape",0)); var size: Vector3=values.get(&"fluid_dimensions",Vector3.ONE); size=size.abs().max(Vector3.ONE*spacing)
	var bounds:=AABB(-size*.5,size); var triangles: TriangleMesh
	if shape==3:
		var faces:=PackedVector3Array(); var edges:={}
		for item: Dictionary in geometry.get("meshes",[]):
			for arrays: Array in item.surfaces:
				var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]; var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
				for i in range(0,(indices.size() if not indices.is_empty() else vertices.size())-2,3):
					var points:=[]
					for slot in 3: points.append(item.local*vertices[indices[i+slot] if not indices.is_empty() else i+slot])
					for slot in 3:
						var a: Vector3=points[slot].snapped(Vector3.ONE*.00001); var b: Vector3=points[(slot+1)%3].snapped(Vector3.ONE*.00001)
						var key:=str(a)+"|"+str(b) if str(a)<str(b) else str(b)+"|"+str(a); edges[key]=int(edges.get(key,0))+1
					faces.append_array(PackedVector3Array(points))
		if faces.is_empty(): return {"points":PackedVector3Array(),"error":"Choose a closed triangle-mesh actor for the initial volume."}
		for count in edges.values():
			if count!=2: return {"points":PackedVector3Array(),"error":"The volume mesh is open or nonmanifold. Close its surface before filling."}
		triangles=TriangleMesh.new(); triangles.create_from_faces(faces); bounds=AABB(faces[0],Vector3.ZERO)
		for p in faces: bounds=bounds.expand(p)
	var points:=PackedVector3Array(); var n:=Vector3i(ceil(bounds.size.x/spacing),ceil(bounds.size.y/spacing),ceil(bounds.size.z/spacing))
	if n.x*n.y*n.z>200000: return {"points":points,"error":"Volume sampling would exceed 200,000 cells. Increase particle spacing or shrink the volume."}
	for x in n.x:
		for y in n.y:
			for z in n.z:
				var p:=bounds.position+(Vector3(x,y,z)+Vector3.ONE*.5)*spacing
				if p.x>bounds.end.x or p.y>bounds.end.y or p.z>bounds.end.z: continue
				var q:=p/(size*.5)
				if shape==1 and q.length_squared()>1.0: continue
				if shape==2 and Vector2(q.x,q.z).length_squared()>1.0: continue
				if shape==3 and not inside(triangles,p,bounds.size.length()*3): continue
				if points.size()>=int(values.budget): return {"points":points,"error":"Initial volume exceeds the particle budget. Increase spacing or raise the budget; the volume was not partially filled."}
				points.append(pose*p)
	return {"points":points,"error":""}
static func inside(mesh: TriangleMesh,point: Vector3,distance: float) -> bool:
	var direction:=Vector3(1,.173,.317).normalized(); var from:=point; var count:=0
	for iteration in 128:
		var hit:=mesh.intersect_ray(from,point+direction*distance)
		if hit.is_empty(): break
		count+=1; from=hit.position+direction*.0001
	return count%2==1
