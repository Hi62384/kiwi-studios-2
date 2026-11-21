class_name KiwiRigViewport
extends RefCounted
const Native=preload("res://Workspaces/ModelWorkspace/rig/RigViewport.cs")
var _native: RefCounted=Native.new()
# Typed compatibility interface; state and behavior live in RigViewport.cs.
var canvas: KiwiModelViewport:
	get: return _native.get("canvas")
	set(value): _native.set("canvas",value)
var editor: KiwiRigEditor:
	get: return _editor
	set(value):
		_editor=value
		_native.set("editor",value.get("_native") if value!=null else null)
var _editor: KiwiRigEditor
var nodes: Dictionary={}:
	get: return _native.get("nodes")
	set(value): _native.set("nodes",value)
var signatures: Dictionary={}:
	get: return _native.get("signatures")
	set(value): _native.set("signatures",value)
var heat_signature: Dictionary={}:
	get: return _native.get("heat_signature")
	set(value): _native.set("heat_signature",value)
var construction: String:
	get: return _native.get("construction")
	set(value): _native.set("construction",value)
var depth: float:
	get: return _native.get("depth")
	set(value): _native.set("depth",value)
var brush_radius: float:
	get: return _native.get("brush_radius")
	set(value): _native.set("brush_radius",value)
var brush_strength: float:
	get: return _native.get("brush_strength")
	set(value): _native.set("brush_strength",value)
var brush_value: float:
	get: return _native.get("brush_value")
	set(value): _native.set("brush_value",value)
var brush_mode: String:
	get: return _native.get("brush_mode")
	set(value): _native.set("brush_mode",value)
var paint_hidden: bool:
	get: return _native.get("paint_hidden")
	set(value): _native.set("paint_hidden",value)
var chain: Variant=null:
	get: return _native.get("chain")
	set(value): _native.set("chain",value)
var chain_parent: int:
	get: return _native.get("chain_parent")
	set(value): _native.set("chain_parent",value)
var placing: bool:
	get: return _native.get("placing")
	set(value): _native.set("placing",value)
var cursor: Vector3:
	get: return _native.get("cursor")
	set(value): _native.set("cursor",value)
var mouse: Vector2:
	get: return _native.get("mouse")
	set(value): _native.set("mouse",value)
var drag: String:
	get: return _native.get("drag")
	set(value): _native.set("drag",value)
var drag_end: bool:
	get: return _native.get("drag_end")
	set(value): _native.set("drag_end",value)
var drag_axis: int:
	get: return _native.get("drag_axis")
	set(value): _native.set("drag_axis",value)
var drag_origin: Vector3:
	get: return _native.get("drag_origin")
	set(value): _native.set("drag_origin",value)
var drag_point: Vector3:
	get: return _native.get("drag_point")
	set(value): _native.set("drag_point",value)
var drag_mouse: Vector2:
	get: return _native.get("drag_mouse")
	set(value): _native.set("drag_mouse",value)
var drag_normal: Vector3:
	get: return _native.get("drag_normal")
	set(value): _native.set("drag_normal",value)
var drag_before: Array[Dictionary]=[]:
	get: return _native.get("drag_before")
	set(value): _native.set("drag_before",value)
var drag_axes: Array[Vector3]=[]:
	get: return _native.get("drag_axes")
	set(value): _native.set("drag_axes",value)
var drag_length: float:
	get: return _native.get("drag_length")
	set(value): _native.set("drag_length",value)
var weight_before: Dictionary={}:
	get: return _native.get("weight_before")
	set(value): _native.set("weight_before",value)
var weight_after: Dictionary={}:
	get: return _native.get("weight_after")
	set(value): _native.set("weight_after",value)
var touched: Dictionary={}:
	get: return _native.get("touched")
	set(value): _native.set("touched",value)
var geometry_cache: Dictionary={}:
	get: return _native.get("geometry_cache")
	set(value): _native.set("geometry_cache",value)
var stroke_geometry: Dictionary={}:
	get: return _native.get("stroke_geometry")
	set(value): _native.set("stroke_geometry",value)
var last_paint: int:
	get: return _native.get("last_paint")
	set(value): _native.set("last_paint",value)
var hover_hit: Dictionary={}:
	get: return _native.get("hover_hit")
	set(value): _native.set("hover_hit",value)
var compare_rest: bool:
	get: return _native.get("compare_rest")
	set(value): _native.set("compare_rest",value)
var stroke_session: KiwiModelSession:
	get: return _native.get("stroke_session")
	set(value): _native.set("stroke_session",value)
var weight_tool: String:
	get: return _native.get("weight_tool")
	set(value): _native.set("weight_tool",value)
var selected_only: bool:
	get: return _native.get("selected_only")
	set(value): _native.set("selected_only",value)
var region: Dictionary={}:
	get: return _native.get("region")
	set(value): _native.set("region",value)
var region_start: Vector2:
	get: return _native.get("region_start")
	set(value): _native.set("region_start",value)
var region_additive: bool:
	get: return _native.get("region_additive")
	set(value): _native.set("region_additive",value)

func sync() -> void:
	_native.call("sync")

func world_bones() -> Array[Transform3D]:
	return _native.call("world_bones")

func pick_bone(point: Vector2, joints_only: bool=false) -> Dictionary:
	return _native.call("pick_bone",point,joints_only)

func plane_hit(point: Vector2, origin: Vector3, normal: Vector3) -> Variant:
	return _native.call("plane_hit",point,origin,normal)

func placement(point: Vector2) -> Vector3:
	return _native.call("placement",point)

func handles() -> Dictionary:
	return _native.call("handles")

func handle_at(point: Vector2, geometry: Dictionary) -> int:
	return _native.call("handle_at",point,geometry)

func draw() -> void:
	_native.call("draw")

func begin_joint(index: int, end: bool, point: Vector2) -> void:
	_native.call("begin_joint",index,end,point)

func begin_pose(index: int, point: Vector2) -> bool:
	return _native.call("begin_pose",index,point)

func update_drag(point: Vector2, snap: bool=false) -> void:
	_native.call("update_drag",point,snap)

func _paint_geometry(item: KiwiModelComponent) -> Dictionary:
	return _native.call("_paint_geometry",item)

func paint(point: Vector2, subtract: bool=false, force: bool=false) -> void:
	_native.call("paint",point,subtract,force)

func finish(cancel: bool=false) -> void:
	_native.call("finish",cancel)

func handle_event(event: InputEvent) -> bool:
	return _native.call("handle_event",event)

func select_region(rect: Rect2, additive: bool=false) -> void:
	_native.call("select_region",rect,additive)

func fill_region() -> void:
	_native.call("fill_region")
