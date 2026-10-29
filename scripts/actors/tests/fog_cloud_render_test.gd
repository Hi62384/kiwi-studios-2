extends "res://scripts/actors/tests/surface_growth_test.gd"
const Presets=preload("res://scripts/actors/fog/fog_cloud_presets.gd")
func capture(view: SubViewport) -> Image:
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func mean_difference(a: Image,b: Image) -> float:
	var sum:=0.
	for y in range(0,a.get_height(),3):
		for x in range(0,a.get_width(),3):
			var ca:=a.get_pixel(x,y); var cb:=b.get_pixel(x,y); sum+=absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)
	return sum
func run() -> void:
	RenderingServer.environment_set_volumetric_fog_volume_size(192,96)
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(384,256); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var environment:=Environment.new(); environment.background_mode=Environment.BG_COLOR; environment.background_color=Color(.08,.14,.25); environment.volumetric_fog_density=0.; environment.volumetric_fog_temporal_reprojection_enabled=false; environment.volumetric_fog_length=30.; environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color=Color.WHITE; environment.ambient_light_energy=.5; view.find_world_3d().environment=environment
	var camera:=Camera3D.new(); view.add_child(camera); camera.current=true
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-50,-25,0); sun.light_energy=3.; view.add_child(sun)
	var config:=Presets.configuration(0); var field:=ActorAnimation.resolve_reference(config[&"field"]); field.values[&"resolution"]=1; var appearance:=ActorAnimation.resolve_reference(config[&"appearance"])
	var actor:=registry.get_definition(&"fog_volume").create_actor({&"position":Vector3(0,0,-7),&"shape":3,&"volume_size":Vector3(8,5,5)}); actor.values.merge(config,true)
	var runtime:=registry.get_definition(&"fog_volume").create_runtime(actor); view.add_child(runtime); runtime.evaluate_transform(actor.values); runtime.set_active(true); runtime.evaluate(0.,actor.values)
	var real:=await capture(view); var material: ShaderMaterial=runtime.content.material; var texture: Texture3D=material.get_shader_parameter("field_0"); var builds:=preload("res://scripts/actors/fog/fog_field.gd").builds
	check(material.get_shader_parameter("cloud_lod")==true and (material.get_shader_parameter("cloud_low") as Texture3D).get_width()==16 and texture.get_width()==32,"Distance LOD uses a cached lower-resolution rendering field while preserving the authored source")
	appearance.values[&"render_style"]=1; appearance.values[&"shadow_tint"]=Color(.1,.25,.6); runtime.evaluate(0.,actor.values); var cartoon:=await capture(view)
	check(mean_difference(real,cartoon)>1. and material.get_shader_parameter("field_0")==texture and builds==preload("res://scripts/actors/fog/fog_field.gd").builds,"Stylized cloud rendering changes actual pixels while retaining the same density texture")
	appearance.values[&"render_style"]=0; runtime.evaluate(0.,actor.values); camera.position.x=2.; camera.look_at(Vector3(0,0,-7)); var angle:=await capture(view)
	check(mean_difference(real,angle)>10.,"Moving the camera produces real cloud parallax")
	camera.position=Vector3(0,0,-7); camera.rotation=Vector3.ZERO; var inside:=await capture(view)
	check(mean_difference(real,inside)>10.,"The camera can enter the native cloud volume")
	camera.position=Vector3.ZERO; sun.light_color=Color(1.,.15,.03); runtime.evaluate(0.,actor.values); var sunset:=await capture(view)
	check(mean_difference(real,sunset)>2.,"Atmospheric volume illumination responds to the actual directional light color")
	field.values[&"cloud_type"]=1; runtime.evaluate(0.,actor.values); var stratus:=await capture(view)
	check(mean_difference(real,stratus)>10.,"Stratus changes the rendered volumetric structure instead of only renaming cumulus")
	field.values[&"cloud_type"]=0; sun.light_color=Color.WHITE; sun.rotation_degrees=Vector3(0,180,0); appearance.values[&"silver_lining"]=0.; runtime.evaluate(0.,actor.values); var back_plain:=await capture(view)
	appearance.values[&"silver_lining"]=4.; runtime.evaluate(0.,actor.values); var back_edge:=await capture(view); var back_difference:=mean_difference(back_plain,back_edge)
	sun.rotation_degrees=Vector3.ZERO; appearance.values[&"silver_lining"]=0.; runtime.evaluate(0.,actor.values); var front_plain:=await capture(view)
	appearance.values[&"silver_lining"]=4.; runtime.evaluate(0.,actor.values); var front_edge:=await capture(view); var front_difference:=mean_difference(front_plain,front_edge)
	print("CLOUD SILVER back_difference=",back_difference," front_difference=",front_difference)
	check(back_difference>2. and front_difference<back_difference*.2,"Silver lining responds to backlight/view alignment rather than drawing a permanent outline")
	real.save_png("res://.godot/verification/cloud_cumulus.png"); cartoon.save_png("res://.godot/verification/cloud_cartoon.png"); stratus.save_png("res://.godot/verification/cloud_stratus.png")
	view.queue_free(); await process_frame; print("CLOUD RENDER: %d checks, %d failures"%[checks,failures]); quit(failures)
