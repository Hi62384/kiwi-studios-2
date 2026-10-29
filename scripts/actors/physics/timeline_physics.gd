class_name KiwiTimelinePhysics
extends RefCounted
signal status_changed(message: String)
signal fluid_contacts(actor_id: String, scene_time: float, contacts: Array)
signal mesh_damage(actor_id: String,scene_time: float,impact: Dictionary)
signal mesh_fractured(actor_id: String,scene_time: float,pieces: int)
signal connection_broken(actor_id: String,connection_id: String,scene_time: float)
signal destruction_event(event: Dictionary)
## No _physics_process, real-time deltas, Engine.time_scale, or live rigid bodies.
const MAX_CHECKPOINTS := 96
const MAX_CACHE_BYTES := 67108864
const SEEK_BUDGET := 240
const FogMotion=preload("res://scripts/actors/fog/fog_motion_bridge.gd")
var world := KiwiPhysicsCollisionWorld.new()
var fluid := KiwiFluidBridge.new()
var powder := KiwiPowderBridge.new()
var destruction:=KiwiDestructionBridge.new()
var structure:=KiwiStructureBridge.new()
var debris:=KiwiDebrisBridge.new()
var vfx:=KiwiDestructionVFX.new()
var prototypes: Dictionary = {}
var states: Dictionary = {}
var checkpoints: Dictionary = {}
var display_states: Dictionary = {}
var base_display_states: Dictionary={}
var signature := ""
var dirty := true
var pending := false
var status := ""
var steps_taken := 0
var generation := 0
var rate := 60
var origin := 0.0
var step := 0
var requested_time := NAN
var _model: RefCounted
var _runtimes: Dictionary = {}
var _floor_states: Dictionary = {}
var _floor_step := -1
var _applied_time := NAN
var _warnings: Array[String] = []
var _baking_actor := ""
var _baking_actors: Dictionary={}
var bake_cancelled:=false
var bake_progress:=0.0
func is_baking(id: String) -> bool: return id==_baking_actor or _baking_actors.has(id)
func cancel_bake() -> void: bake_cancelled=true

func mark_dirty() -> void: dirty = true
func invalidate_asset(path: String) -> void:
	if _model==null or prototypes.is_empty(): return
	var identity:=ProjectSettings.globalize_path(path).replace("\\","/").simplify_path()
	for prototype: Dictionary in prototypes.values():
		var actor: ActorData=prototype.actor
		if actor.type_id!=&"environment_asset": continue
		var environment_path:=str(actor.values.get(&"environment_path","")); var environment:=ResourceLoader.load(environment_path) as KiwiEnvironmentDocument if not environment_path.is_empty() and ResourceLoader.exists(environment_path) else null
		if ProjectSettings.globalize_path(environment_path).replace("\\","/").simplify_path()==identity or (environment!=null and environment.references_asset(path)): signature=""; mark_dirty(); return
	for prototype: Dictionary in prototypes.values():
		for item: Dictionary in prototype.geometry.meshes:
			var actor: ActorData=_model.actor_for_id(str(item.actor_id))
			if actor==null: continue
			var source: Variant=actor.values.get(&"mesh_path","")
			var source_path: String=source.resource_path if source is Resource else str(source)
			if not source_path.is_empty() and ProjectSettings.globalize_path(source_path).replace("\\","/").simplify_path()==identity:
				signature=""; mark_dirty(); return
func dispose(keep_prepared: bool=false) -> void:
	restore_visuals()
	for prototype: Dictionary in prototypes.values():
		if is_instance_valid(prototype.get("rope_node")): prototype.rope_node.free()
	vfx.reset(); debris.reset(); structure.reset(); destruction.reset(keep_prepared); world.reset(); fluid.reset(); powder.reset(); prototypes.clear(); states.clear(); checkpoints.clear(); display_states.clear(); base_display_states.clear(); signature = ""; dirty = true; pending = false; requested_time = NAN
func restore_visuals() -> void:
	destruction.hide()
	for id: String in prototypes:
		var fog_runtime:=_runtime(id)
		if fog_runtime!=null and prototypes[id].actor.type_id==&"fog_volume": preload("res://scripts/actors/fog/fog_motion_render.gd").clear(fog_runtime)
	for id: String in prototypes:
		if not prototypes[id].has("growth"): continue
		var runtime:=_runtime(id)
		if runtime==null: continue
		for node: Node in runtime.find_children("*","MeshInstance3D",true,false):
			if node is KiwiSurfaceGrowthInstance: node.data.motion_guides.clear(); node.data.motion_weights.clear(); node.update_growth()
	for prototype: Dictionary in prototypes.values():
		for item: Dictionary in prototype.geometry.meshes:
			if not is_instance_valid(item.node): continue
			if item.node.mesh!=null and item.node.mesh.get_meta("kiwi_physics_mesh",false): item.node.mesh=item.original; item.node.skin=item.skin
			if item.node.get_meta("kiwi_physics_hidden",false): item.node.visible=item.visible; item.node.remove_meta("kiwi_physics_hidden")
		if is_instance_valid(prototype.get("rope_node")): prototype.rope_node.hide()
func _runtime(actor_id: String) -> ActorRuntime:
	var clip: ActorClip = _model.clip_for_actor_id(actor_id)
	var runtime: Variant = _runtimes.get(clip.id) if clip != null else null
	return runtime if is_instance_valid(runtime) else null
func _local(actor: ActorData, time: float) -> float:
	var clip: ActorClip = _model.clip_for_actor_id(actor.id)
	return clip.local_time(time) if clip != null else time
func animated_world(actor_id: String, time: float, simulated_parent: bool = false, visited: Dictionary = {}) -> Transform3D:
	var actor: ActorData = _model.actor_for_id(actor_id)
	if actor == null or visited.has(actor_id): return Transform3D.IDENTITY
	if not actor.values.get(&"position") is Vector3: return Transform3D.IDENTITY
	visited = visited.duplicate(); visited[actor_id] = true
	var local_time := _local(actor,time)
	var position: Vector3 = ActorAnimation.sampled_value(actor,PackedStringArray(["position"]),local_time,actor.values.get(&"position",Vector3.ZERO))
	var rotation: Vector3 = ActorAnimation.sampled_value(actor,PackedStringArray(["rotation"]),local_time,actor.values.get(&"rotation",Vector3.ZERO))
	var scale: Vector3 = ActorAnimation.sampled_value(actor,PackedStringArray(["scale"]),local_time,actor.values.get(&"scale",Vector3.ONE))
	var local := Transform3D(Basis.from_euler(rotation * PI / 180.0) * Basis.from_scale(scale) * actor.values.get(&"model_basis_residual",Basis.IDENTITY),position)
	var result:=local
	if not actor.parent_id.is_empty():
		var parent_world:=animated_world(actor.parent_id,time,simulated_parent,visited)
		if simulated_parent and states.has(actor.parent_id) and states[actor.parent_id].initialized:
			var parent: ActorData=_model.actor_for_id(actor.parent_id)
			var weight:=float(KiwiPhysicsSettings.sample(parent,_local(parent,time)).influence) if parent!=null else 1.0
			parent_world=parent_world.interpolate_with(states[actor.parent_id].pose,clampf(weight,0,1))
		result=parent_world*local
	for remote: ActorData in _model.actors:
		if remote.type_id!=&"remote_transform" or remote.id==actor_id or visited.has(remote.id): continue
		var clip: ActorClip=_model.clip_for_actor_id(remote.id)
		if clip==null or not clip.contains_time(time): continue
		var values:=ActorAnimation.sampled_values(remote,_local(remote,time))
		if str(values.get(&"remote_actor",""))!=actor_id: continue
		var source:=animated_world(remote.id,time,simulated_parent,visited)
		if values.get(&"set_position",true): result.origin=source.origin
		var orientation: Basis=source.basis.orthonormalized() if values.get(&"set_rotation",true) else result.basis.orthonormalized()
		result.basis=orientation*Basis.from_scale(source.basis.get_scale() if values.get(&"set_scale",true) else result.basis.get_scale())
	return result
func bone_world(actor_id: String, bone_name: String, time: float) -> Transform3D:
	var actor: ActorData = _model.actor_for_id(actor_id)
	if actor == null: return Transform3D.IDENTITY
	var result := animated_world(actor_id,time,true)
	if bone_name.is_empty(): return result
	var bones: Array = actor.values.get(&"rig_bones",[]); var index := -1
	for i in bones.size():
		if str(bones[i].name) == bone_name: index = i; break
	if index < 0:
		_warn(actor.display_name+": missing attachment bone "+bone_name); return result
	var physical: Dictionary=states.get(actor_id,{}).get("bones",{}).get(bone_name,{})
	var chain := []; var visited := {}
	while index >= 0 and index < bones.size() and not visited.has(index):
		visited[index] = true; chain.push_front(index); index = int(bones[index].parent)
	for i: int in chain:
		var bone: Dictionary = bones[i]; var path := PackedStringArray(["bone_poses",str(i)])
		var authored: Dictionary=actor.values.get(&"bone_poses",{}).get(str(i),bone)
		var position: Vector3 = ActorAnimation.sampled_value(actor,path+PackedStringArray(["position"]),_local(actor,time),authored.get("position",Vector3.ZERO))
		var rotation: Vector3 = ActorAnimation.sampled_value(actor,path+PackedStringArray(["rotation"]),_local(actor,time),authored.get("rotation",Vector3.ZERO))
		var scale: Vector3 = ActorAnimation.sampled_value(actor,path+PackedStringArray(["scale"]),_local(actor,time),authored.get("scale",Vector3.ONE))
		# Godot 4 bone poses are complete parent-local transforms, not deltas
		# multiplied by rest (doing both doubles every imported joint offset).
		result *= Transform3D(Basis.from_euler(rotation*PI/180.0)*Basis.from_scale(scale),position)
	if not physical.is_empty():
		var config:=KiwiPhysicsSettings.sample(actor,_local(actor,time)); var bone_config: Dictionary=config.bone_settings.get(bone_name,{})
		if bone_config.get("enabled",true): result=result.interpolate_with(physical.pose,clampf(float(config.influence)*float(bone_config.get("influence",1.0)),0,1))
	return result
func attachment(actor_id: String, bone: String, offset: Vector3, time: float, fallback: Transform3D) -> Vector3:
	if actor_id.is_empty(): return fallback * offset
	if _model.actor_for_id(actor_id) == null:
		_warn("Missing attachment actor: " + actor_id); return fallback * offset
	return bone_world(actor_id,bone,time) * offset
func source_transform(actor_id: String,config: Dictionary,time: float) -> Transform3D:
	var pose:=animated_world(actor_id,time,true)
	if not str(config.attachment).is_empty():
		if _model.actor_for_id(str(config.attachment))!=null: pose=bone_world(str(config.attachment),str(config.attachment_bone),time)
		else: _warn("Missing source attachment actor: "+str(config.attachment))
	pose.origin+=pose.basis*config.pivot
	return pose
func _warn(message: String) -> void:
	if not _warnings.has(message): _warnings.append(message)
func _setup(model: RefCounted, runtimes: Dictionary, new_signature: String) -> void:
	dispose(true); _model = model; _runtimes = runtimes; signature = new_signature; generation += 1; _warnings.clear(); rate = 30; origin = 0.0
	var ids := {}
	for actor: ActorData in model.actors:
		if KiwiPhysicsSettings.configured(actor): ids[actor.id] = true
	if ids.is_empty(): dirty = false; return
	world.create()
	for actor: ActorData in model.actors:
		if not ids.has(actor.id): continue
		var runtime := _runtime(actor.id); var clip: ActorClip = model.clip_for_actor_id(actor.id)
		if runtime == null or clip == null or not runtime.supports_remote_transform(): continue
		if absf(runtime.remote_transform().basis.determinant())<.00000001: _warn(actor.display_name+": physics needs a nonzero scale on every axis."); continue
		var config := KiwiPhysicsSettings.authored(actor); rate = maxi(rate,clampi(int(config.steps),30,240))
		origin = minf(origin,clip.start_time-clip.source_offset/maxf(.001,clip.playback_speed))
		var geometry: Dictionary={"meshes":[],"points":PackedVector3Array(),"bounds":AABB(-Vector3.ONE*.5,Vector3.ONE)} if actor.type_id in [&"powder",&"fluid"] or int(config.type) in [8,9] else KiwiPhysicsGeometry.capture(runtime,ids)
		prototypes[actor.id] = {"actor":actor,"clip":clip,"geometry":geometry,"graph":{},"graph_key":"","rope_node":null}
		if int(config.type)==9: continue
		var activation_time:=clip.start_time+(float(config.activation)-clip.source_offset)/maxf(.001,clip.playback_speed)
		var collision_geometry:=_simulation_geometry(actor.id,{"initial_time":activation_time,"initial_pose":animated_world(actor.id,activation_time)})
		var collider_settings := config.duplicate()
		if int(config.shape) == 0 and actor.type_id == &"basic_shape":
			collider_settings.shape = {1:2,2:4,3:3}.get(int(actor.values.get(&"shape",0)),1)
		if int(config.shape) == 6 and int(config.body_mode) != 1 and not collision_geometry.has("compound_points"): _warn(actor.display_name+": concave mesh collision is static-only; using a box.")
		var collider := KiwiPhysicsGeometry.collider(collision_geometry,collider_settings)
		if not str(collider.get("error","")).is_empty(): _warn(actor.display_name+": "+str(collider.error))
		if collider.has("compound"): world.add_compound(actor.id,collider.compound,int(config.layer),int(config.mask))
		else: world.add(actor.id,collider.shape,collider.offset,int(config.layer),int(config.mask))
	var order:=prototypes.keys(); order.sort_custom(func(a: String,b: String): return _depth(a)<_depth(b))
	var sorted:={}
	for id: String in order: sorted[id]=prototypes[id]
	prototypes=sorted
	step = 0; states.clear()
	for id: String in prototypes:
		states[id] = {"pose":animated_world(id,origin),"v":Vector3.ZERO,"w":Vector3.ZERO,"initialized":false,"active":false,"type":-1,"points":PackedVector3Array(),"velocities":PackedVector3Array(),"bones":{},"sleep":0.0,"initial_time":origin,"initial_pose":animated_world(id,origin)}
	for id: String in prototypes:
		var config:=KiwiPhysicsSettings.authored(prototypes[id].actor); var clip: ActorClip=prototypes[id].clip
		world.place(id,states[id].pose,bool(config.enabled) and bool(config.collision) and int(config.type) in [0,2] and clip.contains_time(origin))
	for id: String in prototypes:
		var config := KiwiPhysicsSettings.sample(prototypes[id].actor,_local(prototypes[id].actor,origin))
		var clip: ActorClip = prototypes[id].clip
		if config.enabled and origin>=clip.start_time-clip.source_offset/maxf(.001,clip.playback_speed)-.000001 and _local(prototypes[id].actor,origin)>=float(config.activation)-.000001 and int(config.mode)!=0:
			_initialize(id,states[id],config,origin); states[id].active = true
			if int(config.mode)==3 and not is_baking(id) and config.frozen.get("state") is Dictionary: states[id]=_snapshot({id:config.frozen.state})[id]
			if int(config.mode)==4 and not is_baking(id):
				var baked := _baked(config.bake,origin)
				if not baked.is_empty(): baked.responds=false; states[id]=baked
	destruction.step(self,origin,0)
	structure.step(self,origin,0)
	checkpoints[0] = _snapshot(states); _floor_step = -1; dirty = false
func _snapshot(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	for state: Dictionary in result.values():
		if state.has("powder_ids") and not state.has("powder_phase"):
			state.powder_phase=PackedByteArray(); state.powder_phase.resize(state.powder_ids.size()); state.powder_settle=PackedFloat32Array(); state.powder_settle.resize(state.powder_ids.size()); state.powder_deposits={}; state.powder_cells={}; state.powder_supports={}; state.powder_releases=0
		for key in ["points","velocities","fluid_ids","fluid_masses","fluid_foam","fluid_density","fog_density","fog_velocity","fog_solid","fog_boundary_velocity","fog_pressure"]:
			if state.has(key): state[key] = state[key].duplicate()
		for key in KiwiPowderSource.ARRAYS:
			if state.has(key): state[key]=state[key].duplicate()
	return result
func _depth(id: String) -> int:
	var depth:=0; var seen:={}; var actor: ActorData=_model.actor_for_id(id)
	while actor!=null and not actor.parent_id.is_empty() and not seen.has(actor.id):
		seen[actor.id]=true; depth+=1; actor=_model.actor_for_id(actor.parent_id)
	return depth
func _cache() -> void:
	if step % 30 != 0: return
	checkpoints[step] = _snapshot(states)
	var points := 0
	var bonds:=0
	var debris_bytes:=0
	for state: Dictionary in states.values(): points += state.points.size() + state.bones.size(); bonds+=(state.get("powder_bonds",{}) as Dictionary).size()+(state.get("structural",{}).get("links",{}) as Dictionary).size()
	for state: Dictionary in states.values(): debris_bytes+=state.get("destruction_events",[]).size()*2048+state.get("destruction_fragments",[]).size()*2048+state.get("debris_recent",{}).size()*128
	for state: Dictionary in states.values(): debris_bytes+=state.get("fog_density",PackedFloat32Array()).size()*40
	var estimate:=maxi(1,prototypes.size()*512+points*128+bonds*512+debris_bytes)
	var limit := mini(MAX_CHECKPOINTS,maxi(1,int(MAX_CACHE_BYTES/estimate)))
	while checkpoints.size() > limit:
		var keys := checkpoints.keys(); keys.sort(); checkpoints.erase(keys[1])
func evaluate(model: RefCounted, runtimes: Dictionary, time: float, budget: int = SEEK_BUDGET) -> void:
	_model = model; _runtimes = runtimes
	var needs_geometry:=false
	for actor: ActorData in model.actors:
		if KiwiPhysicsSettings.configured(actor): needs_geometry=true; break
	for runtime: Variant in runtimes.values():
		if not is_instance_valid(runtime): continue
		if runtime.has_method("physics_geometry_error"):
			var geometry_error:=str(runtime.call("physics_geometry_error"))
			if not geometry_error.is_empty(): pending=false; status="Environment geometry failed: "+geometry_error; status_changed.emit(status); return
		if runtime.has_method("physics_geometry_ready") and not bool(runtime.call("physics_geometry_ready",needs_geometry)): pending=true; status="Preparing environment geometry"; status_changed.emit(status); return
	if dirty:
		var next_signature := KiwiPhysicsSettings.fingerprint(model)
		if next_signature != signature: _setup(model,runtimes,next_signature)
		dirty = false
	if prototypes.is_empty(): pending = false; status = " · ".join(_warnings); status_changed.emit(status); return
	var exact := maxf(0.0,(time-origin)*rate); var target := int(floor(exact+.0000001)); var fraction := exact-target
	var goal := target+(1 if fraction>.000001 else 0)
	if not is_equal_approx(requested_time,time) or is_nan(requested_time):
		requested_time = time
		if step > target:
			var checkpoint := 0
			for index: int in checkpoints:
				if index <= target: checkpoint = maxi(checkpoint,index)
			states = _snapshot(checkpoints[checkpoint]); step = checkpoint; _floor_step = -1
	if step == target: _floor_states = _snapshot(states); _floor_step = target
	var count := 0
	var deadline:=Time.get_ticks_usec()+12000
	while step < goal and count < budget and (count==0 or Time.get_ticks_usec()<deadline):
		_step(origin+float(step+1)/rate,1.0/rate); step += 1; count += 1; steps_taken += 1; _cache()
		if step == target: _floor_states = _snapshot(states); _floor_step = target
	pending = step < goal
	if not pending:
		display_states = _snapshot(states)
		if fraction > .000001 and _floor_step == target:
			for id: String in display_states:
				var value: Dictionary = display_states[id]; var left: Dictionary = _floor_states[id]
				value.pose = left.pose.interpolate_with(value.pose,fraction)
				_interpolate_points(value,left,value.duplicate(true),fraction)
				for bone in value.bones:
					if left.bones.has(bone): value.bones[bone].pose = left.bones[bone].pose.interpolate_with(value.bones[bone].pose,fraction)
		_applied_time = time
		base_display_states=_snapshot(display_states)
	status = "Preparing physics %.2f / %.2f s" % [origin+float(step)/rate,time] if pending else " · ".join(_warnings)
	status_changed.emit(status)
	_apply(time)
func _initialize(id: String, state: Dictionary, config: Dictionary, time: float) -> void:
	var prototype: Dictionary = prototypes[id]; var actor: ActorData = prototype.actor
	state.pose = animated_world(id,time,true); state.initial_pose = state.pose; state.initial_time = time; state.initialized = true; state.type = int(config.type); state.sleep = 0.0
	state.v = config.velocity
	state.v += _events(config,_local(actor,time),.0000001).impulse/maxf(.001,float(config.mass))
	if config.inherit_velocity: state.v += (animated_world(id,time).origin-animated_world(id,time-1.0/rate).origin)*rate
	state.w = (config.angular_velocity as Vector3)*PI/180.0; state.bones = {}; state.points = PackedVector3Array(); state.velocities = PackedVector3Array()
	state.attachment_basis=bone_world(str(config.attachment),str(config.attachment_bone),time).basis.inverse()*state.pose.basis if not str(config.attachment).is_empty() else Basis.IDENTITY
	if int(config.type) in [1,4]:
		_ensure_graph(id,state,config)
		if not prototype.graph.error.is_empty(): _warn(actor.display_name+": "+str(prototype.graph.error)); return
		state.points = prototype.graph.rest.duplicate(); state.velocities.resize(state.points.size()); state.velocities.fill(state.v)
	if int(config.type) == 5:
		var points := PackedVector3Array(); var start: Vector3 = state.pose.origin
		var end := attachment(str(config.end_actor),str(config.end_bone),config.end_offset,time,state.pose*Transform3D(Basis.IDENTITY,Vector3(0,-float(config.rope_length),0)))
		if str(config.end_actor).is_empty(): end = state.pose * Vector3(0,-float(config.rope_length),0)
		var n := clampi(int(config.rope_points),3,96)
		for i in n: points.append(start.lerp(end,float(i)/(n-1)))
		state.points = points; state.velocities.resize(n); state.velocities.fill(state.v)
		var edges := []
		for i in n-1: edges.append([i,i+1,float(config.rope_length)/(n-1),false])
		prototype.graph = {"rest":points.duplicate(),"local":PackedVector3Array(),"edges":edges,"error":"","bindings":[]}
		prototype.graph_key = str(state.initial_time)+":5"
	if int(config.type) == 3:
		var bones: Array = actor.values.get(&"rig_bones",[])
		if bones.is_empty(): _warn(actor.display_name+": Skeleton physics needs a Skeleton Rig actor.")
		for name: String in config.bones:
			if not bones.any(func(bone: Dictionary): return str(bone.name)==name): _warn(actor.display_name+": missing bone "+name)
		for index in bones.size():
			var name:=str(bones[index].name)
			if not config.bones.has(name): continue
			var pose := bone_world(id,name,time); var length := .3; var axis := Vector3.UP
			for child: Dictionary in bones:
				if int(child.parent) == index and child.rest.origin.length() > .001: length = child.rest.origin.length(); axis = child.rest.origin.normalized(); break
			state.bones[name] = {"pose":pose,"point":pose*(axis*length),"v":state.v,"axis":axis,"length":length,"index":index,"anchor":pose.origin,"root_v":state.v}
	if int(config.type)==6: KiwiFluidBridge.initialize(self,id,state,config,time)
	if int(config.type)==7: powder.initialize(self,id,state,config,time)
	if int(config.type)==8: KiwiGrowthPhysics.initialize(self,id,state,config,time)
	if int(config.type)==9: FogMotion.initialize(self,id,state,config,time)
func _simulation_geometry(id: String, state: Dictionary, captured: Dictionary={}) -> Dictionary:
	# Skinning is evaluated at activation, not at the frame where a cache happened
	# to be rebuilt. The captured bind mesh stays intact for disabling/rewinding.
	var source: Dictionary = prototypes[id].geometry if captured.is_empty() else captured
	var geometry := {"meshes":[],"points":PackedVector3Array(),"bounds":source.bounds}
	for original: Dictionary in source.meshes:
		var item := original.duplicate(); item.surfaces = []
		var owner: ActorData = _model.actor_for_id(str(item.actor_id))
		var mesh_world: Transform3D = animated_world(str(item.actor_id),state.initial_time,true)*item.owner_local
		var rig_id := str(owner.values.get(&"model_skeleton_actor","")) if owner != null else ""
		var rig: ActorData = _model.actor_for_id(rig_id)
		if owner != null and owner.values.get(&"model_skin_in_rig_space",false) and rig != null: mesh_world = animated_world(rig_id,state.initial_time,true)
		item.local = state.initial_pose.affine_inverse()*mesh_world
		var matrices := []
		if item.skin != null and rig != null:
			var bones: Array = rig.values.get(&"rig_bones",[])
			var rig_inverse := animated_world(rig_id,state.initial_time,true).affine_inverse()
			for i in item.skin.get_bind_count():
				var bone_index: int = item.skin.get_bind_bone(i); var name: String = str(item.skin.get_bind_name(i))
				if name.is_empty() and bone_index >= 0 and bone_index < bones.size(): name = str(bones[bone_index].name)
				matrices.append(rig_inverse*bone_world(rig_id,name,state.initial_time)*item.skin.get_bind_pose(i))
		elif item.skin != null:
			_warn(id+": missing skin armature; using the mesh's bind pose.")
		var surfaces: Array=original.surfaces
		if original.primitive and owner!=null:
			var mesh:=KiwiPhysicsGeometry.primitive(_runtime(owner.id),ActorAnimation.sampled_values(owner,_local(owner,state.initial_time)))
			surfaces=[]
			for surface in mesh.get_surface_count(): surfaces.append(mesh.surface_get_arrays(surface))
		for arrays: Array in surfaces:
			var data := arrays.duplicate(true); var vertices: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
			if not matrices.is_empty() and data[Mesh.ARRAY_BONES] != null and data[Mesh.ARRAY_WEIGHTS] != null:
				var indices: PackedInt32Array = data[Mesh.ARRAY_BONES]; var weights: PackedFloat32Array = data[Mesh.ARRAY_WEIGHTS]
				var influences := indices.size()/maxi(1,vertices.size())
				for vertex in vertices.size():
					var position := Vector3.ZERO; var total := 0.0
					for slot in influences:
						var index: int = indices[vertex*influences+slot]; var weight: float = weights[vertex*influences+slot]
						if index>=0 and index<matrices.size(): position += (matrices[index]*vertices[vertex])*weight; total+=weight
					if total>.00001: vertices[vertex]=position/total
			data[Mesh.ARRAY_VERTEX]=vertices; item.surfaces.append(data)
			for vertex in vertices: geometry.points.append(item.local*vertex)
		geometry.meshes.append(item)
	if not geometry.points.is_empty():
		var bounds:=AABB(geometry.points[0],Vector3.ZERO)
		for p in geometry.points: bounds=bounds.expand(p)
		geometry.bounds=bounds
	return KiwiPhysicsGeometry.prepare_collision(geometry)
func _ensure_graph(id: String, state: Dictionary, config: Dictionary) -> void:
	var prototype: Dictionary = prototypes[id]
	var key := str(state.initial_time)+":"+str(state.type)
	if prototype.graph_key==key and not prototype.graph.is_empty(): return
	prototype.graph = KiwiPhysicsGeometry.particles(_simulation_geometry(id,state),int(config.particles),state.initial_pose)
	prototype.graph_key=key
func _step(time: float, dt: float) -> void:
	fluid.prepare_environment(self,time)
	destruction.synchronize(self,time-dt)
	debris.refresh(self,time)
	var configs := {}; var targets := {}; var fluid_steps:={}; var powder_steps:={}; var fog_steps:={}; var old_poses:={}
	for id: String in states:
		old_poses[id]=states[id].pose; states[id].destruction_impacts=states[id].get("structure_pending_impacts",[]); states[id].structure_pending_impacts=[]; states[id].structure_contacts=[]
	for id: String in prototypes:
		var p: Dictionary = prototypes[id]; var state: Dictionary = states[id]; var actor: ActorData = p.actor
		var config := KiwiPhysicsSettings.sample(actor,_local(actor,time)); config.environment_wind=_environment_wind(actor,time); configs[id] = config; targets[id] = animated_world(id,time,true)
		if int(config.type)==7: config.wind=(config.wind as Vector3)+config.environment_wind
		if actor.values.get(&"destruction_enabled",false): config.mass=destruction.mass(self,id,state,ActorAnimation.sampled_values(actor,_local(actor,time)),float(config.mass))
		if absf(targets[id].basis.determinant())>.00000001 and state.initialized:
			state.pose.basis=state.pose.basis.orthonormalized()*Basis.from_scale(targets[id].basis.get_scale())
		if is_baking(id) and int(config.mode) in [3,4]: config.mode=int(config.bake.get("source_mode",1))
		var local_time := _local(actor,time); var virtual_start: float = p.clip.start_time-p.clip.source_offset/maxf(.001,p.clip.playback_speed)
		var enabled: bool = config.enabled and time>=virtual_start-.000001 and time<p.clip.start_time+p.clip.duration and local_time>=float(config.activation)-.000001
		state.active = enabled
		if not enabled or int(config.mode) == 0:
			state.v=(targets[id].origin-state.pose.origin)/maxf(.00001,dt*p.clip.playback_speed) if enabled else Vector3.ZERO
			state.pose = targets[id]; state.initialized = false
		elif not state.initialized or state.type != int(config.type):
			_initialize(id,state,config,time)
		if enabled and int(config.type) in [0,2] and int(config.body_mode) in [1,2] and int(config.mode) in [1,2]:
			state.v=(targets[id].origin-state.pose.origin)/maxf(.00001,dt*p.clip.playback_speed) if int(config.body_mode)==2 else Vector3.ZERO
			state.pose=targets[id]
		state.responds=enabled and int(config.type) in [0,2] and int(config.body_mode)==0 and int(config.mode) in [1,2] and (float(config.end)<0 or local_time<float(config.end))
		world.place(id,state.pose,bool(config.collision) and enabled and int(config.type) in [0,2] and not state.get("destruction_detached",false))
	for id: String in prototypes:
		var state: Dictionary = states[id]; var config: Dictionary = configs[id]; var prototype: Dictionary = prototypes[id]
		if not state.active or int(config.mode) == 0: continue
		if int(config.mode) == 3:
			if config.frozen.get("state") is Dictionary: states[id] = _snapshot({id:config.frozen.state})[id]
			continue
		if int(config.mode) == 4:
			var baked := _baked(config.bake,time)
			if not baked.is_empty(): baked.responds=false; states[id] = baked; continue
			_warn(prototype.actor.display_name+": bake is stale or outside its interval; using live replay.")
			config.mode=int(config.bake.get("source_mode",1)); state.responds=int(config.body_mode)==0 and int(config.type) in [0,2]
		if float(config.end) >= 0.0 and _local(prototype.actor,time) >= float(config.end): continue
		if state.get("destruction_detached",false): continue
		if int(config.type) in [0,2] and int(config.body_mode) in [1,2]: continue
		var h := dt*maxf(.001,prototype.clip.playback_speed)
		if is_equal_approx(float(state.initial_time),time): h = 0.0
		if h<=0.0: continue
		match int(config.type):
			0,2: _rigid(id,state,config,targets[id],time,h)
			1,4,5: _particles(id,state,config,time,h)
			3: _skeleton(id,state,config,time,h)
			6: fluid_steps[id]=h
			7: powder.step(self,id,state,config,time,h); powder_steps[id]=h
			8:
				state.pose=KiwiGrowthPhysics.world(self,id,time)
				_particles(id,state,config,time,h)
			9: fog_steps[id]=h
	for id: String in prototypes: world.place(id,states[id].pose,bool(configs[id].collision) and states[id].active and int(configs[id].type) in [0,2] and not states[id].get("destruction_detached",false))
	destruction.step(self,time,dt)
	structure.step(self,time,dt)
	if not fluid_steps.is_empty() or not fog_steps.is_empty():
		fluid.update_proxies(self,time)
		for id: String in fluid_steps:
			fluid.step(self,id,states[id],configs[id],time,float(fluid_steps[id]))
			if not states[id].fluid_contacts.is_empty(): fluid_contacts.emit(id,time,states[id].fluid_contacts)
	if not powder_steps.is_empty(): powder.simulate(self,powder_steps,time,dt,old_poses)
	for id: String in fog_steps: FogMotion.step(self,id,states[id],configs[id],time,float(fog_steps[id]))
func _gravity(config: Dictionary) -> Vector3:
	return (config.gravity_direction as Vector3).normalized()*float(config.gravity)

func _environment_wind(actor: ActorData,time: float) -> Vector3:
	if actor==null: return Vector3.ZERO
	var world_position:=animated_world(actor.id,time,true).origin
	for environment_actor: ActorData in _model.actors:
		if environment_actor.type_id!=&"environment_asset": continue
		var clip: ActorClip=_model.clip_for_actor_id(environment_actor.id)
		if clip==null or not clip.contains_time(time): continue
		var runtime:=_runtime(environment_actor.id)
		if runtime==null or not runtime.has_method("environment_at"): continue
		var values:=ActorAnimation.sampled_values(environment_actor,_local(environment_actor,time))
		var overrides: Dictionary={"climate_time":float(values.get(&"climate_time",-1.)),"climate_weather":int(values.get(&"climate_weather",0)),"climate_intensity":float(values.get(&"climate_intensity",-1.)),"climate_clouds":float(values.get(&"climate_clouds",-1.)),"climate_temperature_offset":float(values.get(&"climate_temperature_offset",0.)),"climate_wind_add":values.get(&"climate_wind_add",Vector3.ZERO)}
		var state: Dictionary=runtime.call("environment_at",world_position,time,overrides)
		return state.get("wind_velocity",Vector3.ZERO) as Vector3
	return Vector3.ZERO
func _events(config: Dictionary, local: float, h: float) -> Dictionary:
	var impulse:=Vector3.ZERO; var force:=Vector3.ZERO
	for event: Dictionary in config.forces:
		var at:=float(event.get("time",0))
		if local-h<at and local>=at: impulse+=event.get("impulse",Vector3.ZERO)
		if local>=at and local<at+float(event.get("duration",0)): force+=event.get("force",Vector3.ZERO)
	return {"impulse":impulse,"force":force}
func _rigid(id: String, state: Dictionary, config: Dictionary, target: Transform3D, time: float, h: float) -> void:
	if int(config.body_mode) in [1,2]: state.v = (target.origin-state.pose.origin)/maxf(.00001,h); state.pose = target; return
	var joint_frame: Basis=bone_world(str(config.attachment),str(config.attachment_bone),time).basis if not str(config.attachment).is_empty() else target.basis
	var rest_basis: Basis=joint_frame*state.get("attachment_basis",Basis.IDENTITY) if not str(config.attachment).is_empty() else target.basis
	var mass := maxf(.001,float(config.mass)); var environment_wind: Vector3=config.environment_wind; var acceleration: Vector3=_gravity(config)
	if not environment_wind.is_zero_approx(): acceleration+=(environment_wind-state.v)*.12
	acceleration+=fluid.rigid_water_acceleration(self,id,state,config,h)
	if int(config.type) == 2 or int(config.mode) == 2:
		var anchor := attachment(str(config.attachment),str(config.attachment_bone),config.pivot,time,target)
		if not config.ragdoll: acceleration += (anchor-state.pose.origin)*float(config.stiffness)/mass
		if not config.ragdoll:
			var error: Quaternion=rest_basis.get_rotation_quaternion()*state.pose.basis.get_rotation_quaternion().inverse()
			var angle:=wrapf(error.get_angle(),-PI,PI)
			if absf(angle)>.00001: state.w+=error.get_axis()*angle*float(config.stiffness)*h/mass
	var events:=_events(config,_local(prototypes[id].actor,time),h)
	if state.sleep>.5 and int(config.type)==0 and events.impulse.is_zero_approx() and events.force.is_zero_approx():
		var wake:=not target.is_equal_approx(state.get("last_target",target))
		for other_id in states:
			if other_id!=id and states[other_id].v.length()>.08: wake=true; break
		if not wake: state.v=Vector3.ZERO; state.w=Vector3.ZERO; return
	state.last_target=target
	state.v+=events.impulse/mass; acceleration+=events.force/mass
	if int(config.type)==2 and config.ragdoll and int(config.constraint)==4:
		var anchor:=attachment(str(config.attachment),str(config.attachment_bone),config.pivot,time,target)
		var difference: Vector3=state.pose.origin-anchor
		acceleration-=difference.normalized()*(difference.length()-float(config.distance))*float(config.stiffness)/mass
	if int(config.type)==2 and config.ragdoll and int(config.constraint)==1:
		var lever: Vector3=state.pose.basis*(prototypes[id].geometry.bounds.get_center()-config.body_pivot)
		state.w+=lever.cross(_gravity(config))*h
	var motion: Vector3 = state.v*h+acceleration*(h*h*.5)
	state.v = (state.v+acceleration*h)*exp(-maxf(0,float(config.damping))*h)
	state.w *= exp(-maxf(0,float(config.angular_damping))*h)
	if state.w.length() > .00001: state.pose.basis = Basis(Quaternion(state.w.normalized(),state.w.length()*h))*state.pose.basis
	if config.collision:
		var excluded: Array[String] = [str(prototypes[id].actor.parent_id),str(config.attachment)]
		if prototypes[id].actor.get_value(&"structure_enabled",false): excluded.erase(str(prototypes[id].actor.parent_id))
		excluded.append_array(structure.exclusions(self,id,time))
		var collision := world.move(id,state.pose,motion,excluded)
		state.structure_contacts=collision.hits
		state.pose.origin += collision.travel
		for hit: Dictionary in collision.hits:
			var normal: Vector3 = hit.normal; var other: Dictionary = debris.lookup(self,str(hit.actor))
			var other_config := debris.settings(self,str(hit.actor),time)
			var inv_other := 1.0/maxf(.001,float(other_config.mass)) if not other.is_empty() and other.get("responds",false) else 0.0
			var source_speed:=maxf(.001,prototypes[id].clip.playback_speed)
			var other_speed:=maxf(.001,prototypes[hit.actor].clip.playback_speed) if prototypes.has(hit.actor) else 1.0
			var relative: Vector3 = state.v*source_speed-(other.get("v",Vector3.ZERO) as Vector3)*other_speed; var speed := relative.dot(normal)
			if speed < 0.0:
				var impact:={"point":hit.point,"normal":normal,"energy":.5*speed*speed/(1.0/mass+inv_other)}
				if speed<-.5 and prototypes[id].actor.get_value(&"destruction_enabled",false): debris.emit(self,id,id+":"+str(hit.actor),"impact",time,hit.point,normal,relative,float(impact.energy))
				if not state.has("destruction_impacts"): state.destruction_impacts=[]
				state.destruction_impacts.append(impact)
				if not other.is_empty():
					if not other.has("destruction_impacts"): other.destruction_impacts=[]
					other.destruction_impacts.append({"point":hit.point,"normal":-normal,"energy":impact.energy})
				var impulse := -(1.0+(float(config.bounce) if speed<-.3 else 0.0))*speed/(1.0/mass+inv_other)
				state.v += normal*impulse/(mass*source_speed)
				if inv_other > 0: other.v -= normal*impulse*inv_other/other_speed
				var tangent := relative-normal*speed
				if tangent.length()>1 and absf(speed)<.5 and prototypes[id].actor.get_value(&"destruction_enabled",false): debris.emit(self,id,id+":"+str(hit.actor),"scrape",time,hit.point,normal,tangent,.5*mass*tangent.length_squared())
				if tangent.length()>.0001: state.v -= tangent.normalized()*minf(tangent.length(),float(config.friction)*impulse/mass)/source_speed
				# A bounded isotropic inertia approximation, not a full inertia tensor.
				var arm: Vector3 = hit.point-state.pose.origin; state.w += arm.cross(normal*impulse)*.1/maxf(.01,mass)
				state.w = state.w.limit_length(30.0)
		state.sleep = state.sleep+h if not collision.hits.is_empty() and state.v.length()<.08 else 0.0
		if not collision.hits.is_empty(): state.w*=exp(-maxf(0,float(config.friction))*h*8.0)
	else: state.pose.origin += motion
	if int(config.type) == 2:
		var anchor := attachment(str(config.attachment),str(config.attachment_bone),config.pivot,time,target)
		var displacement: Vector3 = state.pose.origin-anchor
		var joint:=int(config.constraint)
		var maximum := float(config.distance) if config.ragdoll else float(config.position_limit)
		if joint in [0,1] and config.ragdoll:
			state.pose.origin+=anchor-state.pose*config.body_pivot; state.v=Vector3.ZERO
		elif joint==2 and config.ragdoll:
			var joint_axis: Vector3=(joint_frame*config.axis).normalized()
			state.pose.origin=anchor+joint_axis*clampf(displacement.dot(joint_axis),-float(config.position_limit),float(config.position_limit))
			state.v=joint_axis*state.v.dot(joint_axis); state.pose.basis=rest_basis; state.w=Vector3.ZERO
		elif (displacement.length()>maximum and not (config.ragdoll and joint==4)) or (config.ragdoll and joint==3 and displacement.length()>.00001):
			state.pose.origin = anchor+displacement.limit_length(maximum)
			if config.ragdoll and joint==3: state.pose.origin=anchor+displacement.normalized()*maximum
			if displacement.length()>.0001: state.v -= displacement.normalized()*maxf(0,state.v.dot(displacement.normalized()))
		if config.ragdoll and joint in [0,1]:
			var relative: Quaternion=state.pose.basis.get_rotation_quaternion()*rest_basis.get_rotation_quaternion().inverse()
			var local_axis: Vector3=(config.axis as Vector3).normalized()
			if local_axis.length()<.001: local_axis=Vector3.UP
			var world_axis: Vector3=(joint_frame*local_axis).normalized()
			var angle:=2.0*atan2(Vector3(relative.x,relative.y,relative.z).dot(world_axis),relative.w)
			angle=clampf(wrapf(angle,-PI,PI),-deg_to_rad(float(config.limit)),deg_to_rad(float(config.limit)))
			state.pose.basis=Basis(world_axis,angle if joint==1 else 0.0)*rest_basis
			state.w=world_axis*state.w.dot(world_axis) if joint==1 else Vector3.ZERO
		var base := rest_basis.get_rotation_quaternion(); var q: Quaternion = state.pose.basis.get_rotation_quaternion(); var angle := base.angle_to(q)
		var limit := deg_to_rad(float(config.limit))
		if angle > limit and angle>.00001: state.pose.basis = Basis(base.slerp(q,limit/angle))*Basis.from_scale(state.pose.basis.get_scale())
		if config.ragdoll and joint in [0,1]: state.pose.origin=anchor-state.pose.basis*config.body_pivot
func _pin_positions(id: String, state: Dictionary, config: Dictionary, time: float) -> Dictionary:
	var pinned := {}; var target := animated_world(id,time,true); var graph: Dictionary = prototypes[id].graph
	if int(config.type)==8: return KiwiGrowthPhysics.pins(self,id,time)
	if int(config.type)==5:
		if config.rope_start: pinned[0] = attachment(str(config.attachment),str(config.attachment_bone),config.pivot,time,target)
		if config.rope_end: pinned[state.points.size()-1] = attachment(str(config.end_actor),str(config.end_bone),config.end_offset,time,target*Transform3D(Basis.IDENTITY,Vector3(0,-float(config.rope_length),0)))
	elif not graph.is_empty() and not graph.local.is_empty():
		var bounds: AABB = prototypes[id].geometry.bounds
		# Horizontal sheets have no Y extent; use their Z edge instead.
		var vertical := 1 if bounds.size.y>.0001 else 2
		for i in graph.local.size():
			var p: Vector3 = graph.local[i]; var region := int(config.pin_region)
			if (region==1 and p[vertical]>=bounds.end[vertical]-bounds.size[vertical]*.08) or (region==2 and p[vertical]<=bounds.position[vertical]+bounds.size[vertical]*.08) or (region==3 and p.x<=bounds.position.x+bounds.size.x*.08):
				pinned[i] = attachment(str(config.attachment),str(config.attachment_bone),p,time,target)
	for pin: Dictionary in config.pins:
		var index := int(pin.get("point",-1))
		if index<0 or index>=state.points.size(): _warn(prototypes[id].actor.display_name+": pinned point %d is outside this simulation mesh."%index)
		if index>=0 and index<state.points.size(): pinned[index] = attachment(str(pin.get("actor","")),str(pin.get("bone","")),pin.get("offset",Vector3.ZERO),time,target) if pin.get("follow",true) else pin.get("world",state.points[index])
	return pinned
func _particles(id: String, state: Dictionary, config: Dictionary, time: float, h: float) -> void:
	if state.points.is_empty(): return
	if int(config.type) not in [5,8]: _ensure_graph(id,state,config)
	var graph: Dictionary = prototypes[id].graph; var previous: PackedVector3Array = state.points.duplicate(); var pinned := _pin_positions(id,state,config,time)
	var acceleration := _gravity(config)+(config.wind as Vector3)/maxf(.01,float(config.mass))
	var events:=_events(config,_local(prototypes[id].actor,time),h); acceleration+=events.force/maxf(.001,float(config.mass))
	var growth_targets:=KiwiGrowthPhysics.targets(self,id,time) if int(config.type)==8 else {}
	for i in state.points.size():
		if pinned.has(i): state.points[i]=pinned[i]; continue
		state.velocities[i]+=events.impulse/maxf(.001,float(config.mass))
		if growth_targets.has(i): state.velocities[i]+=(growth_targets[i]-state.points[i])*(float(config.stiffness)/maxf(.001,float(config.mass)) if int(config.mode)==2 else float(config.recovery))*h
		var wind_acceleration:=Vector3.ZERO
		if not (config.environment_wind as Vector3).is_zero_approx(): wind_acceleration=((config.environment_wind as Vector3)-state.velocities[i])*.12
		state.velocities[i]=(state.velocities[i]+(acceleration+wind_acceleration)*h)*exp(-float(config.damping)*h)
		state.points[i]+=state.velocities[i]*h
	if int(config.type)==1:
		# Recover shape around the newly integrated center of mass. Using the
		# previous center accidentally acts as a brake on the entire falling body.
		var center:=Vector3.ZERO; var rest_center:=Vector3.ZERO
		for p in state.points: center+=p
		for p in graph.rest: rest_center+=p
		center/=state.points.size(); rest_center/=state.points.size()
		for i in state.points.size():
			if pinned.has(i): continue
			state.points[i]=state.points[i].lerp(center+(graph.rest[i]-rest_center),clampf(float(config.recovery)*h,0,.3))
	for iteration in clampi(int(config.iterations),1,24):
		for edge: Array in graph.edges:
			var a: int=edge[0]; var b: int=edge[1]; var difference: Vector3=state.points[b]-state.points[a]; var length:=difference.length()
			if length<.000001: continue
			var strength:=float(config.bend) if edge[3] else float(config.stretch)
			# Soft-body elasticity is a per-step resistance, not an almost-rigid
			# projection repeated eight times. Keep it independent of iterations.
			if int(config.type)==1: strength=1.0-pow(1.0-clampf(strength,0,1),1.0/clampi(int(config.iterations),1,24))
			var weight:=0.0 if pinned.has(a) and pinned.has(b) else (1.0 if pinned.has(a) or pinned.has(b) else .5)
			var correction:=difference*((length-float(edge[2]))/length)*clampf(strength,0,1)*weight
			if not pinned.has(a): state.points[a]+=correction
			if not pinned.has(b): state.points[b]-=correction
		for index in pinned: state.points[index]=pinned[index]
	for i in state.points.size():
		var contacts:=[]
		if config.collision and not pinned.has(i):
			var result:=world.point_motion(id,previous[i],state.points[i],float(config.radius),int(config.layer),int(config.mask),[str(config.attachment)])
			state.points[i]=result.position; contacts=result.hits
		state.velocities[i]=(state.points[i]-previous[i])/maxf(.00001,h)
		for hit: Dictionary in contacts:
			var normal: Vector3=hit.normal; var speed: float=state.velocities[i].dot(normal)
			state.velocities[i]-=normal*minf(speed,0.0)
			state.velocities[i]*=exp(-maxf(0,float(config.friction))*h*10.0)
func _skeleton(id: String, state: Dictionary, config: Dictionary, time: float, h: float) -> void:
	var bones: Array = prototypes[id].actor.values.get(&"rig_bones",[])
	var saved: Dictionary=state.bones; state.bones={}; var animated:={}
	for bone: Dictionary in bones: animated[str(bone.name)]=bone_world(id,str(bone.name),time)
	state.bones=saved
	for name: String in state.bones:
		var bone: Dictionary=state.bones[name]; var local_config:=config.duplicate(); local_config.merge(config.bone_settings.get(name,{}),true)
		if not local_config.get("enabled",true): continue
		var base: Transform3D=animated[name]
		var anchor:=base.origin; var parent:=int(bones[bone.index].parent)
		if parent>=0 and state.bones.has(str(bones[parent].name)):
			var parent_name:=str(bones[parent].name)
			if config.bone_settings.get(parent_name,{}).get("enabled",true): anchor=(state.bones[parent_name].pose*(animated[parent_name] as Transform3D).affine_inverse()*base).origin
		var target: Vector3=base*(bone.axis*bone.length)
		var acceleration:=_gravity(local_config)
		var events:=_events(local_config,_local(prototypes[id].actor,time),h)
		bone.v+=events.impulse/maxf(.001,float(local_config.mass)); acceleration+=events.force/maxf(.001,float(local_config.mass))
		if parent<0 and config.ragdoll:
			bone.root_v=(bone.root_v+events.impulse/maxf(.001,float(local_config.mass))+acceleration*h)*exp(-maxf(0,float(local_config.damping))*h)
			anchor=bone.anchor+bone.root_v*h
			if local_config.collision:
				var contact:=world.point_motion(id,bone.anchor,anchor,float(local_config.radius),int(local_config.layer),int(local_config.mask),[]); anchor=contact.position
			bone.root_v=(anchor-bone.anchor)/h; bone.anchor=anchor
		if not config.ragdoll: acceleration+=(target-bone.point)*float(local_config.stiffness)/maxf(.001,float(local_config.mass))
		bone.v=(bone.v+acceleration*h)*exp(-maxf(0,float(local_config.damping))*h)
		var next: Vector3=bone.point+bone.v*h; var direction: Vector3=(next-anchor).normalized(); var rest_direction: Vector3=(base.basis*bone.axis).normalized()
		var angle:=rest_direction.angle_to(direction); var limit:=deg_to_rad(float(local_config.limit))
		if angle>limit and angle>.000001: direction=rest_direction.slerp(direction,limit/angle)
		next=anchor+direction*bone.length
		if local_config.collision:
			var hit:=world.point_motion(id,bone.point,next,float(local_config.radius),int(local_config.layer),int(local_config.mask),[]); next=hit.position
		bone.v=(next-bone.point)/maxf(.00001,h); bone.point=next
		var rotation:=Quaternion(rest_direction,(next-anchor).normalized())*base.basis.get_rotation_quaternion()
		bone.pose=Transform3D(Basis(rotation)*Basis.from_scale(base.basis.get_scale()),anchor)
func _baked(bake: Dictionary, time: float) -> Dictionary:
	if bake.get("portable",false):
		var actor: ActorData=_model.actor_for_id(str(bake.get("owner",""))); var clip: ActorClip=_model.clip_for_actor_id(actor.id) if actor!=null else null
		if actor==null or clip==null or str(bake.get("portable_authored",""))!=KiwiBakeEditing.portable_signature(actor):
			_warn("Reusable bake has physical edits; recalculate the interacting group."); return {}
		var source: Dictionary=bake.duplicate(); source.portable=false; source.signature=signature; source.actor=str(bake.source_actor)
		var value:=_baked(source,KiwiBakeEditing.portable_time(bake,clip,time))
		if value.is_empty(): return {}
		var root:=str(bake.get("portable_root","")); var offset:=animated_world(root,time,true) if not root.is_empty() else Transform3D.IDENTITY
		return KiwiBakeEditing.portable_state(value,bake,clip,offset)
	if bake.get("signature","")!=signature or time<float(bake.get("from",INF)) or time>float(bake.get("to",-INF)): return {}
	var frames: Array=bake.get("frames",[])
	if bake.get("cache") is KiwiPhysicsBakeCache:
		var cache: KiwiPhysicsBakeCache=bake.cache; var exact:=clampf((time-float(bake.from))*float(bake.rate),0,cache.count-1); var index:=int(floor(exact))
		var left: Dictionary=cache.frame(index).get(str(bake.actor),{}); var left_error:=cache.error; var right: Dictionary=cache.frame(mini(index+1,cache.count-1)).get(str(bake.actor),{})
		if not left_error.is_empty(): _warn(left_error)
		if not cache.error.is_empty(): _warn(cache.error)
		if left.is_empty() or right.is_empty(): return {}
		var value: Dictionary=_snapshot({"value":left})["value"]; var fraction:=exact-index
		if index==cache.count-2:
			var left_time:=float(bake.from)+float(index)/float(bake.rate); var right_time:=minf(float(bake.to),left_time+1.0/float(bake.rate)); fraction=clampf((time-left_time)/maxf(.000001,right_time-left_time),0,1)
		value.pose=left.pose.interpolate_with(right.pose,fraction); _interpolate_points(value,left,right,fraction)
		for bone: String in value.bones:
			if right.bones.has(bone): value.bones[bone].pose=value.bones[bone].pose.interpolate_with(right.bones[bone].pose,fraction)
		return value
	if frames.is_empty(): return {}
	var exact:=clampf((time-float(bake.from))*float(bake.rate),0,frames.size()-1)
	var index:=int(floor(exact)); var next:=mini(index+1,frames.size()-1); var fraction:=exact-index
	var value: Dictionary=_snapshot({"value":frames[index]})["value"]; var right: Dictionary=frames[next]
	if right.has("powder_ids") and not right.has("powder_phase"): right=_snapshot({"value":right})["value"]
	value.pose=value.pose.interpolate_with(right.pose,fraction)
	_interpolate_points(value,value.duplicate(true),right,fraction)
	for bone in value.bones:
		if right.bones.has(bone): value.bones[bone].pose=value.bones[bone].pose.interpolate_with(right.bones[bone].pose,fraction)
	return value
func _interpolate_points(result: Dictionary,left: Dictionary,right: Dictionary,fraction: float) -> void:
	FogMotion.interpolate(result,left,right,fraction)
	KiwiDestructionBridge.interpolate(result,left,right,fraction)
	if left.has("structural"): result.structural=left.structural.duplicate(true)
	if left.has("destruction_events"): result.destruction_events=left.destruction_events.duplicate(true)
	else: result.erase("destruction_events")
	if right.has("powder_ids") and not left.has("powder_ids"):
		# Initialization is a discontinuity, not a morph from empty space. Do not
		# expose the right-hand activation before reaching its fixed-step time.
		for key in ["points","velocities"]+KiwiPowderSource.ARRAYS: result[key]=right[key].slice(0,0)
		result.initialized=false
	elif left.has("powder_ids"):
		for key in ["powder_deposits","powder_cells","powder_inventory","powder_releases","powder_cleared"]:
			if left.has(key): result[key]=left[key].duplicate(true) if left[key] is Dictionary else left[key]
		# Match append-only IDs and reveal grains only after their source birth time.
		for key in ["points","velocities"]+KiwiPowderSource.ARRAYS: result[key]=left[key].duplicate()
		if right.points.size()<left.points.size() or not is_equal_approx(float(left.initial_time),float(right.initial_time)):
			result.initialized=left.initialized; result.powder_time=left.powder_time; result.powder_bonds=left.powder_bonds.duplicate(true); return
		var local:=lerpf(float(left.powder_time),float(right.powder_time),fraction)
		for i in left.points.size(): result.points[i]=left.points[i].lerp(right.points[i],fraction)
		for i in range(left.points.size(),right.points.size()):
			if float(right.powder_birth_times[i])>local+1e-8: break
			for key in ["points","velocities"]+KiwiPowderSource.ARRAYS: result[key].append(right[key][i])
		result.powder_time=local
	elif left.has("fluid_ids"):
		# IDs are append-only until an explicit reset. Do not expose particles
		# before their fixed-step birth when interpolating between emitter frames.
		for key in ["points","velocities","fluid_ids","fluid_masses","fluid_foam","fluid_density"]: result[key]=left[key].duplicate()
		var indices:={}
		for i in right.fluid_ids.size(): indices[int(right.fluid_ids[i])]=i
		for i in left.points.size():
			var j:=int(indices.get(int(left.fluid_ids[i]),-1))
			if j>=0: result.points[i]=left.points[i].lerp(right.points[j],fraction); result.fluid_foam[i]=lerpf(left.fluid_foam[i],right.fluid_foam[j],fraction)
	elif left.points.size()==right.points.size():
		for i in result.points.size(): result.points[i]=left.points[i].lerp(right.points[i],fraction)
func _apply(time: float) -> void:
	for id: String in prototypes:
		var runtime:=_runtime(id)
		if runtime==null or not display_states.has(id): continue
		var state: Dictionary=display_states[id]; var config:=KiwiPhysicsSettings.sample(prototypes[id].actor,_local(prototypes[id].actor,time))
		if int(config.type)==9:
			if config.enabled and state.initialized: FogMotion.apply(self,id,state,time)
			else: preload("res://scripts/actors/fog/fog_motion_render.gd").clear(runtime)
			continue
		if runtime is KiwiPowderRuntime:
			if config.enabled and state.initialized: runtime.show_state(state)
			else: runtime.clear_grains()
			continue
		if runtime is KiwiFluidRuntime:
			if config.enabled and state.initialized:
				runtime.show_state(state,ActorAnimation.sampled_values(prototypes[id].actor,_local(prototypes[id].actor,time)))
				if not str(runtime.surface_stats.get("error","")).is_empty(): _warn(str(runtime.surface_stats.error))
			else: runtime.clear_surface()
			continue
		if not config.enabled or not state.initialized: continue
		if int(config.type)==8:
			KiwiGrowthPhysics.apply(self,id,state,config,time); continue
		var influence:=clampf(float(config.influence),0,1)
		runtime.apply_remote_transform(animated_world(id,time).interpolate_with(state.pose,influence),true,true,false)
		if config.collision_only:
			for item: Dictionary in prototypes[id].geometry.meshes:
				if is_instance_valid(item.node): item.node.set_meta("kiwi_physics_hidden",true); item.node.hide()
		if int(config.type) in [1,4] and not state.points.is_empty():
			_ensure_graph(id,state,config)
			if prototypes[id].graph.get("error","").is_empty(): KiwiPhysicsGeometry.deform(prototypes[id].graph,state.points,influence)
		if int(config.type)==5 and state.points.size()>1:
			var prototype: Dictionary=prototypes[id]
			if not is_instance_valid(prototype.rope_node):
				prototype.rope_node=MeshInstance3D.new(); prototype.rope_node.name="TimelinePhysicsRope"; runtime.add_child(prototype.rope_node)
			var material: Material=prototype.geometry.meshes[0].materials[0] if not prototype.geometry.meshes.is_empty() and not prototype.geometry.meshes[0].materials.is_empty() else null
			prototype.rope_node.mesh=KiwiPhysicsGeometry.rope_mesh(state.points,prototype.rope_node.global_transform.affine_inverse(),float(config.rope_radius),material); prototype.rope_node.visible=runtime.active
			for item: Dictionary in prototype.geometry.meshes:
				if is_instance_valid(item.node): item.node.set_meta("kiwi_physics_hidden",true); item.node.hide()
		if int(config.type)==3 and runtime is ActorSkeletonRigRuntime:
			for name: String in state.bones:
				var bone: Dictionary=state.bones[name]; var index: int=runtime.skeleton.find_bone(name)
				if index<0 or not config.bone_settings.get(name,{}).get("enabled",true): continue
				var base: Transform3D=runtime.skeleton.global_transform*runtime.skeleton.get_bone_global_pose(index)
				var weight:=influence*float(config.bone_settings.get(name,{}).get("influence",1.0))
				runtime.skeleton.set_bone_global_pose(index,runtime.skeleton.global_transform.affine_inverse()*base.interpolate_with(bone.pose,clampf(weight,0,1)))
			runtime.skeleton.force_update_all_bone_transforms()
	if not pending: KiwiDestructionAuthoring.apply_overrides(self,time)
	destruction.apply(self,time)
	vfx.apply(self,time)
func freeze(model: RefCounted, actor: ActorData) -> void:
	if not display_states.has(actor.id): return
	var before:=KiwiPhysicsSettings.authored(actor); var after:=before.duplicate(true)
	after.frozen={"state":_snapshot({actor.id:display_states[actor.id]})[actor.id],"time":requested_time}; after.mode=3
	after.frozen.state.v=Vector3.ZERO; after.frozen.state.w=Vector3.ZERO; after.frozen.state.responds=false
	after.frozen.state.velocities.fill(Vector3.ZERO)
	if after.frozen.state.has("fog_velocity"): after.frozen.state.fog_velocity.fill(Vector3.ZERO)
	if int(before.type)==8:
		var shapes:={}; var source:=KiwiGrowthPhysics.points(self,actor.id,requested_time); var transform:=KiwiGrowthPhysics.world(self,actor.id,requested_time); var growth:=KiwiGrowthPhysics.data(actor)
		for control: Dictionary in prototypes[actor.id].get("growth",{}).get("controls",[]):
			var inverse: Transform3D=(transform*KiwiSurfaceGrowth.point_frame(growth,control.root,source)).affine_inverse(); var points:=PackedVector3Array()
			for i in int(control.count): points.append(inverse*after.frozen.state.points[int(control.first)+i])
			shapes[control.id]=points
		after.frozen.growth_shapes=shapes
	for bone: Dictionary in after.frozen.state.bones.values(): bone.v=Vector3.ZERO; bone.root_v=Vector3.ZERO
	model.history.create_action("Freeze Physics")
	model.history.add_do_method(KiwiPhysicsSettings.assign.bind(model,actor,after)); model.history.add_undo_method(KiwiPhysicsSettings.assign.bind(model,actor,before)); model.history.commit_action()
func bake(editor: Control, actor: ActorData, start: float, end: float) -> String:
	if end<=start or start<0: return "Choose a valid non-negative bake interval."
	if not _baking_actor.is_empty() or not _baking_actors.is_empty(): return "A physics bake is already running."
	var count:=ceili((end-start)*rate)+1
	if count>4096: return "Bake at most 4,096 fixed-step frames per interval."
	var saved_time: float=editor.canvas.playhead; var saved_playing: bool=editor.playing; editor.playing=false
	var tree:=editor.get_tree()
	_baking_actor=actor.id; signature=""; mark_dirty()
	var frames:=[]; var expected:=""; var error:=""; var bake_bytes:=0
	for index in count:
		if not is_instance_valid(editor) or not editor.is_inside_tree() or editor.model.actor_for_id(actor.id)!=actor:
			_baking_actor=""; return "Scene closed or changed during bake; nothing was saved."
		var at:=minf(end,start+float(index)/rate); editor.canvas.playhead=at; editor._evaluate_runtimes()
		while pending:
			await tree.process_frame
			if not is_instance_valid(editor) or not editor.is_inside_tree() or editor.model.actor_for_id(actor.id)!=actor:
				_baking_actor=""; return "Scene closed or changed during bake; nothing was saved."
			editor._evaluate_runtimes()
		if expected.is_empty(): expected=signature
		if signature!=expected: error="Scene changed during bake; no bake was saved."; break
		if not display_states.has(actor.id): error="Enable physics before baking."; break
		var frame: Dictionary=_snapshot({actor.id:display_states[actor.id]})[actor.id]
		bake_bytes+=var_to_bytes(frame).size()
		if bake_bytes>MAX_CACHE_BYTES: error="Bake exceeds the 64 MiB per-actor limit. Shorten the interval or lower simulation resolution."; break
		frames.append(frame)
		if index%12==0: await tree.process_frame
	if not is_instance_valid(editor) or not editor.is_inside_tree() or editor.model.actor_for_id(actor.id)!=actor:
		_baking_actor=""; return "Scene closed or changed during bake; nothing was saved."
	var before:=KiwiPhysicsSettings.authored(actor)
	if error.is_empty():
		var source_mode:=int(before.bake.get("source_mode",1)) if int(before.mode) in [3,4] else int(before.mode)
		var after:=before.duplicate(true); after.bake={"signature":expected,"source_mode":source_mode,"from":start,"to":end,"rate":rate,"frames":frames}; after.mode=4
		if var_to_bytes(after.bake).size()>MAX_CACHE_BYTES: error="Bake exceeds the 64 MiB per-actor limit. Shorten the interval or lower simulation resolution."
		else:
			editor.model.history.create_action("Bake Physics")
			editor.model.history.add_do_method(KiwiPhysicsSettings.assign.bind(editor.model,actor,after)); editor.model.history.add_undo_method(KiwiPhysicsSettings.assign.bind(editor.model,actor,before)); editor.model.history.commit_action()
	_baking_actor=""; signature=""; mark_dirty()
	editor.canvas.playhead=saved_time; editor.playing=saved_playing; editor._evaluate_runtimes()
	return error

func bake_group(editor: ActorTimelineEditor,start: float,end: float,sample_rate: int=60,progress: Callable=Callable(),options: Dictionary={}) -> String:
	if not _baking_actor.is_empty() or not _baking_actors.is_empty(): return "A bake is already running."
	if start<0 or end<=start or sample_rate<1 or sample_rate>240: return "Choose a non-negative interval and a sample rate from 1 to 240."
	var count:=ceili((end-start)*sample_rate)+1
	if count>(262144 if options.get("external",false) else 16384): return "Bake sample budget exceeded; shorten the interval or lower the sampling rate."
	var actors: Array[ActorData]=[]; var before: Array[Dictionary]=[]
	for actor: ActorData in editor.model.actors:
		if KiwiPhysicsSettings.configured(actor): actors.append(actor); before.append(KiwiPhysicsSettings.authored(actor)); _baking_actors[actor.id]=true
	if actors.is_empty(): return "Enable physics or destruction first."
	var saved_time:=editor.canvas.playhead; var saved_playing:=editor.playing; editor.playing=false; bake_cancelled=false; bake_progress=0
	var model:=editor.model; var tree:=editor.get_tree(); var cache:=KiwiPhysicsBakeCache.new(); var expected:=""; var error:=""; signature=""; mark_dirty()
	if options.get("external",false):
		var directory:=str(options.get("directory",""))
		if directory.is_empty(): directory=LocalProjectFilesystem.get_project_root_directory().path_join(".kiwi-bakes")
		error=cache.begin_stream(directory)
	var reuse: Dictionary=options.get("reuse",{}); var old: KiwiPhysicsBakeCache=reuse.get("cache"); var boundary:=-1; var prefix:={}; var resumed:=false
	if old!=null:
		if not is_equal_approx(float(reuse.get("from",-1)),start) or int(reuse.get("rate",0))!=sample_rate: error="Interval recalculation requires the original start and sampling rate."
		boundary=mini(old.count-1,floori((float(options.get("recalculate_from",start))-start)*sample_rate))
		while boundary>=0 and absf((start+float(boundary)/sample_rate-origin)*rate-roundf((start+float(boundary)/sample_rate-origin)*rate))>.00001: boundary-=1
	for index in count:
		if not error.is_empty(): break
		if not is_instance_valid(editor) or not editor.is_inside_tree() or editor.model!=model: error="Scene closed or changed; the previous bake was preserved."; break
		if bake_cancelled: error="Bake canceled; the previous bake was preserved."; break
		var at:=minf(end,start+float(index)/sample_rate)
		if old!=null and index<=boundary:
			var saved:=old.frame(index)
			if saved.is_empty() or saved.get("@inputs","")!=KiwiBakeEditing.prefix_signature(model,at): error="The proposed reusable interval has earlier physical edits or missing data. Recalculate from an earlier time."; break
			prefix=saved.duplicate(true); error=cache.append(saved)
			if progress.is_valid(): progress.call(index+1,count,cache.bytes)
			if index%8==0: await tree.process_frame
			continue
		editor.canvas.playhead=at; editor._evaluate_runtimes()
		if not prefix.is_empty() and not resumed:
			resumed=true
			for field: String in ["@inputs","@scene_time"]: prefix.erase(field)
			states=_snapshot(prefix); step=roundi((start+float(boundary)/sample_rate-origin)*rate); checkpoints={step:_snapshot(states)}; requested_time=NAN; _floor_step=-1; pending=true
			editor._evaluate_runtimes()
		while pending and not bake_cancelled:
			await tree.process_frame
			if not is_instance_valid(editor) or not editor.is_inside_tree() or editor.model!=model: break
			editor._evaluate_runtimes()
		if not is_instance_valid(editor) or not editor.is_inside_tree() or editor.model!=model: error="Scene closed; nothing was saved."; break
		if bake_cancelled: error="Bake canceled; the previous bake was preserved."; break
		if expected.is_empty(): expected=signature
		if signature!=expected: error="Scene changed during bake; nothing was saved."; break
		# Record the actual simulation, never the display-only correction layer.
		var frame:=_snapshot(base_display_states)
		frame["@inputs"]=KiwiBakeEditing.prefix_signature(model,at); frame["@scene_time"]=at
		for actor: ActorData in actors:
			if model.actor_for_id(actor.id)!=actor or not frame.has(actor.id): error="A simulation actor was removed; nothing was saved."; break
		if not error.is_empty(): break
		error=cache.append(frame)
		if not error.is_empty(): break
		bake_progress=float(index+1)/count
		if progress.is_valid(): progress.call(index+1,count,cache.bytes)
		if index%8==0: await tree.process_frame
	if error.is_empty(): error=cache.finish_stream()
	if error.is_empty():
		var planned: Array[Dictionary]=[]
		for i in actors.size():
			var after: Dictionary=before[i].duplicate(true); var source_mode:=int(before[i].bake.get("source_mode",1)) if int(before[i].mode) in [3,4] else int(before[i].mode)
			var source_clip:=model.clip_for_actor_id(actors[i].id)
			after.bake={"signature":expected,"source_mode":source_mode,"from":start,"to":end,"rate":sample_rate,"cache":cache,"actor":actors[i].id,"owner":actors[i].id,"source_start":source_clip.start_time,"source_speed":source_clip.playback_speed,"group":_baking_actors.keys()}; after.mode=4
			planned.append(after); actors[i].values[&"physics"]=after
		# A frozen source becomes live-source-mode when rebaked. Sign the final
		# authored configuration, not the temporary frozen mode used before bake.
		var final_signature:=KiwiPhysicsSettings.fingerprint(model)
		for i in actors.size(): actors[i].values[&"physics"]=before[i]
		model.history.create_action("Bake interacting physics group")
		for i in actors.size():
			planned[i].bake.signature=final_signature
			model.history.add_do_method(KiwiPhysicsSettings.assign.bind(model,actors[i],planned[i])); model.history.add_undo_method(KiwiPhysicsSettings.assign.bind(model,actors[i],before[i]))
		model.history.commit_action()
	_baking_actors.clear(); signature=""; mark_dirty()
	if not error.is_empty(): cache.abort_stream()
	if is_instance_valid(editor) and editor.is_inside_tree() and editor.model==model: editor.canvas.playhead=saved_time; editor.playing=saved_playing; editor._evaluate_runtimes()
	return error
