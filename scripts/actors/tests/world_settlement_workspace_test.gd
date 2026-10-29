extends "res://scripts/actors/tests/surface_growth_test.gd"
const Workspace=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func run() -> void:
	root.size=Vector2i(1440,950); var workspace:=Workspace.new(); root.add_child(workspace)
	for i in 4: await process_frame
	var starter:=KiwiEnvironmentDocument.new(); var starter_ground:=starter.add_terrain(); workspace.open_source(starter)
	for i in 3: await process_frame
	var world_button: Button
	for control in workspace.find_children("*","Button",true,false): if control.text=="◎ World": world_button=control
	if world_button==null: check(false,"World creation button exists"); workspace.queue_free(); quit(1); return
	world_button.pressed.emit(); var world:=workspace.session.primary(); var id:=world.id
	check(not str(Worlds.source(world).owned_terrain_id).is_empty(),"The actual World toolbar action creates a referenced native ground surface")
	check(Worlds.source(world).owned_terrain_id==starter_ground.id and workspace.session.environment().terrain(starter_ground.id).dimensions==Vector2(256,256),"The normal starter environment upgrades its existing ground for city generation")
	for i in 3: await process_frame
	var create: MenuButton
	for control in workspace.find_children("*","MenuButton",true,false): if control.text=="＋ Settlement ▾": create=control
	check(create!=null,"World inspector exposes the contextual settlement creation menu")
	if create==null: workspace.queue_free(); quit(1); return
	create.get_popup().id_pressed.emit(2); await Edit.flush(workspace.session)
	for i in 4: await process_frame
	var source:=Worlds.source(workspace.session.document.component(id)); check(source.settlements.size()==1 and source.settlements[0].profile=="City","Choosing City in the actual workspace creates an editable procedural settlement")
	check(int(workspace.get_meta("world_section"))==2,"Creating a settlement opens its contextual settings instead of showing all world controls at once")
	var visible_world_width:=false; var visible_radius:=false
	for control in workspace.find_children("*","Label",true,false):
		if control.text=="World width": visible_world_width=control.is_visible_in_tree()
		if control.text=="Radius": visible_radius=control.is_visible_in_tree()
	check(not visible_world_width and visible_radius,"Inspector sections show only the active settlement controls")
	workspace.canvas.frame(true); var started:=Time.get_ticks_usec(); var path:="user://world_city_workspace.res"; var saved: Error=await workspace.save_to(path)
	check(saved==OK and workspace.canvas.renderer.pending_assets.is_empty() and workspace.canvas.renderer.errors.is_empty(),"Normal workspace save waits for complete native city preview uploads")
	var state:=workspace.capture_state(); workspace.open_source(KiwiEnvironmentDocument.new())
	for i in 3: await process_frame
	workspace.open_source(path)
	for i in 5: await process_frame
	check(int(workspace.get_meta("world_section"))==2 and Worlds.source(workspace.session.document.component(id)).settlements.size()==1,"Saved worlds restore contextual inspector mode and editable settlement settings")
	workspace.open_source(state.session.environment(),state)
	for i in 4: await process_frame
	check(workspace.session==state.session and int(workspace.get_meta("world_section"))==2,"Tab-style state restoration preserves the original world session and inspector section")
	var frames:=0
	while (workspace.canvas._pending_sync or not workspace.canvas.renderer.pending_assets.is_empty() or not workspace.canvas.renderer.pending_chunks.is_empty()) and frames<600: await process_frame; frames+=1
	var expected:=0
	for item in workspace.session.document.components:
		if item.mesh!=null and workspace.session.environment().component_kind(item.id)=="asset" and workspace.session.document.visible_component(item): expected+=1
	var rendered:=0
	for item in workspace.session.document.components:
		if item.mesh==null or workspace.session.environment().component_kind(item.id)!="asset" or not workspace.session.document.visible_component(item): continue
		var node: Node=workspace.canvas.renderer.nodes.get(item.id)
		if node==null: continue
		for visual: MeshInstance3D in node.find_children("*","MeshInstance3D",true,false):
			if visual.mesh!=null: rendered+=1
	check(frames<600 and expected>100 and rendered==expected,"Reopened city finishes every native building mesh upload before visual verification")
	if DisplayServer.get_name()!="headless":
		workspace.canvas.tool=""; workspace.canvas.distance*=.55; workspace.canvas.update_camera()
		for i in 3: await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/verification/world_city_workspace.png")
	print("WORLD CITY WORKSPACE preview_save_reopen_ms=",float(Time.get_ticks_usec()-started)/1000.," components=",workspace.session.document.components.size()); workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("WORLD SETTLEMENT WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
