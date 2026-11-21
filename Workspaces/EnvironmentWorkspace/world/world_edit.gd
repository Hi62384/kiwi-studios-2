extends RefCounted
static var pending: Dictionary={}
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service","world_edit")
static func _invoke_cancel(state: Dictionary) -> void:
	if state.callback.is_valid(): state.callback.call()
static func source(session: KiwiEnvironmentSession,id: String) -> Resource: return _native().call("source",session,id,pending)
static func cancel(session: KiwiModelSession) -> void: _native().call("cancel",session,pending)
static func request(session: KiwiEnvironmentSession,id: String,authored: Resource,label: String="Edit world") -> Dictionary:
	var state: Dictionary=_native().call("begin_request",session,id,authored,label,pending,{"callback":cancel.bind(session)})
	if state.get("done",false): return state.result
	var tree:=Engine.get_main_loop() as SceneTree
	while not state.job.complete():
		_native().call("poll",session,state)
		await tree.process_frame
	return _native().call("finish",session,state,pending)
static func flush(session: KiwiModelSession) -> bool:
	var tree:=Engine.get_main_loop() as SceneTree; var success:=true
	while pending.has(session.get_instance_id()):
		var state: Dictionary=pending[session.get_instance_id()]; await tree.process_frame; success=success and state.success
	return success
