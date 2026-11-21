extends RefCounted
static func build(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations").call("growth_regions",workspace,parent,data)
