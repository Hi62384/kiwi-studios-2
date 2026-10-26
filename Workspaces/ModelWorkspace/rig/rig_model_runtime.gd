class_name KiwiRigModelRuntime
extends Node3D
## Keeps the original component-node hierarchy intact for native-model users
## while rigid parts follow bones, including children of those components.
var attachments: Array[Dictionary]=[]
func _ready() -> void: update_attachments()
func _process(_delta: float) -> void: update_attachments()
func update_attachments() -> void:
	for entry in attachments:
		var target: Node3D=entry.target; var skeleton: Skeleton3D=entry.skeleton
		if not is_instance_valid(target) or not is_instance_valid(skeleton) or not target.is_inside_tree(): continue
		skeleton.force_update_all_bone_transforms()
		target.global_transform=skeleton.global_transform*skeleton.get_bone_global_pose(int(entry.bone))*entry.offset
