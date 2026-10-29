extends "res://scripts/actors/tests/surface_growth_test.gd"
const Workspace=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Cities=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func settle(workspace: Control) -> void:
	await Edit.flush(workspace.session); var frames:=0
	while frames<900:
		await process_frame; frames+=1
		if frames>5 and not workspace.canvas._pending_sync and workspace.canvas.renderer.pending_assets.is_empty() and workspace.canvas.renderer.pending_chunks.is_empty(): break
func run() -> void:
	root.size=Vector2i(1440,950); var workspace:=Workspace.new(); root.add_child(workspace)
	for i in 4: await process_frame
	var world:=Worlds.add(workspace.session,Vector3.ZERO,true); var id:=world.id; var terrain:=workspace.session.environment().terrain(Worlds.source(world).terrain_id); terrain.hydrology=KiwiTerrainHydrology.new(); terrain.hydrology.automatic_rivers=false; terrain.hydrology.automatic_lakes=false; terrain.hydrology.manual_rivers=[{"id":"river","points":PackedVector3Array([Vector3(0,0,-128),Vector3(0,0,128)]),"width":12.,"depth":1.,"follow_terrain":false}]; terrain.prepare_water(); var source: Resource=Cities.create(Worlds.source(world),Vector3(-70,0,0)); source=Cities.create(source,Vector3(70,0,0))
	for settlement: Dictionary in source.settlements: settlement.radius=16.; settlement.blocks=1; settlement.height_max=1
	workspace.set_meta("world_section",6); var result:=await Edit.request(workspace.session,id,source); await settle(workspace); var owner:=workspace.session.document.component(id)
	check(result.errors.is_empty() and owner.parameters.world_connections.size()==1 and int(owner.parameters.world_connections[0].bridges)>0,"Actual workspace renders two settlements connected over native river terrain")
	var edit: Button; var settings:=false
	for control in workspace.find_children("*","Button",true,false):
		if control.text=="Make connection roads editable" and not control.is_queued_for_deletion(): edit=control
		if control.text=="Allow bridges and approaches" and control.is_visible_in_tree(): settings=true
	check(edit!=null and settings and workspace.canvas.renderer.errors.is_empty(),"Connections have a dedicated inspector page and completed native geometry uploads")
	workspace.canvas.target=Vector3.ZERO; workspace.canvas.distance=140.; workspace.canvas.update_camera()
	if DisplayServer.get_name()!="headless":
		for i in 3: await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/verification/world_connections_workspace.png")
	if edit!=null: edit.pressed.emit(); await settle(workspace)
	check(Worlds.source(workspace.session.document.component(id)).roads.size()>0 and int(workspace.get_meta("world_section"))==1,"The inspector promotes connections to ordinary editable road sources")
	workspace.session.undo(); await settle(workspace); var saved: Error=await workspace.save_to("user://world_connections_workspace.res"); var loaded:=ResourceLoader.load("user://world_connections_workspace.res","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(saved==OK and loaded!=null and loaded.validate().is_empty() and loaded.component(id).parameters.world_connections.size()==1,"Saving a connection world preserves native water, bridge geometry and editable generation settings")
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("WORLD CONNECTION WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
