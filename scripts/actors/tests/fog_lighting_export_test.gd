extends "res://scripts/actors/tests/destruction_authoring_workspace_test.gd"
func run() -> void:
	root.size=Vector2i(1400,900); root.gui_embed_subwindows=true; var folder:=ProjectSettings.globalize_path("user://fog-light-video-"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash")); var project:=Project.new("Fog lighting video"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(12); editor=(get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs).timeline; var viewport:=editor.runtime_holder.get_viewport(); var lens:=viewport.get_camera_3d(); lens.global_position=Vector3(7,3,7); lens.look_at(Vector3(0,1,-2))
	var environment:=viewport.find_world_3d().environment; environment.background_mode=Environment.BG_COLOR; environment.background_color=Color.BLACK; environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color=Color.BLACK; environment.ambient_light_energy=0.; environment.volumetric_fog_density=0.; environment.volumetric_fog_temporal_reprojection_enabled=false
	var fog:=editor.model.create_actor(editor.registry.get_definition(&"fog_volume"),0,{&"position":Vector3(0,1,-2),&"volume_size":Vector3(12,8,16),&"density":.06}); fog.layer=0; fog.start_time=0.
	var light_clip:=editor.model.create_actor(editor.registry.get_definition(&"light_3d"),0,{&"light_type":2,&"position":Vector3(0,2,3),&"rotation":Vector3(-8,0,0),&"energy":8.,&"volumetric_fog_energy":2.,&"range":16.,&"spot_angle":30.,&"shadows":true}); light_clip.layer=1; light_clip.start_time=0.; var light:=editor.model.actor_for_id(light_clip.actor_id)
	var wall_clip:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0,{&"position":Vector3(0,2,0),&"scale":Vector3(1.8,4,.2)}); wall_clip.layer=2; wall_clip.start_time=0.; var wall:=editor.model.actor_for_id(wall_clip.actor_id)
	for entry in [[light,"color",Color.RED,Color.BLUE],[light,"position",Vector3(0,2,3),Vector3(.5,2,3)],[wall,"position",Vector3(0,2,0),Vector3(3,2,0)]]:
		var path:=PackedStringArray([entry[1]]); editor.model.playhead_time=0.; editor.model.add_keyframe(entry[0],path,"Lighting animation",entry[2]); editor.model.playhead_time=5./24.; editor.model.add_keyframe(entry[0],path,"Lighting animation",entry[3])
	editor.model.changed.emit(); editor.set_video_duration(.25); var results:=[]
	for fps in [24,48]:
		var samples: Array[Color]=[]; var path:=folder.path_join("lighting-%d.mp4"%fps); var progress:=func(frame: int,_total: int,stage: String):
			if stage=="Rendering" and (fps==24 or (frame-1)%2==0): samples.append(viewport.get_texture().get_image().get_pixel(96,54))
		var error:=await ActorSceneExporter.render(editor,path,192,108,fps,progress); check(error.is_empty() and FileAccess.file_exists(path),"Animated fog lighting and moving shadows encode at %d fps: %s"%[fps,error]); results.append(samples); DirAccess.remove_absolute(path)
	check(results[0].size()==6 and results[0][0].r>results[0][0].b+.02 and results[0][-1].b>results[0][-1].r+.02,"Captured lighting colors follow their authored scene times")
	var consistent: bool=results[0].size()==results[1].size()
	if consistent:
		for index in results[0].size():
			var a: Color=results[0][index]; var b: Color=results[1][index]; consistent=consistent and absf(a.r-b.r)<.04 and absf(a.g-b.g)<.04 and absf(a.b-b.b)<.04
	print("FOG LIGHT VIDEO samples=",results); check(consistent,"Matching scene times remain visually consistent at 24 and 48 fps without temporal trails")
	editor.physics.dispose(); editor.model.history.clear_history(); main.queue_free(); await settle(); print("FOG LIGHTING VIDEO: %d checks, %d failures"%[checks,failures]); quit(failures)
