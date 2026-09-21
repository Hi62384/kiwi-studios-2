class_name ActorInspectorState
extends Resource
## Persistent editor-only state, keyed by stable actor ID.

@export var actor_states: Dictionary = {}


func restore_from(other: ActorInspectorState) -> void:
	actor_states = other.actor_states.duplicate(true) if other != null else {}
	emit_changed()


func scroll_for(actor_id: String) -> float:
	return float(_actor_state(actor_id).get("scroll", 0.0))


func set_scroll(actor_id: String, value: float) -> void:
	_set_actor_value(actor_id, "scroll", maxf(value, 0.0))


func category_expanded(actor_id: String, category: String) -> bool:
	var categories: Dictionary = _actor_state(actor_id).get("categories", {})
	return bool(categories.get(category, true))


func set_category_expanded(actor_id: String, category: String, expanded: bool) -> void:
	var state := _actor_state(actor_id)
	var categories: Dictionary = state.get("categories", {}).duplicate()
	categories[category] = expanded
	state["categories"] = categories
	actor_states[actor_id] = state
	emit_changed()


func vector_linked(actor_id: String, property_id: StringName) -> bool:
	var links: Dictionary = _actor_state(actor_id).get("links", {})
	return bool(links.get(str(property_id), false))


func set_vector_linked(actor_id: String, property_id: StringName, linked: bool) -> void:
	var state := _actor_state(actor_id)
	var links: Dictionary = state.get("links", {}).duplicate()
	links[str(property_id)] = linked
	state["links"] = links
	actor_states[actor_id] = state
	emit_changed()


func _actor_state(actor_id: String) -> Dictionary:
	return (actor_states.get(actor_id, {}) as Dictionary).duplicate()


func _set_actor_value(actor_id: String, key: String, value: Variant) -> void:
	var state := _actor_state(actor_id)
	if state.get(key) == value:
		return
	state[key] = value
	actor_states[actor_id] = state
	emit_changed()
