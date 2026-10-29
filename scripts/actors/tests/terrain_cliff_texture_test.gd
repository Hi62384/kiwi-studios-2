extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=65; terrain.dimensions=Vector2(16,16); terrain.generation=KiwiTerrainGenerator.preset(0); terrain.generation.layers=[{"type":"Cliff","height":4.,"width":4.,"length":20.}]; var document:=KiwiEnvironmentDocument.new(); var item:=document.add_terrain(terrain); var image:=Image.create(16,16,false,Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16: image.set_pixel(x,y,Color.WHITE if (x/2+y/2)%2==0 else Color.BLACK)
	image.generate_mipmaps(); var ground:=StandardMaterial3D.new(); ground.albedo_texture=ImageTexture.create_from_image(image); ground.uv1_triplanar=true; var paint:=ground.duplicate(true) as StandardMaterial3D; terrain.material_mask.fill(.5); document.component_settings[item.id].material=ground; document.component_settings[item.id].paint_material=paint
	var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(400,300); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); var runtime:=KiwiEnvironmentRuntime.new(); view.add_child(runtime); runtime.configure(document); var environment:=WorldEnvironment.new(); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color.BLACK; environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=1.; view.add_child(environment); var camera:=Camera3D.new(); view.add_child(camera); camera.position=Vector3(-8,2,0); camera.look_at(Vector3(0,2,0)); camera.current=true
	if DisplayServer.get_name()!="headless":
		for i in 6: await RenderingServer.frame_post_draw
		var rendered:=view.get_texture().get_image(); var horizontal:=PackedFloat32Array(); var vertical:=PackedFloat32Array()
		for index in range(160,240): horizontal.append(rendered.get_pixel(index,150).get_luminance())
		for index in range(110,190): vertical.append(rendered.get_pixel(200,index).get_luminance())
		var a:=edges(horizontal); var b:=edges(vertical); check(a>8 and b>8 and float(a)/maxi(1,b)>.7 and float(a)/maxi(1,b)<1.4,"Real checker texture cells retain comparable horizontal and vertical spacing on a steep cliff")
		print("CLIFF CHECKER horizontal_edges=",a," vertical_edges=",b)
	check((runtime.nodes[item.id].get_node("Chunk_0_0") as MeshInstance3D).get_surface_override_material(0) is ShaderMaterial,"Cliff rendering exercises the shared blended triplanar PBR shader")
	view.queue_free(); await process_frame; print("TERRAIN CLIFF TEXTURE: %d checks, %d failures"%[checks,failures]); quit(failures)
func edges(values: PackedFloat32Array) -> int:
	var high: float=Array(values).max(); var low: float=Array(values).min()
	if high-low<.1: return 0
	var threshold: float=(high+low)*.5; var count:=0
	for index in range(1,values.size()): count+=1 if (values[index]>=threshold)!=(values[index-1]>=threshold) else 0
	return count
