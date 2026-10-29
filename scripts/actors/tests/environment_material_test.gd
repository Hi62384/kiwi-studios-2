extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var session:=KiwiEnvironmentSession.new(); var item:=session.add_terrain(); var terrain:=session.environment().terrain(item.id); var heights:=terrain.edits.duplicate()
	var base:=StandardMaterial3D.new(); base.albedo_color=Color.GREEN; var paint:=StandardMaterial3D.new(); paint.albedo_color=Color.SADDLE_BROWN
	session.environment().component_settings[item.id].material=base; session.environment().component_settings[item.id].paint_material=paint
	session.begin_terrain(item.id,true); session.sculpt(Vector2(-10,-10),3.,1.,.1,0); session.finish_terrain()
	check(Array(terrain.material_mask).max()>.9 and terrain.edits==heights,"Terrain material brush paints a separate mask without changing elevation")
	var mask:=terrain.material_mask.duplicate(); var mesh:=terrain.chunk_mesh(Vector2i.ZERO)
	check(mesh.get_surface_count()==2 and mesh.get_meta("environment_material_slots")==PackedInt32Array([0,1]),"Painted terrain partitions native triangles into base and painted material surfaces")
	session.undo(); check(Array(terrain.material_mask).max()==0.,"Material painting undoes in one sparse transaction")
	session.redo(); check(terrain.material_mask==mask,"Material painting redoes the exact stored mask")
	var runtime:=KiwiEnvironmentRuntime.new(); root.add_child(runtime); runtime.configure(session.environment()); var chunk:=runtime.nodes[item.id].get_node("Chunk_0_0") as MeshInstance3D
	var blended:=chunk.get_surface_override_material(0) as ShaderMaterial
	check(blended!=null and chunk.mesh.get_surface_count()==1 and blended.get_shader_parameter("ground_color")==base.albedo_color and blended.get_shader_parameter("paint_color")==paint.albedo_color and base.albedo_color==Color.GREEN and paint.albedo_color==Color.SADDLE_BROWN,"Terrain blends selected native materials in a single surface without editing their shared source assets")
	var shape:=chunk.get_node("Collision/Shape").shape as ConcavePolygonShape3D
	check(shape.get_faces().size()==32*32*6,"Material painting preserves complete terrain collision triangles")
	var path:="user://environment-material.tres"; ResourceSaver.save(session.environment(),path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(loaded.terrain(item.id).material_mask==mask and loaded.component_settings[item.id].paint_material is StandardMaterial3D,"Painted mask and both material resources survive save and reopen")
	var image:=Image.create(8,8,false,Image.FORMAT_RGBA8); image.fill(Color.CORAL); var image_path:="user://environment-ground.png"; image.save_png(image_path); var from_image:=KiwiEnvironmentAssets.material(image_path) as StandardMaterial3D
	check(from_image!=null and from_image.albedo_texture!=null,"Raw project image files resolve to usable triplanar ground materials")
	var shader:=ShaderMaterial.new(); shader.shader=Shader.new(); var code:="shader_type spatial; uniform float gain=0.5; void fragment(){ALBEDO=vec3(gain+sin(TIME)*0.1);}"; shader.shader.code=code; shader.set_shader_parameter("gain",.3)
	var wrapped:=KiwiEnvironmentAssets.material(shader) as ShaderMaterial
	check(wrapped!=shader and wrapped.shader.code.contains("uniform float kiwi_timeline_time") and shader.shader.code==code and is_equal_approx(wrapped.get_shader_parameter("gain"),.3),"Native terrain shaders receive deterministic runtime TIME without changing source code or parameter values")
	check(KiwiEnvironmentAssets.material(shader)==wrapped,"Unchanged material content reuses its cached runtime conversion")
	shader.set_shader_parameter("gain",.7); var refreshed:=KiwiEnvironmentAssets.material(shader) as ShaderMaterial
	check(refreshed!=wrapped and is_equal_approx(refreshed.get_shader_parameter("gain"),.7),"Changing a shared shader parameter invalidates its cached terrain material")
	var noise:=NoiseTexture2D.new(); noise.width=16; noise.height=16; noise.noise=FastNoiseLite.new(); var before:=KiwiEnvironmentAssets.content_stamp(noise); noise.noise.seed=123
	check(before!=KiwiEnvironmentAssets.content_stamp(noise),"Nested procedural noise edits contribute to the material content signature")
	runtime.queue_free(); await process_frame; session._undo.clear(); session._redo.clear(); DirAccess.remove_absolute(path); DirAccess.remove_absolute(image_path)
	print("ENVIRONMENT MATERIAL: %d checks, %d failures"%[checks,failures]); quit(failures)
