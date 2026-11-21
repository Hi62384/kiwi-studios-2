extends Control
const Buildings=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_session.gd")
const Source=preload("res://Workspaces/EnvironmentWorkspace/architecture/BuildingSource.cs")
var workspace: Control
var building_id:=""
var current_floor:=0
var tool:="Select"
var zoom:=35.
var pan:=Vector2.ZERO
var snap:=true
var grid_step:=.25
var selected_wall:=-1
var selected_opening:=-1
var cutaway:=false
var view_mode:=1
var _drag: Dictionary={}
var _panning:=false
## Native interaction, drawing and geometry; legacy state/API retained.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","building_plan")
func _ready() -> void:
	_native().call("ready",self)
func authored() -> Resource:
	return _native().call("authored",self)
func to_screen(point: Vector2) -> Vector2:
	return _native().call("to_screen",self,point)
func to_plan(point: Vector2) -> Vector2:
	return _native().call("to_plan",self,point)
func _snap_point(point: Vector2,control: bool=false) -> Vector2:
	return _native().call("snap_point",self,point,control)
func _process(_delta: float) -> void:
	_native().call("process",self)
func _notification(what: int) -> void:
	_native().call("notification",self,what)
func _apply_cutaway() -> void:
	_native().call("apply_cutaway",self)
func _draw() -> void:
	_native().call("draw",self)
func _pick(point: Vector2,openings: bool=true) -> Dictionary:
	return _native().call("pick",self,point,openings)
func _gui_input(event: InputEvent) -> void:
	_native().call("input",self,event)
func _apply(source: Resource,preview: bool) -> bool:
	return _native().call("apply",self,source,preview)
func cancel() -> void:
	_native().call("cancel",self)
static func _replace_points(source: Resource,floor: Dictionary,replacements: Dictionary) -> void:
	_native().call("replace_points",source,floor,replacements)
func _room(source: Resource,floor: Dictionary,box: Rect2,id: String) -> bool:
	return _native().call("room",self,source,floor,box,id)
static func partition_walls(walls: Array) -> Dictionary:
	return _native().call("partition_walls",walls)
static func _set_footprint(source: Resource,floor: Dictionary,polygon: PackedVector2Array) -> void:
	_native().call("set_footprint",source,floor,polygon)
