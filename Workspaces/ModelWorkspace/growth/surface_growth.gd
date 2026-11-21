class_name KiwiSurfaceGrowth
extends RefCounted
const TYPES:=["Hair","Fur","Feathers"]
const MAX_ROOTS:=20000
const MAX_VERTICES:=1000000
const GROWTH_FORMAT:=(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
static func _geometry_native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","surface_growth_geometry")
static func _settings_native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","surface_growth_settings")
static func base_settings(data: KiwiSurfaceGrowthData) -> Dictionary:
	return _settings_native().call("base_settings",data)
static func prepare_regions(data: KiwiSurfaceGrowthData) -> void:
	_settings_native().call("prepare_regions",data)
static func root_settings(data: KiwiSurfaceGrowthData,root: Dictionary) -> Dictionary:
	return _settings_native().call("root_settings",data,root)
static func region_material(data: KiwiSurfaceGrowthData,index: int) -> Material:
	return _settings_native().call("region_material",data,index)
static func defaults(kind: int=0) -> Dictionary:
	return _settings_native().call("defaults",kind)
static func add(session: KiwiModelSession,kind: int) -> String:
	return _geometry_native().call("add",session,kind)
static func add_layered_fur(session: KiwiModelSession) -> String:
	return _geometry_native().call("add_layered_fur",session)
static func prepare(document: KiwiModelDocument,item: KiwiModelComponent,source: KiwiModelComponent) -> String:
	return _geometry_native().call("prepare",document,item,source)
static func triangle_key(a: Vector3,b: Vector3,c: Vector3) -> String:
	return _geometry_native().call("triangle_key",a,b,c)
static func point_frame(data: KiwiSurfaceGrowthData,root: Dictionary,positions: PackedVector3Array) -> Transform3D:
	return _geometry_native().call("point_frame",data,root,positions)
static func posed_points(data: KiwiSurfaceGrowthData,skeleton: Skeleton3D) -> PackedVector3Array:
	return _geometry_native().call("posed_points",data,skeleton)
static func style(data: KiwiSurfaceGrowthData,root: Dictionary) -> Dictionary:
	return _geometry_native().call("style",data,root)
static func curve(data: KiwiSurfaceGrowthData,root: Dictionary,segments: int=-1) -> PackedVector3Array:
	return _geometry_native().call("curve",data,root,segments)
static func motion_delta(data: KiwiSurfaceGrowthData,root: Dictionary,t: float) -> Vector3:
	return _geometry_native().call("motion_delta",data,root,t)
static func resample_curve(points: PackedVector3Array,count: int) -> PackedVector3Array:
	return _geometry_native().call("resample_curve",points,count)
static func cut_plane(data: KiwiSurfaceGrowthData,plane: Plane) -> int:
	return _geometry_native().call("cut_plane",data,plane)
static func render(data: KiwiSurfaceGrowthData,positions: PackedVector3Array=PackedVector3Array()) -> ArrayMesh:
	return _geometry_native().call("render",data,positions)
static func render_chunk(data: KiwiSurfaceGrowthData,positions: PackedVector3Array,first: int,last: int) -> ArrayMesh:
	return _geometry_native().call("render_chunk",data,positions,first,last)
static func render_roots(data: KiwiSurfaceGrowthData,positions: PackedVector3Array,first: int,last: int,region: int) -> ArrayMesh:
	return _geometry_native().call("render_roots",data,positions,first,last,region)
