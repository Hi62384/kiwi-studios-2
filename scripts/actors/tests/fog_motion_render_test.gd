extends "res://scripts/actors/tests/destruction_timeline_test.gd"
func capture(view: SubViewport) -> Image:
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func darkness(image: Image) -> Vector2:
	var total:=0.; var center:=0.
	for y in range(20,image.get_height()-20,2):
		for x in range(10,image.get_width()-10,2):
			var weight:=1.-image.get_pixel(x,y).r; total+=weight; center+=weight*x
	return Vector2(center/maxf(.00001,total),total)
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); view.own_world_3d=true; view.size=Vector2i(320,240); view.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var environment:=Environment.new(); environment.background_mode=Environment.BG_COLOR; environment.background_color=Color.WHITE; environment.volumetric_fog_density=0.; environment.volumetric_fog_temporal_reprojection_enabled=false; environment.volumetric_fog_length=15.; view.find_world_3d().environment=environment
	var camera:=Camera3D.new(); view.add_child(camera); camera.current=true
	var source:=editor.registry.get_object_definition(&"fog_emitter").create_object(); source.values.merge({&"shape":1,&"position":Vector3(-1.2,0,0),&"size":Vector3.ONE*1.5,&"mode":1,&"burst":3.,&"velocity":Vector3.RIGHT*2.},true)
	var appearance:=editor.registry.get_object_definition(&"fog_appearance").create_object(); appearance.values[&"scattering"]=0.
	var fog:=add(&"fog_volume",{&"position":Vector3(0,0,-5),&"shape":3,&"volume_size":Vector3(8,4,4),&"density":.6,&"appearance":ActorObjectReference.from_object(appearance),&"fog_motion_mode":2,&"fog_initial":1,&"fog_wind":Vector3.RIGHT*2.,&"fog_obstacles":false,&"fog_velocity_damping":0.,&"fog_source_0":ActorObjectReference.from_object(source)})
	await seek(0.); var first:=await capture(view); var a:=darkness(first)
	await seek(.8); var moved:=await capture(view); var b:=darkness(moved)
	print("FOG MOTION PIXELS before=",a," after=",b," stats=",editor.physics._runtime(fog.id).get_meta("fog_motion_stats"))
	check(a.y>20. and b.x>a.x+8.,"Transported three-dimensional concentration moves the actual rendered volumetric silhouette")
	await seek(0.); var rewind:=darkness(await capture(view))
	check(absf(rewind.x-a.x)<1. and absf(rewind.y-a.y)<1.,"Native volumetric rewind restores the initial silhouette without history trails")
	first.save_png("res://.godot/verification/fog_motion_before.png"); moved.save_png("res://.godot/verification/fog_motion_after.png")
	editor.physics.dispose(); editor.queue_free(); view.queue_free(); await process_frame; print("FOG MOTION RENDER: %d checks, %d failures"%[checks,failures]); quit(failures)
