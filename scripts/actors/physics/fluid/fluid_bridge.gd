class_name KiwiFluidBridge
extends RefCounted
## Boundary adapter; fluid remains independent of actor/editor nodes.
var proxies:=KiwiPhysicsCollisionWorld.new()
var proxy_owners:={}
var compute: KiwiFluidCompute
func reset() -> void:
	proxies.reset(); proxy_owners.clear()
	if compute!=null: compute.dispose(); compute=null
func ensure_compute() -> void:
	if compute==null: compute=KiwiFluidCompute.new()
static func values(controller: KiwiTimelinePhysics,id: String,time: float) -> Dictionary:
	var actor: ActorData=controller.prototypes[id].actor
	return KiwiFluidSettings.effective(ActorAnimation.sampled_values(actor,controller._local(actor,time)))
static func source(controller: KiwiTimelinePhysics,id: String,config: Dictionary,time: float) -> Transform3D:
	var pose:=controller.animated_world(id,time,true)
	if not str(config.attachment).is_empty(): pose=controller.bone_world(str(config.attachment),str(config.attachment_bone),time)
	pose.origin+=pose.basis*config.pivot
	return pose
static func initialize(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,time: float) -> void:
	controller.fluid.ensure_compute()
	var settings:=values(controller,id,time); var pose:=source(controller,id,config,time); var geometry:={}
	if not controller.fluid.compute.available(): settings.budget=mini(int(settings.budget),256); controller._warn("Fluid uses the CPU fallback (maximum 256 particles). "+controller.fluid.compute.error)
	if int(settings.fluid_shape)==3:
		var runtime:=controller._runtime(str(settings.fluid_mesh_actor))
		if runtime!=null: geometry=KiwiPhysicsGeometry.capture(runtime,{})
	var volume:={"points":PackedVector3Array(),"error":""}
	if int(settings.fluid_source_mode)!=1: volume=KiwiFluidVolume.generate(settings,pose,geometry)
	state.fluid_error=volume.error
	if not str(volume.error).is_empty(): controller._warn(controller.prototypes[id].actor.display_name+": "+str(volume.error)); volume.points=PackedVector3Array()
	KiwiFluidSolver.initialize(state,settings,volume.points)
func update_proxies(controller: KiwiTimelinePhysics,time: float) -> void:
	for id: String in proxy_owners: proxies.place(id,Transform3D.IDENTITY,false)
	var characters:=false; var deformables:=false
	for id: String in controller.prototypes:
		if int(controller.states[id].type)!=6: continue
		var config:=values(controller,id,time); characters=characters or bool(config.fluid_characters); deformables=deformables or bool(config.fluid_deformables)
	if characters:
		for actor: ActorData in controller._model.actors:
			var clip: ActorClip=controller._model.clip_for_actor_id(actor.id)
			if clip==null or not clip.contains_time(time): continue
			var bones: Array=actor.values.get(&"rig_bones",[])
			for i in mini(128,bones.size()):
				var pose:=controller.bone_world(actor.id,str(bones[i].name),time)
				_proxy(actor.id+":"+str(i),actor.id,pose,.08)
	if deformables:
		for id: String in controller.states:
			var state: Dictionary=controller.states[id]
			if not state.active or int(state.type) not in [1,4,5]: continue
			for i in state.points.size(): _proxy(id+":p"+str(i),id,Transform3D(Basis.IDENTITY,state.points[i]),.06)
func _proxy(key: String,owner: String,pose: Transform3D,radius: float) -> void:
	if not proxy_owners.has(key):
		var shape:=SphereShape3D.new(); shape.radius=radius; proxies.add(key,shape,Transform3D.IDENTITY,1,1); proxy_owners[key]=owner
	proxies.place(key,pose)
func step(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,time: float,dt: float) -> void:
	var settings:=values(controller,id,time)
	if compute==null or not compute.available(): settings.budget=mini(int(settings.budget),256)
	if not str(state.get("fluid_error","")).is_empty(): return
	var pose:=source(controller,id,config,time); var previous:=source(controller,id,config,time-dt/maxf(.001,controller.prototypes[id].clip.playback_speed))
	var inherited: Vector3=(pose.origin-previous.origin)/dt if config.inherit_velocity else Vector3.ZERO
	KiwiFluidSolver.emit(state,settings,pose,inherited+config.velocity,controller._local(controller.prototypes[id].actor,time),dt)
	var events:=controller._events(config,controller._local(controller.prototypes[id].actor,time),dt)
	var collide:=func(from: Vector3,to: Vector3,radius: float,_velocity: Vector3) -> Dictionary:
		if not config.collision: return {"position":to,"hits":[]}
		var result:=controller.world.point_motion(id,from,to,radius,int(config.layer),int(config.mask),[])
		for hit: Dictionary in result.hits:
			var other: Dictionary=controller.states.get(str(hit.actor),{})
			hit.velocity=other.get("v",Vector3.ZERO)
			if not other.is_empty(): hit.velocity+=(other.get("w",Vector3.ZERO) as Vector3).cross(hit.point-(other.pose as Transform3D).origin)
		if bool(settings.fluid_characters) or bool(settings.fluid_deformables):
			var secondary:=proxies.point_motion(id,from,result.position,radius,int(config.layer),int(config.mask),[])
			for hit: Dictionary in secondary.hits: hit.actor=proxy_owners.get(str(hit.actor),"")
			result.position=secondary.position; result.hits.append_array(secondary.hits)
		return result
	KiwiFluidSolver.step(state,settings,controller._gravity(config)+events.force/maxf(1.0,float(settings.fluid_density)),events.impulse,dt,collide,compute)
	for i in state.velocities.size(): state.velocities[i]*=exp(-float(config.damping)*dt)
	state.pose=pose
