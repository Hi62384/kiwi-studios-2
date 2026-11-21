class_name KiwiEnvironmentRuntime
extends Node3D
## Shared by preview and Scene actor. Terrain chunks and repeated native meshes
## are renderer data, not thousands of independently authored scene actors.
var document: KiwiEnvironmentDocument
var nodes: Dictionary={}
var component_index: Dictionary={}
var preview_hidden: Dictionary={}
var signatures: Dictionary={}
var errors:=PackedStringArray()
var warnings:=PackedStringArray()
var chunks_rebuilt:=0
var instances:=0
var default_ground:=StandardMaterial3D.new()
var include_lighting:=false
var include_atmosphere:=false
var sun: DirectionalLight3D
var progressive:=false
var cave_cutaway:=false
var upload_budget_usec:=4000
var pending_chunks: Dictionary={}
var pending_assets: Dictionary={}
var _material_scope: Dictionary={}
var _scatter_mesh_scope: Dictionary={}
var _asset_lod_scope: Dictionary={}
var priority_camera: Camera3D
var preview_time:=0.
var animate_preview:=false
var biome_preview_id:=""
var biome_preview_terrain:=""
var scatter_jobs: Dictionary={}
var _retired_scatter: Array[RefCounted]=[]
var _stream_time:=0.
var stream_nodes: Dictionary={}
var _stream_camera: Camera3D
var _stream_pose:=Transform3D.IDENTITY
var _stream_root:=Transform3D.IDENTITY
var _stream_visible:=false
var building_stream:=preload("res://Workspaces/EnvironmentWorkspace/world/world_building_stream.gd").new()
var weather_particles: Dictionary={}
func _init() -> void: building_stream.runtime=self; default_ground.albedo_color=Color("718365"); default_ground.roughness=1.
func _ready() -> void: building_stream.runtime=self; add_to_group("environment_runtimes")

func _collision_native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_collision")
func _weather_native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_weather")
func update_weather_particles(state: Dictionary,camera: Camera3D) -> void:
	_weather_native().call("update",self,state,camera)
func _make_weather_particles(kind: String) -> GPUParticles3D:
	return _weather_native().call("make",kind)

func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_runtime")
func configure(source: KiwiEnvironmentDocument) -> void: _native().call("configure",self,source)
func _process(delta: float) -> void: _native().call("process",self,delta)
func _next_chunk() -> String: return _native().call("next_chunk",self)
func _poll_scatter() -> void: _native().call("poll_scatter",self)
func _exit_tree() -> void: _native().call("release",self)
func cancel_scatter_generation() -> void: _native().call("cancel_scatter_generation",self)
func sync() -> void: _native().call("sync",self)
func geometry_ready(physics_full: bool=false) -> bool: return _native().call("geometry_ready",self,physics_full)
func sync_lighting() -> void: _native().call("sync_lighting",self)
func _terrain(item: KiwiModelComponent,node: Node3D,metadata: Dictionary) -> void: _native().call("terrain",self,item,node,metadata)
func _build_chunk(terrain: KiwiEnvironmentTerrain,coordinate: Vector2i,chunk: MeshInstance3D,key: int) -> void:
	_collision_native().call("build_chunk",self,terrain,coordinate,chunk,key)
func _biome_overlay(owner: Node3D,terrain: KiwiEnvironmentTerrain) -> Material: return _native().call("biome_overlay",self,owner,terrain)
func _assign_chunk_materials(chunk: MeshInstance3D,material: Material,paint: Material,collision: bool) -> void:
	_collision_native().call("assign_chunk_materials",chunk,material,paint,collision)
func _asset(item: KiwiModelComponent,node: Node3D,metadata: Dictionary) -> void: _native().call("asset",self,item,node,metadata)
static func _native_asset_key(item: KiwiModelComponent) -> int:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_runtime").call("native_asset_key",item)
func _world_render(item: KiwiModelComponent,node: Node3D) -> void: _native().call("world_render",self,item,node)
static func _lod_mesh(source: Mesh,cache: Dictionary) -> Mesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_runtime").call("lod_mesh",source,cache)
func _sync_asset_collision(node: Node3D,enabled: bool) -> void: _collision_native().call("sync_asset_collision",node,enabled)
func _scatter(item: KiwiModelComponent,node: Node3D,metadata: Dictionary) -> void: _native().call("scatter",self,item,node,metadata)
func _install_scatter(node: Node3D,result: Dictionary,source: KiwiEnvironmentScatter) -> void: _native().call("install_scatter",self,node,result,source)
func _scatter_mesh(source: Mesh,lod: bool=false) -> Mesh: return _native().call("scatter_mesh",self,source,lod)
func _scatter_collision(node: Node3D,result: Dictionary,source: KiwiEnvironmentScatter) -> void: _native().call("scatter_collision",self,node,result,source)
