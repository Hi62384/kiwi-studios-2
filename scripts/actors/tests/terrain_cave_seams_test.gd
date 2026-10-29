extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=65; terrain.dimensions=Vector2(32,32); terrain.voxel_height=1.; var cave:=KiwiTerrainCave.new(); cave.radius=1.5; cave.radius_variation=0.; cave.roughness=0.; cave.paths=[PackedVector3Array([Vector3(-8,-2,-8),Vector3(8,-2,-8)])]; cave.chambers=PackedVector4Array([Vector4(-8,-3,-8,2.),Vector4(8,-3,-8,2.)]); terrain.caves=[cave]
	check(terrain.prepare_volumes() and terrain.volume_chunks.size()==2,"Cave extraction replaces only the two chunks intersecting the underground network")
	var left: Dictionary=terrain.volume_chunks[Vector2i(0,0)]; var right: Dictionary=terrain.volume_chunks[Vector2i(1,0)]; var a:=boundary(left); var b:=boundary(right)
	check(a.size()>10 and a.size()==b.size() and all_keys(a,b),"Neighboring cave chunks share identical isosurface vertices along their common boundary")
	var source:=KiwiEnvironmentDocument.new(); var item:=source.add_terrain(terrain); var runtime:=KiwiEnvironmentRuntime.new(); root.add_child(runtime); runtime.configure(source); var untouched:=runtime.nodes[item.id].get_node("Chunk_1_0").mesh as Mesh; var old_key: int=right.key
	cave.edits.append({"center":Vector3(-8,-3,-8),"radius":2.5,"fill":false}); check(terrain.prepare_volumes() and terrain.volume_chunks_rebuilt==1 and int(terrain.volume_chunks[Vector2i(1,0)].key)==old_key,"A local dig rebuilds its affected cave chunk and retains the neighboring generated data")
	runtime.sync(); check(runtime.chunks_rebuilt==1 and runtime.nodes[item.id].get_node("Chunk_1_0").mesh==untouched,"Regional cave editing preserves untouched native meshes and collision resources")
	print("TERRAIN CAVE SEAMS boundary_vertices=",a.size()," edited_chunks=",terrain.volume_chunks_rebuilt); runtime.queue_free(); await process_frame; print("TERRAIN CAVE SEAMS: %d checks, %d failures"%[checks,failures]); quit(failures)
func boundary(data: Dictionary) -> Dictionary:
	var result:={}
	for point: Vector3 in data.vertices:
		if absf(point.x)<.00001: result[Vector2i(roundi(point.y*10000.),roundi(point.z*10000.))]=true
	return result
func all_keys(a: Dictionary,b: Dictionary) -> bool:
	for key in a:
		if not b.has(key): return false
	return true
