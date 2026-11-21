extends RefCounted
const Districts=preload("res://Workspaces/EnvironmentWorkspace/world/world_districts.gd")
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service","world_ui")
static func properties(workspace: Control,id: String,source: Resource,parent: Node) -> void: _native().call("districts",workspace,id,source,parent,Districts.STYLES.PRESETS,PackedStringArray(Districts.CATEGORIES))
static func _set_district(workspace: Control,id: String,settlement: int,district: int,field: String,value: Variant) -> void: _native().call("set_district",workspace,id,settlement,district,field,value)
static func _block(workspace: Control,id: String,settlement: int,block: String,field: String,value: Variant) -> void: _native().call("block",workspace,id,settlement,block,field,value)
