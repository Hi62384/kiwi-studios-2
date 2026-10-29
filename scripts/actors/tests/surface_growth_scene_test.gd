extends "res://scripts/actors/tests/destruction_timeline_test.gd"
func run() -> void:
	var session:=KiwiModelSession.new(); var body:=session.add("Cylinder",{"radius":.4,"height":2.0,"segments":8}); var body_id:=body.id; var author:=KiwiRigEditor.new(session); var rig:=author.create("Tentacle",3); author.bind("Smooth"); session.select(body_id); KiwiSurfaceGrowth.add(session,1); var growth:=session.primary(); growth.title="Animated fur"; growth.growth.settings.density=25; session.document.prepare_growth(); var original_roots:=growth.growth.roots.duplicate(true)
	var tool:=KiwiGroomTool.new(); tool.tool="Comb"; tool.through=true; tool.radius=2; tool.apply_at(growth.growth,growth.growth.roots[0].position,Vector3(.2,0,0),Vector3.UP); growth.growth.groom_layers.append({"id":"style","tool":"Comb","enabled":true,"changes":growth.growth.pending.duplicate(true)}); growth.growth.pending.clear(); growth.growth.revision+=1
	var path:=ProjectSettings.globalize_path("user://Animated growth "+ActorData.new_id()+".tres"); ResourceSaver.save(session.document,path)
	editor=ActorTimelineEditor.new(); root.add_child(editor); var viewport:=SubViewport.new(); viewport.own_world_3d=true; viewport.size=Vector2i(640,400); root.add_child(viewport); editor.runtime_holder=Node3D.new(); viewport.add_child(editor.runtime_holder)
	editor.model.create_actor(editor.registry.get_definition(&"basic_mesh"),0,{&"mesh_path":path}); await process_frame; await process_frame; await seek(0)
	var fur: ActorData; var rig_actor: ActorData
	for actor: ActorData in editor.model.actors:
		if actor.display_name=="Animated fur": fur=actor
		if actor.type_id==&"skeleton_rig": rig_actor=actor
	check(fur!=null and rig_actor!=null,"A native model imports its growth and actual rig as separate scene actors")
	if fur==null or rig_actor==null: quit(1); return
	var clip:=editor.model.clip_for_actor_id(fur.id); var visual: KiwiSurfaceGrowthInstance=editor._runtime_for_clip(clip.id).content.get_child(0)
	check(visual.growth_skeleton!=null and visual.mesh.get_surface_count()>0,"Scene growth resolves the instantiated skeleton and renders actual geometry")
	var path_to_pose:=PackedStringArray(["bone_poses","1","rotation"]); editor.model.add_keyframe(rig_actor,path_to_pose,"Bend",Vector3.ZERO); editor.model.playhead_time=.8; editor.model.add_keyframe(rig_actor,path_to_pose,"Bend",Vector3(0,0,50))
	await seek(0); visual.update_growth(); var before: PackedVector3Array=visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]; await seek(.8); visual.update_growth(); var after: PackedVector3Array=visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var same_roots:=visual.data.roots.size()==original_roots.size()
	for i in mini(visual.data.roots.size(),original_roots.size()): same_roots=same_roots and visual.data.roots[i].id==original_roots[i].id and (visual.data.roots[i].bary as Vector3).is_equal_approx(original_roots[i].bary)
	check(before!=after and same_roots,"Scene keyframes deform groomed fur while preserving root identities and the authored groom")
	var chosen: Dictionary={}
	for root_data: Dictionary in visual.data.roots:
		if root_data.density_rank<=KiwiSurfaceGrowth.style(visual.data,root_data).density: chosen=root_data; break
	var posed:=KiwiSurfaceGrowth.posed_points(visual.data,visual.growth_skeleton); var expected:=KiwiSurfaceGrowth.point_frame(visual.data,chosen,posed).origin
	check(((after[0]+after[1])*.5).is_equal_approx(expected),"Rendered strand root is exactly on the corresponding animated barycentric surface")
	check(visual.global_transform.is_equal_approx(visual.growth_skeleton.global_transform),"Rig-space growth does not receive the component transform twice")
	var cache:=visual.mesh; await seek(.8); visual.update_growth(); check(visual.mesh==cache,"Paused skeletal playback reuses generated geometry instead of regenerating it")
	var snapshot:=editor.capture_scene_data(); var scene_path:="user://growth scene "+ActorData.new_id()+".tres"; ResourceSaver.save(snapshot,scene_path); var restored:=ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData; check(restored.actors.any(func(actor: ActorData): return actor.values.get(&"model_component_data") is KiwiModelComponent and actor.values.model_component_data.growth!=null),"Scene roundtrip retains the procedural and groomed component data")
	DirAccess.remove_absolute(scene_path); DirAccess.remove_absolute(path); editor.physics.dispose(); editor.model.history.clear_history(); editor.queue_free(); viewport.queue_free(); await process_frame
	print("SURFACE GROWTH SCENE: %d checks, %d failures"%[checks,failures]); quit(failures)
