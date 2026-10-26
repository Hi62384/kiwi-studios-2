class_name KiwiFluidCompute
extends RefCounted
var device: RenderingDevice
var shader:=RID()
var pipeline:=RID()
var buffers: Array[RID]=[]
var uniforms:=RID()
var capacity:=-1
var error:=""
func _init() -> void:
	if RenderingServer.get_rendering_device()==null: error="GPU compute requires Forward+ or Mobile rendering."; return
	device=RenderingServer.create_local_rendering_device()
	if device==null: error="GPU compute unavailable; using bounded CPU fallback."; return
	var source:=RDShaderSource.new(); source.source_compute=FileAccess.get_file_as_string("res://scripts/actors/physics/fluid/fluid_compute.glsl").replace("#[compute]","")
	var spirv:=device.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty(): error=spirv.compile_error_compute; return
	shader=device.shader_create_from_spirv(spirv); pipeline=device.compute_pipeline_create(shader)
func available() -> bool: return pipeline.is_valid()
func dispose() -> void:
	if device==null: return
	if uniforms.is_valid(): device.free_rid(uniforms); uniforms=RID()
	for buffer in buffers: device.free_rid(buffer)
	buffers.clear()
	if pipeline.is_valid(): device.free_rid(pipeline); pipeline=RID()
	if shader.is_valid(): device.free_rid(shader); shader=RID()
	device.free(); device=null
func _allocate(n: int) -> void:
	if capacity==n: return
	if uniforms.is_valid(): device.free_rid(uniforms)
	for buffer in buffers: device.free_rid(buffer)
	buffers.clear(); var bindings: Array[RDUniform]=[]
	for i in 8:
		var bytes: int=4096*4 if i==5 else (64 if i==7 else (n*4 if i==6 else n*16))
		var buffer:=device.storage_buffer_create(bytes); buffers.append(buffer)
		var uniform:=RDUniform.new(); uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; uniform.binding=i; uniform.add_id(buffer); bindings.append(uniform)
	uniforms=device.uniform_set_create(bindings,shader,0); capacity=n
func project(state: Dictionary,settings: Dictionary,gravity: Vector3,dt: float) -> void:
	var n: int=state.points.size(); _allocate(n)
	var positions:=PackedFloat32Array(); var velocities:=PackedFloat32Array(); positions.resize(n*4); velocities.resize(n*4)
	for i in n:
		for axis in 3: positions[i*4+axis]=state.points[i][axis]; velocities[i*4+axis]=state.velocities[i][axis]
	var viscosity:=float(settings.fluid_viscosity)
	if int(settings.fluid_preset)==4: viscosity*=exp(clampf((1100-float(settings.fluid_temperature))/1000,-2,2))
	var spacing:=float(settings.spacing)
	var config:=PackedFloat32Array([gravity.x,gravity.y,gravity.z,dt,spacing*2.05,pow(spacing,3),float(settings.fluid_compliance),viscosity,float(settings.fluid_cohesion),float(settings.fluid_tension),spacing,float(settings.fluid_max_speed),0,0,0,0])
	device.buffer_update(buffers[0],0,positions.size()*4,positions.to_byte_array()); device.buffer_update(buffers[2],0,velocities.size()*4,velocities.to_byte_array()); device.buffer_update(buffers[7],0,64,config.to_byte_array())
	var list:=device.compute_list_begin(); device.compute_list_bind_compute_pipeline(list,pipeline); device.compute_list_bind_uniform_set(list,uniforms,0)
	var stages: Array[int]=[1]
	for iteration in int(settings.iterations): stages.append_array([0,2,3,4,5])
	stages.append_array([6,0,2,7,8])
	for stage in stages:
		device.compute_list_set_push_constant(list,PackedInt32Array([stage,n,0,0]).to_byte_array(),16)
		device.compute_list_dispatch(list,ceili(float(4096 if stage==0 else n)/64),1,1); device.compute_list_add_barrier(list)
	device.compute_list_end(); device.submit(); device.sync()
	positions=device.buffer_get_data(buffers[0]).to_float32_array(); velocities=device.buffer_get_data(buffers[2]).to_float32_array(); var density:=device.buffer_get_data(buffers[4]).to_float32_array()
	for i in n:
		state.points[i]=Vector3(positions[i*4],positions[i*4+1],positions[i*4+2]); state.velocities[i]=Vector3(velocities[i*4],velocities[i*4+1],velocities[i*4+2]); state.fluid_density[i]=density[i*4+1]
