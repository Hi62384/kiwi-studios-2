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
	var a := model.create_actor(definition, 0)
	var c := model.create_actor(definition, 6)
	var b := model.create_actor(definition, 12)
	model.set_parent(c.actor_id, a.actor_id)
	model.set_timeline_children_visible(a.actor_id, false)
	model.focus_actor(b.actor_id)
	check(model.hidden_clip_obstructs_view(model._index_of(a.id)), "Focusing B displays hidden sibling A")
	check(not model.can_place(b.id, a.start_time, b.duration, a.layer), "B cannot overlap A")
	model.focus_actor(a.actor_id)
	check(model.hidden_clip_obstructs_view(model._index_of(b.id)), "Focusing A also displays hidden sibling B")
	check(not model.can_place(a.id, b.start_time, a.duration, b.layer), "A cannot overlap B")
	var states := {a.id: {"start": b.start_time, "duration": a.duration, "layer": b.layer, "offset": a.source_offset}}
	check(not model.can_place_group(states), "Drag preview also rejects sibling overlap")
	check(model.can_place(c.id, b.start_time, c.duration, b.layer), "A's isolated child C can still share space with B")
	model.select(c.id)
	check(not model.hidden_clip_obstructs_view(model._index_of(b.id)), "Selecting only C hides unrelated B obstruction box")
	model.select(a.id, true)
	check(model.hidden_clip_obstructs_view(model._index_of(b.id)), "Selecting A restores B obstruction box")
	model.move_clip(a.id, b.start_time, b.layer)
	check(a.start_time + a.duration <= b.start_time or a.start_time >= b.start_time + b.duration,
		"Moving A snaps away from B")
	model.leave_actor_focus()
	check(model.can_place_group({}), "Returning to section does not reveal sibling overlaps")
	model.history.clear_history()
	print("Sibling collision checks: %d failures" % failures)
	quit(failures)
