class_name KiwiEnvironmentTerrain
extends Resource
## Procedural base and authored edits are distinct. Runtime chunks share edge
## heights/normals; brush history stores only changed samples.
const CHUNK_CELLS:=32
const VOLUME_FORMAT_VERSION:=1
const BASE_CACHE_BYTES:=64*1024*1024
const MAX_RESOLUTION:=1025
const PROXY_RESOLUTION:=129
const GEOLOGY:=["Mixed","Granite","Limestone","Sandstone","Basalt","Volcanic"]
static var _base_cache_size: int:
	get:
		return Engine.get_singleton("KiwiNativeServices").call("service","terrain_data").call("cache_bytes")
@export var dimensions:=Vector2(32,32)
@export var resolution:=65
@export var seed:=1
@export_enum("Mixed","Granite","Limestone","Sandstone","Basalt","Volcanic") var geology:=0
@export var base_height:=0.
@export var amplitude:=0.
@export var frequency:=.05
@export var edits:=PackedFloat32Array()
@export var material_mask:=PackedFloat32Array()
@export var revision:=0
@export var generation: KiwiTerrainGenerator
@export var erosion: Array[KiwiTerrainErosion]=[]
@export var hydrology: KiwiTerrainHydrology
@export var water_delta:=PackedFloat32Array()
@export var water_data: Dictionary={}
@export var water_key:=0
@export var biomes: KiwiTerrainBiomes
@export var biome_data: Dictionary={}
@export var biome_key:=0
@export var cave_biome_data: Dictionary={}
@export var cave_biome_key:=0
@export var chunk_keys: Dictionary={}
@export var chunk_keys_stamp:=0
var _tracked_key_edits:=false
var water_status:=""
@export var caves: Array[KiwiTerrainCave]=[]
@export var voxel_height:=.5
@export var voxel_cell_budget:=500000
@export var lod_enabled:=true
@export var lod_bias:=1.
@export var render_distance:=0.
@export var volume_chunks: Dictionary={}
var volume_status:=""
var volume_chunks_rebuilt:=0
var _volume_validity_key:=0
var _volume_validity:=false
var derived_fields: Dictionary={}
var _base:=PackedFloat32Array()
var _base_key:=0
var dirty_chunks: Dictionary={}
var _chunk_cache: Dictionary={}

func _data_native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","terrain_data")
func validate() -> PackedStringArray:
	return _data_native().call("validate",self)
func erosion_signature() -> int:
	return _data_native().call("erosion_signature",self)
func cave_signature() -> int:
	return _data_native().call("cave_signature",self)
func signature() -> int:
	return _data_native().call("signature",self)
func climate_key() -> int:
	return _data_native().call("climate_key",self)
func cave_climate_key() -> int:
	return _data_native().call("cave_climate_key",self)
func cave_biomes_valid() -> bool:
	return _data_native().call("cave_biomes_valid",self)
func prepare_cave_biomes(cancel: Callable=Callable()) -> bool:
	return _data_native().call("prepare_cave_biomes",self,{"enabled":cancel.is_valid(),"callback":cancel})
func cave_biome_at(point: Vector3) -> Dictionary:
	return _data_native().call("cave_biome_at",self,point)
func biomes_valid() -> bool:
	return _data_native().call("biomes_valid",self)
func prepare_biomes(cancel: Callable=Callable()) -> bool:
	return _data_native().call("prepare_biomes",self,{"enabled":cancel.is_valid(),"callback":cancel})
func biome_at(point: Vector2) -> Dictionary:
	return _data_native().call("biome_at",self,point)
func hydrology_key() -> int:
	return _data_native().call("hydrology_key",self)
func water_valid() -> bool:
	prepare(); return hydrology==null or (water_key==hydrology_key() and water_delta.size()==resolution*resolution)
func height_snapshot() -> Dictionary:
	# Duplicate the packed buffers: GDScript assignments share mutable arrays.
	# This avoids per-sample UI conversion while giving workers private data.
	prepare(); return {"resolution":resolution,"base":_base.duplicate(),"edits":edits.duplicate(),"water":water_delta.duplicate() if hydrology!=null and hydrology.enabled and water_delta.size()==resolution*resolution else PackedFloat32Array()}
func prepare_water(cancel: Callable=Callable()) -> bool:
	return _data_native().call("prepare_water",self,{"enabled":cancel.is_valid(),"callback":cancel})
func _water_cave_ground(ground: PackedFloat32Array,cancel: Callable) -> Dictionary:
	return _data_native().call("water_cave_ground",self,ground,{"enabled":cancel.is_valid(),"callback":cancel})
static func _water_void_distance(point: Vector3,sources: Array[KiwiTerrainCave]) -> float:
	return Engine.get_singleton("KiwiNativeServices").call("service","terrain_data").call("water_void_distance",point,sources)
func water_at(point: Vector3) -> Dictionary:
	return _data_native().call("water_at",self,point)
func chunk_bounds(coordinate: Vector2i) -> AABB:
	return _data_native().call("chunk_bounds",self,coordinate)
func needs_volume(coordinate: Vector2i) -> bool:
	return _data_native().call("needs_volume",self,coordinate)
func _local_samples_key(coordinate: Vector2i,materials: bool) -> int:
	return _data_native().call("local_samples_key",self,coordinate,materials)
func volume_key(coordinate: Vector2i) -> int:
	return _data_native().call("volume_key",self,coordinate)
func volume_signature() -> int:
	return _data_native().call("volume_signature",self)
func volumes_valid() -> bool:
	return _data_native().call("volumes_valid",self)
func prepare_volumes(cancel: Callable=Callable(),progress: Callable=Callable()) -> bool:
	return _data_native().call("prepare_volumes",self,{"enabled":cancel.is_valid(),"callback":cancel},{"enabled":progress.is_valid(),"callback":progress})
func chunk_geometry_key(coordinate: Vector2i,include_paint: bool=true) -> int:
	return _data_native().call("chunk_geometry_key",self,coordinate,include_paint)
func _geometry_stamp() -> int:
	return _data_native().call("geometry_stamp",self)
func prepare_geometry_keys(cancel: Callable=Callable()) -> bool:
	return _data_native().call("prepare_geometry_keys",self,{"enabled":cancel.is_valid(),"callback":cancel})
func prepare(cancel: Callable=Callable()) -> void:
	var native:=_data_native()
	var key: int=native.call("base_signature",self)
	if _base_key==key and _base.size()==resolution*resolution and edits.size()==resolution*resolution and material_mask.size()==resolution*resolution: return
	native.call("prepare_data",self,key,{"enabled":cancel.is_valid(),"callback":cancel})
static func _data_bytes(data: Variant) -> int:
	return Engine.get_singleton("KiwiNativeServices").call("service","terrain_data").call("data_bytes",data)
func mark_all_dirty() -> void:
	_data_native().call("mark_all_dirty",self)
func height(x: int,z: int) -> float:
	if _base.size()!=resolution*resolution or edits.size()!=resolution*resolution: prepare()
	var index:=clampi(x,0,resolution-1)+clampi(z,0,resolution-1)*resolution
	return _base[index]+edits[index]+_water_offset(index)
func _water_offset(index: int) -> float: return water_delta[index] if hydrology!=null and hydrology.enabled and water_delta.size()==resolution*resolution else 0.
func position(x: int,z: int) -> Vector3: return Vector3((float(x)/(resolution-1)-.5)*dimensions.x,height(x,z),(float(z)/(resolution-1)-.5)*dimensions.y)
func normal(x: int,z: int) -> Vector3:
	var dx: float=(height(x+1,z)-height(x-1,z))/(dimensions.x/(resolution-1)*2.); var dz: float=(height(x,z+1)-height(x,z-1))/(dimensions.y/(resolution-1)*2.)
	return Vector3(-dx,1.,-dz).normalized()
func sample(point: Vector2) -> Dictionary:
	prepare(); var uv:=point/dimensions+Vector2.ONE*.5
	if uv.x<0. or uv.y<0. or uv.x>1. or uv.y>1.: return {}
	var p:=uv*(resolution-1); var cell:=Vector2i(p.floor()); var f:=p-Vector2(cell); var h:=lerpf(lerpf(height(cell.x,cell.y),height(cell.x+1,cell.y),f.x),lerpf(height(cell.x,cell.y+1),height(cell.x+1,cell.y+1),f.x),f.y)
	return {"height":h,"normal":normal(cell.x,cell.y)}

func sculpt(center: Vector2,radius: float,strength: float,falloff: float,mode: int,flatten_height: float=0.,options: Dictionary={}) -> Dictionary:
	return _data_native().call("sculpt",self,center,radius,strength,falloff,mode,flatten_height,options)
func apply_samples(samples: Dictionary) -> void:
	_data_native().call("apply_samples",self,samples)
func mark_samples_dirty(samples: Dictionary) -> void:
	_data_native().call("mark_samples_dirty",self,samples)
func apply_material_samples(samples: Dictionary) -> void:
	_data_native().call("apply_material_samples",self,samples)
func paint_material(center: Vector2,radius: float,strength: float,falloff: float,erase: bool) -> Dictionary:
	return _data_native().call("paint_material",self,center,radius,strength,falloff,erase)
func chunk_mesh(chunk: Vector2i,cutaway: bool=false,smooth_paint: bool=false) -> ArrayMesh:
	return _data_native().call("chunk_mesh",self,chunk,cutaway,smooth_paint)
func _volume_native_mesh(data: Dictionary,cutaway: bool=false,smooth_paint: bool=false) -> ArrayMesh:
	return _data_native().call("volume_native_mesh",self,data,cutaway,smooth_paint)
func editable_mesh(cancel: Callable=Callable()) -> KiwiModelMesh:
	return _data_native().call("editable_mesh",self,{"enabled":cancel.is_valid(),"callback":cancel})
static func _report_progress(state: Dictionary,value: float) -> void:
	var callback: Callable=state.callback
	if callback.is_valid(): callback.call(value)
