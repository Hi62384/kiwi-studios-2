class_name KiwiStructureBridge
extends RefCounted
## Timeline-only XPBD rigid joints. Reaction estimates are artistic approximations,
## not engineering-certified stress/FEM. No parenting-derived constraints.
const MAX_ELEMENTS:=512
const MAX_LINKS:=1024
var nodes: Dictionary={}
var edges: Array[Dictionary]=[]
var islands: Dictionary={}
var graph_key:=0
var graph_builds:=0
var elapsed_usec:=0
var enabled:=false
var excluded: Dictionary={}
var excluded_time:=NAN
func reset() -> void:
	nodes.clear(); edges.clear(); islands.clear(); graph_key=0; enabled=false; excluded.clear(); excluded_time=NAN
func exclusions(controller: KiwiTimelinePhysics,id: String,time: float) -> Array[String]:
	if not is_nan(excluded_time) and is_equal_approx(excluded_time,time):
		var cached: Array[String]=[]; cached.assign(excluded.get(id,[])); return cached
	excluded_time=time; excluded.clear()
	for owner: String in controller.prototypes:
		var actor: ActorData=controller.prototypes[owner].actor; var values:=ActorAnimation.sampled_values(actor,controller._local(actor,time))
		if not values.get(&"structure_enabled",false): continue
		var saved: Dictionary=controller.states[owner].get("structural",{}).get("links",{})
		for key: String in values.get(&"structure_connections",{}):
			var link: Dictionary=values.structure_connections[key]; var target:=str(link.get("target",""))
			if link.get("exclude_collision",true) and link.get("enabled",true) and not saved.get(key,{}).get("broken",false):
				if not excluded.has(owner): excluded[owner]=[]
				if not excluded.has(target): excluded[target]=[]
				excluded[owner].append(target); excluded[target].append(owner)
	var result: Array[String]=[]; result.assign(excluded.get(id,[]))
	return result
func add_node(controller: KiwiTimelinePhysics,id: String,owner: String,state: Dictionary,config: Dictionary,role: int,bounds: AABB,mass: float,locked: bool=false) -> void:
	if nodes.size()>=MAX_ELEMENTS: controller._warn("Structure: 512-element limit reached; split or simplify the assembly."); return
	var size:=bounds.size*(state.pose as Transform3D).basis.get_scale().abs()
	var inverse:=0.0 if role!=0 or locked else 1/maxf(.001,mass)
	nodes[id]={"id":id,"owner":owner,"state":state,"mass":mass,"inv":inverse,"inertia":inverse*12/maxf(.001,size.length_squared()),"config":config,"bounds":bounds,"fixed":role!=0 or locked,"before":state.pose,"contact":false}
func endpoint(owner: String,local: Vector3) -> Dictionary:
	if nodes.has(owner): return {"id":owner,"local":local}
	var best:={}; var score:=INF
	for id: String in nodes:
		var node: Dictionary=nodes[id]
		if node.owner!=owner: continue
		var original: Vector3=node.state.get("structure_origin",Vector3.ZERO)
		var point:=local-original; var box: AABB=node.bounds; var distance:=point.distance_squared_to(point.clamp(box.position,box.end))
		if distance<.0001:
			var mesh: KiwiModelMesh=node.state.mesh
			for face in mesh.faces.size():
				if mesh.normal(face).dot(point-mesh.center(face))>.01: distance=INF; break
		# Preserve an endpoint only on a surviving piece containing that material.
		if distance<score and distance<.0001: score=distance; best={"id":id,"local":point}
	return best
func step(controller: KiwiTimelinePhysics,time: float,dt: float) -> void:
	var start:=Time.get_ticks_usec(); nodes.clear(); edges.clear(); enabled=false; var values_by_id:={}; var iterations:=2
	for id: String in controller.prototypes:
		var actor: ActorData=controller.prototypes[id].actor; var values:=ActorAnimation.sampled_values(actor,controller._local(actor,time)); var state: Dictionary=controller.states[id]
		if not values.get(&"structure_enabled",false) or not state.active: continue
		enabled=true; values_by_id[id]=values; iterations=maxi(iterations,clampi(int(values.get(&"structure_iterations",12)),2,32))
		var config:=KiwiPhysicsSettings.sample(actor,controller._local(actor,time)); var locked:=not controller.is_baking(id) and int(config.mode) in [3,4]
		config.mass=controller.destruction.mass(controller,id,state,values,float(config.mass))
		if not state.has("structural"): state.structural={"links":{},"supported":false,"island":"","load":0.0}
		state.structural.load=0.0; state.structural.supported=false; state.structural.fragments={}
		if state.get("destruction_detached",false):
			for fragment: Dictionary in state.get("destruction_fragments",[]): add_node(controller,fragment.id,id,fragment,config,0,fragment.mesh.bounds(),float(fragment.mass),locked or not values.get(&"debris_enabled",true))
		else: add_node(controller,id,id,state,config,int(values.get(&"structure_role",0)),controller.prototypes[id].geometry.bounds,float(config.mass),locked)
	for owner: String in values_by_id:
		var values: Dictionary=values_by_id[owner]; var state: Dictionary=controller.states[owner]; var local:=controller._local(controller.prototypes[owner].actor,time)
		for key: String in values.get(&"structure_connections",{}):
			if edges.size()>=MAX_LINKS: controller._warn("Structure: 1,024-joint budget reached."); break
			var link: Dictionary=values.structure_connections[key]; var target:=str(link.get("target","")); var saved: Dictionary=state.structural.links.get(key,{"broken":false,"damage":float(link.get("initial_damage",0)),"reason":""})
			state.structural.links[key]=saved; saved.damage=maxf(float(saved.damage),float(link.get("initial_damage",0))); saved.enabled=bool(link.get("enabled",true)); saved.load=0.0; saved.torque=0.0; saved.utilization=0.0
			if not controller.prototypes.has(target): controller._warn("Missing structural target on "+controller.prototypes[owner].actor.display_name+": "+target); saved.reason="Missing target"; continue
			if float(link.get("break_at",-1))>=0 and local>=float(link.break_at): saved.broken=true; saved.reason="Directed timeline break"
			var a:=endpoint(owner,link.get("pivot",Vector3.ZERO)); var b:=endpoint(target,link.get("target_pivot",Vector3.ZERO))
			if a.is_empty() or b.is_empty(): saved.reason="Inactive or removed attachment material"; continue
			if saved.broken or not saved.enabled: continue
			saved.reason=""
			if not saved.has("rest"):
				var pose_a: Transform3D=nodes[a.id].state.pose; var pose_b: Transform3D=nodes[b.id].state.pose
				saved.rest=pose_b.basis.orthonormalized().inverse()*pose_a.basis.orthonormalized()
			var owner_config:=KiwiPhysicsSettings.sample(controller.prototypes[owner].actor,local)
			var edge:={"a":a,"b":b,"owner":owner,"key":key,"link":link,"saved":saved,"linear":Vector3.ZERO,"angular":Vector3.ZERO,"locked":not controller.is_baking(owner) and int(owner_config.mode) in [3,4]}
			edges.append(edge)
	if dt>0:
		for pass_index in iterations:
			for edge in edges: solve(edge,dt)
		for edge in edges: assess(controller,edge,time,dt)
		for id: String in nodes:
			var node: Dictionary=nodes[id]; var state: Dictionary=node.state
			if node.inv==0: continue
			var delta: Vector3=state.pose.origin-node.before.origin
			state.v+=delta/dt
			var rotation: Quaternion=state.pose.basis.orthonormalized().get_rotation_quaternion()*node.before.basis.orthonormalized().get_rotation_quaternion().inverse()
			var angle:=wrapf(rotation.get_angle(),-PI,PI)
			if absf(angle)>.000001: state.w=(state.w+rotation.get_axis()*angle/dt).limit_length(30)
			if delta.length_squared()>.0000001: state.sleep=0.0
			controller.world.place(id,state.pose,bool(node.config.collision))
	update_islands(controller)
	elapsed_usec=Time.get_ticks_usec()-start
func rotate(node: Dictionary,delta: Vector3) -> void:
	if delta.length_squared()<1e-16: return
	var length:=minf(.25,delta.length()); node.state.pose.basis=Basis(Quaternion(delta.normalized(),length))*node.state.pose.basis
func solve(edge: Dictionary,dt: float) -> void:
	if edge.saved.broken: return
	var a: Dictionary=nodes[edge.a.id]; var b: Dictionary=nodes[edge.b.id]; var link: Dictionary=edge.link; var kind:=int(link.get("type",0))
	var ra: Vector3=a.state.pose.basis*edge.a.local; var rb: Vector3=b.state.pose.basis*edge.b.local
	var difference: Vector3=a.state.pose.origin+ra-b.state.pose.origin-rb
	var frame: Basis=b.state.pose.basis.orthonormalized()*Basis.from_euler(link.get("orientation",Vector3.ZERO)*PI/180)
	var axis: Vector3=frame.y.normalized(); var constrained:=difference
	if kind==2: constrained-=axis*clampf(difference.dot(axis),-float(link.get("limit",1)),float(link.get("limit",1)))
	if kind in [3,4]:
		var length:=float(link.get("length",0)); constrained=difference.normalized()*(difference.length()-length)
		if kind==3 and link.get("tension_only",true) and difference.length()<=length: constrained=Vector3.ZERO
	var alpha:=1/maxf(.01,float(link.get("stiffness",100000)))/dt/dt
	for i in 3:
		var n:=Vector3.ZERO; n[i]=1
		var ga:=ra.cross(n); var gb:=rb.cross(n); var denominator: float=a.inv+b.inv+a.inertia*ga.length_squared()+b.inertia*gb.length_squared()+alpha
		if denominator<=0: continue
		var correction: float=(-constrained[i]-alpha*edge.linear[i])/denominator
		edge.linear[i]+=correction
		a.state.pose.origin+=n*correction*a.inv; b.state.pose.origin-=n*correction*b.inv
		rotate(a,ga*correction*a.inertia); rotate(b,-gb*correction*b.inertia)
	if kind in [0,1,2]:
		var qa: Quaternion=a.state.pose.basis.orthonormalized().get_rotation_quaternion(); var qb: Quaternion=b.state.pose.basis.orthonormalized().get_rotation_quaternion()
		var error: Quaternion=qa*(qb*(edge.saved.rest as Basis).get_rotation_quaternion()).inverse(); var angle:=wrapf(error.get_angle(),-PI,PI)
		var vector:=error.get_axis()*angle if absf(angle)>1e-8 else Vector3.ZERO
		if kind==1: vector-=axis*vector.dot(axis)
		var compliance:=1/maxf(.01,float(link.get("angular_stiffness",100000)))/dt/dt
		var denominator: float=a.inertia+b.inertia+compliance
		if denominator>0:
			var correction: Vector3=(-vector-compliance*edge.angular)/denominator
			edge.angular+=correction; rotate(a,correction*a.inertia); rotate(b,-correction*b.inertia)
	# Damping is applied once below, not once per solver iteration.
func assess(controller: KiwiTimelinePhysics,edge: Dictionary,time: float,dt: float) -> void:
	if edge.get("locked",false): return
	var link: Dictionary=edge.link; var saved: Dictionary=edge.saved; var a: Dictionary=nodes[edge.a.id]; var b: Dictionary=nodes[edge.b.id]
	var force: Vector3=edge.linear/(dt*dt); var torque: Vector3=edge.angular/(dt*dt)
	var frame: Basis=b.state.pose.basis.orthonormalized()*Basis.from_euler(link.get("orientation",Vector3.ZERO)*PI/180); var component:=force.dot(frame.y); var axial:=component*(-1 if (b.state.pose.origin-a.state.pose.origin).dot(frame.y)<0 else 1)
	var strength:=maxf(.0001,float(link.get("strength",1))*(1-clampf(float(saved.damage),0,.999)))
	if link.get("material_strength",false):
		for owner in [a.owner,b.owner]:
			var physical:=KiwiDestructionMaterial.resolve(ActorAnimation.sampled_values(controller.prototypes[owner].actor,controller._local(controller.prototypes[owner].actor,time)))
			if physical!=null: strength*=sqrt(clampf((float(physical.get_value(&"strength",10))+float(physical.get_value(&"toughness",5)))/20,.1,10))
	var breaking:=maxf(.001,float(link.get("breaking_force",10000))*strength)
	var bending:=maxf(.001,float(link.get("breaking_torque",10000))*strength*maxf(.001,float(link.get("bending",1))))
	var lever_a: Vector3=a.state.pose.basis*edge.a.local; var lever_b: Vector3=b.state.pose.basis*edge.b.local
	var moment:=maxf(torque.length(),maxf(lever_a.cross(force).length(),lever_b.cross(force).length()))
	var utilization:=maxf(maxf(0,axial)/(breaking*maxf(.001,float(link.get("tension",1)))),maxf(0,-axial)/(breaking*maxf(.001,float(link.get("compression",1)))))
	utilization=maxf(utilization,(force-frame.y*component).length()/(breaking*maxf(.001,float(link.get("shear",1))))); utilization=maxf(utilization,moment/bending)
	saved.load=force.length(); saved.torque=moment; saved.utilization=utilization; saved.force=force
	for node in [a,b]: controller.states[node.owner].structural.load+=force.length()
	if not link.get("prevent_failure",false):
		saved.damage=minf(1,float(saved.damage)+maxf(0,utilization-.35)*maxf(0,utilization-.35)*float(link.get("damage_rate",.05))*dt)
		if utilization>=1 or saved.damage>=1:
			saved.broken=true; saved.reason="Force / torque overload"; controller.connection_broken.emit(edge.owner,edge.key,time)
			controller.debris.emit(controller,edge.owner,edge.key,"collapse",time,a.state.pose*edge.a.local,frame.y,a.state.v,.5*force.length_squared()/maxf(1,float(link.stiffness)))
	var damping:=clampf(float(link.get("damping",.15)),0,1); var relative: Vector3=a.state.v-b.state.v
	if int(link.type)==1: relative=relative # Hinge still damps relative pivot translation.
	var total: float=a.inv+b.inv
	if total>0 and not saved.broken:
		a.state.v-=relative*damping*a.inv/total; b.state.v+=relative*damping*b.inv/total
	for node in [a,b]:
		var parent: Dictionary=controller.states[node.owner]
		if node.id!=node.owner or parent.get("destruction_detached",false): continue
		var actor: ActorData=controller.prototypes[node.owner].actor; var local:=controller._local(actor,time)
		if not actor.get_value(&"destruction_enabled",false) and actor.animation_track(PackedStringArray(["destruction_enabled"]))==null: continue
		if local<float(parent.get("structure_damage_next",0)): continue
		var energy:=.5*force.length_squared()/maxf(1,float(link.stiffness))+.5*moment*moment/maxf(1,float(link.angular_stiffness))
		if axial<0:
			var dimensions: Vector3=node.bounds.size*(node.state.pose as Transform3D).basis.get_scale().abs()
			var slenderness:=dimensions[dimensions.max_axis_index()]/maxf(.01,dimensions[dimensions.min_axis_index()])
			energy*=clampf(1+slenderness*slenderness*.005,1,6) # Artistic slender-column compression amplification, not Euler/FEM certification.
		var values:=ActorAnimation.sampled_values(actor,local)
		if energy>.0001 and values.get(&"destruction_enabled",false) and int(values.get(&"destruction_mode",0))!=0:
			var point: Vector3=node.state.pose*(edge.a.local if node==a else edge.b.local)
			parent.structure_pending_impacts=parent.get("structure_pending_impacts",[]); parent.structure_pending_impacts.append({"point":point,"normal":force.normalized(),"energy":energy}); parent.structure_damage_next=local+.15
func update_islands(controller: KiwiTimelinePhysics) -> void:
	var adjacency:={}; var supported:={}; var queue: Array[String]=[]; var stamp:=[]
	for id: String in nodes:
		adjacency[id]=[]
		if nodes[id].fixed: supported[id]=true; queue.append(id)
	for edge in edges:
		if edge.saved.broken: continue
		adjacency[edge.a.id].append(edge.b.id); adjacency[edge.b.id].append(edge.a.id); stamp.append([edge.a.id,edge.b.id])
	var next:=hash([nodes.keys(),stamp])
	if graph_key!=next:
		graph_key=next; graph_builds+=1; islands.clear()
		for id: String in nodes:
			if islands.has(id): continue
			var walk: Array[String]=[id]; islands[id]=id
			while not walk.is_empty():
				var current:=walk.pop_back() as String
				for neighbor: String in adjacency[current]:
					if not islands.has(neighbor): islands[neighbor]=id; walk.append(neighbor)
	# Contacts are directed compressive support, never permanent weld edges.
	var support_adjacency:=adjacency.duplicate(true)
	for id: String in nodes:
		var owner: String=nodes[id].owner
		for hit: Dictionary in controller.states[owner].get("structure_contacts",[]):
			if (hit.normal as Vector3).dot(Vector3.UP)<.35: continue
			var target:=str(hit.actor)
			if nodes.has(target): support_adjacency[target].append(id)
			elif controller.states.has(target) and controller.states[target].active and not controller.states[target].get("responds",false): supported[id]=true; queue.append(id)
	while not queue.is_empty():
		var id:=queue.pop_back() as String
		for neighbor: String in support_adjacency[id]:
			if not supported.has(neighbor): supported[neighbor]=true; queue.append(neighbor)
	for id: String in nodes:
		var state: Dictionary=controller.states[nodes[id].owner]
		state.structural.supported=bool(state.structural.supported) or supported.has(id); state.structural.island=islands.get(id,id)
		state.structural.fragments[id]={"supported":supported.has(id),"island":islands.get(id,id)}
