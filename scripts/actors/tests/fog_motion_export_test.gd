extends "res://scripts/actors/tests/destruction_authoring_workspace_test.gd"
func run() -> void:
	root.size=Vector2i(1400,900); root.gui_embed_subwindows=true; var folder:=ProjectSettings.globalize_path("user://fog-motion-video-"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash")); var project:=Project.new("Fog motion video"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(12); editor=(get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs).timeline; var viewport:=editor.runtime_holder.get_viewport(); var camera:=viewport.get_camera_3d(); camera.global_transform=Transform3D.IDENTITY
	var environment:=viewport.find_world_3d().environment; environment.background_mode=Environment.BG_COLOR; environment.background_color=Color.WHITE; environment.ambient_light_energy=0.; environment.volumetric_fog_density=0.; environment.volumetric_fog_temporal_reprojection_enabled=false
	var source:=editor.registry.get_object_definition(&"fog_emitter").create_object(); source.values.merge({&"mode":1,&"shape":1,&"size":Vector3.ONE*1.4,&"position":Vector3(-.6,0,0),&"burst":3.,&"velocity":Vector3.RIGHT*2.},true)
	var appearance:=editor.registry.get_object_definition(&"fog_appearance").create_object(); appearance.values[&"scattering"]=0.
	var clip:=editor.model.create_actor(editor.registry.get_definition(&"fog_volume"),0,{&"position":Vector3(0,0,-5),&"shape":3,&"volume_size":Vector3(6,4,4),&"density":.6,&"appearance":ActorObjectReference.from_object(appearance),&"fog_motion_mode":2,&"fog_initial":1,&"fog_wind":Vector3.RIGHT*2.,&"fog_obstacles":false,&"fog_velocity_damping":0.,&"fog_source_0":ActorObjectReference.from_object(source)}); clip.layer=0; clip.start_time=0.; editor.model.changed.emit(); editor.set_video_duration(.2)
	var results:=[]
	var densities:=[]
	for fps in [24,30,60]:
		var samples: Array[PackedByteArray]=[]; var grids: Array=[]; var path:=folder.path_join("motion-%d.mp4"%fps); var progress:=func(frame: int,_total: int,stage: String):
			if stage=="Rendering" and (frame==1 or frame-1==fps/6):
				var captured:=viewport.get_texture().get_image(); print("FOG VIDEO frame ",fps,"/",frame," format=",captured.get_format()," size=",captured.get_size()," pixel=",captured.get_pixel(96,54)); captured.convert(Image.FORMAT_RGBA8); captured.save_png("res://.godot/verification/fog_motion_video_%d_%d.png"%[fps,frame]); samples.append(captured.get_data()); grids.append(hash(editor.physics.display_states[clip.actor_id].fog_density))
		var error:=await ActorSceneExporter.render(editor,path,192,108,fps,progress); check(error.is_empty() and FileAccess.file_exists(path),"Actual transported fog frames encode at %d fps: %s"%[fps,error]); results.append(samples); densities.append(grids); DirAccess.remove_absolute(path)
	var matching:=results.size()==3
	for values: Array in results: matching=matching and values.size()==2
	var maximum:=0; var average:=0.; var count:=0
	if matching:
		for fps_index in [1,2]:
			for index in 2:
				matching=matching and densities[0][index]==densities[fps_index][index]
				for pixel in results[0][index].size():
					var delta:=absi(int(results[0][index][pixel])-int(results[fps_index][index][pixel])); maximum=maxi(maximum,delta); average+=delta; count+=1
	print("FOG VIDEO density_hashes=",densities," pixel_max_delta=",maximum," pixel_mean_delta=",average/maxi(1,count))
	check(matching,"Transported concentration is identical at shared scene times across 24, 30 and 60 fps")
	check(maximum<=10 and average/maxi(1,count)<1.,"Native volumetric capture remains visually consistent across output frame rates")
	check(results[0].size()==2 and results[0][0]!=results[0][1],"Scene-video capture contains evolving density rather than a frozen fog frame")
	editor.physics.dispose(); editor.model.history.clear_history(); main.queue_free(); await settle(); print("FOG MOTION VIDEO: %d checks, %d failures"%[checks,failures]); quit(failures)
