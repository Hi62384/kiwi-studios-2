class_name KiwiPowderFluid
extends RefCounted
## Kernel-sampled drag/buoyancy and mass-weighted, two-way positional exclusion.
## Fluid keeps its own PBF solver. No pressure constraint is applied to grains.
static func fluids(controller: KiwiTimelinePhysics,batch: Dictionary,time: float) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for id: String in controller.prototypes:
		var state: Dictionary=controller.states[id]
		if int(state.type)!=6 or not state.active or not state.initialized or state.points.is_empty(): continue
		var actor: ActorData=controller.prototypes[id].actor; var config:=KiwiPhysicsSettings.sample(actor,controller._local(actor,time))
		if not batch.config.collision or not config.collision or (int(batch.config.mask)&int(config.layer))==0 or (int(config.mask)&int(batch.config.layer))==0: continue
		var values:=KiwiFluidBridge.values(controller,id,time); var h:=float(values.spacing)*2.05; var grid:={}
		for i in state.points.size():
			var cell:=Vector3i((state.points[i]/h).floor())
			if not grid.has(cell): grid[cell]=[]
			grid[cell].append(i)
		result.append({"id":id,"state":state,"values":values,"grid":grid,"h":h,"moving":int(config.mode) in [1,2],"speed":float(controller.prototypes[id].clip.playback_speed)})
	return result
static func near(fluid: Dictionary,point: Vector3) -> PackedInt32Array:
	var cell:=Vector3i((point/float(fluid.h)).floor()); var result:=PackedInt32Array()
	for x in range(-1,2):
		for y in range(-1,2):
			for z in range(-1,2):
				for i: int in fluid.grid.get(cell+Vector3i(x,y,z),[]):
					if point.distance_squared_to(fluid.state.points[i])<float(fluid.h)*float(fluid.h): result.append(i)
	return result
static func forces(controller: KiwiTimelinePhysics,batches: Array[Dictionary],time: float) -> void:
	for batch: Dictionary in batches:
		if not batch.moving or float(batch.settings.fluid_strength)<=0: continue
		var state: Dictionary=batch.state; var strength:=float(batch.settings.fluid_strength); var dt:=float(batch.h)
		var grain_speed: float=controller.prototypes[batch.id].clip.playback_speed
		for fluid in fluids(controller,batch,time):
			for i in state.points.size():
				if state.has("powder_phase") and int(state.powder_phase[i])==KiwiPowderTransport.Phase.DEPOSITED: continue
				var neighbors:=near(fluid,state.points[i]); var weights:=PackedFloat32Array(); var total:=0.0; var velocity:=Vector3.ZERO
				for j in neighbors:
					var weight:=KiwiFluidSolver.kernel(state.points[i].distance_squared_to(fluid.state.points[j]),float(fluid.h))*pow(float(fluid.values.spacing),3)
					weights.append(weight); total+=weight; velocity+=(fluid.state.velocities[j] as Vector3)*weight*float(fluid.speed)/maxf(.001,grain_speed)
				if total<=.000001: continue
				velocity/=total
				var radius:=float(state.powder_radii[i]); var mass:=float(batch.settings.density)*4.0/3.0*PI*pow(radius,3); var occupancy:=clampf(total,0,1)
				var relative: Vector3=velocity-state.velocities[i]
				var drag:=.5*float(fluid.values.fluid_density)*.47*PI*radius*radius/mass*relative.length()*occupancy*strength
				var change: Vector3=relative*(1-exp(-drag*dt))
				change-=batch.gravity*float(batch.settings.gravity_scale)*(float(fluid.values.fluid_density)/float(batch.settings.density))*occupancy*strength*dt
				state.velocities[i]+=change; state.powder_sleep[i]=0
				if fluid.moving:
					for k in neighbors.size():
						var j:=neighbors[k]
						fluid.state.velocities[j]-=change*mass/maxf(.000001,float(fluid.state.fluid_masses[j]))*(weights[k]/total)*grain_speed/maxf(.001,float(fluid.speed))
static func contacts(controller: KiwiTimelinePhysics,batches: Array[Dictionary],time: float) -> void:
	for batch: Dictionary in batches:
		if not batch.moving or float(batch.settings.fluid_strength)<=0: continue
		var state: Dictionary=batch.state; var h:=maxf(.000001,float(batch.h)); var grain_speed: float=controller.prototypes[batch.id].clip.playback_speed
		for fluid in fluids(controller,batch,time):
			var old_grains: PackedVector3Array=state.points.duplicate(); var old_fluid: PackedVector3Array=fluid.state.points.duplicate(); var touched:={}
			var fluid_radius:=float(fluid.values.spacing)*.32
			for i in state.points.size():
				for j in near(fluid,state.points[i]):
					var delta: Vector3=state.points[i]-fluid.state.points[j]; var distance:=delta.length(); var rest:=float(state.powder_radii[i])+fluid_radius
					if distance>=rest: continue
					var normal:=delta/maxf(.000001,distance)
					if distance<.000001: normal=Vector3.UP
					var attached: bool=state.has("powder_phase") and int(state.powder_phase[i])==KiwiPowderTransport.Phase.DEPOSITED
					var a:=0.0 if attached else 1.0/maxf(1e-9,float(state.powder_masses[i])); var b:=1.0/maxf(1e-9,float(fluid.state.fluid_masses[j])) if fluid.moving else 0.0
					if a+b<=0: continue
					var correction:=normal*minf((rest-distance)*clampf(float(batch.settings.fluid_strength),0,1),float(state.powder_radii[i])*.2)/(a+b)
					var grain_delta:=correction*a; var fluid_delta: Vector3=-correction*b
					state.points[i]+=grain_delta; state.velocities[i]+=grain_delta/h
					if fluid.moving:
						fluid.state.points[j]+=fluid_delta; fluid.state.velocities[j]+=fluid_delta/h*grain_speed/maxf(.001,float(fluid.speed)); touched[j]=true
			# Reproject the coupling corrections against real geometry as well.
			# This prevents liquid/grain exclusion from moving grains through walls.
			if controller.world.space.is_valid():
				for i in state.points.size():
					if state.points[i]==old_grains[i]: continue
					var safe:=controller.world.point_motion(batch.id,old_grains[i],state.points[i],state.powder_radii[i],int(batch.config.layer),int(batch.config.mask),[])
					state.velocities[i]+=(safe.position-state.points[i])/h; state.points[i]=safe.position
				for j: int in touched:
					var actor: ActorData=controller.prototypes[fluid.id].actor; var config:=KiwiPhysicsSettings.sample(actor,controller._local(actor,time))
					var safe:=controller.world.point_motion(fluid.id,old_fluid[j],fluid.state.points[j],fluid_radius,int(config.layer),int(config.mask),[])
					fluid.state.velocities[j]+=(safe.position-fluid.state.points[j])/h*grain_speed/maxf(.001,float(fluid.speed)); fluid.state.points[j]=safe.position
			for i in state.velocities.size(): state.velocities[i]=(state.velocities[i] as Vector3).limit_length(float(batch.settings.max_speed))
			for j: int in touched: fluid.state.velocities[j]=(fluid.state.velocities[j] as Vector3).limit_length(float(fluid.values.fluid_max_speed))
