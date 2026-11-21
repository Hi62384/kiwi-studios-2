class_name KiwiGroomTool
extends RefCounted
const TOOLS:=["Brush","Comb","Cut","Grow","Curl","Clump","Density","Length","Smooth","Relax","Part","Feather width","Spread","Protect","Reset region","Guide","Color paint","Select strands"]
var paint_color:=Color.WHITE
var selected_preset:=-1
var clump_start:=0.
var clump_end:=1.
var clump_variation:=.15
var canvas: KiwiModelViewport
var enabled:=false
var tool:="Comb"
var radius:=.35
var strength:=.3
var falloff:=.65
var spacing:=.12
var value:=.3
var frequency:=3.0
var symmetry:=-1
var through:=false
var replace:=false
var target_cut:=false
var drawing:=false
var cursor:=Vector2.ZERO
var previous:=Vector3.ZERO
var last_world:=Vector3.INF
var component_id:=""
var triangle_mesh: TriangleMesh
var hit_key:=0
var last_hit: Dictionary={}
var stroke_id:=""
var touched:=0
var distance_metric:=Basis.IDENTITY
var selected_root:=-1
var selected_guide:=""
var guide_point:=-1
var guide_before: Dictionary={}
var guide_plane:=Plane()
func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","surface_growth_geometry")
func item() -> KiwiModelComponent: return _native().call("item",self)
func active() -> bool: return _native().call("active",self)
func hit(position: Vector2) -> Dictionary: return _native().call("hit",self,position)
func build_grid(data: KiwiSurfaceGrowthData) -> void: _native().call("build_grid",data)
func query(data: KiwiSurfaceGrowthData,center: Vector3,local_radius: float) -> Array[int]: return _native().call("query",data,center,local_radius)
func apply_at(data: KiwiSurfaceGrowthData,center: Vector3,movement: Vector3,normal: Vector3,invert: bool=false) -> int: return _native().call("apply_at",self,data,center,movement,normal,invert)
func stroke(position: Vector2,invert: bool=false) -> void: _native().call("stroke",self,position,invert)
func finish(cancel: bool=false) -> void: _native().call("finish",self,cancel)
func handle(event: InputEvent) -> bool: return _native().call("handle",self,event)
func draw() -> void: _native().call("draw",self)
func create_guide(root_index: int) -> void: _native().call("create_guide",self,root_index)
func guide_frame() -> Transform3D: return _native().call("guide_frame",self)
func draw_guide() -> void: _native().call("draw_guide",self)
func guide_event(event: InputEvent) -> bool: return _native().call("guide_event",self,event)
