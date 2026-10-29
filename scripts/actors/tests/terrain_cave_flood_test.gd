extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=33; terrain.dimensions=Vector2(16,16); terrain.voxel_height=.25; terrain.prepare()
	for z in 33:
		for x in 33: terrain.edits[x+z*33]=(float(x)/32.-.5)*16.*.4+1.2
	var cave:=KiwiTerrainCave.new(); cave.radius=1.5; cave.radius_variation=0.; cave.roughness=0.; cave.paths=[PackedVector3Array([Vector3(-7,-1,0),Vector3(4,-1,0)])]; cave.chambers=PackedVector4Array([Vector4(4,-4,4,1)]); terrain.caves=[cave]; terrain.hydrology=KiwiTerrainHydrology.new(); terrain.hydrology.automatic_rivers=false; terrain.hydrology.automatic_lakes=false; terrain.hydrology.ocean_enabled=true; terrain.hydrology.sea_level=0.
	var started:=Time.get_ticks_usec(); var prepared:=terrain.prepare_water(); check(prepared and terrain.water_valid() and terrain.water_data.has("cave_volume"),"Ocean water enters actual connected cave air beneath an intact terrain roof")
	if not prepared: print(terrain.water_status); quit(failures); return
	var sample:=terrain.water_at(Vector3(3,-1,0)); check(not sample.is_empty() and sample.get("cave",false) and sample.inside and absf((sample.surface as Vector3).y)<.001,"Underground queries find the hydrostatic water level and submerged volume")
	check(terrain.water_at(Vector3(4,-4,4)).is_empty(),"A sealed underground chamber stays dry even when it is below ocean level")
	var interior_surface:=false
	for point: Vector3 in terrain.water_data.mesh.vertices: interior_surface=interior_surface or (point.x>1. and absf(point.z)<1.5 and absf(point.y)<.001)
	check(interior_surface,"Cave water adds an actual free surface under the roof instead of only flooding metadata")
	check(terrain.water_data.cave_volume.voxels<=terrain.voxel_cell_budget and terrain.water_data.cave_volume.heads.size()==terrain.water_data.cave_volume.voxels,"Underground water connectivity respects its explicit voxel budget")
	var path:="user://cave-flood.tres"; ResourceSaver.save(terrain,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentTerrain; var reopened:=loaded.water_at(Vector3(3,-1,0)); check(loaded.water_valid() and reopened.get("inside",false) and loaded.water_data.cave_volume.heads==terrain.water_data.cave_volume.heads,"Saving and reopening preserves connected underground water fields and queries")
	var original:=terrain.water_data.duplicate(true); terrain.voxel_cell_budget=1; check(not terrain.prepare_water() and terrain.water_data==original and "budget" in terrain.water_status,"A failed underground-water budget retains the previous complete data instead of publishing partial fields")
	if DisplayServer.get_name()!="headless":
		terrain.voxel_cell_budget=500000; terrain.prepare_water(); terrain.prepare_volumes(); var document:=KiwiEnvironmentDocument.new(); document.add_terrain(terrain); var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(240,180); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); var runtime:=KiwiEnvironmentRuntime.new(); view.add_child(runtime); runtime.configure(document); var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color.BLACK; environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=1.; view.add_child(environment); var camera:=Camera3D.new(); view.add_child(camera); camera.position=Vector3(3,.3,0); camera.look_at(Vector3(2,0,0)); camera.current=true
		for i in 5: await RenderingServer.frame_post_draw
		var image:=view.get_texture().get_image(); var blue:=0
		for y in image.get_height():
			for x in image.get_width(): var color:=image.get_pixel(x,y); blue+=1 if color.b>color.r*1.2 and color.b>.15 else 0
		check(blue>100,"A native camera inside the covered tunnel renders its blue underground water surface"); view.queue_free(); await process_frame
	DirAccess.remove_absolute(path); print("TERRAIN CAVE FLOOD milliseconds=",float(Time.get_ticks_usec()-started)/1000.); print("TERRAIN CAVE FLOOD: %d checks, %d failures"%[checks,failures]); quit(failures)
