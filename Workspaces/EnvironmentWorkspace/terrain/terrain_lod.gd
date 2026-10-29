extends RefCounted
## Godot's native mesh optimizer keeps surface borders locked. All LODs retain
## those border vertices, so mixed-detail neighboring chunks still meet exactly.
static func prepare(source: ArrayMesh) -> ArrayMesh:
	if source==null or source.get_surface_count()==0: return source
	var importer:=ImporterMesh.new(); var original:=0
	for surface in source.get_surface_count():
		var arrays:=source.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_INDEX]==null:
			var builder:=SurfaceTool.new(); builder.create_from(source,surface); builder.index(); arrays=builder.commit_to_arrays()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},source.surface_get_material(surface)); var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array(); original+=indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var started:=Time.get_ticks_usec(); importer.generate_lods(25.,60.,[]); var result:=importer.get_mesh(); var levels: Array[Dictionary]=[]
	for surface in importer.get_surface_count():
		var data:={}
		for level in importer.get_surface_lod_count(surface): data[importer.get_surface_lod_size(surface,level)]=importer.get_surface_lod_indices(surface,level)
		levels.append(data)
	for name in source.get_meta_list(): result.set_meta(name,source.get_meta(name))
	result.set_meta("environment_lods",levels); result.set_meta("environment_lod_base_indices",original); result.set_meta("environment_lod_ms",float(Time.get_ticks_usec()-started)/1000.); return result
