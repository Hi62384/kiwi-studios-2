extends "res://scripts/actors/tests/surface_growth_test.gd"
var viewport: SubViewport
var registry: ActorRegistry
var lens: Camera3D
func capture() -> Image:
	for i in 7: await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func brightness(image: Image,point: Vector2i,radius: int=3) -> float:
	var total:=0.; var count:=0
	for y in range(maxi(0,point.y-radius),mini(image.get_height(),point.y+radius+1)):
		for x in range(maxi(0,point.x-radius),mini(image.get_width(),point.x+radius+1)):
			var c:=image.get_pixel(x,y); total+=(c.r+c.g+c.b)/3.; count+=1
	return total/maxi(1,count)
func difference(a: Image,b: Image) -> float:
	var total:=0.
	for y in range(0,a.get_height(),4):
		for x in range(0,a.get_width(),4): var delta:=a.get_pixel(x,y)-b.get_pixel(x,y); total+=absf(delta.r)+absf(delta.g)+absf(delta.b)
	return total
func make_actor(type: StringName,values: Dictionary) -> ActorRuntime:
	var definition:=registry.get_definition(type); var actor:=definition.create_actor(values); var runtime:=definition.create_runtime(actor); viewport.add_child(runtime); runtime.evaluate_transform(actor.values); runtime.set_active(true); runtime.evaluate(0.,actor.values); return runtime
func run() -> void:
	registry=ActorRegistry.new(); BasicActors.register_all(registry); viewport=SubViewport.new(); viewport.own_world_3d=true; viewport.size=Vector2i(512,384); viewport.positional_shadow_atlas_size=2048; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var environment:=Environment.new(); environment.background_mode=Environment.BG_COLOR; environment.background_color=Color.BLACK; environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color=Color.BLACK; environment.ambient_light_energy=0.; environment.volumetric_fog_density=0.; environment.volumetric_fog_gi_inject=0.; environment.volumetric_fog_temporal_reprojection_enabled=false; environment.volumetric_fog_length=30.; viewport.find_world_3d().environment=environment
	lens=Camera3D.new(); viewport.add_child(lens); lens.position=Vector3(7,3,7); lens.look_at(Vector3(0,1,-2)); lens.current=true
	var fog:=make_actor(&"fog_volume",{&"position":Vector3(0,1,-2),&"volume_size":Vector3(12,8,16),&"density":.06})
	var light:=make_actor(&"light_3d",{&"light_type":2,&"position":Vector3(0,2,3),&"energy":8.,&"volumetric_fog_energy":2.,&"range":16.,&"spot_angle":25.,&"shadows":false}); light.content.look_at(Vector3(0,1,-4))
	var lit:=await capture(); light.actor.values[&"volumetric_fog_energy"]=0.; light.evaluate(0.,light.actor.values); var unlit:=await capture(); var probe:=Vector2i(lens.unproject_position(Vector3(0,1.3,-2)))
	var on:=brightness(lit,probe); var off:=brightness(unlit,probe); print("FOG SPOT energy_on=",on," off=",off," probe=",probe)
	check(on>off+.03 and light.content.light_energy==8.,"Spot volumetric energy changes real fog pixels independently of surface Energy")
	light.actor.values[&"volumetric_fog_energy"]=2.; light.evaluate(0.,light.actor.values); light.content.look_at(Vector3(0,1,-4)); var restored:=await capture(); check(brightness(restored,probe)>off+.03,"Restoring volumetric energy restores the spotlight shaft")
	var wall:=make_actor(&"basic_shape",{&"position":Vector3(0,2,0),&"scale":Vector3(1.8,4,.2)}); var no_shadow:=await capture(); light.actor.values[&"shadows"]=true; light.evaluate(0.,light.actor.values); var shadow:=await capture(); var behind:=Vector2i(lens.unproject_position(Vector3(0,1.1,-3)))
	var before:=brightness(no_shadow,behind,6); var after:=brightness(shadow,behind,6); print("FOG SHADOW disabled=",before," enabled=",after)
	print("FOG SHADOW params enabled=",light.content.shadow_enabled," caster=",wall.content.cast_shadow," geometry=",wall.content.mesh," delta=",difference(no_shadow,shadow)," atlas=",viewport.positional_shadow_atlas_size," bias=",light.content.shadow_bias," opacity=",light.content.shadow_opacity," shadow_mask=",light.content.shadow_caster_mask," bake=",light.content.light_bake_mode)
	check(before>after+.015,"A real wall and native spotlight shadow map darken fog behind the wall")
	wall.actor.values[&"position"]=Vector3(4,2,0); wall.evaluate_transform(wall.actor.values); var moved:=await capture(); check(brightness(moved,behind,6)>after+.015,"Moving the caster updates its volumetric shadow")
	light.actor.values[&"shadow_casting"]=0; light.actor.values[&"shadows"]=false; light.actor.values[&"spot_angle"]=10.; light.evaluate(0.,light.actor.values); var narrow:=await capture(); light.actor.values[&"spot_angle"]=45.; light.evaluate(0.,light.actor.values); var wide:=await capture(); var edge:=Vector2i(lens.unproject_position(Vector3(2,1,-3)))
	check(difference(wide,narrow)>100.,"Spot angle changes the actual illuminated fog cone")
	print("FOG ANGLE narrow=",brightness(narrow,edge)," wide=",brightness(wide,edge)," delta=",difference(narrow,wide)," angle=",light.content.spot_angle)
	light.set_active(false); wall.set_active(false)
	var omni:=make_actor(&"light_3d",{&"light_type":1,&"position":Vector3(0,1,-2),&"color":Color.BLUE,&"energy":5.,&"volumetric_fog_energy":2.,&"range":6.,&"shadows":false}); var blue:=await capture(); var center:=blue.get_pixelv(probe)
	check(center.b>center.r+.03,"The existing Omni actor illuminates fog with its own color")
	omni.set_active(false); var sun:=make_actor(&"directional_light",{&"energy":1.,&"volumetric_fog_energy":1.,&"color":Color.RED,&"shadows":false}); var sunlight:=await capture(); center=sunlight.get_pixelv(probe)
	check(center.r>center.b+.03,"The existing dedicated Directional actor illuminates fog")
	sun.set_active(false); omni.set_active(true); light.set_active(true); light.actor.values[&"color"]=Color.RED; light.evaluate(0.,light.actor.values); var mixed:=await capture(); var mixture:=mixed.get_pixelv(probe)
	check(mixture.r>.03 and mixture.b>.03,"Independent red and blue lights contribute simultaneously to the same fog")
	omni.set_active(false); var red_only:=await capture(); check(mixture.b>red_only.get_pixelv(probe).b+.03 and red_only.get_pixelv(probe).r>.03,"Disabling one volumetric light preserves the other light's contribution")
	omni.set_active(true); make_actor(&"fog_volume",{&"position":Vector3(2,1,-3),&"volume_size":Vector3(4,4,6),&"density":.15}); var overlap:=await capture(); check(difference(mixed,overlap)>20.,"Overlapping local fog volumes respond through native light composition")
	wall.set_active(true); wall.actor.values[&"position"]=Vector3(3,2,2); wall.actor.values[&"scale"]=Vector3(2,2,2); wall.evaluate_transform(wall.actor.values); var paint:=StandardMaterial3D.new(); paint.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; paint.albedo_color=Color.GREEN; wall.content.material_override=paint; var foreground:=await capture(); var solid:=foreground.get_pixelv(Vector2i(lens.unproject_position(Vector3(3,2,2))))
	check(solid.g>solid.r+.1 and solid.g>solid.b+.1,"Opaque foreground geometry occludes the fog behind it using real scene depth")
	shadow.save_png("res://.godot/verification/fog_light_shadow.png"); lit.save_png("res://.godot/verification/fog_light_spot.png"); viewport.queue_free(); await process_frame; await process_frame; print("FOG LIGHTING RENDER: %d checks, %d failures"%[checks,failures]); quit(failures)
