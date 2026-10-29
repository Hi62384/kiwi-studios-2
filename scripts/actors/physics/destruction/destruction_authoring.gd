class_name KiwiDestructionAuthoring
extends RefCounted
## Authored source data, simulated guidance, and display-only corrections remain
## separate. A correction never changes the cached collision trajectory.
const NON_GEOMETRY := [12,13,14]
const GEOMETRY_FIELDS := ["type","enabled","position","direction","radius","amount","falloff","pieces","seed","irregularity","anisotropy","grain_direction","branching","path","region_enabled","region_center","region_radius"]
const SETUP_FIELDS := [&"destruction_operations",&"destruction_fragments",&"destruction_material",&"destruction_region",&"destruction_region_2",&"destruction_mode",&"debris_secondary",&"debris_vfx_preset"]
static func extend_actor(d: ActorDefinition) -> void:
	if d.type_id not in [&"basic_shape",&"basic_mesh"] or d.find_property(&"destruction_fragments")!=null: return
	for row in [["destruction_fragments","Fragment direction",{}, {"fragment_director":true,"no_keyframes":true}], ["destruction_overrides","Animation corrections",{}, {"no_keyframes":true,"hidden":true}]]:
		if row[0]=="destruction_overrides": row[3].inspector_hidden=true
		KiwiPowderDefinition.add(d,row[0],row[1],row[2],"Destruction",row[3],false)
	KiwiPowderDefinition.add(d,"destruction_vfx_offset","VFX timing offset (s)",0.0,"Destruction",{"advanced":true,"min":-100.0,"max":100.0},true)
	var p:=ActorProperty.create(&"destruction_setup","Reusable setup",null); p.object_type=&"destruction_setup"; p.options={"group":"Destruction","refresh_inspector":true}; d.properties.append(p)
	KiwiPowderDefinition.add(d,"destruction_setup_actions","Setup / simulation",0,"Destruction",{"destruction_workflow":true,"no_keyframes":true},false)
static func definition() -> ActorObjectDefinition:
	var d:=ActorObjectDefinition.new(); d.type_id=&"destruction_setup"; d.display_name="Destruction Setup"
	for row in [["name","Name","Destruction setup"],["source_signature","Source compatibility",""] ,["settings","Authored setup",{}],["tracks","Destruction animation tracks",[]],["baked_assembly","Baked rigid assembly",null]]:
		var p:=ActorProperty.create(StringName(row[0]),row[1],row[2],false); p.options.no_keyframes=true; p.options.inspector_hidden=row[0]!="name"; d.properties.append(p)
	return d
static func edit(model: ActorTimeline,actor: ActorData,field: StringName,value: Variant,label: String) -> void:
	var before: Variant=ActorData.copy_value(actor.values.get(field,{}))
	model.history.create_action(label)
	model.history.add_do_method(assign.bind(weakref(model),actor,field,ActorData.copy_value(value)))
	model.history.add_undo_method(assign.bind(weakref(model),actor,field,before)); model.history.commit_action()
static func assign(reference: WeakRef,actor: ActorData,field: StringName,value: Variant) -> void:
	var model:=reference.get_ref() as ActorTimeline
	if model==null: return
	actor.values[field]=ActorData.copy_value(value); actor.animation_previews.clear(); actor.emit_changed(); model.changed.emit()
static func operation_action(model: ActorTimeline,actor: ActorData,id: String,action: String) -> String:
	var ops: Dictionary=actor.get_value(&"destruction_operations",{}).duplicate(true)
	if not ops.has(id): return "Choose an operation first."
	if action=="Duplicate":
		var copy: Dictionary=ops[id].duplicate(true); copy.seed=int(copy.get("seed",1))+1; ops[ActorData.new_id()]=copy
	elif action=="Reset":
		ops[id]=KiwiDestructionDefinition.operation(int(ops[id].type),float(ops[id].get("time",0)))
		var before:=model.animation_snapshot(actor); var after: Array[ActorAnimationTrack]=[]
		for track: ActorAnimationTrack in before:
			if track.path.size()>1 and track.path[0]=="destruction_operations" and track.path[1]==id: continue
			after.append(track.copy_track())
		model.history.create_action("Reset destruction operation"); model.history.add_do_method(KiwiDestructionDefinition.restore_animation.bind(weakref(model),actor,ops,after)); model.history.add_undo_method(KiwiDestructionDefinition.restore_animation.bind(weakref(model),actor,ActorData.copy_value(actor.values.get(&"destruction_operations",{})),before)); model.history.commit_action(); return ""
	elif action in ["Up","Down"]:
		var order:=ops.keys(); var index:=order.find(id); var target:=index+(-1 if action=="Up" else 1)
		if target<0 or target>=order.size(): return "Already at the end of the stack."
		order.remove_at(index); order.insert(target,id); var seen:={}; var next:={}
		for key: String in order:
			for dependency: String in ops[key].get("depends_on",[]):
				if not seen.has(dependency): return "Cannot move before required operation "+dependency+". Remove or retarget its dependency first."
			seen[key]=true; next[key]=ops[key]
		ops=next
	KiwiDestructionDefinition.edit(model,actor,ops,action+" destruction operation")
	return ""
static func geometry_operations(ops: Dictionary) -> Dictionary:
	var result:={}; var protected: Array[Dictionary]=[]
	for op: Dictionary in ops.values():
		if op.get("enabled",true) and int(op.get("type",0))==13: protected.append(op)
	for id: String in ops:
		var op: Dictionary=ops[id]
		if int(op.get("type",0)) in NON_GEOMETRY: continue
		var copy:={}
		for key: String in GEOMETRY_FIELDS:
			if op.has(key): copy[key]=op[key]
		if not protected.is_empty(): copy.protected_regions=protected.map(func(region: Dictionary): return {"position":region.get("position",Vector3.ZERO),"radius":region.get("radius",.5)})
		result[id]=copy
	return result
static func resistance(ops: Dictionary,point: Vector3) -> float:
	var multiplier:=1.0
	for op: Dictionary in ops.values():
		if not op.get("enabled",true) or int(op.get("type",0)) not in [12,13]: continue
		var distance:=point.distance_to(op.get("position",Vector3.ZERO)); var radius:=maxf(.001,float(op.get("radius",.5)))
		if distance>=radius: continue
		if int(op.type)==13: return INF
		multiplier*=lerpf(1,maxf(.01,float(op.get("amount",.25))),pow(1-distance/radius,maxf(.1,float(op.get("falloff",2)))))
	return maxf(.01,multiplier)
static func fragment_defaults(position: Vector3=Vector3.ZERO) -> Dictionary:
	return {"mode":0,"enabled":true,"velocity":Vector3.ZERO,"angular_velocity":Vector3.ZERO,"impulse":Vector3.ZERO,"impulse_time":0.0,"pin_until":-1.0,"target":position,"strength":25.0,"damping":8.0,"from":0.0,"to":-1.0,"mass_scale":1.0,"collision":true}
static func fragment_key(owner: String,id: String) -> String: return id.trim_prefix(owner+":fragment:")
static func guidance(controller: KiwiTimelinePhysics,owner: String,fragment: Dictionary,values: Dictionary,time: float,h: float) -> bool:
	var key:=fragment_key(owner,str(fragment.id)); var rules: Dictionary=values.get(&"destruction_fragments",{}); var rule: Dictionary=rules.get(key,{})
	if rule.is_empty() or not rule.get("enabled",true): return false
	var local:=controller._local(controller.prototypes[owner].actor,time); var pose: Transform3D=fragment.pose
	if not fragment.get("directed_initialized",false):
		fragment.v+=rule.get("velocity",Vector3.ZERO); fragment.w+=rule.get("angular_velocity",Vector3.ZERO)*PI/180
		fragment.mass=maxf(.001,float(fragment.mass)*clampf(float(rule.get("mass_scale",1)),.01,100)); fragment.directed_initialized=true; fragment.pin_pose=pose
	if local>=float(rule.get("impulse_time",0)) and not fragment.get("directed_impulse",false): fragment.v+=rule.get("impulse",Vector3.ZERO)/fragment.mass; fragment.directed_impulse=true; fragment.sleep=0.0
	var pin: float=float(rule.get("pin_until",-1))
	if pin>=0 and local<pin:
		fragment.pose=fragment.pin_pose; fragment.v=Vector3.ZERO; fragment.w=Vector3.ZERO; fragment.responds=false; return true
	var in_interval:=local>=float(rule.get("from",0)) and (float(rule.get("to",-1))<0 or local<float(rule.to))
	var mode:=int(rule.get("mode",0)) if in_interval else 0
	if mode==2:
		# Explicit animation control, not claimed to solve physical contacts.
		var target: Vector3=rule.get("target",pose.origin); fragment.v=(target-pose.origin)/maxf(.00001,h); fragment.pose.origin=target; fragment.directed_animated=true; fragment.responds=false; return true
	fragment.directed_animated=false
	if mode==1:
		var acceleration: Vector3=(rule.get("target",pose.origin)-pose.origin)*maxf(0,float(rule.get("strength",25)))-fragment.v*maxf(0,float(rule.get("damping",8)))
		fragment.v+=acceleration.limit_length(500)*h; fragment.sleep=0.0
	return false
static func apply_overrides(controller: KiwiTimelinePhysics,time: float) -> void:
	for owner: String in controller.display_states:
		var actor: ActorData=controller.prototypes[owner].actor; var values:=ActorAnimation.sampled_values(actor,controller._local(actor,time)); var corrections: Dictionary=values.get(&"destruction_overrides",{})
		for fragment: Dictionary in controller.display_states[owner].get("destruction_fragments",[]):
			var key:=fragment_key(owner,str(fragment.id)); var rule: Dictionary=corrections.get(key,{})
			if rule.is_empty() or not rule.get("enabled",true): continue
			var timing:=float(rule.get("time_offset",0)); var speed:=float(rule.get("time_scale",1)); var freeze:=float(rule.get("freeze_time",-1))
			if not is_zero_approx(timing) or not is_equal_approx(speed,1) or freeze>=0:
				var config:=KiwiPhysicsSettings.sample(actor,controller._local(actor,time)); var sample:=controller._baked(config.bake,freeze if freeze>=0 else time*speed+timing)
				for candidate: Dictionary in sample.get("destruction_fragments",[]):
					if str(candidate.id)==str(fragment.id): fragment.pose=candidate.pose; break
			var pose: Transform3D=fragment.pose; pose.origin+=rule.get("offset",Vector3.ZERO); pose.basis=Basis.from_euler(rule.get("rotation",Vector3.ZERO)*PI/180)*pose.basis; fragment.pose=pose
		var shift:=float(values.get(&"destruction_vfx_offset",0))
		if not is_zero_approx(shift):
			for event: Dictionary in controller.display_states[owner].get("destruction_events",[]): event.time+=shift
static func source_signature(controller: KiwiTimelinePhysics,actor: ActorData) -> String:
	if not controller.states.has(actor.id): return ""
	var source:=controller.destruction.source(controller,actor.id,controller.states[actor.id])
	if not source.get("mesh") is KiwiModelMesh: return ""
	# Canonical integer coordinates ignore signed zero and roundoff introduced by
	# world-to-local conversion, while retaining size and topology validation.
	var points:=[]
	for point: Vector3 in source.mesh.vertices: points.append(Vector3i((point*100000).round()))
	return str(hash([points,source.mesh.faces]))
static func capture_setup(controller: KiwiTimelinePhysics,actor: ActorData) -> ActorObjectData:
	var setup:=definition().create_object(); setup.values.name=actor.display_name+" destruction"; setup.values.source_signature=source_signature(controller,actor); var settings:={}
	for key: StringName in SETUP_FIELDS: settings[key]=ActorData.copy_value(actor.values.get(key))
	setup.values.settings=settings; var tracks: Array[ActorAnimationTrack]=[]
	for track: ActorAnimationTrack in actor.animation_tracks:
		if not track.path.is_empty() and (StringName(track.path[0]) in SETUP_FIELDS or track.path[0]=="destruction_enabled"): tracks.append(track.copy_track())
	setup.values.tracks=tracks; return setup
static func apply_setup(model: ActorTimeline,controller: KiwiTimelinePhysics,actor: ActorData,setup: ActorObjectData) -> String:
	if setup==null or setup.type_id!=&"destruction_setup": return "Load a Destruction Setup resource first."
	var identity:=source_signature(controller,actor)
	if identity.is_empty() or identity!=str(setup.get_value(&"source_signature","")): return "Source topology differs. Apply this setup to a matching mesh; no vertex or fragment data was copied."
	var before: Dictionary=ActorData.copy_value(actor.values); var after: Dictionary=ActorData.copy_value(actor.values); after.merge(ActorData.copy_value(setup.get_value(&"settings",{})),true); after[&"destruction_enabled"]=true
	var old_tracks:=model.animation_snapshot(actor); var tracks: Array[ActorAnimationTrack]=[]
	for track: ActorAnimationTrack in old_tracks:
		if track.path.is_empty() or (not StringName(track.path[0]) in SETUP_FIELDS and track.path[0]!="destruction_enabled"): tracks.append(track.copy_track())
	for track: ActorAnimationTrack in setup.get_value(&"tracks",[]): tracks.append(track.copy_track())
	model.history.create_action("Apply destruction setup"); model.history.add_do_method(assign_setup.bind(weakref(model),actor,after,tracks)); model.history.add_undo_method(assign_setup.bind(weakref(model),actor,before,old_tracks)); model.history.commit_action(); return ""
static func assign_setup(reference: WeakRef,actor: ActorData,values: Dictionary,tracks: Array[ActorAnimationTrack]) -> void:
	var model:=reference.get_ref() as ActorTimeline
	if model!=null: actor.values=ActorData.copy_value(values); actor.animation_previews.clear(); model.restore_animation(actor,tracks)
static func assign_values(reference: WeakRef,actor: ActorData,values: Dictionary) -> void:
	var model:=reference.get_ref() as ActorTimeline
	if model!=null: actor.values=ActorData.copy_value(values); actor.emit_changed(); model.changed.emit()
static func edit_fragments(model: ActorTimeline,actor: ActorData,field: StringName,ids: Array,key: String,value: Variant) -> void:
	if ids.is_empty(): return
	var guided:=key=="guided_target"
	if guided: key="target"
	var before: Dictionary=ActorData.copy_value(actor.values.get(field,{})); var next:=before.duplicate(true); var tracks:=model.animation_snapshot(actor); var after:=model.animation_snapshot(actor)
	var clip:=model.clip_for_actor_id(actor.id)
	for id: String in ids:
		if not next.has(id): next[id]=fragment_defaults() if field==&"destruction_fragments" else {"enabled":true,"offset":Vector3.ZERO,"rotation":Vector3.ZERO}
		if guided: next[id].mode=1
		var path:=PackedStringArray([str(field),id,key]); var found:=false
		for track: ActorAnimationTrack in after:
			if track.path!=path: continue
			found=true; var at:=clip.local_time(model.playhead_time); var frame:=track.key_at(at)
			if frame==null: frame=ActorKeyframe.new(); frame.id=ActorData.new_id(); frame.time=at; track.keys.append(frame)
			frame.value=ActorData.copy_value(value[track.component] if track.component>=0 else value); track.sort_keys()
		if not found: next[id][key]=ActorData.copy_value(value)
	model.history.create_action("Correct growth motion" if field==&"growth_overrides" else ("Direct fragments" if field==&"destruction_fragments" else "Correct fragment animation"))
	model.history.add_do_method(restore_fragments.bind(weakref(model),actor,field,next,after)); model.history.add_undo_method(restore_fragments.bind(weakref(model),actor,field,before,tracks)); model.history.commit_action()
static func restore_fragments(reference: WeakRef,actor: ActorData,field: StringName,values: Dictionary,tracks: Array[ActorAnimationTrack]) -> void:
	var model:=reference.get_ref() as ActorTimeline
	if model==null: return
	actor.values[field]=ActorData.copy_value(values); actor.animation_previews.clear(); model.restore_animation(actor,tracks)
static func key_fragments(model: ActorTimeline,actor: ActorData,field: StringName,ids: Array,key: String,fallback: Variant) -> void:
	if ids.is_empty(): return
	var before: Dictionary=ActorData.copy_value(actor.get_value(field,{})); var next:=before.duplicate(true); var tracks:=model.animation_snapshot(actor); var after:=model.animation_snapshot(actor)
	for id: String in ids:
		if not next.has(id): next[id]=fragment_defaults() if field==&"destruction_fragments" else {"enabled":true,"offset":Vector3.ZERO,"rotation":Vector3.ZERO}
		var path:=PackedStringArray([str(field),id,key]); var matches: Array[ActorAnimationTrack]=[]
		for candidate: ActorAnimationTrack in after:
			if candidate.path==path: matches.append(candidate)
		if matches.is_empty():
			var track:=ActorAnimationTrack.new(); track.path=path; track.label=("Correction " if field==&"destruction_overrides" else "Piece ")+id.trim_prefix(id.get_slice(":",0)+":")+" · "+key.replace("_"," ").capitalize(); after.append(track); matches.append(track)
		var time:=model.clip_for_actor_id(actor.id).local_time(model.playhead_time); var value: Variant=ActorAnimation.sampled_value(actor,path,time,next[id].get(key,fallback))
		for track: ActorAnimationTrack in matches:
			var frame:=track.key_at(time)
			if frame==null: frame=ActorKeyframe.new(); frame.id=ActorData.new_id(); frame.time=time; track.keys.append(frame)
			frame.value=ActorData.copy_value(value[track.component] if track.component>=0 else value); track.sort_keys()
	model.history.create_action("Keyframe selected fragments"); model.history.add_do_method(restore_fragments.bind(weakref(model),actor,field,next,after)); model.history.add_undo_method(restore_fragments.bind(weakref(model),actor,field,before,tracks)); model.history.commit_action()
	model.overlay_actor_id=actor.id; model.overlay_path=PackedStringArray([str(field),str(ids[0]),key]); model.changed.emit()
