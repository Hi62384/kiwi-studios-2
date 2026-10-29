class_name KiwiPowderSource
extends RefCounted
## Pure generation; no integration, collisions, liquid pressure or renderer dependency.
const APPEARANCE := ["powder_color","powder_roughness","powder_show_source"]
const ARRAYS := ["powder_ids","powder_radii","powder_masses","powder_birth_times","powder_birth_positions","powder_sources","powder_compaction","powder_sleep","powder_contacts","powder_phase","powder_settle"]
static func validate(values: Dictionary) -> String:
	if int(values.powder_source_mode) not in [0,1,2]: return "Choose Finite volume, Emitter or Volume + emitter."
	if int(values.powder_budget)<1 or int(values.powder_budget)>65536: return "Maximum grain count must be between 1 and 65,536."
	for key in [&"powder_radius",&"powder_density",&"powder_spacing"]:
		if not is_finite(float(values[key])) or float(values[key])<=0: return "Grain radius, density and spacing must be positive and finite."
	if not (values.powder_emit_velocity as Vector3).is_finite(): return "Initial grain velocity must be finite."
	if int(values.powder_source_mode)!=0:
		if int(values.powder_emit_shape) not in [0,1,2,3]: return "Choose Point, Disk, Box or Sphere for the emitter."
		for key in [&"powder_emit_rate",&"powder_emit_speed",&"powder_emit_radius",&"powder_spread"]:
			if not is_finite(float(values[key])) or float(values[key])<0 or float(values[key])>1000000: return "Emitter values must be finite, nonnegative and within a safe generation range."
		if not (values.powder_emit_direction as Vector3).is_finite() or not (values.powder_emit_dimensions as Vector3).is_finite(): return "Emitter direction and dimensions must be finite."
		var dimensions: Vector3=values.powder_emit_dimensions
		if int(values.powder_emit_shape)==2 and (dimensions.x<=0 or dimensions.y<=0 or dimensions.z<=0): return "Box emitter dimensions must be positive."
		for key in [&"powder_emit_start",&"powder_emit_end"]:
			if not is_finite(float(values[key])): return "Emission times must be finite."
	return ""
static func volume(values: Dictionary,pose: Transform3D,geometry: Dictionary={}) -> Dictionary:
	var invalid:=validate(values)
	if not invalid.is_empty(): return KiwiVolumeSampler.failure(invalid)
	var spacing:=float(values.powder_spacing); var radius:=float(values.powder_radius)*(1.0+clampf(float(values.get(&"powder_size_variation",0)),0,.5))
	if radius<=0 or not is_finite(radius) or spacing<radius*2: return KiwiVolumeSampler.failure("Grain spacing must be at least twice the radius. Increase spacing or reduce grain radius.")
	var jitter:=minf(clampf(float(values.powder_jitter),0,.2),maxf(0,(1.0-2*radius/spacing)*.45))
	return KiwiVolumeSampler.generate(int(values.powder_shape),values.powder_dimensions,spacing,clampi(int(values.powder_budget),1,65536),pose,geometry,jitter,int(values.powder_seed))
static func initialize(state: Dictionary) -> void:
	state.points=PackedVector3Array(); state.velocities=PackedVector3Array()
	state.powder_ids=PackedInt32Array(); state.powder_radii=PackedFloat32Array(); state.powder_masses=PackedFloat32Array(); state.powder_birth_times=PackedFloat64Array(); state.powder_birth_positions=PackedVector3Array(); state.powder_sources=PackedByteArray()
	state.powder_next_id=0; state.powder_emitted=0; state.powder_fraction=0.0; state.powder_error=""; state.powder_warning=""
	state.powder_compaction=PackedFloat32Array(); state.powder_sleep=PackedFloat32Array(); state.powder_contacts=PackedInt32Array(); state.powder_bonds={}
	state.powder_phase=PackedByteArray(); state.powder_settle=PackedFloat32Array(); state.powder_deposits={}; state.powder_supports={}; state.powder_cells={}; state.powder_inventory={}; state.powder_releases=0; state.powder_cleared=false
static func append(state: Dictionary,point: Vector3,velocity: Vector3,values: Dictionary,pose: Transform3D,birth: float,source: int) -> void:
	var scale:=pose.basis.get_scale().abs(); var radius:=maxf(.0001,float(values.powder_radius)*minf(scale.x,minf(scale.y,scale.z)))
	radius*=1.0+rng_for(int(values.powder_seed),int(state.powder_next_id)+1000000).randf_range(-1,1)*clampf(float(values.get(&"powder_size_variation",0)),0,.5)
	state.points.append(point); state.velocities.append(velocity)
	state.powder_ids.append(int(state.powder_next_id)); state.powder_next_id+=1
	state.powder_radii.append(radius); state.powder_masses.append(maxf(.001,float(values.powder_density))*4.0/3.0*PI*radius*radius*radius)
	state.powder_birth_times.append(birth); state.powder_birth_positions.append(point); state.powder_sources.append(source)
	state.powder_compaction.append(0); state.powder_sleep.append(0); state.powder_contacts.append(0)
	state.powder_phase.append(0); state.powder_settle.append(0)
static func rng_for(seed: int,id: int) -> RandomNumberGenerator:
	var rng:=RandomNumberGenerator.new(); rng.seed=(seed*1000003+id*9176+37)&0x7fffffffffffffff; return rng
static func spawn(state: Dictionary,values: Dictionary,pose: Transform3D,velocity: Vector3,birth: float) -> void:
	var rng:=rng_for(int(values.powder_seed),int(state.powder_next_id))
	var axis: Vector3=(values.powder_emit_direction as Vector3).normalized()
	if axis.is_zero_approx(): axis=Vector3.DOWN
	var tangent:=axis.cross(Vector3.RIGHT if absf(axis.x)<.9 else Vector3.UP).normalized(); var bitangent:=axis.cross(tangent)
	var angle:=rng.randf()*TAU; var radial:=tangent*cos(angle)+bitangent*sin(angle); var offset:=Vector3.ZERO
	match int(values.powder_emit_shape):
		1: offset=radial*sqrt(rng.randf())*float(values.powder_emit_radius)
		2: offset=Vector3(rng.randf()-.5,rng.randf()-.5,rng.randf()-.5)*(values.powder_emit_dimensions as Vector3)
		3:
			var y:=rng.randf_range(-1,1); var r:=sqrt(maxf(0,1-y*y))
			offset=Vector3(r*cos(angle),y,r*sin(angle))*pow(rng.randf(),1.0/3.0)*float(values.powder_emit_radius)
	var direction: Vector3=(axis+radial*float(values.powder_spread)*sqrt(rng.randf())).normalized()
	append(state,pose*offset,velocity+pose.basis*(values.powder_emit_velocity+direction*float(values.powder_emit_speed)),values,pose,birth,1)
	state.powder_emitted+=1
