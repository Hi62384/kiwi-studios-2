extends RefCounted
const Worlds=preload("res://Workspaces/EnvironmentWorkspace/world/world_session.gd")
const Edit=preload("res://Workspaces/EnvironmentWorkspace/world/world_edit.gd")
static func _native() -> Object: return Engine.get_singleton("KiwiNativeServices").call("service","world_ui")
static func capture(workspace: Control) -> Dictionary: return _native().call("capture",workspace)
static func restore(workspace: Control,state: Dictionary) -> void: _native().call("restore",workspace,state)
static func apply(workspace: Control,id: String,authored: Resource,label: String="Edit world") -> void: _native().call("apply",workspace,id,authored,label)
static func properties(workspace: Control,item: KiwiModelComponent,parent: Node) -> bool:
	var forests=preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd")
	var catalog:={"road_types":PackedStringArray(preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").TYPES),"forest_profiles":PackedStringArray(forests.PROFILES),"props":PackedStringArray(preload("res://Workspaces/EnvironmentWorkspace/world/world_prop_library.gd").NAMES),"layers":PackedStringArray(forests.LAYERS),"recipes":PackedStringArray(preload("res://Workspaces/EnvironmentWorkspace/world/world_recipes.gd").NAMES),"styles":preload("res://Workspaces/EnvironmentWorkspace/architecture/building_styles.gd").PRESETS,"species":forests.SPECIES,"district_categories":PackedStringArray(preload("res://Workspaces/EnvironmentWorkspace/world/world_districts.gd").CATEGORIES)}
	return _native().call("properties",workspace,item,parent,catalog)
static func _compact_choices(parent: Node) -> void: _native().call("compact_choices",parent)
static func _connections(workspace: Control,item: KiwiModelComponent,source: Resource,parent: Node) -> void: _native().call("connections",workspace,item,source,parent,PackedStringArray(preload("res://Workspaces/EnvironmentWorkspace/world/road_section.gd").TYPES))
static func _add_props(workspace: Control,id: String,mode: String) -> void: _native().call("add_props",workspace,id,mode)
static func _props(workspace: Control,id: String,source: Resource,parent: Node) -> void: _native().call("props",workspace,id,source,parent)
static func _forests(workspace: Control,id: String,source: Resource,parent: Node) -> void: _native().call("forests",workspace,id,source,parent,PackedStringArray(preload("res://Workspaces/EnvironmentWorkspace/world/world_forests.gd").LAYERS))
static func _grade(workspace: Control,id: String,remove: bool) -> void: _native().call("grade",workspace,id,remove)
static func _settlements(workspace: Control,id: String,source: Resource,parent: Node) -> void: _native().call("settlements",workspace,id,source,parent)
