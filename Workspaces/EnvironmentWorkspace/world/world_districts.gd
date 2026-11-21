extends RefCounted
## Authored districts classify whole road blocks; later entries take priority.
const CATEGORIES=["Residential","Commercial","Industrial","Downtown","Suburban","Mixed Use","Civic","Park/Green Space","Agricultural","Custom"]
const STYLES=preload("res://Workspaces/EnvironmentWorkspace/architecture/building_styles.gd")
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service","world_districts")
static func create(category: String,polygon: PackedVector2Array) -> Dictionary: return _native().call("create",category,polygon,STYLES.PRESETS)
static func validate(settlement: Dictionary) -> PackedStringArray: return _native().call("validate",settlement)
static func _validate_rules(settings: Dictionary) -> PackedStringArray: return _native().call("validate_rules",settings)
static func rules(block: Dictionary,settlement: Dictionary) -> Dictionary: return _native().call("rules",block,settlement)
static func effective(settlement: Dictionary,settings: Dictionary) -> Dictionary: return _native().call("effective",settlement,settings)
static func accept(plot: Dictionary,settings: Dictionary) -> bool: return _native().call("accept",plot,settings)
static func _area(polygon: PackedVector2Array) -> float: return _native().call("area",polygon)
static func _simple(polygon: PackedVector2Array) -> bool: return _native().call("simple",polygon)
