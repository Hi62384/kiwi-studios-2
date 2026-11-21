class_name ShaderSampleCatalog
extends RefCounted
## Source records are compiled into C#; all consumers receive independent copies.
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service","shader_samples")
static func get_entries() -> Array[Dictionary]: return _native().call("get_entries")
static func get_entry(id: String) -> Dictionary: return _native().call("get_entry",id)
static func get_code(entry_or_id: Variant) -> String: return _native().call("get_code",entry_or_id)
static func entries() -> Array[Dictionary]: return get_entries()
static func entry(id: String) -> Dictionary: return get_entry(id)
