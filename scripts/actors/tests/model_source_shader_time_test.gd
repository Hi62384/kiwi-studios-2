extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var model:=KiwiModelSession.new(); var item:=model.add("Box"); var material:=ShaderMaterial.new(); var shader:=Shader.new(); shader.code="shader_type spatial; uniform float strength=0.7; void vertex(){VERTEX.y+=sin(TIME)*strength*.1;} void fragment(){ALBEDO=vec3(.4,.7,.2);}"; material.shader=shader; material.set_shader_parameter("strength",.42); item.surface_materials=[material]
	var registry:=ActorRegistry.new(); BasicActors.register_all(registry); var actor:=registry.get_definition(&"basic_mesh").create_actor(); actor.set_value(&"mesh_path",model.document); var runtime:=registry.get_definition(&"basic_mesh").create_runtime(actor); root.add_child(runtime); runtime.evaluate_clip(ActorClip.create(actor),0.)
	var controlled: ShaderMaterial
	for visual in runtime.find_children("*","MeshInstance3D",true,false):
		if visual.mesh!=null and visual.mesh.get_surface_count()>0: controlled=visual.get_active_material(0)
	check(controlled!=null and controlled.has_meta("kiwi_time_uniform") and not controlled.shader.code.contains("TIME"),"Native model shader source receives controlled timeline time")
	runtime.set_timeline_time(1.25); check(is_equal_approx(float(controlled.get_shader_parameter(str(controlled.get_meta("kiwi_time_uniform")))),1.25),"Scene model updates native shader uniforms at the evaluated time")
	check(shader.code.contains("TIME") and is_equal_approx(float(material.get_shader_parameter("strength")),.42) and is_equal_approx(float(controlled.get_shader_parameter("strength")),.42),"Runtime preparation preserves author code and shader parameter values")
	material.set_shader_parameter("strength",.81); runtime.set_timeline_time(1.25); check(is_equal_approx(float(controlled.get_shader_parameter("strength")),.81),"Native parameter changes synchronize even without a resource changed signal")
	shader.code="shader_type spatial; uniform float strength=0.7; void fragment(){ALBEDO=vec3(strength,.2,.1);}"; runtime.set_timeline_time(2.)
	check(controlled.get_meta("kiwi_time_uniform","")=="" and controlled.shader.code==shader.code,"Removing TIME updates the linked runtime without leaving a stale time uniform")
	shader.code="shader_type spatial; uniform float strength=0.7; void fragment(){ALBEDO=vec3(abs(sin(TIME)),strength,.1);}"
	check(not str(controlled.get_meta("kiwi_time_uniform","")).is_empty() and is_equal_approx(float(controlled.get_shader_parameter(str(controlled.get_meta("kiwi_time_uniform")))),2.),"Adding TIME at a paused playhead preserves the current evaluated time")
	var saved:=ResourceSaver.save(controlled,"user://native_runtime_material.res"); var loaded:=ResourceLoader.load("user://native_runtime_material.res","",ResourceLoader.CACHE_MODE_IGNORE) as ShaderMaterial
	check(saved==OK and loaded!=null and loaded.shader!=null,"Runtime material metadata remains safely serializable for baked/saved meshes")
	var copied:=controlled.duplicate(false) as ShaderMaterial; var prepared:=KiwiEnvironmentAssets.timeline_material(copied) as ShaderMaterial
	check(prepared!=copied and prepared.get_meta("kiwi_timeline_link").active_for(prepared),"Duplicated and baked materials receive their own runtime binding")
	var transient:=KiwiEnvironmentAssets.timeline_material(material) as ShaderMaterial; var link: WeakRef=weakref(transient.get_meta("kiwi_timeline_link")); transient=null
	check(link.get_ref()==null,"Releasing a runtime material releases its source binding without a signal cycle")
	var independent:=ShaderMaterial.new(); independent.shader=shader; independent.set_shader_parameter("strength",.2); var second:=KiwiEnvironmentAssets.timeline_material(independent) as ShaderMaterial; var clock:=str(second.get_meta("kiwi_time_uniform")); second.set_shader_parameter(clock,7.)
	check(second.shader==controlled.shader and second!=controlled,"Identical source code shares the compiled native shader without sharing material instances")
	check(is_equal_approx(float(second.get_shader_parameter("strength")),.2) and is_equal_approx(float(controlled.get_shader_parameter("strength")),.81) and is_equal_approx(float(second.get_shader_parameter(clock)),7.) and is_equal_approx(float(controlled.get_shader_parameter(clock)),2.),"Shared compilation preserves independent shader parameters and timeline clocks")
	runtime.queue_free(); await process_frame; print("MODEL SOURCE SHADER TIME: %d checks, %d failures"%[checks,failures]); quit(failures)
