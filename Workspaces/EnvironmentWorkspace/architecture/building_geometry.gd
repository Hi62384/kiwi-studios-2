extends RefCounted
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","building_geometry")
## CPU polygon generation: openings are absent solid geometry, including colliders.
static func generate(source: Resource,cancel: Callable=Callable()) -> Dictionary:
	return _native().call("generate",source,{"enabled":cancel.is_valid(),"callback":cancel})
static func _cached_slab(footprint: PackedVector2Array,cuts: Array,thickness: float) -> KiwiModelMesh:
	return _native().call("cached_slab",footprint,cuts,thickness)
static func _item(document: KiwiModelDocument,id: String,title: String,parent: String,mesh: KiwiModelMesh,pose: Transform3D,source: Resource,material: int,type: String) -> KiwiModelComponent:
	return _native().call("item",document,id,title,parent,mesh,pose,source,material,type)
static func mesh_key(mesh: KiwiModelMesh,format: int=2) -> int:
	return _native().call("mesh_key",mesh,format)
static func _interior_trim(document: KiwiModelDocument,wall_node: KiwiModelComponent,source: Resource,floor: Dictionary,wall: Dictionary,length: float,height: float) -> void:
	for entry: Dictionary in _native().call("interior_trim",source,floor,wall,length,height):
		_item(document,wall_node.id+":"+str(entry.kind),str(entry.kind).capitalize(),wall_node.id,entry.mesh,Transform3D.IDENTITY,source,3,"interior trim")
static func _wall_finishes(item: KiwiModelComponent,source: Resource,floor: Dictionary,wall: Dictionary) -> void:
	_native().call("wall_finishes",item,source,floor,wall)
static func wall_mesh(length: float,height: float,thickness: float,openings: Array) -> KiwiModelMesh:
	return _native().call("wall_mesh",length,height,thickness,openings)
static func _floor_cuts(source: Resource,floor: Dictionary) -> Array:
	return _native().call("floor_cuts",source,floor)
static func _stair_crosses(source: Resource,stair: Dictionary,elevation: float) -> bool:
	return _native().call("stair_crosses",source,stair,elevation)
static func _stair_bounds(stair: Dictionary) -> Rect2:
	return _native().call("stair_bounds",stair)
static func _build_stairs(document: KiwiModelDocument,source: Resource,warnings: PackedStringArray) -> void:
	warnings.append_array(_native().call("build_stairs",document,source))
static func _upper_landing(stair: Dictionary,height: float) -> KiwiModelMesh:
	return _native().call("upper_landing",stair,height)
static func _connect_support(document: KiwiModelDocument,item: KiwiModelComponent,target: KiwiModelComponent,point: Vector3,key: String) -> void:
	_native().call("connect_support",document,item,target,point,key)
static func _build_supports(document: KiwiModelDocument,source: Resource) -> void:
	_native().call("build_supports",document,source)
static func _post(mesh: KiwiModelMesh,point: Vector3) -> void:
	_native().call("post",mesh,point)
static func _beam(mesh: KiwiModelMesh,a: Vector3,b: Vector3,width: float) -> void:
	_native().call("beam",mesh,a,b,width)
static func _opening_top(opening: Dictionary,x: float,length: float) -> float:
	return _native().call("opening_top",opening,x,length)
static func _panel(mesh: KiwiModelMesh,left: float,right: float,bottom: Vector2,top: Vector2,thickness: float) -> void:
	_native().call("panel",mesh,left,right,bottom,top,thickness)
static func _slab(footprint: PackedVector2Array,cuts: Array,thickness: float) -> KiwiModelMesh:
	return _native().call("slab",footprint,cuts,thickness)
static func _convex_slab(polygon: PackedVector2Array,thickness: float) -> KiwiModelMesh:
	return _native().call("convex_slab",polygon,thickness)
static func _opening(document: KiwiModelDocument,wall: KiwiModelComponent,opening: Dictionary,length: float,source: Resource) -> void:
	_native().call("opening",document,wall,opening,length,source)
static func roof_mesh(source: Resource,warnings: PackedStringArray) -> KiwiModelMesh:
	var result: Dictionary=_native().call("roof_mesh",source)
	warnings.append_array(result.warnings)
	return result.mesh
static func _cancel_requested(state: Dictionary) -> bool:
	var callback: Callable=state.callback
	return callback.is_valid() and bool(callback.call())
