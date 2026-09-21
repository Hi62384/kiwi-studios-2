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
	var d := model.create_actor(definition, 18)
	var b := model.create_actor(definition, 12)
	model.set_parent(c.actor_id, a.actor_id)
	model.set_parent(d.actor_id, a.actor_id)
	model.set_timeline_children_visible(a.actor_id, false)
	model.move_clip(c.id, b.start_time, b.layer)
	model.move_clip(d.id, b.start_time, 1)
	var blocker := model.create_actor(definition, b.start_time)
	model.move_clip(blocker.id, b.start_time, 1)
	check(c.start_time == b.start_time and c.layer == b.layer, "Hidden branch can overlap unrelated overview actor")
	var before_c := c.layer
	var before_d := d.layer
	var before_b := b.layer
	var before_blocker := blocker.layer
	var c_time := c.start_time
	var d_time := d.start_time
	var c_duration := c.duration
	var hierarchy := model.actor_for_id(c.actor_id).parent_id
	model.set_timeline_children_visible(a.actor_id, true)
	var revealed_c := c.layer
	var revealed_d := d.layer
	check(model.can_place_group({}), "Revealing merged branches resolves every introduced overlap")
	check(c.layer != before_c and d.layer != before_d, "Conflicting children are relocated to free layers")
	check(b.layer == before_b and blocker.layer == before_blocker, "Existing overview actors keep their layers")
	check(c.start_time == c_time and d.start_time == d_time and c.duration == c_duration
		and model.actor_for_id(c.actor_id).parent_id == hierarchy, "Reveal preserves timing, duration and parenting")
	model.undo()
	check(not model.actor_for_id(a.actor_id).show_timeline_children and c.layer == before_c and d.layer == before_d,
		"One undo restores hidden state and all exact original layers")
	model.redo()
	check(model.actor_for_id(a.actor_id).show_timeline_children and c.layer == revealed_c and d.layer == revealed_d
		and model.can_place_group({}), "One redo restores the exact repaired layout")
	model.set_timeline_children_visible(a.actor_id, false)
	check(c.layer == revealed_c and d.layer == revealed_d, "Collapsing does not unnecessarily shuffle layers")
	model.undo()
	check(model.actor_for_id(a.actor_id).show_timeline_children and c.layer == revealed_c, "Collapsing is undoable too")
	model.history.clear_history()
	print("Reveal overlap checks: %d failures" % failures)
	quit(failures)
