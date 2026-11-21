extends RefCounted
static func build(studio:KiwiImageWorkspace)->void:Engine.get_singleton("KiwiNativeServices").service("image_workspace_ui").repair_build(studio)
static func _fill_and_finish(tool:RefCounted)->void:
 await tool.fill_selection()
 tool.finish()
