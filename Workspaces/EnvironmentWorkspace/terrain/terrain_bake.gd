extends RefCounted
## State/default/await adapter; incremental full-resolution bake runs in C#.
var cancelled:=false
var progress:=0.
var error:=""
func cancel() -> void: cancelled=true
func run(runtime: KiwiEnvironmentRuntime,id: String,owner: Node,include_water: bool=false) -> KiwiModelDocument:
	var job=preload("res://Workspaces/EnvironmentWorkspace/TerrainBakeJob.cs").new()
	owner.add_child(job)
	job.start(self,runtime,id,owner,include_water)
	return await job.completed
static func _freeze(source: Material) -> Material:
	return Engine.get_singleton("KiwiNativeServices").call("service","terrain_bake").call("freeze",source)
