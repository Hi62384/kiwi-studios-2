extends RefCounted
const Geometry=preload("res://Workspaces/EnvironmentWorkspace/world/road_geometry.gd")
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","road_network")
static func _cancel_requested(state: Dictionary) -> bool: return bool(state.enabled) and bool(state.callback.call())
static func graph(source: Resource,cancel: Callable=Callable(),settlement_layout: Dictionary={}) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("graph",source,state,settlement_layout)
	state.clear(); return result
static func _canonical(input: Dictionary) -> Dictionary: return _native().call("canonical",input)
static func _candidates(paths: Array,cancel: Callable) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("candidates",paths,state)
	state.clear(); return result
static func _node(nodes: Dictionary,position: Vector3,prefix: String) -> String: return _native().call("node",nodes,position,prefix)
static func generate(source: Resource,cancel: Callable=Callable(),development: KiwiModelDocument=null) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("generate",source,state,development)
	state.clear(); return result
static func _populate(document: KiwiModelDocument,source: Resource,layout: Dictionary,graph_data: Dictionary,cancel: Callable) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("populate",document,source,layout,graph_data,state)
	state.clear(); return result
static func _junction_plan(graph_data: Dictionary) -> Dictionary: return _native().call("junction_plan",graph_data)
static func _item(document: KiwiModelDocument,id: String,title: String,parent: String,mesh: KiwiModelMesh,material: Material,owner: String="") -> KiwiModelComponent:
	return _native().call("item",document,id,title,parent,mesh,material,owner)
