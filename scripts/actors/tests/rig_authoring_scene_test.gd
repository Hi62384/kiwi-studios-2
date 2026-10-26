extends SceneTree
var failures := 0
var checks := 0
var editor: ActorTimelineEditor
func _initialize() -> void: run.call_deferred()
func check(ok: bool, title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func settle() -> void:
	for i in 5: await process_frame
func named(title: String) -> ActorData:
	for actor in editor.model.actors:
		if actor.display_name==title: return actor
	return null
func runtime(actor: ActorData) -> ActorRuntime: return editor._runtime_for_clip(editor.model.clip_for_actor_id(actor.id).id)
func run() -> void:
	var session := KiwiModelSession.new(); var body := session.add("Cylinder",{"radius":.4,"height":4.}); body.title="Skinned body"
	var author := KiwiRigEditor.new(session); var rig := author.create("Tentacle",4); rig.title="Authored armature"; author.bind("Smooth")
	var part := session.add("Gear",{},Vector3(.8,1.,0)); part.title="Rigid gear"; author.selected_bone=2; author.bind("Rigid")
	# Non-trivial scene/node transforms must not double-transform skin vertices.
	var container := KiwiModelComponent.new(); container.id=ActorData.new_id(); container.title="Model root"; container.transform=Transform3D(Basis.from_euler(Vector3(.1,.2,-.1))*Basis.from_scale(Vector3(1.2,1.1,.9)),Vector3(1,.2,-.4)); session.document.components.append(container)
	for item in [body,rig,part]: item.parent_id=container.id
	check(session.document.validate().is_empty(),"Authored mixed rig has a valid transformed component hierarchy")
	var path := ProjectSettings.globalize_path("user://Authored Scene Rig.tres"); ResourceSaver.save(session.document,path)
	var model_runtime := session.document.instantiate_model() as KiwiRigModelRuntime; root.add_child(model_runtime); await settle()
	var nodes := {}
	for node: Node3D in model_runtime.find_children("*","Node3D",true,false):
		if node.has_meta("kiwi_component_id"): nodes[str(node.get_meta("kiwi_component_id"))]=node
	var skeleton: Skeleton3D=nodes[rig.id]; var bone_rest := skeleton.get_bone_pose_rotation(2); var gear_before: Transform3D=nodes[part.id].global_transform
	skeleton.set_bone_pose_rotation(2,Quaternion(Vector3.BACK,.7)*bone_rest); await settle()
	check(not (nodes[part.id].global_transform as Transform3D).is_equal_approx(gear_before),"Direct native model instantiation updates real rigid attachments")
	check(nodes[part.id].get_parent()==nodes[container.id],"Rigid follow behavior preserves the original component-node hierarchy")
	model_runtime.queue_free(); await settle()
	editor=ActorTimelineEditor.new(); root.add_child(editor); editor.hide()
	var holder := Node3D.new(); root.add_child(holder); editor.runtime_holder=holder
	editor.model.create_actor(editor.registry.get_definition(&"basic_mesh"),0,{&"mesh_path":path}); await settle()
	var rig_actor := named("Authored armature"); var body_actor := named("Skinned body"); var gear_actor := named("Rigid gear")
	check(rig_actor!=null and rig_actor.type_id==&"skeleton_rig","Authored skeleton imports as an editable Skeleton Rig actor")
	var rig_runtime := runtime(rig_actor) as ActorSkeletonRigRuntime; var body_runtime := runtime(body_actor); var gear_runtime := runtime(gear_actor)
	var visual := body_runtime.content.get_child(0) as MeshInstance3D
	check(visual.skin!=null and visual.get_node(visual.skeleton)==rig_runtime.skeleton,"Scene body resolves the newly instantiated armature skin")
	check(visual.global_transform.is_equal_approx(rig_runtime.skeleton.global_transform),"Rig-local generated vertices are not double-transformed by model hierarchy")
	var bind_world: Transform3D=gear_runtime.content.global_transform; var expected := session.document.world_transform(part)
	check(bind_world.is_equal_approx(expected),"Scene rigid part starts at its exact original affine transform")
	editor.model.select(editor.model.clip_for_actor_id(rig_actor.id).id); await settle()
	var pose: Dictionary=rig_actor.values[&"bone_poses"]["2"]; var original: Vector3=pose.rotation
	ActorSkeletonPose.key_pose(editor.model,rig_actor,2)
	editor.canvas.playhead=2.; editor._evaluate_runtimes(); await settle()
	ActorSkeletonPose.commit(editor.model,ActorSkeletonPose.capture(editor.model,rig_actor),2,{"rotation":original+Vector3(0,0,70)})
	editor.canvas.playhead=1.; editor._evaluate_runtimes(); await settle()
	check(rig_actor.animation_tracks.size()==3 and rig_actor.animation_track(ActorSkeletonPose.path(2,"rotation")).keys.size()==2,"Authored rig uses the existing scene bone keyframe tracks")
	check(not (gear_runtime.content.global_transform as Transform3D).is_equal_approx(bind_world),"Rigid mechanical part follows animated bone poses in the scene")
	var count := rig_runtime.skeleton.get_bone_count(); var rest: Transform3D=KiwiRigMath.globals(rig.bones)[2]
	var expected_gear: Transform3D=rig_runtime.skeleton.global_transform*rig_runtime.skeleton.get_bone_global_pose(2)*rest.affine_inverse()*rig_runtime.skeleton.global_transform.affine_inverse()*bind_world
	check(count==4 and (gear_runtime.content.global_transform as Transform3D).is_equal_approx(expected_gear),"Rigid scene transform matches the animated bone's exact rest-to-pose delta")
	var baked: ArrayMesh=visual.bake_mesh_from_current_skeleton_pose(); check(baked!=null and baked.get_surface_count()>0,"Scene GPU skin can be evaluated for frame rendering")
	editor._evaluate_runtimes(); await settle(); check((gear_runtime.content.global_transform as Transform3D).is_equal_approx(expected_gear),"Repeated evaluation never accumulates rigid bone transforms")
	var saved := "user://Authored Animation.tres"; ResourceSaver.save(editor.capture_scene_data(),saved); editor.restore_scene_data(ResourceLoader.load(saved,"",ResourceLoader.CACHE_MODE_IGNORE)); await settle()
	rig_actor=named("Authored armature"); gear_actor=named("Rigid gear")
	check(rig_actor.animation_tracks.size()==3 and (runtime(gear_actor).content.global_transform as Transform3D).is_equal_approx(expected_gear),"Scene roundtrip preserves authored bone animation and rigid attachments")
	# Editing source rests must not pair a new skin with an old animated scene rig.
	var revised := session.document.snapshot(); var revised_rig := revised.component(rig.id)
	KiwiRigMath.move_joint(revised_rig,1,true,KiwiRigMath.tail(revised_rig.bones[1],KiwiRigMath.globals(revised_rig.bones)[1])+Vector3(.4,0,0)); KiwiRigEditor.refresh_bindings(revised,revised_rig); ResourceSaver.save(revised,path)
	call_group("actor_shader_runtimes","refresh_saved_model",path); editor._evaluate_runtimes(); await settle()
	var body_visual := runtime(named("Skinned body")).content.get_child(0) as MeshInstance3D
	var original_skin: Skin=(named("Skinned body").values[&"model_component_data"] as KiwiModelComponent).skin
	check(body_visual.skin.get_bind_pose(2).is_equal_approx(original_skin.get_bind_pose(2)),"Scene rigs retain their compatible skin snapshot when source rest structure changes")
	check((runtime(gear_actor).content.global_transform as Transform3D).is_equal_approx(expected_gear),"Source rig edits never corrupt existing scene bone animation or rigid attachments")
	editor.restore_scene_data(ResourceLoader.load(saved,"",ResourceLoader.CACHE_MODE_IGNORE)); await settle()
	var reopened_visual := runtime(named("Skinned body")).content.get_child(0) as MeshInstance3D
	check(reopened_visual.skin.get_bind_pose(2).is_equal_approx(original_skin.get_bind_pose(2)),"Reopening a previously saved scene still restores its compatible embedded skin after source rig edits")
	editor.queue_free(); holder.queue_free(); await settle()
	print("RIG_AUTHORING_SCENE checks=%d failures=%d"%[checks,failures]); quit(failures)
