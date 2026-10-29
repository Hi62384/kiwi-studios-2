extends "res://scripts/actors/tests/model_scene_integration_test.gd"
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_source.gd")
func visual(editor: ActorTimelineEditor,actor: ActorData) -> MeshInstance3D:
	var runtime:=editor._runtime_for_clip(editor.model.clip_for_actor_id(actor.id).id)
	for child in runtime.find_children("*","MeshInstance3D",true,false):
		if child.mesh!=null: return child
	return null
func run() -> void:
	root.size=Vector2i(1440,950); root.gui_embed_subwindows=true; var folder:=ProjectSettings.globalize_path("user://architecture_scene_"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash")); var project:=Project.new("Architecture integration"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(); await settle(); var tabs:=get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs; tabs.new_model(); await settle(); var workspace:=tabs.model_workspace; var building:=Buildings.add(workspace.session,Vector3.ZERO,2); var id:=building.id; var path:=folder.path_join("Building.tres"); var saved: Error=await workspace.save_to(path)
	check(saved==OK,"Complete architecture saves through the native Model Workspace")
	tabs._model_to_scene(path); await settle(); var scene_index:=tabs._active_index; var editor:=tabs.timeline; var door: ActorData; var wall: ActorData
	for actor in editor.model.actors:
		if actor.values.get(&"model_component_id","")==id+":floor0:opening:door0:leaf": door=actor
		if actor.values.get(&"model_component_id","")==id+":floor0:wall:wall0": wall=actor
	check(door!=null and wall!=null and door.parent_id==wall.id,"To Scene preserves individual native door actors and their wall hierarchy")
	if door==null or wall==null: main.queue_free(); quit(1); return
	check(door.values[&"structure_connections"].hinge.target==wall.id,"Scene conversion remaps the structural hinge to its actual wall actor")
	var wall_visual:=visual(editor,wall); var before:=hash(wall_visual.mesh.get_faces()); var wall_pose: Transform3D=(editor._runtime_for_clip(editor.model.clip_for_actor_id(wall.id).id).content as Node3D).transform; var original_hinge: Vector3=door.values[&"position"]; var original_joint: Vector3=door.values[&"structure_connections"].hinge.target_pivot
	editor.model.playhead_time=0.; editor.model.add_keyframe(door,PackedStringArray(["rotation"]),"Door rotation",Vector3.ZERO); editor.model.playhead_time=1.; editor.model.add_keyframe(door,PackedStringArray(["rotation"]),"Door rotation",Vector3(0,90,0)); editor.canvas.playhead=.5; editor._evaluate_runtimes(); await settle()
	var door_content:=editor._runtime_for_clip(editor.model.clip_for_actor_id(door.id).id).content as Node3D; var fixed_wall:=editor._runtime_for_clip(editor.model.clip_for_actor_id(wall.id).id).content as Node3D
	check(absf(door_content.rotation_degrees.y-45.)<.05 and fixed_wall.transform.is_equal_approx(wall_pose),"Keyframed door rotates around its own hinge while the wall remains fixed")
	tabs.open_model(path); await settle(); var next: Resource=Source.copy(Buildings.source(workspace.session.document.component(id))); next.floors[0].walls[0].openings[0].width=1.6; next.floors[0].walls[0].openings[0].t=.65; next.floors[0].height=3.5; next.floors[1].elevation=3.5; var update:=Buildings.update(workspace.session,id,next,"Widen linked doorway"); saved=await workspace.save_to(path); tabs._capture_current(); tabs._open_index(scene_index); await settle(); editor.canvas.playhead=.5; editor._evaluate_runtimes(); await settle()
	check(update.errors.is_empty() and saved==OK and hash(visual(editor,wall).mesh.get_faces())!=before,"Saving the edited source refreshes real linked doorway geometry in Scene Workspace")
	check(door.animation_track(PackedStringArray(["rotation"])).keys.size()==2 and absf((editor._runtime_for_clip(editor.model.clip_for_actor_id(door.id).id).content as Node3D).rotation_degrees.y-45.)<.05,"Linked geometry refresh preserves door keyframes and evaluated pose")
	check(not (door.values[&"position"] as Vector3).is_equal_approx(original_hinge) and not (door.values[&"structure_connections"].hinge.target_pivot as Vector3).is_equal_approx(original_joint),"Moving a source opening updates both default hinge placement and structural pivot")
	var moved_floor:=false
	for actor in editor.model.actors:
		if actor.values.get(&"model_component_id","")==id+":floor1": moved_floor=is_equal_approx(actor.values[&"position"].y,3.5)
	check(moved_floor,"Linked floor groups receive compatible source elevation updates")
	var scene:=editor.capture_scene_data(); var scene_path:=folder.path_join("Architecture Scene.tres"); ResourceSaver.save(scene,scene_path); var loaded:=ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData; var found:=false
	for actor in loaded.actors:
		if actor.id==door.id: found=actor.animation_track(PackedStringArray(["rotation"])).keys.size()==2 and actor.values[&"mesh_path"]==path
	check(found,"Scene serialization preserves linked architecture resources and component animation")
	editor.physics.dispose(); editor.model.history.clear_history(); main.queue_free(); await process_frame; await process_frame; StaticData.loaded_project=null; print("ARCHITECTURE SCENE: %d checks, %d failures"%[checks,failures]); quit(failures)
