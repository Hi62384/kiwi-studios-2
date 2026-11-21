class_name KiwiEnvironmentViewport
extends KiwiModelViewport
signal brush_settings_changed
signal asset_placed(path: String,point: Vector3,normal: Vector3)
signal cave_replaced(terrain_id: String,cave: KiwiTerrainCave)
signal water_replaced(terrain_id: String,source: KiwiTerrainHydrology)
signal biomes_replaced(terrain_id: String,source: KiwiTerrainBiomes)
signal world_replaced(world_id: String,source: Resource)
const BRUSH_TOOLS:=["Raise","Lower","Smooth","Flatten","Level to height","Terrace","Noise","Ridge","Valley","Pinch / sharpen","Relax","Erode brush","Stamp"]
var renderer:=KiwiEnvironmentRuntime.new()
var environment_tool:="Select"
var brush_radius:=2.
var brush_strength:=.2
var brush_falloff:=1.
var brush_spacing:=.2
var brush_target_height:=0.
var brush_terrace_step:=.5
var brush_square:=false
var brush_symmetry_x:=false
var brush_symmetry_z:=false
var stamp_path:=""
var stamp_image: Image
var placement_asset:=""
var _painting:=false
var _painting_id:=""
var _last_dab:=Vector2.ZERO
var _flatten_height:=0.
var _brush_hit: Dictionary={}
var _triangles: Dictionary={}
var _drop_preview: Node3D
var _drop_path:=""
var _preview_environment: Environment
var _environment_key:=0
var cave_tool:=preload("res://Workspaces/EnvironmentWorkspace/terrain/environment_cave_tool.gd").new()
var water_tool:=preload("res://Workspaces/EnvironmentWorkspace/terrain/environment_water_tool.gd").new()
var biome_tool:=preload("res://Workspaces/EnvironmentWorkspace/terrain/environment_biome_tool.gd").new()
var road_tool:=preload("res://Workspaces/EnvironmentWorkspace/WorldRoadTool.cs").new()

func _environment_native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_viewport")
func _ready() -> void: _environment_native().call("setup",self)
func capture_state() -> Dictionary: return _environment_native().call("capture",self)
func restore_state(state: Dictionary) -> void: _environment_native().call("restore",self,state)
func frame(all: bool=false) -> void: _environment_native().call("frame",self,all)
func environment_session() -> KiwiEnvironmentSession: return _environment_native().call("environment_session",self)
func sync() -> void: _environment_native().call("sync",self)
func _sync_lighting() -> void: _environment_native().call("sync_lighting",self)
func geometry() -> Dictionary: return _environment_native().call("geometry",self)
func _process(delta: float) -> void: _environment_native().call("process",self,delta)
func _pick(point: Vector2,terrain_only: bool,excluded: Array[String]) -> Dictionary: return _environment_native().call("pick",self,point,terrain_only,excluded)
func pick(point: Vector2,excluded: Array[String]=[]) -> Dictionary: return _pick(point,false,excluded)
func pick_terrain(point: Vector2) -> Dictionary: return _pick(point,true,[])
func _draw_overlay() -> void: _environment_native().call("draw",self)
func _dab(point: Vector2,subtract: bool) -> void: _environment_native().call("dab",self,point,subtract)
func _gui_input(event: InputEvent) -> void: _environment_native().call("handle",self,event)
func _can_drop_data(point: Vector2,data: Variant) -> bool: return _environment_native().call("can_drop_data",self,point,data)
func _drop_data(point: Vector2,data: Variant) -> void: _environment_native().call("drop_data",self,point,data)
func _placement_point(point: Vector3,terrain_id: String="") -> Vector3: return _environment_native().call("placement_point",self,point,terrain_id)
func _clear_preview() -> void: _environment_native().call("clear_preview",self)
func _notification(what: int) -> void:
	if what==NOTIFICATION_DRAG_END: _environment_native().call("clear_preview",self)
func cancel_all() -> void: _environment_native().call("cancel_all",self)
func _finish_brush(cancelled: bool=false) -> void: _environment_native().call("finish_brush",self,cancelled)
