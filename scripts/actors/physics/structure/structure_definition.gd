class_name KiwiStructure
extends RefCounted
const TYPES:=["Weld / fixed","Hinge","Slider","Cable / distance","Spring"]
const ROLES:=["Dynamic element","Fixed foundation","Animated support"]
static func extend_actor(d: ActorDefinition) -> void:
	if d.type_id not in [&"basic_shape",&"basic_mesh"] or d.find_property(&"structure_enabled")!=null: return
	for row in [
		["structure_enabled","Enabled",false,{"refresh_inspector":true}],
		["structure_role","Role",0,{"choices":ROLES}],
		["structure_iterations","Joint quality",12,{"min":2,"max":32,"step":1}],
		["structure_overlay","Load overlay",true,{}],
		["structure_connections","Connections",{},{"structure_editor":true,"no_keyframes":true}]
	]: KiwiPowderDefinition.add(d,row[0],row[1],row[2],"Structure",row[3],row[0] not in ["structure_connections","structure_iterations","structure_overlay"])
static func connection(target: String,pivot: Vector3=Vector3.ZERO,target_pivot: Vector3=Vector3.ZERO,kind: int=0) -> Dictionary:
	return {"target":target,"type":kind,"enabled":true,"pivot":pivot,"target_pivot":target_pivot,"orientation":Vector3.ZERO,"strength":1.0,"stiffness":100000.0,"angular_stiffness":100000.0,"breaking_force":10000.0,"breaking_torque":10000.0,"tension":1.0,"compression":1.0,"shear":1.0,"bending":1.0,"damping":.15,"damage_rate":.05,"initial_damage":0.0,"break_at":-1.0,"prevent_failure":false,"length":0.0,"limit":1.0,"tension_only":true,"material_strength":false,"exclude_collision":true}
static func assign(reference: WeakRef,entries: Array) -> void:
	var model:=reference.get_ref() as ActorTimeline
	if model==null: return
	for entry: Dictionary in entries:
		entry.actor.values=ActorData.copy_value(entry.values); entry.actor.animation_previews.clear()
		if entry.has("tracks"):
			entry.actor.animation_tracks.clear()
			for track: ActorAnimationTrack in entry.tracks: entry.actor.animation_tracks.append(track.copy_track())
		entry.actor.emit_changed()
	model.changed.emit()
static func commit(model: ActorTimeline,actors: Array[ActorData],updates: Array[Dictionary],label: String) -> void:
	var before:=[]; var after:=[]
	for i in actors.size():
		var actor:=actors[i]; var values:=actor.values.duplicate(true); values.merge(updates[i],true)
		var tracks:=model.animation_snapshot(actor); var retained: Array[ActorAnimationTrack]=[]
		for track in tracks:
			if track.path.size()>1 and track.path[0]=="structure_connections" and not values.get(&"structure_connections",{}).has(track.path[1]): continue
			retained.append(track.copy_track())
		before.append({"actor":actor,"values":ActorData.copy_value(actor.values),"tracks":tracks}); after.append({"actor":actor,"values":values,"tracks":retained})
	model.history.create_action(label); model.history.add_do_method(assign.bind(weakref(model),after)); model.history.add_undo_method(assign.bind(weakref(model),before)); model.history.commit_action()
static func set_value(model: ActorTimeline,actor: ActorData,id: String,key: String,value: Variant,preview: bool=false) -> void:
	var path:=PackedStringArray(["structure_connections",id,key])
	if actor.animation_track(path)!=null:
		if preview: model.preview_animation_value(actor,path,value)
		else: model.commit_animation_value(actor,path,value)
		return
	var links: Dictionary=ActorData.copy_value(actor.get_value(&"structure_connections",{}))
	if not links.has(id): return
	links[id][key]=value
	if preview: actor.values[&"structure_connections"]=links; actor.emit_changed(); model.changed.emit()
	else: commit(model,[actor],[{&"structure_connections":links}],"Edit structural connection")
static func connect_actors(model: ActorTimeline,a: ActorData,b: ActorData,point: Vector3,pose_a: Transform3D,pose_b: Transform3D,kind: int=0) -> String:
	var id:=ActorData.new_id(); var links: Dictionary=ActorData.copy_value(a.get_value(&"structure_connections",{})); links[id]=connection(b.id,pose_a.affine_inverse()*point,pose_b.affine_inverse()*point,kind)
	var group:=str(a.get_value(&"structure_assembly",ActorData.new_id()))
	commit(model,[a,b],[{&"structure_connections":links,&"structure_enabled":true,&"structure_assembly":group},{&"structure_enabled":true,&"structure_assembly":group}],"Connect structural elements")
	return id
static func remap_actor(actor: ActorData,ids: Dictionary,clear_external: bool=true) -> void:
	var links: Dictionary=ActorData.copy_value(actor.get_value(&"structure_connections",{}))
	for link: Dictionary in links.values():
		var target:=str(link.get("target","")); link.target=ids.get(target,"" if clear_external else target)
	actor.values[&"structure_connections"]=links
	if actor.values.has(&"structure_assembly"): actor.values[&"structure_assembly"]=str(ids.get(str(actor.values.structure_assembly),actor.id))
	for track in actor.animation_tracks:
		if track.path.size()==3 and track.path[0]=="structure_connections" and track.path[2]=="target":
			for key in track.keys: key.value=ids.get(str(key.value),"" if clear_external else key.value)
static func candidates(actors: Array[ActorData],bounds: Dictionary,tolerance: float) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for i in actors.size():
		if not bounds.has(actors[i].id): continue
		for j in range(i+1,actors.size()):
			if not bounds.has(actors[j].id): continue
			var a: AABB=bounds[actors[i].id]; var b: AABB=bounds[actors[j].id]
			var pa:=b.get_center().clamp(a.position,a.end); var pb:=pa.clamp(b.position,b.end)
			if pa.distance_to(pb)<=tolerance: result.append({"a":actors[i],"b":actors[j],"point":(pa+pb)*.5,"gap":pa.distance_to(pb)})
	return result
