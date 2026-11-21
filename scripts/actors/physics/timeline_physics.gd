class_name KiwiTimelinePhysics
extends RefCounted
signal status_changed(message: String)
signal fluid_contacts(actor_id: String, scene_time: float, contacts: Array)
signal mesh_damage(actor_id: String,scene_time: float,impact: Dictionary)
signal mesh_fractured(actor_id: String,scene_time: float,pieces: int)
signal connection_broken(actor_id: String,connection_id: String,scene_time: float)
signal destruction_event(event: Dictionary)
## No _physics_process, real-time deltas, Engine.time_scale, or live rigid bodies.
const MAX_CHECKPOINTS := 96
const MAX_CACHE_BYTES := 67108864
const SEEK_BUDGET := 240
const FogMotion=preload("res://scripts/actors/fog/fog_motion_bridge.gd")
var world := KiwiPhysicsCollisionWorld.new()
var fluid := KiwiFluidBridge.new()
var powder := KiwiPowderBridge.new()
var destruction:=KiwiDestructionBridge.new()
var structure:=KiwiStructureBridge.new()
var debris:=KiwiDebrisBridge.new()
var vfx:=KiwiDestructionVFX.new()
var prototypes: Dictionary = {}
var states: Dictionary = {}
var checkpoints: Dictionary = {}
var display_states: Dictionary = {}
var base_display_states: Dictionary={}
var signature := ""
var dirty := true
var pending := false
var status := ""
var steps_taken := 0
var generation := 0
var rate := 60
var origin := 0.0
var step := 0
var requested_time := NAN
var _model: RefCounted
var _runtimes: Dictionary = {}
var _floor_states: Dictionary = {}
var _floor_step := -1
var _applied_time := NAN
var _warnings: Array[String] = []
var _baking_actor := ""
var _baking_actors: Dictionary={}
var bake_cancelled:=false
var bake_progress:=0.0
func is_baking(id: String) -> bool:
	return _native_physics().is_baking(self,id)

func cancel_bake() -> void:
	_native_physics().cancel_bake(self)

func mark_dirty() -> void:
	_native_physics().mark_dirty(self)

func invalidate_asset(path: String) -> void:
	_native_physics().invalidate_asset(self,path)

func dispose(keep_prepared: bool=false) -> void:
	_native_physics().dispose(self,keep_prepared)

func restore_visuals() -> void:
	_native_physics().restore_visuals(self)

func _runtime(actor_id: String) -> ActorRuntime:
	return _native_physics().runtime(self,actor_id)

func _local(actor: ActorData, time: float) -> float:
	return _native_physics().local(self,actor,time)

func animated_world(actor_id: String, time: float, simulated_parent: bool = false, visited: Dictionary = {}) -> Transform3D:
	return _native_physics().animated_world(self,actor_id,time,simulated_parent,visited)

func bone_world(actor_id: String, bone_name: String, time: float) -> Transform3D:
	return _native_physics().bone_world(self,actor_id,bone_name,time)

func attachment(actor_id: String, bone: String, offset: Vector3, time: float, fallback: Transform3D) -> Vector3:
	return _native_physics().attachment(self,actor_id,bone,offset,time,fallback)

func source_transform(actor_id: String,config: Dictionary,time: float) -> Transform3D:
	return _native_physics().source_transform(self,actor_id,config,time)

func _warn(message: String) -> void:
	_native_physics().warn(self,message)

func _setup(model: RefCounted, runtimes: Dictionary, new_signature: String) -> void:
	_native_physics().setup(self,model,runtimes,new_signature)

func _snapshot(value: Dictionary) -> Dictionary:
	return _native_physics().snapshot(value)

func _depth(id: String) -> int:
	return _native_physics().depth(self,id)

func _cache() -> void:
	_native_physics().cache(self)

func evaluate(model: RefCounted, runtimes: Dictionary, time: float, budget: int = SEEK_BUDGET) -> void:
	_native_physics().evaluate(self,model,runtimes,time,budget)

func _initialize(id: String, state: Dictionary, config: Dictionary, time: float) -> void:
	_native_physics().initialize(self,id,state,config,time)

func _simulation_geometry(id: String, state: Dictionary, captured: Dictionary={}) -> Dictionary:
	return _native_physics().simulation_geometry(self,id,state,captured)

func _ensure_graph(id: String, state: Dictionary, config: Dictionary) -> void:
	_native_physics().ensure_graph(self,id,state,config)

func _step(time: float, dt: float) -> void:
	_native_physics().step(self,time,dt)

func _gravity(config: Dictionary) -> Vector3:
	return _native_physics().gravity(config)

func _environment_wind(actor: ActorData,time: float) -> Vector3:
	return _native_physics().environment_wind(self,actor,time)

func _events(config: Dictionary, local: float, h: float) -> Dictionary:
	return _native_physics().events(config,local,h)

func _rigid(id: String, state: Dictionary, config: Dictionary, target: Transform3D, time: float, h: float) -> void:
	_native_physics().rigid(self,id,state,config,target,time,h)

func _pin_positions(id: String, state: Dictionary, config: Dictionary, time: float) -> Dictionary:
	return _native_physics().pin_positions(self,id,state,config,time)

func _particles(id: String, state: Dictionary, config: Dictionary, time: float, h: float) -> void:
	_native_physics().particles(self,id,state,config,time,h)

func _skeleton(id: String, state: Dictionary, config: Dictionary, time: float, h: float) -> void:
	_native_physics().skeleton(self,id,state,config,time,h)

func _baked(bake: Dictionary, time: float) -> Dictionary:
	return _native_physics().baked(self,bake,time)

func _interpolate_points(result: Dictionary,left: Dictionary,right: Dictionary,fraction: float) -> void:
	_native_physics().interpolate_points(result,left,right,fraction)

func _apply(time: float) -> void:
	_native_physics().apply(self,time)

func freeze(model: RefCounted, actor: ActorData) -> void:
	_native_physics().freeze(self,model,actor)

func bake(editor: Control, actor: ActorData, start: float, end: float) -> String:
	var native:=_native_physics()
	var job: Dictionary=native.bake_begin(self,editor,actor,start,end)
	if not str(job.error).is_empty(): return str(job.error)
	var tree:=editor.get_tree()
	var error:=""
	for index in int(job.count):
		if not native.bake_valid(editor,job): break
		native.bake_seek(self,editor,job,index)
		while pending:
			await tree.process_frame
			if not native.bake_valid(editor,job): break
			editor._evaluate_runtimes()
		if not native.bake_valid(editor,job): break
		error=native.bake_sample(self,job)
		if not error.is_empty(): break
		if index%12==0: await tree.process_frame
	return native.bake_finish(self,editor,job,error)

func bake_group(editor: ActorTimelineEditor,start: float,end: float,sample_rate: int=60,progress: Callable=Callable(),options: Dictionary={}) -> String:
	var native:=_native_physics()
	var job: Dictionary=native.group_bake_begin(self,editor,start,end,sample_rate,options)
	if not job.has("cache"): return str(job.error)
	var tree:=editor.get_tree()
	var error:=str(job.error)
	for index in int(job.count):
		if not error.is_empty(): break
		var result: Dictionary=native.group_bake_seek(self,editor,job,index)
		error=str(result.error)
		if not error.is_empty(): break
		if not result.reused:
			while pending and not bake_cancelled:
				await tree.process_frame
				if not native.group_bake_valid(editor,job): break
				editor._evaluate_runtimes()
			error=native.group_bake_sample(self,editor,job,index)
			if not error.is_empty(): break
		if progress.is_valid(): progress.call(index+1,int(job.count),job.cache.bytes)
		if index%8==0: await tree.process_frame
	return native.group_bake_finish(self,editor,job,error)

static func _native_physics() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","timeline_physics")
