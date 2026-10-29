extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var session:=KiwiModelSession.new(); session.add("Plane",{"size":Vector3.ONE}); KiwiSurfaceGrowth.add(session,0); var first:=session.primary(); var second:=first.copy_component(true); second.growth.appearance=first.growth.appearance; session.document.components.append(second)
	var source_id:=first.id; var other_id:=second.id; var asset_id:=first.growth.appearance.asset_id
	session.action("Make growth material unique",func(): first.growth.appearance=first.growth.appearance.copy_material(true))
	check(first.growth.appearance.asset_id!=asset_id,"Make Unique is a real resource-identity edit")
	session.undo(); check(session.document.component(source_id).growth.appearance==session.document.component(other_id).growth.appearance,"Undo restores the shared material relationship")
	session.redo(); check(session.document.component(source_id).growth.appearance!=session.document.component(other_id).growth.appearance,"Redo restores independent editable material resources")
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var object:=registry.get_object_definition(&"shader_material").create_object(); var shader:=Shader.new(); shader.code="shader_type spatial; uniform float gain=.4; uniform sampler2D detail; void fragment(){ALBEDO=vec3(gain+TIME*.001);}"; object.set_value(&"shader_path",shader); object.set_value(&"uniforms",{&"gain":.4})
	var material:=KiwiGrowthMaterial.new(); material.mode=2; material.custom_asset=object; var native:=material.material() as ShaderMaterial
	check(native!=null and native.shader!=null and not native.shader.code.contains("+TIME") and shader.code.contains("+TIME"),"Existing Kiwi ShaderMaterial assets adapt without modifying their authoring shader")
	object.set_value(&"uniforms",{&"gain":.7}); native=material.material() as ShaderMaterial
	check(is_equal_approx(float(native.get_shader_parameter("gain")),.7),"Custom material parameter changes refresh through the shared adapter")
	var component:=session.document.component(source_id); component.growth.appearance=material; var instance:=KiwiSurfaceGrowthInstance.new(); root.add_child(instance); instance.configure(component,true); instance.update_growth(); instance.set_growth_time(.25)
	var uniform:=str((instance.material_override as ShaderMaterial).get_meta("kiwi_time_uniform","")); check(not uniform.is_empty() and is_equal_approx(float(instance.material_override.get_shader_parameter(uniform)),.25),"Custom growth TIME is controlled by scene time")
	var noise:=registry.get_object_definition(&"noise_image").create_object(); noise.set_value(&"resolution",0); object.set_value(&"uniforms",{&"gain":.7,&"detail":ActorObjectReference.from_object(noise)}); native=material.material() as ShaderMaterial; var before: Texture2D=native.get_shader_parameter("detail"); noise.set_value(&"frequency",.25); native=material.material() as ShaderMaterial
	check(before!=null and native.get_shader_parameter("detail")!=before,"Nested Noise Image edits refresh custom growth shader textures")
	var path:="user://growth-source-image.png"; var image:=Image.create(2,2,false,Image.FORMAT_RGBA8); image.fill(Color.RED); image.save_png(path); var textured:=KiwiGrowthMaterial.new(); textured.texture_sources={"albedo_texture":path}; textured.material(); image.fill(Color.GREEN); image.save_png(path); KiwiGrowthMaterial.invalidate_source(path); textured.material()
	check(textured.albedo_texture.get_image().get_pixel(0,0).g>.9,"Image workspace-style save invalidation refreshes same-second texture changes")
	instance.queue_free(); await process_frame; DirAccess.remove_absolute(path); print("GROWTH RESOURCES: %d checks, %d failures"%[checks,failures]); quit(failures)
