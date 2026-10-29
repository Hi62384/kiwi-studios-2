extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.amplitude=4.; terrain.prepare(); var mesh:=terrain.chunk_mesh(Vector2i.ZERO); var arrays:=mesh.surface_get_arrays(0); var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]; var base: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]; var borders:={}
	for index in base:
		var point:=vertices[index]
		if is_equal_approx(point.x,-16.) or is_equal_approx(point.x,0.) or is_equal_approx(point.z,-16.) or is_equal_approx(point.z,0.): borders[index]=true
	var levels: Array=mesh.get_meta("environment_lods"); var valid: bool=not levels[0].is_empty(); var smallest:=base.size()
	for indices: PackedInt32Array in levels[0].values():
		var kept:={}; smallest=mini(smallest,indices.size())
		for index in indices:
			valid=valid and index>=0 and index<vertices.size()
			if borders.has(index): kept[index]=true
		valid=valid and kept.size()==borders.size()
	check(valid and smallest<base.size()/2,"Native terrain LODs reduce triangles while retaining every shared boundary vertex")
	var source:=KiwiEnvironmentDocument.new(); var item:=source.add_terrain(terrain); var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(400,300); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); var camera:=Camera3D.new(); view.add_child(camera); camera.position=Vector3(0,25,25); camera.look_at(Vector3.ZERO); camera.current=true; var runtime:=KiwiEnvironmentRuntime.new(); view.add_child(runtime); runtime.configure(source); var chunk:=runtime.nodes[item.id].get_node("Chunk_0_0") as MeshInstance3D; var shape:=chunk.get_node("Collision/Shape").shape as ConcavePolygonShape3D
	check(shape.get_faces().size()==32*32*6,"Physics collision retains full terrain triangles independently from render LOD")
	terrain.lod_bias=.5; terrain.render_distance=100.; runtime.sync(); check(is_equal_approx(chunk.lod_bias,.5) and is_equal_approx(chunk.visibility_range_end,100.) and chunk.visibility_range_end_margin>0.,"Terrain detail and render-distance controls reach native geometry settings with a fade margin")
	if DisplayServer.get_name()!="headless":
		terrain.render_distance=0.; runtime.sync(); view.mesh_lod_threshold=0.
		for index in 5: await RenderingServer.frame_post_draw
		var high:=view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME); view.mesh_lod_threshold=1000.
		for index in 5: await RenderingServer.frame_post_draw
		var low:=view.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		check(high>2000 and low<high*.7,"Actual renderer submits fewer terrain primitives when lower detail levels are selected"); print("TERRAIN LOD native_primitives_full=",high," coarse=",low)
	var progressive:=KiwiEnvironmentRuntime.new(); progressive.progressive=true; progressive.upload_budget_usec=1; progressive.priority_camera=camera; view.add_child(progressive); camera.position=Vector3(14,8,14); progressive.configure(source); progressive._process(0.)
	check(progressive.nodes[item.id].get_node("Chunk_1_1").mesh!=null and progressive.chunks_rebuilt==1,"Progressive terrain uploads prioritize the chunk nearest the editing camera")
	terrain.lod_enabled=false; var full:=terrain.chunk_mesh(Vector2i.ZERO); check(not full.has_meta("environment_lods") and full.get_faces().size()==mesh.get_faces().size(),"Disabling automatic LOD restores the full source representation")
	print("TERRAIN LOD base_indices=",base.size()," smallest_indices=",smallest," protected_border_vertices=",borders.size()," optimize_ms=",mesh.get_meta("environment_lod_ms")); view.queue_free(); await process_frame; print("TERRAIN LOD: %d checks, %d failures"%[checks,failures]); quit(failures)
