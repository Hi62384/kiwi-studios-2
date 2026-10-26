class_name KiwiRigMath
extends RefCounted
## Authoring identities are stable; Skeleton3D indices are only a runtime mapping.
static func ensure(rig: KiwiModelComponent) -> void:
	var world: Array[Transform3D]=[]
	for i in rig.bones.size():
		var bone := rig.bones[i]
		if not bone.has("id") or str(bone.id).is_empty(): bone.id=rig.id+":bone:"+str(i)
		if not bone.has("length"):
			bone.length=.25
			for child in rig.bones:
				if int(child.parent)==i: bone.length=maxf(.01,(child.rest as Transform3D).origin.length()); break
		if not bone.has("radius"): bone.radius=maxf(.025,float(bone.length)*.3)
		if not bone.has("connected"): bone.connected=false
		if not bone.has("roll"):
			if world.is_empty(): world=globals(rig.bones)
			var aligned := frame(world[i].origin,world[i].origin+world[i].basis.y)
			var relative := aligned.basis.inverse()*world[i].basis.orthonormalized()
			bone.roll=atan2(relative.z.x,relative.x.x)
		if not bone.has("mirror_id"): bone.mirror_id=""
		if not bone.has("metadata"): bone.metadata={}

static func globals(bones: Array, pose: bool=false) -> Array[Transform3D]:
	var result: Array[Transform3D]=[]; result.resize(bones.size()); var ready := {}
	for i in bones.size(): _global(i,bones,result,ready,{},pose)
	return result

static func bind_signature(bones: Array) -> int:
	return hash(bones.map(func(bone: Dictionary): return [bone.get("id",bone.name),bone.parent,bone.rest]))

static func _global(index: int, bones: Array, result: Array[Transform3D], ready: Dictionary, visiting: Dictionary, pose: bool) -> Transform3D:
	if ready.has(index): return result[index]
	if visiting.has(index): return Transform3D.IDENTITY
	visiting[index]=true
	var bone: Dictionary=bones[index]
	var local: Transform3D=Transform3D(Basis.from_euler((bone.rotation as Vector3)*PI/180.)*Basis.from_scale(bone.scale),bone.position) if pose else bone.rest
	var parent := int(bone.parent)
	result[index]=_global(parent,bones,result,ready,visiting,pose)*local if parent>=0 and parent<bones.size() else local
	ready[index]=true; visiting.erase(index); return result[index]

static func tail(bone: Dictionary, global: Transform3D) -> Vector3:
	return global*Vector3(0,maxf(.001,float(bone.get("length",.25))),0)

static func frame(head: Vector3, end: Vector3, roll: float=0.) -> Transform3D:
	var direction := (end-head).normalized()
	if direction.length_squared()<.5: direction=Vector3.UP
	return Transform3D(Basis(Quaternion(Vector3.UP,direction))*Basis(Vector3.UP,roll),head)

static func set_rest(bone: Dictionary, local: Transform3D, keep_pose: bool=true) -> void:
	var old: Transform3D=bone.get("rest",local)
	var pose := Transform3D(Basis.from_euler((bone.get("rotation",Vector3.ZERO) as Vector3)*PI/180.)*Basis.from_scale(bone.get("scale",Vector3.ONE)),bone.get("position",local.origin))
	bone.rest=local
	var next := local*old.affine_inverse()*pose if keep_pose else local
	bone.position=next.origin; bone.rotation=next.basis.get_rotation_quaternion().get_euler()*180./PI; bone.scale=next.basis.get_scale()

static func add_bone(rig: KiwiModelComponent, head: Vector3, end: Vector3, parent: int=-1, title: String="Bone") -> int:
	ensure(rig)
	if parent< -1 or parent>=rig.bones.size(): parent=-1
	var world := globals(rig.bones); var local := frame(head,end)
	if parent>=0 and parent<world.size(): local=world[parent].affine_inverse()*local
	var names := {}
	for bone in rig.bones: names[str(bone.name)]=true
	var unique := title; var number := 2
	while names.has(unique): unique=title+" "+str(number); number+=1
	var bone := {"id":ActorData.new_id(),"name":unique,"parent":parent,"length":maxf(.001,head.distance_to(end)),"radius":maxf(.025,head.distance_to(end)*.3),"connected":parent>=0 and tail(rig.bones[parent],world[parent]).distance_to(head)<.001,"roll":0.,"mirror_id":"","metadata":{}}
	set_rest(bone,local,false); rig.bones.append(bone); return rig.bones.size()-1

static func move_joint(rig: KiwiModelComponent, index: int, end: bool, position: Vector3, connected: bool=true) -> void:
	var world := globals(rig.bones); var heads := PackedVector3Array(); var tails := PackedVector3Array()
	var changed := {index:true}
	for i in rig.bones.size(): heads.append(world[i].origin); tails.append(tail(rig.bones[i],world[i]))
	if end:
		tails[index]=position
		if connected:
			for i in rig.bones.size():
				if int(rig.bones[i].parent)==index and rig.bones[i].get("connected",false): heads[i]=position; changed[i]=true
	else:
		heads[index]=position
		var parent := int(rig.bones[index].parent)
		if connected and parent>=0 and rig.bones[index].get("connected",false):
			tails[parent]=position; changed[parent]=true
			for i in rig.bones.size():
				if int(rig.bones[i].parent)==parent and rig.bones[i].get("connected",false): heads[i]=position; changed[i]=true
		elif not connected: rig.bones[index].connected=false
	for i in changed: world[i]=frame(heads[i],tails[i],float(rig.bones[i].get("roll",0.)))
	for i in rig.bones.size():
		var parent := int(rig.bones[i].parent)
		if changed.has(i): rig.bones[i].length=maxf(.001,heads[i].distance_to(tails[i]))
		set_rest(rig.bones[i],world[parent].affine_inverse()*world[i] if parent>=0 else world[i])

static func descendants(rig: KiwiModelComponent, index: int) -> PackedInt32Array:
	var result := PackedInt32Array([index]); var cursor := 0
	while cursor<result.size():
		for i in rig.bones.size():
			if int(rig.bones[i].parent)==result[cursor] and not result.has(i): result.append(i)
		cursor+=1
	return result

static func parent_bone(rig: KiwiModelComponent, index: int, parent: int, connect: bool=false) -> bool:
	if index<0 or index>=rig.bones.size() or parent< -1 or parent>=rig.bones.size() or parent==index or descendants(rig,index).has(parent): return false
	var world := globals(rig.bones); rig.bones[index].parent=parent; rig.bones[index].connected=connect and parent>=0
	set_rest(rig.bones[index],world[parent].affine_inverse()*world[index] if parent>=0 else world[index])
	if connect and parent>=0: move_joint(rig,index,false,tail(rig.bones[parent],world[parent]))
	return true

static func validate(bones: Array) -> PackedStringArray:
	var errors := PackedStringArray(); var names := {}; var ids := {}
	for i in bones.size():
		var bone: Dictionary=bones[i]; var parent := int(bone.get("parent",-1))
		if parent>=bones.size() or parent==i or parent< -1: errors.append("Invalid bone parent")
		var seen := {i:true}; var ancestor := parent
		while ancestor>=0 and ancestor<bones.size():
			if seen.has(ancestor): errors.append("Bone parenting cycle"); break
			seen[ancestor]=true; ancestor=int(bones[ancestor].get("parent",-1))
		var rest: Transform3D=bone.get("rest",Transform3D.IDENTITY)
		if not rest.origin.is_finite() or not rest.basis.is_finite() or absf(rest.basis.determinant())<.000001: errors.append("Invalid bone rest transform")
		if str(bone.get("name","")).is_empty() or names.has(str(bone.name)): errors.append("Duplicate or empty bone name")
		if str(bone.get("name","")).contains(":") or str(bone.get("name","")).contains("/"): errors.append("Unsupported bone name character")
		names[str(bone.get("name",""))]=true
		if bone.has("id"):
			if str(bone.id).is_empty() or ids.has(str(bone.id)): errors.append("Missing or duplicate bone identity")
			ids[str(bone.id)]=true
		for key in ["length","radius","roll"]:
			if bone.has(key) and (not is_finite(float(bone[key])) or (key in ["length","radius"] and float(bone[key])<=0.)): errors.append("Invalid bone "+key)
		for channel in ["position","rotation","scale"]:
			if not bone.get(channel,Vector3.ZERO) is Vector3 or not (bone.get(channel,Vector3.ZERO) as Vector3).is_finite(): errors.append("Invalid bone pose")
	return errors
