class_name Project
extends Resource

@export var project_name: String
@export var actor_inspector_state: ActorInspectorState = ActorInspectorState.new()

func _init(_project_name: String = "") -> void:
	project_name = _project_name
