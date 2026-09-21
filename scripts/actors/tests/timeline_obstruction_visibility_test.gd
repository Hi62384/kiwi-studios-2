extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var registry := ActorRegistry.new()
	BasicActors.register_all(registry)
	var definition := registry.get_definition(&"point_3d")
	var model := ActorTimeline.new()
	var parent := model.create_actor(definition, 0)
	var focused := model.create_actor(definition, 6)
	var child := model.create_actor(definition, 12)
	var nested := model.create_actor(definition, 18)
	var hidden := model.create_actor(definition, 24)
	var sibling := model.create_actor(definition, 30)
	model.set_parent(focused.actor_id, parent.actor_id)
	model.set_parent(child.actor_id, focused.actor_id)
	model.set_parent(nested.actor_id, focused.actor_id)
	model.set_parent(hidden.actor_id, nested.actor_id)
	model.set_parent(sibling.actor_id, parent.actor_id)
	model.set_timeline_children_visible(nested.actor_id, false)
	model.focus_actor(focused.actor_id)
	check(not model.hidden_clip_obstructs_view(model._index_of(hidden.id)), "Box obstructing only unselected child stays hidden")
	check(model.hidden_clip_obstructs_view(model._index_of(parent.id))
		and model.hidden_clip_obstructs_view(model._index_of(sibling.id)), "Selected actor reveals parent and sibling blockers")
	model.select(nested.id)
	check(model.hidden_clip_obstructs_view(model._index_of(hidden.id)), "Selecting blocked child reveals descendant blocker")
	model.select(child.id)
	check(not model.hidden_clip_obstructs_view(model._index_of(hidden.id)), "Changing selection hides irrelevant descendant box immediately")
	model.select(nested.id, true)
	check(model.hidden_clip_obstructs_view(model._index_of(hidden.id)), "Any blocked actor in multiselection reveals the box")
	model.select("")
	check(model.hidden_clip_obstructs_view(model._index_of(parent.id))
		and model.hidden_clip_obstructs_view(model._index_of(sibling.id)), "Common blockers appear with no selection")
	check(not model.hidden_clip_obstructs_view(model._index_of(hidden.id)), "Partial blockers stay hidden with no selection")
	check(not model.can_place(nested.id, hidden.start_time, nested.duration, hidden.layer), "Hiding box does not disable actual collision")
	model.focus_actor(child.actor_id)
	model.select("")
	check(model.hidden_clip_obstructs_view(model._index_of(parent.id)), "One-actor view displays shared ancestor blockers without selection")
	model.create_section()
	check(not model.hidden_clip_obstructs_view(model._index_of(parent.id)), "Empty view has no obstruction boxes")
	model.history.clear_history()
	print("Obstruction visibility checks: %d failures" % failures)
	quit(failures)
