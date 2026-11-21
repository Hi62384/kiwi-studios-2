extends RefCounted
const MODES=["Roadside","Region","Clusters","Grid","Anchors"]
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","world_props")
static func _cancel_requested(state: Dictionary) -> bool: return bool(state.enabled) and bool(state.callback.call())
static func create(source: Resource,model: Variant,mode: String="Roadside") -> Resource:
	return _native().call("create",source,model,mode)
static func build(document: KiwiModelDocument,source: Resource,layout: Dictionary,graph: Dictionary,cancel: Callable=Callable()) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("build",document,source,layout,graph,state)
	state.clear(); return result
static func _anchors(rule: Dictionary,graph: Dictionary,cancel: Callable) -> Dictionary:
	var state:={"enabled":cancel.is_valid(),"callback":cancel}
	var result: Dictionary=_native().call("anchors",rule,graph,state)
	state.clear(); return result
