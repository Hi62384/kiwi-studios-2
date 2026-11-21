extends RefCounted
## Saved architecture stays authoritative. CPU documents are cached; GPU detail
## exists near the camera, or stays available for complete offline collision.
const Builder=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_geometry.gd")
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/BuildingSource.cs")
var runtime: KiwiEnvironmentRuntime
var entries: Dictionary={}
var retired: Array[RefCounted]=[]
var physics_full:=false
var builds:=0
var cache_hits:=0
var cache_bytes:=0
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_building_stream")
func failure() -> String: return _native().call("failure",self)
func sync(item: KiwiModelComponent,node: Node3D,metadata: Dictionary) -> void: _native().call("sync",self,item,node,metadata)
func _retire(entry: Dictionary) -> void: _native().call("retire",self,entry)
func dispose() -> void: _native().call("dispose",self)
func ready(need_physics: bool) -> bool: return _native().call("ready",self,need_physics)
func _policy(entry: Dictionary) -> Dictionary: return _native().call("policy",self,entry)
func process() -> void: _native().call("process",self)
