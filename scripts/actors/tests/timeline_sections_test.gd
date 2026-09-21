extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var registry := ActorRegistry.new()
	BasicActors.register_all(registry)
	var definition := registry.get_definition(&"point_3d")
	var model := ActorTimeline.new()
	check(model.sections.size() == 1, "Default section exists")
	var first := model.create_actor(definition, 0)
	var child := model.create_actor(definition, 6)
	model.set_parent(child.actor_id, first.actor_id)
	var second_section := model.create_section()
	check(model.visible_clips().is_empty() and model.selected_ids.is_empty(), "Switching sections clears selection and filters clips")
	var second := model.create_actor(definition, 0)
	check(second.start_time == 0 and model.actor_for_id(second.actor_id).section_id == second_section.id,
		"Creation uses selected section, without collisions from other sections")
	model.select_all()
	check(model.selected_ids == [second.id], "Select all only includes selected section")
	check(not model.can_set_parent(first.actor_id, second.actor_id), "Prevent cross-section transform parents")
	var move_ids: Array[String] = [first.actor_id, child.actor_id]
	model.move_to_section(move_ids, second_section.id)
	check(model.visible_clips().size() == 3 and model.actor_for_id(child.actor_id).parent_id == first.actor_id,
		"Moving a branch preserves nested parenting")
	check(model.can_place_group({}), "Moving into occupied section preserves non-overlap")
	model.undo()
	check(model.actor_for_id(first.actor_id).section_id == "default" and model.actor_for_id(child.actor_id).section_id == "default",
		"Undo restores section membership")
	model.redo()
	check(model.actor_for_id(child.actor_id).section_id == second_section.id, "Redo restores section move")
	model.select_section("default")
	check(model.visible_clips().is_empty(), "Old section is empty after moving branch")
	model.select_section(second_section.id)
	var grandchild := model.create_actor(definition, 12)
	model.set_parent(grandchild.actor_id, child.actor_id)
	model.set_timeline_children_visible(first.actor_id, false)
	check(model.clip_is_visible(model._index_of(first.id)) and not model.clip_is_visible(model._index_of(child.id))
		and not model.clip_is_visible(model._index_of(grandchild.id)), "Hiding children hides all descendants, not the actor itself")
	check(not model.can_place(first.id, child.start_time, first.duration, child.layer), "Parents cannot overlap hidden children")
	model.select_all()
	check(not model.is_selected(child.id) and not model.is_selected(grandchild.id), "Timeline select-all excludes hidden descendants")
	model.undo()
	check(model.clip_is_visible(model._index_of(grandchild.id)), "Undo restores descendants in timeline")
	model.set_timeline_children_visible(child.actor_id, false)
	model.set_timeline_children_visible(first.actor_id, false)
	model.set_timeline_children_visible(first.actor_id, true)
	check(model.clip_is_visible(model._index_of(child.id)) and not model.clip_is_visible(model._index_of(grandchild.id)),
		"Showing ancestor respects a child's own visibility toggle")
	check(not model.actor_for_id(child.actor_id).copy_actor().show_timeline_children, "Actor copies retain children visibility")
	var scene_tree := ActorSceneTree.new()
	root.add_child(scene_tree)
	scene_tree.setup(model, registry)
	await process_frame
	await process_frame
	var section_count := model.sections.size()
	scene_tree._section_button_clicked(scene_tree._items[child.actor_id], 0, 1, MOUSE_BUTTON_LEFT)
	check(model.actor_for_id(child.actor_id).show_timeline_children and model.sections.size() == section_count,
		"Actor eye button toggles descendants without creating a section")
	await process_frame
	check(model.clip_is_visible(model._index_of(grandchild.id)), "Eye button updates timeline visibility immediately")
	var previous_selection := model.selected_ids.duplicate()
	model.delete_section(second_section.id)
	check(model.actors.is_empty() and model.sections.size() == 1 and model.selected_section_id == "default",
		"Deleting section removes its contents and selects another section")
	model.undo()
	check(model.actors.size() == 4 and model.selected_ids == previous_selection
		and model.actor_for_id(grandchild.actor_id).parent_id == child.actor_id, "Undo section deletion restores actors, hierarchy and selection")
	model.redo()
	check(model.actors.is_empty() and model.section_for_id(second_section.id) == null, "Redo removes section and its actors")
	model.delete_section("default")
	check(model.sections.size() == 1 and model.sections[0].id != "default", "Deleting last section creates an empty replacement")
	model.undo()
	check(model.sections.size() == 1 and model.selected_section_id == "default", "Undo restores last section without keeping replacement")
	scene_tree.queue_free()
	await process_frame
	print("Timeline sections: %d failures" % failures)
	quit(failures)
