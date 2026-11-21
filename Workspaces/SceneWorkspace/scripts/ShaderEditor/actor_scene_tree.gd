class_name ActorSceneTree
extends Tree
## Hierarchy workspace for timeline actors. Drag an actor onto another actor to
## reparent it, or onto the Scene root to unparent it.

var model: ActorTimeline
var registry: ActorRegistry
var _rebuilding := false
var _rebuild_scheduled := false
var _items: Dictionary = {}
var _selection_anchor: String = ""
var _structure_signature: String = ""


func _ready() -> void:
	_native_tree().ready(self)

func _section_button_clicked(item: TreeItem, _column: int, id: int, mouse_button: int) -> void:
	_native_tree().section_button_clicked(self,item,_column,id,mouse_button)

func _section_edited() -> void:
	_native_tree().section_edited(self)

func setup(timeline: ActorTimeline, types: ActorRegistry) -> void:
	_native_tree().setup(self,timeline,types)

func _exit_tree() -> void:
	_native_tree().exit_tree(self)

func _request_rebuild() -> void:
	_native_tree().request_rebuild(self)

func _refresh_from_model() -> void:
	_native_tree().refresh_from_model(self)

func _rebuild() -> void:
	_native_tree().rebuild(self)

func _model_structure_signature() -> String:
	return _native_tree().model_structure_signature(self)

func _sync_selection() -> void:
	_native_tree().sync_selection(self)

func _add_children(parent_item: TreeItem, parent_id: String, children: Dictionary,
		collapsed: Dictionary, visited: Dictionary) -> void:
	_native_tree().add_children(self,parent_item,parent_id,children,collapsed,visited)

func _input(event: InputEvent) -> void:
	_native_tree().input(self,event)

func _gui_input(event: InputEvent) -> void:
	_native_tree().gui_input(self,event)

func _select_range(clicked_actor_id: String) -> void:
	_native_tree().select_range(self,clicked_actor_id)

func _visible_actor_ids() -> Array[String]:
	return _native_tree().visible_actor_ids(self)

func _get_drag_data(at_position: Vector2) -> Variant:
	return _native_tree().get_drag_data(self,at_position)

func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	return _native_tree().can_drop_data(self,at_position,data)

func _drop_data(at_position: Vector2, data: Variant) -> void:
	_native_tree().drop_data(self,at_position,data)

func _apply_theme() -> void:
	_native_tree().apply_theme(self)


static func _native_tree() -> Object:
	return Engine.get_singleton("KiwiNativeServices").service("actor_scene_tree")
