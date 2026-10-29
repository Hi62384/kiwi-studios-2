extends "res://scripts/actors/tests/world_connections_workspace_test.gd"
func run() -> void:
	root.size=Vector2i(1440,950); var workspace:=Workspace.new(); root.add_child(workspace)
	for i in 4: await process_frame
	var world:=Worlds.add(workspace.session,Vector3.ZERO,true); var id:=world.id; var source: Resource=Worlds.source(world)
	var corners:=PackedVector3Array([Vector3(-40,.03,-40),Vector3(40,.03,-40),Vector3(40,.03,40),Vector3(-40,.03,40)])
	for i in 4: source=Worlds.add_road(source,corners[i],corners[(i+1)%4])
	source=Cities.create(source,Vector3.ZERO); source.settlements[0].radius=64.; source.settlements[0].height_max=1; source.settlements[0].blocks=1
	workspace.set_meta("world_section",2); var result:=await Edit.request(workspace.session,id,source); await settle(workspace)
	var layout: OptionButton
	for control in workspace.find_children("*","OptionButton",true,false):
		if control.is_visible_in_tree() and not control.is_queued_for_deletion() and control.item_count==2 and control.get_item_text(1)=="Use drawn road network": layout=control; break
	check(result.errors.is_empty() and layout!=null,"Settlement inspector exposes the actual road-network layout choice")
	if layout!=null: layout.select(1); layout.item_selected.emit(1); await settle(workspace)
	var owner:=workspace.session.document.component(id); var roots:=0
	for item in workspace.session.document.components:
		if item.parameters.has("architecture_source"): roots+=1
	check(Worlds.source(owner).settlements[0].layout_mode=="Road network" and owner.parameters.world_blocks.size()==1 and roots>=4,"Switching the visible layout control generates buildings in the drawn road block")
	check(workspace.canvas.renderer.errors.is_empty() and workspace.session.environment().validate().is_empty(),"Road-block native meshes upload and the environment remains valid")
	workspace.canvas.target=Vector3.ZERO; workspace.canvas.distance=135.; workspace.canvas.update_camera()
	if DisplayServer.get_name()!="headless":
		for i in 3: await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/verification/world_blocks_workspace.png")
	var saved: Error=await workspace.save_to("user://world_blocks_workspace.res"); var loaded:=ResourceLoader.load("user://world_blocks_workspace.res","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(saved==OK and loaded!=null and loaded.validate().is_empty() and loaded.component(id).parameters.world_blocks.size()==1,"Saving and reopening preserves actual road blocks, native architecture and layout sources")
	workspace.session.undo(); await settle(workspace); owner=workspace.session.document.component(id); check(Worlds.source(owner).settlements[0].get("layout_mode","Grid")=="Grid","Road-network layout switching is undoable")
	workspace.session.redo(); await settle(workspace); owner=workspace.session.document.component(id); check(Worlds.source(owner).settlements[0].layout_mode=="Road network" and owner.parameters.world_blocks.size()==1,"Redo restores the road-derived building layout")
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("WORLD BLOCK WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
