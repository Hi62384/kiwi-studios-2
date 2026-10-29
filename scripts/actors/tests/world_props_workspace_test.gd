extends "res://scripts/actors/tests/surface_growth_test.gd"
const Workspace=preload("res://Workspaces/EnvironmentWorkspace/environment_workspace.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Props=preload("res://Workspaces/EnvironmentWorkspace/world/world_props.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
func run() -> void:
	root.size=Vector2i(1440,950); var workspace:=Workspace.new(); root.add_child(workspace)
	for i in 4: await process_frame
	var world:=Worlds.add(workspace.session,Vector3.ZERO,true); var id:=world.id; var source: Resource=Worlds.add_road(Worlds.source(world),Vector3(-40,.03,0),Vector3(40,.03,0)); var model:=KiwiModelDocument.new(); var component:=KiwiModelComponent.new(); component.id="column"; component.title="Columns"; component.generator="Architecture / Column"; component.parameters=preload("res://Workspaces/EnvironmentWorkspace/architecture/architectural_component.gd").defaults(component.generator); component.mesh=preload("res://Workspaces/EnvironmentWorkspace/architecture/architectural_component.gd").generate(component.generator,component.parameters); var stone:=StandardMaterial3D.new(); stone.albedo_color=Color("ddd4bc"); component.surface_materials=[stone]; model.components.append(component); source=Props.create(source,model); await Edit.request(workspace.session,id,source); workspace.set_meta("world_section",5); workspace._refresh_properties()
	for i in 8: await process_frame
	var menu: MenuButton; var edit: Button; var controls:=false
	for control in workspace.find_children("*","Button",true,false):
		if control.text=="＋ Objects ▾": menu=control
		if control.text=="Edit layer filters and palette": edit=control
	for control in workspace.find_children("*","Label",true,false):
		if control.text=="Distance from road" and control.is_visible_in_tree(): controls=true
	check(menu!=null and menu.get_popup().get_item_index(100)>=0 and menu.get_popup().get_item_text(0)=="Along roads…" and controls,"World object placement exposes file-based and built-in models with contextual roadside controls")
	if edit!=null: edit.pressed.emit()
	check(edit!=null and workspace.session.environment().component_kind(workspace.session.primary().id)=="scatter","Placement layers open the shared native palette, filtering and instance-editing tools")
	workspace.session.select(id); workspace.canvas.target=Vector3.ZERO; workspace.canvas.distance=75.; workspace.canvas.update_camera(); var path:="user://world_props_workspace.res"; var saved: Error=await workspace.save_to(path); workspace.open_source(KiwiEnvironmentDocument.new()); await process_frame; workspace.open_source(path)
	for i in 8: await process_frame
	check(saved==OK and int(workspace.get_meta("world_section"))==5 and workspace.canvas.renderer.instances>5,"Normal workspace save/reopen retains object placement, rendered instances and its inspector page")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw; root.get_texture().get_image().save_png("res://.godot/verification/world_props_workspace.png")
	menu=null
	for control in workspace.find_children("*","MenuButton",true,false):
		if control.is_visible_in_tree() and not control.is_queued_for_deletion() and control.text=="＋ Objects ▾": menu=control; break
	var had_menu:=menu!=null
	if had_menu: menu.get_popup().id_pressed.emit(100); await Edit.flush(workspace.session)
	var current: Resource=Worlds.source(workspace.session.document.component(id)); check(had_menu and current.prop_rules.size()==2 and current.prop_rules[-1].name=="Park bench" and current.prop_rules[-1].sidewalk,"Built-in prop creation through the workspace installs an editable sidewalk model palette")
	workspace.session._undo.clear(); workspace.session._redo.clear(); workspace.queue_free(); await process_frame; print("WORLD PROPS WORKSPACE: %d checks, %d failures"%[checks,failures]); quit(failures)
