extends RefCounted
const Links=preload("res://Workspaces/EnvironmentWorkspace/architecture/module_links.gd")
static func properties(workspace: Control,item: KiwiModelComponent,parent: Node) -> bool:
	var path:=str(item.parameters.get("architecture_module_source",""))
	if path.is_empty(): return false
	var title:=Label.new(); title.text=("LINKED MODEL · " if item.parameters.get("module_linked",false) else "MODEL SNAPSHOT · ")+path.get_file(); title.tooltip_text=path; title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS; parent.add_child(title)
	var open:=Button.new(); open.text="Open source ↗"; open.disabled=not FileAccess.file_exists(path); parent.add_child(open); open.pressed.connect(func(): var tabs:=workspace.get_tree().get_first_node_in_group("actor_scene_tabs"); if tabs!=null: tabs.open_model(path))
	for entry in [["Refresh from source",false],["Reset source overrides",true]]:
		var button:=Button.new(); button.text=entry[0]; button.disabled=not item.parameters.get("module_linked",false); parent.add_child(button); button.pressed.connect(func():
			var session: KiwiModelSession=workspace.session
			if not await preload("res://Workspaces/EnvironmentWorkspace/architecture/building_edit.gd").flush(session) or workspace.session!=session: return
			var error:=Links.refresh(session,item.id,entry[1]); workspace.status.text=error if not error.is_empty() else "Linked model updated")
	var unique:=Button.new(); unique.text="Make unique"; parent.add_child(unique); unique.pressed.connect(func(): Links.make_unique(workspace.session,item.id))
	return true
static func refresh_open(tabs: Node,path: String) -> void:
	var seen: Dictionary={}
	for record: Dictionary in tabs.documents.duplicate():
		if record.get("type","") not in ["model","environment"]: continue
		var session: KiwiModelSession=record.get("state",{}).get("session")
		if tabs._active_index>=0 and tabs._active_index<tabs.documents.size() and record==tabs.documents[tabs._active_index]: session=tabs.model_workspace.session if record.type=="model" else tabs.environment_workspace.session
		if session==null or seen.has(session.get_instance_id()): continue
		seen[session.get_instance_id()]=true
		if not await preload("res://Workspaces/EnvironmentWorkspace/architecture/building_edit.gd").flush(session): continue
		var error:=Links.refresh_changed(session,path)
		if not error.is_empty():
			if record.type=="model" and tabs.model_workspace.session==session: tabs.model_workspace.status.text=error
			elif record.type=="environment" and tabs.environment_workspace.session==session: tabs.environment_workspace.status.text=error
