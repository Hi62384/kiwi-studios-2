extends "res://scripts/actors/tests/destruction_authoring_workspace_test.gd"
func run() -> void:
	root.size=Vector2i(1280,800); root.gui_embed_subwindows=true; var folder:=ProjectSettings.globalize_path("user://terrain-water-physics"); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash")); var project:=Project.new("Water physics"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var terrain:=KiwiEnvironmentTerrain.new(); terrain.resolution=33; terrain.dimensions=Vector2(16,16); terrain.base_height=-3.; terrain.hydrology=KiwiTerrainHydrology.new(); terrain.hydrology.automatic_rivers=false; terrain.hydrology.automatic_lakes=false; terrain.hydrology.ocean_enabled=true; terrain.prepare_water(); var flow: PackedVector2Array=terrain.water_data.flow; flow.fill(Vector2(.5,0)); terrain.water_data.flow=flow; var document:=KiwiEnvironmentDocument.new(); document.add_terrain(terrain); var path:=folder.path_join("Water.tres"); ResourceSaver.save(document,path)
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(10); var tabs:=get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs; editor=tabs.timeline; var env_clip:=editor.model.create_actor(editor.registry.get_definition(&"environment_asset"),0.,{&"environment_path":path}); env_clip.start_time=0.; env_clip.duration=5.
	var actors: Array[ActorData]=[]
	for index in 3:
		var clip:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0.,{&"position":Vector3((index-1)*2.,1,0),&"box_size":Vector3(.5,.5,.5)}); clip.start_time=0.; clip.duration=5.; clip.layer=index+1; var actor:=editor.model.actor_for_id(clip.actor_id); actor.values[&"physics"]={"enabled":true,"bounce":0.,"mass":300. if index==1 else 50.,"water_interaction":index!=2}; actors.append(actor)
	editor.model.changed.emit(); await seek(3.); var positions: Array[Vector3]=[]
	for actor in actors: positions.append((editor.physics.display_states[actor.id].pose as Transform3D).origin)
	check(positions[0].y>-.2 and positions[0].y<.3,"The existing offline rigid solver floats a light actor at its displacement equilibrium")
	check(positions[1].y<-.5 and positions[2].y<-2.4,"Dense actors sink and per-actor water-response toggles disable buoyancy")
	check(positions[0].x>-1.7 and float(editor.physics.display_states[actors[0].id].get("water_fraction",0.))>0.,"Shared terrain flow drives submerged actors through the existing physics bridge")
	await seek(.5); await seek(3.); var deterministic:=true
	for index in actors.size(): deterministic=deterministic and (editor.physics.display_states[actors[index].id].pose as Transform3D).origin.distance_to(positions[index])<.001
	check(deterministic,"Rewinding reproduces buoyancy, flow and terrain collision deterministically")
	# Use the controller's existing runtime lookup; no replacement physics engine.
	var runtime: ActorRuntime=editor.physics._runtime(env_clip.actor_id); terrain.hydrology.water_physics=false; ResourceSaver.save(document,path); runtime.call("reload_environment",path); editor.physics.invalidate_asset(path); await seek(3.)
	check((editor.physics.display_states[actors[0].id].pose as Transform3D).origin.y<-2.4,"Saving a disabled environment water response invalidates replay and removes buoyancy")
	editor.physics.dispose(); editor.model.history.clear_history(); main.queue_free(); await settle(); print("TERRAIN WATER PHYSICS positions=",positions); print("TERRAIN WATER PHYSICS: %d checks, %d failures"%[checks,failures]); quit(failures)
