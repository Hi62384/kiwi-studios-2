extends "res://scripts/actors/tests/fog_lighting_render_test.gd"
func run() -> void:
	registry=ActorRegistry.new(); BasicActors.register_all(registry); viewport=SubViewport.new(); viewport.own_world_3d=true; viewport.size=Vector2i(512,384); viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var environment:=Environment.new(); environment.background_mode=Environment.BG_COLOR; environment.background_color=Color.BLACK; environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color=Color.BLACK; environment.ambient_light_energy=0.; environment.volumetric_fog_density=0.; environment.volumetric_fog_gi_inject=0.; environment.volumetric_fog_temporal_reprojection_enabled=false; environment.volumetric_fog_length=30.; viewport.find_world_3d().environment=environment
	lens=Camera3D.new(); viewport.add_child(lens); lens.position=Vector3(5,2,6); lens.look_at(Vector3(0,1,-3)); lens.current=true
	make_actor(&"fog_volume",{&"position":Vector3(0,1,-3),&"volume_size":Vector3(10,6,12),&"density":.08})
	var sun:=make_actor(&"directional_light",{&"energy":2.,&"volumetric_fog_energy":2.,&"shadows":true,&"shadow_max_distance":30.}); sun.content.look_at(sun.content.global_position+Vector3(0,-.12,-1))
	for x in [-2.,0.,2.]: make_actor(&"basic_shape",{&"position":Vector3(x,1.5,0),&"scale":Vector3(.5,3.,.25)})
	for y in [0.,3.]: make_actor(&"basic_shape",{&"position":Vector3(0,y,0),&"scale":Vector3(4.5,.4,.25)})
	var open:=await capture(); var point:=Vector2i(lens.unproject_position(Vector3(1,1.1,-3)))
	var blocker:=make_actor(&"basic_shape",{&"position":Vector3(1,1.5,0),&"scale":Vector3(1.5,2.6,.3)}); var closed:=await capture(); var before:=brightness(open,point,5); var after:=brightness(closed,point,5)
	print("FOG WINDOW open=",before," blocked=",after," pixel=",point," delta=",difference(open,closed))
	check(before>after+.02,"Directional light forms a real window shaft that darkens when the opening is blocked")
	blocker.set_active(false); var restored:=await capture(); check(brightness(restored,point,5)>after+.02,"Reopening the window restores the native volumetric shaft")
	environment.volumetric_fog_anisotropy=.6; var forward:=await capture(); environment.volumetric_fog_anisotropy=-.6; var backward:=await capture()
	check(difference(forward,backward)>100.,"Environment-wide scattering directionality changes real shaft illumination")
	lens.position=Vector3(3,2,6); lens.look_at(Vector3(0,1,-3)); var moved:=await capture(); check(difference(restored,moved)>100.,"Camera movement preserves actual three-dimensional shaft parallax")
	open.save_png("res://.godot/verification/fog_window_open.png"); closed.save_png("res://.godot/verification/fog_window_closed.png"); viewport.queue_free(); await process_frame; await process_frame; print("FOG WINDOW SHAFTS: %d checks, %d failures"%[checks,failures]); quit(failures)
