extends RefCounted
## Worker-owned CPU resources only. Scene nodes and GPU meshes are committed on
## the main thread after checking that the authored source is still current.
var terrain: KiwiEnvironmentTerrain
var mesh: KiwiModelMesh
var task_id:=-1
var elapsed_ms:=0.
var error:=""
var _mutex:=Mutex.new()
var _cancelled:=false
var _progress:=0.
func cancel() -> void: _mutex.lock(); _cancelled=true; _mutex.unlock()
func cancelled() -> bool:
	_mutex.lock(); var value:=_cancelled; _mutex.unlock(); return value
func progress() -> float:
	_mutex.lock(); var value:=_progress; _mutex.unlock(); return value
func _set_progress(value: float) -> void: _mutex.lock(); _progress=value; _mutex.unlock()
func start(source: KiwiEnvironmentTerrain,settings: Dictionary,reset_edits: bool) -> void:
	terrain=source.duplicate(true) as KiwiEnvironmentTerrain
	for key: String in settings:
		if key=="caves":
			var values: Array[KiwiTerrainCave]=[]
			for cave in settings[key]: values.append(cave.duplicate(true))
			terrain.caves=values
		elif key=="erosion":
			var operations: Array[KiwiTerrainErosion]=[]
			for operation in settings[key]: operations.append(operation.duplicate(true))
			terrain.erosion=operations
		elif key in ["dimensions","resolution","seed","geology","base_height","amplitude","frequency","generation","hydrology","biomes","voxel_height","voxel_cell_budget"]: terrain.set(key,settings[key].duplicate(true) if settings[key] is Resource else settings[key])
	if reset_edits: terrain.edits=PackedFloat32Array()
	task_id=WorkerThreadPool.add_task(_run,false,"Environment terrain generation")
func _run() -> void:
	var started:=Time.get_ticks_usec(); terrain.prepare(cancelled)
	if cancelled(): return
	if not terrain.prepare_water(cancelled): error=terrain.water_status; return
	if not terrain.prepare_biomes(cancelled): error=terrain.water_status; return
	_set_progress(.4)
	if not terrain.prepare_volumes(cancelled,func(value: float): _set_progress(.4+value*.4)):
		error=terrain.volume_status; return
	if not terrain.prepare_cave_biomes(cancelled): error=terrain.volume_status; return
	_set_progress(.8); mesh=terrain.editable_mesh(cancelled)
	if not terrain.prepare_geometry_keys(cancelled): return
	if cancelled(): return
	_set_progress(1.); elapsed_ms=float(Time.get_ticks_usec()-started)/1000.
func complete() -> bool: return task_id>=0 and WorkerThreadPool.is_task_completed(task_id)
func collect() -> void:
	if task_id>=0: WorkerThreadPool.wait_for_task_completion(task_id); task_id=-1
