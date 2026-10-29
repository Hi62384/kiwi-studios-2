class_name KiwiPowderSolver
extends RefCounted
## CPU XPBD unilateral sphere contacts, Coulomb positional friction and breakable bonds.
## The adapter supplies time, boundary queries and reactions; no live physics nodes.
const MAX_PAIRS:=1000000
const MAX_BONDS_PER_ACTOR:=65536
var positions:=PackedVector3Array()
var previous:=PackedVector3Array()
var velocities:=PackedVector3Array()
var radii:=PackedFloat32Array()
var masses:=PackedFloat32Array()
var inverse_masses:=PackedFloat32Array()
var owners:=PackedInt32Array()
var slots:=PackedInt32Array()
var contacts:=PackedInt32Array()
var batches: Array[Dictionary]=[]
var pairs:=PackedInt32Array()
var lambdas:=PackedFloat32Array()
var checks:=0
var elapsed_usec:=0
var error:=""

func solve(input: Array[Dictionary],collide: Callable,reaction: Callable,prepare: Callable=Callable()) -> void:
	var started:=Time.get_ticks_usec(); batches=input; checks=0; error=""
	positions.clear(); velocities.clear(); radii.clear(); masses.clear(); inverse_masses.clear(); owners.clear(); slots.clear()
	var substeps:=1; var iterations:=2; var max_radius:=.001; var min_radius:=INF; var max_h:=0.0; var max_speed:=0.0
	for b in batches.size():
		var batch: Dictionary=batches[b]; var state: Dictionary=batch.state; var settings: Dictionary=batch.settings
		state.powder_supports={}
		substeps=maxi(substeps,int(settings.substeps)); iterations=maxi(iterations,int(settings.iterations)); max_h=maxf(max_h,float(batch.h))
		for i in state.points.size():
			var radius:=maxf(.0001,float(state.powder_radii[i])); var mass:=float(settings.density)*4.0/3.0*PI*pow(radius,3)
			state.powder_masses[i]=mass
			positions.append(state.points[i]); velocities.append(state.velocities[i]); radii.append(radius); masses.append(mass)
			var deposited: bool=state.has("powder_phase") and int(state.powder_phase[i])==KiwiPowderTransport.Phase.DEPOSITED
			inverse_masses.append(1.0/maxf(1e-9,mass) if batch.moving and not deposited else 0.0); owners.append(b); slots.append(i)
			max_radius=maxf(max_radius,radius); min_radius=minf(min_radius,radius); max_speed=maxf(max_speed,state.velocities[i].length())
	if positions.is_empty(): return
	substeps=clampi(maxi(substeps,ceili((max_speed+20*max_h)*max_h/maxf(.001,min_radius*.6))),1,16)
	var boundaries:=[]; boundaries.resize(positions.size()); contacts.resize(positions.size())
	for substep in substeps:
		if prepare.is_valid(): prepare.call(float(substep+1)/substeps)
		previous=positions.duplicate(); contacts.fill(0)
		for i in positions.size():
			var batch: Dictionary=batches[owners[i]]; var s: Dictionary=batch.settings; var h:=float(batch.h)/substeps
			boundaries[i]=[]
			if inverse_masses[i]==0 or h<=0: continue
			var state: Dictionary=batch.state; var index:=slots[i]
			var acceleration: Vector3=batch.gravity*float(s.gravity_scale)+batch.force/masses[i]
			if substep==0: velocities[i]+=batch.impulse/masses[i]
			var wind: Vector3=batch.wind
			var seed:=int(state.powder_ids[index]); var t:=float(state.powder_time)
			wind+=Vector3(sin(t*1.7+seed*.73),sin(t*1.31+seed*.37),cos(t*1.83+seed*.51))*float(s.turbulence)
			var relative:=wind-velocities[i]; var shelter:=1.0/(1.0+maxi(0,int(state.powder_contacts[index])-3)*.4)
			var drag:=.5*1.225*float(s.air_drag)*PI*radii[i]*radii[i]/masses[i]*relative.length()*float(s.wind_influence)*shelter
			velocities[i]+=relative*(1.0-exp(-drag*h))
			velocities[i]=(velocities[i]+acceleration*h).limit_length(minf(float(s.max_speed),radii[i]*.65*substeps/maxf(.000001,float(batch.h))))
			# Rest clears residual velocity, never gravity/support checks. A pile
			# immediately wakes if its floor is removed or contacts are disturbed.
			if float(state.powder_sleep[index])>=float(s.sleep_delay) and acceleration.length()<20 and relative.length()*drag<.1 and batch.impulse.is_zero_approx(): velocities[i]=acceleration*h
			positions[i]+=velocities[i]*h
			if batch.config.collision:
				var result: Dictionary=collide.call(batch.id,previous[i],positions[i],radii[i],h)
				for hit: Dictionary in result.get("hits",[]): boundaries[i].append(hit)
				var correction: Vector3=result.position-positions[i]; positions[i]=result.position
				if not correction.is_zero_approx() and not boundaries[i].is_empty(): _reaction(reaction,i,boundaries[i][0],correction,h)
		var incoming_velocities:=velocities.duplicate()
		if not _neighbors(max_radius): return
		lambdas.resize(pairs.size()/2); lambdas.fill(0)
		for iteration in iterations:
			for pair in pairs.size()/2: _contact(pair,iterations,substeps,iteration==iterations-1)
			for i in positions.size():
				if inverse_masses[i]==0: continue
				var batch: Dictionary=batches[owners[i]]; var h:=float(batch.h)/substeps
				for hit: Dictionary in boundaries[i]: _boundary(i,hit,h,reaction,iteration==iterations-1)
		# Constraints can push grains into a new surface. One final swept query
		# catches those contacts without doing a native query for every iteration.
		for i in positions.size():
			var batch: Dictionary=batches[owners[i]]; var s: Dictionary=batch.settings; var h:=float(batch.h)/substeps
			if inverse_masses[i]==0 or h<=0: continue
			if batch.config.collision:
				var result: Dictionary=collide.call(batch.id,previous[i],positions[i],radii[i],h)
				var correction: Vector3=result.position-positions[i]; positions[i]=result.position
				for hit: Dictionary in result.get("hits",[]):
					if boundaries[i].is_empty() and not correction.is_zero_approx(): _reaction(reaction,i,hit,correction,h)
					_boundary(i,hit,h,reaction,false)
			var incoming:=velocities[i]; velocities[i]=(positions[i]-previous[i])/h
			for hit: Dictionary in boundaries[i]:
				var normal: Vector3=hit.normal; var surface: Vector3=hit.get("velocity",Vector3.ZERO)
				var impact: float=(incoming-surface).dot(normal)
				if impact<-.3:
					var bounce:=sqrt(float(s.restitution)*float(hit.get("restitution",s.restitution)))
					var extra:=maxf(0,-impact*bounce-(velocities[i]-surface).dot(normal))
					velocities[i]+=normal*extra
					if extra>0 and reaction.is_valid(): reaction.call(hit,-normal*extra*masses[i],Vector3.ZERO)
			velocities[i]*=exp(-float(s.damping)*h)
			if not positions[i].is_finite() or not velocities[i].is_finite(): positions[i]=previous[i]; velocities[i]=Vector3.ZERO; error="Non-finite granular state was recovered; reduce forces or source overlap."
			velocities[i]=velocities[i].limit_length(float(s.max_speed))
			var state: Dictionary=batch.state; var index:=slots[i]
			if contacts[i]>0 and velocities[i].length()<float(s.sleep_speed):
				state.powder_sleep[index]+=h
				if state.powder_sleep[index]>=float(s.sleep_delay): velocities[i]=Vector3.ZERO
			else: state.powder_sleep[index]=0
			state.powder_contacts[index]=contacts[i]
			state.powder_compaction[index]=maxf(float(state.powder_compaction[index])*.999,clampf(float(contacts[i])/12,0,1))
		# Impact restitution and damping exchange equal/opposite grain impulses.
		for pair in pairs.size()/2: _velocity_contact(pair,incoming_velocities)
	for i in positions.size():
		var state: Dictionary=batches[owners[i]].state; state.points[slots[i]]=positions[i]; state.velocities[slots[i]]=velocities[i]
	_prune_bonds()
	elapsed_usec=Time.get_ticks_usec()-started

func _prune_bonds() -> void:
	var lookup:={}
	for i in positions.size(): lookup[str(batches[owners[i]].id)+":"+str(batches[owners[i]].state.powder_ids[slots[i]])]=i
	for batch: Dictionary in batches:
		var bonds: Dictionary=batch.state.powder_bonds
		for key in bonds.keys():
			var bond: Dictionary=bonds[key]; var a:=int(lookup.get(str(batch.id)+":"+str(bond.a),-1)); var b:=int(lookup.get(str(bond.actor)+":"+str(bond.b),-1))
			if a<0 or b<0 or float(batch.settings.cohesion)<=0:
				bonds.erase(key); continue
			var limit:=minf(float(batch.settings.separation),float(batches[owners[b]].settings.separation))
			if positions[a].distance_to(positions[b])>float(bond.rest)*(1+limit): bonds.erase(key)

func _neighbors(max_radius: float) -> bool:
	var separation:=0.0
	for batch: Dictionary in batches: separation=maxf(separation,float(batch.settings.separation) if float(batch.settings.cohesion)>0 else 0.0)
	var cell_size:=max_radius*2*(1.0+separation); var grid:={}; var cells:=[]; pairs.clear()
	for i in positions.size():
		var cell:=Vector3i((positions[i]/cell_size).floor()); cells.append(cell)
		if not grid.has(cell): grid[cell]=[]
		grid[cell].append(i)
	for i in positions.size():
		var cell: Vector3i=cells[i]; var a: Dictionary=batches[owners[i]]
		for x in range(-1,2):
			for y in range(-1,2):
				for z in range(-1,2):
					for j: int in grid.get(cell+Vector3i(x,y,z),[]):
						if j<=i: continue
						checks+=1
						var b: Dictionary=batches[owners[j]]
						if not a.config.collision or not b.config.collision or (int(a.config.layer)&int(b.config.mask))==0 or (int(b.config.layer)&int(a.config.mask))==0: continue
						if positions[i].distance_squared_to(positions[j])>pow((radii[i]+radii[j])*(1.0+separation),2): continue
						if pairs.size()>=MAX_PAIRS*2: error="Excessive grain overlap exceeds the contact budget. Increase source spacing; no grains were discarded."; return false
						pairs.append(i); pairs.append(j)
	return true

func _contact(pair: int,iterations: int,substeps: int,count_contact: bool) -> void:
	var i:=pairs[pair*2]; var j:=pairs[pair*2+1]; var w:=inverse_masses[i]+inverse_masses[j]
	if w<=0: return
	var a: Dictionary=batches[owners[i]]; var b: Dictionary=batches[owners[j]]; var sa: Dictionary=a.settings; var sb: Dictionary=b.settings
	var h:=maxf(.000001,minf(float(a.h) if a.moving else float(b.h),float(b.h) if b.moving else float(a.h))/substeps)
	var delta:=positions[i]-positions[j]; var distance:=delta.length(); var normal:=delta/maxf(distance,1e-8)
	if distance<1e-8: normal=Vector3.RIGHT if (i+j)%2==0 else Vector3.UP
	var rest:=radii[i]+radii[j]; var penetration:=rest-distance
	# An overlapping birth/authoring error is position repair, not stored spring
	# energy. Move the velocity reference with that repair to avoid explosive jets.
	var initial_delta:=previous[i]-previous[j]; var initial_overlap:=rest-initial_delta.length()
	if lambdas[pair]==0 and initial_overlap>rest*.05:
		var repair:=normal*initial_overlap/w
		previous[i]+=repair*inverse_masses[i]; previous[j]-=repair*inverse_masses[j]
	if distance<rest*.9:
		var hard_limit: Vector3=normal*(rest*.9-distance)/w
		positions[i]+=hard_limit*inverse_masses[i]; positions[j]-=hard_limit*inverse_masses[j]; penetration=rest*.1
	if penetration>0 or lambdas[pair]>0:
		var packing:=sqrt(float(sa.packing)*float(sb.packing)); var compliance: float=pow(1.0-packing,2)*.05/(h*h)
		var change: float=(penetration-compliance*lambdas[pair])/(w+compliance)
		change=maxf(-lambdas[pair],change); lambdas[pair]+=change
		positions[i]+=normal*change*inverse_masses[i]; positions[j]-=normal*change*inverse_masses[j]
		var relative: Vector3=(positions[i]-previous[i])-(positions[j]-previous[j]); var tangent:=relative-normal*relative.dot(normal); var length:=tangent.length()
		var support: float=lambdas[pair]*w
		var mu_static:=sqrt(float(sa.static_friction)*float(sb.static_friction)); var mu_dynamic:=sqrt(float(sa.dynamic_friction)*float(sb.dynamic_friction))+sqrt(float(sa.rolling)*float(sb.rolling))
		if length>1e-9 and count_contact:
			var fraction:=1.0 if length<mu_static*support else minf(1,mu_dynamic*support/length)
			var correction:=tangent*fraction/w; positions[i]-=correction*inverse_masses[i]; positions[j]+=correction*inverse_masses[j]
		if count_contact and distance<rest*1.03: contacts[i]+=1; contacts[j]+=1
	var strength:=sqrt(float(sa.cohesion)*float(sb.cohesion)); var bond_key:=str(a.state.powder_ids[slots[i]])+"|"+str(b.id)+"|"+str(b.state.powder_ids[slots[j]])
	var bonds: Dictionary=a.state.powder_bonds
	if strength<=0 or distance>rest*(1.0+minf(float(sa.separation),float(sb.separation))): bonds.erase(bond_key); return
	if not bonds.has(bond_key) and distance<=rest*1.1:
		if bonds.size()>=MAX_BONDS_PER_ACTOR: error="Cohesive contact storage limit reached. Reduce grain count or cohesion range; grain identities are preserved."; return
		bonds[bond_key]={"a":int(a.state.powder_ids[slots[i]]),"actor":b.id,"b":int(b.state.powder_ids[slots[j]]),"rest":rest}
	if bonds.has(bond_key) and distance>rest:
		var compact:=1.0+.25*minf(float(a.state.powder_compaction[slots[i]]),float(b.state.powder_compaction[slots[j]]))
		var correction: Vector3=normal*minf((distance-rest)/w,strength*compact*h*h/iterations)
		positions[i]-=correction*inverse_masses[i]; positions[j]+=correction*inverse_masses[j]

func _boundary(i: int,hit: Dictionary,h: float,reaction: Callable,count_contact: bool) -> void:
	var batch: Dictionary=batches[owners[i]]; var s: Dictionary=batch.settings; var normal: Vector3=hit.normal
	var depth:=radii[i]-normal.dot(positions[i]-(hit.point as Vector3)); var correction:=normal*maxf(0,depth)
	positions[i]+=correction
	var relative: Vector3=positions[i]-previous[i]-hit.get("velocity",Vector3.ZERO)*h
	var tangent:=relative-normal*relative.dot(normal); var length:=tangent.length()
	var support:=maxf(depth,(-batch.gravity as Vector3).dot(normal)*h*h)
	var mu_static:=sqrt(float(s.static_friction)*float(hit.get("friction",s.static_friction))); var mu_dynamic:=sqrt(float(s.dynamic_friction)*float(hit.get("friction",s.dynamic_friction)))
	if length>1e-9 and count_contact:
		var fraction:=1.0 if length<mu_static*support else minf(1,(mu_dynamic+float(s.rolling))*support/length)
		positions[i]-=tangent*fraction; correction-=tangent*fraction
	if count_contact:
		contacts[i]+=1
		var id:=int(batch.state.powder_ids[slots[i]]); var old: Dictionary=batch.state.powder_supports.get(id,{})
		if old.is_empty() or normal.dot(-batch.gravity)>=old.normal.dot(-batch.gravity): batch.state.powder_supports[id]=hit
	if not correction.is_zero_approx(): _reaction(reaction,i,hit,correction,h)
func _reaction(callback: Callable,i: int,hit: Dictionary,correction: Vector3,h: float) -> void:
	if callback.is_valid() and h>0:
		var contact:=hit.duplicate(); contact.grain_mass=masses[i]; contact.grain_key=str(batches[owners[i]].id)+":"+str(slots[i]); contact.grain_velocity=velocities[i]*float(hit.get("source_speed",1))
		callback.call(contact,-correction*masses[i]/h,-correction*masses[i])
func _velocity_contact(pair: int,incoming: PackedVector3Array) -> void:
	var i:=pairs[pair*2]; var j:=pairs[pair*2+1]; var w:=inverse_masses[i]+inverse_masses[j]
	if w<=0: return
	var delta:=positions[i]-positions[j]
	if delta.length_squared()>pow((radii[i]+radii[j])*1.04,2): return
	var normal:=delta.normalized(); var relative:=velocities[i]-velocities[j]; var speed:=relative.dot(normal)
	var a: Dictionary=batches[owners[i]].settings; var b: Dictionary=batches[owners[j]].settings
	var impact: float=(incoming[i]-incoming[j]).dot(normal)
	var restitution:=sqrt(float(a.restitution)*float(b.restitution)) if impact<-.3 else 0.0
	var damping:=maxf(float(a.contact_damping),float(b.contact_damping))
	var target:=maxf(0,-impact*restitution)
	var change:=maxf(0,target-speed) if restitution>0 else maxf(0,-speed*damping)
	var impulse:=normal*change/w
	velocities[i]+=impulse*inverse_masses[i]; velocities[j]-=impulse*inverse_masses[j]
