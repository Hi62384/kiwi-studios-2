extends RefCounted
## Static/default-argument compatibility for the native render adapter.
static func prepare(source: ArrayMesh,item: Resource) -> ArrayMesh:
	return Engine.get_singleton("KiwiNativeServices").call("service","natural_render").prepare(source,item)
static func time(root: Node,value: float,visited: Variant=null) -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","natural_render").time(root,value,{} if visited==null else visited)
