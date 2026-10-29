class_name KiwiGrowthPhysics
extends RefCounted
## Adapter into the existing timeline point-constraint solver. No frame-delta loop.
static func data(actor: ActorData) -> KiwiSurfaceGrowthData:
	var component: Variant=actor.values.get(&"model_component_data")
	return component.growth if component is KiwiModelComponent else null
static func points(controller: KiwiTimelinePhysics,id: String,time: float) -> PackedVector3Array:
	var actor: ActorData=controller.prototypes[id].actor; var growth:=data(actor); var rig_id:=str(actor.values.get(&"model_skeleton_actor",""))
	if growth.source_skin==null or growth.source_weights.is_empty() or rig_id.is_empty(): return growth.source_points
	var rig: ActorData=controller._model.actor_for_id(rig_id)
	if rig==null: return growth.source_points
	var matrices: Array[Transform3D]=[]; var inverse:=controller.animated_world(rig_id,time,true).affine_inverse(); var bones: Array=rig.values.get(&"rig_bones",[])
	for i in growth.source_skin.get_bind_count():
		var index:=growth.source_skin.get_bind_bone(i); var name:=str(growth.source_skin.get_bind_name(i))
		if name.is_empty() and index>=0 and index<bones.size(): name=str(bones[index].name)
		matrices.append(inverse*controller.bone_world(rig_id,name,time)*growth.source_skin.get_bind_pose(i))
	var result:=PackedVector3Array(); result.resize(growth.source_points.size())
	for i in result.size():
		var total:=0.; var point:=Vector3.ZERO
		for bone: int in growth.source_weights[i]:
			if bone>=0 and bone<matrices.size(): point+=matrices[bone]*growth.source_points[i]*float(growth.source_weights[i][bone]); total+=float(growth.source_weights[i][bone])
		result[i]=point/total if total>.00001 else growth.source_points[i]
	return result
static func world(controller: KiwiTimelinePhysics,id: String,time: float) -> Transform3D:
	var actor: ActorData=controller.prototypes[id].actor; var growth:=data(actor); var rig_id:=str(actor.values.get(&"model_skeleton_actor",""))
	var rig: ActorData=controller._model.actor_for_id(rig_id)
	if rig!=null:
		var bones: Array=rig.values.get(&"rig_bones",[])
		if growth.rigid_bone>=0 and growth.rigid_bone<bones.size(): return controller.bone_world(rig_id,str(bones[growth.rigid_bone].name),time)*growth.rigid_offset
		if growth.source_skin!=null: return controller.animated_world(rig_id,time,true)
	return controller.animated_world(id,time,true)
static func initialize(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,time: float) -> void:
	var growth:=data(controller.prototypes[id].actor)
	if growth==null or growth.roots.is_empty(): return
	var controls: Array[Dictionary]=[]; var weights:={}; var authored:={}
	for guide_id: String in growth.guides:
		var guide: Dictionary=growth.guides[guide_id]
		for root: Dictionary in growth.roots:
			if int(root.id)==int(guide.root): controls.append({"id":guide_id,"root":root}); authored[guide_id]=true; break
		if controls.size()>=128: break
	if controls.is_empty():
		var count:=mini(128,maxi(1,int(config.get("particles",64))))
		for index in mini(count,growth.roots.size()):
			var root: Dictionary=growth.roots[index*growth.roots.size()/mini(count,growth.roots.size())]; controls.append({"id":"auto-"+str(root.id),"root":root})
	for root: Dictionary in growth.roots:
		var edit:=KiwiSurfaceGrowth.style(growth,root); var chosen: Dictionary=edit.get("guide_weights",{}).duplicate()
		if chosen.is_empty() and edit.get("guide","")!="": chosen[str(edit.guide)]=1.
		for key: String in chosen.keys():
			if not authored.has(key): chosen.erase(key)
		if chosen.is_empty():
			var nearby:=[]
			for control: Dictionary in controls: nearby.append([root.position.distance_squared_to(control.root.position),control.id])
			nearby.sort_custom(func(a: Array,b: Array): return float(a[0])<float(b[0]))
			for i in mini(4,nearby.size()): chosen[str(nearby[i][1])]=1./maxf(.0001,float(nearby[i][0]))
		weights[str(root.id)]=chosen
	var targets:=PackedVector3Array(); var edges:=[]; var source:=points(controller,id,time); var transform:=world(controller,id,time)
	for control: Dictionary in controls:
		var curve:=KiwiSurfaceGrowth.curve(growth,control.root,8); control.first=targets.size(); control.count=curve.size(); var frame:=transform*KiwiSurfaceGrowth.point_frame(growth,control.root,source)
		for point: Vector3 in curve: targets.append(frame*point)
		for i in curve.size()-1: edges.append([int(control.first)+i,int(control.first)+i+1,targets[int(control.first)+i].distance_to(targets[int(control.first)+i+1]),false])
		for i in curve.size()-2: edges.append([int(control.first)+i,int(control.first)+i+2,targets[int(control.first)+i].distance_to(targets[int(control.first)+i+2]),true])
	controller.prototypes[id].growth={"controls":controls,"weights":weights,"binding":hash([controls,weights])}
	controller.prototypes[id].graph={"rest":targets,"local":PackedVector3Array(),"edges":edges,"error":"","bindings":[]}
	state.points=targets.duplicate(); state.velocities.resize(targets.size()); state.velocities.fill(Vector3.ZERO); state.pose=transform
static func targets(controller: KiwiTimelinePhysics,id: String,time: float) -> Dictionary:
	var growth:=data(controller.prototypes[id].actor); var result:={}; var source:=points(controller,id,time); var transform:=world(controller,id,time)
	for control: Dictionary in controller.prototypes[id].get("growth",{}).get("controls",[]):
		var frame:=transform*KiwiSurfaceGrowth.point_frame(growth,control.root,source); var curve:=KiwiSurfaceGrowth.curve(growth,control.root,8)
		for i in mini(int(control.count),curve.size()): result[int(control.first)+i]=frame*curve[i]
	return result
static func pins(controller: KiwiTimelinePhysics,id: String,time: float) -> Dictionary:
	var desired:=targets(controller,id,time); var result:={}
	for control: Dictionary in controller.prototypes[id].get("growth",{}).get("controls",[]): result[int(control.first)]=desired[int(control.first)]
	return result
static func apply(controller: KiwiTimelinePhysics,id: String,state: Dictionary,config: Dictionary,time: float) -> void:
	var prototype: Dictionary=controller.prototypes[id]; var runtime:=controller._runtime(id)
	if runtime==null or not prototype.has("growth"): return
	var controls: Array=prototype.growth.controls; var motion:={}; var source:=points(controller,id,time); var transform:=world(controller,id,time); var growth:=data(prototype.actor)
	var actor: ActorData=prototype.actor; var local:=controller._local(actor,time); var overrides: Dictionary=ActorAnimation.sampled_values(actor,local).get(&"growth_overrides",{})
	for control: Dictionary in controls:
		var inverse: Transform3D=(transform*KiwiSurfaceGrowth.point_frame(growth,control.root,source)).affine_inverse(); var curve:=PackedVector3Array()
		var correction: Dictionary=overrides.get(str(control.id),{}); var from:=float(correction.get("from",0.)); var to:=float(correction.get("to",-1.)); var weight:=0.
		if local>=from and (to<0. or local<=to):
			weight=clampf(float(correction.get("influence",1.)),0,1)
			var blend:=maxf(0,float(correction.get("blend",.1)))
			if blend>0.: weight*=smoothstep(from,from+blend,local)*(1.-smoothstep(to-blend,to,local) if to>=0. else 1.)
		var sampled:=state
		if weight>0 and int(config.mode)==4:
			var at: float=float(correction.get("freeze_time",-1.))
			if at<0.: at=(time-float(config.bake.get("from",0.)))*float(correction.get("time_scale",1.))+float(config.bake.get("from",0.))+float(correction.get("time_offset",0.))
			if not is_equal_approx(at,time):
				var baked:=controller._baked(config.bake,clampf(at,float(config.bake.get("from",0.)),float(config.bake.get("to",time))))
				if not baked.is_empty(): sampled=baked
		var offset: Vector3=correction.get("offset",Vector3.ZERO); var rotation:=Basis.from_euler((correction.get("rotation",Vector3.ZERO) as Vector3)*PI/180.)
		var frozen: PackedVector3Array=config.frozen.get("growth_shapes",{}).get(str(control.id),PackedVector3Array()) if int(config.mode)==3 else PackedVector3Array()
		for i in int(control.count):
			var index:=int(control.first)+i
			if index<state.points.size():
				var original: Vector3=frozen[i] if i<frozen.size() else inverse*state.points[index]; var adjusted: Vector3=(frozen[i] if i<frozen.size() else inverse*sampled.points[index]) if index<sampled.points.size() else original; var t:=float(i)/maxi(1,int(control.count)-1)
				curve.append(original.lerp(rotation*adjusted+offset*t*t,weight) if i>0 else Vector3.ZERO)
		var target_curve:=KiwiSurfaceGrowth.curve(growth,control.root,maxi(1,curve.size()-1)); var delta:=PackedVector3Array()
		for i in curve.size(): delta.append(curve[i]-target_curve[i])
		motion[control.id]={"points":curve,"delta_points":delta,"influence":1.}
	for node: Node in runtime.find_children("*","MeshInstance3D",true,false):
		if node is KiwiSurfaceGrowthInstance:
			node.data.motion_guides=motion; node.data.motion_weights=prototype.growth.weights; node.data.motion_binding=int(prototype.growth.binding); node.data.motion_influence=clampf(float(config.influence),0,1); node.update_growth()
