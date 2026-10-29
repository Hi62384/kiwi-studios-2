extends RefCounted
## Generated render LODs and wood/rock collision share the authored mesh.
static func prepare(source: ArrayMesh,item: Resource) -> ArrayMesh:
	if not preload("res://Workspaces/ModelWorkspace/natural_generator.gd").accepts(item.generator): return source
	var collision:=PackedVector3Array(); var kind: String=item.generator
	if not kind.begins_with("Plant"):
		var topology: KiwiModelMesh=KiwiModelModifiers.evaluate(item)
		for f in topology.faces.size():
			if topology.materials[f]!=0: continue
			var triangles:=topology.triangles(f)
			for index in triangles: collision.append(topology.vertices[topology.faces[f][index]])
	source.set_meta("kiwi_collision_faces",collision)
	var optimized:=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_lod.gd").prepare(source); var levels: Array=optimized.get_meta("environment_lods",[]); var result:=ArrayMesh.new()
	for surface in optimized.get_surface_count():
		var material:=optimized.surface_get_material(surface)
		# A generic simplifier can remove every disconnected leaf/blade. Keep actual
		# foliage coverage until a silhouette-preserving clustered LOD is available.
		if material!=null and material.get_meta("kiwi_natural_foliage",false): levels[surface]={}
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,optimized.surface_get_arrays(surface),[],levels[surface]); result.surface_set_material(surface,material)
	for name in optimized.get_meta_list(): result.set_meta(name,optimized.get_meta(name))
	result.set_meta("environment_lods",levels); return result

static func time(root: Node,value: float,visited: Variant=null) -> void:
	if not is_instance_valid(root): return
	var seen: Dictionary={} if visited==null else visited
	var mesh: Mesh=root.mesh if root is MeshInstance3D else (root.multimesh.mesh if root is MultiMeshInstance3D and root.multimesh!=null else null)
	if mesh!=null:
		for surface in mesh.get_surface_count():
			var material: Material=root.get_active_material(surface) if root is MeshInstance3D else (root.material_override if root.material_override!=null else mesh.surface_get_material(surface))
			if material is ShaderMaterial and not seen.has(material.get_instance_id()):
				seen[material.get_instance_id()]=true; material.set_meta("kiwi_last_time",value)
				if material.has_meta("kiwi_timeline_link"): material.get_meta("kiwi_timeline_link").synchronize_parameters()
				var uniform:=str(material.get_meta("kiwi_time_uniform",""))
				if not uniform.is_empty(): material.set_shader_parameter(uniform,value)
	for child in root.get_children(): time(child,value,seen)
