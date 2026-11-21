extends RefCounted
## Native compatibility checks preserve the existing actor reference/history path.
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service","shader_sample_apply")
static func target_for(tree: SceneTree,kind: String) -> Dictionary: return _native().call("target_for",tree,kind)
static func target_for_model(model: ActorTimeline,registry: ActorRegistry,kind: String) -> Dictionary: return _native().call("target_for_model",model,registry,kind)
static func apply_to_target(target: Dictionary,source: String,sample_name: String) -> String: return _native().call("apply_to_target",target,source,sample_name)
