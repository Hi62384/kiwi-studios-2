extends RefCounted
const NAMES=["Modern City","Suburban Town","Rural Countryside","Medieval Village","Mountain Region","Tropical Island","Fantasy World"]
const Cities=preload("res://Workspaces/EnvironmentWorkspace/world/world_settlement.gd")
const Districts=preload("res://Workspaces/EnvironmentWorkspace/world/world_districts.gd")
const Forests=preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd")
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
static var pending: Dictionary={}
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service","world_recipes")
static func empty(source: Resource) -> bool: return _native().call("empty",source)
static func configure(source: Resource,name: String) -> Dictionary: return _native().call("configure",source,name,Districts.STYLES.PRESETS,Forests.SPECIES)
static func _has_cancel(session: KiwiModelSession) -> bool: return session.pending_source_cancel.is_valid()
static func _clear_cancel(session: KiwiModelSession,state: Dictionary) -> void:
	if session.pending_source_cancel==state.cancel_callback: session.pending_source_cancel=Callable()
static func cancel(session: KiwiModelSession) -> void: _native().call("cancel",session,pending)
static func flush(session: KiwiModelSession) -> bool:
	var tree:=Engine.get_main_loop() as SceneTree; var success:=true
	while pending.has(session.get_instance_id()):
		var state: Dictionary=pending[session.get_instance_id()]
		while pending.get(session.get_instance_id(),{})==state: await tree.process_frame
		success=success and bool(state.get("success",false))
	return success
static func request(workspace: Control,id: String,name: String) -> void:
	var session: KiwiEnvironmentSession=workspace.session
	if not _native().call("can_start",workspace,session,pending): return
	if not await preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd").flush(session): return
	if not is_instance_valid(workspace) or not _native().call("same_workspace",workspace,session): return
	var state: Dictionary=_native().call("begin_recipe",workspace,session,id,name,pending,{"callback":cancel.bind(session)},Districts.STYLES.PRESETS,Forests.SPECIES)
	if state.is_empty(): return
	var tree:=Engine.get_main_loop() as SceneTree
	while not state.finished:
		_native().call("poll_recipe",workspace if is_instance_valid(workspace) else null,session,state,pending)
		if not state.finished: await tree.process_frame
