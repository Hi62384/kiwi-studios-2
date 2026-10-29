extends "res://scripts/actors/tests/destruction_authoring_workspace_test.gd"
const Appearance=preload("res://scripts/actors/fog/fog_appearance.gd")
func run() -> void:
	root.size=Vector2i(1400,900); root.gui_embed_subwindows=true
	var folder:=ProjectSettings.globalize_path("user://fog-export-"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash")); var project:=Project.new("Fog export validation"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(12); editor=(get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs).timeline
	var appearance:=Appearance.definition().create_object(); appearance.values[&"emission"]=Color.RED; appearance.values[&"color"]=Color.RED
	var clip:=editor.model.create_actor(editor.registry.get_definition(&"global_fog"),0,{&"appearance":ActorObjectReference.from_object(appearance),&"density":.5}); var actor:=editor.model.actor_for_id(clip.actor_id)
	for key in ["color","emission"]:
		var path:=PackedStringArray(["appearance",key]); editor.model.playhead_time=0.; editor.model.add_keyframe(actor,path,"Fog "+key,Color.RED); editor.model.playhead_time=1./6.; editor.model.add_keyframe(actor,path,"Fog "+key,Color.BLUE)
	editor.set_video_duration(.25); var frames: Array[Color]=[]; var viewport:=editor.runtime_holder.get_viewport()
	var progress:=func(_frame: int,_total: int,stage: String):
		if stage=="Rendering": frames.append(viewport.get_texture().get_image().get_pixel(96,54))
	var path:=folder.path_join("fog-validation.mp4"); var error:=await ActorSceneExporter.render(editor,path,192,108,12,progress)
	print("FOG VIDEO frames=",frames)
	check(error.is_empty() and FileAccess.file_exists(path),"A native fog scene renders and encodes through the actual scene-video pipeline")
	check(frames.size()==3 and frames[0].r>frames[0].b+.1,"The first captured frame includes fog ownership immediately")
	check(frames.size()==3 and frames[-1].b>frames[-1].r+.1,"Nested fog appearance keyframes affect the actual final video frame")
	check(absf(float(ActorVideo.info(path).get("duration",0.))-.25)<.05,"Encoded fog video preserves the requested duration")
	DirAccess.remove_absolute(path); editor.physics.dispose(); editor.model.history.clear_history(); main.queue_free(); await settle(); print("FOG SCENE VIDEO: %d checks, %d failures"%[checks,failures]); quit(failures)
