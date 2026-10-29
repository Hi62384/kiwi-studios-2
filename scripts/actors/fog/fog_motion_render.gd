extends RefCounted
static func procedural(runtime: Node,values: Dictionary,time: float) -> void:
	if not runtime.content is FogVolume: return
	var material:=runtime.content.material as ShaderMaterial
	if material==null or material.shader!=preload("res://scripts/actors/fog/fog_surface.gdshader"): return
	var enabled:=int(values.get(&"fog_motion_mode",0)) in [1,3]; material.set_shader_parameter("procedural_motion",enabled)
	if not enabled: return
	var wind: Vector3=values.get(&"fog_wind",Vector3.ZERO); wind*=float(values.get(&"fog_wind_influence",1.)); var frequency:=float(values.get(&"fog_gust_frequency",1.)); var gust:=float(values.get(&"fog_gust_strength",0.))
	# Integral of the sinusoidal gust, rather than current speed * elapsed time.
	var elapsed:=time+gust*(1.-cos(time*frequency))/maxf(.000001,frequency) if frequency>0. else time
	var dimensions: Vector3=runtime.content.size.max(Vector3.ONE*.001); var local: Vector3=runtime.content.global_basis.inverse()*wind*elapsed
	material.set_shader_parameter("motion_unit_offset",local/dimensions); material.set_shader_parameter("motion_world_offset",wind*elapsed)
	material.set_shader_parameter("motion_rotation",Basis.from_euler((values.get(&"fog_procedural_rotation",Vector3.ZERO) as Vector3)*time*PI/180.))
	material.set_shader_parameter("motion_turbulence",float(values.get(&"fog_turbulence",0.))); material.set_shader_parameter("motion_scale",float(values.get(&"fog_turbulence_scale",1.))); var seed:=float(values.get(&"fog_seed",1))*1.732; material.set_shader_parameter("motion_phase",time*float(values.get(&"fog_turbulence_frequency",1.))+seed); material.set_shader_parameter("motion_seed",seed)

static func clear(runtime: Node) -> void:
	if runtime==null or not runtime.get("content") is FogVolume: return
	var fog: FogVolume=runtime.content
	if fog.material is ShaderMaterial and fog.material.shader==preload("res://scripts/actors/fog/fog_surface.gdshader"): fog.material.set_shader_parameter("has_simulation",false)
	elif fog.material is ShaderMaterial: fog.material.set_shader_parameter("kiwi_simulation_enabled",false)
	for key in ["kiwi_fog_simulation_texture","kiwi_fog_simulation_key","kiwi_fog_shadow_grid"]:
		if fog.has_meta(key): fog.remove_meta(key)

static func apply(runtime: Node,state: Dictionary,values: Dictionary) -> Dictionary:
	var result:={"upload_ms":0.,"error":""}
	if not runtime.content is FogVolume or not state.has("fog_density"): return result
	var fog: FogVolume=runtime.content; var material:=fog.material as ShaderMaterial
	if material==null: result.error="Assign a built-in appearance or a fog shader with the kiwi_density sampler interface."; return result
	if material.shader==null: result.error="The assigned fog material has no shader."; return result
	var built_in:=material.shader==preload("res://scripts/actors/fog/fog_surface.gdshader"); var compatible:=false
	if not built_in:
		for uniform: Dictionary in material.shader.get_shader_uniform_list():
			if str(uniform.get("name",""))=="kiwi_density": compatible=true
		if not compatible: result.error="Simulation is calculated, but this custom fog shader does not sample kiwi_density."; return result
	var n:=int(state.fog_n); var density: PackedFloat32Array=state.fog_density; var key:=hash([n,density]); var texture: ImageTexture3D=fog.get_meta("kiwi_fog_simulation_texture") if fog.has_meta("kiwi_fog_simulation_texture") else null
	if not fog.has_meta("kiwi_fog_simulation_key") or int(fog.get_meta("kiwi_fog_simulation_key"))!=key:
		var start:=Time.get_ticks_usec(); var bytes:=density.to_byte_array(); var slices: Array[Image]=[]
		for z in n: slices.append(Image.create_from_data(n,n,false,Image.FORMAT_RF,bytes.slice(z*n*n*4,(z+1)*n*n*4)))
		if texture==null or texture.get_width()!=n: texture=ImageTexture3D.new(); texture.create(Image.FORMAT_RF,n,n,n,false,slices); fog.set_meta("kiwi_fog_simulation_texture",texture)
		else: texture.update(slices)
		fog.set_meta("kiwi_fog_simulation_key",key); result.upload_ms=float(Time.get_ticks_usec()-start)/1000.
	var pose: Transform3D=state.fog_pose; var dimensions: Vector3=state.fog_size; fog.global_transform=pose; fog.size=dimensions; fog.shape=RenderingServer.FOG_VOLUME_SHAPE_BOX
	fog.set_meta("kiwi_fog_shadow_grid",{"n":n,"density":density,"key":key})
	var to_unit:=Transform3D(Basis.from_scale(Vector3.ONE/dimensions),Vector3.ONE*.5)*pose.affine_inverse()
	material.set_shader_parameter("simulation_density" if built_in else "kiwi_density",texture); material.set_shader_parameter("simulation_to_unit" if built_in else "kiwi_density_world_to_unit",to_unit)
	material.set_shader_parameter("has_simulation" if built_in else "kiwi_simulation_enabled",true)
	if built_in:
		material.set_shader_parameter("world_to_local",pose.affine_inverse()); material.set_shader_parameter("volume_dimensions",dimensions); material.set_shader_parameter("shape_kind",3); material.set_shader_parameter("global_volume",false); procedural(runtime,values,float(state.fog_time))
	return result
