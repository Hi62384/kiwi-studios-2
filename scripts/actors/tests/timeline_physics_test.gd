extends SceneTree
var checks:=0
var failures:=0
var editor: ActorTimelineEditor
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func seek(time: float) -> void:
	editor.canvas.playhead=time; editor._evaluate_runtimes()
	while editor.physics.pending: await process_frame; editor._evaluate_runtimes()
func create(position: Vector3, config: Dictionary, values: Dictionary={}) -> ActorData:
	values=values.duplicate(); values[&"position"]=position
	var clip:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0,values)
	clip.start_time=0; clip.layer=editor.model.clips.size()-1; clip.duration=12
	var actor:=editor.model.selected_actor(); actor.values[&"physics"]=KiwiPhysicsSettings.DEFAULTS.duplicate(true); actor.values[&"physics"].merge(config,true); actor.values[&"physics"].enabled=true
	editor.model.changed.emit(); return actor
func pose(actor: ActorData) -> Transform3D: return editor.physics.display_states[actor.id].pose
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor)
	var viewport:=SubViewport.new(); viewport.size=Vector2i(640,480); root.add_child(viewport); editor.runtime_holder=Node3D.new(); viewport.add_child(editor.runtime_holder)
	var floor_actor:=create(Vector3(0,-.5,0),{"body_mode":1,"bounce":.0},{&"box_size":Vector3(20,1,20)})
	var ball:=create(Vector3(0,3,0),{"damping":0.0,"bounce":.6},{&"shape":1,&"sphere_radius":.5,&"sphere_height":1.0,&"sphere_radial_segments":12,&"sphere_rings":6})
	await seek(0); check(is_equal_approx(pose(ball).origin.y,3.0),"Physics begins at the authored pose")
	await seek(.5); check(pose(ball).origin.y<2.0 and pose(ball).origin.y>1.6,"Rigid body falls by fixed timeline time")
	var first_half:=pose(ball); var count:=editor.physics.steps_taken
	for i in 20: await process_frame
	check(editor.physics.steps_taken==count and pose(ball).is_equal_approx(first_half),"Paused timeline never advances the simulation")
	await seek(1.2); check(pose(ball).origin.y>.49,"Native swept collision prevents falling through the floor")
	await seek(.5); check(pose(ball).is_equal_approx(first_half),"Scrubbing backward restores the correct historical rigid pose")
	await seek(3); var at_three:=pose(ball)
	editor.physics.signature=""; editor.physics.mark_dirty(); await seek(3)
	check(pose(ball).is_equal_approx(at_three),"Jumping directly to a time matches uninterrupted fixed-step replay")
	count=editor.physics.steps_taken; await seek(3)
	check(editor.physics.steps_taken==count,"Repeated sampling of the same time does not simulate again")
	var generation:=editor.physics.generation
	editor.model.rename_actor(ball,"Renamed ball"); await seek(3)
	check(editor.physics.generation==generation,"Renaming an actor does not invalidate simulation state")
	KiwiPhysicsSettings.edit(editor.model,ball,"gravity",3.0); await seek(.5)
	check(editor.physics.generation>generation and pose(ball).origin.y>first_half.origin.y,"Physics edits invalidate dependent checkpoints")
	editor.model.undo(); await seek(.5); check(pose(ball).is_equal_approx(first_half),"Undo restores the prior physics and recalculates correctly")
	editor.model.redo(); await seek(.5); check(pose(ball).origin.y>first_half.origin.y,"Physics configuration changes redo")
	var timed:=create(Vector3(4,4,0),{"activation":2.0,"collision":false,"inherit_velocity":false,"damping":0.0})
	await seek(1); check(is_equal_approx(pose(timed).origin.y,4.0),"Physics does not accumulate before its activation time")
	await seek(2); check(is_equal_approx(pose(timed).origin.y,4.0),"Activation initializes from the exact release pose")
	await seek(2.5); check(pose(timed).origin.y<3.0 and pose(timed).origin.y>2.6,"Physics advances after the release window begins")
	var cube:=create(Vector3(-4,2,0),{"type":2,"stiffness":20.0,"position_limit":1.0,"collision":false})
	await seek(1); check(pose(cube).origin.y<1.95 and pose(cube).origin.y>1.0,"Object jiggle responds to gravity with a bounded spring offset")
	var cloth:=create(Vector3(0,4,3),{"type":4,"pin_region":1,"collision":false,"particles":64,"stretch":.9,"bend":.05,"wind":Vector3(0,0,5)},{&"shape":4,&"plane_size":Vector2(2,2),&"plane_orientation":2,&"plane_subdivide_width":5,&"plane_subdivide_depth":5})
	await seek(.6); var cloth_state: Dictionary=editor.physics.display_states[cloth.id]; var graph: Dictionary=editor.physics.prototypes[cloth.id].graph
	check(cloth_state.points.size()>3,"Cloth uses a real multi-point deformation mesh")
	var deformation:=0.0
	for i in cloth_state.points.size(): deformation=maxf(deformation,cloth_state.points[i].distance_to(graph.rest[i]))
	check(deformation>.05,"Cloth vertices visibly deform instead of moving as one rigid object")
	var cloth_points: PackedVector3Array=cloth_state.points.duplicate(); await seek(1.1); await seek(.6)
	check(editor.physics.display_states[cloth.id].points==cloth_points,"Seeking restores the complete cloth configuration")
	var runtime:=editor._runtime_for_clip(editor.model.clip_for_actor_id(cloth.id).id)
	check(runtime.content.mesh is ArrayMesh,"Cloth solver changes the actual viewport render mesh")
	var rope:=create(Vector3(4,4,3),{"type":5,"rope_start":true,"rope_end":false,"rope_points":12,"rope_length":2.0,"collision":false,"wind":Vector3(3,0,0)})
	await seek(.8); var rope_state: Dictionary=editor.physics.display_states[rope.id]
	check(rope_state.points.size()==12 and rope_state.points[0].distance_to(Vector3(4,4,3))<.001,"Rope has simulated points and a fixed start attachment")
	check(is_instance_valid(editor.physics.prototypes[rope.id].rope_node) and editor.physics.prototypes[rope.id].rope_node.mesh.get_surface_count()==1,"Rope is rendered as actual 3D tube geometry")
	var rope_error:=0.0
	for i in 11: rope_error=maxf(rope_error,absf(rope_state.points[i].distance_to(rope_state.points[i+1])-2.0/11))
	check(rope_error<.08,"Rope distance constraints preserve its approximate length")
	var soft:=create(Vector3(-3,3,3),{"type":1,"collision":true,"particles":64,"stretch":.7,"recovery":5.0},{&"box_subdivide_width":2,&"box_subdivide_height":2,&"box_subdivide_depth":2})
	await seek(1); var soft_state: Dictionary=editor.physics.display_states[soft.id]
	check(soft_state.points.size()>8,"Soft bodies retain independent deforming simulation points")
	check(Array(soft_state.points).any(func(p: Vector3): return p.y>.4),"Soft-body points collide with the rigid floor")
	var relative_deformation:=0.0; var soft_rest: PackedVector3Array=editor.physics.prototypes[soft.id].graph.rest
	for time in [.65,.7,.75,.8,1.0]:
		await seek(time); soft_state=editor.physics.display_states[soft.id]
		for i in soft_state.points.size(): relative_deformation=maxf(relative_deformation,(soft_state.points[i]-soft_rest[i]).distance_to(soft_state.points[0]-soft_rest[0]))
	check(relative_deformation>.005,"Soft-body floor contacts produce non-rigid elastic deformation")
	var rig_clip:=editor.model.create_actor(editor.registry.get_definition(&"skeleton_rig"),0)
	rig_clip.start_time=0; rig_clip.layer=editor.model.clips.size()-1; rig_clip.duration=12
	var rig:=editor.model.selected_actor(); rig.values[&"rig_bones"]=[{"name":"Root","parent":-1,"rest":Transform3D.IDENTITY,"position":Vector3.ZERO,"rotation":Vector3.ZERO,"scale":Vector3.ONE},{"name":"Tail","parent":0,"rest":Transform3D(Basis.IDENTITY,Vector3(0,1,0)),"position":Vector3.ZERO,"rotation":Vector3.ZERO,"scale":Vector3.ONE},{"name":"Arm","parent":0,"rest":Transform3D(Basis.IDENTITY,Vector3(1,0,0)),"position":Vector3.ZERO,"rotation":Vector3.ZERO,"scale":Vector3.ONE}]
	rig.values[&"physics"]=KiwiPhysicsSettings.DEFAULTS.duplicate(true); rig.values[&"physics"].merge({"enabled":true,"type":3,"bones":["Tail"],"gravity_direction":Vector3.RIGHT,"gravity":8.0,"collision":false},true); editor._recreate_runtimes(); editor.model.changed.emit()
	await seek(.7); var rig_runtime:=editor._runtime_for_clip(rig_clip.id) as ActorSkeletonRigRuntime
	check(editor.physics.display_states[rig.id].bones.size()==1 and editor.physics.display_states[rig.id].bones.has("Tail"),"Skeleton physics affects only explicitly selected bones")
	check(not rig_runtime.skeleton.get_bone_pose_rotation(1).is_equal_approx(Quaternion.IDENTITY),"Selected skeleton bone visibly responds to physics")
	check(rig_runtime.skeleton.get_bone_pose_rotation(2).is_equal_approx(Quaternion.IDENTITY),"Unselected bones retain ordinary animation")
	var bone_pose:=rig_runtime.skeleton.get_bone_pose_rotation(1); await seek(1.2); await seek(.7)
	check(rig_runtime.skeleton.get_bone_pose_rotation(1).is_equal_approx(bone_pose),"Skeleton simulation restores its earlier pose on rewind")
	KiwiPhysicsSettings.edit(editor.model,rig,"enabled",false); await seek(.7)
	check(rig_runtime.skeleton.get_bone_pose_rotation(1).is_equal_approx(Quaternion.IDENTITY),"Disabling skeleton physics restores its base animation")
	await seek(.6); var live_cloth: PackedVector3Array=editor.physics.display_states[cloth.id].points.duplicate()
	var bake_error: String=await editor.physics.bake(editor,cloth,0,1.2)
	check(bake_error.is_empty() and KiwiPhysicsSettings.authored(cloth).mode==4,"Physics bakes an interval as one authored transaction")
	await seek(.6)
	check(editor.physics.display_states[cloth.id].points==live_cloth,"Baked deformation matches the original live timeline state")
	var bake_path:="user://physics_bake_"+ActorData.new_id()+".tres"
	var baked_scene:=ActorSceneData.new(); baked_scene.actors.assign(editor.model.actors); baked_scene.clips.assign(editor.model.clips)
	check(ResourceSaver.save(baked_scene,bake_path)==OK,"Baked point states serialize in a native scene resource")
	var loaded_bake:=ResourceLoader.load(bake_path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	var signature_before:=KiwiPhysicsSettings.fingerprint(editor.model)
	var model_reload:=ActorTimeline.new(); model_reload.actors.assign(loaded_bake.actors); model_reload.clips.assign(loaded_bake.clips)
	check(KiwiPhysicsSettings.fingerprint(model_reload)==signature_before,"Physics bake signatures survive scene reload")
	check(KiwiPhysicsSettings.authored(loaded_bake.actors[editor.model.actors.find(cloth)]).bake.frames.size()>60,"Saved bake preserves full deformation frames, not just actor positions")
	editor.model.undo(); await seek(.6); check(KiwiPhysicsSettings.authored(cloth).mode==1,"Undo removes the bake and restores live simulation")
	editor.model.redo(); await seek(.6); check(editor.physics.display_states[cloth.id].points==live_cloth,"Redo restores an identical usable physics bake")
	KiwiPhysicsSettings.edit(editor.model,cloth,"wind",Vector3(5,0,0)); await seek(.6)
	check(editor.physics.status.contains("stale") and editor.physics.display_states[cloth.id].points!=live_cloth,"Changing a driver invalidates stale baked deformation")
	DirAccess.remove_absolute(bake_path)
	await seek(.8); editor.physics.freeze(editor.model,ball); await seek(2)
	var frozen:=pose(ball); await seek(3); check(pose(ball).is_equal_approx(frozen),"Freeze holds a complete world-space physics pose")
	var saved:=ActorSceneData.new(); saved.actors.assign(editor.model.actors); saved.clips.assign(editor.model.clips)
	var path:="user://physics_scene_"+ActorData.new_id()+".tres"; check(ResourceSaver.save(saved,path)==OK,"Scene saves all physics types and frozen states")
	var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	check(loaded.actors.size()==editor.model.actors.size() and KiwiPhysicsSettings.authored(loaded.actors[1]).enabled,"Scene reload preserves physics configuration")
	DirAccess.remove_absolute(path)
	editor.physics.dispose(); editor.queue_free(); viewport.queue_free(); for i in 4: await process_frame
	print("TIMELINE_PHYSICS checks=%d failures=%d"%[checks,failures]); quit(failures)
