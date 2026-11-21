class_name KiwiGrowthAppearanceUI
extends RefCounted
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations")
static func styles(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void: _native().call("growth_styles",workspace,parent,data)
static func load_style(workspace: KiwiModelWorkspace,data: KiwiSurfaceGrowthData) -> void: _native().call("growth_load_style",workspace,data)
static func save_style(workspace: KiwiModelWorkspace,data: KiwiSurfaceGrowthData) -> void: _native().call("growth_save_style",workspace,data)
static func build(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void: _native().call("growth_appearance",workspace,parent,data)
static func asset_actions(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void: _native().call("growth_asset_actions",workspace,parent,data)
static func save(workspace: KiwiModelWorkspace,data: KiwiSurfaceGrowthData) -> void: _native().call("growth_save_material",workspace,data)
static func name_field(workspace: KiwiModelWorkspace,parent: Node,resource: Resource) -> void: _native().call("growth_name_field",workspace,parent,resource)
