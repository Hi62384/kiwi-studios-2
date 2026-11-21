extends RefCounted
## Static strand vertices, dynamic source vertices and a bounded guide table.
## Each instance owns its pose textures/material, while the shader is shared.
var material: ShaderMaterial
var base_key: int=-1
var roots_key: int=0
var binding_key: int=0
var source_key: int=0
var motion_key: int=0
var textures: Dictionary={}
var guide_ids: Array=[]
var uploads:=0
var uploaded_bytes:=0
var bounds:=AABB()
var regional: Dictionary={}
var growth_extent:=.01
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","growth_gpu")
static func supports(data: KiwiSurfaceGrowthData) -> bool: return _native().call("supports",data)
func upload(name: String,values: PackedFloat32Array) -> Texture2D: return _native().call("upload",self,name,values)
func point_table(points: PackedVector3Array) -> PackedFloat32Array: return _native().call("point_table",points)
func update(instance: Variant,posed: PackedVector3Array,skinned: bool) -> void: _native().call("update",self,instance,posed,skinned)
func bind_regions(instance: Variant,deformed: bool=true) -> void: _native().call("bind_regions",self,instance,deformed)
