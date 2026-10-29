extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var session:=KiwiModelSession.new(); session.add("Sphere",{"radius":.6,"segments":12,"rings":8}); KiwiSurfaceGrowth.add(session,0)
	var data:=session.primary().growth; data.settings.length=.35; data.settings.direction_mode=0
	var mesh:=KiwiSurfaceGrowth.render(data); var original_roots:=data.roots.duplicate(true); var key:=data.generation_key; var builds:=data.chunk_builds; var material:=data.appearance
	check(mesh.get_surface_count()>0 and material.material() is ShaderMaterial,"Growth uses a specialized shared shader material")
	var arrays:=mesh.surface_get_arrays(0); var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]; var tangents: PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
	check(tangents.size()==vertices.size()*4 and arrays[Mesh.ARRAY_CUSTOM0]!=null,"Every vertex carries strand tangents and stable root-space pattern attributes")
	material.root_color=Color(.9,.02,.01); material.tip_color=Color(1,.4,.02); var result:=KiwiSurfaceGrowth.render(data)
	check(result==mesh and data.chunk_builds==builds and data.roots==original_roots,"Color edits update uniforms without rebuilding geometry or roots")
	for mode in [1,0,1,0]: material.mode=mode; KiwiSurfaceGrowth.render(data)
	check(data.chunk_builds==builds and data.generation_key==key and data.roots==original_roots,"Repeated rendering-mode switches preserve authored growth")
	var custom:=StandardMaterial3D.new(); material.custom=custom; material.mode=2; check(KiwiSurfaceGrowth.render(data).surface_get_material(0)==custom,"Custom materials attach to the same authored geometry")
	material.mode=0; KiwiSurfaceGrowth.render(data)
	session.action("Material test",func(): data.appearance.roughness=.85)
	session.undo(); check(session.primary().growth.appearance.roughness!=.85,"Appearance edits participate in modeling undo")
	session.redo(); data=session.primary().growth; check(is_equal_approx(data.appearance.roughness,.85),"Appearance redo restores material values")
	data.growth_style=KiwiGrowthStyle.preset("Curly"); data.revision+=1; var curled:=KiwiSurfaceGrowth.render(data)
	check(curled.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]!=vertices and data.roots==original_roots,"Style presets change real strand curves while preserving roots")
	data.growth_style=KiwiGrowthStyle.preset("Coarse fur"); data.revision+=1; var tube:=KiwiSurfaceGrowth.render(data)
	check(tube.surface_get_array_len(0)>vertices.size(),"Rounded styles generate actual cross-section geometry")
	var path:="user://growth_appearance.tres"; ResourceSaver.save(session.document,path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiModelDocument
	check(loaded.components[-1].growth.appearance!=null and loaded.components[-1].growth.growth_style.title=="Coarse fur","Native model save/load preserves separate styles and materials")
	DirAccess.remove_absolute(path)
	var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var instance:=MeshInstance3D.new(); instance.mesh=KiwiSurfaceGrowth.render(data); viewport.add_child(instance)
	var camera:=Camera3D.new(); viewport.add_child(camera); camera.position=Vector3(0,.3,2.); camera.look_at(Vector3.ZERO); camera.current=true
	var light:=DirectionalLight3D.new(); viewport.add_child(light); light.rotation_degrees=Vector3(-45,-25,0)
	var environment:=WorldEnvironment.new(); viewport.add_child(environment); environment.environment=Environment.new(); environment.environment.background_mode=Environment.BG_COLOR; environment.environment.background_color=Color(.07,.08,.1); environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color=Color.WHITE; environment.environment.ambient_light_energy=.35
	if DisplayServer.get_name()!="headless":
		for mode in [0,1]:
			data.appearance.mode=mode; instance.mesh=KiwiSurfaceGrowth.render(data)
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			var image:=viewport.get_texture().get_image(); check(image.save_png("res://.godot/verification/growth_render_%d.png"%mode)==OK,"Native rendering mode %d screenshot"%mode)
		viewport.msaa_3d=Viewport.MSAA_4X
		for coverage in [1,2]:
			data.appearance.coverage=coverage; data.appearance.opacity=.65; instance.mesh=KiwiSurfaceGrowth.render(data)
			for i in 4: await process_frame
			await RenderingServer.frame_post_draw
			check(not viewport.get_texture().get_image().is_empty(),"Native coverage shader variant %d renders with MSAA"%coverage)
	else: print("Native screenshots require the separately tested rendered run.")
	viewport.queue_free(); await process_frame; await process_frame
	print("GROWTH MATERIAL: %d checks, %d failures"%[checks,failures]); quit(failures)
