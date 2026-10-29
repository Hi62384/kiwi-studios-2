extends RefCounted
## Regional GPU instance buffers; native authored poses and collision stay complete.
static func install(runtime: KiwiEnvironmentRuntime,node: Node3D,result: Dictionary,source: KiwiEnvironmentScatter) -> void:
	var state: Dictionary={"packets":{},"bins":{},"active":{},"rules":source,"radius":0.}
	for palette: int in result.batches:
		var asset:=KiwiEnvironmentAssets.load_scatter_parts(source.palette[palette].get("source",""))
		if not str(asset.error).is_empty(): runtime.errors.append(str(asset.error)); continue
		for part_index in asset.parts.size():
			var part: Dictionary=asset.parts[part_index]; var clusters: Dictionary={}; var mesh: Mesh=runtime._scatter_mesh(part.mesh,source.lod_enabled); var original: AABB=mesh.get_aabb()
			for pose: Transform3D in result.batches[palette]:
				var cell:=Vector2i(floori(pose.origin.x/source.render_cluster_size),floori(pose.origin.z/source.render_cluster_size))
				if not clusters.has(cell): clusters[cell]=[]
				clusters[cell].append(pose*(part.transform as Transform3D))
			for cell: Vector2i in clusters:
				var identity:=str(palette)+":"+str(part_index)+":"+str(cell.x)+":"+str(cell.y); var poses: Array=clusters[cell]; var bounds: AABB=poses[0]*original
				for pose: Transform3D in poses: bounds=bounds.merge(pose*original)
				var center:=Vector3((cell.x+.5)*source.render_cluster_size,0.,(cell.y+.5)*source.render_cluster_size); state.radius=maxf(float(state.radius),bounds.get_center().distance_to(center)+bounds.size.length()*.5)
				state.packets[identity]={"mesh":mesh,"poses":poses,"center":center,"bounds":bounds}
				if not state.bins.has(cell): state.bins[cell]=[]
				state.bins[cell].append(identity)
	node.set_meta("scatter_stream",state); runtime.stream_nodes[node.get_instance_id()]=node; refresh(runtime,node)
static func refresh(runtime: KiwiEnvironmentRuntime,node: Node3D) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree(): return
	var state: Dictionary=node.get_meta("scatter_stream",{})
	if state.is_empty(): return
	var source: KiwiEnvironmentScatter=state.rules; var camera:=runtime.get_viewport().get_camera_3d()
	if camera==null and is_instance_valid(runtime.priority_camera): camera=runtime.priority_camera
	var candidates: Array=[]; var wanted: Dictionary={}; var position:=Vector3.ZERO; var limit:=source.render_distance+maxf(8.,source.render_cluster_size*.5); var scale:=node.global_basis.get_scale().abs(); var invertible:=absf(node.global_basis.determinant())>.000001
	if not node.is_visible_in_tree(): pass
	elif camera==null or not invertible:
		candidates=state.packets.keys()
	else:
		position=camera.global_position; var local:=node.global_transform.affine_inverse()*position; var radius:=(limit/maxf(.0001,minf(scale.x,minf(scale.y,scale.z)))+float(state.radius))/source.render_cluster_size; var reach:=ceili(radius)+1; var center:=Vector2i(floori(local.x/source.render_cluster_size),floori(local.z/source.render_cluster_size))
		if float(reach*2+1)*float(reach*2+1)>state.bins.size()*2:
			for bin: Array in state.bins.values(): candidates.append_array(bin)
		else:
			for z in range(center.y-reach,center.y+reach+1):
				for x in range(center.x-reach,center.x+reach+1): candidates.append_array(state.bins.get(Vector2i(x,z),[]))
	for identity: String in candidates:
		var packet: Dictionary=state.packets[identity]
		if camera!=null and invertible:
			var bounds: AABB=node.global_transform*(packet.bounds as AABB); var closest:=position.clamp(bounds.position,bounds.end); var threshold:=limit+source.render_cluster_size*.5 if state.active.has(identity) else limit
			if closest.distance_squared_to(position)>threshold*threshold: continue
		wanted[identity]=true
		if state.active.has(identity): continue
		var batch:=MultiMeshInstance3D.new(); var mesh:=MultiMesh.new(); mesh.transform_format=MultiMesh.TRANSFORM_3D; mesh.mesh=packet.mesh; mesh.instance_count=packet.poses.size(); var center: Vector3=packet.center
		for index in packet.poses.size():
			var pose: Transform3D=packet.poses[index]; pose.origin-=center; mesh.set_instance_transform(index,pose)
		batch.position=center; batch.multimesh=mesh; batch.lod_bias=source.lod_bias; batch.visibility_range_end=source.render_distance; batch.visibility_range_end_margin=source.render_distance*.15; batch.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF; node.add_child(batch); state.active[identity]=batch
		preload("res://Workspaces/ModelWorkspace/natural_render.gd").time(batch,runtime.preview_time)
	for identity: String in state.active.keys():
		if wanted.has(identity): continue
		var batch: MultiMeshInstance3D=state.active[identity]
		if is_instance_valid(batch): batch.free()
		state.active.erase(identity)
