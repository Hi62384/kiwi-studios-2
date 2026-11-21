class_name KiwiRigMath
extends RefCounted
const Native=preload("res://Workspaces/ModelWorkspace/rig/RigMath.cs")
static var _native: RefCounted=Native.new()
# Default-argument/static facade retained until the remaining GDScript consumers migrate.
static func ensure(rig: KiwiModelComponent) -> void: _native.ensure(rig)
static func globals(bones: Array, pose: bool=false) -> Array[Transform3D]: return _native.globals(bones,pose)
static func bind_signature(bones: Array) -> int: return _native.bind_signature(bones)
static func tail(bone: Dictionary, global: Transform3D) -> Vector3: return _native.tail(bone,global)
static func frame(head: Vector3, end: Vector3, roll: float=0.) -> Transform3D: return _native.frame(head,end,roll)
static func set_rest(bone: Dictionary, local: Transform3D, keep_pose: bool=true) -> void: _native.set_rest(bone,local,keep_pose)
static func add_bone(rig: KiwiModelComponent, head: Vector3, end: Vector3, parent: int=-1, title: String="Bone") -> int: return _native.add_bone(rig,head,end,parent,title)
static func move_joint(rig: KiwiModelComponent, index: int, end: bool, position: Vector3, connected: bool=true) -> void: _native.move_joint(rig,index,end,position,connected)
static func descendants(rig: KiwiModelComponent, index: int) -> PackedInt32Array: return _native.descendants(rig,index)
static func parent_bone(rig: KiwiModelComponent, index: int, parent: int, connect: bool=false) -> bool: return _native.parent_bone(rig,index,parent,connect)
static func validate(bones: Array) -> PackedStringArray: return _native.validate(bones)

static func duplicate_chain(rig: KiwiModelComponent, chosen: PackedInt32Array, reflect: bool, axis: int, offset: float) -> void: _native.duplicate_chain(rig,chosen,reflect,axis,offset)

static func fit_to_bounds(rig: KiwiModelComponent, target: AABB) -> void: _native.fit_to_bounds(rig,target)

static func capture_preset(preset: Resource, rig: KiwiModelComponent) -> void: _native.capture_preset(preset,rig)
static func create_preset_armature(preset: Resource, fit: bool, target: AABB) -> KiwiModelComponent: return _native.create_preset_armature(preset,fit,target)
