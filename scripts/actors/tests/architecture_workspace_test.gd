extends "res://scripts/actors/tests/surface_growth_test.gd"
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const UI=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_ui.gd")
func button(plan: Control,point: Vector2,pressed: bool=true) -> void:
	var event:=InputEventMouseButton.new(); event.position=plan.to_screen(point); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=pressed; plan._gui_input(event)
func move(plan: Control,point: Vector2) -> void:
	var event:=InputEventMouseMotion.new(); event.position=plan.to_screen(point); event.button_mask=MOUSE_BUTTON_MASK_LEFT; plan._gui_input(event)
func run() -> void:
	var workspace:=KiwiEnvironmentWorkspace.new(); root.add_child(workspace); await process_frame; var building:=Buildings.add(workspace.session,Vector3.ZERO,2); var id:=building.id; var plan: Control=await UI.show_plan(workspace,building,1)
	for i in 5: await process_frame
	check(is_instance_valid(plan) and plan.visible and workspace.canvas.visible and plan.size.x>=260.,"Floor plan shares a resizable split with the existing 3D viewport")
	var count:=workspace.session._undo.size(); plan.tool="Wall"; button(plan,Vector2(-2,0)); move(plan,Vector2(2,0)); button(plan,Vector2(2,0),false)
	var source:=Buildings.source(workspace.session.document.component(id)); check(source.floors[0].walls.size()==5 and workspace.session._undo.size()==count+1,"Drawing a real wall updates source and geometry as one gesture")
	workspace.session.undo(); check(Buildings.source(workspace.session.document.component(id)).floors[0].walls.size()==4,"Plan wall creation undoes exactly")
	plan.tool="Select"; button(plan,Vector2(-3,-4)); move(plan,Vector2(-2.5,-4)); plan.cancel()
	check(Buildings.source(workspace.session.document.component(id)).floors[0].walls[0].a==Vector2(-3,-4),"Escape/right-click cancellation restores connected wall endpoints")
	plan.tool="Room"; button(plan,Vector2(-3,1.5)); move(plan,Vector2(-1.5,4)); button(plan,Vector2(-1.5,4),false); source=Buildings.source(workspace.session.document.component(id))
	check(source.floors[0].rooms.size()==2 and workspace.session.document.validate().is_empty(),"Room drawing partitions real shared walls and retains a valid hierarchy")
	var overlaps:=false
	for i in source.floors[0].rooms.size():
		for j in i:
			for polygon in Geometry2D.intersect_polygons(source.floors[0].rooms[i].polygon,source.floors[0].rooms[j].polygon): overlaps=overlaps or not Geometry2D.triangulate_polygon(polygon).is_empty()
	check(not overlaps,"Boundary-attached rooms partition previous room areas instead of overlapping them")
	var seen: Dictionary={}; var duplicates:=false
	for wall: Dictionary in source.floors[0].walls:
		var a:=str(wall.a)+":"+str(wall.b); var b:=str(wall.b)+":"+str(wall.a); duplicates=duplicates or seen.has(a) or seen.has(b); seen[a]=true
	check(not duplicates,"Partially shared room boundaries do not create duplicate walls")
	plan.cutaway=true
	for i in 5: await process_frame
	UI._frame(workspace)
	check(not (workspace.canvas.renderer.nodes[id+":roof"] as Node3D).visible and not (workspace.canvas.renderer.nodes[id+":floor1:wall:wall0"] as Node3D).visible and (workspace.canvas.renderer.nodes[id+":floor0:wall:wall0"] as Node3D).visible,"Interior cutaway hides roof and upper levels in the editor")
	var authored_visible:=true
	for item in workspace.session.document.components: authored_visible=authored_visible and item.visible
	var instance:=workspace.session.document.instantiate_model(); var roof_visible:=false
	for child in instance.find_children("*","Node3D",true,false):
		if child.get_meta("kiwi_component_id","")==id+":roof": roof_visible=child.visible
	check(authored_visible and roof_visible,"Cutaway does not hide saved source geometry or instantiated scene roofs"); instance.free()
	var camera_pose: Transform3D=workspace.canvas.camera.transform; var saved: Error=await workspace.save_to("user://architecture_editor_state.res")
	check(saved==OK,"Architecture environment saves through the normal project resource flow")
	workspace.hide(); var reopened:=KiwiEnvironmentWorkspace.new(); root.add_child(reopened); await process_frame; reopened.open_source("user://architecture_editor_state.res")
	for i in 10: await process_frame
	var restored: Control=reopened.get_meta("building_plan") if reopened.has_meta("building_plan") else null
	check(is_instance_valid(restored) and restored.cutaway and restored.visible,"Saved plan mode and cutaway reopen in the shared editor")
	check(reopened.canvas.camera.transform.is_equal_approx(camera_pose),"Reopening the plan preserves the exact 3D editing camera pose")
	reopened.queue_free(); workspace.show(); await process_frame
	for i in 5: await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://.godot/verification/architecture_workspace.png")
	await UI.show_plan(workspace,workspace.session.document.component(id),2); check(not plan.visible and workspace.canvas.visible,"3D-only mode returns the plan's space to the main viewport")
	workspace.queue_free(); await process_frame; print("ARCHITECTURE WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
