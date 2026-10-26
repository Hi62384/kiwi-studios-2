extends SceneTree
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(title)
	print("PASS " if ok else "FAIL ", title)
func settle(count: int = 5) -> void:
	for i in count: await process_frame
func click(button: Button) -> void:
	var point := button.get_global_transform_with_canvas() * (button.size / 2)
	var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point; root.push_input(motion, true)
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.position = point; event.global_position = point; event.pressed = true; root.push_input(event, true)
	await process_frame
	event = event.duplicate(); event.pressed = false; root.push_input(event, true)
	await settle()
func run() -> void:
	root.size = Vector2i(1440, 1000); root.gui_embed_subwindows = true
	var folder := ProjectSettings.globalize_path("user://inspector_tabs_" + ActorData.new_id())
	DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash"))
	var project := Project.new("Inspector tab verification")
	ResourceSaver.save(project, folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project = project
	var main: Node = load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(10)
	var tabs := get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs
	var editor := tabs.timeline; var model := editor.model; var inspector := editor.inspector
	var shape := editor.registry.get_definition(&"basic_shape_2d")
	var clip := model.create_actor(shape, 0); var actor := model.selected_actor(); await settle()
	var natural_size := inspector.size
	check(inspector.main_tabs.visible and inspector._main_buttons.size() == 2, "Actor inspector has two fixed main tabs")
	check(inspector._main_buttons.Actor.text == "Actor" and inspector._main_buttons.Properties.text == "Properties", "Main tab labels match Actor and Properties")
	check(inspector._sections.has("Actor/General") and inspector._sections.has("Actor/Transform") and inspector._sections.has("Actor/Layout"), "Name, transforms and 2D layout are shared Actor sections")
	check(inspector._sections.has("Properties/Shape") and inspector._sections.has("Properties/Appearance"), "Type-specific properties have their own section tabs")
	check(inspector._main_tab == "Properties" and inspector._section == "Shape", "New actors open their type-specific settings")
	await click(inspector._main_buttons.Actor)
	check(inspector._main_tab == "Actor" and inspector._section == "Transform", "Clicking Actor opens shared transform controls")
	var position := inspector.find_child("position_0", true, false) as DragNumber
	var shape_choice := inspector.find_child("shape_choice", true, false) as OptionButton
	check(position.is_visible_in_tree() and not shape_choice.is_visible_in_tree(), "Only the selected section's properties are shown")
	var transform_button: Button = inspector._sections["Actor/Transform"].button
	check(transform_button.get_global_rect().end.x <= inspector.content_scroll.get_global_rect().position.x, "Section tabs sit to the left of the property content")
	await click(inspector._sections["Actor/General"].button)
	check(inspector._section == "General" and inspector.find_child("ActorName", true, false).is_visible_in_tree() and not position.is_visible_in_tree(), "Left-side section tabs switch to the name editor")
	await click(transform_button)
	position.value = 24.0
	check(actor.get_value(&"position").x == 24.0, "Transform fields remain editable in the Actor tab")
	model.undo(); check(actor.get_value(&"position").x == 0.0, "Tabbed inspector edits still undo")
	model.redo(); check(position.value == 24.0 and inspector._section == "Transform", "Redo refreshes fields without changing the selected section")
	var diamond := inspector.find_child("position_keyframe", true, false) as Button
	diamond.button_pressed = true; diamond.pressed.emit()
	check(actor.animation_track(PackedStringArray(["position"])) != null, "Shared actor transforms remain keyframeable")
	inspector.size = Vector2(natural_size.x, 250); await settle()
	inspector.scroll_vertical = 75; await settle()
	var saved_scroll := inspector.scroll_vertical
	check(saved_scroll > 0, "Long property sections scroll independently")
	var main_position := inspector.main_tabs.global_position; var rail_position := inspector.section_scroll.global_position
	inspector.scroll_vertical = 95; await settle()
	check(inspector.main_tabs.global_position == main_position and inspector.section_scroll.global_position == rail_position, "Scrolling fields never moves either tab bar")
	saved_scroll = inspector.scroll_vertical
	inspector.select_section("Layout"); await settle()
	check(inspector.scroll_vertical == 0 and inspector.find_child("size_0", true, false).is_visible_in_tree(), "A new section starts at its own scroll position")
	inspector.select_section("Transform"); await settle()
	check(abs(inspector.scroll_vertical - saved_scroll) <= 1, "Returning to a section restores its scroll position")
	inspector.select_main_tab("Properties"); inspector.select_section("Appearance"); await settle()
	check(not position.is_visible_in_tree() and inspector.find_child("material_resource", true, false).is_visible_in_tree(), "Properties shows appearance and resource editors, not inherited transforms")
	var material_slot := inspector.find_child("material_resource", true, false) as ActorResourceSlot
	check(material_slot.size.x > inspector.content_scroll.size.x * .8, "Resource slots use the section width instead of a cramped label column")
	inspector.select_main_tab("Actor"); await settle()
	check(inspector._section == "Transform" and abs(inspector.scroll_vertical - saved_scroll) <= 1, "Each main tab remembers its previous section and scroll")
	inspector.select_main_tab("Properties"); await settle()
	check(inspector._section == "Appearance", "Properties remembers its selected left-side section")
	var other_clip := model.create_actor(editor.registry.get_definition(&"point_3d"), 6); await settle()
	check(inspector._main_tab == "Actor" and inspector._section == "Transform", "Actors with no type-specific settings start in Actor")
	inspector.select_main_tab("Properties"); await settle()
	check(inspector._empty_section.visible and not inspector.section_scroll.visible, "Empty Properties tab is explained without irrelevant section tabs")
	model.select(clip.id); await settle()
	check(inspector._main_tab == "Properties" and inspector._section == "Appearance", "Reselecting an actor restores its inspector navigation")
	inspector._rebuild_selected(); await settle()
	check(inspector._main_tab == "Properties" and inspector._section == "Appearance", "Inspector rebuilds retain the chosen main tab and section")
	model.select(other_clip.id); await settle()
	check(inspector._main_tab == "Properties" and inspector._empty_section.visible, "Explicit empty-tab choice is also preserved per actor")
	model.select(clip.id); await settle()
	var captured := editor.capture_scene_data()
	var state_path := folder.path_join("InspectorState.tres")
	check(ResourceSaver.save(captured.inspector_state, state_path) == OK, "Inspector navigation is saved with scene UI state")
	var loaded := ResourceLoader.load(state_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorInspectorState
	check(loaded.main_tab_for(actor.id) == "Properties" and loaded.section_for(actor.id, "Properties") == "Appearance", "Native resource reload preserves inspector main and section tabs")
	check(abs(loaded.page_scroll_for(actor.id, "Actor", "Transform") - saved_scroll) <= 1, "Native resource reload preserves per-section scroll")
	# Nonconsecutive groups share a page; many sections must not crush the content.
	var custom := ActorDefinition.new(); custom.type_id = &"inspector_fixture_2d"; custom.display_name = "Inspector fixture"; custom.runtime_scene = shape.runtime_scene; custom.icon = shape.icon
	custom.properties.assign(shape.properties)
	for index in 28:
		var property := ActorProperty.create(StringName("extra_" + str(index)), "Extra value", 1.0, true)
		property.options.group = "Extra " + str(index); custom.properties.append(property)
	var repeated := ActorProperty.create(&"repeated_appearance", "Repeated group", 2.0, true); repeated.options.group = "Appearance"; custom.properties.append(repeated)
	check(editor.registry.register(custom), "Register a many-section inspector fixture")
	var custom_clip := model.create_actor(custom, 12); await settle()
	check(inspector._sections.size() == 33 and inspector._sections["Properties/Appearance"].content.find_child("repeated_appearance", true, false) != null, "Repeated groups merge into one section without losing any fields")
	check(inspector.section_scroll.get_v_scroll_bar().max_value > inspector.section_scroll.get_v_scroll_bar().page, "Many section tabs have their own scrollbar")
	inspector.select_section("Extra 27"); await settle()
	check(inspector.find_child("extra_27", true, false).is_visible_in_tree(), "Sections remain reachable beyond the visible left rail")
	var last_tab: Button = inspector._sections["Properties/Extra 27"].button
	check(last_tab.get_global_rect().position.y >= inspector.section_scroll.get_global_rect().position.y - 1 and last_tab.get_global_rect().end.y <= inspector.section_scroll.get_global_rect().end.y + 1, "Restoring a deep section scrolls its selected tab into view")
	inspector.section_scroll.scroll_vertical = 1000; await settle()
	check(inspector.content_scroll.get_global_rect().size.x > 150, "A long section list preserves usable property width")
	model.select(clip.id); await settle(); inspector.size = natural_size
	inspector.select_main_tab("Actor"); inspector.select_section("Transform"); await settle()
	check(inspector.find_child("position_0", true, false).get_global_rect().end.x <= inspector.get_global_rect().end.x + 1, "Transform controls fit a narrow inspector")
	check((inspector.get_global_transform_with_canvas() * inspector.size).x <= root.size.x + 1, "Inspector tabs and controls fit inside the actual application window")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/verification/actor_inspector_tabs_actor.png")
	inspector.select_main_tab("Properties"); inspector.select_section("Appearance"); await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/verification/actor_inspector_tabs_properties.png")
	# File previews should not leave actor tabs over a resource preview.
	var image_path := folder.path_join("Preview.png"); var image := Image.create(8, 8, false, Image.FORMAT_RGBA8); image.fill(Color.CORAL); image.save_png(image_path)
	inspector.inspect_file_resource(image_path); await settle()
	check(inspector._inspecting_file and not inspector.main_tabs.visible and not inspector.section_scroll.visible, "File previews use the content area without stale actor navigation")
	model.select(custom_clip.id); await settle()
	check(inspector.main_tabs.visible and not inspector._inspecting_file and inspector._actor.id == custom_clip.actor_id, "Selecting an actor restores the tabbed inspector after a file preview")
	model.select(""); await settle()
	check(not inspector.main_tabs.visible and not inspector.section_scroll.visible, "Clearing the actor selection clears its navigation")
	main.queue_free(); await settle(); StaticData.loaded_project = null
	print("ACTOR_INSPECTOR_TABS checks=%d failures=%d" % [checks, failures]); quit(failures)
