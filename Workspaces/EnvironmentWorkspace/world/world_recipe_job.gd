extends RefCounted
var authored: Resource
var result: Dictionary={}
var task:=-1
var mutex:=Mutex.new()
var stopped:=false
func cancel() -> void: mutex.lock(); stopped=true; mutex.unlock()
func cancelled() -> bool: mutex.lock(); var value:=stopped; mutex.unlock(); return value
func start(source: Resource) -> void:
	authored=source.copy(); task=WorkerThreadPool.add_task(_run,false,"World recipe layout")
func complete() -> bool: return task>=0 and WorkerThreadPool.is_task_completed(task)
func collect() -> Dictionary:
	if task>=0: WorkerThreadPool.wait_for_task_completion(task); task=-1
	return result
func _run() -> void:
	var warnings:=PackedStringArray()
	for index in authored.settlements.size():
		if cancelled(): result={"cancelled":true}; return
		var site:=preload("res://Workspaces/EnvironmentWorkspace/world/world_sites.gd").find(authored,index,cancelled)
		if site.get("cancelled",false): result={"cancelled":true}; return
		if not str(site.error).is_empty(): warnings.append(str(authored.settlements[index].name)+": "+str(site.error)); authored.settlements[index].enabled=false; continue
		var previous: Vector3=authored.settlements[index].center; var next: Vector3=site.position; authored.settlements[index].center=next
		for district: Dictionary in authored.settlements[index].get("districts",[]):
			var polygon: PackedVector2Array=district.polygon.duplicate()
			for point in polygon.size(): polygon[point]+=Vector2(next.x-previous.x,next.z-previous.z)
			district.polygon=polygon
	result=preload("res://Workspaces/EnvironmentWorkspace/world/road_network.gd").generate(authored,cancelled)
	if not result.get("cancelled",false): result.warnings.append_array(warnings)
