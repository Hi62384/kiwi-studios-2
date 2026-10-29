extends "res://scripts/actors/tests/destruction_timeline_test.gd"
func run() -> void:
	var session:=KiwiModelSession.new(); session.add("Plane",{"size":Vector3(1,1,1)}); KiwiSurfaceGrowth.add(session,0); var item:=session.primary(); item.title="Moving hair"; item.growth.settings.length=.5; item.growth.settings.density=45.; session.document.prepare_growth()
	var path:="user://growth physics.tres"; ResourceSaver.save(session.document,path)
	editor=ActorTimelineEditor.new(); root.add_child(editor); var viewport:=SubViewport.new(); viewport.own_world_3d=true; viewport.size=Vector2i(600,400); root.add_child(viewport); editor.runtime_holder=Node3D.new(); viewport.add_child(editor.runtime_holder)
	editor.model.create_actor(editor.registry.get_definition(&"basic_mesh"),0,{&"mesh_path":path}); await process_frame; await process_frame
	var actor: ActorData
	for candidate: ActorData in editor.model.actors:
		if candidate.display_name=="Moving hair": actor=candidate
	check(actor!=null,"Imported growth actor available for guide physics")
	if actor==null: quit(1); return
	actor.values.physics={"enabled":true,"gravity":2.,"wind":Vector3(2,0,0),"collision":false,"particles":8,"recovery":5.,"radius":.01}
	editor.physics.mark_dirty()
	await seek(0); var initial: PackedVector3Array=state(actor).points.duplicate(); await seek(.5); var moved: PackedVector3Array=state(actor).points.duplicate()
	check(initial.size()==72 and moved!=initial,"Guide-based growth uses existing fixed-step point simulation")
	var pinned:=KiwiGrowthPhysics.pins(editor.physics,actor.id,.5); var attached:=true
	for index: int in pinned: attached=attached and state(actor).points[index].is_equal_approx(pinned[index])
	check(attached,"Every simulated guide root remains attached to its source surface")
	var visual: KiwiSurfaceGrowthInstance=editor._runtime_for_clip(editor.model.clip_for_actor_id(actor.id).id).content.get_child(0)
	check(not visual.data.motion_guides.is_empty() and visual.data.motion_guides.size()==8,"Rendered strands receive actual guide motion")
	var steps:=editor.physics.steps_taken; await seek(.5); check(editor.physics.steps_taken==steps and state(actor).points==moved,"Pause never advances guide simulation")
	await seek(.1); await seek(.5); check(state(actor).points==moved,"Seeking restores deterministic guide motion")
	var error:=await editor.physics.bake_group(editor,0,1,30); check(error.is_empty(),"Guide simulation bakes through the shared physics controller: "+error)
	var cache: KiwiPhysicsBakeCache=actor.values.physics.bake.cache
	check(cache.frame(15)[actor.id].points==moved,"Baked guide positions exactly match the simulation")
	await seek(.5); var generation:=editor.physics.generation; var original_mesh:=visual.mesh
	var component: KiwiModelComponent=actor.values.model_component_data; component.growth.appearance.mode=1; component.growth.appearance.root_color=Color.RED
	editor.physics.mark_dirty()
	await seek(.5); check(editor.physics.generation==generation and state(actor).points==moved,"Appearance-only edits preserve simulation and baked motion")
	component.growth.settings.quality=3; editor.physics.mark_dirty(); await seek(.5); check(editor.physics.generation==generation,"Rendering detail does not change fixed guide topology")
	var control: Dictionary=editor.physics.prototypes[actor.id].growth.controls[0]; var guide_id: String=control.id; var baseline: PackedVector3Array=visual.data.motion_guides[guide_id].points.duplicate()
	KiwiDestructionAuthoring.edit_fragments(editor.model,actor,&"growth_overrides",[guide_id],"offset",Vector3(0,0,1)); await seek(.5)
	check(visual.data.motion_guides[guide_id].points[-1].is_equal_approx(baseline[-1]+Vector3(0,0,1)) and cache.frame(15)[actor.id].points==moved,"Post-bake lock offset changes rendered motion without editing the original bake")
	editor.model.undo(); await seek(.5); check(visual.data.motion_guides[guide_id].points==baseline,"Guide correction is undoable as one action")
	var color_path:=PackedStringArray(["growth_root_color"]); editor.model.playhead_time=0.; editor.model.add_keyframe(actor,color_path,"Hair roots",Color.RED); editor.model.playhead_time=1.; editor.model.add_keyframe(actor,color_path,"Hair roots",Color.BLUE)
	await seek(.5); check(visual.data.appearance.root_color.is_equal_approx(Color(.5,0,.5)) and editor.physics.generation==generation,"Appearance keyframes animate the live material without invalidating the guide bake")
	var frozen_shape: PackedVector3Array=visual.data.motion_guides[guide_id].points.duplicate(); editor.physics.freeze(editor.model,actor)
	var parent_actor:=editor.model.actor_for_id(actor.parent_id)
	if parent_actor!=null: editor.model.edit_property(parent_actor,editor.registry.get_definition(parent_actor.type_id),&"position",Vector3(2,0,0))
	await seek(.8)
	check(visual.data.motion_guides[guide_id].points==frozen_shape and visual.data.motion_guides[guide_id].points[0]==Vector3.ZERO,"Frozen guide shape follows a moved source while keeping its root attached")
	editor.model.undo(); editor.model.undo(); await seek(.5)
	var custom:=editor.registry.get_object_definition(&"shader_material").create_object(); var shader:=Shader.new(); shader.code="shader_type spatial; uniform float gain=.2; void fragment(){ALBEDO=vec3(gain+TIME*.001);}"; custom.set_value(&"shader_path",shader); custom.set_value(&"uniforms",{&"gain":.2}); actor.values.growth_custom_material=ActorObjectReference.from_object(custom); actor.values.growth_rendering_mode=2
	var gain_path:=PackedStringArray(["growth_custom_material","uniforms","gain"]); editor.model.playhead_time=0.; editor.model.add_keyframe(actor,gain_path,"Custom growth gain",.2); editor.model.playhead_time=1.; editor.model.add_keyframe(actor,gain_path,"Custom growth gain",.8); await seek(.5)
	check(visual.material_override is ShaderMaterial and is_equal_approx(float(visual.material_override.get_shader_parameter("gain")),.5),"Existing nested shader-uniform keyframes drive the custom growth material")
	var time_name:=str(visual.material_override.get_meta("kiwi_time_uniform","")); check(not time_name.is_empty() and is_equal_approx(float(visual.material_override.get_shader_parameter(time_name)),.5),"Custom growth shader TIME samples the same scene time during playback")
	var saved:=editor.capture_scene_data(); ResourceSaver.save(saved,"user://growth physics scene.tres"); var loaded:=ResourceLoader.load("user://growth physics scene.tres","",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	check(loaded.actors.any(func(a: ActorData): return a.values.get(&"physics",{}).get("bake",{}).get("cache") is KiwiPhysicsBakeCache),"Scene roundtrip retains reusable guide bake")
	print("GROWTH BAKE points=",initial.size()," roots=",component.growth.roots.size()," bytes=",cache.bytes)
	editor.physics.dispose(); editor.queue_free(); viewport.queue_free(); await process_frame; DirAccess.remove_absolute(path); DirAccess.remove_absolute("user://growth physics scene.tres")
	print("GROWTH PHYSICS: %d checks, %d failures"%[checks,failures]); quit(failures)
