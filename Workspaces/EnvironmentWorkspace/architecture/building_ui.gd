extends RefCounted
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","building_ui")
static func create(workspace: Control,levels: int=1) -> void:
	var job=preload("res://Workspaces/EnvironmentWorkspace/BuildingUiPlanJob.cs").new()
	workspace.add_child(job)
	job.start(workspace,"create",null,1,true,levels)
	if not job.finished: await job.completed
static func show_plan(workspace: Control,root: KiwiModelComponent,mode: int=1,fit_first: bool=true) -> Control:
	var job=preload("res://Workspaces/EnvironmentWorkspace/BuildingUiPlanJob.cs").new()
	workspace.add_child(job)
	job.start(workspace,"show",root,mode,fit_first,1)
	if not job.finished: await job.completed
	return job.result
static func cancel(workspace: Control) -> void:
	_native().call("cancel",workspace)
static func restore(workspace: Control) -> void:
	var job=preload("res://Workspaces/EnvironmentWorkspace/BuildingUiPlanJob.cs").new()
	workspace.add_child(job)
	job.start(workspace,"restore",null,1,false,1)
	if not job.finished: await job.completed
static func _frame(workspace: Control) -> void:
	_native().call("frame",workspace)
static func properties(workspace: Control,item: KiwiModelComponent,parent: Node) -> bool:
	return _native().call("properties",workspace,item,parent)
static func _anchors(workspace: Control,id: String) -> void:
	_native().call("anchors",workspace,id)
static func _wall_properties(workspace: Control,id: String,source: Resource,level: int,index: int,selected: int,parent: Node) -> void:
	_native().call("wall_properties",workspace,id,source,level,index,selected,parent)
static func _stair_properties(workspace: Control,id: String,source: Resource,index: int,parent: Node) -> void:
	_native().call("stair_properties",workspace,id,source,index,parent)
static func choose_material(workspace: Control,id: String,index: int) -> void:
	var job=preload("res://Workspaces/EnvironmentWorkspace/BuildingUiFileJob.cs").new()
	workspace.add_child(job)
	job.start(workspace,"material",id,index)
	if not job.finished: await job.completed
static func _apply(workspace: Control,id: String,source: Resource,label: String) -> void:
	var job=preload("res://Workspaces/EnvironmentWorkspace/BuildingUiApplyJob.cs").new()
	workspace.add_child(job)
	job.start(workspace,id,source,label)
	if not job.finished: await job.completed
static func _source(workspace: Control,id: String) -> Resource:
	return _native().call("source",workspace,id)
static func _insert_model(workspace: Control,id: String) -> void:
	var job=preload("res://Workspaces/EnvironmentWorkspace/BuildingUiFileJob.cs").new()
	workspace.add_child(job)
	job.start(workspace,"module",id,0)
	if not job.finished: await job.completed
