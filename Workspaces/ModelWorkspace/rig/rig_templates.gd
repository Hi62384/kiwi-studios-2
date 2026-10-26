class_name KiwiRigTemplates
extends RefCounted
const CATEGORIES := {"Humanoid":["Humanoid","Simple humanoid"],"Animals":["Quadruped","Bird","Fish","Snake","Insect","Spider"],"Flexible":["Tail","Tentacle","Flexible chain","Branch","Long neck"],"Mechanical":["Hinged arm","Rotating shaft","Slider","Robot arm","Rigid assembly"]}

static func create(kind: String, bounds: AABB, count: int=6) -> KiwiModelComponent:
	var rig := KiwiModelComponent.new(); rig.id=ActorData.new_id(); rig.title=kind+" Rig"; rig.is_skeleton=true
	var dimensions := bounds.size.max(Vector3.ONE*.1); var center := bounds.get_center()
	var point := func(x: float,y: float,z: float) -> Vector3: return center+Vector3(x,y,z)*dimensions
	if kind in ["Humanoid","Simple humanoid"]:
		var pelvis := KiwiRigMath.add_bone(rig,point.call(0,-.12,0),point.call(0,.08,0),-1,"pelvis")
		var spine := KiwiRigMath.add_bone(rig,point.call(0,.08,0),point.call(0,.30,0),pelvis,"spine")
		var neck := KiwiRigMath.add_bone(rig,point.call(0,.30,0),point.call(0,.37,0),spine,"neck")
		KiwiRigMath.add_bone(rig,point.call(0,.37,0),point.call(0,.49,0),neck,"head")
		for side in [-1.,1.]:
			var suffix := "_L" if side<0 else "_R"
			var arm := KiwiRigMath.add_bone(rig,point.call(side*.10,.29,0),point.call(side*.30,.23,0),spine,"upper_arm"+suffix)
			var forearm := KiwiRigMath.add_bone(rig,point.call(side*.30,.23,0),point.call(side*.44,.17,0),arm,"forearm"+suffix)
			if kind=="Humanoid": KiwiRigMath.add_bone(rig,point.call(side*.44,.17,0),point.call(side*.49,.15,0),forearm,"hand"+suffix)
			var thigh := KiwiRigMath.add_bone(rig,point.call(side*.09,-.10,0),point.call(side*.11,-.29,.01),pelvis,"thigh"+suffix)
			var shin := KiwiRigMath.add_bone(rig,point.call(side*.11,-.29,.01),point.call(side*.12,-.46,0),thigh,"shin"+suffix)
			if kind=="Humanoid": KiwiRigMath.add_bone(rig,point.call(side*.12,-.46,0),point.call(side*.12,-.48,-.13),shin,"foot"+suffix)
	elif kind in ["Quadruped","Bird","Insect","Spider"]:
		var torso := KiwiRigMath.add_bone(rig,point.call(0,0,.3),point.call(0,0,-.25),-1,"body")
		var head := KiwiRigMath.add_bone(rig,point.call(0,0,-.25),point.call(0,.12,-.45),torso,"head")
		if kind=="Quadruped": KiwiRigMath.add_bone(rig,point.call(0,0,.3),point.call(0,.1,.49),torso,"tail")
		var pairs := 4 if kind=="Spider" else (3 if kind=="Insect" else (1 if kind=="Bird" else 2))
		for i in pairs:
			var z := lerpf(-.25,.25,float(i)/maxi(1,pairs-1))
			for side in [-1.,1.]:
				var suffix := "_%d"%i+("_L" if side<0 else "_R")
				var upper := KiwiRigMath.add_bone(rig,point.call(side*.08,0,z),point.call(side*.28,.05 if kind in ["Spider","Insect"] else -.22,z),torso,"limb"+suffix)
				KiwiRigMath.add_bone(rig,KiwiRigMath.tail(rig.bones[upper],KiwiRigMath.globals(rig.bones)[upper]),point.call(side*(.46 if kind in ["Spider","Insect"] else .3),-.47,z-.04),upper,"tip"+suffix)
		if kind=="Bird":
			for side in [-1.,1.]: KiwiRigMath.add_bone(rig,point.call(side*.1,0,-.1),point.call(side*.49,.15,0),head,"wing_L" if side<0 else "wing_R")
	else:
		var axis := dimensions.max_axis_index(); var start := center; var end := center
		start[axis]-=dimensions[axis]*.48; end[axis]+=dimensions[axis]*.48
		if kind in ["Rotating shaft","Slider"]: count=1
		elif kind=="Hinged arm": count=2
		elif kind=="Robot arm": count=3
		var parent := -1
		for i in clampi(count,1,64):
			parent=KiwiRigMath.add_bone(rig,start.lerp(end,float(i)/clampi(count,1,64)),start.lerp(end,float(i+1)/clampi(count,1,64)),parent,"joint_%02d"%i)
		if kind=="Branch":
			var world := KiwiRigMath.globals(rig.bones)
			for i in range(1,rig.bones.size()-1,2): KiwiRigMath.add_bone(rig,world[i].origin,world[i].origin+Vector3(dimensions.x*.3,dimensions.y*.12,0),i,"branch_%d"%i)
	# Preset positions are approximate bounds fitting, not anatomical inference.
	KiwiRigMath.ensure(rig)
	for bone in rig.bones:
		if str(bone.name).ends_with("_L"):
			for other in rig.bones:
				if other.name==str(bone.name).trim_suffix("_L")+"_R": bone.mirror_id=other.id; other.mirror_id=bone.id
	return rig
