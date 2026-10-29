extends "res://scripts/actors/tests/surface_growth_test.gd"
const Shadow=preload("res://scripts/actors/fog/fog_cloud_shadow.gd")
func capture(view: SubViewport) -> Image:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func run() -> void:
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(320,240); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view)
	var camera:=Camera3D.new(); view.add_child(camera); camera.position=Vector3(0,7,7); camera.look_at(Vector3.ZERO); camera.current=true
	var environment:=Environment.new(); environment.background_mode=Environment.BG_COLOR; environment.background_color=Color(.2,.2,.2); environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color=Color.WHITE; environment.ambient_light_energy=1.; environment.volumetric_fog_density=0.; environment.volumetric_fog_temporal_reprojection_enabled=false; view.find_world_3d().environment=environment
	var floor_mesh:=MeshInstance3D.new(); floor_mesh.mesh=PlaneMesh.new(); floor_mesh.mesh.size=Vector2.ONE*20.; var floor_material:=StandardMaterial3D.new(); floor_material.albedo_color=Color.WHITE; floor_mesh.material_override=floor_material; view.add_child(floor_mesh)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-90,0,0); view.add_child(sun)
	var appearance:=registry.get_object_definition(&"fog_appearance").create_object(); appearance.values[&"shadow_strength"]=1.; var field:=registry.get_object_definition(&"fog_field").create_object(); field.values.merge({&"mode":6,&"shape":1,&"shape_size":Vector3.ONE*.8},true)
	var actor:=registry.get_definition(&"fog_volume").create_actor({&"position":Vector3(0,4,0),&"shape":3,&"volume_size":Vector3(4,2,4),&"density":1.,&"field":ActorObjectReference.from_object(field),&"appearance":ActorObjectReference.from_object(appearance)}); var runtime:=registry.get_definition(&"fog_volume").create_runtime(actor); view.add_child(runtime); runtime.set_active(true); runtime.evaluate_transform(actor.values); runtime.evaluate(0.,actor.values)
	appearance=ActorAnimation.resolve_reference(actor.values[&"appearance"])
	var before:=await capture(view); appearance.values[&"projected_shadow"]=true; runtime.evaluate(0.,actor.values); var after:=await capture(view); var decal:=runtime.content.get_node_or_null("KiwiCloudShadow") as Decal
	check(decal!=null and decal.texture_albedo!=null,"Cloud shadows create a native local decal from density integration")
	if decal!=null:
		var image:=decal.texture_albedo.get_image(); check(image.get_pixel(8,8).a>image.get_pixel(0,0).a+.1,"Projected shadow opacity follows the actual volume interior")
		var a:=before.get_pixel(160,120); var b:=after.get_pixel(160,120); print("CLOUD SHADOW pixel_before=",a," after=",b," generation_ms=",runtime.content.get_meta("cloud_shadow_ms")); check(b.r<a.r-.02,"Integrated cloud shadow darkens actual receiving scene geometry")
		var texture:=decal.texture_albedo; var old_position:=decal.global_position; sun.rotation_degrees=Vector3(-65,25,0); var moved:=await capture(view)
		check(decal.texture_albedo==texture and decal.global_position.distance_to(old_position)>.1,"Changing sun direction moves the projection while reusing its texture")
		after.save_png("res://.godot/verification/cloud_shadow.png")
	appearance.values[&"projected_shadow"]=false; runtime.evaluate(0.,actor.values); await process_frame; await process_frame
	check(decal!=null and not decal.visible,"Disabling the projection removes the shadow without deleting authored density")
	view.queue_free(); await process_frame; print("CLOUD SHADOW: %d checks, %d failures"%[checks,failures]); quit(failures)
