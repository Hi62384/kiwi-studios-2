extends "res://scripts/actors/tests/surface_growth_test.gd"
const Appearance=preload("res://scripts/actors/fog/fog_appearance.gd")
func run() -> void:
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry)
	var viewport:=SubViewport.new(); viewport.own_world_3d=true; viewport.size=Vector2i(320,240); viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
	var environment:=Environment.new(); environment.background_mode=Environment.BG_COLOR; environment.background_color=Color.WHITE; environment.volumetric_fog_density=0.; environment.volumetric_fog_temporal_reprojection_enabled=false; environment.volumetric_fog_length=20.
	viewport.find_world_3d().environment=environment
	var camera:=Camera3D.new(); viewport.add_child(camera); camera.current=true
	var definition:=registry.get_definition(&"fog_volume"); var actor:=definition.create_actor({&"position":Vector3(0,0,-4),&"volume_size":Vector3(6,6,4),&"density":.5}); var appearance:=Appearance.definition().create_object(); appearance.values[&"color"]=Color.RED; appearance.values[&"emission"]=Color.RED; actor.values[&"appearance"]=ActorObjectReference.from_object(appearance)
	var runtime:=definition.create_runtime(actor); viewport.add_child(runtime); runtime.evaluate_transform(actor.values); runtime.set_active(true); runtime.evaluate(0.,actor.values)
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw; var red:=viewport.get_texture().get_image(); var first:=red.get_pixel(160,120)
	check(first.r>first.g+.1,"Fog appearance changes real volumetric pixels")
	var material: Material=runtime.content.material; var builds:=preload("res://scripts/actors/fog/fog_field.gd").builds
	appearance.values[&"color"]=Color.BLUE; appearance.values[&"emission"]=Color.BLUE; runtime.evaluate(0.,actor.values)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw; var blue:=viewport.get_texture().get_image().get_pixel(160,120)
	check(blue.b>blue.r+.1 and runtime.content.material==material and builds==preload("res://scripts/actors/fog/fog_field.gd").builds,"Color edits update uniforms without replacing shaders or rebuilding fields")
	appearance.values[&"opacity"]=0.; runtime.evaluate(0.,actor.values)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw; var clear:=viewport.get_texture().get_image().get_pixel(160,120)
	check(clear.r>.9 and clear.g>.9 and clear.b>.9,"Zero opacity is transparent through the native volumetric renderer")
	check(environment.volumetric_fog_enabled==false and viewport.find_world_3d().environment!=environment,"Fog enables a temporary environment without mutating the source resource")
	runtime.set_active(false); await process_frame; await process_frame; check(viewport.find_world_3d().environment==environment,"Ending the last fog clip restores environment ownership")
	var global_definition:=registry.get_definition(&"global_fog"); var global_a:=global_definition.create_actor(); global_a.id="a"; var global_b:=global_definition.create_actor(); global_b.id="b"
	var first_global:=global_definition.create_runtime(global_a); var second_global:=global_definition.create_runtime(global_b); viewport.add_child(first_global); viewport.add_child(second_global)
	first_global.set_active(true); second_global.set_active(true); first_global.evaluate(0.,global_a.values); second_global.evaluate(0.,global_b.values)
	for i in 3: await process_frame
	check(first_global.content.visible and not second_global.content.visible and viewport.find_world_3d().environment.volumetric_fog_density==0.,"Overlapping global actors choose one stable owner and avoid double-counting environment density")
	await process_frame; await process_frame; check(first_global.content.visible and not second_global.content.visible,"Global ownership does not flicker across frames")
	first_global.set_active(false); await process_frame; await process_frame; check(second_global.content.visible,"Another global actor takes over when the owner ends")
	check(viewport.find_world_3d().environment.background_color==environment.background_color,"Global fog preserves unrelated environment appearance")
	second_global.set_active(false); await process_frame; await process_frame; check(viewport.find_world_3d().environment==environment,"Global fog restores the original environment on exit")
	environment.background_color=Color.BLACK; environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color=Color.WHITE; environment.ambient_light_energy=1.
	var light:=DirectionalLight3D.new(); light.light_energy=2.; light.light_volumetric_fog_energy=1.; viewport.add_child(light)
	runtime.set_active(true); appearance.values[&"opacity"]=1.; appearance.values[&"emission"]=Color.BLACK; appearance.values[&"color"]=Color.RED; appearance.values[&"secondary"]=Color.BLUE; appearance.values[&"gradient"]=1; runtime.evaluate(0.,actor.values)
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw; var gradient:=viewport.get_texture().get_image(); var upper:=gradient.get_pixel(160,55); var lower:=gradient.get_pixel(160,185)
	check(upper.b-upper.r>lower.b-lower.r+.03,"Actual three-dimensional color gradients vary across the rendered volume")
	actor.values[&"rotation"]=Vector3(0,0,90); runtime.evaluate_transform(actor.values); runtime.evaluate(0.,actor.values)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw; var turned:=viewport.get_texture().get_image(); var left:=turned.get_pixel(70,120); var right:=turned.get_pixel(250,120)
	check(absf((left.r-left.b)-(right.r-right.b))>.03,"Rotating the volume rotates its local-space color gradient")
	actor.values[&"rotation"]=Vector3.ZERO; runtime.evaluate_transform(actor.values)
	environment.background_color=Color.WHITE; appearance.values[&"gradient"]=0; appearance.values[&"scattering"]=0.; actor.values[&"volume_size"]=Vector3(6,6,1); runtime.evaluate(0.,actor.values)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw; var thin:=viewport.get_texture().get_image().get_pixel(160,120)
	actor.values[&"volume_size"]=Vector3(6,6,4); runtime.evaluate(0.,actor.values)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw; var thick:=viewport.get_texture().get_image().get_pixel(160,120)
	check(thin.r>thick.r+.05,"Longer paths through the same real fog material produce greater attenuation")
	appearance.values[&"opacity"]=.5; runtime.evaluate(0.,actor.values)
	for i in 6: await process_frame
	await RenderingServer.frame_post_draw; var half:=viewport.get_texture().get_image().get_pixel(160,120)
	check(half.r>thick.r+.03,"Opacity changes native volumetric attenuation rather than a mesh alpha layer")
	environment.background_color=Color.BLACK; appearance.values[&"gradient"]=1; appearance.values[&"scattering"]=1.; appearance.values[&"opacity"]=1.; runtime.evaluate(0.,actor.values)
	var field:=preload("res://scripts/actors/fog/fog_field.gd").definition().create_object(); field.values[&"mode"]=4; field.values[&"resolution"]=0; appearance.values[&"layer_0"]=ActorObjectReference.from_object(field); runtime.evaluate(0.,actor.values)
	for i in 5: await process_frame
	await RenderingServer.frame_post_draw; var noisy:=viewport.get_texture().get_image()
	check(noisy.get_data()!=gradient.get_data(),"A three-dimensional procedural density field changes the rendered fog")
	var build_count:=preload("res://scripts/actors/fog/fog_field.gd").builds; var start:=Time.get_ticks_usec()
	for i in 30: appearance.values[&"color"]=Color(float(i)/30.,.2,.4); runtime.evaluate(0.,actor.values)
	var milliseconds:=float(Time.get_ticks_usec()-start)/30000.
	check(preload("res://scripts/actors/fog/fog_field.gd").builds==build_count,"Animated color changes retain the same cached density texture")
	print("FOG uniform_update_ms=",milliseconds," field_builds=",build_count)
	var mask:=preload("res://scripts/actors/fog/fog_field.gd").definition().create_object(); mask.values[&"value"]=0.; field.values[&"mask"]=ActorObjectReference.from_object(mask); runtime.evaluate(0.,actor.values)
	check((runtime.content.material.get_shader_parameter("field_has_mask") as PackedFloat32Array)[0]==1.,"Appearance influences bind reusable field masks")
	var image_path:="user://fog-color-map.png"; var image:=Image.create(4,4,false,Image.FORMAT_RGBA8); image.fill(Color.GREEN); image.save_png(image_path)
	var image_object:=registry.get_object_definition(&"image").create_object(); image_object.values[&"source"]=image_path; appearance.values[&"color_texture"]=ActorObjectReference.from_object(image_object); runtime.evaluate(0.,actor.values)
	check(runtime.content.material.get_shader_parameter("has_color"),"Existing Kiwi image objects bind as fog color textures")
	var volume:=ImageTexture3D.new(); var slices: Array[Image]=[]
	for z in 4:
		var slice:=Image.create(4,4,false,Image.FORMAT_RGBA8); slice.fill(Color(float(z)/3.,0,0)); slices.append(slice)
	volume.create(Image.FORMAT_RGBA8,4,4,4,false,slices); var volume_path:="user://fog-density-map.res"; ResourceSaver.save(volume,volume_path); appearance.values[&"density_volume"]=volume_path; runtime.evaluate(0.,actor.values)
	check(runtime.content.material.get_shader_parameter("has_density_volume") and runtime.content.material.get_shader_parameter("density_volume") is Texture3D,"Native volumetric textures bind to the actual sampler3D density path")
	var custom:=registry.get_object_definition(&"fog_shader_material").create_object(); var shader:=Shader.new(); shader.code="shader_type fog; uniform float amount=.2; void fog(){DENSITY=amount;ALBEDO=vec3(0.0,1.0,0.0);}"; custom.values[&"shader_path"]=shader; custom.values[&"uniforms"]={&"amount":.3}; actor.values[&"material"]=ActorObjectReference.from_object(custom); runtime.evaluate(0.,actor.values)
	check(runtime.content.material!=material and runtime.content.material.get_shader_parameter("amount")==.3 and shader.code.contains("DENSITY=amount"),"Custom fog shaders retain source and editable uniforms while bypassing built-in appearance")
	actor.values[&"material"]=null; runtime.evaluate(0.,actor.values); check(runtime.content.material==material,"Clearing a custom shader restores the existing built-in appearance material")
	var camera_environment:=Environment.new(); camera_environment.background_mode=Environment.BG_COLOR; camera_environment.background_color=Color(.1,.2,.3); camera.environment=camera_environment; await process_frame; await process_frame
	check(camera.environment!=camera_environment and camera.environment.volumetric_fog_enabled and camera_environment.volumetric_fog_enabled==false,"Camera-specific environments receive temporary fog settings without altering the authored resource")
	runtime.set_active(false); await process_frame; await process_frame; check(camera.environment==camera_environment,"Camera-specific environment ownership restores when the fog clip ends")
	gradient.save_png("res://.godot/verification/fog_gradient.png")
	DirAccess.remove_absolute(image_path); DirAccess.remove_absolute(volume_path)
	red.save_png("res://.godot/verification/fog_appearance_red.png"); viewport.queue_free(); await process_frame; await process_frame; print("FOG RENDER: %d checks, %d failures"%[checks,failures]); quit(failures)
