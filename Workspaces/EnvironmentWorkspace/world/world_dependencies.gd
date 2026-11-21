extends RefCounted
## Native dependency scheduling/history merge. Shared world edit await remains a bridge.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","world_dependencies")
static func state(workspace: Control) -> Dictionary: return _native().call("state",workspace)
static func suspend(workspace: Control) -> void: _native().call("suspend",workspace)
static func poll(workspace: Control) -> void: _native().call("poll",workspace)
static func _update(workspace: Control,session: KiwiEnvironmentSession,id: String,desired: Resource,key: int) -> void:
	_native().call("update",workspace,session,id,desired,key)
static func _cost(snapshot: Dictionary) -> int: return _native().call("cost",snapshot)
static func _invoke_callback(callbacks: Dictionary,key: String) -> void: callbacks[key].call()
