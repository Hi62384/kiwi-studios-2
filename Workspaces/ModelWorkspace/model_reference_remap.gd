extends RefCounted
## Static type interface while saved hierarchy consumers migrate.
static func component(item: KiwiModelComponent,mapping: Dictionary) -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","model_reference_remap").component(item,mapping)
static func _structure(settings: Dictionary,mapping: Dictionary) -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","model_reference_remap")._structure(settings,mapping)
static func terrain(source: KiwiEnvironmentTerrain,mapping: Dictionary) -> void:
	Engine.get_singleton("KiwiNativeServices").call("service","model_reference_remap").terrain(source,mapping)
