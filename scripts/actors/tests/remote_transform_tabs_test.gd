extends SceneTree
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var layout := VBoxContainer.new()
	root.add_child(layout)
	var tabs := ActorSceneTabs.new()
	tabs.name = "Tabs"
	layout.add_child(tabs)
	var split := HSplitContainer.new()
	split.name = "HSplitContainer"
	layout.add_child(split)
	var placeholder := Control.new()
	placeholder.name = "VSplitContainer"
	split.add_child(placeholder)
	var editor_column := VSplitContainer.new()
	editor_column.name = "VSplitContainer2"
	split.add_child(editor_column)
	var editor := load("res://Workspaces/SceneWorkspace/Timeline.tscn").instantiate() as ActorTimelineEditor
	editor.name = "ActorTimeline"
	editor_column.add_child(editor)
	await process_frame
	await process_frame
	check(tabs.documents.size() == 1 and tabs.tab_count == 2,
		"Top tab bar has one scene tab and a new-scene tab")

	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 360)
	root.add_child(viewport)
	editor.runtime_holder = Node3D.new()
	viewport.add_child(editor.runtime_holder)
	var target_clip := editor.model.create_actor(editor.registry.get_definition(&"point_3d"), 0.0)
	var target := editor.model.selected_actor()
	target.set_value(&"position", Vector3(1, 2, 3))
	target.set_value(&"rotation", Vector3(5, 10, 15))
	target.set_value(&"scale", Vector3(2, 2, 2))
	editor.model.selected_layer = 1
	var remote_clip := editor.model.create_actor(editor.registry.get_definition(&"remote_transform"), 0.0)
	var remote := editor.model.selected_actor()
	remote.set_value(&"position", Vector3(8, 9, 10))
	remote.set_value(&"rotation", Vector3(20, 30, 40))
	remote.set_value(&"scale", Vector3(3, 4, 5))
	remote.set_value(&"remote_actor", target.id)
	editor.model.changed.emit()
	editor._evaluate_runtimes()
	var target_runtime := editor._runtime_for_clip(target_clip.id)
	var remote_runtime := editor._runtime_for_clip(remote_clip.id)
	check(target_runtime.remote_transform().origin.is_equal_approx(remote_runtime.remote_transform().origin),
		"Remote Transform applies the source global position")
	check(target.get_value(&"position") == Vector3(1, 2, 3),
		"Remote Transform does not overwrite the target's saved properties")
	remote.set_value(&"set_position", false)
	remote.set_value(&"set_rotation", false)
	remote.set_value(&"set_scale", true)
	editor._evaluate_runtimes()
	check(target_runtime.remote_transform().origin.is_equal_approx(Vector3(1, 2, 3)),
		"Remote Transform channels can be disabled independently")
	check(target_runtime.remote_transform().basis.get_scale().is_equal_approx(Vector3(3, 4, 5)),
		"Remote Transform selectively applies scale")

	editor.canvas.scroll_time = 12.5
	var first_actor_id := target.id
	tabs.current_tab = tabs.documents.size()
	await process_frame
	var new_tab_menu: PopupPanel
	for child in tabs.get_children():
		if child is PopupPanel and child.visible: new_tab_menu = child
	check(new_tab_menu != null, "Plus tab opens the scene-or-shader chooser")
	if new_tab_menu != null: new_tab_menu.queue_free()
	tabs.new_scene()
	check(tabs.documents.size() == 2 and editor.model.actors.is_empty(), "New tab creates a fresh scene")
	check(tabs.tab_count == 3, "The plus tab remains at the end after creating a scene")
	editor.model.create_actor(editor.registry.get_definition(&"basic_shape"), 1.0)
	var second_actor_id := editor.model.selected_actor().id
	tabs.current_tab = 0
	check(editor.model.actor_for_id(first_actor_id) != null and is_equal_approx(editor.canvas.scroll_time, 12.5),
		"Switching tabs restores actors and timeline state")
	tabs.current_tab = 1
	check(editor.model.actor_for_id(second_actor_id) != null, "A tab keeps edits made before switching away")
	tabs.current_tab = 0
	editor.model.undo()
	check(editor.model.actor_for_id(remote.id) == null, "Each tab preserves its own undo history")
	editor.model.redo()
	check(editor.model.actor_for_id(remote.id) != null, "Tab-local redo history remains usable after switching")
	var scene_path := "user://tab_scene_" + ActorData.new_id() + ".tres"
	check(tabs.save_current(scene_path) == OK, "Current tab saves to a scene file")
	var count_before := tabs.documents.size()
	tabs.open_scene(scene_path)
	check(tabs.documents.size() == count_before and tabs.current_scene_path() == scene_path,
		"Opening an already-open scene focuses its existing tab")
	var external_path := "user://external_tab_scene_" + ActorData.new_id() + ".tres"
	var external_scene := ActorSceneData.new()
	external_scene.sections.append(ActorSection.new())
	external_scene.inspector_state = ActorInspectorState.new()
	check(ResourceSaver.save(external_scene, external_path) == OK, "Create external scene for filesystem open")
	count_before = tabs.documents.size()
	tabs._filesystem_resource_opened(external_path)
	check(tabs.documents.size() == count_before + 1 and tabs.current_scene_path() == external_path,
		"Filesystem scene double-click opens a new tab")
	tabs._filesystem_resource_opened(external_path)
	check(tabs.documents.size() == count_before + 1, "Repeated filesystem open focuses the existing scene tab")
	DirAccess.remove_absolute(scene_path)
	DirAccess.remove_absolute(external_path)
	layout.free()
	viewport.free()
	await process_frame
	print("Remote transform / scene tabs checks: %d failures" % failures)
	quit(failures)
