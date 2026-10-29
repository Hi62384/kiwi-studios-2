extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=33; terrain.base_height=3.; terrain.dimensions=Vector2(16,16); terrain.hydrology=KiwiTerrainHydrology.new(); terrain.hydrology.automatic_rivers=false; terrain.hydrology.automatic_lakes=false; terrain.hydrology.manual_rivers=[{"id":"fall","points":PackedVector3Array([Vector3(0,3,-4),Vector3(0,-2,4)]),"follow_terrain":false,"width":2.,"depth":1.}]; check(terrain.prepare_water() and terrain.water_data.waterfalls.size()==1,"A real drop in an authored river creates waterfall geometry and source metadata")
	var document:=KiwiEnvironmentDocument.new(); var item:=document.add_terrain(terrain); var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(240,180); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); var actor:=preload("res://Workspaces/EnvironmentWorkspace/environment_actor.gd").new(); view.add_child(actor); actor.source_document=document; actor.content.configure(document); actor.set_active(true); var water:=actor.content.nodes[item.id].get_node("Water") as MeshInstance3D; var spray:=water.get_node("Spray") as MultiMeshInstance3D
	check(spray.multimesh.instance_count==terrain.hydrology.spray_per_fall and spray.get_meta("kiwi_physics_excluded",false),"Waterfall spray is one bounded native instanced batch, excluded from terrain collision")
	var custom:=spray.multimesh.get_instance_custom_data(0); var material:=spray.material_override as ShaderMaterial; actor.set_timeline_time(.4); check(is_equal_approx(float(material.get_shader_parameter("liquid_time")),.4),"Waterfall spray consumes the exact scene timeline time")
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color.BLACK; environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=1.; view.add_child(environment); var camera:=Camera3D.new(); view.add_child(camera); camera.position=Vector3(4,1,7); camera.look_at(Vector3(0,-1,4)); camera.current=true
	if DisplayServer.get_name()!="headless":
		for i in 5: await RenderingServer.frame_post_draw
		var original:=view.get_texture().get_image().get_data(); actor.set_timeline_time(.9)
		for i in 3: await RenderingServer.frame_post_draw
		var moved:=view.get_texture().get_image().get_data(); actor.set_timeline_time(.4)
		for i in 3: await RenderingServer.frame_post_draw
		var replayed:=view.get_texture().get_image().get_data(); check(original!=moved and original==replayed,"Real rendered waterfall frames change with time and reproduce exactly after rewind")
	actor.content.sync(); check(spray.multimesh.get_instance_custom_data(0)==custom,"Unchanged waterfall sources preserve their seeded spray distribution")
	terrain.hydrology.waterfall_spray=false; actor.content.sync(); check(not spray.visible,"Waterfall spray can be disabled without removing its river source")
	view.queue_free(); await process_frame; print("TERRAIN WATERFALL: %d checks, %d failures"%[checks,failures]); quit(failures)
