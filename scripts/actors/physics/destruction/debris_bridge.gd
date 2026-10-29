class_name KiwiDebrisBridge
extends RefCounted
var bodies: Dictionary={}
var renderers: Dictionary={}
var meshes: Dictionary={}
var elapsed_usec:=0
func reset() -> void:
	for node: Node in renderers.values():
		if is_instance_valid(node): node.free()
	bodies.clear(); renderers.clear(); meshes.clear()
func refresh(controller: KiwiTimelinePhysics,time: float) -> void:
	bodies.clear()
	for owner: String in controller.states:
		var actor: ActorData=controller.prototypes[owner].actor; var values:=ActorAnimation.sampled_values(actor,controller._local(actor,time)); var config:=KiwiPhysicsSettings.sample(actor,controller._local(actor,time))
		var material:=KiwiDestructionMaterial.resolve(values)
		if material!=null and values.get(&"debris_use_material_contacts",true): config.friction=float(material.get_value(&"debris_friction",config.friction)); config.bounce=float(material.get_value(&"debris_restitution",config.bounce))
		for fragment: Dictionary in controller.states[owner].get("destruction_fragments",[]):
			fragment.responds=controller.states[owner].active and bool(values.get(&"debris_enabled",true)) and (int(config.mode) not in [3,4] or controller.is_baking(owner))
			var rule: Dictionary=values.get(&"destruction_fragments",{}).get(KiwiDestructionAuthoring.fragment_key(owner,fragment.id),{}); var local:=controller._local(actor,time)
			if rule.get("enabled",true) and (local<float(rule.get("pin_until",-1)) or (int(rule.get("mode",0))==2 and local>=float(rule.get("from",0)) and (float(rule.get("to",-1))<0 or local<float(rule.to)))): fragment.responds=false
			bodies[fragment.id]={"state":fragment,"owner":owner,"config":config,"values":values}
func lookup(controller: KiwiTimelinePhysics,id: String) -> Dictionary:
	return bodies[id].state if bodies.has(id) else controller.states.get(id,{})
func settings(controller: KiwiTimelinePhysics,id: String,time: float) -> Dictionary:
	if bodies.has(id):
		var config: Dictionary=bodies[id].config.duplicate(); config.mass=bodies[id].state.mass; return config
	return KiwiPhysicsSettings.sample(controller.prototypes[id].actor,controller._local(controller.prototypes[id].actor,time)) if controller.prototypes.has(id) else KiwiPhysicsSettings.DEFAULTS
func emit(controller: KiwiTimelinePhysics,owner: String,source: String,kind: String,time: float,point: Vector3,normal: Vector3,velocity: Vector3,energy: float) -> void:
	if not controller.states.has(owner) or energy<.02: return
	var state: Dictionary=controller.states[owner]; var stamp:=source+":"+kind; var recent: Dictionary=state.get("debris_recent",{})
	if time-float(recent.get(stamp,-100))<.15: return
	recent[stamp]=time; state.debris_recent=recent
	while recent.size()>512: recent.erase(recent.keys()[0])
	var events: Array=state.get("destruction_events",[])
	while events.size()>=96: events.pop_front()
	var id:=stamp+":"+str(roundi(time*controller.rate)); var event:={"id":id,"source_actor":owner,"fragment":source,"type":kind,"time":time,"point":point,"normal":normal,"velocity":velocity,"energy":energy,"seed":hash(id)}
	events.append(event); state.destruction_events=events; controller.destruction_event.emit(event)
func step(controller: KiwiTimelinePhysics,time: float,dt: float) -> void:
	var start:=Time.get_ticks_usec(); refresh(controller,time); var splits:=[]
	var fluids: Array[Dictionary]=[]
	if not bodies.is_empty(): fluids=KiwiPowderFluid.fluids(controller,{"config":{"collision":true,"mask":0x7fffffff,"layer":0x7fffffff}},time)
	for id: String in bodies:
		var entry: Dictionary=bodies[id]; var fragment: Dictionary=entry.state; var config: Dictionary=entry.config; var values: Dictionary=entry.values; var parent: Dictionary=controller.states[entry.owner]
		fragment.active=parent.active
		if not parent.active or not values.get(&"debris_enabled",true) or (int(config.mode) in [3,4] and not controller.is_baking(entry.owner)): continue
		var h:=dt*float(controller.prototypes[entry.owner].clip.playback_speed)
		if h<=0: continue
		var rule: Dictionary=values.get(&"destruction_fragments",{}).get(KiwiDestructionAuthoring.fragment_key(entry.owner,id),{})
		if KiwiDestructionAuthoring.guidance(controller,entry.owner,fragment,values,time,h):
			controller.world.place(id,fragment.pose,config.collision and rule.get("collision",true)); continue
		var nearby_motion:=false
		for state: Dictionary in controller.states.values():
			if state.active and not state.get("destruction_detached",false) and state.v.length_squared()>.01 and (state.pose as Transform3D).origin.distance_squared_to(fragment.pose.origin)<9: nearby_motion=true; break
		for fluid: Dictionary in fluids:
			if not KiwiPowderFluid.near(fluid,fragment.pose.origin).is_empty(): nearby_motion=true; break
		if float(fragment.get("sleep",0))>.6 and values.get(&"debris_sleep",true) and not nearby_motion: continue
		var mass:=maxf(.001,float(fragment.mass)); var radius:=maxf(.01,(fragment.mesh.bounds() as AABB).size.length()*.5); var inertia:=.4*mass*radius*radius
		for fluid: Dictionary in fluids:
			var fluid_config:=KiwiPhysicsSettings.sample(controller.prototypes[fluid.id].actor,controller._local(controller.prototypes[fluid.id].actor,time))
			if not config.collision or not values.get(&"debris_collision",true) or (int(config.mask)&int(fluid_config.layer))==0 or (int(fluid_config.mask)&int(config.layer))==0: continue
			var neighbors:=KiwiPowderFluid.near(fluid,fragment.pose.origin); var total:=0.0; var velocity:=Vector3.ZERO; var weights:=[]
			for index in neighbors:
				var weight:=KiwiFluidSolver.kernel(fragment.pose.origin.distance_squared_to(fluid.state.points[index]),float(fluid.h))*pow(float(fluid.values.spacing),3); total+=weight; velocity+=fluid.state.velocities[index]*weight; weights.append(weight)
			if total<=.000001: continue
			velocity/=total; var occupancy:=clampf(total,0,1); var density:=float(fluid.values.fluid_density); var relative: Vector3=velocity-fragment.v
			var drag: Vector3=relative*(1-exp(-.5*density*.47*PI*radius*radius/mass*relative.length()*occupancy*h))
			var displaced:=KiwiDestructionGeometry.volume(fragment.mesh)*absf((fragment.pose as Transform3D).basis.determinant())
			var change: Vector3=drag-controller._gravity(config)*density*displaced/mass*occupancy*h
			change=change.limit_length(20); fragment.v+=change; fragment.sleep=0.0
			if fluid.moving:
				for k in neighbors.size(): fluid.state.velocities[neighbors[k]]-=change*mass/maxf(.000001,float(fluid.state.fluid_masses[neighbors[k]]))*float(weights[k])/total
		var motion: Vector3=fragment.v*h+controller._gravity(config)*h*h*.5; fragment.v=(fragment.v+controller._gravity(config)*h)*exp(-float(config.damping)*h)
		if fragment.w.length()>.00001: fragment.pose.basis=Basis(Quaternion(fragment.w.normalized(),fragment.w.length()*h))*fragment.pose.basis
		var exclude: Array[String]=[entry.owner]; exclude.append_array(controller.structure.exclusions(controller,entry.owner,time))
		var result:=controller.world.move(id,fragment.pose,motion,exclude) if config.collision and values.get(&"debris_collision",true) and rule.get("collision",true) else {"travel":motion,"hits":[]}; fragment.pose.origin+=result.travel
		var strongest:={}; var strongest_energy:=0.0
		for hit: Dictionary in result.hits:
			var normal: Vector3=hit.normal; var other:=lookup(controller,str(hit.actor)); var other_config:=settings(controller,str(hit.actor),time)
			var inverse:=1/maxf(.001,float(other_config.mass)) if other.get("responds",false) else 0.0
			var arm: Vector3=hit.point-fragment.pose.origin; var relative: Vector3=fragment.v+fragment.w.cross(arm)-(other.get("v",Vector3.ZERO) as Vector3); var speed:=relative.dot(normal)
			if speed<0:
				var energy:=.5*speed*speed/(1/mass+inverse); var impulse: float=-(1+(float(config.bounce) if speed<-.3 else 0.0))*speed/(1/mass+inverse+arm.cross(normal).length_squared()/inertia)
				fragment.v+=normal*impulse/mass; fragment.w=(fragment.w+arm.cross(normal*impulse)/inertia).limit_length(30)
				if inverse>0: other.v-=normal*impulse*inverse; other.sleep=0.0
				var tangent:=relative-normal*speed; fragment.v-=tangent.limit_length(float(config.friction)*impulse/mass)
				if energy>strongest_energy: strongest_energy=energy; strongest=hit
				if speed<-.5:
					emit(controller,entry.owner,id+":"+str(hit.actor),"impact",time,hit.point,normal,relative,energy)
					if controller.states.has(str(hit.actor)):
						var target: Dictionary=controller.states[str(hit.actor)]; target.structure_pending_impacts=target.get("structure_pending_impacts",[]); target.structure_pending_impacts.append({"point":hit.point,"normal":-normal,"energy":energy})
				if tangent.length()>1 and absf(speed)<.5: emit(controller,entry.owner,id+":"+str(hit.actor),"scrape",time,hit.point,normal,tangent,.5*mass*tangent.length_squared())
		fragment.w*=exp(-(float(config.angular_damping)+(float(config.friction)*8 if not result.hits.is_empty() else 0))*h)
		fragment.sleep=float(fragment.get("sleep",0))+h if not result.hits.is_empty() and fragment.v.length()<.12 and fragment.w.length()<.2 else 0.0
		if fragment.sleep>.6: fragment.v=Vector3.ZERO; fragment.w=Vector3.ZERO
		controller.world.place(id,fragment.pose,bool(config.collision) and values.get(&"debris_collision",true) and rule.get("collision",true))
		if values.get(&"debris_secondary",false) and strongest_energy>float(values.get(&"debris_secondary_energy",10)) and int(fragment.get("depth",0))<int(values.get(&"debris_depth",2)) and radius>float(values.get(&"debris_min_size",.08))*2:
			var children:=secondary(controller,entry,fragment,strongest,strongest_energy,time)
			if not children.is_empty(): splits.append({"owner":entry.owner,"parent":fragment,"children":children})
	for split: Dictionary in splits:
		var inventory: Array=controller.states[split.owner].destruction_fragments
		if inventory.size()+split.children.size()-1>int(ActorAnimation.sampled_values(controller.prototypes[split.owner].actor,controller._local(controller.prototypes[split.owner].actor,time)).get(&"debris_budget",96)) or bodies.size()+split.children.size()>256: continue
		inventory.erase(split.parent); inventory.append_array(split.children); controller.world.remove(split.parent.id); controller.destruction.collider_keys.erase(split.parent.id)
		controller.destruction.sync_actor_world(controller,split.owner,controller.states[split.owner],time)
	refresh(controller,time)
	elapsed_usec=Time.get_ticks_usec()-start
func secondary(controller: KiwiTimelinePhysics,entry: Dictionary,parent: Dictionary,hit: Dictionary,energy: float,time: float) -> Array:
	var material:=KiwiDestructionMaterial.resolve(entry.values); var event:={"energy":energy,"normal":(parent.pose as Transform3D).basis.inverse()*hit.normal,"local_point":(parent.pose as Transform3D).affine_inverse()*hit.point}
	var size: Vector3=parent.mesh.bounds().size
	var op:=KiwiDestructionMaterial.response(material,event,{},size[size.min_axis_index()]) if material!=null else KiwiDestructionDefinition.operation(2)
	if op.is_empty() or int(op.type) not in [0,2]: return []
	op.position=event.local_point; op.direction=event.normal; op.pieces=clampi(int(op.get("pieces",3)),2,4); op.seed=hash(str(parent.id)+str(parent.get("depth",0)))
	var output:=KiwiDestructionGeometry.evaluate(parent.mesh,{"secondary":op},controller.states[entry.owner].destruction_geometry.materials.size())
	if not output.error.is_empty() or output.parts.size()<2: return []
	var total:=0.0
	for mesh: KiwiModelMesh in output.parts: total+=KiwiDestructionGeometry.volume(mesh)
	var children:=[]
	for i in output.parts.size():
		var mesh: KiwiModelMesh=output.parts[i].copy_mesh(); var center:=mesh.bounds().get_center(); var volume:=KiwiDestructionGeometry.volume(mesh)
		for v in mesh.vertices.size(): mesh.vertices[v]-=center
		var offset: Vector3=parent.pose.basis*center
		children.append({"id":parent.id+":s"+str(i),"mesh":mesh,"pose":parent.pose*Transform3D(Basis.IDENTITY,center),"v":parent.v+parent.w.cross(offset),"w":parent.w,"mass":float(parent.mass)*volume/maxf(.000001,total),"sleep":0.0,"depth":int(parent.get("depth",0))+1,"structure_origin":parent.get("structure_origin",Vector3.ZERO)+center})
	emit(controller,entry.owner,parent.id,"secondary",time,hit.point,hit.normal,parent.v,energy)
	return children
