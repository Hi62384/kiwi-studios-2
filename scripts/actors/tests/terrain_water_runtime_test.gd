extends "res://scripts/actors/tests/surface_growth_test.gd"
const Job=preload("res://Workspaces/EnvironmentWorkspace/environment_generation_job.gd")
func run() -> void:
	var source:=KiwiEnvironmentTerrain.new(); source.resolution=33; source.dimensions=Vector2(16,16); source.base_height=-1.; source.hydrology=KiwiTerrainHydrology.new(); source.hydrology.automatic_rivers=false; source.hydrology.automatic_lakes=false; source.hydrology.ocean_enabled=true
	var job:=Job.new(); job.start(source,{},false)
	while not job.complete(): await process_frame
	job.collect(); var terrain: KiwiEnvironmentTerrain=job.terrain
	check(job.error.is_empty() and terrain.water_valid() and job.mesh!=null and source.water_data.is_empty(),"Worker publishes complete saved hydrology without modifying its authored source")
	var document:=KiwiEnvironmentDocument.new(); var item:=document.add_terrain(terrain); var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(240,180); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); var runtime:=KiwiEnvironmentRuntime.new(); view.add_child(runtime); runtime.configure(document)
	var water:=runtime.nodes[item.id].get_node("Water") as MeshInstance3D; var chunk:=runtime.nodes[item.id].get_node("Chunk_0_0") as MeshInstance3D
	check(water.mesh.get_surface_count()==1 and water.get_child_count()==0 and water.get_meta("kiwi_physics_excluded",false),"Native water uses real surface geometry and remains separate from solid terrain collision")
	check((chunk.get_node("Collision/Shape").shape as ConcavePolygonShape3D).get_faces()==chunk.mesh.get_faces(),"Carved solid terrain retains matching collision geometry")
	var sample:=terrain.water_at(Vector3(0,-.5,0)); check(not sample.is_empty() and sample.inside and absf(sample.depth-1.)<.0001 and sample.surface==Vector3.ZERO,"Water queries return actual local surface, depth and submerged state")
	var mesh:=water.mesh; terrain.hydrology.water_color=Color(1,.1,.1); runtime.sync(); check(water.mesh==mesh and (water.material_override as ShaderMaterial).get_shader_parameter("liquid_color")==terrain.hydrology.water_color,"Appearance changes update the material without rebuilding water geometry")
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color.BLACK; environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=1.; view.add_child(environment); var camera:=Camera3D.new(); view.add_child(camera); camera.position=Vector3(0,6,6); camera.look_at(Vector3.ZERO); camera.current=true
	if DisplayServer.get_name()!="headless":
		for i in 5: await RenderingServer.frame_post_draw
		var pixel:=view.get_texture().get_image().get_pixel(120,90); check(pixel.r>pixel.b*1.3 and pixel.r>.1,"A native camera renders the colored water surface with the shared liquid shader")
	var path:="user://terrain-water.tres"; ResourceSaver.save(document,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument; var reopened:=loaded.terrain(item.id)
	check(reopened.water_valid() and reopened.water_data.mesh.indices==terrain.water_data.mesh.indices,"Saving and reopening retains valid water geometry and editable drainage settings")
	var actor:=preload("res://Workspaces/EnvironmentWorkspace/environment_actor.gd").new(); root.add_child(actor); actor.source_document=document; actor.content.configure(document); actor.set_active(true); actor.position=Vector3(10,2,0); actor.scale=Vector3.ONE*2.; var world_query:=actor.water_at(Vector3(10,1,0))
	check(not world_query.is_empty() and world_query.inside and (world_query.surface as Vector3).is_equal_approx(Vector3(10,2,0)) and is_equal_approx(float(world_query.depth),2.),"Scene actor water surface, bottom and depth respect the full instantiated environment transform")
	actor.set_timeline_time(2.5); var scene_water:=actor.content.nodes[item.id].get_node("Water") as MeshInstance3D
	check(is_equal_approx(float((scene_water.material_override as ShaderMaterial).get_shader_parameter("liquid_time")),2.5),"Scene water waves consume manually controlled timeline time")
	actor.set_timeline_time(.25); check(is_equal_approx(float((scene_water.material_override as ShaderMaterial).get_shader_parameter("liquid_time")),.25),"Rewinding updates liquid time exactly rather than relying on wall-clock shader time")
	actor.content.progressive=true; actor.content._process(.5); check(is_equal_approx(float((scene_water.material_override as ShaderMaterial).get_shader_parameter("liquid_time")),.25),"Progressive scene uploads never advance paused water animation away from the timeline")
	actor.queue_free()
	var heights:=terrain.water_delta.duplicate(); check(terrain.prepare_water() and terrain.water_delta==heights,"Reusing derived water data never applies channel carving twice")
	terrain.hydrology.enabled=false; runtime.sync(); check(not water.visible and terrain.water_at(Vector3.ZERO).is_empty(),"Disabling water removes its preview and queries")
	view.queue_free(); await process_frame; DirAccess.remove_absolute(path); print("TERRAIN WATER RUNTIME: %d checks, %d failures"%[checks,failures]); quit(failures)
