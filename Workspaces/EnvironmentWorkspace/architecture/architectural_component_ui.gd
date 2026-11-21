extends RefCounted
static func properties(workspace: Control,item: KiwiModelComponent,parent: Node) -> bool:
	return Engine.get_singleton("KiwiNativeServices").call("service","architectural_component_ui").call("properties",workspace,item,parent)
