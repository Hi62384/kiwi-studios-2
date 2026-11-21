extends RefCounted
## Await bridge for the remaining world/architecture flush APIs.
static func _controller(workspace: Control,create: bool=true) -> Node:
	return _native_edits().controller(workspace,create)
static func request(workspace: Control,id: String,key: String,value: Variant,finished: bool) -> void:
	_native_edits().request(workspace,id,key,value,finished)
static func finish(workspace: Control) -> void:
	_native_edits().finish(workspace)
static func cancel(workspace: Control) -> void:
	_native_edits().cancel(workspace)
static func flush(workspace: Control) -> bool:
	if not await preload("res://Workspaces/EnvironmentWorkspace/world/world_recipes.gd").flush(workspace.session): return false
	if not await preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd").flush(workspace.session): return false
	if not await preload("res://Workspaces/EnvironmentWorkspace/architecture/building_edit.gd").flush(workspace.session): return false
	var state: Dictionary=_native_edits().begin_flush(workspace)
	while not _native_edits().flush_done(workspace,state): await workspace.get_tree().process_frame
	return _native_edits().finish_flush(workspace,state)

static func _native_edits() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("natural_edit_api")
