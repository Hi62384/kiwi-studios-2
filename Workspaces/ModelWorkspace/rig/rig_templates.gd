class_name KiwiRigTemplates
extends RefCounted
const CATEGORIES := {"Humanoid":["Humanoid","Simple humanoid"],"Animals":["Quadruped","Bird","Fish","Snake","Insect","Spider"],"Flexible":["Tail","Tentacle","Flexible chain","Branch","Long neck"],"Mechanical":["Hinged arm","Rotating shaft","Slider","Robot arm","Rigid assembly"]}

static func create(kind: String, bounds: AABB, count: int=6) -> KiwiModelComponent:
	return preload("res://Workspaces/ModelWorkspace/rig/RigTemplates.cs").new().create(kind,bounds,count)
