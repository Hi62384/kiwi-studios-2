extends "res://scripts/actors/tests/surface_growth_test.gd"
const Workspace=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func button(workspace: Control,caption: String) -> Button:
	for control in workspace.find_children("*","Button",true,false):
		if control.text==caption and not control.is_queued_for_deletion(): return control
	return null
func settle(workspace: Control) -> void:
	await Edit.flush(workspace.session)
	for i in 5: await process_frame
func run() -> void:
	root.size=Vector2i(1440,950); var workspace:=Workspace.new(); root.add_child(workspace)
	for i in 4: await process_frame
	var world:=Worlds.add(workspace.session); var id:=world.id; var source: Resource=Worlds.add_road(Worlds.source(world),Vector3(-30,0,0),Vector3(30,0,0)); workspace.set_meta("world_section",1); await Edit.request(workspace.session,id,source); await settle(workspace); var categories: OptionButton
	for control in workspace.find_children("*","OptionButton",true,false):
		if control.item_count==10 and control.get_item_text(0)=="Highway" and control.is_visible_in_tree() and not control.is_queued_for_deletion(): categories=control
	check(categories!=null,"The actual World road inspector exposes all ten road categories")
	if categories==null: workspace.free(); quit(1); return
	categories.item_selected.emit(0); await settle(workspace); source=Worlds.source(workspace.session.document.component(id)); check(source.roads[0].type=="Highway" and source.roads[0].width==20. and source.roads[0].lanes==6,"Changing road category in the inspector applies its actual cross-section and lane metadata")
	var from:=str(source.roads[0].from); button(workspace,"Reverse").pressed.emit(); await settle(workspace); source=Worlds.source(workspace.session.document.component(id)); check(str(source.roads[0].to)==from,"The inspector Reverse command updates the editable source direction")
	button(workspace,"Split").pressed.emit(); await settle(workspace); source=Worlds.source(workspace.session.document.component(id)); check(source.roads.size()==2 and source.roads[0].to==source.roads[1].from,"The inspector Split command creates connected road sources")
	var joining:=button(workspace,"Join endpoint to road…") as MenuButton; joining.get_popup().id_pressed.emit(1); await settle(workspace); source=Worlds.source(workspace.session.document.component(id)); check(source.roads.size()==1 and source.roads[0].points.size()==3,"The inspector Join command retains the joint control point")
	workspace.canvas.environment_tool="Road points"; workspace.canvas.road_tool.road_index=0; workspace.canvas.road_tool.point_index=1; workspace.canvas.grab_focus(); var erase:=InputEventKey.new(); erase.keycode=KEY_DELETE; erase.pressed=true; workspace.canvas._gui_input(erase); await settle(workspace); source=Worlds.source(workspace.session.document.component(id)); check(source.roads[0].points.size()==2 and workspace.session.document.component(id)!=null,"Delete in the road viewport edits the selected point without deleting the world")
	button(workspace,"Extend").pressed.emit(); check(workspace.canvas.road_tool._first==source.roads[0].points[-1],"Extend starts a live road preview from the existing endpoint")
	workspace.canvas.distance=80.; workspace.canvas.target=Vector3.ZERO; workspace.canvas.update_camera(); var click:=InputEventMouseButton.new(); click.position=workspace.canvas.project(Vector3(-50,0,0)); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; workspace.canvas._gui_input(click); click.pressed=false; workspace.canvas._gui_input(click); await settle(workspace); source=Worlds.source(workspace.session.document.component(id)); check(source.roads.size()==2 and source.roads[0].to==source.roads[1].from,"Completing a collinear extension reuses its existing graph endpoint")
	var frames:=0
	while (workspace.canvas._pending_sync or not workspace.canvas.renderer.pending_assets.is_empty()) and frames<600: await process_frame; frames+=1
	check(frames<600 and workspace.canvas.renderer.errors.is_empty(),"Edited cross-sections finish their native preview uploads without renderer errors")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://.godot/verification/road_editor_workspace.png")
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("ROAD EDITOR WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)

