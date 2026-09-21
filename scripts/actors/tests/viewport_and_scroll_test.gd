extends SceneTree
var failures: int = 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func wheel(button: MouseButton, position: Vector2) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = position
	event.factor = 1.0
	return event


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	# Mirror the relevant main-scene hierarchy without starting filesystem services.
	var scene_workspace := Control.new()
	root.add_child(scene_workspace)
	var world := Node3D.new()
	world.name = "World"
	scene_workspace.add_child(world)
	var viewport := SubViewport.new()
	viewport.name = "SubViewport"
	viewport.size = Vector2i(640, 360)
	world.add_child(viewport)
	var camera := Camera3D.new()
	camera.cull_mask = 1
	viewport.add_child(camera)
	var workspace_column := VBoxContainer.new()
	scene_workspace.add_child(workspace_column)
	var shader_editor := ShaderCodeEditor.new()
	scene_workspace.add_child(shader_editor)
	var split := HSplitContainer.new()
	workspace_column.add_child(split)
	var timeline_side := VSplitContainer.new()
	split.add_child(timeline_side)
	var upper_split := HSplitContainer.new()
	upper_split.name = "HSplitContainer"
	timeline_side.add_child(upper_split)
	var spacer := Control.new()
	upper_split.add_child(spacer)
	var properties := Panel.new()
	properties.name = "PropertiesPanel"
	upper_split.add_child(properties)
	var editor := load("res://Workspaces/SceneWorkspace/Timeline.tscn").instantiate() as ActorTimelineEditor
	timeline_side.add_child(editor)
	await process_frame
	await process_frame
	check(editor.runtime_holder != null and editor.runtime_holder.get_parent() == viewport, "Runtime holder belongs to main SubViewport")
	var shape_index := -1
	for index in editor._definitions.size():
		if editor._definitions[index].type_id == &"basic_shape":
			shape_index = index
	editor.create_actor(shape_index)
	var runtime := editor._runtimes[editor.model.clips[0].id] as ActorRuntime
	var mesh := runtime.get_child(0) as MeshInstance3D
	check(mesh != null and mesh.layers == 1, "Basic Shape uses main viewport visibility layer")
	check(mesh.position == Vector3(0, 0, -3) and mesh.visible, "New Basic Shape is in front of camera and active")
	var shape_definition := editor.registry.get_definition(&"basic_shape")
	var material_definition := editor.registry.get_object_definition(&"material")
	editor.model.edit_property(editor.model.selected_actor(), shape_definition, &"material",
		ActorObjectReference.from_object(material_definition.create_object()))
	editor.model.history.clear_history()
	editor.inspector._rebuild_selected()
	var material_slot := editor.inspector.find_child("material_resource", true, false) as ActorResourceSlot
	material_slot.button_pressed = true
	var position_x := editor.inspector.find_child("position_0", true, false) as DragNumber
	var history_name := editor.model.history.get_current_action_name()
	position_x.interaction_started.emit()
	position_x.set_value_no_signal(2.0)
	position_x.preview_changed.emit(2.0)
	check(mesh.position.x == 2.0 and editor.model.selected_actor().get_value(&"position").x == 2.0,
		"Property drag updates actor runtime before release")
	check(editor.model.history.get_current_action_name() == history_name, "Live viewport preview creates no history")
	position_x.drag_committed.emit(2.0)
	position_x.interaction_ended.emit()
	check(editor.model.history.get_current_action_name() == "Change Position", "Release creates property history entry")
	editor.undo()
	check(mesh.position.x == 0.0, "Undo live property drag restores viewport")
	var color_input := editor.inspector.find_child("tint", true, false) as LiveColorPickerButton
	var original_color: Color = (mesh.material_override as StandardMaterial3D).albedo_color
	var color_swatch := color_input.find_child("ColorSwatch", false, false) as ColorRect
	check(color_swatch != null and color_swatch.color == color_input.color, "Color property button displays its current color")
	var color_history := editor.model.history.get_current_action_name()
	color_input.begin_session()
	color_input.get_popup().show()
	color_input.color = Color.RED
	color_input._on_color_changed(Color.RED)
	check(color_swatch.color == Color.RED, "Color property swatch updates live")
	check(color_input.dragging and editor.hint_label.text == "Esc cancels color drag", "First color change starts gesture")
	check(mesh.material_override.albedo_color == Color.RED, "Color updates viewport before release")
	check(editor.model.history.get_current_action_name() == color_history, "Color preview creates no history")
	color_input.finish_drag()
	check(editor.model.history.get_current_action_name() == "Change Tint", "Color release creates history entry")
	check(not editor.hint_label.text.contains("Esc cancels"), "Color release clears interaction hint")
	editor.undo()
	check(mesh.material_override.albedo_color == original_color, "Undo color drag restores viewport")
	color_input.begin_drag()
	color_input.color = Color.BLUE
	color_input.preview_changed.emit(Color.BLUE)
	color_input.cancel_drag()
	check(mesh.material_override.albedo_color == original_color, "Cancel color drag restores live preview")
	color_input.get_popup().hide()
	check(not editor.hint_label.text.contains("Esc cancels"), "Closing color popup cannot leave stale hint")
	# Selection and resource-panel rebuilds must retain the actual scroll offset,
	# not overwrite it with the temporary zero produced while controls relayout.
	var first_actor := editor.model.selected_actor()
	editor.inspector.size = Vector2(260, 170)
	await process_frame
	await process_frame
	editor.inspector.scroll_vertical = 70
	await process_frame
	var stored_inspector_scroll := editor.inspector.scroll_vertical
	check(stored_inspector_scroll > 0 and editor.inspector_ui_state.scroll_for(first_actor.id) > 0,
		"Scrolling actor properties records the actor's inspector position")
	editor.model.create_actor(shape_definition, 6.0)
	await process_frame
	editor.model.select(editor.model.clip_for_actor_id(first_actor.id).id)
	await process_frame
	await process_frame
	check(editor.inspector.scroll_vertical == stored_inspector_scroll,
		"Reselecting an actor restores its previous inspector scroll position")
	editor.inspector._rebuild_selected()
	await process_frame
	await process_frame
	check(editor.inspector.scroll_vertical == stored_inspector_scroll,
		"Rebuilding selected actor properties preserves inspector scroll")
	editor.canvas.size = Vector2(500, 180)
	editor._refresh()
	var original_h := editor.h_scroll.value
	editor.canvas._gui_input(wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(250, 10)))
	check(editor.h_scroll.value > original_h and editor.canvas.scroll_time == editor.h_scroll.value, "Wheel over seconds ruler scrolls horizontally")
	# Make enough shared layers to exercise vertical scrolling.
	for layer in 8:
		editor.model.selected_layer = layer + 1
		editor.create_actor(shape_index)
	editor._refresh()
	var original_v := editor.v_scroll.value
	editor.canvas._gui_input(wheel(MOUSE_BUTTON_WHEEL_DOWN, Vector2(250, ActorTimelineCanvas.HEADER + 20)))
	check(editor.v_scroll.value > original_v and editor.canvas.scroll_rows == editor.v_scroll.value, "Wheel over layers scrolls vertically")
	var horizontal_after := editor.h_scroll.value
	editor.canvas._gui_input(wheel(MOUSE_BUTTON_WHEEL_UP, Vector2(250, ActorTimelineCanvas.HEADER + 20)))
	check(editor.h_scroll.value == horizontal_after, "Layer wheel does not change horizontal scroll")
	var runtime_before_shader_revision := (editor._runtimes[editor.model.clips[0].id] as ActorRuntime).get_instance_id()
	shader_editor.shader_changed.emit(null)
	var rebuilt_runtime := editor._runtimes[editor.model.clips[0].id] as ActorRuntime
	check(rebuilt_runtime != null and rebuilt_runtime.get_instance_id() != runtime_before_shader_revision,
		"Shader source revisions recreate viewport actor runtimes after compiler failures")
	scene_workspace.free()
	await process_frame
	print("Viewport and scroll checks: ", failures, " failures")
	quit(1 if failures else 0)
