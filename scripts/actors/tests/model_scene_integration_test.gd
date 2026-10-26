extends SceneTree
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
	print("PASS " if ok else "FAIL ",label)
func settle() -> void:
	for i in 5: await process_frame
func button(root_node: Node, text: String) -> Button:
	if root_node is Button and root_node.text==text: return root_node
	for child in root_node.get_children():
		var found := button(child,text)
		if found!=null: return found
	return null
func width(editor: ActorTimelineEditor, clip_id: String) -> float:
	var runtime := editor._runtime_for_clip(clip_id)
	if runtime==null: return -1
	var meshes := runtime.find_children("*","MeshInstance3D",true,false)
	return (meshes[0] as MeshInstance3D).mesh.get_aabb().size.x if not meshes.is_empty() else -1
func run() -> void:
	root.size=Vector2i(1440,1000); root.gui_embed_subwindows=true
	var folder := ProjectSettings.globalize_path("user://model_project_"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash"))
	var project := Project.new("Model integration"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(ProjectSettings.globalize_path(folder.path_join(".proj/Project.tres"))); StaticData.loaded_project=project
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(); await settle()
	var tabs := get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs
	tabs.new_model(); await settle(); var workspace := tabs.model_workspace
	check(workspace.visible and not tabs.scene_workspace.visible and tabs.documents.back().type=="model","New tab creates a dedicated Modeling Workspace")
	workspace.session.add("Box"); workspace.session.mode="Face"; workspace.session.elements=PackedInt32Array([0]); await settle()
	var count := workspace.session._undo.size(); var revision := workspace.session.revision
	workspace._operation_dialog("Inset"); await settle(); var popup := workspace.get_node("GeometryOperation") as PopupPanel
	check(workspace.session.primary().mesh.faces.size()==10,"Operation dialog shows real live geometry preview")
	var amount := popup.find_child("Distance",true,false) as DragNumber; amount.value=.15; await settle()
	check(workspace.session._undo.size()==count and workspace.session.revision==revision,"Live numeric previews do not alter undo history or dirty revision")
	popup.hide(); await settle(); check(workspace.session.primary().mesh.faces.size()==6,"Cancelling operation restores source mesh")
	workspace._operation_dialog("Inset"); await settle(); popup=workspace.get_node("GeometryOperation") as PopupPanel; button(popup,"Apply").pressed.emit(); await settle()
	check(workspace.session.primary().mesh.faces.size()==10 and workspace.session._undo.size()==count+1,"Apply commits geometry instead of silently cancelling on popup close")
	workspace.session.undo(); check(workspace.session.primary().mesh.faces.size()==6,"One undo restores accepted operation")
	var path := folder.path_join("Shared Model.tres")
	check(await workspace.save_to(path)==OK,"Model saves into project filesystem")
	check(tabs.documents[tabs._active_index].path==path and not tabs.documents[tabs._active_index].dirty,"Save updates tab identity and clears its dirty marker")
	var thumbnail: Texture2D=await FileOperations.get_file_thumbnail(path)
	check(thumbnail!=null and thumbnail.get_width()>0 and thumbnail.get_height()>0,"Project filesystem decodes the saved model thumbnail without a GPU resource reload")
	check(ActorFileImport.type_for_path(path)==&"basic_mesh","Dragging a native model resolves through the mesh import entry point")
	var definition := tabs.timeline.registry.get_definition(&"basic_mesh"); var property := definition.find_property(&"mesh_path")
	check(PackedStringArray(property.options.native_resource_types).has("KiwiModelDocument"),"Basic Mesh project picker accepts native modeling assets")
	tabs._model_to_scene(path); await settle(); var first := tabs.timeline.model.selected_clip(); var first_id := first.id
	tabs.timeline.model.selected_layer=tabs.timeline.model.clips.size()+1
	var second := tabs.timeline.model.create_actor(definition,0,{&"mesh_path":path}); var second_id := second.id; await settle()
	check(is_equal_approx(width(tabs.timeline,first_id),1.) and is_equal_approx(width(tabs.timeline,second_id),1.),"Native components render as ordinary Basic Mesh instances (%s, %s)"%[width(tabs.timeline,first_id),width(tabs.timeline,second_id)])
	tabs.open_model(path); await settle(); check(tabs.documents.size()==2,"Opening an already-open model reuses its tab")
	workspace.session.action("Edit shared geometry",func(): workspace.session.primary().mesh.vertices[0].x-=.4)
	await workspace.save(); tabs._capture_current(); tabs._open_index(0); await settle()
	check(width(tabs.timeline,first_id)>1.3 and width(tabs.timeline,second_id)>1.3,"Saving shared geometry updates every scene instance")
	var unique := KiwiModelImport.load_document(path); var unique_path := folder.path_join("Unique Model.tres"); ResourceSaver.save(unique,unique_path)
	var second_actor: ActorData
	for candidate in tabs.timeline.model.actors:
		if candidate.parent_id==second.actor_id and candidate.type_id==&"basic_mesh": second_actor=candidate; break
	tabs.timeline.model.edit_property(second_actor,definition,&"mesh_path",unique_path); await settle(); var unique_width := width(tabs.timeline,second_id)
	tabs.open_model(path); await settle(); workspace.session.action("Edit original again",func(): workspace.session.primary().mesh.vertices[0].x-=.3); await workspace.save()
	tabs._capture_current(); tabs._open_index(0); await settle()
	check(width(tabs.timeline,first_id)>unique_width+.2 and is_equal_approx(width(tabs.timeline,second_id),unique_width),"A unique model asset is independent of subsequent shared edits")
	var scene := tabs.timeline.capture_scene_data(); var scene_path := folder.path_join("Model Scene.tres"); ResourceSaver.save(scene,scene_path)
	var saved_scene := ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	check(saved_scene!=null and saved_scene.actors.size()==4 and saved_scene.actors[1].values[&"mesh_path"]==path,"Scene saving preserves separate model actors and native model references")
	tabs.open_model(path); await settle(); workspace.canvas.frame(true)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		var output := ProjectSettings.globalize_path("res://.godot/verification/model_workspace/full_application.png")
		DirAccess.make_dir_recursive_absolute(output.get_base_dir()); check(root.get_texture().get_image().save_png(output)==OK,"Full modeling application screenshot")
	tabs.new_model(); await settle(); workspace.session.add("Cylinder")
	tabs._capture_current(); tabs._open_index(1); await settle(); check(workspace.session.primary().mesh.vertices[0].x<-.9,"Switching models retains each document and its editing history")
	tabs.new_image(); await settle(); check(tabs.image_workspace.visible and not workspace.visible,"Image workspace stays isolated from modeling world")
	tabs._capture_current(); tabs._open_index(0); await settle(); check(tabs.scene_workspace.visible and not workspace.visible,"Scene workspace restores normally after modeling/image tabs")
	main.queue_free(); await process_frame; await process_frame; StaticData.loaded_project=null
	print("MODEL_SCENE_INTEGRATION checks=%d failures=%d"%[checks,failures]); quit(failures)
