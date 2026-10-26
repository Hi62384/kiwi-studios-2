class_name ActorSkeletonRigRuntime
extends "res://scripts/actors/examples/point_actor.gd"
## Bones are runtime views of actor-owned poses; never edit the imported rig.
var skeleton: Skeleton3D

static func create_skeleton(bones: Array) -> Skeleton3D:
	var result := Skeleton3D.new(); result.name="Skeleton"
	for bone: Dictionary in bones: result.add_bone(str(bone.name))
	for i in bones.size():
		var bone: Dictionary=bones[i]
		result.set_bone_parent(i,int(bone.parent)); result.set_bone_rest(i,bone.rest)
		result.set_bone_pose_position(i,bone.position)
		result.set_bone_pose_rotation(i,Quaternion.from_euler((bone.rotation as Vector3)*PI/180.))
		result.set_bone_pose_scale(i,bone.scale)
	return result

func _ready() -> void:
	super._ready()
	skeleton=create_skeleton(actor.values.get(&"rig_bones",[])); transform_node.add_child(skeleton)
	add_to_group("actor_skeleton_rigs")

func evaluate_transform(values: Dictionary) -> void:
	super.evaluate_transform(values)
	# Like the actor transform, the pose must stay current even when only a
	# child mesh's clip is active outside the rig actor's own clip interval.
	var poses: Dictionary=values.get(&"bone_poses",{})
	var bones: Array=actor.values.get(&"rig_bones",[])
	for i in skeleton.get_bone_count():
		var pose: Dictionary=poses.get(str(i),bones[i] if i<bones.size() else {})
		if pose.is_empty(): continue
		skeleton.set_bone_pose_position(i,pose.position)
		skeleton.set_bone_pose_rotation(i,Quaternion.from_euler((pose.rotation as Vector3)*PI/180.))
		skeleton.set_bone_pose_scale(i,pose.scale)
	skeleton.force_update_all_bone_transforms()
