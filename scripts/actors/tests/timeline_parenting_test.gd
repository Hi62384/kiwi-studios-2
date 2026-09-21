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
	var timeline := ActorTimeline.new()
	var parent_clip := timeline.create_actor(definition, 0.0)
	var child_clip := timeline.create_actor(definition, 6.0)
	var grandchild_clip := timeline.create_actor(definition, 12.0)
	var parent := timeline.actor_for_id(parent_clip.actor_id)
	var child := timeline.actor_for_id(child_clip.actor_id)
	var grandchild := timeline.actor_for_id(grandchild_clip.actor_id)
	parent.set_value(&"position", Vector3(10, 0, 0))
	child.set_value(&"position", Vector3(12, 0, 0))
	grandchild.set_value(&"position", Vector3(13, 0, 0))
	timeline.set_parent(child.id, parent.id)
	check(child.parent_id == parent.id and child.get_value(&"position").is_equal_approx(Vector3(2, 0, 0))
		and timeline.world_transform_for(child.id).origin.is_equal_approx(Vector3(12, 0, 0)),
		"Assign actor parent while preserving world transform")
	timeline.set_parent(grandchild.id, child.id)
	check(grandchild.parent_id == child.id and grandchild.get_value(&"position").is_equal_approx(Vector3(1, 0, 0))
		and timeline.world_transform_for(grandchild.id).origin.is_equal_approx(Vector3(13, 0, 0)),
		"Assign nested parent while preserving world transform")
	check(not timeline.can_set_parent(parent.id, grandchild.id), "Reject parent cycle")
	timeline.set_parent(parent.id, grandchild.id)
	check(parent.parent_id.is_empty(), "Cycle attempt leaves hierarchy unchanged")
	timeline.unparent(child.id)
	check(child.parent_id.is_empty() and child.get_value(&"position").is_equal_approx(Vector3(12, 0, 0)),
		"Unparent actor while preserving world transform")
	timeline.undo()
	check(child.parent_id == parent.id and child.get_value(&"position").is_equal_approx(Vector3(2, 0, 0)),
		"Undo unparent restores parent and local transform")
	timeline.redo()
	check(child.parent_id.is_empty() and child.get_value(&"position").is_equal_approx(Vector3(12, 0, 0)),
		"Redo unparent restores root transform")
	timeline.set_parent(child.id, parent.id)
	var scene_tree := ActorSceneTree.new()
	root.add_child(scene_tree)
	scene_tree.setup(timeline, registry)
	await process_frame
	check((scene_tree._items[child.id] as TreeItem).get_parent() == scene_tree._items[parent.id]
		and (scene_tree._items[grandchild.id] as TreeItem).get_parent() == scene_tree._items[child.id],
		"Scene Tree displays nested actor parenting")
	scene_tree.custom_minimum_size = Vector2(300, 240)
	var tree_press := InputEventMouseButton.new()
	tree_press.button_index = MOUSE_BUTTON_LEFT
	tree_press.pressed = true
	tree_press.position = scene_tree.get_item_area_rect(scene_tree._items[parent.id]).get_center()
	scene_tree._gui_input(tree_press)
	tree_press.ctrl_pressed = true
	tree_press.position = scene_tree.get_item_area_rect(scene_tree._items[grandchild.id]).get_center()
	scene_tree._gui_input(tree_press)
	check(timeline.selected_ids.size() == 2 and timeline.selected_id == grandchild_clip.id,
		"Scene Tree Ctrl-click adds an actor and makes it primary")
	tree_press.ctrl_pressed = false
	tree_press.shift_pressed = true
	scene_tree._selection_anchor = parent.id
	scene_tree._gui_input(tree_press)
	check(timeline.selected_ids.size() == 3 and timeline.selected_id == grandchild_clip.id,
		"Scene Tree Shift-click selects every visible actor between anchor and click")
	var scene_root := scene_tree.get_root()
	scene_tree.scroll_to_item(scene_root)
	await process_frame
	var root_position := scene_tree.get_item_area_rect(scene_root).get_center()
	var tree_drag := {"type": "actor_scene_tree", "actor_id": grandchild.id}
	check(scene_tree._can_drop_data(root_position, tree_drag), "Scene Tree accepts reparenting to Scene root")
	scene_tree._drop_data(root_position, tree_drag)
	check(grandchild.parent_id.is_empty(), "Dropping on Scene root unparents the actor")
	timeline.undo()
	check(grandchild.parent_id == child.id, "Scene Tree reparenting participates in undo")
	var parent_runtime := definition.create_runtime(parent)
	var child_runtime := definition.create_runtime(child)
	var grandchild_runtime := definition.create_runtime(grandchild)
	root.add_child(parent_runtime)
	root.add_child(child_runtime)
	root.add_child(grandchild_runtime)
	child_runtime.reparent(parent_runtime.parenting_node())
	grandchild_runtime.reparent(child_runtime.parenting_node())
	parent_runtime.evaluate_clip(parent_clip, 12.0)
	child_runtime.evaluate_clip(child_clip, 12.0)
	grandchild_runtime.evaluate_clip(grandchild_clip, 12.0)
	check((grandchild_runtime.get_node("Transform") as Node3D).global_position.is_equal_approx(Vector3(13, 0, 0)),
		"Nested runtime transforms evaluate through inactive parent clips")
	parent_runtime.free()
	scene_tree.free()
	timeline.select(parent_clip.id)
	timeline.delete_selected()
	check(timeline.actor_for_id(parent.id) == null and child.parent_id.is_empty()
		and timeline.world_transform_for(child.id).origin.is_equal_approx(Vector3(12, 0, 0)),
		"Deleting a root parent promotes children and preserves world transforms")
	timeline.undo()
	check(timeline.actor_for_id(parent.id) == parent and child.parent_id == parent.id
		and child.get_value(&"position").is_equal_approx(Vector3(2, 0, 0)),
		"Undo delete restores hierarchy and local transforms")
	timeline.select(child_clip.id)
	timeline.delete_selected()
	check(grandchild.parent_id == parent.id
		and timeline.world_transform_for(grandchild.id).origin.is_equal_approx(Vector3(13, 0, 0)),
		"Deleting a middle parent promotes descendants to the grandparent")
	timeline.undo()
	check(grandchild.parent_id == child.id and grandchild.get_value(&"position").is_equal_approx(Vector3(1, 0, 0)),
		"Undo middle-parent deletion restores the nested branch")
	print("Timeline parenting checks: ", failures, " failures")
	quit(1 if failures else 0)
