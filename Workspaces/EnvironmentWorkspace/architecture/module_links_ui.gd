extends RefCounted
static func properties(workspace: Control,item: KiwiModelComponent,parent: Node) -> bool:
	return Engine.get_singleton("KiwiNativeServices").call("service","module_links_ui").call("properties",workspace,item,parent)
static func refresh_open(tabs: Node,path: String) -> void:
	var job=preload("res://Workspaces/EnvironmentWorkspace/ModuleLinkRefreshJob.cs").new()
	tabs.add_child(job)
	job.start(tabs,path)
	if not job.finished: await job.completed
