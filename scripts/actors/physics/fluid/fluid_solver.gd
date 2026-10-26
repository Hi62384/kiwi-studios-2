class_name KiwiFluidSolver
extends RefCounted
## Position-based density projection, Poly6 density and Spiky gradients (PBF).
## All time and collision queries are supplied by the shared timeline controller.
static func initialize(state: Dictionary,values: Dictionary,points: PackedVector3Array) -> void:
	state.points=points; state.velocities=PackedVector3Array(); state.velocities.resize(points.size()); state.velocities.fill(state.v)
	state.fluid_ids=PackedInt32Array(); state.fluid_masses=PackedFloat32Array(); state.fluid_foam=PackedFloat32Array(); state.fluid_density=PackedFloat32Array()
	for i in points.size(): state.fluid_ids.append(i); state.fluid_masses.append(float(values.fluid_density)*pow(float(values.spacing),3)); state.fluid_foam.append(0); state.fluid_density.append(1)
	state.fluid_next_id=points.size(); state.fluid_emitted=0; state.fluid_emit_fraction=0.0; state.fluid_contacts=[]; state.fluid_checks=0
static func emit(state: Dictionary,values: Dictionary,pose: Transform3D,velocity: Vector3,local: float,dt: float) -> void:
	if int(values.fluid_source_mode)==0: return
	var start:=float(values.fluid_emit_start); var end:=float(values.fluid_emit_end)
	var duration:=maxf(0.0,minf(local,end if end>=0 else local)-maxf(start,local-dt))
	if duration<=0: return
	state.fluid_emit_fraction+=float(values.fluid_emit_rate)*duration
	var count:=mini(int(floor(state.fluid_emit_fraction)),int(values.budget)-state.points.size()); state.fluid_emit_fraction-=floor(state.fluid_emit_fraction)
	if int(values.fluid_supply)>0: count=mini(count,maxi(0,int(values.fluid_supply)-int(state.fluid_emitted)))
	var axis: Vector3=(values.fluid_emit_direction as Vector3).normalized()
	if axis.is_zero_approx(): axis=Vector3.DOWN
	var tangent:=axis.cross(Vector3.RIGHT if absf(axis.x)<.9 else Vector3.UP).normalized(); var bitangent:=axis.cross(tangent)
	for i in count:
		var id:=int(state.fluid_next_id); var a:=random(id*3+1); var b:=random(id*3+2); var c:=random(id*3+3)
		var radial:=tangent*(cos(a*TAU)*sqrt(b))+bitangent*(sin(a*TAU)*sqrt(b))
		var offset:=radial*float(values.fluid_emit_radius)
		match int(values.get(&"fluid_emit_shape",0)):
			1: offset=Vector3(a-.5,b-.5,c-.5)*2.0*float(values.fluid_emit_radius)
			2: offset=Vector3(a-.5,b-.5,c-.5).normalized()*pow(random(id*3+4),1.0/3.0)*float(values.fluid_emit_radius)
		state.points.append(pose*offset)
		state.velocities.append(velocity+pose.basis*((axis+radial*float(values.fluid_spread)).normalized()*float(values.fluid_emit_speed)))
		state.fluid_ids.append(id); state.fluid_masses.append(float(values.fluid_density)*pow(float(values.spacing),3)); state.fluid_foam.append(0); state.fluid_density.append(1)
		state.fluid_next_id+=1; state.fluid_emitted+=1
static func random(seed: int) -> float: return float((seed*1103515245+12345)&0x7fffffff)/2147483648.0
static func neighbors(points: PackedVector3Array,h: float) -> Dictionary:
	var grid:={}; var cells:=[]; var output:=[]; var checks:=0
	for i in points.size():
		var cell:=Vector3i(floor(points[i].x/h),floor(points[i].y/h),floor(points[i].z/h)); cells.append(cell)
		if not grid.has(cell): grid[cell]=[]
		grid[cell].append(i)
	for i in points.size():
		var near:=PackedInt32Array(); var cell: Vector3i=cells[i]
		for x in range(-1,2):
			for y in range(-1,2):
				for z in range(-1,2):
					for j: int in grid.get(cell+Vector3i(x,y,z),[]):
						checks+=1
						if j!=i and points[i].distance_squared_to(points[j])<h*h and near.size()<128: near.append(j)
		output.append(near)
	return {"neighbors":output,"checks":checks}
static func kernel(distance_squared: float,h: float) -> float:
	var q:=maxf(0,1.0-distance_squared/(h*h)); return 315.0/(64.0*PI*h*h*h)*q*q*q
static func gradient(delta: Vector3,h: float) -> Vector3:
	var distance:=delta.length()
	if distance<.000001 or distance>=h: return Vector3.ZERO
	return delta*(-45.0/(PI*pow(h,4))*pow(1.0-distance/h,2)/distance)
static func step(state: Dictionary,values: Dictionary,gravity: Vector3,impulse: Vector3,dt: float,collide: Callable,compute: KiwiFluidCompute=null) -> void:
	if state.points.is_empty(): return
	if compute!=null and compute.available(): _gpu_step(state,values,gravity,impulse,dt,collide,compute); return
	var spacing: float=values.spacing; var h:=spacing*2.05; var volume:=spacing*spacing*spacing; var n: int=state.points.size()
	var speed:=0.0
	for v: Vector3 in state.velocities: speed=maxf(speed,v.length())
	var substeps:=clampi(maxi(int(values.substeps),ceili(speed*dt/(spacing*.45))),1,8); var tick:=dt/substeps
	state.fluid_contacts=[]; state.fluid_checks=0
	for substep in substeps:
		var previous: PackedVector3Array=state.points.duplicate()
		for i in n:
			if substep==0: state.velocities[i]+=impulse/maxf(.001,float(state.fluid_masses[i]))
			state.velocities[i]=(state.velocities[i]+gravity*tick).limit_length(float(values.fluid_max_speed))
			state.points[i]+=state.velocities[i]*tick
		var near:=neighbors(state.points,h); state.fluid_checks+=near.checks
		for iteration in int(values.iterations):
			var lambda:=PackedFloat32Array(); lambda.resize(n)
			for i in n:
				var density:=volume*kernel(0,h); var sum_gradient:=Vector3.ZERO; var denominator:=float(values.fluid_compliance)/(spacing*spacing)
				for j: int in near.neighbors[i]:
					var delta: Vector3=state.points[i]-state.points[j]; density+=volume*kernel(delta.length_squared(),h)
					var g:=gradient(delta,h)*volume; sum_gradient+=g; denominator+=g.length_squared()
				state.fluid_density[i]=density; denominator+=sum_gradient.length_squared()
				lambda[i]=-maxf(density-1.0,0.0)/maxf(.000001,denominator)
			var corrections:=PackedVector3Array(); corrections.resize(n)
			for i in n:
				var correction:=Vector3.ZERO
				for j: int in near.neighbors[i]:
					var delta: Vector3=state.points[i]-state.points[j]
					var artificial:=-.00005*pow(kernel(delta.length_squared(),h)/kernel(h*h*.09,h),4)*spacing*spacing
					correction+=(lambda[i]+lambda[j]+artificial)*volume*gradient(delta,h)
				corrections[i]=correction.limit_length(spacing*.25)
			for i in n: state.points[i]+=corrections[i]
			if iteration+1<int(values.iterations): near=neighbors(state.points,h); state.fluid_checks+=near.checks
		var velocities:=PackedVector3Array(); velocities.resize(n)
		for i in n: velocities[i]=(state.points[i]-previous[i])/tick
		var viscosity:=float(values.fluid_viscosity)
		if int(values.fluid_preset)==4: viscosity*=exp(clampf((1100.0-float(values.fluid_temperature))/1000.0,-2,2))
		for i in n:
			var weighted:=Vector3.ZERO; var weight:=0.0; var attraction:=Vector3.ZERO
			for j: int in near.neighbors[i]:
				var delta: Vector3=state.points[j]-state.points[i]; var w:=volume*kernel(delta.length_squared(),h)
				weighted+=(velocities[j]-velocities[i])*w; weight+=w
				if delta.length_squared()>spacing*spacing: attraction+=delta*w*float(values.fluid_cohesion)
				attraction+=delta*w*float(values.fluid_tension)*.2
			var v: Vector3=velocities[i]+weighted/maxf(1.0,weight)*(1.0-exp(-viscosity*tick))+attraction*tick
			var result: Dictionary=collide.call(previous[i],state.points[i],spacing*.32,v)
			state.points[i]=result.position
			state.fluid_foam[i]*=exp(-tick/maxf(.05,float(values.fluid_foam_duration)))
			for hit: Dictionary in result.get("hits",[]):
				var normal: Vector3=hit.normal; var surface_velocity: Vector3=hit.get("velocity",Vector3.ZERO)
				var relative:=v-surface_velocity; var impact:=maxf(0,-relative.dot(normal))
				if impact>0: relative+=normal*impact*(1.0+float(values.fluid_restitution))
				var tangent:=relative-normal*relative.dot(normal); relative-=tangent*clampf(float(values.fluid_boundary_friction)*tick*40,0,1); v=relative+surface_velocity
				state.fluid_foam[i]=maxf(state.fluid_foam[i],clampf(impact/6,0,1))
				if state.fluid_contacts.size()<64 and impact>.1: state.fluid_contacts.append({"position":result.position,"normal":normal,"relative_velocity":velocities[i]-surface_velocity,"intensity":impact*float(state.fluid_masses[i]),"actor":hit.get("actor",""),"preset":int(values.fluid_preset),"temperature":float(values.fluid_temperature),"particle":int(state.fluid_ids[i])})
			state.velocities[i]=v.limit_length(float(values.fluid_max_speed))
			if not state.points[i].is_finite() or not state.velocities[i].is_finite(): state.points[i]=previous[i]; state.velocities[i]=Vector3.ZERO
static func _gpu_step(state: Dictionary,values: Dictionary,gravity: Vector3,impulse: Vector3,dt: float,collide: Callable,compute: KiwiFluidCompute) -> void:
	var spacing:=float(values.spacing); var speed:=0.0
	for i in state.points.size():
		state.velocities[i]+=impulse/maxf(.001,float(state.fluid_masses[i])); speed=maxf(speed,state.velocities[i].length())
	var substeps:=clampi(maxi(int(values.substeps),ceili(speed*dt/(spacing*.45))),1,8); var tick:=dt/substeps
	state.fluid_contacts=[]; state.fluid_checks=0
	for substep in substeps:
		var previous: PackedVector3Array=state.points.duplicate()
		compute.project(state,values,gravity,tick)
		for i in state.points.size():
			var v: Vector3=state.velocities[i]; var result: Dictionary=collide.call(previous[i],state.points[i],spacing*.32,v); state.points[i]=result.position
			state.fluid_foam[i]*=exp(-tick/maxf(.05,float(values.fluid_foam_duration)))
			for hit: Dictionary in result.get("hits",[]):
				var normal: Vector3=hit.normal; var surface_velocity: Vector3=hit.get("velocity",Vector3.ZERO); var relative:=v-surface_velocity; var impact:=maxf(0,-relative.dot(normal))
				if impact>0: relative+=normal*impact*(1.0+float(values.fluid_restitution))
				var tangent:=relative-normal*relative.dot(normal); relative-=tangent*clampf(float(values.fluid_boundary_friction)*tick*40,0,1); v=relative+surface_velocity
				state.fluid_foam[i]=maxf(state.fluid_foam[i],clampf(impact/6,0,1))
				if state.fluid_contacts.size()<64 and impact>.1: state.fluid_contacts.append({"position":result.position,"normal":normal,"relative_velocity":state.velocities[i]-surface_velocity,"intensity":impact*float(state.fluid_masses[i]),"actor":hit.get("actor",""),"preset":int(values.fluid_preset),"temperature":float(values.fluid_temperature),"particle":int(state.fluid_ids[i])})
			state.velocities[i]=v.limit_length(float(values.fluid_max_speed))
			if not state.points[i].is_finite() or not state.velocities[i].is_finite(): state.points[i]=previous[i]; state.velocities[i]=Vector3.ZERO
