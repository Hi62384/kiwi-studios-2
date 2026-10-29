class_name Project
extends Resource

@export var project_name: String
@export var actor_inspector_state: ActorInspectorState = ActorInspectorState.new()
@export var fog_rendering: Dictionary = {}

func _init(_project_name: String = "") -> void:
	project_name = _project_name
