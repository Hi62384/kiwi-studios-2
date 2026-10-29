extends "res://scripts/actors/tests/destruction_timeline_test.gd"
func run() -> void:
	editor=ActorTimelineEditor.new(); root.add_child(editor); var view:=SubViewport.new(); view.size=Vector2i(600,400); root.add_child(view); editor.runtime_holder=Node3D.new(); view.add_child(editor.runtime_holder)
	var cube:=add(&"basic_shape",{&"destruction_enabled":true}); cube.values.physics={"enabled":true,"gravity":0.0,"collision":false}; var op:=KiwiDestructionDefinition.operation(0,.2); op.impulse=0
	KiwiDestructionDefinition.edit(editor.model,cube,{"cut":op}); await seek(.4)
	check(state(cube).destruction_fragments.size()==2,"Directed fracture creates real fragments at the authored time")
	var original: PackedVector3Array=editor.physics.destruction.source(editor.physics,cube.id,state(cube)).mesh.vertices.duplicate(); var prepared:=editor.physics.destruction.builds; var first_id: String=state(cube).destruction_fragments[0].id
	op.impulse=2; KiwiDestructionDefinition.edit(editor.model,cube,{"cut":op}); await seek(.4)
	check(editor.physics.destruction.builds==prepared and state(cube).destruction_fragments[0].id==first_id,"Impulse edits reuse prepared geometry and preserve fragment IDs across recalculation")
	op.enabled=false; KiwiDestructionDefinition.edit(editor.model,cube,{"cut":op}); await seek(.4); check(not state(cube).get("destruction_detached",false),"Disabling an operation restores the intact source")
	op.enabled=true; op.impulse=0; KiwiDestructionDefinition.edit(editor.model,cube,{"cut":op}); await seek(.4)
	check(editor.physics.destruction.source(editor.physics,cube.id,state(cube)).mesh.vertices==original,"Setup edits never modify the original shared mesh")
	var protect:=KiwiDestructionDefinition.operation(13); protect.radius=.1; KiwiDestructionDefinition.edit(editor.model,cube,{"protect":protect,"cut":op}); await seek(.4)
	check(state(cube).destruction_fragments.size()==1,"A protected volume prevents a fracture plane cutting through it")
	check(is_inf(KiwiDestructionAuthoring.resistance({"p":protect},Vector3.ZERO)),"Protected impact regions reject physical damage")
	var weak:=KiwiDestructionDefinition.operation(12); check(KiwiDestructionAuthoring.resistance({"w":weak},Vector3.ZERO)<1,"Weakness regions lower physical resistance rather than adding decorative damage")
	KiwiDestructionDefinition.edit(editor.model,cube,{"cut":op}); await seek(.4); var key:=KiwiDestructionAuthoring.fragment_key(cube.id,first_id); var ids: Array=[key]
	KiwiDestructionAuthoring.edit_fragments(editor.model,cube,&"destruction_fragments",ids,"guided_target",Vector3(2,0,0)); await seek(.8)
	var guided_x: float=state(cube).destruction_fragments[0].pose.origin.x
	check(guided_x>0,"Force guidance changes a selected fragment trajectory")
	editor.model.undo(); await seek(.8); check(not cube.values.destruction_fragments.has(key),"One undo removes the entire target-drag action")
	KiwiDestructionAuthoring.edit_fragments(editor.model,cube,&"destruction_fragments",ids,"pin_until",.5); await seek(.4); var pinned: Transform3D=state(cube).destruction_fragments[0].pose
	await seek(.49); check(state(cube).destruction_fragments[0].pose==pinned,"Temporary pins hold the actual fragment until source release time")
	var setup:=KiwiDestructionAuthoring.capture_setup(editor.physics,cube); var second:=add(&"basic_shape",{&"destruction_enabled":true,&"position":Vector3(4,0,0)}); second.values.physics={"enabled":true,"gravity":0.0,"collision":false}; await seek(0)
	await process_frame; await seek(0)
	var setup_error:=KiwiDestructionAuthoring.apply_setup(editor.model,editor.physics,second,setup); print("SETUP ",setup_error," signatures=",setup.values.source_signature," / ",KiwiDestructionAuthoring.source_signature(editor.physics,second))
	check(setup_error.is_empty() and second.values.destruction_operations.has("cut"),"Reusable setup validates topology and copies independent authored settings")
	KiwiDestructionAuthoring.edit_fragments(editor.model,cube,&"destruction_fragments",ids,"impulse",Vector3(1,0,0)); KiwiDestructionAuthoring.edit_fragments(editor.model,cube,&"destruction_fragments",ids,"impulse_time",.55)
	var error:=await editor.physics.bake_group(editor,0,1,30); check(error.is_empty(),"Chunked group bake completes")
	var cache: KiwiPhysicsBakeCache=cube.values.physics.bake.cache
	check(cache.count==31 and cache.records.size()<=3 and cache.resources.size()<16,"Persistent bake interns unchanged geometry rather than repeating it per frame")
	check(second.values.physics.bake.cache==cache and int(second.values.physics.mode)==4,"Interacting actors share an atomic group bake")
	await seek(.8); var raw: Transform3D=state(cube).destruction_fragments[0].pose; var generation:=editor.physics.generation
	KiwiDestructionAuthoring.edit_fragments(editor.model,cube,&"destruction_overrides",ids,"offset",Vector3(0,2,0)); await seek(.8)
	check(state(cube).destruction_fragments[0].pose.origin.is_equal_approx(raw.origin+Vector3(0,2,0)) and editor.physics.generation==generation,"Post-bake offsets preserve simulation and its cache")
	await seek(.8); check(state(cube).destruction_fragments[0].pose.origin.is_equal_approx(raw.origin+Vector3(0,2,0)),"Paused correction does not accumulate its offset")
	KiwiDestructionAuthoring.key_fragments(editor.model,cube,&"destruction_overrides",ids,"offset",Vector3.ZERO)
	check(cube.animation_track(PackedStringArray(["destruction_overrides",key,"offset"]))!=null,"Fragment correction keys use the existing editable keyframe timeline")
	var path:="user://directed_"+ActorData.new_id()+".tres"; var scene:=editor.capture_scene_data(); check(ResourceSaver.save(scene,path)==OK,"Chunked group bake saves with ordinary scene resources")
	var reopened:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData; var saved_cache: KiwiPhysicsBakeCache=reopened.actors[0].values.physics.bake.cache
	check(saved_cache.frame(24)[cube.id].destruction_fragments[0].mesh is KiwiModelMesh,"Reopened compressed frames restore geometry resources and fragment topology")
	var old_cache: Resource=cube.values.physics.bake.cache
	error=await editor.physics.bake_group(editor,0,1,30,func(done: int,_total: int,_bytes: int):
		if done==2: editor.physics.cancel_bake())
	check(error.contains("canceled") and cube.values.physics.bake.cache==old_cache,"Canceled bake preserves the previous valid bake")
	KiwiDestructionAuthoring.edit_fragments(editor.model,cube,&"destruction_overrides",ids,"freeze_time",.6); await seek(.8); var hold: Transform3D=state(cube).destruction_fragments[0].pose; await seek(.9); check(state(cube).destruction_fragments[0].pose==hold,"Individual post-bake fragments can be frozen without discarding the original bake")
	var dependent:=op.duplicate(true); dependent.depends_on=["cut"]; KiwiDestructionDefinition.edit(editor.model,cube,{"cut":op,"dependent":dependent}); check(not KiwiDestructionAuthoring.operation_action(editor.model,cube,"dependent","Up").is_empty(),"Explicit geometry dependencies prevent invalid operation reordering")
	print("DIRECTED BAKE compressed=",cache.bytes," raw=",cache.raw_bytes," resources=",cache.resources.size()," geometry records=",cache.records.size())
	DirAccess.remove_absolute(path); editor.physics.dispose(); editor.queue_free(); view.queue_free(); await process_frame
	print("DESTRUCTION AUTHORING: %d checks, %d failures"%[checks,failures]); quit(failures)
