class_name KiwiPowderBridge
extends RefCounted
## Timeline adapter. Future granular solver consumes the packed state after emission.
var volumes: Dictionary={}
var generation_count:=0
var solver:=KiwiPowderSolver.new()
var reactions: Dictionary={}
func reset() -> void: volumes.clear(); reactions.clear()
static func values(controller: KiwiTimelinePhysics,id: String,time: float) -> Dictionary:
	var actor: ActorData=controller.prototypes[id].actor
	return ActorAnimation.sampled_values(actor,controller._local(actor,time))
static func source(controller: KiwiTimelinePhysics,id: String,config: Dictionary,time: float) -> Transform3D:
	return controller.source_transform(id,config,time)
func initialize(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,time: float) -> void:
	KiwiPowderSource.initialize(state)
	var settings:=values(controller,id,time); var pose:=source(controller,id,config,time)
	state.powder_time=controller._local(controller.prototypes[id].actor,time)
	state.powder_error=KiwiPowderSource.validate(settings)
	if not str(state.powder_error).is_empty(): controller._warn(str(state.powder_error)); return
	state.pose=pose
	if int(settings.powder_source_mode)==1: return
	var geometry:={}
	if int(settings.powder_shape)==3:
		var target:=str(settings.powder_mesh_actor); var runtime:=controller._runtime(target)
		if runtime==null or runtime.actor.type_id in [&"powder",&"fluid"]:
			state.powder_error="Missing or unsupported source mesh actor. Choose a closed 3D mesh actor."; controller._warn(state.powder_error); return
		pose=controller.animated_world(target,time,true)
		geometry=controller._simulation_geometry(target,{"initial_time":time,"initial_pose":pose},KiwiPhysicsGeometry.capture(runtime,{id:true}))
	var geometry_key:=[]
	for item: Dictionary in geometry.get("meshes",[]): geometry_key.append([item.local,item.surfaces])
	var key:=hash([settings.powder_shape,settings.powder_dimensions,settings.powder_spacing,settings.powder_radius,settings.get(&"powder_size_variation",0),settings.powder_jitter,settings.powder_seed,settings.powder_budget,pose,geometry_key])
	if not volumes.has(key):
		var generated:=KiwiPowderSource.volume(settings,pose,geometry); generation_count+=1
		if volumes.size()>=8: volumes.erase(volumes.keys()[0])
		volumes[key]=generated
	var volume: Dictionary=volumes[key]; state.powder_error=volume.error
	if not str(volume.error).is_empty(): controller._warn(controller.prototypes[id].actor.display_name+": "+str(volume.error)); return
	var birth:=controller._local(controller.prototypes[id].actor,time)
	for point: Vector3 in volume.points: KiwiPowderSource.append(state,point,config.velocity+pose.basis*settings.powder_emit_velocity,settings,pose,birth,0)
func step(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,time: float,dt: float) -> void:
	if not str(state.get("powder_error","")).is_empty(): return
	var actor: ActorData=controller.prototypes[id].actor; var speed: float=controller.prototypes[id].clip.playback_speed
	var scene_dt:=dt/maxf(.001,speed); var settings:=values(controller,id,time-scene_dt*.5)
	state.pose=source(controller,id,config,time)
	state.powder_time=controller._local(actor,time)
	var invalid:=KiwiPowderSource.validate(settings)
	if not invalid.is_empty(): state.powder_error=invalid; controller._warn(invalid); return
	if not (state.pose as Transform3D).basis.is_finite() or absf((state.pose as Transform3D).basis.determinant())<1e-10: state.powder_error="Emitter transform needs a finite nonzero scale."; controller._warn(state.powder_error); return
	if int(settings.powder_source_mode)==0: return
	var local:=controller._local(actor,time); var begin:=maxf(maxf(local-dt,controller._local(actor,float(state.initial_time))),float(settings.powder_emit_start)); var end:=minf(local,float(settings.powder_emit_end) if float(settings.powder_emit_end)>=0 else local)
	if end<=begin: return
	var rate:=maxf(0,float(settings.powder_emit_rate)); var amount:=rate*(end-begin); var previous:=float(state.powder_fraction)
	var count:=int(floor(previous+amount+1e-8)); state.powder_fraction=previous+amount-count
	var capacity:=maxi(0,clampi(int(settings.powder_budget),1,65536)-state.points.size())
	if not settings.powder_continuous: capacity=mini(capacity,maxi(0,int(settings.powder_supply)-int(state.powder_emitted)))
	if count>capacity and state.points.size()>=int(settings.powder_budget):
		state.powder_warning="Maximum grain count reached; emission is capped. Raise the budget to generate more."; controller._warn(actor.display_name+": "+state.powder_warning)
	for i in mini(count,capacity):
		var birth:=clampf(begin+(i+1-previous)/maxf(rate,.000001),begin,end)
		var scene_birth:=time-(local-birth)/maxf(.001,speed)
		var at_birth:=values(controller,id,scene_birth); var birth_config:=KiwiPhysicsSettings.sample(actor,birth)
		var pose:=source(controller,id,birth_config,scene_birth); var velocity: Vector3=birth_config.velocity
		if birth_config.inherit_velocity:
			var before:=source(controller,id,birth_config,scene_birth-1.0/controller.rate)
			velocity+=(pose.origin-before.origin)*controller.rate/maxf(.001,speed)
		KiwiPowderSource.spawn(state,at_birth,pose,velocity,birth)
	# Intentionally no integration here: grains remain at their world-space birth positions.

func simulate(controller: KiwiTimelinePhysics,steps: Dictionary,time: float,dt: float,old_poses: Dictionary) -> void:
	var batches: Array[Dictionary]=[]; reactions.clear()
	var configs:={}; var authored_values:={}; var exclusions:={}; var motions:={}
	for id: String in controller.prototypes:
		var actor: ActorData=controller.prototypes[id].actor; var state: Dictionary=controller.states[id]
		configs[id]=KiwiPhysicsSettings.sample(actor,controller._local(actor,time))
		if actor.type_id==&"powder": authored_values[id]=values(controller,id,time)
		var before: Transform3D=old_poses.get(id,state.pose)
		var q:=((state.pose as Transform3D).basis.orthonormalized().get_rotation_quaternion()*before.basis.orthonormalized().get_rotation_quaternion().inverse()).normalized()
		motions[id]={"linear":((state.pose as Transform3D).origin-before.origin)/maxf(.000001,dt),"angular":q.get_axis()*wrapf(q.get_angle(),-PI,PI)/maxf(.000001,dt)}
	for id: String in controller.prototypes:
		var state: Dictionary=controller.states[id]
		if int(state.type)!=7 or not state.active or not state.initialized or not state.has("powder_ids"): continue
		var authored: Dictionary=authored_values[id]; var settings:=KiwiPowderSettings.effective(authored)
		if not authored.get(&"powder_simulate",true): continue
		var actor: ActorData=controller.prototypes[id].actor; var config: Dictionary=configs[id]
		var excluded: Array[String]=[]
		for other: String in controller.prototypes:
			if (int(config.layer)&int(configs[other].mask))==0: excluded.append(other)
		exclusions[id]=excluded
		var h:=float(steps.get(id,0)); var events:=controller._events(config,controller._local(actor,time),h)
		batches.append({"id":id,"state":state,"settings":settings,"config":config,"h":h,"moving":steps.has(id) and h>0,"gravity":controller._gravity(config),"wind":config.wind,"force":events.force,"impulse":events.impulse})
		if state.points.size()>4096: controller._warn(actor.display_name+": more than 4,096 grains is expensive on the CPU contact solver; use baking or increase source spacing.")
	if batches.is_empty(): return
	controller.fluid.update_proxies(controller,time)
	KiwiPowderTransport.before(controller,batches,time,motions)
	KiwiPowderFluid.forces(controller,batches,time)
	var prepare:=func(fraction: float):
		for id: String in controller.prototypes:
			var state: Dictionary=controller.states[id]
			if int(state.type) not in [0,2] or not state.active: continue
			var config: Dictionary=configs[id]
			var before: Transform3D=old_poses.get(id,state.pose)
			controller.world.place(id,before.interpolate_with(state.pose,fraction),bool(config.collision) and not state.get("destruction_detached",false))
	var collide:=func(id: String,from: Vector3,to: Vector3,radius: float,_h: float) -> Dictionary:
		var config: Dictionary=configs[id]; var speed: float=controller.prototypes[id].clip.playback_speed
		var excluded: Array[String]=exclusions[id]
		var result:=controller.world.point_motion(id,from,to,radius,int(config.layer),int(config.mask),excluded)
		var authored: Dictionary=authored_values[id]
		if not controller.fluid.proxy_owners.is_empty() and (authored.get(&"powder_characters",true) or authored.get(&"powder_deformables",true)):
			var proxy_excluded: Array[String]=[]
			for key: String in controller.fluid.proxy_owners:
				var owner:=str(controller.fluid.proxy_owners[key]); var owner_config: Dictionary=configs.get(owner,KiwiPhysicsSettings.DEFAULTS)
				if excluded.has(owner) or not owner_config.collision or (key.contains(":p") and not authored.get(&"powder_deformables",true)) or (not key.contains(":p") and not authored.get(&"powder_characters",true)): proxy_excluded.append(key)
			var proxy:=controller.fluid.proxies.point_motion(id,from,result.position,radius,int(config.layer),int(config.mask),proxy_excluded)
			result.position=proxy.position; result.hits.append_array(proxy.hits)
		for hit: Dictionary in result.hits:
			var proxy_key:=str(hit.actor); hit.proxy=proxy_key
			hit.actor=controller.fluid.proxy_owners.get(proxy_key,proxy_key)
			var other: Dictionary=controller.states.get(str(hit.actor),{}); hit.source_speed=speed
			if controller.debris.bodies.has(str(hit.actor)):
				var body: Dictionary=controller.debris.bodies[str(hit.actor)].state; var surface:=controller.debris.settings(controller,str(hit.actor),time)
				hit.velocity=(body.v+(body.w as Vector3).cross(hit.point-(body.pose as Transform3D).origin))/maxf(.001,speed); hit.friction=float(surface.friction); hit.restitution=float(surface.bounce)
			hit.velocity=other.get("v",Vector3.ZERO)
			if not other.is_empty():
				var other_config: Dictionary=configs[hit.actor]
				var other_speed: float=controller.prototypes[hit.actor].clip.playback_speed
				var linear: Vector3=motions[hit.actor].linear; var angular: Vector3=motions[hit.actor].angular
				hit.velocity=(linear+angular.cross(hit.point-(other.pose as Transform3D).origin))/maxf(.001,speed)
				if proxy_key.contains(":p"):
					var index:=int(proxy_key.get_slice(":p",1))
					if index<other.velocities.size(): hit.velocity=other.velocities[index]*other_speed/maxf(.001,speed)
				hit.friction=float(other_config.friction); hit.restitution=float(other_config.bounce)
		return result
	var reaction:=func(hit: Dictionary,impulse: Vector3,displacement: Vector3):
		if controller.debris.bodies.has(str(hit.actor)):
			var fragment: Dictionary=controller.debris.bodies[str(hit.actor)].state; var mass:=maxf(.001,float(fragment.mass)); var radius:=maxf(.01,fragment.mesh.bounds().size.length()*.5); var world_impulse: Vector3=impulse*float(hit.get("source_speed",1))
			if not fragment.get("responds",false): return
			fragment.v+=world_impulse/mass; fragment.w=(fragment.w+(hit.point-(fragment.pose as Transform3D).origin).cross(world_impulse)/(.4*mass*radius*radius)).limit_length(30); fragment.sleep=0.0; return
		var key:=str(hit.get("proxy",hit.actor))
		if not reactions.has(key): reactions[key]={"actor":str(hit.actor),"linear":Vector3.ZERO,"torque":Vector3.ZERO,"displacement":Vector3.ZERO,"point":hit.point,"grains":{},"mass":0.0,"grain_velocity":Vector3.ZERO}
		var body: Dictionary=controller.states.get(str(hit.actor),{})
		if body.is_empty(): return
		impulse*=float(hit.get("source_speed",1))
		reactions[key].linear+=impulse; reactions[key].torque+=(hit.point-(body.pose as Transform3D).origin).cross(impulse); reactions[key].displacement+=displacement
		if hit.has("grain_key") and not reactions[key].grains.has(hit.grain_key):
			reactions[key].grains[hit.grain_key]=true; reactions[key].mass+=float(hit.grain_mass); reactions[key].grain_velocity+=hit.grain_velocity*float(hit.grain_mass)
	solver.solve(batches,collide,reaction,prepare)
	if not solver.error.is_empty(): controller._warn(solver.error)
	for key: String in reactions:
		var response: Dictionary=reactions[key]; var id:=str(response.actor); var state: Dictionary=controller.states[id]
		var config:=KiwiPhysicsSettings.sample(controller.prototypes[id].actor,controller._local(controller.prototypes[id].actor,time))
		var speed: float=controller.prototypes[id].clip.playback_speed
		if state.get("responds",false):
			# The query collider is kinematic during projection. Solve its collected
			# contacts using aggregate reduced mass, not N independent infinite-mass
			# impulses (which launches a light body out of a dense pile).
			var mass:=maxf(.001,float(config.mass)); var effective:=mass+float(response.mass)
			var impulse: Vector3=response.linear; var normal:=impulse.normalized()
			var grain_velocity: Vector3=response.grain_velocity/maxf(.001,float(response.mass))
			var closing:=maxf(0,(grain_velocity-state.v*speed).dot(normal))
			var maximum:=closing*(1+clampf(float(config.bounce),0,.5))
			var change: Vector3=impulse/effective
			change=change.limit_length(maximum)
			state.v=(state.v+change/maxf(.001,speed)).limit_length(40)
			state.w=(state.w+response.torque*.1/effective/maxf(.001,speed)).limit_length(5); state.pose.origin+=(response.displacement/effective as Vector3).limit_length(.05); state.sleep=0
		elif key.contains(":p") and int(config.mode) in [1,2] and int(state.type) in [1,4,5]:
			var index:=int(key.get_slice(":p",1)); var mass:=maxf(.001,float(config.mass)/maxi(1,state.points.size()))
			if index<state.velocities.size(): state.velocities[index]=(state.velocities[index]+response.linear/mass/maxf(.001,speed)).limit_length(30); state.points[index]+=(response.displacement/mass as Vector3).limit_length(.05)
	for id: String in controller.prototypes:
		var state: Dictionary=controller.states[id]
		if int(state.type) in [0,2]: controller.world.place(id,state.pose,state.active and not state.get("destruction_detached",false) and bool(KiwiPhysicsSettings.sample(controller.prototypes[id].actor,controller._local(controller.prototypes[id].actor,time)).collision))
	KiwiPowderFluid.contacts(controller,batches,time)
	KiwiPowderTransport.after(controller,batches,time)
