class_name KiwiRigPreset
extends Resource
@export var title := "Custom rig"
@export var bones: Array[Dictionary]=[]
@export var metadata: Dictionary={}

# Legacy binary schema and compatibility checks for callers still in GDScript.
const Native=preload("res://Workspaces/ModelWorkspace/rig/RigPreset.cs")
static func accepts(value: Resource) -> bool:
	return value!=null and (value is KiwiRigPreset or value.get_script()==Native)
static func create_native() -> Resource:
	return Native.new()
