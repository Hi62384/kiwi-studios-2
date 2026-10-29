extends "res://scripts/actors/tests/surface_growth_test.gd"
func run() -> void:
	var store:=KiwiClipboardStore.new("user://environment-clipboard-"+ActorData.new_id()); var folder:=store.root.path_join("originals"); DirAccess.make_dir_recursive_absolute(folder)
	var model:=KiwiModelSession.new(); model.add("Box",{"size":Vector3.ONE}); var model_path:=folder.path_join("Rock.tres"); ResourceSaver.save(model.document,model_path)
	var image:=Image.create(8,8,false,Image.FORMAT_RGBA8); image.fill(Color.CHOCOLATE); var image_path:=folder.path_join("Ground.png"); image.save_png(image_path)
	var session:=KiwiEnvironmentSession.new(); var terrain:=session.add_terrain(); session.environment().component_settings[terrain.id].material=image_path; session.place_asset(model_path,Vector3(1,0,2)); var placed:=session.primary(); session.add_scatter(terrain.id,model_path)
	var id:=store.save(session.environment(),"Reusable environment"); check(not id.is_empty(),"Super Clipboard captures a complete environment with model, image and scatter dependencies")
	var component:=session.selected_environment(); check(component.components.size()==2 and component.terrain(terrain.id)!=null,"Saving only a scatter component includes its required terrain dependency")
	var inserted:=KiwiEnvironmentSession.new(); var error:=inserted.insert_environment(component,Vector3(3,0,0)); var inserted_scatter: KiwiEnvironmentScatter
	for settings: Dictionary in inserted.environment().component_settings.values():
		if settings.get("scatter") is KiwiEnvironmentScatter: inserted_scatter=settings.scatter
	check(error.is_empty() and inserted_scatter!=null and inserted_scatter.terrain_id!=terrain.id and inserted.environment().terrain(inserted_scatter.terrain_id)!=null,"Reusable component insertion remaps stable terrain links under a new movable parent")
	inserted.undo(); check(inserted.document.components.is_empty(),"Inserting a reusable environment component undoes as one action")
	inserted.redo(); check(inserted.document.components.size()==3,"Reusable component insertion redoes its hierarchy and generators")
	var loaded:=ResourceLoader.load(store.entry_path(id),"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	DirAccess.remove_absolute(model_path); DirAccess.remove_absolute(image_path); KiwiEnvironmentAssets.cache.clear(); KiwiEnvironmentAssets.material_cache.clear()
	check(loaded!=null and loaded.validate().is_empty() and loaded.components.size()==3,"Portable environment retains its component hierarchy and valid generator metadata")
	var copied_path:=str(loaded.component_settings[placed.id].source); var parts:=KiwiEnvironmentAssets.load_parts(copied_path)
	check(copied_path!=model_path and parts.parts.size()==1 and parts.parts[0].mesh.get_faces().size()==36,"Copied model source still has real geometry after the original is removed")
	var material:=KiwiEnvironmentAssets.material(loaded.component_settings[terrain.id].material) as StandardMaterial3D
	check(material!=null and material.albedo_texture!=null,"Portable ground image still resolves after its original file is removed")
	var scatter:=loaded.component_settings[session.primary().id].scatter as KiwiEnvironmentScatter
	check(scatter.terrain_id==terrain.id and str(scatter.palette[0].source)==copied_path,"Scatter retains its stable terrain dependency and shares the copied model source")
	var runtime:=KiwiEnvironmentRuntime.new(); root.add_child(runtime); runtime.configure(loaded); check(runtime.errors.is_empty() and runtime.instances>0,"Portable environment renders terrain, placed geometry and instanced scatter through the shared runtime")
	runtime.queue_free(); await process_frame; model._undo.clear(); model._redo.clear(); session._undo.clear(); session._redo.clear(); inserted._undo.clear(); inserted._redo.clear(); store.close(); print("ENVIRONMENT PORTABILITY: %d checks, %d failures"%[checks,failures]); quit(failures)
