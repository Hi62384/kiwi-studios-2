extends RefCounted
## Pure CPU tetrahedral extraction of one solid field. Surface terrain and cave
## voids share the same isosurface, including real openings through the surface.
const OFFSETS:=[Vector3i(0,0,0),Vector3i(1,0,0),Vector3i(0,1,0),Vector3i(1,1,0),Vector3i(0,0,1),Vector3i(1,0,1),Vector3i(0,1,1),Vector3i(1,1,1)]
const TETRAHEDRA:=[[0,1,3,7],[0,3,2,7],[0,2,6,7],[0,6,4,7],[0,4,5,7],[0,5,1,7]]
var terrain: KiwiEnvironmentTerrain
var caves: Array[KiwiTerrainCave]=[]
var cave_bounds: Array[AABB]=[]
var vertices:=PackedVector3Array()
var normals:=PackedVector3Array()
var uv:=PackedVector2Array()
var indices:=PackedInt32Array()
var triangle_kind:=PackedByteArray()
var _edges: Dictionary={}
var _epsilon:=.05
var _origin:=Vector3.ZERO
var _spacing:=Vector3.ONE
var _counts:=Vector3i.ONE
var _values:=PackedFloat32Array()
var _controller: Object
var _configured:=false
func _native() -> Object:
	if _controller==null: _controller=preload("res://Workspaces/EnvironmentWorkspace/TerrainVolumeMesher.cs").new()
	return _controller
func _configure() -> void:
	if _configured: return
	terrain.prepare()
	_native().call("configure",terrain,caves,cave_bounds)
	_configured=true
func build(source: KiwiEnvironmentTerrain,coordinate: Vector2i,sources: Array[KiwiTerrainCave],height_step: float=1.,cell_budget: int=200000,cancel: Callable=Callable()) -> Dictionary:
	terrain=source; source.prepare(cancel)
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("build",source,coordinate,sources,height_step,cell_budget,state)
	state.clear(); _configured=true
	if result.has("vertices"):
		vertices=result.vertices; normals=result.normals; uv=result.uv; indices=result.indices; triangle_kind=result.triangle_kind
		caves.assign(result.caves); cave_bounds.assign(result.cave_bounds); result.erase("caves"); result.erase("cave_bounds")
	return result
func _height(point: Vector2) -> float:
	_configure()
	return _native().call("height",point)
func _void_subtracted(point: Vector3,surface: float) -> float:
	_configure()
	return _native().call("void_subtracted",point,surface)
func density(point: Vector3) -> float:
	_configure()
	return _native().call("density",point)
func _gradient(point: Vector3) -> Vector3: return _native().call("gradient",point)
func _index(point: Vector3i) -> int: return _native().call("index",point)
func _position(index: int) -> Vector3: return _native().call("position",index)
func _edge(a: int,b: int) -> int: return _native().call("edge",a,b)
func _triangle(a: int,b: int,c: int) -> void: _native().call("triangle",a,b,c)
