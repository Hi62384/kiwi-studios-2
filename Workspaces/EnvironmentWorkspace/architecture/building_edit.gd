extends RefCounted
## Native job ownership and revision guards; only coroutine waiting remains here.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","building_edit")
static func source(session: KiwiModelSession,id: String) -> Resource:
	return _native().call("source",session,id)
static func cancel(session: KiwiModelSession) -> void:
	_native().call("cancel",session)
static func request(session: KiwiModelSession,id: String,authored: Resource,label: String) -> Dictionary:
	var native:=_native()
	var state: Dictionary=native.call("start",session,id,authored,label)
	if state.has("result"): return state.result
	var tree:=Engine.get_main_loop() as SceneTree
	while not native.call("poll",session,state):
		await tree.process_frame
	return native.call("finish",session,state)
static func flush(session: KiwiModelSession) -> bool:
	var tree:=Engine.get_main_loop() as SceneTree
	var success:=true
	var native:=_native()
	while true:
		var state: Dictionary=native.call("pending",session)
		if state.is_empty(): break
		await tree.process_frame
		success=success and bool(state.success)
	return success
