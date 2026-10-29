extends "res://scripts/actors/tests/surface_growth_test.gd"
const Job=preload("res://Workspaces/EnvironmentWorkspace/environment_generation_job.gd")
func run() -> void:
	var source:=KiwiEnvironmentTerrain.new(); source.resolution=65; source.dimensions=Vector2(32,32); source.generation=KiwiTerrainGenerator.preset(2); source.generation.layers=[{"type":"Mountain range","height":8.,"width":8.,"length":16.}]; source.amplitude=8.; source.base_height=3.; source.geology=3; source.biomes=KiwiTerrainBiomes.new(); source.biomes.sea_temperature=5.; source.biomes.altitude_lapse=.5
	for index in [0,1,7,12,13]:
		var rule:=KiwiTerrainBiomes.starter(index); var material:=StandardMaterial3D.new(); material.albedo_color=[Color.GREEN,Color.DARK_GREEN,Color.WHITE,Color.BISQUE,Color.DARK_GRAY][source.biomes.definitions.size()]; rule.materials=[material]; source.biomes.definitions.append(rule)
	source.biomes.definitions.append(KiwiTerrainBiomes.cave_starter(0)); source.hydrology=KiwiTerrainHydrology.new(); source.hydrology.ocean_enabled=true; source.hydrology.sea_level=7.; source.hydrology.catchment_threshold=4.; var cave:=KiwiTerrainCave.new(); cave.radius=1.5; cave.roughness=0.; cave.radius_variation=0.; cave.paths=[PackedVector3Array([Vector3(-14,5,0),Vector3(0,2,0)])]; cave.chambers=PackedVector4Array([Vector4(0,2,0,2)]); source.caves=[cave]; source.prepare(); source.apply_samples({18+18*65:2.}); source.apply_material_samples({18+18*65:.75}); var job:=Job.new(); job.start(source,{},false)
	while not job.complete(): await process_frame
	job.collect(); var terrain: KiwiEnvironmentTerrain=job.terrain; check(job.error.is_empty() and terrain.water_valid() and terrain.biomes_valid() and terrain.volumes_valid() and terrain.cave_biomes_valid(),"The combined mountains, caves, water, geology, biomes and paint pipeline completes coherently")
	if not job.error.is_empty(): print(job.error); quit(failures); return
	var document:=KiwiEnvironmentDocument.new(); var item:=document.add_terrain(terrain); var paint:=StandardMaterial3D.new(); paint.albedo_color=Color.SADDLE_BROWN; document.component_settings[item.id].paint_material=paint; document.workspace_state={"view":{"target":Vector3(1,2,3),"distance":15.},"selected":[item.id],"property_scrolls":{item.id:120}}; var signature:=terrain.signature(); var path:="user://terrain-acceptance.res"; ResourceSaver.save(document,path,ResourceSaver.FLAG_COMPRESS); var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument; var loaded:=reopened.terrain(item.id)
	check(loaded.signature()==signature and loaded.water_valid() and loaded.biomes_valid() and loaded.volumes_valid() and loaded.cave_biomes_valid() and reopened.workspace_state==document.workspace_state,"A combined environment reopens with all authored sources, valid generated stages, materials and editor state")
	check(loaded.edits[18+18*65]==2. and loaded.material_mask[18+18*65]==.75 and not loaded.volume_chunks.is_empty() and not loaded.cave_biome_data.is_empty(),"Saved sculpt, paint and underground fields retain their actual independent data")
	var runtime:=KiwiEnvironmentRuntime.new(); root.add_child(runtime); runtime.configure(reopened); check(runtime.errors.is_empty() and runtime.nodes[item.id].has_node("Water") and runtime.chunks_rebuilt==4,"The combined saved resource renders all native terrain chunks, cave materials and aligned water without warnings")
	var heights:=PackedFloat32Array(); heights.resize(33*33)
	for z in 33:
		for x in 33: heights[x+z*33]=8.-z*.4+pow(float(x)-16.,2.)*.025
	var water:=KiwiTerrainHydrology.new(); water.automatic_lakes=false; water.catchment_threshold=8.; water.rainfall_variation=0.; var network:=water.generate(heights,33,Vector2(32,32),41); var visited:={}; var joins:=0; var exact:=true
	for river: Dictionary in network.paths:
		var points: PackedVector3Array=river.points; var end:=points[-1]
		for point: Vector3 in visited:
			if absf(point.x-end.x)<.0001 and absf(point.z-end.z)<.0001: joins+=1; exact=exact and absf(point.y-end.y)<.00001; break
		for point in points: visited[point]=true
	check(joins>0 and exact,"Multiple tributaries meet earlier river paths at the exact same final water height")
	runtime.queue_free(); await process_frame; DirAccess.remove_absolute(path); print("TERRAIN ACCEPTANCE pipeline_ms=",job.elapsed_ms," tributary_joins=",joins); print("TERRAIN ACCEPTANCE: %d checks, %d failures"%[checks,failures]); quit(failures)
