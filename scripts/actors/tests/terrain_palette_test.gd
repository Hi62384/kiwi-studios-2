extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=33; terrain.prepare(); terrain.biomes=KiwiTerrainBiomes.new(); var count:=preload("res://Workspaces/EnvironmentWorkspace/terrain/terrain_biome_render.gd").capacity()
	for index in count:
		var rule:=KiwiTerrainBiomes.starter(0); rule.id="layer"+str(index); var material:=StandardMaterial3D.new(); material.albedo_color=Color.from_hsv(float(index)/count,.7,.8); rule.materials=[material]; terrain.biomes.definitions.append(rule)
	terrain.prepare_biomes()
	for id: String in terrain.biome_data.weights: var values: PackedFloat32Array=terrain.biome_data.weights[id]; values.fill(1./count); terrain.biome_data.weights[id]=values
	var document:=KiwiEnvironmentDocument.new(); var item:=document.add_terrain(terrain); var runtime:=KiwiEnvironmentRuntime.new(); root.add_child(runtime); runtime.configure(document); var material: ShaderMaterial=runtime.nodes[item.id].get_node("Chunk_0_0").get_surface_override_material(0)
	check(material!=null and runtime.errors.is_empty() and material.get_shader_parameter("layer%d_color"%(count+1))!=null,"The renderer compiles and binds every supported biome material without silently dropping its last layer")
	var image: Image=(material.get_shader_parameter("weights%d"%((count+1)/4)) as Texture2D).get_image(); var color:=image.get_pixel(16,16); check(absf(color[(count+1)%4]-1./count)<.00001,"Weights beyond the first RGBA texture are uploaded with the correct channel mapping")
	if DisplayServer.get_name()!="headless":
		for i in 3: await RenderingServer.frame_post_draw
	print("TERRAIN PALETTE biome_materials=",count," total_PBR_layers=",count+2); runtime.queue_free(); await process_frame; print("TERRAIN PALETTE: %d checks, %d failures"%[checks,failures]); quit(failures)
