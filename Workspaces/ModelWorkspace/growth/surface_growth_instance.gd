class_name KiwiSurfaceGrowthInstance
extends MeshInstance3D
var data: KiwiSurfaceGrowthData
var growth_skeleton: Skeleton3D
var pose_signature:=0
var gpu:=preload("res://Workspaces/ModelWorkspace/growth/growth_gpu_attachment.gd").new()
var gpu_bones_key:=0
var gpu_points:=PackedVector3Array()
var appearance_instance: ShaderMaterial
var appearance_key: int=-1
var appearance_source: Resource
func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","growth_instance")
func base_override() -> Material: return _native().call("base_override",self)
func set_growth_time(time: float) -> void: _native().call("set_growth_time",self,time)
func configure(component: KiwiModelComponent,independent: bool=false) -> void: _native().call("configure",self,component,independent)
func update_growth() -> void: _native().call("update_growth",self)
func _process(_delta: float) -> void: update_growth()
func update_lod() -> void: _native().call("update_lod",self)
