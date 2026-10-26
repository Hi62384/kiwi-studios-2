class_name KiwiModelGeometry
extends RefCounted
## Operations return fresh topology, keeping document snapshots immutable.
static func remove_faces(mesh: KiwiModelMesh, selected: PackedInt32Array) -> KiwiModelMesh:
	var result := mesh.copy_mesh(); result.faces.clear(); result.uv.clear(); result.materials.clear()
	var chosen := {}
	for f in selected: chosen[f]=true
	for f in mesh.faces.size():
		if not chosen.has(f): result.add_face(mesh.faces[f].duplicate(),mesh.uv[f].duplicate(),mesh.materials[f])
	return compact(result)

static func compact(mesh: KiwiModelMesh) -> KiwiModelMesh:
	var used := {}; var result := KiwiModelMesh.new(); result.smooth=mesh.smooth
	for f in mesh.faces.size():
		var face := PackedInt32Array()
		for index in mesh.faces[f]:
			if not used.has(index): used[index]=result.vertices.size(); result.vertices.append(mesh.vertices[index])
			face.append(used[index])
		result.add_face(face,mesh.uv[f],mesh.materials[f])
	return result

static func extrude(mesh: KiwiModelMesh, selected: PackedInt32Array, distance: float, individual: bool=false) -> Dictionary:
	var result := mesh.copy_mesh(); var mapping := {}; var normals := {}; var chosen := PackedInt32Array()
	var selected_set := {}
	for f in selected: selected_set[f]=true
	for f in selected:
		if f<0 or f>=mesh.faces.size(): continue
		for index in mesh.faces[f]:
			var key := str(f)+":"+str(index) if individual else str(index)
			normals[key]=normals.get(key,Vector3.ZERO)+mesh.normal(f)
	for f in selected:
		if f<0 or f>=mesh.faces.size(): continue
		var old := mesh.faces[f]; var cap := PackedInt32Array()
		for index in old:
			var key := str(f)+":"+str(index) if individual else str(index)
			if not mapping.has(key): mapping[key]=result.vertices.size(); result.vertices.append(mesh.vertices[index]+normals[key].normalized()*distance)
			cap.append(mapping[key])
		result.faces[f]=cap; chosen.append(f)
	for edge in mesh.edges():
		var adjacent := PackedInt32Array()
		for f in edge.faces:
			if selected_set.has(f): adjacent.append(f)
		if adjacent.is_empty() or (adjacent.size()>1 and not individual): continue
		for f in adjacent:
			var face := mesh.faces[f]; var a: int=edge.a; var b: int=edge.b
			if face[(face.find(a)+1)%face.size()]!=b: var temp:=a; a=b; b=temp
			var prefix := str(f)+":" if individual else ""
			result.add_face(PackedInt32Array([a,b,mapping[prefix+str(b)],mapping[prefix+str(a)]]),PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2(1,distance),Vector2(0,distance)]),mesh.materials[f])
	return {"mesh":result,"selection":chosen}

static func inset(mesh: KiwiModelMesh, selected: PackedInt32Array, width: float) -> Dictionary:
	var result := mesh.copy_mesh(); var chosen := PackedInt32Array()
	for f in selected:
		if f<0 or f>=mesh.faces.size(): continue
		var face := mesh.faces[f]; var normal := mesh.normal(f); var cap := PackedInt32Array()
		var cap_uv := PackedVector2Array()
		for i in face.size():
			var current := mesh.vertices[face[i]]; var previous := mesh.vertices[face[posmod(i-1,face.size())]]; var next := mesh.vertices[face[(i+1)%face.size()]]
			var a := (current-previous).normalized().cross(normal); var b := (next-current).normalized().cross(normal)
			var bisector := (a+b).normalized(); var distance := minf(maxf(0.,width),minf(current.distance_to(previous),current.distance_to(next))*.45)
			var offset := bisector*distance/maxf(.1,absf(bisector.dot(b)))
			cap.append(result.vertices.size()); result.vertices.append(current+offset); cap_uv.append(mesh.uv_at(f,current+offset))
		result.faces[f]=cap; result.uv[f]=cap_uv; chosen.append(f)
		for i in face.size():
			var j := (i+1)%face.size()
			result.add_face(PackedInt32Array([face[i],face[j],cap[j],cap[i]]),PackedVector2Array([mesh.uv[f][i],mesh.uv[f][j],cap_uv[j],cap_uv[i]]),mesh.materials[f])
	return {"mesh":result,"selection":chosen}

static func subdivide(mesh: KiwiModelMesh, selected: PackedInt32Array=PackedInt32Array()) -> KiwiModelMesh:
	var result := KiwiModelMesh.new(); result.vertices=mesh.vertices.duplicate(); result.smooth=mesh.smooth; var midpoints := {}
	var selected_set := {}
	for f in selected: selected_set[f]=true
	for edge in mesh.edges():
		var split := selected.is_empty()
		for f in edge.faces:
			if selected_set.has(f): split=true
		if split:
			midpoints[KiwiModelMesh.edge_key(edge.a,edge.b)]=result.vertices.size(); result.vertices.append((mesh.vertices[edge.a]+mesh.vertices[edge.b])*.5)
	for f in mesh.faces.size():
		if not selected.is_empty() and not selected_set.has(f):
			var expanded := PackedInt32Array(); var coordinates := PackedVector2Array(); var old := mesh.faces[f]
			for i in old.size():
				var j := (i+1)%old.size(); expanded.append(old[i]); coordinates.append(mesh.uv[f][i]); var key := KiwiModelMesh.edge_key(old[i],old[j])
				if midpoints.has(key): expanded.append(midpoints[key]); coordinates.append((mesh.uv[f][i]+mesh.uv[f][j])*.5)
			result.add_face(expanded,coordinates,mesh.materials[f]); continue
		var face := mesh.faces[f]; var midpoint := result.vertices.size(); result.vertices.append(mesh.center(f)); var center_uv := Vector2.ZERO
		for corner in mesh.uv[f]: center_uv+=corner/face.size()
		for i in face.size():
			var prev := posmod(i-1,face.size()); var next := (i+1)%face.size(); var mids := []
			for neighbor in [next,prev]:
				var key := KiwiModelMesh.edge_key(face[i],face[neighbor])
				if not midpoints.has(key): midpoints[key]=result.vertices.size(); result.vertices.append((mesh.vertices[face[i]]+mesh.vertices[face[neighbor]])*.5)
				mids.append(midpoints[key])
			result.add_face(PackedInt32Array([face[i],mids[0],midpoint,mids[1]]),PackedVector2Array([mesh.uv[f][i],(mesh.uv[f][i]+mesh.uv[f][next])*.5,center_uv,(mesh.uv[f][i]+mesh.uv[f][prev])*.5]),mesh.materials[f])
	return result

static func subdivide_edges(mesh: KiwiModelMesh, selected: PackedInt32Array) -> KiwiModelMesh:
	var result := KiwiModelMesh.new(); result.vertices=mesh.vertices.duplicate(); result.smooth=mesh.smooth; var midpoints := {}; var edges := mesh.edges()
	for index in selected:
		if index<0 or index>=edges.size(): continue
		var edge := edges[index]; midpoints[KiwiModelMesh.edge_key(edge.a,edge.b)]=result.vertices.size(); result.vertices.append((mesh.vertices[edge.a]+mesh.vertices[edge.b])*.5)
	for f in mesh.faces.size():
		var face := PackedInt32Array(); var coordinates := PackedVector2Array(); var old := mesh.faces[f]
		for i in old.size():
			var j := (i+1)%old.size(); face.append(old[i]); coordinates.append(mesh.uv[f][i]); var key := KiwiModelMesh.edge_key(old[i],old[j])
			if midpoints.has(key): face.append(midpoints[key]); coordinates.append((mesh.uv[f][i]+mesh.uv[f][j])*.5)
		result.add_face(face,coordinates,mesh.materials[f])
	return result

static func smooth_mesh(mesh: KiwiModelMesh, strength: float=.5, iterations: int=1) -> KiwiModelMesh:
	var result := mesh.copy_mesh(); var neighbors := {}; var boundary := {}
	for edge in mesh.edges():
		for pair in [[edge.a,edge.b],[edge.b,edge.a]]:
			if not neighbors.has(pair[0]): neighbors[pair[0]]=[]
			neighbors[pair[0]].append(pair[1])
		if edge.faces.size()==1: boundary[edge.a]=true; boundary[edge.b]=true
	for unused in clampi(iterations,1,8):
		var points := result.vertices.duplicate()
		for index in neighbors:
			if boundary.has(index): continue
			var average := Vector3.ZERO
			for neighbor in neighbors[index]: average+=points[neighbor]/neighbors[index].size()
			result.vertices[index]=points[index].lerp(average,clampf(strength,0,1))
	return result

static func clip_plane(mesh: KiwiModelMesh, normal: Vector3, distance: float) -> KiwiModelMesh:
	var result := KiwiModelMesh.new(); var cut: Array[Vector3]=[]; var lookup := {}; result.smooth=mesh.smooth
	for f in mesh.faces.size():
		var points: Array[Vector3]=[]; var coords: Array[Vector2]=[]; var face := mesh.faces[f]
		for i in face.size():
			var j := (i+1)%face.size(); var a := mesh.vertices[face[i]]; var b := mesh.vertices[face[j]]; var da := normal.dot(a)-distance; var db := normal.dot(b)-distance
			if da<=.000001: points.append(a); coords.append(mesh.uv[f][i])
			if absf(da)<.000001: cut.append(a)
			if (da<-.000001 and db>.000001) or (da>.000001 and db<-.000001):
				var t := da/(da-db); var p := a.lerp(b,t); points.append(p); coords.append(mesh.uv[f][i].lerp(mesh.uv[f][j],t)); cut.append(p)
		if points.size()<3: continue
		var indices := PackedInt32Array()
		for p in points: indices.append(_vertex(result,lookup,p))
		result.add_face(indices,PackedVector2Array(coords),mesh.materials[f])
	var unique: Array[Vector3]=[]; var used := {}
	for p in cut:
		var key := p.snapped(Vector3.ONE*.00001)
		if not used.has(key): used[key]=true; unique.append(p)
	if unique.size()>=3:
		var center := Vector3.ZERO
		for p in unique: center+=p/unique.size()
		var u := normal.cross(Vector3.UP if absf(normal.y)<.9 else Vector3.RIGHT).normalized(); var v := normal.cross(u)
		unique.sort_custom(func(a:Vector3,b:Vector3)->bool: return atan2((a-center).dot(v),(a-center).dot(u))>atan2((b-center).dot(v),(b-center).dot(u)))
		var cap := PackedInt32Array()
		for p in unique: cap.append(_vertex(result,lookup,p))
		var f := result.add_face(cap)
		if result.normal(f).dot(normal)<0: result.faces[f].reverse(); result.uv[f].reverse()
	return result

static func _vertex(mesh: KiwiModelMesh, lookup: Dictionary, p: Vector3) -> int:
	var key := p.snapped(Vector3.ONE*.00001)
	if not lookup.has(key): lookup[key]=mesh.vertices.size(); mesh.vertices.append(p)
	return lookup[key]

static func convex(mesh: KiwiModelMesh) -> bool:
	for f in mesh.faces.size():
		var n := mesh.normal(f); var d := n.dot(mesh.center(f))
		for point in mesh.vertices:
			if n.dot(point)>d+.0001: return false
	return true

static func bevel(mesh: KiwiModelMesh, selected_edges: PackedInt32Array, width: float) -> KiwiModelMesh:
	if mesh.faces.size()>64 or not convex(mesh): return null
	var planes := []; var edges := mesh.edges(); var unique := {}
	for f in mesh.faces.size():
		var n := mesh.normal(f); var d := n.dot(mesh.center(f)); var key := str(n.snapped(Vector3.ONE*.00001))+":"+str(snappedf(d,.00001))
		if not unique.has(key): unique[key]=true; planes.append([n,d,mesh.materials[f],f])
	for e in edges.size():
		if not selected_edges.is_empty() and not selected_edges.has(e): continue
		var edge := edges[e]
		if edge.faces.size()!=2: continue
		var a := mesh.normal(edge.faces[0]); var b := mesh.normal(edge.faces[1])
		if a.dot(b)>.999: continue
		var n := (a+b).normalized(); planes.append([n,n.dot(mesh.vertices[edge.a])-maxf(.0001,width),mesh.materials[edge.faces[0]],-1])
	if planes.size()>64: return null
	# Intersect convex half-spaces directly. This avoids cracks and T-junctions
	# where three sequential edge clips meet at an existing cut vertex.
	var result := KiwiModelMesh.new(); var lookup := {}
	for i in planes.size():
		for j in range(i+1,planes.size()):
			for k in range(j+1,planes.size()):
				var a: Vector3=planes[i][0]; var b: Vector3=planes[j][0]; var c: Vector3=planes[k][0]; var determinant := a.dot(b.cross(c))
				if absf(determinant)<.000001: continue
				var point: Vector3=(b.cross(c)*planes[i][1]+c.cross(a)*planes[j][1]+a.cross(b)*planes[k][1])/determinant
				var inside := true
				for plane in planes:
					if (plane[0] as Vector3).dot(point)>plane[1]+.00001: inside=false; break
				if inside: _vertex(result,lookup,point)
	for plane in planes:
		var n: Vector3=plane[0]; var indices: Array[int]=[]; var center := Vector3.ZERO
		for i in result.vertices.size():
			if absf(n.dot(result.vertices[i])-plane[1])<.00005: indices.append(i); center+=result.vertices[i]
		if indices.size()<3: continue
		center/=indices.size(); var u := n.cross(Vector3.UP if absf(n.y)<.9 else Vector3.RIGHT).normalized(); var v := n.cross(u)
		indices.sort_custom(func(a:int,b:int)->bool: return atan2((result.vertices[a]-center).dot(v),(result.vertices[a]-center).dot(u))>atan2((result.vertices[b]-center).dot(v),(result.vertices[b]-center).dot(u)))
		var coordinates := PackedVector2Array()
		if plane[3]>=0:
			for index in indices: coordinates.append(mesh.uv_at(plane[3],result.vertices[index]))
		var f := result.add_face(PackedInt32Array(indices),coordinates,plane[2])
		if result.normal(f).dot(n)<0: result.faces[f].reverse(); result.uv[f].reverse()
	return result

static func weld(mesh: KiwiModelMesh, distance: float=.0001) -> KiwiModelMesh:
	var result := KiwiModelMesh.new(); var lookup := {}; var mapping := {}; result.smooth=mesh.smooth
	for i in mesh.vertices.size():
		var p := mesh.vertices[i]; var key := p.snapped(Vector3.ONE*maxf(.000001,distance))
		if not lookup.has(key): lookup[key]=result.vertices.size(); result.vertices.append(p)
		mapping[i]=lookup[key]
	for f in mesh.faces.size():
		var face := PackedInt32Array(); var corners := PackedVector2Array()
		for i in mesh.faces[f].size():
			var mapped: int=mapping[mesh.faces[f][i]]
			if not face.has(mapped): face.append(mapped); corners.append(mesh.uv[f][i])
		if face.size()>=3:
			var added := result.add_face(face,corners,mesh.materials[f])
			if result.normal(added).length_squared()<.5: result.faces.pop_back(); result.uv.pop_back(); result.materials.resize(result.materials.size()-1)
	return result
