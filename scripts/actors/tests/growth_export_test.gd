extends "res://scripts/actors/tests/destruction_authoring_workspace_test.gd"
func run() -> void:
	root.size=Vector2i(1400,900); root.gui_embed_subwindows=true
	var folder:=ProjectSettings.globalize_path("user://growth-export-"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash")); var project:=Project.new("Growth validation"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var session:=KiwiModelSession.new(); session.add("Plane",{"size":Vector3(.8,1,.8)}); KiwiSurfaceGrowth.add(session,0); session.primary().title="Baked export hair"; var growth:=session.primary().growth; growth.settings.density=150.; growth.settings.length=.4; growth.rendering.gpu_threshold=1; growth.appearance.emission=Color(.2,.5,.1); session.document.prepare_growth(); var source:=folder.path_join("Hair.tres"); ResourceSaver.save(session.document,source)
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(12); editor=(get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs).timeline; editor.model.create_actor(editor.registry.get_definition(&"basic_mesh"),0,{&"mesh_path":source}); await settle(4)
	var actor: ActorData
	for candidate: ActorData in editor.model.actors:
		if candidate.display_name=="Baked export hair": actor=candidate
	check(actor!=null,"Native scene instantiates the groom for frame rendering")
	if actor==null: main.queue_free(); quit(1); return
	actor.values.physics={"enabled":true,"gravity":1.,"wind":Vector3(3,0,0),"particles":8,"collision":false}; editor.physics.mark_dirty(); var error:=await editor.physics.bake_group(editor,0,.3,60); check(error.is_empty(),"Hair guide simulation bakes before rendering")
	var lens:=editor.runtime_holder.get_viewport().get_camera_3d(); lens.global_position=Vector3(0,1.,2.); lens.look_at(Vector3(0,.2,0)); editor.set_video_duration(.25)
	var snapshots:=[]
	for pass_index in 3:
		var frames:=[]; var fps:=12 if pass_index!=1 else 24; var options:={"motion_samples":2,"shutter":.5} if pass_index==2 else {}
		var path:=folder.path_join("growth-%d.mp4"%pass_index)
		var progress:=func(frame: int,_total: int,stage: String):
			if stage=="Rendering" and pass_index<2 and (pass_index==0 or (frame-1)%2==0): frames.append(editor.physics.display_states[actor.id].points.duplicate())
		error=await ActorSceneExporter.render(editor,path,192,108,fps,progress,options)
		check(error.is_empty() and FileAccess.file_exists(path),"Actual growth scene video encodes (%d fps, %d samples): %s"%[fps,int(options.get("motion_samples",1)),error])
		var metadata:=ActorVideo.info(path); check(absf(float(metadata.get("duration",0.))-.25)<.05,"Scene clip keeps the requested duration after temporal sampling")
		if pass_index<2: snapshots.append(frames)
		DirAccess.remove_absolute(path)
	check(not snapshots[0].is_empty() and snapshots[0]==snapshots[1],"Baked growth poses match at corresponding timestamps across actual 12/24 fps scene renders")
	check(not editor.runtime_holder.get_viewport().has_meta("kiwi_final_growth"),"Frame rendering restores the interactive growth quality afterward")
	editor.physics.dispose(); editor.model.history.clear_history(); main.queue_free(); await settle(); DirAccess.remove_absolute(source)
	print("GROWTH EXPORT: %d checks, %d failures"%[checks,failures]); quit(failures)
