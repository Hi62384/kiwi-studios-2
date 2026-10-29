extends RefCounted
## Owns a private CPU source snapshot; native upload stays on the main thread.
var result: Dictionary={}
var task_id:=-1
var _mutex:=Mutex.new()
var _cancelled:=false
func cancel() -> void: _mutex.lock(); _cancelled=true; _mutex.unlock()
func cancelled() -> bool:
	_mutex.lock(); var value:=_cancelled; _mutex.unlock(); return value
func start(kind: String,parameters: Dictionary) -> void:
	var snapshot:=parameters.duplicate(true)
	task_id=WorkerThreadPool.add_task(func(): result=preload("res://Workspaces/ModelWorkspace/natural_generator.gd").generate(kind,snapshot,cancelled),false,"Natural object generation")
func complete() -> bool: return task_id>=0 and WorkerThreadPool.is_task_completed(task_id)
func collect() -> Dictionary:
	if task_id>=0: WorkerThreadPool.wait_for_task_completion(task_id); task_id=-1
	return result
