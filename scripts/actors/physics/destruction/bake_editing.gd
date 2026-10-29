class_name KiwiBakeEditing
extends RefCounted
static func prefix_signature(model: ActorTimeline,time: float) -> String:
	var rows:=[]
	for actor: ActorData in model.actors:
		if not actor.values.get(&"position") is Vector3: continue
		var clip:=model.clip_for_actor_id(actor.id); var local:=clip.local_time(time); var values:=ActorAnimation.sampled_values(actor,local); var physical:={}
		for key: Variant in values:
			var name:=str(key)
			if actor.type_id==&"fog_volume":
				if preload("res://scripts/actors/fog/fog_motion_definition.gd").physical_path(PackedStringArray([name])): physical[key]=preload("res://scripts/actors/fog/fog_motion_definition.gd").content(values[key])
				continue
			if name.begins_with("growth_"): continue
			if name in ["physics","material","color","text","uniforms","shader","shadow_casting","structure_overlay","structure_assembly","destruction_overrides","destruction_setup","destruction_setup_actions","destruction_vfx_offset","destruction_interior","destruction_interior_color","destruction_preset"] or name in KiwiDebris.VISUAL: continue
			physical[key]=KiwiDestructionMaterial.physical(values[key]) if name in ["destruction_material","destruction_region","destruction_region_2"] else values[key]
		var ops:={}
		for id: String in values.get(&"destruction_operations",{}):
			var op: Dictionary=values.destruction_operations[id]
			if op.get("enabled",true) and float(op.get("time",0))<=local: ops[id]=op
		physical[&"destruction_operations"]=ops
		var rules: Dictionary=values.get(&"destruction_fragments",{}).duplicate(true)
		for rule: Dictionary in rules.values():
			if float(rule.get("impulse_time",0))>local: rule.erase("impulse_time"); rule.erase("impulse")
			if float(rule.get("from",0))>local:
				for field: String in ["from","to","target","mode","strength","damping"]: rule.erase(field)
		physical[&"destruction_fragments"]=rules
		var config:=KiwiPhysicsSettings.sample(actor,local)
		if int(config.mode)==4: config.mode=int(config.bake.get("source_mode",1))
		config.erase("bake")
		if int(config.mode)!=3: config.erase("frozen")
		var forces:=[]
		for force: Dictionary in config.forces:
			if float(force.get("time",0))<=local: forces.append(force)
		config.forces=forces
		rows.append([actor.id,actor.parent_id,physical,config,[clip.start_time,clip.duration,clip.source_offset,clip.playback_speed]])
	return var_to_str(KiwiPhysicsSettings.canonical(rows)).sha256_text()
static func group_cache(actor: ActorData) -> Dictionary: return KiwiPhysicsSettings.authored(actor).bake
static func remap_frame(frame: Dictionary,ids: Dictionary,offset: Transform3D) -> Dictionary:
	var result:={}
	for key: Variant in frame:
		if str(key).begins_with("@"): result[key]=frame[key]; continue
		var state: Dictionary=frame[key].duplicate(true); var next:=str(ids.get(str(key),str(key))); state.pose=offset*state.pose
		for field: String in ["v","w"]:
			if state.has(field): state[field]=offset.basis*state[field]
		for fragment: Dictionary in state.get("destruction_fragments",[]):
			fragment.id=next+":fragment:"+str(fragment.id).get_slice(":fragment:",1); fragment.pose=offset*fragment.pose; fragment.v=offset.basis*fragment.v; fragment.w=offset.basis*fragment.w
		for event: Dictionary in state.get("destruction_events",[]):
			event.source_actor=next; event.point=offset*event.point; event.normal=offset.basis*event.normal; event.velocity=offset.basis*event.velocity
		if state.has("structural"):
			state.structural.island=remap_id(str(state.structural.get("island","")),ids)
			var fragments:={}
			for fragment_id: String in state.structural.get("fragments",{}):
				var info: Dictionary=state.structural.fragments[fragment_id]; info.island=remap_id(str(info.get("island","")),ids); fragments[remap_id(fragment_id,ids)]=info
			state.structural.fragments=fragments
		result[next]=state
	return result
static func remap_id(id: String,ids: Dictionary) -> String:
	if id.contains(":fragment:"): return str(ids.get(id.get_slice(":fragment:",0),id.get_slice(":fragment:",0)))+":fragment:"+id.get_slice(":fragment:",1)
	return str(ids.get(id,id))
static func portable_signature(actor: ActorData) -> String:
	var values:={}
	for key: Variant in actor.values:
		var name:=str(key)
		if name in ["physics","material","color","text","uniforms","shader","shadow_casting","structure_overlay","structure_assembly","destruction_overrides","destruction_setup","destruction_setup_actions","destruction_vfx_offset","destruction_interior","destruction_interior_color","destruction_preset"] or name in KiwiDebris.VISUAL or name.begins_with("growth_"): continue
		values[key]=actor.values[key]
	var config:=KiwiPhysicsSettings.authored(actor); config.mode=int(config.bake.get("source_mode",1)); config.erase("bake"); config.erase("frozen")
	var tracks:=[]
	for track: ActorAnimationTrack in actor.animation_tracks:
		if track.path.is_empty() or track.path[0] in ["destruction_overrides","destruction_vfx_offset","color","material","shader","uniforms","shadow_casting"]: continue
		var keys:=[]
		for key: ActorKeyframe in track.keys: keys.append([key.time,key.value,key.interpolation,key.attenuation,key.value_curve])
		tracks.append([track.path,keys])
	return var_to_str(KiwiPhysicsSettings.canonical([values,config,tracks])).sha256_text()
static func portable_scene(editor: ActorTimelineEditor) -> Dictionary:
	var scene:=editor.capture_scene_data(); var caches:=0; var start:=-INF; var end:=INF
	for actor: ActorData in scene.actors:
		if not KiwiPhysicsSettings.configured(actor): continue
		var config:=KiwiPhysicsSettings.authored(actor); var bake: Dictionary=config.bake
		if int(config.type) not in [0,2]: return {"error":"Reusable baked assemblies currently support rigid bodies and real destruction fragments. Other solvers must be recalculated after instantiation."}
		if int(config.mode)!=4 or not bake.get("cache") is KiwiPhysicsBakeCache or bake.get("signature","")!=editor.physics.signature: return {"error":"Bake the complete interacting group before capturing a reusable assembly."}
		var clip: ActorClip
		for candidate: ActorClip in scene.clips:
			if candidate.actor_id==actor.id: clip=candidate; break
		if clip==null: return {"error":"The assembly has an actor without timing data."}
		bake.portable=true; bake.source_actor=actor.id; bake.owner=actor.id; bake.source_start=clip.start_time; bake.source_speed=clip.playback_speed; bake.source_offset=clip.source_offset; bake.portable_authored=portable_signature(actor); config.bake=bake; actor.values[&"physics"]=config; caches+=1
		start=maxf(start,float(bake.from)); end=minf(end,float(bake.to))
	if caches==0: return {"error":"The scene has no baked rigid/destruction group."}
	if end<=start: return {"error":"Baked groups must share a nonempty playback interval."}
	for clip: ActorClip in scene.clips:
		var first:=maxf(start,clip.start_time); var last:=minf(end,clip.start_time+clip.duration); clip.source_offset+=(first-clip.start_time)*clip.playback_speed; clip.start_time=clampf(first,start,end); clip.duration=maxf(0,last-first)
	return {"error":"","scene":scene}
static func portable_time(bake: Dictionary,clip: ActorClip,time: float) -> float:
	return float(bake.get("source_start",0.))+(clip.local_time(time)-float(bake.get("source_offset",0.)))/maxf(.001,float(bake.get("source_speed",1.)))
static func current_time(bake: Dictionary,clip: ActorClip,time: float) -> float:
	return clip.start_time+((time-float(bake.get("source_start",0.)))*float(bake.get("source_speed",1.))+float(bake.get("source_offset",0.))-clip.source_offset)/maxf(.001,clip.playback_speed)
static func portable_state(state: Dictionary,bake: Dictionary,clip: ActorClip,offset: Transform3D) -> Dictionary:
	var ids: Dictionary=bake.get("portable_ids",{}); var result:=remap_frame({str(bake.source_actor):state},ids,offset).get(str(bake.owner),{}) as Dictionary
	if result.is_empty(): return result
	var speed:=clip.playback_speed/maxf(.001,float(bake.get("source_speed",1.)))
	for field: String in ["initial_time"]:
		if result.has(field): result[field]=current_time(bake,clip,float(result[field]))
	if result.has("initial_pose"): result.initial_pose=offset*result.initial_pose
	for field: String in ["v","w"]:
		if result.has(field): result[field]*=speed
	for fragment: Dictionary in result.get("destruction_fragments",[]):
		fragment.v*=speed; fragment.w*=speed
	for event: Dictionary in result.get("destruction_events",[]):
		for field: String in ["time","scene_time","birth_time"]:
			if event.has(field): event[field]=current_time(bake,clip,float(event[field]))
		event.age_scale=speed
	return result
