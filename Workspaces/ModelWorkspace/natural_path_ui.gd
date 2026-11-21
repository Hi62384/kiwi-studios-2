extends RefCounted
static func open(workspace: Control,id: String) -> void: Engine.get_singleton("KiwiNativeServices").call("service","natural_ui").open_path(workspace,id)
