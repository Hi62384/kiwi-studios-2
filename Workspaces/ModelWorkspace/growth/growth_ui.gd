class_name KiwiGrowthUI
extends RefCounted
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","model_workspace_operations")
static func icon(title: String) -> Texture2D: return _native().call("growth_icon",title)
static func add_menu(workspace: KiwiModelWorkspace) -> void: _native().call("growth_add_menu",workspace)
static func build(workspace: KiwiModelWorkspace,item: KiwiModelComponent,parent: VBoxContainer) -> void: _native().call("growth_build",workspace,item,parent)
static func choice(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData,key: String,title: String,choices: Array) -> void: _native().call("growth_choice",workspace,parent,data,key,title,choices)
static func build_guides(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void: _native().call("growth_build_guides",workspace,parent,data)
static func build_presets(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void: _native().call("growth_build_presets",workspace,parent,data)
static func build_individual(workspace: KiwiModelWorkspace,parent: Node,data: KiwiSurfaceGrowthData) -> void: _native().call("growth_build_individual",workspace,parent,data)
