extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=33; terrain.dimensions=Vector2(16,16); terrain.prepare()
	for z in 33:
		for x in 33: terrain.material_mask[x+z*33]=float(x)/32.
	var document:=KiwiEnvironmentDocument.new(); var item:=document.add_terrain(terrain); var ground:=StandardMaterial3D.new(); ground.albedo_color=Color.RED; var paint:=StandardMaterial3D.new(); paint.albedo_color=Color.BLUE; document.component_settings[item.id].material=ground; document.component_settings[item.id].paint_material=paint
	var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(240,180); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); var runtime:=KiwiEnvironmentRuntime.new(); view.add_child(runtime); runtime.configure(document); var chunk:=runtime.nodes[item.id].get_node("Chunk_0_0") as MeshInstance3D; var material:=chunk.get_surface_override_material(0) as ShaderMaterial
	check(material!=null and (material.get_shader_parameter("paint_mask") as Texture2D).get_image().get_pixel(16,16).r==.5,"The native terrain material receives the exact continuous floating-point paint mask")
	var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color.BLACK; environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=1.; view.add_child(environment); var camera:=Camera3D.new(); view.add_child(camera); camera.position=Vector3(0,10,0); camera.look_at(Vector3.ZERO,Vector3.FORWARD); camera.projection=Camera3D.PROJECTION_ORTHOGONAL; camera.size=16.; camera.current=true
	if DisplayServer.get_name()!="headless":
		for i in 5: await RenderingServer.frame_post_draw
		var image:=view.get_texture().get_image(); var left:=image.get_pixel(75,90); var center:=image.get_pixel(120,90); var right:=image.get_pixel(165,90)
		check(left.r>left.b*1.2 and right.b>right.r*1.2 and center.r>.1 and center.b>.1 and absf(center.r-center.b)<.1,"Real camera pixels blend smoothly from red ground through purple to blue paint")
	var original:=chunk.mesh; var texture:=material.get_shader_parameter("paint_mask") as Texture2D; terrain.material_mask.fill(.25); runtime.sync(); var refreshed:=chunk.get_surface_override_material(0) as ShaderMaterial
	check(refreshed==material and refreshed.get_shader_parameter("paint_mask")==texture and texture.get_image().get_pixel(16,16).r==.25,"Painting updates the existing floating-point mask texture and shader rather than reallocating them per dab")
	check(ground.albedo_color==Color.RED and paint.albedo_color==Color.BLUE and original==chunk.mesh and runtime.chunks_rebuilt==0,"Continuous paint preserves the exact native mesh and collider instead of rebuilding topology per dab")
	var map:=Image.create(4,4,false,Image.FORMAT_RGBA8); map.fill(Color(.2,.4,.8,1)); var roughness_map:=ImageTexture.create_from_image(map); ground.roughness_texture=roughness_map; ground.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_BLUE; ground.uv1_offset=Vector3(.25,.5,.75); map.fill(Color(.5,.5,1)); ground.normal_texture=ImageTexture.create_from_image(map); ground.normal_enabled=true; ground.normal_scale=.4; runtime.sync()
	check(material.get_shader_parameter("ground_roughness_texture")==roughness_map and material.get_shader_parameter("ground_roughness_channel")==Vector4(0,0,1,0) and material.get_shader_parameter("ground_offset")==ground.uv1_offset and is_equal_approx(float(material.get_shader_parameter("ground_normal_strength")),.4),"Native roughness channel selection, UV offsets and normal-map strength survive material conversion")
	if DisplayServer.get_name()!="headless":
		for i in 3: await RenderingServer.frame_post_draw
	view.queue_free(); await process_frame; print("TERRAIN PAINT RENDER: %d checks, %d failures"%[checks,failures]); quit(failures)
