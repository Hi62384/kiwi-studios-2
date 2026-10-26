class_name ActorSkeletonPose
extends RefCounted
## A complete gesture (including auto-keys) is one undo/redo transaction.
static func path(bone: int, channel: String) -> PackedStringArray:
	return PackedStringArray(["bone_poses",str(bone),channel])

static func value(actor: ActorData, bone: int, channel: String) -> Vector3:
	var address := path(bone,channel)
	var base: Variant=ActorAnimation.value_at_path(actor,address)
	return ActorAnimation.sampled_value(actor,address,actor.animation_time if not is_nan(actor.animation_time) else 0.,base)

static func capture(model: ActorTimeline, actor: ActorData) -> Dictionary:
	return {"actor":actor,"poses":ActorData.copy_value(actor.values.get(&"bone_poses",{})),"tracks":model.animation_snapshot(actor)}

static func restore(model: ActorTimeline, state: Dictionary) -> void:
	state.actor.values[&"bone_poses"]=ActorData.copy_value(state.poses)
	state.actor.animation_previews.clear(); model.restore_animation(state.actor,state.tracks)

static func preview(model: ActorTimeline, actor: ActorData, bone: int, channel: String, next: Vector3) -> void:
	model.preview_animation_value(actor,path(bone,channel),next)

static func commit(model: ActorTimeline, before: Dictionary, bone: int, changes: Dictionary, key_all: bool=false) -> void:
	var actor: ActorData=before.actor
	actor.animation_previews.clear()
	var modified := key_all
	for channel: String in changes:
		var address := path(bone,channel)
		var original: Variant=ActorAnimation.sampled_value(actor,address,actor.animation_time,ActorAnimation.value_at_path(actor,address))
		if not (original as Vector3).is_equal_approx(changes[channel]): modified=true
	if not modified: restore(model,before); return
	var was_batch := model.property_batch_active; model.property_batch_active=true
	var bones: Array=actor.values.get(&"rig_bones",[])
	for channel: String in changes:
		var address := path(bone,channel)
		if key_all or actor.animation_track(address)!=null:
			model.add_keyframe(actor,address,"Bones / "+str(bones[bone].name)+" / "+channel.capitalize(),changes[channel])
		else: actor.values[&"bone_poses"][str(bone)][channel]=changes[channel]
	model.property_batch_active=was_batch
	var after := capture(model,actor)
	model.history.create_action("Key Bone Pose" if key_all else "Transform Bone")
	model.history.add_do_method(restore.bind(model,after)); model.history.add_undo_method(restore.bind(model,before)); model.history.commit_action()

static func key_pose(model: ActorTimeline, actor: ActorData, bone: int) -> void:
	var changes := {}
	for channel in ["position","rotation","scale"]: changes[channel]=value(actor,bone,channel)
	commit(model,capture(model,actor),bone,changes,true)
