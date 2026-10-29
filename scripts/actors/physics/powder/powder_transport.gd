class_name KiwiPowderTransport
extends RefCounted
## Surface-local sleeping deposits. IDs and mass never change at phase transitions.
enum Phase { ACTIVE, DEPOSITED, AIRBORNE }
static func fields(d: ActorDefinition) -> void:
	for row in [
		["powder_deposition","Deposition enabled",false,{}],
		["powder_adhesion","Surface adhesion (N/grain)",0.0,{"min":0.0,"max":2.0,"step":.001}],
		["powder_settling","Settling speed (m/s)",.08,{"min":.001,"max":2.0}],
		["powder_coating","Maximum attached coating (m)",.25,{"min":.001,"max":5.0}],
		["powder_deposit_compaction","Deposit compaction rate",.3,{"min":0.0,"max":5.0}],
		["powder_displacement","Collision displacement",true,{}],
		["powder_displacement_resistance","Displacement resistance",.2,{"min":0.0,"max":10.0}],
		["powder_reactivation","Detachment exposure (s)",.15,{"min":.01,"max":5.0}],
		["powder_erosion","Erosion enabled",true,{}],
		["powder_erosion_resistance","Erosion resistance",1.0,{"min":.01,"max":20.0}],
		["powder_wind_erosion","Wind erosion influence",1.0,{"min":0.0,"max":10.0}],
		["powder_fluid_erosion","Fluid erosion influence",1.0,{"min":0.0,"max":10.0}],
		["powder_airborne","Airborne classification",true,{}],
		["powder_airborne_threshold","Airborne speed (m/s)",.2,{"min":.01,"max":10.0}],
		["powder_clear_at","Reactivate deposits at (-1 = never)",-1.0,{"min":-1.0,"max":86400.0}]
	]:
		if row[0] not in ["powder_deposition","powder_adhesion","powder_settling","powder_displacement","powder_erosion","powder_airborne"]: row[3].advanced=true
		KiwiPowderDefinition.add(d,row[0],row[1],row[2],"Deposition & Transport",row[3])

static func release(state: Dictionary,index: int,velocity: Vector3) -> void:
	state.powder_deposits.erase(int(state.powder_ids[index])); state.powder_phase[index]=Phase.ACTIVE
	state.velocities[index]=velocity; state.powder_sleep[index]=0; state.powder_settle[index]=0
	state.powder_releases=int(state.get("powder_releases",0))+1

static func before(controller: KiwiTimelinePhysics,batches: Array[Dictionary],time: float,motions: Dictionary) -> void:
	for batch: Dictionary in batches:
		if not batch.moving: continue
		var state: Dictionary=batch.state; var s: Dictionary=batch.settings
		var fluids: Array[Dictionary]=[]
		if s.get(&"powder_erosion",true) and not state.powder_deposits.is_empty(): fluids=KiwiPowderFluid.fluids(controller,batch,time)
		var clear_at:=float(s.get(&"powder_clear_at",-1)); var clear: bool=clear_at>=0 and float(state.powder_time)>=clear_at and not state.get("powder_cleared",false)
		if clear: state.powder_cleared=true
		for i in state.points.size():
			if int(state.powder_phase[i])!=Phase.DEPOSITED: continue
			var deposit: Dictionary=state.powder_deposits.get(int(state.powder_ids[i]),{})
			var owner:=str(deposit.get("actor","")); var other: Dictionary=controller.states.get(owner,{})
			if clear or not s.get(&"powder_deposition",false) or other.is_empty() or not other.get("active",false): release(state,i,Vector3.ZERO); continue
			var config:=KiwiPhysicsSettings.sample(controller.prototypes[owner].actor,controller._local(controller.prototypes[owner].actor,time))
			if not config.collision or not config.powder_accumulation: release(state,i,Vector3.ZERO); continue
			var pose: Transform3D=other.pose; var next: Vector3=pose*deposit.local; var normal: Vector3=(pose.basis.inverse().transposed()*deposit.normal).normalized()
			var proxy:=str(deposit.get("proxy","")); var proxy_index:=int(proxy.get_slice(":p",1)) if proxy.contains(":p") else -1
			if controller.fluid.proxies.bodies.has(proxy) and deposit.has("proxy_local"):
				var proxy_pose: Transform3D=PhysicsServer3D.body_get_state(controller.fluid.proxies.bodies[proxy].rid,PhysicsServer3D.BODY_STATE_TRANSFORM)
				next=proxy_pose*deposit.proxy_local; normal=proxy_pose.basis*deposit.proxy_normal
			elif proxy_index>=0 and proxy_index<other.points.size(): next=other.points[proxy_index]+deposit.proxy_offset
			var velocity: Vector3=(next-state.points[i])/maxf(.000001,float(batch.h)); state.points[i]=next; state.velocities[i]=velocity
			var mass:=maxf(1e-9,float(state.powder_masses[i])); var radius:=float(state.powder_radii[i]); var g: float=batch.gravity.length()*float(s.gravity_scale)
			var support:=maxf(0,normal.dot((-batch.gravity as Vector3).normalized()))
			var resistance: float=(float(s.get(&"powder_adhesion",0))+float(config.powder_adhesion)+float(s.cohesion)+mass*g*support*float(s.static_friction))*(1+float(state.powder_compaction[i]))
			var relative: Vector3=batch.wind-velocity; var force: float=.5*1.225*float(s.air_drag)*PI*radius*radius*relative.length_squared()*float(s.wind_influence)*float(s.get(&"powder_wind_erosion",1))
			var transport_velocity:=relative
			for fluid: Dictionary in fluids:
				var neighbors:=KiwiPowderFluid.near(fluid,next)
				if neighbors.is_empty(): continue
				var flow:=Vector3.ZERO
				for j in neighbors: flow+=fluid.state.velocities[j]/neighbors.size()
				var shear: Vector3=flow-velocity
				force+=.5*float(fluid.values.fluid_density)*PI*radius*radius*shear.length_squared()*float(s.fluid_strength)*float(s.get(&"powder_fluid_erosion",1)); transport_velocity+=shear
			var downhill:=sqrt(maxf(0,1-support*support))*mass*g
			var ratio: float=(force+downhill)/maxf(1e-9,resistance)
			if s.get(&"powder_erosion",true): deposit.damage=maxf(0,float(deposit.get("damage",0))+(ratio-1)*float(batch.h)/maxf(.01,float(s.get(&"powder_erosion_resistance",1))))
			if float(deposit.get("damage",0))>=float(s.get(&"powder_reactivation",.15)):
				release(state,i,velocity+transport_velocity*.15+normal*minf(1,sqrt(force/mass)*.05)); continue
			if s.get(&"powder_displacement",true):
				var exclude: Array[String]=[owner]
				var hit:=controller.world.point_motion(batch.id,next,next,radius,int(batch.config.layer),int(batch.config.mask),exclude)
				var displacement: Vector3=hit.position-next
				# An initially overlapping cylinder can report penetration with zero
				# travel. Use its real contact depth instead of relying on the support
				# collider's recovery (which is deliberately excluded from this query).
				for contact: Dictionary in hit.hits:
					var depth:=maxf(0,float(contact.get("depth",0))-.002)
					if depth>displacement.length(): displacement=(contact.normal as Vector3)*minf(depth,radius)
				if not hit.hits.is_empty() and displacement.length()>radius*.02:
					var target:=str(hit.hits[0].actor); var movement: Vector3=motions.get(target,{"linear":Vector3.ZERO}).linear
					if movement.length()+displacement.length()/maxf(.000001,float(batch.h))>float(s.get(&"powder_displacement_resistance",.2)):
						state.points[i]=next+displacement; release(state,i,velocity+movement); continue
			state.powder_compaction[i]=minf(1,float(state.powder_compaction[i])+float(s.get(&"powder_deposit_compaction",.3))*float(batch.h)*.1)

static func after(controller: KiwiTimelinePhysics,batches: Array[Dictionary],time: float) -> void:
	for batch: Dictionary in batches:
		if not batch.moving: continue
		var state: Dictionary=batch.state; var s: Dictionary=batch.settings; var cells:={}
		for i in state.points.size():
			if int(state.powder_phase[i])==Phase.DEPOSITED: continue
			var support: Dictionary=state.get("powder_supports",{}).get(int(state.powder_ids[i]),{})
			var speed: float=state.velocities[i].length()
			state.powder_phase[i]=Phase.AIRBORNE if s.get(&"powder_airborne",true) and support.is_empty() and speed>float(s.get(&"powder_airborne_threshold",.2)) else Phase.ACTIVE
			if not s.get(&"powder_deposition",false) or support.is_empty(): state.powder_settle[i]=0; continue
			var owner:=str(support.get("actor","")); var other: Dictionary=controller.states.get(owner,{})
			if other.is_empty() or not other.active: continue
			var config:=KiwiPhysicsSettings.sample(controller.prototypes[owner].actor,controller._local(controller.prototypes[owner].actor,time))
			if not config.powder_accumulation: continue
			var normal: Vector3=support.normal; var relative: Vector3=state.velocities[i]-support.get("velocity",Vector3.ZERO)
			var support_force: float=maxf(0,normal.dot((-batch.gravity as Vector3).normalized()))
			var adhesion: float=float(s.get(&"powder_adhesion",0))+float(config.powder_adhesion)
			if support_force<.2 and adhesion<float(state.powder_masses[i])*batch.gravity.length(): continue
			if relative.length()>float(s.get(&"powder_settling",.08)): state.powder_settle[i]=0; continue
			state.powder_settle[i]+=float(batch.h)
			if float(state.powder_settle[i])<float(s.sleep_delay): continue
			var pose: Transform3D=other.pose; var local: Vector3=pose.affine_inverse()*state.points[i]
			var radius:=float(state.powder_radii[i])
			if radius*2>minf(float(s.get(&"powder_coating",.25)),float(config.powder_max_coating)): continue
			var proxy:=str(support.get("proxy","")); var index:=int(proxy.get_slice(":p",1)) if proxy.contains(":p") else -1
			var offset: Vector3=state.points[i]-other.points[index] if index>=0 and index<other.points.size() else Vector3.ZERO
			state.powder_deposits[int(state.powder_ids[i])] = {"actor":owner,"proxy":proxy,"local":local,"normal":pose.basis.transposed()*normal,"proxy_offset":offset,"damage":0.0}
			if controller.fluid.proxies.bodies.has(proxy):
				var proxy_pose: Transform3D=PhysicsServer3D.body_get_state(controller.fluid.proxies.bodies[proxy].rid,PhysicsServer3D.BODY_STATE_TRANSFORM)
				state.powder_deposits[int(state.powder_ids[i])].proxy_local=proxy_pose.affine_inverse()*state.points[i]; state.powder_deposits[int(state.powder_ids[i])].proxy_normal=proxy_pose.basis.inverse()*normal
			state.powder_phase[i]=Phase.DEPOSITED; state.velocities[i]=support.get("velocity",Vector3.ZERO)
		for i in state.points.size():
			if int(state.powder_phase[i])!=Phase.DEPOSITED: continue
			var deposit: Dictionary=state.powder_deposits[int(state.powder_ids[i])]; var r:=float(state.powder_radii[i]); var cell:=str(deposit.actor)+":"+str(Vector3i((deposit.local/maxf(.001,r*4)).floor()))
			if not cells.has(cell): cells[cell]={"actor":deposit.actor,"mass":0.0,"volume":0.0,"area":maxf(.000001,r*r*16),"count":0}
			cells[cell].mass+=float(state.powder_masses[i]); cells[cell].volume+=4.0/3*PI*pow(r,3); cells[cell].count+=1; cells[cell].thickness=cells[cell].volume/cells[cell].area
		state.powder_cells=cells; state.powder_inventory=inventory(state)

static func inventory(state: Dictionary) -> Dictionary:
	var result:={"active":0.0,"deposited":0.0,"airborne":0.0,"total":0.0,"count":state.points.size()}
	for i in state.points.size():
		var mass:=float(state.powder_masses[i]); result.total+=mass; result[["active","deposited","airborne"][int(state.powder_phase[i])]]+=mass
	return result
