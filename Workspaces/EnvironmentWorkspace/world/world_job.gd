extends RefCounted
var result: Dictionary={}
var task_id:=-1
var _mutex:=Mutex.new()
var _cancelled:=false
var terrain_job: RefCounted
var terrain_plan: Dictionary={}
func cancel() -> void:
	_mutex.lock(); _cancelled=true; _mutex.unlock()
	if terrain_job!=null: terrain_job.cancel()
func cancelled() -> bool:
	_mutex.lock(); var value:=_cancelled; _mutex.unlock(); return value
func start(source: Resource,plan: Dictionary={},development: KiwiModelDocument=null) -> void:
	terrain_plan=plan
	if plan.has("settings"):
		terrain_job=preload("res://Workspaces/EnvironmentWorkspace/environment_generation_job.gd").new(); terrain_job.start(plan.source,plan.settings,false)
	task_id=WorkerThreadPool.add_task(func(): result=preload("res://Workspaces/EnvironmentWorkspace/world/road_network.gd").generate(source,cancelled,development),false,"World generation")
func complete() -> bool: return task_id>=0 and WorkerThreadPool.is_task_completed(task_id) and (terrain_job==null or terrain_job.complete())
func collect() -> Dictionary:
	if task_id>=0: WorkerThreadPool.wait_for_task_completion(task_id); task_id=-1
	if terrain_job!=null:
		terrain_job.collect()
		if terrain_job.cancelled(): result.cancelled=true
		elif not str(terrain_job.error).is_empty(): result.document=null; result.errors=PackedStringArray([str(terrain_job.error)])
		else: result.terrain_result={"id":terrain_plan.id,"terrain":terrain_job.terrain,"mesh":terrain_job.mesh}
	if cancelled(): result.cancelled=true
	return result
