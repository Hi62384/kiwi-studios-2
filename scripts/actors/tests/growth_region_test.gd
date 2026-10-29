extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var session:=KiwiModelSession.new(); session.add("Plane",{"size":Vector3(.8,1,.8)}); KiwiSurfaceGrowth.add(session,0); var data:=session.primary().growth; data.settings.length=.5; data.settings.density=100.; session.document.prepare_growth(); data.appearance.root_color=Color.BLACK; data.appearance.tip_color=Color.BLACK; data.appearance.emission=Color.BLUE
	var ids:=PackedInt32Array(); var selected: Dictionary={}
	for row: Dictionary in data.roots:
		if row.position.x<0.: ids.append(int(row.id)); selected=row
	var local_material:=data.appearance.copy_material(); local_material.emission=Color.RED; var local_style:=KiwiGrowthStyle.new(); local_style.values={"length":.25}
	data.regions.append({"id":"left","name":"Left region","roots":ids,"enabled":true,"material":local_material,"style":local_style}); data.revision+=1; var roots:=data.roots.duplicate(true); var mesh:=KiwiSurfaceGrowth.render(data)
	check(mesh.get_surface_count()>1 and KiwiSurfaceGrowth.style(data,selected).length==.25,"A local style and material form bounded real surface batches")
	var shared:=true
	for surface in mesh.get_surface_count():
		var material:=mesh.surface_get_material(surface); shared=shared and material in [data.appearance.material(),local_material.material()]
	check(shared,"Surface batches share materials rather than creating one per strand")
	var builds:=data.chunk_builds; local_material.emission=Color.GREEN; var same:=KiwiSurfaceGrowth.render(data)
	check(same==mesh and builds==data.chunk_builds and data.roots==roots,"Local color changes update uniforms without rebuilding roots or geometry")
	var path:="user://growth regions.tres"; ResourceSaver.save(session.document,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(loaded.components[-1].growth.regions[0].material is KiwiGrowthMaterial and loaded.components[-1].growth.regions[0].style is KiwiGrowthStyle,"Local style/material dependencies survive native serialization")
	var copy:=data.copy_data(); copy.regions[0].material.roughness=.99; check(data.regions[0].material.roughness!=.99,"Independent copies own editable local material settings")
	var viewport:=SubViewport.new(); viewport.size=Vector2i(500,400); viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport); var visual:=KiwiSurfaceGrowthInstance.new(); viewport.add_child(visual); visual.configure(session.primary(),true)
	var camera:=Camera3D.new(); viewport.add_child(camera); camera.position=Vector3(0,.7,2.); camera.look_at(Vector3(0,.2,0)); camera.current=true
	if DisplayServer.get_name()!="headless":
		for i in 5: await process_frame
		await RenderingServer.frame_post_draw; var image:=viewport.get_texture().get_image(); var green:=0; var blue:=0
		for y in range(0,400,2):
			for x in range(0,500,2):
				var color:=image.get_pixel(x,y)
				if color.g>color.r+.1 and color.g>color.b+.1: green+=1
				if color.b>color.r+.1 and color.b>color.g+.1: blue+=1
		check(green>20 and blue>20,"Independent local materials produce both colors in the actual viewport")
		image.save_png("res://.godot/verification/growth_regions.png")
		visual.data.rendering.gpu_threshold=1; visual.data.motion_binding=431; visual.data.motion_guides={"g":{"points":PackedVector3Array([Vector3.ZERO,Vector3(.2,.5,0)]),"delta_points":PackedVector3Array([Vector3.ZERO,Vector3(.2,0,0)])}}
		for root_row: Dictionary in visual.data.roots: visual.data.motion_weights[str(root_row.id)]={"g":1.}
		visual.update_growth()
		for i in 4: await process_frame
		await RenderingServer.frame_post_draw
		check(visual.data.gpu_motion and visual.material_override==null and visual.gpu.regional.size()==2,"Built-in regional materials share GPU pose tables through bounded per-material batches")
		var cached_mesh:=visual.mesh; var old_builds:=visual.data.chunk_builds; visual.data.motion_guides.g.delta_points=PackedVector3Array([Vector3.ZERO,Vector3(.3,0,0)]); visual.update_growth()
		check(visual.mesh==cached_mesh and visual.data.chunk_builds==old_builds,"Regional guide motion does not rebuild strand geometry")
		var custom:=StandardMaterial3D.new(); custom.albedo_color=Color.YELLOW; visual.data.regions[0].material.mode=2; visual.data.regions[0].material.custom=custom; visual.update_growth(); var cleared:=true
		for surface in visual.mesh.get_surface_count():
			var override:=visual.get_surface_override_material(surface)
			if override is ShaderMaterial and override.shader.code.contains("growth_guide_motion"): cleared=cleared and not bool(override.get_shader_parameter("growth_guide_motion"))
		check(not visual.data.gpu_motion and cleared,"An arbitrary regional custom shader uses CPU deformation and clears old GPU overrides safely")
	viewport.queue_free(); await process_frame; DirAccess.remove_absolute(path); print("GROWTH REGIONS: %d checks, %d failures"%[checks,failures]); quit(failures)
