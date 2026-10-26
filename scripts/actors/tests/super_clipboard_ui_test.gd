extends SceneTree
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,title: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(title)
	print("PASS " if ok else "FAIL ",title)
func settle(count: int=5) -> void:
	for i in count: await process_frame
func f8() -> void:
	var event:=InputEventKey.new(); event.keycode=KEY_F8; event.physical_keycode=KEY_F8; event.pressed=true; root.push_input(event,true); event=event.duplicate(); event.pressed=false; root.push_input(event,true); await settle()
func run() -> void:
	root.size=Vector2i(1600,1000); root.gui_embed_subwindows=true
	var folder:=ProjectSettings.globalize_path("user://clipboard_ui_"+ActorData.new_id()); DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash"))
	var project:=Project.new("Clipboard UI verification"); ResourceSaver.save(project,folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project=project
	var main: Node=load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(12)
	var tabs:=get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs; var editor:=tabs.timeline
	var service:=KiwiSuperClipboardService.instance; service.store.close(); service.store=KiwiClipboardStore.new(folder.path_join("library"))
	var material_definition:=editor.registry.get_object_definition(&"material"); var material:=material_definition.create_object()
	var clip:=editor.model.create_actor(editor.registry.get_definition(&"basic_shape"),0,{&"material":ActorObjectReference.from_object(material)}); var actor:=editor.model.selected_actor(); editor.model.changed.emit(); await settle()
	var property:=editor.registry.get_definition(&"basic_shape").find_property(&"material")
	editor.inspector._object_menu_action(6,actor,editor.registry.get_definition(&"basic_shape"),property,material_definition,editor.registry.object_definitions_for(&"material")); await settle()
	var id:=str(service.store.data.default_slot)
	check(not id.is_empty() and service.store.data.entries.size()==1,"Inspector Copy to Super Clipboard stores the current editable material")
	await f8(); check(is_instance_valid(service.window) and service.window.visible,"F8 opens the global embedded floating library")
	check(service.window.files.item_count==1 and service.window.tree.get_root()!=null,"Floating library lists folders and stored resources")
	var payload:=service.drag_payload(PackedStringArray([id])); var slot:=ActorResourceSlot.new(); root.add_child(slot); slot.accepts_file=editor.inspector._object_resource_path_allowed.bind(property)
	var dropped:={"path":""}; slot.file_dropped.connect(func(path: String): dropped.path=path)
	check(slot._can_drop_data(Vector2.ZERO,payload),"Material drags use the existing inspector compatibility rules")
	slot._drop_data(Vector2.ZERO,payload)
	check(not str(dropped.path).is_empty() and FileOperations.is_path_inside(folder,str(dropped.path)),"Clipboard drags supply a real project-local material path")
	var image:=Image.create(4,4,false,Image.FORMAT_RGBA8); image.fill(Color.CORAL); var image_path:=folder.path_join("Test.png"); image.save_png(image_path)
	var image_id:=service.store.save(image_path,"Test image")
	check(not slot._can_drop_data(Vector2.ZERO,service.drag_payload(PackedStringArray([image_id]))),"Incompatible image drags are rejected by a Material field")
	check(ActorResourceSlot.path_from_drag(service.drag_payload(PackedStringArray([id,image_id]))).is_empty(),"Single-resource slots reject multi-item drags instead of silently dropping extras")
	service.window._receive({"paths":PackedStringArray([image_path])},"default")
	check(service.store.data.entries.size()==3,"Dragging a project file into the floating library saves a persistent copy")
	await f8()
	var picker:=ActorProjectFilePicker.new(); root.add_child(picker); picker._build(editor.inspector._object_picker_property(property),"Choose material"); picker._set_clipboard_source(true); await settle()
	check(picker.files.item_count==1,"Existing resource picker filters Super Clipboard to compatible material types")
	var result:={"path":""}; picker.finished.connect(func(path: String): result.path=path); picker._file_selected(0); picker._choose()
	check(not str(result.path).is_empty() and FileOperations.is_path_inside(folder,str(result.path)),"Choosing a clipboard asset imports it before returning the normal project picker path")
	picker.queue_free()
	var save_dialog:=ActorProjectResourceSaveDialog.new(); save_dialog.clipboard_value=material; root.add_child(save_dialog); save_dialog._build("Save material","Material","tres",false)
	var save_result:={}; save_dialog.finished.connect(func(value: Dictionary): save_result.merge(value,true)); var button:=save_dialog.find_child("SaveToSuperClipboard",true,false) as Button
	check(button!=null,"Existing Save As dialog offers a working Super Clipboard destination")
	button.pressed.emit(); await settle()
	check(save_result.has("clipboard_saved") and str(actor.values.material.embedded.resource_path).is_empty(),"Saving a clipboard copy does not redirect or overwrite the original resource")
	save_dialog.queue_free()
	var original_index:=tabs._active_index; var original_count:=tabs.documents.size(); service.toggle(); service.save_active_document(); await settle()
	check(tabs._active_index==original_index and tabs.documents.size()==original_count,"Saving the active scene into the library leaves its document and tab intact")
	print("CLIPBOARD_GEOMETRY size=",service.window.size," min=",service.window.get_combined_minimum_size()," viewport=",service.window.get_viewport_rect()," global=",service.window.get_global_rect())
	check(service.window.get_global_rect().end.y<=service.window.get_viewport_rect().size.y,"Floating library fits within the visible viewport")
	await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://.godot/verification/super_clipboard_ui.png")
	service.window._close()
	for create: Callable in [tabs.new_image,tabs.new_shader,tabs.new_audio,tabs.new_model,tabs.new_transformation]:
		create.call(); await settle(); var active:=tabs._active_index
		await f8(); check(service.window.visible and tabs._active_index==active,"F8 opens Super Clipboard without switching the active %s workspace"%str(tabs.documents[active].type)); await f8()
	main.queue_free(); slot.queue_free(); await settle()
	print("SUPER CLIPBOARD UI: %d checks, %d failures"%[checks,failures]); quit(failures)
