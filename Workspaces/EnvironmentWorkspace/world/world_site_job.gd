extends RefCounted
var result: Dictionary={}
var task_id:=-1
var _mutex:=Mutex.new()
var _cancelled:=false
func cancel() -> void: _mutex.lock(); _cancelled=true; _mutex.unlock()
func cancelled() -> bool: _mutex.lock(); var value:=_cancelled; _mutex.unlock(); return value
func start(source: Resource,index: int) -> void:
	task_id=WorkerThreadPool.add_task(func(): result=preload("res://Workspaces/EnvironmentWorkspace/world/world_sites.gd").find(source,index,cancelled),false,"Find settlement site")
func complete() -> bool: return task_id<0 or WorkerThreadPool.is_task_completed(task_id)
func collect() -> Dictionary:
	if task_id>=0: WorkerThreadPool.wait_for_task_completion(task_id); task_id=-1
	return result
