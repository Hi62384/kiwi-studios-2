extends RefCounted
## CPU reference transport. Concentration uses conservative face fluxes; velocity
## uses advection/forces/projection. No renderer nodes, clocks or undo operations.
const MAX_RESOLUTION:=32
static var grids: Dictionary={}

static func grid(n: int) -> Dictionary:
	if grids.has(n): return grids[n]
	var neighbors:=PackedInt32Array(); neighbors.resize(n*n*n*6); var positions:=PackedVector3Array(); positions.resize(n*n*n)
	for z in n:
		for y in n:
			for x in n:
				var i:=x+n*(y+n*z); positions[i]=(Vector3(x,y,z)+Vector3.ONE*.5)/n-Vector3.ONE*.5
				for axis in 3:
					var coordinate: int=[x,y,z][axis]; var stride: int=[1,n,n*n][axis]
					neighbors[i*6+axis*2]=i-stride if coordinate>0 else -1
					neighbors[i*6+axis*2+1]=i+stride if coordinate<n-1 else -1
	var result:={"neighbors":neighbors,"positions":positions}; grids[n]=result; return result

static func initialize(n: int,size: Vector3,density: PackedFloat32Array=PackedFloat32Array()) -> Dictionary:
	n=clampi(n,4,MAX_RESOLUTION); size=size.abs().max(Vector3.ONE*.01); var count:=n*n*n
	var rho:=density.duplicate() if density.size()==count else PackedFloat32Array(); rho.resize(count)
	for i in count: rho[i]=maxf(0.,rho[i]) if is_finite(rho[i]) else 0.
	var velocity:=PackedVector3Array(); velocity.resize(count); var solid:=PackedByteArray(); solid.resize(count); var pressure:=PackedFloat32Array(); pressure.resize(count)
	return {"fog_n":n,"fog_size":size,"fog_density":rho,"fog_velocity":velocity,"fog_solid":solid,"fog_boundary_velocity":velocity.duplicate(),"fog_pressure":pressure,"fog_time":0.,"fog_step":0,"fog_emitted":0.,"fog_lost":0.,"fog_trapped":{},"fog_bursts":{},"fog_clamped":false}

static func total_mass(state: Dictionary) -> float:
	var amount:=0.
	for value: float in state.fog_density: amount+=value
	for value: float in state.fog_trapped.values(): amount+=value
	var size: Vector3=state.fog_size; return amount*size.x*size.y*size.z/pow(float(state.fog_n),3.)

static func set_obstacles(state: Dictionary,solid: PackedByteArray,boundary_velocity: PackedVector3Array) -> void:
	var rho: PackedFloat32Array=state.fog_density; var count:=rho.size()
	if solid.size()!=count or boundary_velocity.size()!=count: return
	var neighbors: PackedInt32Array=grid(int(state.fog_n)).neighbors; var trapped: Dictionary=state.fog_trapped
	for key: int in trapped.keys():
		if solid[key]==0: rho[key]+=float(trapped[key]); trapped.erase(key)
	for i in count:
		if solid[i]==0 or rho[i]<=0.: continue
		var free:=PackedInt32Array()
		for slot in 6:
			var j:=neighbors[i*6+slot]
			if j>=0 and solid[j]==0: free.append(j)
		if free.is_empty(): trapped[i]=float(trapped.get(i,0.))+rho[i]
		else:
			var share:=rho[i]/free.size()
			for j in free: rho[j]+=share
		rho[i]=0.
	state.fog_density=rho; state.fog_solid=solid.duplicate(); state.fog_boundary_velocity=boundary_velocity.duplicate(); state.fog_trapped=trapped

static func inject(state: Dictionary,cells: PackedInt32Array,weights: PackedFloat32Array,mass: float,velocity: Vector3) -> void:
	if cells.size()!=weights.size() or mass<=0. or not is_finite(mass): return
	var rho: PackedFloat32Array=state.fog_density; var v: PackedVector3Array=state.fog_velocity; var solid: PackedByteArray=state.fog_solid; var sum:=0.
	for index in cells.size():
		if cells[index]>=0 and cells[index]<rho.size() and solid[cells[index]]==0: sum+=maxf(0.,weights[index])
	if sum<=0.: return
	var size: Vector3=state.fog_size; var cell_volume:=size.x*size.y*size.z/rho.size()
	for index in cells.size():
		var i:=cells[index]
		if i<0 or i>=rho.size() or solid[i]!=0: continue
		var added:=mass*maxf(0.,weights[index])/sum/cell_volume; var next:=rho[i]+added
		v[i]=(v[i]*rho[i]+velocity*added)/maxf(.000001,next); rho[i]=next
	state.fog_density=rho; state.fog_velocity=v; state.fog_emitted=float(state.fog_emitted)+mass

static func velocity_sample(velocities: PackedVector3Array,solid: PackedByteArray,point: Vector3,size: Vector3,n: int) -> Vector3:
	var p:=((point/size+Vector3.ONE*.5)*n-Vector3.ONE*.5).clamp(Vector3.ZERO,Vector3.ONE*(n-1)); var base:=Vector3i(p.floor()); var fraction:=p-Vector3(base); var value:=Vector3.ZERO; var weight_sum:=0.
	for z in 2:
		for y in 2:
			for x in 2:
				var cell: Vector3i=(base+Vector3i(x,y,z)).min(Vector3i.ONE*(n-1)); var i:=cell.x+n*(cell.y+n*cell.z)
				if solid[i]!=0: continue
				var weight: float=(fraction.x if x==1 else 1.-fraction.x)*(fraction.y if y==1 else 1.-fraction.y)*(fraction.z if z==1 else 1.-fraction.z); value+=velocities[i]*weight; weight_sum+=weight
	return value/maxf(.000001,weight_sum)

static func field_acceleration(fields: Array,point: Vector3,time: float) -> Vector3:
	var value:=Vector3.ZERO
	for field: Dictionary in fields:
		if not field.get("enabled",true): continue
		var offset: Vector3=point-field.get("center",Vector3.ZERO); var radius:=maxf(.001,float(field.get("radius",1.))); var distance:=offset.length()/radius
		if distance>1.: continue
		var strength:=float(field.get("strength",1.))*pow(1.-distance,maxf(0.,float(field.get("falloff",1.)))); var direction: Vector3=field.get("direction",Vector3.UP)
		match int(field.get("type",0)):
			1: direction=offset.normalized()
			2: direction=-offset.normalized()
			3: direction=direction.normalized().cross(offset)/radius
			4: direction=Vector3(sin(point.z+time),cos(point.x-time),sin(point.y+time))
		value+=direction*strength
	return value

static func step(state: Dictionary,config: Dictionary,dt: float) -> void:
	if dt<=0. or not is_finite(dt): return
	var n:=int(state.fog_n); var size: Vector3=state.fog_size; var h:=size/n; var maximum:=0.; var wind: Vector3=config.get("wind",Vector3.ZERO)
	for v: Vector3 in state.fog_velocity:
		if v.is_finite(): maximum=maxf(maximum,maxf(absf(v.x),maxf(absf(v.y),absf(v.z))))
	maximum=maxf(maximum,maxf(absf(wind.x),maxf(absf(wind.y),absf(wind.z))))
	var substeps:=clampi(ceili(maximum*dt/maxf(.0001,minf(h.x,minf(h.y,h.z)))*6./.8),1,8)
	for substep in substeps: substep_state(state,config,dt/substeps)
	state.fog_step=int(state.fog_step)+1

static func substep_state(state: Dictionary,config: Dictionary,dt: float) -> void:
	var n:=int(state.fog_n); var size: Vector3=state.fog_size; var h:=size/n; var data:=grid(n); var positions: PackedVector3Array=data.positions; var neighbors: PackedInt32Array=data.neighbors; var count:=positions.size()
	var rho: PackedFloat32Array=state.fog_density; var old: PackedVector3Array=state.fog_velocity; var solid: PackedByteArray=state.fog_solid; var boundary: PackedVector3Array=state.fog_boundary_velocity; var v:=old.duplicate(); var time:=float(state.fog_time)+dt
	var wind: Vector3=config.get("wind",Vector3.ZERO); var response:=1.-exp(-maxf(0.,float(config.get("wind_response",2.)))*dt); var damping:=exp(-maxf(0.,float(config.get("damping",.1)))*dt); var turbulence:=float(config.get("turbulence",0.)); var scale:=maxf(.001,float(config.get("turbulence_scale",1.))); var phase:=time*float(config.get("turbulence_frequency",1.))+float(config.get("seed",1))*1.732
	var fields: Array=config.get("fields",[])
	for i in count:
		if solid[i]!=0: v[i]=boundary[i]; continue
		var p:=positions[i]*size; var flow:=velocity_sample(old,solid,p-old[i]*dt,size,n)*damping; flow=flow.lerp(wind,response)
		var q:=p/scale; var curl:=Vector3(sin(q.z+phase)+cos(q.y-phase),sin(q.x+phase)+cos(q.z-phase),sin(q.y+phase)+cos(q.x-phase))
		flow+=(curl*turbulence+field_acceleration(fields,p,time)+(config.get("buoyancy_direction",Vector3.UP) as Vector3)*float(config.get("buoyancy",0.))*rho[i])*dt
		v[i]=flow if flow.is_finite() else Vector3.ZERO
	v=project(v,solid,boundary,neighbors,h,dt,clampi(int(config.get("pressure_iterations",6)),0,32),bool(config.get("closed",false)),state)
	var limit:=minf(h.x,minf(h.y,h.z))*.8/(6.*dt); var expansion:=float(config.get("expansion",0.))
	for i in count:
		if solid[i]!=0: continue
		v[i]+=positions[i]*expansion
		if not v[i].is_finite(): v[i]=Vector3.ZERO; state.fog_clamped=true
		var bounded:=v[i].clamp(-Vector3.ONE*limit,Vector3.ONE*limit)
		if bounded!=v[i]: state.fog_clamped=true
		v[i]=bounded
	var delta:=PackedFloat32Array(); delta.resize(count); var lost:=0.; var closed:=bool(config.get("closed",false))
	for i in count:
		if solid[i]!=0: continue
		for axis in 3:
			var j:=neighbors[i*6+axis*2+1]
			if j>=0 and solid[j]==0:
				var speed: float=(v[i][axis]+v[j][axis])*.5; var amount: float=speed*dt/h[axis]*(rho[i] if speed>=0. else rho[j]); delta[i]-=amount; delta[j]+=amount
			elif j<0 and not closed:
				var amount: float=maxf(0.,v[i][axis])*dt/h[axis]*rho[i]; delta[i]-=amount; lost+=amount
			if neighbors[i*6+axis*2]<0 and not closed:
				var amount: float=maxf(0.,-v[i][axis])*dt/h[axis]*rho[i]; delta[i]-=amount; lost+=amount
	for i in count: rho[i]=maxf(0.,rho[i]+delta[i])
	var diffusion:=maxf(0.,float(config.get("diffusion",0.)))
	if diffusion>0.:
		delta.fill(0.)
		for i in count:
			if solid[i]!=0: continue
			for axis in 3:
				var j:=neighbors[i*6+axis*2+1]
				if j<0 or solid[j]!=0: continue
				var amount: float=(rho[i]-rho[j])*minf(1./6.,diffusion*dt/(h[axis]*h[axis])); delta[i]-=amount; delta[j]+=amount
		for i in count: rho[i]=maxf(0.,rho[i]+delta[i])
	var dissipation:=maxf(0.,float(config.get("dissipation",0.))); var sink: PackedFloat32Array=config.get("sink_mask",PackedFloat32Array()); var maximum:=maxf(.01,float(config.get("max_density",32.)))
	for i in count:
		var value:=rho[i]*exp(-dissipation*dt*(sink[i] if sink.size()==count else 1.)); lost+=rho[i]-value; var bounded:=minf(value,maximum); lost+=value-bounded; rho[i]=bounded
	state.fog_density=rho; state.fog_velocity=v; state.fog_time=time; state.fog_lost=float(state.fog_lost)+lost*size.x*size.y*size.z/count

static func project(v: PackedVector3Array,solid: PackedByteArray,boundary: PackedVector3Array,neighbors: PackedInt32Array,h: Vector3,dt: float,iterations: int,closed: bool,state: Dictionary) -> PackedVector3Array:
	var count:=v.size(); var pressure: PackedFloat32Array=state.fog_pressure; var divergence:=PackedFloat32Array(); divergence.resize(count); var weights:=Vector3.ONE/(h*h)
	var largest_divergence:=0.
	for i in count:
		if solid[i]!=0: continue
		var sum:=0.
		for axis in 3:
			for side in 2:
				var j:=neighbors[i*6+axis*2+side]; var face: float=v[i][axis]
				if j>=0: face=(v[i][axis]+v[j][axis])*.5 if solid[j]==0 else boundary[j][axis]
				elif closed: face=0.
				sum+=face*(1. if side==1 else -1.)/h[axis]
		divergence[i]=sum/dt
		largest_divergence=maxf(largest_divergence,absf(divergence[i]))
	if largest_divergence<.000001: pressure.fill(0.); iterations=0
	for iteration in iterations:
		var next:=pressure.duplicate()
		for i in count:
			if solid[i]!=0: next[i]=0.; continue
			var sum:=0.; var denominator:=0.
			for axis in 3:
				for side in 2:
					var j:=neighbors[i*6+axis*2+side]
					if j>=0 and solid[j]==0: sum+=pressure[j]*weights[axis]; denominator+=weights[axis]
					elif j<0 and not closed: denominator+=weights[axis]
			var value: float=(sum-divergence[i])/denominator if denominator>0. else 0.; next[i]=value if is_finite(value) else 0.
		pressure=next
	for i in count:
		if solid[i]!=0: continue
		var value:=v[i]
		for axis in 3:
			var minus:=neighbors[i*6+axis*2]; var plus:=neighbors[i*6+axis*2+1]; var a: float=pressure[minus] if minus>=0 and solid[minus]==0 else (pressure[i] if minus>=0 or closed else 0.); var b: float=pressure[plus] if plus>=0 and solid[plus]==0 else (pressure[i] if plus>=0 or closed else 0.)
			value[axis]-=dt*(b-a)/(2.*h[axis])
			if plus>=0 and solid[plus]!=0: value[axis]=minf(value[axis],boundary[plus][axis])
			elif plus<0 and closed: value[axis]=minf(value[axis],0.)
			if minus>=0 and solid[minus]!=0: value[axis]=maxf(value[axis],boundary[minus][axis])
			elif minus<0 and closed: value[axis]=maxf(value[axis],0.)
		v[i]=value
	state.fog_pressure=pressure; return v
