extends SceneTree
var checks:=0
var failures:=0
var editor: ActorTimelineEditor
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func settle(count: int=4) -> void:
	for i in count: await process_frame
func seek(time: float) -> void:
	editor.canvas.playhead=time; editor._evaluate_runtimes()
	while editor.physics.pending: await process_frame; editor._evaluate_runtimes()
func add(type: StringName, position: Vector3, config: Dictionary={}) -> ActorData:
	var clip:=editor.model.create_actor(editor.registry.get_definition(type),0,{&"position":position})
	clip.start_time=0; clip.layer=editor.model.clips.size()-1; clip.duration=10
	var actor:=editor.model.selected_actor()
	if not config.is_empty(): actor.values[&"physics"]=KiwiPhysicsSettings.DEFAULTS.duplicate(true); actor.values[&"physics"].merge(config,true)
	editor.model.changed.emit(); return actor
func key(actor: ActorData,path: PackedStringArray,time: float,value: Variant) -> void:
	var track:=actor.animation_track(path)
	if track==null: track=ActorAnimationTrack.new(); track.path=path; actor.animation_tracks.append(track)
	var frame:=ActorKeyframe.new(); frame.time=time; frame.value=value; track.keys.append(frame); track.sort_keys()
func runtime(actor: ActorData) -> ActorRuntime: return editor._runtime_for_clip(editor.model.clip_for_actor_id(actor.id).id)
func state(actor: ActorData) -> Dictionary: return editor.physics.display_states[actor.id]
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor)
	var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); root.add_child(viewport); editor.runtime_holder=Node3D.new(); viewport.add_child(editor.runtime_holder)
	var parent:=add(&"point_3d",Vector3.ZERO)
	key(parent,PackedStringArray(["position"]),0,Vector3.ZERO); key(parent,PackedStringArray(["position"]),2,Vector3(4,0,0))
	var ball:=add(&"basic_shape",Vector3(0,4,0),{"enabled":true,"collision":false,"damping":0.0,"activation":1.0,"inherit_velocity":true})
	ball.parent_id=parent.id; editor._recreate_runtimes(); editor.model.changed.emit()
	await seek(.5); check(is_equal_approx(runtime(ball).remote_transform().origin.x,1.0),"A child follows its animated parent before physics release")
	await seek(1); check(is_equal_approx(state(ball).pose.origin.x,2.0),"Released physics initializes in the parent's world space")
	await seek(1.5); check(absf(state(ball).pose.origin.x-3.0)<.005,"Release inherits the animated parent's velocity without double transforms")
	check(runtime(ball).remote_transform().is_equal_approx(state(ball).pose),"Viewport world pose matches solver pose under parenting")
	var jiggle:=add(&"basic_shape",Vector3(0,2,0),{"enabled":true,"type":2,"attachment":parent.id,"gravity":0.0,"collision":false,"stiffness":20.0,"position_limit":4.0})
	await seek(.8); check(state(jiggle).pose.origin.x>.1 and state(jiggle).pose.origin.x<2.5 and absf(state(jiggle).pose.origin.x-1.6)>.005,"Jiggle follows a moving animated attachment with secondary motion")
	var clipped:=add(&"basic_shape",Vector3(8,5,0),{"enabled":true,"collision":false,"inherit_velocity":false,"damping":0.0})
	var clip:=editor.model.clip_for_actor_id(clipped.id); clip.start_time=1; clip.source_offset=1; clip.playback_speed=2; editor.model.changed.emit()
	await seek(1)
	check(absf(state(clipped).pose.origin.y-.1)<.03,"Source offsets and playback speed replay the trimmed physics history")
	var driver:=add(&"point_3d",Vector3(0,5,3)); key(driver,PackedStringArray(["position"]),0,Vector3(0,5,3)); key(driver,PackedStringArray(["position"]),1,Vector3(1,5,3))
	var end:=add(&"point_3d",Vector3(2,5,3))
	var rope:=add(&"point_3d",Vector3(0,5,3),{"enabled":true,"type":5,"rope_start":true,"attachment":driver.id,"rope_end":true,"end_actor":end.id,"rope_length":3.0,"rope_points":16,"collision":false})
	await seek(.7)
	check(state(rope).points[0].distance_to(Vector3(.7,5,3))<.001 and state(rope).points[-1].distance_to(Vector3(2,5,3))<.001,"Both rope endpoints follow separate animated actor attachments")
	check(state(rope).points[8].y<4.95,"An attached rope bends under gravity rather than remaining a straight link")
	var impulse:=add(&"basic_shape",Vector3(12,3,0),{"enabled":true,"gravity":0.0,"damping":0.0,"collision":false,"inherit_velocity":false,"forces":[{"time":.5,"impulse":Vector3(2,0,0),"duration":0.0}]})
	await seek(.4); check(is_zero_approx(state(impulse).v.x),"Impulse events do not execute before their source time")
	await seek(.75); check(is_equal_approx(state(impulse).v.x,2.0),"A timed impulse executes once and changes body velocity")
	await seek(.2); await seek(.75); check(is_equal_approx(state(impulse).v.x,2.0),"Rewinding and replaying an impulse does not apply it twice")
	key(impulse,PackedStringArray(["physics","enabled"]),0,false); key(impulse,PackedStringArray(["physics","enabled"]),.5,true); editor.model.changed.emit()
	await seek(.25); check(not state(impulse).initialized,"Physics-enabled keyframes control activation on the ordinary timeline")
	await seek(.75); check(state(impulse).initialized,"Keyframed activation starts the actual solver")
	KiwiPhysicsSettings.edit(editor.model,impulse,"collision_only",true); await seek(.75)
	check(not runtime(impulse).content.visible,"Collision-only actors hide render geometry")
	editor.model.undo(); await seek(.75); check(runtime(impulse).content.visible,"Undoing collision-only restores the original actor visibility")
	var session:=KiwiModelSession.new(); var body:=session.add("Cylinder",{"radius":.4,"height":3.0}); body.title="Cloth garment"
	var author:=KiwiRigEditor.new(session); var armature:=author.create("Tentacle",4); armature.title="Cloth driver"; author.bind("Smooth")
	var source_path:="user://Physics cloth rig.tres"; ResourceSaver.save(session.document,source_path)
	editor.model.create_actor(editor.registry.get_definition(&"basic_mesh"),0,{&"mesh_path":source_path}); await settle()
	var garment: ActorData; var rig: ActorData
	for actor: ActorData in editor.model.actors:
		if actor.display_name==body.title: garment=actor
		if actor.display_name==armature.title: rig=actor
	for actor in [garment,rig]: editor.model.clip_for_actor_id(actor.id).start_time=0
	key(rig,PackedStringArray(["bone_poses","1","rotation"]),0,Vector3.ZERO); key(rig,PackedStringArray(["bone_poses","1","rotation"]),1,Vector3(0,0,50)); editor.model.changed.emit()
	await seek(1); await settle()
	var visual: MeshInstance3D=runtime(garment).content.get_child(0)
	var skin_before:=visual.skin; var mesh_before:=visual.mesh; var baked:=visual.bake_mesh_from_current_skeleton_pose()
	var expected: PackedVector3Array=baked.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var expected_world:=PackedVector3Array()
	for point in expected: expected_world.append(visual.global_transform*point)
	garment.values[&"physics"]=KiwiPhysicsSettings.DEFAULTS.duplicate(true); garment.values[&"physics"].merge({"enabled":true,"type":4,"activation":1.0,"collision":false,"particles":64},true); editor.model.changed.emit(); await seek(1)
	var mapping: PackedVector3Array=editor.physics.prototypes[garment.id].graph.bindings[0].surfaces[0].rest
	var error:=0.0
	for i in expected_world.size(): error=maxf(error,expected_world[i].distance_to(mapping[i]))
	check(error<.005,"Cloth handoff starts from the actual animated skinned pose, not the bind pose")
	await seek(1.3); check(visual.mesh is ArrayMesh and visual.skin==null,"Simulated cloth drives actual skinned render vertices")
	KiwiPhysicsSettings.edit(editor.model,garment,"enabled",false); await seek(1.3)
	check(visual.mesh==mesh_before and visual.skin==skin_before,"Disabling cloth cleanly restores the original mesh and skin binding")
	KiwiPhysicsSettings.edit(editor.model,rig,"enabled",true); KiwiPhysicsSettings.edit(editor.model,rig,"type",3); KiwiPhysicsSettings.edit(editor.model,rig,"bones",[str(armature.bones[1].name),str(armature.bones[2].name)]); KiwiPhysicsSettings.edit(editor.model,rig,"ragdoll",true); KiwiPhysicsSettings.edit(editor.model,rig,"collision",false)
	await seek(.8); var rig_runtime:=runtime(rig) as ActorSkeletonRigRuntime
	check(state(rig).bones.size()==2 and rig_runtime.skeleton.get_bone_pose_rotation(0).is_equal_approx(Quaternion.IDENTITY),"Partial ragdoll affects checked bones while the rest of the rig stays animated")
	var physical:=rig_runtime.skeleton.get_bone_pose_rotation(1)
	KiwiPhysicsSettings.edit(editor.model,rig,"influence",0.0); await seek(.8)
	var animated: Vector3=ActorAnimation.sampled_value(rig,PackedStringArray(["bone_poses","1","rotation"]),.8,Vector3.ZERO)
	check(rig_runtime.skeleton.get_bone_pose_rotation(1).is_equal_approx(Quaternion.from_euler(animated*PI/180.0)),"Zero skeleton influence restores the exact animated pose")
	check(not physical.is_equal_approx(rig_runtime.skeleton.get_bone_pose_rotation(1)),"Partial ragdoll and animation are visibly distinct states")
	var generation:=editor.physics.generation; garment.set_value(&"color",Color.RED); editor.model.changed.emit(); await seek(.8)
	check(editor.physics.generation==generation,"Unrelated appearance edits preserve existing simulation caches")
	KiwiPhysicsSettings.edit(editor.model,rig,"influence",1.0); KiwiPhysicsSettings.edit(editor.model,rig,"bones",armature.bones.map(func(bone: Dictionary): return str(bone.name)))
	await seek(.5)
	var root_name:=str(armature.bones[0].name)
	check(state(rig).bones[root_name].pose.origin.y<editor.physics.animated_world(rig.id,0).origin.y+float(armature.bones[0].position.y)-.5,"Full-body ragdoll can release the selected root instead of anchoring the whole skeleton")
	KiwiPhysicsSettings.edit(editor.model,rig,"bone_settings",{root_name:{"enabled":false}}); await seek(.5)
	check(rig_runtime.skeleton.get_bone_pose_position(0).is_equal_approx(armature.bones[0].position),"A per-bone enabled override leaves that bone under animation control")
	var hinge:=add(&"basic_shape",Vector3(15,3,0),{"enabled":true,"type":2,"ragdoll":true,"constraint":1,"axis":Vector3.BACK,"body_pivot":Vector3(0,.5,0),"limit":45.0,"angular_velocity":Vector3(0,0,150),"collision":false})
	await seek(.6)
	check((state(hinge).pose*Vector3(0,.5,0)).distance_to(Vector3(15,3,0))<.001,"Hinge constraints preserve their chosen body pivot")
	check(rad_to_deg(state(hinge).pose.basis.get_rotation_quaternion().get_angle())<=45.01,"Hinge motion respects the configured angular limit")
	var slider:=add(&"basic_shape",Vector3(18,3,0),{"enabled":true,"type":2,"ragdoll":true,"constraint":2,"axis":Vector3.RIGHT,"position_limit":.5,"gravity":0.0,"velocity":Vector3(5,2,3),"collision":false})
	await seek(.8)
	check(absf(state(slider).pose.origin.y-3.0)<.001 and absf(state(slider).pose.origin.z)<.001 and state(slider).pose.origin.x<=18.501,"Slider joints restrict motion to their axis and travel interval")
	var distance:=add(&"basic_shape",Vector3(21,3,0),{"enabled":true,"type":2,"ragdoll":true,"constraint":3,"distance":1.0,"velocity":Vector3(3,0,0),"collision":false})
	await seek(.6); check(absf(state(distance).pose.origin.distance_to(Vector3(21,3,0))-1.0)<.001,"Distance joints preserve a fixed attachment distance")
	await seek(.6); var pin_point: Vector3=state(rope).points[8]
	KiwiPhysicsSettings.pin(editor,rope,8,pin_point); await seek(.7)
	check(state(rope).points[8].distance_to(pin_point+Vector3(.1,0,0))<.005,"Intermediate rope pins preserve offsets to animated attachments")
	editor.model.undo(); await seek(.7); check(KiwiPhysicsSettings.authored(rope).pins.is_empty(),"Creating a viewport point pin is undoable")
	var platform:=add(&"basic_shape",Vector3(24,-.5,0),{"enabled":true,"body_mode":2})
	key(platform,PackedStringArray(["position"]),0,Vector3(24,-.5,0)); key(platform,PackedStringArray(["position"]),1,Vector3(24,.5,0))
	var carried:=add(&"basic_shape",Vector3(24,1.2,0),{"enabled":true,"gravity":0.0,"damping":0.0,"collision":true,"bounce":0.0})
	await seek(.9)
	check((PhysicsServer3D.body_get_state(editor.physics.world.bodies[platform.id].rid,PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D).is_equal_approx(state(platform).pose),"Inactive native query colliders update their actual transforms without engine ticks")
	check(state(carried).pose.origin.y>1.35 and state(carried).v.y>.2,"An animated collider pushes a dynamic body using its actual surface velocity")
	DirAccess.remove_absolute(source_path); editor.physics.dispose(); editor.queue_free(); viewport.queue_free(); await settle()
	print("PHYSICS_INTEGRATION checks=%d failures=%d"%[checks,failures]); quit(failures)
