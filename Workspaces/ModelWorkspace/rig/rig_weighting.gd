class_name KiwiRigWeighting
extends RefCounted
const MAX_VERTICES := 100000
const MAX_PAIRS := 3000000
## Independent CPU algorithms. No scene nodes or rendering resources are changed.
static func geometry(source: Mesh, transform: Transform3D) -> Dictionary:
	var points := PackedVector3Array(); var surfaces: Array[PackedInt32Array]=[]; var lookup := {}; var edges := {}; var neighbors: Array[Dictionary]=[]
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface); var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]; var mapping := PackedInt32Array()
		for vertex in vertices:
			var p := transform*vertex; var key := Vector3i(roundi(p.x*100000),roundi(p.y*100000),roundi(p.z*100000))
			if not lookup.has(key): lookup[key]=points.size(); points.append(p); neighbors.append({})
			mapping.append(lookup[key])
		var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else vertices.size()
		for offset in range(0,count-2,3):
			for k in 3:
				var a := mapping[indices[offset+k] if not indices.is_empty() else offset+k]
				var b := mapping[indices[offset+(k+1)%3] if not indices.is_empty() else offset+(k+1)%3]
				if a!=b: neighbors[a][b]=true; neighbors[b][a]=true; edges[KiwiModelMesh.edge_key(a,b)]=points[a].distance_to(points[b])
		surfaces.append(mapping)
	var graph: Array[PackedInt32Array]=[]
	for connected in neighbors: graph.append(PackedInt32Array(connected.keys()))
	var islands := PackedInt32Array(); islands.resize(points.size()); islands.fill(-1); var groups: Array[PackedInt32Array]=[]
	for v in points.size():
		if islands[v]>=0: continue
		var members := PackedInt32Array([v]); islands[v]=groups.size(); var cursor := 0
		while cursor<members.size():
			for other in graph[members[cursor]]:
				if islands[other]<0: islands[other]=groups.size(); members.append(other)
			cursor+=1
		groups.append(members)
	var average := 0.
	for value: float in edges.values(): average+=value
	return {"points":points,"surfaces":surfaces,"neighbors":graph,"islands":islands,"groups":groups,"edge":average/maxi(1,edges.size())}

static func compute(source: Mesh, bones: Array, transform: Transform3D, method: String="Smooth", count: int=4, iterations: int=8, cancellation: RefCounted=null) -> KiwiRigBinding:
	for surface in source.get_surface_count():
		if source.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: return null
	var result := KiwiRigBinding.new(); result.source_mesh=source; result.mesh_to_rig=transform; result.influence_count=8 if count==8 else 4
	for bone: Dictionary in bones: result.bone_ids.append(str(bone.id))
	if bones.is_empty(): return result
	if not bones.any(func(bone: Dictionary): return bone.get("metadata",{}).get("deform",true)): return null
	var shape := geometry(source,transform); var points: PackedVector3Array=shape.points; var rest := KiwiRigMath.globals(bones)
	var values: Array[Dictionary]=[]; var island_distance: Array[Dictionary]=[]
	for group in shape.groups: island_distance.append({})
	for v in points.size():
		if v%256==0 and cancellation!=null and cancellation.is_cancelled(): return null
		var distances := {}; var island: Dictionary=island_distance[shape.islands[v]]
		for b in bones.size():
			if not bones[b].get("metadata",{}).get("deform",true): continue
			var nearest := Geometry3D.get_closest_point_to_segment(points[v],rest[b].origin,KiwiRigMath.tail(bones[b],rest[b]))
			var d := points[v].distance_to(nearest); distances[b]=d; island[b]=minf(float(island.get(b,INF)),d)
		values.append(distances)
	var closest_island := {}
	for distances: Dictionary in island_distance:
		for bone: int in distances: closest_island[bone]=minf(float(closest_island.get(bone,INF)),float(distances[bone]))
	for v in points.size():
		var scores := {}; var candidates: Dictionary=island_distance[shape.islands[v]]; var nearest := INF
		for d: float in candidates.values(): nearest=minf(nearest,d)
		for b: int in values[v]:
			var distance := float(values[v][b]); var radius := maxf(float(bones[b].get("radius",.25)),.0001)
			# A bone primarily belongs to its closest connected surface island.
			# Nearby disconnected limbs cannot steal influence just because their
			# coarse triangles happen to have a large average edge length.
			if method=="Smooth" and shape.groups.size()>1 and float(candidates[b])>float(closest_island[b])+maxf(.0001,minf(float(shape.edge)*.1,radius*.1)): continue
			if method=="Envelope": scores[b]=exp(-pow(distance/radius,2.)*2.)
			else: scores[b]=1./pow(distance+maxf(.0001,float(shape.edge)*.5),3.)
		var peak := 0.
		for score: float in scores.values(): peak=maxf(peak,score)
		if peak<=1.e-30:
			var best := 0; var distance := INF
			for b: int in values[v]:
				if float(values[v][b])<distance: best=b; distance=float(values[v][b])
			scores={best:1.}
		else:
			# Scores are relative. Keep distant/tiny envelopes from hitting the
			# normalization epsilon and spuriously assigning every vertex to root.
			for b: int in scores: scores[b]=float(scores[b])/peak
		values[v]=result.normalized(scores)
	if method=="Smooth":
		# Connectivity-aware Jacobi smoothing. Nothing propagates between islands.
		var anchors: Array[Dictionary]=values.duplicate(true)
		for step in clampi(iterations,0,24):
			if cancellation!=null and cancellation.is_cancelled(): return null
			var next: Array[Dictionary]=[]
			for v in points.size():
				var sum := {}; var adjacent: PackedInt32Array=shape.neighbors[v]
				for b: int in anchors[v]: sum[b]=float(anchors[v][b])*.35
				for other in adjacent:
					for b: int in values[other]: sum[b]=float(sum.get(b,0.))+float(values[other][b])*.65/maxi(1,adjacent.size())
				next.append(result.normalized(sum))
			values=next
	for mapping: PackedInt32Array in shape.surfaces:
		var ids := PackedInt32Array(); ids.resize(mapping.size()*result.influence_count); var amounts := PackedFloat32Array(); amounts.resize(ids.size())
		for v in mapping.size():
			var weights: Dictionary=values[mapping[v]]; var order := weights.keys()
			order.sort_custom(func(a: Variant,b: Variant) -> bool: return float(weights[a])>float(weights[b]))
			for k in mini(order.size(),result.influence_count): ids[v*result.influence_count+k]=int(order[k]); amounts[v*result.influence_count+k]=float(weights[order[k]])
		result.indices.append(ids); result.weights.append(amounts)
	return result

static func corrected(binding: KiwiRigBinding, surface: int, vertex: int, bone: int, mode: String, amount: float, neighbor_values: Dictionary={}) -> Dictionary:
	var values := binding.vertex(surface,vertex)
	if binding.locked_bones.has(binding.bone_ids[bone]): return values
	var old := float(values.get(bone,0.)); var next := old
	match mode:
		"Add": next=minf(1.,old+amount)
		"Subtract": next=maxf(0.,old-amount)
		"Replace": next=clampf(amount,0.,1.)
		"Smooth":
			var blended := values.duplicate()
			for b: int in neighbor_values: blended[b]=lerpf(float(values.get(b,0.)),float(neighbor_values[b]),amount)
			return binding.normalized(blended,bone)
		"Clear": next=0.
	var fixed := 0.; var remainder := 0.
	for b: int in values:
		if b==bone: continue
		if binding.locked_bones.has(binding.bone_ids[b]): fixed+=float(values[b])
		else: remainder+=float(values[b])
	next=minf(next,1.-fixed); values[bone]=next
	for b: int in values:
		if b!=bone and not binding.locked_bones.has(binding.bone_ids[b]): values[b]=float(values[b])/remainder*maxf(0.,1.-fixed-next) if remainder>0. else 0.
	if remainder<=.000001 and fixed+next<.99999:
		for b in binding.bone_ids.size():
			if b!=bone and not binding.locked_bones.has(binding.bone_ids[b]): values[b]=1.-fixed-next; break
	return binding.normalized(values,bone)
