extends RefCounted
## Timeline adapter. Authoring resources are never mutated by the solver.
const Solver=preload("res://scripts/actors/fog/fog_transport_solver.gd")
const Definition=preload("res://scripts/actors/fog/fog_motion_definition.gd")
const Field=preload("res://scripts/actors/fog/fog_field.gd")
const ActorFog=preload("res://scripts/actors/fog/fog_actor.gd")
const Render=preload("res://scripts/actors/fog/fog_motion_render.gd")

static func values(controller: RefCounted,id: String,time: float) -> Dictionary:
	var actor: ActorData=controller.prototypes[id].actor
	return ActorAnimation.sampled_values(actor,controller._local(actor,time))

static func initialize(controller: RefCounted,id: String,state: Dictionary,_config: Dictionary,time: float) -> void:
	var v:=values(controller,id,time); var world: Transform3D=controller.animated_world(id,time,true)
	var dimensions: Vector3=(v.get(&"volume_size",Vector3(4,2,4)) as Vector3).abs()*world.basis.get_scale().abs(); dimensions=dimensions.max(Vector3.ONE*.01)
	var pose:=Transform3D(world.basis.orthonormalized(),world.origin); var n:=Definition.resolution(v); var rho:=PackedFloat32Array(); rho.resize(n*n*n)
	if int(v.get(&"fog_initial",0))==0:
		var object:=ActorFog.resolve(v.get(&"field")); var source:=Field.prepare_cpu(object.values) if object!=null else {}; var kind:=int(v.get(&"shape",3)); var boundary: Array[Image]=[]
		if object!=null and object.values.get(&"cloud_follow_ground",false):
			var ground:=preload("res://scripts/actors/fog/fog_ground_sampler.gd").prepare(controller,pose,dimensions,object.values)
			if ground.get("image") is Image: source.ground=ground.image
			if not str(ground.get("error","")).is_empty(): controller._warn(str(ground.error))
		if kind==7: boundary.assign(preload("res://scripts/actors/fog/fog_mesh.gd").prepare(str(v.get(&"boundary_mesh",""))).get("slices",[]))
		var points: PackedVector3Array=Solver.grid(n).positions
		for i in points.size():
			var unit:=points[i]+Vector3.ONE*.5; var inside:=true
			if kind!=3 and kind!=4 and kind!=7:
				var shape: int={0:2,1:4,2:3,5:1,6:5}.get(kind,0); inside=Field.shape_distance(points[i]*dimensions,dimensions,shape)<=0.
			elif kind==7: inside=Field.sample_volume(boundary,unit,false)>.5
			if not inside: continue
			var density:=1.
			if not source.is_empty() and source["values"].get(&"enabled",true) and int(source["values"].get(&"target",0))==0:
				var f: Dictionary=source["values"]; var mask:=mask_value(source.mask,unit,pose*(points[i]*dimensions)); density=Field.combine(1.,Field.sample_prepared(source,unit,pose*(points[i]*dimensions)),int(f.get(&"combine",1)),float(f.get(&"strength",1.))*mask)
			rho[i]=density
	state.merge(Solver.initialize(n,dimensions,rho),true); state.fog_pose=pose; state.fog_time=controller._local(controller.prototypes[id].actor,time); state.fog_source_previous={}; state.fog_obstacle_previous={}
	obstacles(controller,id,state,v,0.); emit_sources(controller,id,state,v,time,0.)

static func mask_value(source: Dictionary,unit: Vector3,world: Vector3) -> float:
	if source.is_empty(): return 1.
	return clampf(Field.sample_prepared(source,unit,world)*mask_value(source.mask,unit,world),0.,1.)

static func source_pose(controller: RefCounted,id: String,v: Dictionary,time: float) -> Transform3D:
	var owner: ActorData=controller.prototypes[id].actor; var target:=str(v.get(&"source_actor","")); var links: Dictionary=owner.values.get(&"fog_motion_links",{}); target=str(links.get(target,target))
	var pose: Transform3D=controller.bone_world(target,str(v.get(&"source_bone","")),time) if not target.is_empty() else controller.animated_world(id,time,true)
	pose.origin=pose*(v.get(&"position",Vector3.ZERO) as Vector3)
	return pose

static func emit_sources(controller: RefCounted,id: String,state: Dictionary,v: Dictionary,time: float,dt: float) -> void:
	var n:=int(state.fog_n); var points: PackedVector3Array=Solver.grid(n).positions; var domain: Transform3D=state.fog_pose; var inverse:=domain.affine_inverse(); var local: float=controller._local(controller.prototypes[id].actor,time)
	for slot in 4:
		var object:=ActorFog.resolve(v.get(StringName("fog_source_%d"%slot)))
		if object==null: continue
		var source: Dictionary=object.values
		if not source.get(&"enabled",true): continue
		var pose:=source_pose(controller,id,source,time); var previous: Transform3D=state.fog_source_previous.get(slot,pose); state.fog_source_previous[slot]=pose
		var start:=float(source.get(&"start",0.)); var end:=float(source.get(&"end",-1.)); var mass:=0.
		if int(source.get(&"mode",0))==1:
			if local>=start and not state.fog_bursts.has(slot):
				state.fog_bursts[slot]=true
				if (dt>0. and local-dt<start+.000001) or is_equal_approx(local,start): mass=float(source.get(&"burst",1.))
		else:
			var overlap:=maxf(0.,minf(local,end if end>=0. else local)-maxf(local-dt,start)); mass=float(source.get(&"rate",.2))*overlap
		if mass<=0.: continue
		var cells:=PackedInt32Array(); var weights:=PackedFloat32Array(); var kind:=int(source.get(&"shape",1)); var source_size: Vector3=(source.get(&"size",Vector3.ONE*.5) as Vector3).abs().max(Vector3.ONE*.001); var source_inverse:=pose.affine_inverse(); var padding: float=(state.fog_size as Vector3).length()/n*.5; var mesh: Array[Image]=[]
		if kind in [3,4]:
			var direction: Vector3=source.get(&"direction",Vector3.UP)
			if not direction.is_zero_approx(): source_inverse=(pose*Transform3D(Basis(Quaternion(Vector3.UP,direction.normalized())),Vector3.ZERO)).affine_inverse()
		if kind==5:
			var volume:=preload("res://scripts/actors/fog/fog_mesh.gd").prepare(str(source.get(&"mesh",""))); mesh.assign(volume.get("slices",[]))
			if not str(volume.get("error","")).is_empty(): controller._warn("Fog source: "+str(volume.error))
		if kind==0:
			var unit: Vector3=(inverse*pose.origin)/state.fog_size+Vector3.ONE*.5
			if AABB(Vector3.ZERO,Vector3.ONE).has_point(unit):
				var p:=Vector3i(unit*n).clamp(Vector3i.ZERO,Vector3i.ONE*(n-1)); cells.append(p.x+n*(p.y+n*p.z)); weights.append(1.)
		else:
			for i in points.size():
				var point: Vector3=source_inverse*(domain*(points[i]*state.fog_size)); var distance:=0.
				if kind==5:
					var unit:=point/source_size+Vector3.ONE*.5
					if not AABB(Vector3.ZERO,Vector3.ONE).has_point(unit) or Field.sample_volume(mesh,unit,false)<.5: continue
				else:
					var dimensions:=source_size
					if kind==3: dimensions.y=minf(dimensions.y,padding*.5)
					distance=Field.shape_distance(point,dimensions,{1:2,2:0,3:3,4:4}.get(kind,0))
					if distance>padding: continue
				cells.append(i); weights.append(clampf(.5-distance/maxf(.001,padding),.01,1.))
		var velocity: Vector3=pose.basis.orthonormalized()*(source.get(&"velocity",Vector3.UP) as Vector3)
		if source.get(&"inherit_velocity",true) and dt>0.: velocity+=(pose.origin-previous.origin)/dt
		var spread:=deg_to_rad(float(source.get(&"spread",0.)))
		if spread<=0. or cells.is_empty(): Solver.inject(state,cells,weights,mass,domain.basis.inverse()*velocity)
		else:
			var sum:=0.
			for index in cells.size():
				if state.fog_solid[cells[index]]==0: sum+=weights[index]
			var rng:=RandomNumberGenerator.new(); rng.seed=hash([int(source.get(&"seed",1)),slot,state.fog_step])
			for index in cells.size():
				if state.fog_solid[cells[index]]!=0 or sum<=0.: continue
				var direction:=velocity.normalized(); var axis:=direction.cross(Vector3.UP if absf(direction.y)<.9 else Vector3.RIGHT).normalized(); var tilted:=direction.rotated(axis,acos(lerpf(cos(spread),1.,rng.randf()))).rotated(direction,rng.randf()*TAU)
				Solver.inject(state,PackedInt32Array([cells[index]]),PackedFloat32Array([1.]),mass*weights[index]/sum,domain.basis.inverse()*tilted*velocity.length())

static func contains(shape: Shape3D,p: Vector3,padding: Vector3) -> bool:
	if shape is BoxShape3D: return p.abs().x<=shape.size.x*.5+padding.x and p.abs().y<=shape.size.y*.5+padding.y and p.abs().z<=shape.size.z*.5+padding.z
	if shape is SphereShape3D: return p.length()<=shape.radius+padding.length()*.5
	if shape is CapsuleShape3D:
		p.y-=clampf(p.y,-maxf(0.,shape.height*.5-shape.radius),maxf(0.,shape.height*.5-shape.radius)); return p.length()<=shape.radius+padding.length()*.5
	if shape is CylinderShape3D: return Vector2(p.x,p.z).length()<=shape.radius+maxf(padding.x,padding.z) and absf(p.y)<=shape.height*.5+padding.y
	if shape is ConvexPolygonShape3D:
		# Conservative hull bounds for offline occupancy, never claim exact mesh flow.
		if shape.points.is_empty(): return false
		var box:=AABB(shape.points[0],Vector3.ZERO)
		for point in shape.points: box=box.expand(point)
		return box.grow(padding.length()*.5).has_point(p)
	return false

static func bounds(shape: Shape3D) -> AABB:
	var size:=Vector3.ZERO
	if shape is BoxShape3D: size=shape.size
	elif shape is SphereShape3D: size=Vector3.ONE*shape.radius*2.
	elif shape is CapsuleShape3D or shape is CylinderShape3D: size=Vector3(shape.radius*2.,shape.height,shape.radius*2.)
	elif shape is ConvexPolygonShape3D and not shape.points.is_empty():
		var box:=AABB(shape.points[0],Vector3.ZERO)
		for point in shape.points: box=box.expand(point)
		return box
	return AABB(-size*.5,size)

static func obstacles(controller: RefCounted,id: String,state: Dictionary,v: Dictionary,dt: float) -> void:
	var points: PackedVector3Array=Solver.grid(int(state.fog_n)).positions; var solid:=PackedByteArray(); solid.resize(points.size()); var boundary:=PackedVector3Array(); boundary.resize(points.size()); var previous: Dictionary=state.fog_obstacle_previous; var next: Dictionary={}; var domain: Transform3D=state.fog_pose
	if v.get(&"fog_obstacles",true):
		var collider_sets: Array=[controller.world.bodies]
		if v.get(&"fog_character_proxies",true): collider_sets.append(controller.fluid.proxies.bodies)
		for entries: Dictionary in collider_sets:
			for key: String in entries:
				var entry: Dictionary=entries[key]
				if key==id or key.begins_with("@probe:") or not entry.get("enabled",false): continue
				var pose: Transform3D=entry.get("pose",Transform3D.IDENTITY); var before: Transform3D=previous.get(key,pose); next[key]=pose
				var velocity: Vector3=(pose.origin-before.origin)/dt if dt>0. else Vector3.ZERO
				for item: Dictionary in entry.get("compound",[{"shape":entry.shape,"offset":entry.offset}]):
					var transform: Transform3D=pose*item.offset
					if absf(transform.basis.determinant())<.000001: continue
					var box:=bounds(item.shape)
					if box.size.is_zero_approx():
						controller._warn("Fog obstacles support primitives and conservative convex bounds. Use compound convex colliders for mesh openings."); continue
					var inverse:=transform.affine_inverse(); var padding: Vector3=transform.basis.get_scale().abs().inverse()*(state.fog_size as Vector3)/int(state.fog_n)*.5
					var to_domain:=domain.affine_inverse()*transform; var region:=AABB(to_domain*box.position,Vector3.ZERO)
					for corner in 8: region=region.expand(to_domain*(box.position+box.size*Vector3(corner&1,(corner>>1)&1,(corner>>2)&1)))
					var n:=int(state.fog_n); var dimensions: Vector3=state.fog_size; var low:=Vector3i(((region.position/dimensions+Vector3.ONE*.5)*n-Vector3.ONE*.5).floor()).max(Vector3i.ZERO); var high:=Vector3i(((region.end/dimensions+Vector3.ONE*.5)*n+Vector3.ONE*.5).ceil()).min(Vector3i.ONE*(n-1))
					for z in range(low.z,high.z+1):
						for y in range(low.y,high.y+1):
							for x in range(low.x,high.x+1):
								var i:=x+n*(y+n*z); var world: Vector3=domain*(points[i]*dimensions)
								if contains(item.shape,inverse*world,padding): solid[i]=1; boundary[i]=domain.basis.inverse()*velocity*float(v.get(&"fog_obstacle_motion",1.))
	state.fog_obstacle_previous=next; Solver.set_obstacles(state,solid,boundary)

static func step(controller: RefCounted,id: String,state: Dictionary,config: Dictionary,time: float,dt: float) -> void:
	var started:=Time.get_ticks_usec(); var v:=values(controller,id,time); var world: Transform3D=controller.animated_world(id,time,true)
	var dimensions: Vector3=(v.get(&"volume_size",Vector3(4,2,4)) as Vector3).abs()*world.basis.get_scale().abs()
	if Definition.resolution(v)!=int(state.fog_n) or not dimensions.max(Vector3.ONE*.01).is_equal_approx(state.fog_size):
		initialize(controller,id,state,config,time); controller._warn("Fog domain dimensions or resolution changed; concentration restarted.")
	if int(v.get(&"fog_domain_behavior",0))==1: state.fog_pose=Transform3D(world.basis.orthonormalized(),world.origin)
	obstacles(controller,id,state,v,dt); emit_sources(controller,id,state,v,time,dt)
	var fields: Array=[]; var inverse: Basis=(state.fog_pose as Transform3D).basis.inverse()
	for slot in 4:
		var object:=ActorFog.resolve(v.get(StringName("fog_velocity_%d"%slot)))
		if object==null: continue
		var source: Dictionary=object.values; var pose:=source_pose(controller,id,source,time); var f:=source.duplicate(); f.center=(state.fog_pose as Transform3D).affine_inverse()*pose.origin; f.direction=inverse*pose.basis*(source.get(&"direction",Vector3.UP) as Vector3); fields.append(f)
	var frequency:=float(v.get(&"fog_gust_frequency",1.)); var gust:=1.+float(v.get(&"fog_gust_strength",0.))*sin(float(state.fog_time)*frequency)
	var events: Dictionary=controller._events(config,controller._local(controller.prototypes[id].actor,time),dt)
	if not events.impulse.is_zero_approx():
		var velocity: PackedVector3Array=state.fog_velocity; var impulse: Vector3=inverse*events.impulse
		for i in velocity.size():
			if state.fog_solid[i]==0: velocity[i]+=impulse
		state.fog_velocity=velocity
	var wind: Vector3=(v.get(&"fog_wind",Vector3.ZERO) as Vector3)*float(v.get(&"fog_wind_influence",1.))*gust+config.wind
	if not events.force.is_zero_approx(): fields.append({"center":Vector3.ZERO,"radius":100000.,"direction":inverse*events.force,"strength":1.,"falloff":0.})
	var options:={"wind":inverse*wind,"fields":fields,"buoyancy_direction":inverse*Vector3.UP,"closed":int(v.get(&"fog_boundaries",0))==1}
	for pair in [["damping","fog_velocity_damping"],["turbulence","fog_turbulence"],["turbulence_scale","fog_turbulence_scale"],["turbulence_frequency","fog_turbulence_frequency"],["seed","fog_seed"],["buoyancy","fog_buoyancy"],["pressure_iterations","fog_pressure_iterations"],["expansion","fog_expansion"],["diffusion","fog_diffusion"],["dissipation","fog_dissipation"],["max_density","fog_max_density"]]: options[pair[0]]=v.get(StringName(pair[1]),0.)
	Solver.step(state,options,dt); state.fog_cpu_ms=float(Time.get_ticks_usec()-started)/1000.
	if state.fog_clamped: controller._warn("Fog speed reached this grid's stable transport limit. Increase fixed steps or lower velocity / expansion.")

static func apply(controller: RefCounted,id: String,state: Dictionary,time: float) -> void:
	var runtime: Node=controller._runtime(id)
	if runtime==null: return
	var result:=Render.apply(runtime,state,values(controller,id,time)); runtime.set_meta("fog_motion_stats",{"cpu_ms":state.get("fog_cpu_ms",0.),"upload_ms":result.upload_ms,"cells":int(state.fog_n)*int(state.fog_n)*int(state.fog_n),"mass":Solver.total_mass(state),"lost":state.fog_lost,"error":result.error})
	if not str(result.error).is_empty(): controller._warn(str(result.error))

static func interpolate(result: Dictionary,left: Dictionary,right: Dictionary,fraction: float) -> void:
	if not left.has("fog_density") or not right.has("fog_density") or left.fog_n!=right.fog_n: return
	for key in ["fog_density","fog_velocity","fog_pressure"]:
		var array: Variant=left[key].duplicate()
		for i in array.size(): array[i]=left[key][i].lerp(right[key][i],fraction) if key=="fog_velocity" else lerpf(left[key][i],right[key][i],fraction)
		result[key]=array
	result.fog_solid=left.fog_solid.duplicate(); result.fog_pose=(left.fog_pose as Transform3D).interpolate_with(right.fog_pose,fraction); result.fog_time=lerpf(left.fog_time,right.fog_time,fraction)
