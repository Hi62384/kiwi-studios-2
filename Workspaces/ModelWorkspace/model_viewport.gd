class_name KiwiModelViewport
extends Control
signal command_requested(command: String)
signal gesture_finished
signal notice(message: String)
var _state_native: RefCounted=preload("res://Workspaces/ModelWorkspace/ModelViewportState.cs").new()
var _input_native: RefCounted=preload("res://Workspaces/ModelWorkspace/ModelViewportInput.cs").new()
var _sync_native: RefCounted=preload("res://Workspaces/ModelWorkspace/ModelViewportSync.cs").new()
var _transforms_native: RefCounted=preload("res://Workspaces/ModelWorkspace/ModelViewportTransforms.cs").new()
var _navigation_native: RefCounted=preload("res://Workspaces/ModelWorkspace/ModelViewportNavigation.cs").new()
var _picking_native: RefCounted=preload("res://Workspaces/ModelWorkspace/ModelViewportPicking.cs").new()
var _overlay_native: RefCounted=preload("res://Workspaces/ModelWorkspace/ModelViewportOverlay.cs").new()
var session: KiwiModelSession
var viewport := SubViewport.new()
var world := Node3D.new()
var camera := Camera3D.new()
var display := TextureRect.new()
var overlay := Control.new()
var grid := MeshInstance3D.new()
var visuals: Dictionary = {}
var evaluated: Dictionary = {}
var signatures: Dictionary = {}
var preview_hidden: Dictionary={}
var upload_budget_usec:=4000
var _material_scope: Dictionary={}
var _natural_preview_time:=0.
var tool := "Move"
var local_axes := false
var xray := false
var wireframe := false
var show_normals := false
var show_edges := true
var grid_step := .25
var snap := false
var snap_kind := "Grid"
var align_surface := false
var proportional := false
var radius := 1.5
var strength := .3
var sculpt := ""
var push_pull := false
var _extruding := false
var _extrude_amount := 0.
var _extrude_numeric := ""
var target := Vector3.ZERO
var distance := 7.
var yaw := .65
var pitch := -.4
var fly_speed := 4.
var _pending_sync := true
var _navigating := false
var _panning := false
var _orbiting := false
var _pressed := false
var _box := false
var _start := Vector2.ZERO
var _mouse := Vector2.ZERO
var _drag := false
var _modal := false
var _axis := -1
var _plane := false
var _pivot := Vector3.ZERO
var _axes: Array[Vector3] = []
var _start_world := Vector3.ZERO
var _source: KiwiModelDocument
var _numeric := ""
var _create := ""
var _create_phase := 0
var _create_origin := Vector3.ZERO
var _create_component: KiwiModelComponent
var _selected_vertices := PackedInt32Array()
var _selected_lookup: Dictionary = {}
var _weights := PackedFloat32Array()
var _weights_radius := -1.
var rig_tool: KiwiRigViewport
var groom_tool:=KiwiGroomTool.new()
const COLORS := [Color("f3848c"),Color("8bddae"),Color("85bdff")]

func _ready() -> void: _state_native.call("setup",self)

func _resize() -> void: viewport.size=Vector2i(maxi(64,int(size.x)),maxi(64,int(size.y)))
func request_sync() -> void: _pending_sync=true; overlay.queue_redraw()
func update_camera() -> void: _navigation_native.call("update_camera",self)
func set_view(view: String) -> void: _navigation_native.call("set_view",self,view)
func frame(all: bool=false) -> void: _navigation_native.call("frame",self,all)
func rebuild_grid() -> void: _navigation_native.call("rebuild_grid",self)
func sync() -> void: _sync_native.call("sync",self)
func flush_preview() -> void:
	while _pending_sync and is_inside_tree(): sync(); await get_tree().process_frame
func _process(delta: float) -> void: _sync_native.call("process",self,delta)

func project(point: Vector3) -> Vector2: return _picking_native.call("project",self,point)
func ray(point: Vector2) -> Dictionary: return _picking_native.call("ray",self,point)
func pick(point: Vector2, excluded: Array[String]=[]) -> Dictionary: return _picking_native.call("pick",self,point,excluded)
func face_at(item: KiwiModelComponent, point: Vector2) -> int: return _picking_native.call("face_at",self,item,point)
func visible_point(point: Vector3) -> bool: return _picking_native.call("visible_point",self,point)
func element_at(point: Vector2) -> int: return _picking_native.call("element_at",self,point)
func select_at(point: Vector2, additive: bool) -> void: _picking_native.call("select_at",self,point,additive)
func box_select(rect: Rect2, additive: bool) -> void: _picking_native.call("box_select",self,rect,additive)

func geometry() -> Dictionary: return _picking_native.call("geometry",self)
func handle_at(point: Vector2, data: Dictionary) -> int: return _picking_native.call("handle_at",self,point,data)
func begin_transform(index: int, point: Vector2, modal: bool=false) -> bool: return _transforms_native.call("begin_transform",self,index,point,modal)
func screen_plane(point: Vector2, pivot: Vector3, normal: Vector3=Vector3.ZERO) -> Vector3: return _transforms_native.call("screen_plane",self,point,pivot,normal)
func update_transform(point: Vector2, ctrl: bool=false) -> void: _transforms_native.call("update_transform",self,point,ctrl)
func _source_screen() -> Vector2: return project(_pivot)
func finish_transform(cancel: bool=false) -> void: _transforms_native.call("finish_transform",self,cancel)

func begin_extrusion(point: Vector2) -> bool: return _transforms_native.call("begin_extrusion",self,point)
func update_extrusion(point: Vector2, ctrl: bool=false) -> void: _transforms_native.call("update_extrusion",self,point,ctrl)
func finish_extrusion(cancel: bool=false) -> void: _transforms_native.call("finish_extrusion",self,cancel)
func snap_target(point: Vector2) -> Dictionary: return _transforms_native.call("snap_target",self,point)

func _draw_overlay() -> void:
	_overlay_native.call("draw",self)

func _draw_handles_and_navigation(custom_hint: String="") -> void:
	_overlay_native.call("draw_handles_and_navigation",self,custom_hint)

func start_creation(kind: String) -> void: _input_native.call("start_creation",self,kind)
func _creation_input(event: InputEvent) -> bool: return _input_native.call("creation_input",self,event)

func sculpt_at(point: Vector2, previous: Vector2, erase: bool=false) -> void: _transforms_native.call("sculpt_at",self,point,previous,erase)

func _gui_input(event: InputEvent) -> void: _input_native.call("handle",self,event)

func capture_state() -> Dictionary: return _state_native.call("capture",self)
func cancel_all() -> void: _state_native.call("cancel_all",self)
func restore_state(state: Dictionary) -> void: _state_native.call("restore",self,state)
