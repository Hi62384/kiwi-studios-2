extends RefCounted
## Native regional instance-buffer installation, culling and hysteresis.
static func _native() -> Object:
	return Engine.get_singleton("KiwiNativeServices").call("service","environment_instance_stream")
static func install(runtime: KiwiEnvironmentRuntime,node: Node3D,result: Dictionary,source: KiwiEnvironmentScatter) -> void:
	_native().call("install",runtime,node,result,source)
static func refresh(runtime: KiwiEnvironmentRuntime,node: Node3D) -> void: _native().call("refresh",runtime,node)
