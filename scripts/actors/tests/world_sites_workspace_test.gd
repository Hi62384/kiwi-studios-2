extends "res://scripts/actors/tests/surface_growth_test.gd"
const Workspace=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func run() -> void:
	root.size=Vector2i(1440,950); var workspace:=Workspace.new(); root.add_child(workspace)
	for i in 4: await process_frame
	var world:=Worlds.add(workspace.session,Vector3.ZERO,true); var id:=world.id
	for i in 4: await process_frame
	var menu: MenuButton
	for control in workspace.find_children("*","MenuButton",true,false):
		if control.text=="＋ Settlement ▾" and not control.is_queued_for_deletion(): menu=control
	check(menu!=null and menu.get_popup().get_item_index(100)>=0,"Settlement creation offers automatic terrain placement alongside manual creation")
	if menu==null: workspace.free(); quit(1); return
	var depth:=workspace.session._undo.size(); menu.get_popup().id_pressed.emit(100); var deadline:=Time.get_ticks_msec()+30000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if Worlds.source(workspace.session.document.component(id)).settlements.size()==1 and not workspace.session.pending_source_cancel.is_valid(): break
	var source:=Worlds.source(workspace.session.document.component(id)); check(source.settlements.size()==1 and int(workspace.get_meta("world_section"))==2 and workspace.session._undo.size()==depth+1,"Automatic placement creates its native settlement and source in one undoable action")
	var find: Button
	for i in 5: await process_frame
	for control in workspace.find_children("*","Button",true,false):
		if control.text=="Find suitable site" and not control.is_queued_for_deletion(): find=control
	check(find!=null and not find.disabled and workspace.session.environment().validate().is_empty(),"Existing settlements expose the same site finder in their contextual inspector")
	workspace.session.undo()
	for i in 5: await process_frame
	check(Worlds.source(workspace.session.document.component(id)).settlements.is_empty(),"One undo removes an automatically placed settlement and every generated component")
	await Edit.flush(workspace.session); workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("WORLD SITES WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
