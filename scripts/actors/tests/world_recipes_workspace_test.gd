extends "res://scripts/actors/tests/world_connections_workspace_test.gd"
const Recipes=preload("res://Workspaces/EnvironmentWorkspace/world/world_recipes.gd")
func run() -> void:
	root.size=Vector2i(1440,950); var workspace:=Workspace.new(); root.add_child(workspace)
	for i in 4: await process_frame
	var world:=Worlds.add(workspace.session,Vector3.ZERO,true); var id:=world.id; var source: Resource=Worlds.source(world); source.dimensions=Vector2(96,96); source.configure_regions(); workspace.canvas.request_sync(); workspace._refresh_properties(); await process_frame; var menu: MenuButton
	for control in workspace.find_children("*","MenuButton",true,false):
		if control.is_visible_in_tree() and not control.is_queued_for_deletion() and control.text=="Generate world preset…": menu=control; break
	check(menu!=null and not menu.disabled and menu.get_popup().item_count==7,"Empty owned worlds expose the seven complete preset choices")
	var terrain_id:=str(source.terrain_id); var original:=workspace.session.environment().terrain(terrain_id).signature(); var depth:=workspace.session._undo.size()
	if menu!=null: menu.get_popup().id_pressed.emit(1)
	var saved: Error=await workspace.save_to("user://world_recipes_workspace.res"); await settle(workspace); var root_world:=workspace.session.document.component(id); var current: Resource=Worlds.source(root_world); var loaded:=ResourceLoader.load("user://world_recipes_workspace.res","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(saved==OK and root_world.parameters.get("world_recipe","")=="Suburban Town" and current.settlements.size()==1 and current.forests.size()==1 and loaded!=null and loaded.component(id).parameters.get("world_recipe","")=="Suburban Town","Saving during preset generation waits for complete terrain, settlement and vegetation output")
	check(workspace.session._undo.size()==depth+1 and workspace.session.environment().terrain(terrain_id).dimensions==Vector2(96,96) and workspace.canvas.renderer.errors.is_empty(),"Preset terrain and native world output commit together as one valid undoable action")
	workspace.session.undo(); await settle(workspace); root_world=workspace.session.document.component(id); check(Recipes.empty(Worlds.source(root_world)) and workspace.session.environment().terrain(terrain_id).signature()==original,"Undo restores the entire previous terrain and empty world")
	Recipes.request(workspace,id,"Tropical Island"); workspace.session.undo(); var completed:=await Recipes.flush(workspace.session); await settle(workspace); root_world=workspace.session.document.component(id)
	check(not completed and Recipes.empty(Worlds.source(root_world)) and workspace.session.environment().terrain(terrain_id).signature()==original and workspace.session._undo.size()==depth,"Canceling a preset discards worker output without changing terrain or adding history")
	workspace.session.redo(); await settle(workspace); root_world=workspace.session.document.component(id); check(root_world.parameters.get("world_recipe","")=="Suburban Town" and workspace.session.environment().validate().is_empty(),"Redo after cancellation still restores the previously generated native world")
	workspace.canvas.target=Vector3.ZERO; workspace.canvas.distance=100.; workspace.canvas.update_camera()
	if DisplayServer.get_name()!="headless":
		for i in 3: await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/verification/world_recipes_workspace.png")
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("WORLD RECIPE WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
