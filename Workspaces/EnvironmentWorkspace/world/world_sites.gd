extends RefCounted
## Native site search plus asynchronous source/workspace ownership guards.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","world_sites")
static func _cancel_requested(state: Dictionary) -> bool: return bool(state.enabled) and bool(state.callback.call())
static func find(source: Resource,index: int,cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("find",source,index,state)
	state.clear(); return result
static func request(workspace: Control,id: String,index: int=-1,profile: String="") -> void:
	var job:=preload("res://Workspaces/EnvironmentWorkspace/WorldSiteRequestJob.cs").new()
	workspace.add_child(job); job.start(workspace,id,index,profile)
	if not job.finished: await job.completed
