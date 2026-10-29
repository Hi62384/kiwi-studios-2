extends "res://scripts/actors/tests/world_connections_workspace_test.gd"
const Districts=preload("res://Workspaces/EnvironmentWorkspace/world/world_districts.gd")
func run() -> void:
	root.size=Vector2i(1440,950); var workspace:=Workspace.new(); root.add_child(workspace)
	for i in 4: await process_frame
	var world:=Worlds.add(workspace.session,Vector3.ZERO,true); var id:=world.id; var source: Resource=Worlds.source(world); var corners:=PackedVector3Array([Vector3(-40,.03,-40),Vector3(40,.03,-40),Vector3(40,.03,40),Vector3(-40,.03,40)])
	for i in 4: source=Worlds.add_road(source,corners[i],corners[(i+1)%4])
	source=Cities.create(source,Vector3.ZERO); source.settlements[0].radius=64.; source.settlements[0].layout_mode="Road network"; source.settlements[0].lot_size=64.; source.settlements[0].height_max=1; workspace.set_meta("world_section",7); var result:=await Edit.request(workspace.session,id,source); await settle(workspace)
	var add: MenuButton
	for control in workspace.find_children("*","MenuButton",true,false):
		if control.is_visible_in_tree() and not control.is_queued_for_deletion() and control.text=="＋ District": add=control; break
	check(result.errors.is_empty() and add!=null and add.get_popup().item_count==10,"District page exposes ten creation presets in the actual workspace")
	if add!=null: add.get_popup().id_pressed.emit(2); await settle(workspace)
	source=Worlds.source(workspace.session.document.component(id)); check(source.settlements[0].get("districts",[]).size()==1 and source.settlements[0].districts[0].template.style=="Industrial","Creating a district through the menu installs its actual architectural preset")
	var boundary: Button
	for control in workspace.find_children("*","Button",true,false):
		if control.is_visible_in_tree() and not control.is_queued_for_deletion() and control.text=="✎ Edit district boundary": boundary=control; break
	var has_boundary:=boundary!=null
	if has_boundary: boundary.pressed.emit()
	workspace.canvas.target=Vector3.ZERO; workspace.canvas.distance=135.; workspace.canvas.update_camera(); await process_frame; var tool: RefCounted=workspace.canvas.road_tool.district_tool; var info: Dictionary=tool.selection(); var before: PackedVector2Array=source.settlements[0].districts[0].polygon.duplicate(); var projected: Vector2=workspace.canvas.project(tool._world(info,before[0])); var pressed:=InputEventMouseButton.new(); pressed.button_index=MOUSE_BUTTON_LEFT; pressed.pressed=true; pressed.position=projected; var began: bool=tool.input(pressed); var motion:=InputEventMouseMotion.new(); motion.position=workspace.canvas.project(tool._world(info,before[0]+Vector2(6,0))); tool.input(motion); var release:=InputEventMouseButton.new(); release.button_index=MOUSE_BUTTON_LEFT; release.position=motion.position; tool.input(release); await settle(workspace)
	source=Worlds.source(workspace.session.document.component(id)); var after: PackedVector2Array=source.settlements[0].districts[0].polygon
	check(has_boundary and began and after[0].distance_to(before[0])>3. and after[1]==before[1],"Viewport boundary handles move the intended district point and commit the source on release")
	workspace.session.undo(); await settle(workspace); source=Worlds.source(workspace.session.document.component(id)); check(source.settlements[0].districts[0].polygon==before,"Boundary editing undoes as one source-and-geometry action")
	workspace.session.redo(); await settle(workspace); source=Worlds.source(workspace.session.document.component(id)); check(source.settlements[0].districts[0].polygon==after and workspace.canvas.renderer.errors.is_empty(),"Redo restores the boundary and native district meshes upload without renderer errors")
	if DisplayServer.get_name()!="headless":
		for i in 3: await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/verification/world_districts_workspace.png")
	var saved: Error=await workspace.save_to("user://world_districts_workspace.res"); var loaded:=ResourceLoader.load("user://world_districts_workspace.res","",ResourceLoader.CACHE_MODE_IGNORE) as KiwiEnvironmentDocument
	check(saved==OK and loaded!=null and loaded.validate().is_empty() and Worlds.source(loaded.component(id)).settlements[0].districts[0].polygon==after,"Actual district workspace saves and reopens editable polygon sources and native geometry")
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("WORLD DISTRICT WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
