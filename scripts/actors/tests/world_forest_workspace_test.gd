extends "res://scripts/actors/tests/surface_growth_test.gd"
const Workspace=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func settle(workspace: Control) -> bool:
	var frames:=0
	while frames<600:
		await process_frame; frames+=1
		if frames>5 and not workspace.canvas._pending_sync and workspace.canvas.renderer.pending_assets.is_empty() and workspace.canvas.renderer.pending_chunks.is_empty() and workspace.canvas.renderer.scatter_jobs.is_empty(): return true
	return false
func run() -> void:
	root.size=Vector2i(1440,950); var workspace:=Workspace.new(); root.add_child(workspace)
	for i in 4: await process_frame
	var world:=Worlds.add(workspace.session,Vector3.ZERO,true); var id:=world.id; var source: Resource=Worlds.source(world).copy(); source.dimensions=Vector2(64,64); source.configure_regions(); await Edit.request(workspace.session,id,source)
	for i in 4: await process_frame
	var create: MenuButton
	for control in workspace.find_children("*","MenuButton",true,false):
		if control.text=="♧ Add forest ▾": create=control
	check(create!=null and create.get_popup().item_count==8,"The World inspector exposes all eight forest profiles through its native creation menu")
	if create==null: workspace.free(); quit(1); return
	create.get_popup().id_pressed.emit(0); await Edit.flush(workspace.session); var ready:=await settle(workspace)
	check(ready and Worlds.source(workspace.session.document.component(id)).forests.size()==1 and int(workspace.get_meta("world_section"))==4,"Choosing a forest creates native rules and opens its contextual controls")
	var renderer: KiwiEnvironmentRuntime=workspace.canvas.renderer; var batches:=0; var count:=0
	for node: Node3D in renderer.nodes.values():
		for visual: MultiMeshInstance3D in node.find_children("*","MultiMeshInstance3D",true,false):
			if visual.multimesh!=null: batches+=1; count+=visual.multimesh.instance_count
	check(renderer.errors.is_empty() and batches>=7 and count>100,"Real multi-species vegetation is rendered through bounded MultiMesh batches")
	var path:="user://world_forest_workspace.res"; var saved: Error=await workspace.save_to(path); workspace.open_source(KiwiEnvironmentDocument.new()); await process_frame; workspace.open_source(path); ready=await settle(workspace)
	check(saved==OK and ready and int(workspace.get_meta("world_section"))==4 and workspace.canvas.renderer.instances>100,"Normal workspace save/reopen restores forest controls, native palettes and rendered instances")
	var layer: Button
	for control in workspace.find_children("*","Button",true,false):
		if control.text=="Edit Canopy": layer=control
	if layer!=null: layer.pressed.emit()
	check(layer!=null and workspace.session.environment().component_kind(workspace.session.primary().id)=="scatter","The forest's Edit Canopy button opens existing per-layer scatter tools")
	workspace.session.select(id); workspace.canvas.target=Vector3.ZERO; workspace.canvas.distance=85.; workspace.canvas.update_camera()
	for i in 4: await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://.godot/verification/world_forest_workspace.png")
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("WORLD FOREST WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
