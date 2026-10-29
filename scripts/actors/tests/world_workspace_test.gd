extends "res://scripts/actors/tests/surface_growth_test.gd"
const Workspace=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func click(canvas: Control,point: Vector2,pressed: bool=true) -> void:
	var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.position=point; event.pressed=pressed; canvas._gui_input(event)
func run() -> void:
	root.size=Vector2i(1440,900); var workspace:=Workspace.new(); root.add_child(workspace)
	for i in 4: await process_frame
	var world:=Worlds.add(workspace.session); var id:=world.id; var canvas: Control=workspace.canvas; canvas.distance=100.; canvas.update_camera(); canvas.environment_tool="Draw road"
	var first: Vector2=canvas.project(Vector3(-20,0,0)); var last: Vector2=canvas.project(Vector3(20,0,0)); click(canvas,first); click(canvas,first,false)
	check(canvas.road_tool._first is Vector3 and Worlds.source(workspace.session.document.component(id)).roads.is_empty(),"First viewport click previews a road endpoint without creating a partial source")
	var hover:=InputEventMouseMotion.new(); hover.position=last; canvas._gui_input(hover); await process_frame; check(canvas.road_tool._hover is Vector3 and (canvas.road_tool._hover as Vector3).distance_to(Vector3(20,0,0))<.05 and Worlds.source(workspace.session.document.component(id)).roads.is_empty(),"Road width previews follow the cursor without committing partial geometry")
	click(canvas,last); click(canvas,last,false); await Edit.flush(workspace.session)
	var source:=Worlds.source(workspace.session.document.component(id)); check(source.roads.size()==1 and workspace.session.document.components.size()>=2,"Drawing two viewport endpoints creates a real continuous road through the shared world job")
	var upload_frames:=0
	while (canvas._pending_sync or not canvas.renderer.pending_assets.is_empty() or canvas.renderer.nodes.size()!=workspace.session.document.components.size()) and upload_frames<600: await process_frame; upload_frames+=1
	check(upload_frames<600 and canvas.renderer.nodes.size()==workspace.session.document.components.size() and canvas.renderer.pending_assets.is_empty(),"World road geometry reaches the native environment renderer within its progressive upload budget")
	canvas.environment_tool="Road points"; var original: Vector3=source.roads[0].points[1]; last=canvas.project(original); click(canvas,last); var move:=InputEventMouseMotion.new(); move.position=canvas.project(original+Vector3(0,0,12)); canvas._gui_input(move); click(canvas,move.position,false); await Edit.flush(workspace.session)
	source=Worlds.source(workspace.session.document.component(id)); var moved: Vector3=source.roads[0].points[1]
	check(moved.distance_to(original+Vector3(0,0,12))<.05 and source.nodes[source.roads[0].to].is_equal_approx(moved),"Dragging a road handle updates its control point and shared graph endpoint together")
	workspace.session.undo(); source=Worlds.source(workspace.session.document.component(id)); check((source.roads[0].points[1] as Vector3).is_equal_approx(original),"One undo restores the entire road handle gesture")
	canvas.environment_tool="Draw road"; click(canvas,first); var escape:=InputEventKey.new(); escape.keycode=KEY_ESCAPE; escape.pressed=true; canvas._gui_input(escape); check(canvas.road_tool._first==null,"Escape cancels a new road preview without changing authored geometry")
	var path:="user://world_workspace.res"; var saved: Error=await workspace.save_to(path); var loaded:=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(saved==OK and loaded!=null and loaded.validate().is_empty() and Worlds.source(loaded.component(id)).roads.size()==1,"Normal workspace save preserves the editable world and road hierarchy")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://.godot/verification/world_roads_workspace.png")
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("WORLD WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
