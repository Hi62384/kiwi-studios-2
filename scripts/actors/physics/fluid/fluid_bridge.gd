class_name KiwiFluidBridge
extends RefCounted
## Boundary adapter; fluid remains independent of actor/editor nodes.
var proxies:=KiwiPhysicsCollisionWorld.new()
var proxy_owners:={}
var compute: KiwiFluidCompute
var environment_documents: Dictionary={}
var environment_water: Array[Dictionary]=[]
func reset() -> void:
	proxies.reset(); proxy_owners.clear(); environment_documents.clear(); environment_water.clear()
	if compute!=null: compute.dispose(); compute=null
func ensure_compute() -> void:
	if compute==null: compute=KiwiFluidCompute.new()
func prepare_environment(controller: KiwiTimelinePhysics,time: float) -> void:
	environment_water.clear()
	for actor: ActorData in controller._model.actors:
		if actor.type_id!=&"environment_asset": continue
		var clip: ActorClip=controller._model.clip_for_actor_id(actor.id)
		if clip==null or not clip.contains_time(time): continue
		var values:=ActorAnimation.sampled_values(actor,controller._local(actor,time)); var path:=str(values.get(&"environment_path",""))
		if path.is_empty(): continue
		var runtime:=controller._runtime(actor.id)
		if runtime!=null and runtime.has_method("environment_for_physics") and str(runtime.get("source_path"))==path:
			var prepared:=runtime.call("environment_for_physics") as KiwiEnvironmentDocument
			if prepared!=null: environment_water.append({"document":prepared,"pose":controller.animated_world(actor.id,time,true)})
			continue
		if not environment_documents.has(path):
			var document:=ResourceLoader.load(path) as KiwiEnvironmentDocument if ResourceLoader.exists(path) else null
			environment_documents[path]=document if document!=null and document.validate().is_empty() else null
		var document:=environment_documents[path] as KiwiEnvironmentDocument
		if document!=null: environment_water.append({"document":document,"pose":controller.animated_world(actor.id,time,true)})
func environment_at(point: Vector3) -> Dictionary:
	var result:={}
	for entry in environment_water:
		var query: Dictionary=(entry.document as KiwiEnvironmentDocument).water_at(point,entry.pose)
		if query.is_empty() or not query.get("physics",true): continue
		if result.is_empty() or (query.surface as Vector3).y>(result.surface as Vector3).y: result=query
	return result
func rigid_water_acceleration(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,h: float) -> Vector3:
	state["water_fraction"]=0.
	if environment_water.is_empty() or not config.get("water_interaction",true) or h<=0.: return Vector3.ZERO
	var local_bounds: AABB=controller.prototypes[id].geometry.bounds; var pose: Transform3D=state.pose; var bounds:=pose*local_bounds; var volume:=absf(pose.basis.determinant())*local_bounds.get_volume()
	if volume<=.0000001: return Vector3.ZERO
	var mass:=maxf(.001,float(config.mass)); var gravity:=controller._gravity(config); var k:=0.; var buoyancy:=0.; var normal:=Vector3.ZERO; var flow:=Vector3.ZERO; var drag:=0.; var cover:=0.
	for z in 3:
		for x in 3:
			var center:=Vector3(bounds.position.x+bounds.size.x*float(x)*.5,bounds.get_center().y,bounds.position.z+bounds.size.z*float(z)*.5); var water:=environment_at(center)
			if water.is_empty(): continue
			var up: Vector3=water.normal; var height:=maxf(.001,up.abs().dot(bounds.size)); var depth:=clampf(up.dot((water.surface as Vector3)-center)+height*.5,0.,height)
			if depth<=0.: continue
			var fraction:=depth/height; var stiffness:=maxf(0.,float(water.density))*gravity.length()*maxf(0.,float(config.get("water_buoyancy",1.)))*volume/(height*9.*mass)
			k+=stiffness; buoyancy+=stiffness*depth; normal+=up*fraction; flow+=(water.flow as Vector3)*fraction; cover+=fraction; drag+=maxf(0.,float(water.drag))*maxf(0.,float(config.get("water_drag",1.)))*fraction/9.
	if cover<=0.: return Vector3.ZERO
	state.water_fraction=cover/9.; normal=normal.normalized(); flow/=cover; drag*=2.+2.*sqrt(k); var velocity: Vector3=state.v; var along:=velocity.dot(normal); var flow_along:=flow.dot(normal); var g:=gravity.dot(normal)
	# Implicit buoyancy spring and drag stay stable even for very light objects.
	var next: float=(along+h*(g+buoyancy+drag*flow_along))/(1.+h*drag+h*h*k); var correction: float=(next-along)/h-g
	var tangent: Vector3=velocity-normal*along; var flow_tangent:=flow-normal*flow_along; var damping: Vector3=(flow_tangent-tangent)*drag/(1.+h*drag)
	if correction*correction+damping.length_squared()>.000001: state.sleep=0.
	return normal*correction+damping
static func values(controller: KiwiTimelinePhysics,id: String,time: float) -> Dictionary:
	var actor: ActorData=controller.prototypes[id].actor
	return KiwiFluidSettings.effective(ActorAnimation.sampled_values(actor,controller._local(actor,time)))
static func source(controller: KiwiTimelinePhysics,id: String,config: Dictionary,time: float) -> Transform3D:
	return controller.source_transform(id,config,time)
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
		if int(controller.states[id].type)==9:
			var fog: Dictionary=ActorAnimation.sampled_values(controller.prototypes[id].actor,controller._local(controller.prototypes[id].actor,time)); characters=characters or bool(fog.get(&"fog_character_proxies",true)); deformables=deformables or bool(fog.get(&"fog_character_proxies",true)); continue
		if int(controller.states[id].type)==7:
			var config:=KiwiPowderBridge.values(controller,id,time); characters=characters or bool(config.get(&"powder_characters",true)); deformables=deformables or bool(config.get(&"powder_deformables",true)); continue
		if int(controller.states[id].type)!=6: continue
		var config:=values(controller,id,time); characters=characters or bool(config.fluid_characters); deformables=deformables or bool(config.fluid_deformables)
	if characters:
		for actor: ActorData in controller._model.actors:
			var clip: ActorClip=controller._model.clip_for_actor_id(actor.id)
			if clip==null or not clip.contains_time(time): continue
			var settings:=KiwiPhysicsSettings.sample(actor,clip.local_time(time))
			var bones: Array=actor.values.get(&"rig_bones",[])
			for i in mini(128,bones.size()):
				var pose:=controller.bone_world(actor.id,str(bones[i].name),time)
				_proxy(actor.id+":"+str(i),actor.id,pose,.08,int(settings.layer),int(settings.mask))
	if deformables:
		for id: String in controller.states:
			var state: Dictionary=controller.states[id]
			if not state.active or int(state.type) not in [1,4,5]: continue
			var settings:=KiwiPhysicsSettings.sample(controller.prototypes[id].actor,controller._local(controller.prototypes[id].actor,time))
			for i in state.points.size(): _proxy(id+":p"+str(i),id,Transform3D(Basis.IDENTITY,state.points[i]),.06,int(settings.layer),int(settings.mask))
func _proxy(key: String,owner: String,pose: Transform3D,radius: float,layer: int=1,mask: int=1) -> void:
	if not proxy_owners.has(key):
		var shape:=SphereShape3D.new(); shape.radius=radius; proxies.add(key,shape,Transform3D.IDENTITY,layer,mask); proxy_owners[key]=owner
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
			var other: Dictionary=controller.debris.lookup(controller,str(hit.actor))
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
