extends "res://scripts/actors/tests/growth_material_test.gd"
func run() -> void:
	var data:=KiwiSurfaceGrowthData.new(); data.settings=KiwiSurfaceGrowth.defaults(2); data.settings.merge({"length":1.,"width":.6,"curvature":0.,"variation":0.,"orientation_variation":0.},true); data.source_points=PackedVector3Array([Vector3(-.5,0,0),Vector3(.5,0,0),Vector3(-.5,0,1)]); data.generation_key=1
	data.roots.append({"id":0,"triangle":Vector3i(0,1,2),"bary":Vector3(.3,.4,.3),"normal":Vector3.UP,"random":Vector4(.5,.5,.5,.5),"position":Vector3(-.1,0,.3),"density_rank":0.,"face":0})
	data.appearance=KiwiGrowthMaterial.new(); data.appearance.root_color=Color.WHITE; data.appearance.tip_color=Color.WHITE; data.appearance.specular=0.; data.appearance.feather_detail=0.; data.appearance.shaft_color=Color.BLUE
	var component:=KiwiModelComponent.new(); component.growth=data
	var viewport:=SubViewport.new(); viewport.own_world_3d=true; viewport.size=Vector2i(400,400); viewport.msaa_3d=Viewport.MSAA_4X; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var instance:=KiwiSurfaceGrowthInstance.new(); viewport.add_child(instance); instance.configure(component,true)
	var camera:=Camera3D.new(); viewport.add_child(camera); camera.position=Vector3(-.1,.5,3.); camera.look_at(Vector3(-.1,.5,.3)); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=1.3; camera.current=true
	var environment:=WorldEnvironment.new(); viewport.add_child(environment); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color.BLACK; environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=1.
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw; var plain:=viewport.get_texture().get_image()
	instance.data.appearance.feather_pattern=1; instance.data.appearance.feather_pattern_color=Color.RED; instance.data.appearance.feather_pattern_width=.5; instance.update_growth()
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw; var marked:=viewport.get_texture().get_image(); var red:=0; var blue:=0
	for y in range(0,400,2):
		for x in range(0,400,2):
			var color:=marked.get_pixel(x,y)
			if color.r>color.g+.1 and color.r>color.b+.1: red+=1
			if color.b>color.r+.1 and color.b>color.g+.1: blue+=1
	check(plain.get_data()!=marked.get_data() and red>100,"Feather band controls change actual vane pixels")
	check(blue>20,"Separate shaft color is rendered independently from the vanes")
	marked.save_png("res://.godot/verification/feather_markings.png"); print("FEATHER PIXELS red=",red," blue=",blue," uniforms=",instance.data.appearance.runtime.get_shader_parameter("feather_pattern"))
	viewport.queue_free(); await process_frame; await process_frame; print("FEATHER RENDER: %d checks, %d failures"%[checks,failures]); quit(failures)
