class_name KiwiSurfaceGrowthData
extends Resource
@export var source_id: String=""
@export var settings: Dictionary={}
@export var faces:=PackedInt32Array()
@export var roots: Array[Dictionary]=[]
@export var topology: int=0
@export var source_points:=PackedVector3Array()
@export var surface_triangles: Array[Dictionary]=[]
@export var source_weights: Array[Dictionary]=[]
@export var source_skin: Skin
@export var rigid_bone: int=-1
@export var rigid_offset:=Transform3D.IDENTITY
@export var source_to_rig:=Transform3D.IDENTITY
@export var groom: Dictionary={}
@export var groom_enabled:=true
@export var groom_layers: Array[Dictionary]=[]
@export var guides: Dictionary={}
@export var protected_faces:=PackedInt32Array()
@export var generation_key: int=0
@export var error: String=""
@export var source_valid:=true
@export var appearance: KiwiGrowthMaterial
@export var growth_style: KiwiGrowthStyle
@export var rendering: Dictionary={"automatic_lod":true,"near":4.,"far":16.,"minimum_density":.15}
@export var brush_presets: Array[Dictionary]=[]
@export var individual: Dictionary={}
@export var regions: Array[Dictionary]=[]
var root_regions: Dictionary={}
var region_settings: Dictionary={}
var region_revision: int=-1
var region_base: int=0
var region_signature: int=0
var surface_regions: Dictionary={}
var lod_density: float=1.
var lod_upper: float=1.
var lod_detail: int=0
var render_final:=false
var base_cache: Dictionary={}
var base_signature:=0
var motion_guides: Dictionary={}
var motion_weights: Dictionary={}
var motion_influence: float=1.
var motion_binding: int=0
var gpu_motion:=false
var revision:=0
var generated_usec:=0
var groom_usec:=0
var candidate_grid: Dictionary={}
var grid_size:=.25
var render_cache: ArrayMesh
var render_key:=0
var pending: Dictionary={}
var effective: Dictionary={}
var effective_revision: int=-1
var chunks: Dictionary={}
var chunk_signature:=0
var chunk_revision:=-1
var dirty_chunks: Dictionary={}
var surface_chunks: Dictionary={}
var material: Material
var chunk_builds:=0
func copy_data() -> KiwiSurfaceGrowthData:
	var result:=KiwiSurfaceGrowthData.new(); result.source_id=source_id; result.settings=settings.duplicate(true); result.faces=faces.duplicate(); result.roots=roots.duplicate(true); result.topology=topology; result.source_points=source_points; result.source_weights=source_weights.duplicate(true); result.source_skin=source_skin; result.source_to_rig=source_to_rig; result.appearance=appearance.copy_material() if appearance!=null else null; result.growth_style=growth_style.duplicate(true) if growth_style!=null else null
	for region: Dictionary in regions:
		var row:=region.duplicate(true)
		if row.get("material") is KiwiGrowthMaterial: row.material=row.material.copy_material()
		if row.get("style") is KiwiGrowthStyle: row.style=row.style.duplicate(true)
		result.regions.append(row)
	result.individual=individual.duplicate(true); result.brush_presets=brush_presets.duplicate(true); result.rendering=rendering.duplicate(true); result.source_valid=source_valid; result.rigid_bone=rigid_bone; result.rigid_offset=rigid_offset; result.surface_triangles=surface_triangles.duplicate(true); result.groom=groom.duplicate(true); result.groom_layers=groom_layers.duplicate(true); result.guides=guides.duplicate(true); result.groom_enabled=groom_enabled; result.protected_faces=protected_faces; result.generation_key=generation_key; result.error=error; result.revision=revision; return result
