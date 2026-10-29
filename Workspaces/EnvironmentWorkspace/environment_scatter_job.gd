extends RefCounted
var source: KiwiEnvironmentScatter
var terrain: KiwiEnvironmentTerrain
var result: Dictionary={}
var task_id:=-1
var _mutex:=Mutex.new()
var _cancelled:=false
func cancel() -> void: _mutex.lock(); _cancelled=true; _mutex.unlock()
func cancelled() -> bool:
	_mutex.lock(); var value:=_cancelled; _mutex.unlock(); return value
func start(rules: KiwiEnvironmentScatter,surface: KiwiEnvironmentTerrain) -> void:
	source=rules.duplicate(true); terrain=surface.duplicate(true); task_id=WorkerThreadPool.add_task(_run,false,"Environment scatter generation")
func _run() -> void: result=source.generate(terrain,cancelled)
func complete() -> bool: return task_id>=0 and WorkerThreadPool.is_task_completed(task_id)
func collect() -> void:
	if task_id>=0: WorkerThreadPool.wait_for_task_completion(task_id); task_id=-1
