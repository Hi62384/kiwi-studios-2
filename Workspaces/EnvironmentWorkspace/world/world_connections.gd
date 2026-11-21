extends RefCounted
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service","world_connections")
static func _cancel_requested(state: Dictionary) -> bool: return bool(state.enabled) and bool(state.callback.call())
static func augment(source: Resource,nodes: Dictionary,roads: Array[Dictionary],cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("augment",source,nodes,roads,state)
	state.clear(); return result
static func _parts(source: Resource,pair: Dictionary,path: PackedVector3Array,profile: Dictionary,cancel: Callable) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("parts",source,pair,path,profile,state)
	state.clear(); return result
static func _root(groups: Dictionary,id: String) -> String: return _native().call("root",groups,id)
static func _union(groups: Dictionary,a: String,b: String) -> void: _native().call("union",groups,a,b)
static func make_editable(source: Resource,connection: Dictionary) -> Resource: return _native().call("make_editable",source,connection)
