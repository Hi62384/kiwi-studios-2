extends SceneTree
var checks := 0
var failures := 0
var editor: ActorTimelineEditor
func _initialize() -> void: run.call_deferred()
func check(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(title)
	print("PASS " if ok else "FAIL ", title)
func settle(count: int = 6) -> void:
	for i in count: await process_frame
func seek(time: float) -> void:
	editor.canvas.playhead = time
	editor._evaluate_runtimes()
	editor.model.changed.emit()
func fixture() -> KiwiTransformationImage2D:
	var document := KiwiTransformationImage2D.blank(Vector2i(160, 120))
	var item := document.components[0]; item.title = "Face"
	var first := item.states[0]; first.title = "Rest"
	var image := Image.create(48, 48, false, Image.FORMAT_RGBA8); image.fill(Color(0, 0, 0, 0))
	for y in range(8, 40):
		for x in range(8, 40): image.set_pixel(x, y, Color("ed624e"))
	first.artwork.texture = ImageTexture.create_from_image(image)
	first.artwork.position = Vector2(8, 16); first.artwork.dimensions = Vector2(48, 48)
	var second := first.copy_state(true); second.title = "Smile"; second.artwork.position = Vector2(96, 24)
	image = image.duplicate(); image.fill(Color(0, 0, 0, 0))
	for y in 48:
		for x in 48:
			if Vector2(x - 24, y - 24).length() < 20: image.set_pixel(x, y, Color("399ce9"))
	second.artwork.texture = ImageTexture.create_from_image(image); item.states.append(second)
	KiwiTransformationExamples.key(item, 0, first, "Auto Morph")
	KiwiTransformationExamples.key(item, 2, second, "Auto Morph")
	var detail := KiwiTransformationImage2D.make_component(document.canvas_size, "Detail")
	var dot := Image.create(8, 8, false, Image.FORMAT_RGBA8); dot.fill(Color("5ce19b"))
	detail.states[0].artwork.texture = ImageTexture.create_from_image(dot)
	detail.states[0].artwork.position = Vector2(12, 96); detail.states[0].artwork.dimensions = Vector2(8, 8)
	var other := detail.states[0].copy_state(true); other.title = "Raised"; other.artwork.position.y = 76; detail.states.append(other)
	document.components.append(detail)
	return document
func centroid(image: Image) -> Vector2:
	var sum := Vector2.ZERO; var weight := 0.0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > .1 and pixel.g < .7: sum += Vector2(x, y) * pixel.a; weight += pixel.a
	return sum / maxf(.001, weight)
func run() -> void:
	root.size = Vector2i(1440, 1000); root.gui_embed_subwindows = true
	var folder := ProjectSettings.globalize_path("user://transform_actor_" + ActorData.new_id())
	DirAccess.make_dir_recursive_absolute(folder.path_join(".proj/.trash"))
	var project := Project.new("Transformation actor verification")
	ResourceSaver.save(project, folder.path_join(".proj/Project.tres")); project.take_over_path(folder.path_join(".proj/Project.tres")); StaticData.loaded_project = project
	var document := fixture(); var item := document.components[0]; var detail := document.components[1]
	check(document.validate().is_empty(), "Actor fixture is a valid multi-component transformation")
	var source := folder.path_join("Face.tres")
	check(ResourceSaver.save(document, source) == OK, "Save native transformation fixture")
	var main: Node = load("res://scenes/Main.tscn").instantiate(); root.add_child(main); await settle(10)
	var tabs := get_first_node_in_group("actor_scene_tabs") as ActorSceneTabs; editor = tabs.timeline
	var definition := editor.registry.get_definition(&"transform_image_2d")
	check(definition != null and definition.category == "Media", "Transform Image 2D is creatable in the real actor catalog")
	check(ActorFileImport.type_for_path(source) == &"transform_image_2d", "Project transformation files can be dragged into the timeline")
	var clip := editor.model.create_actor(definition, 0, ActorFileImport.values_for_path(source, editor.registry))
	var actor := editor.model.selected_actor(); await settle()
	var runtime := editor._runtime_for_clip(clip.id) as ActorTransformImage2DRuntime
	check(runtime != null and runtime.active and runtime is ActorUIRuntime, "New actor renders in the scene with normal 2D viewport handles")
	check(is_equal_approx(clip.duration, document.duration), "Actor initially matches its transformation asset duration")
	check(runtime.bounds().size == Vector2(640, 360), "Actor has editable viewport size bounds")
	check(runtime.renderer.viewport.world_2d != runtime.get_viewport().world_2d, "Morph contents have an isolated 2D world")
	check(runtime.renderer.views.size() == 2 and runtime.renderer.viewport.size == Vector2i(160, 120), "All transformation components render at native canvas resolution")
	var inspector := editor.inspector
	var prop := definition.find_property(&"transformation")
	check(inspector._file_path_allowed(source, prop), "Inspector accepts native transformation assets")
	check(not inspector._file_path_allowed(folder.path_join(".proj/Project.tres"), prop), "Inspector rejects unrelated native resource types")
	var selector := inspector.fields.find_child("TransformationState_" + item.id, true, false) as OptionButton
	check(selector != null and selector.item_count == 2 and selector.get_item_text(1) == "Smile", "Inspector exposes named current states per component")
	check(inspector.fields.find_child("TransformationState_" + detail.id, true, false) != null, "Each component has an independent state selector")
	check(selector.get_global_rect().end.x <= inspector.get_global_rect().end.x + 1, "State controls fit within the inspector without horizontal clipping")
	selector.item_selected.emit(1); await settle()
	check(actor.values[&"component_states"].get(item.id) == item.states[1].id, "Choosing an inspector state changes the scene actor")
	check(document.components[0].default_state_id == item.states[0].id, "Actor state changes never mutate the source asset")
	editor.model.undo(); await settle()
	check(ActorTransformationStates.current(actor, item, 0) == item.states[0].id, "State changes undo")
	editor.model.redo(); await settle()
	check(ActorTransformationStates.current(actor, item, 0) == item.states[1].id, "State changes redo")
	editor.model.undo(); await settle()
	var path := ActorTransformationStates.path_for(item.id)
	var diamond := inspector.fields.find_child("state_" + item.id + "_keyframe", true, false) as Button
	diamond.button_pressed = true; diamond.pressed.emit(); await settle()
	var track := actor.animation_track(path)
	check(track != null and track.keys.size() == 1 and track.keys[0].value == item.states[0].id, "Inspector diamond inserts a state keyframe")
	check(track.label == "States / Face" and editor.model.overlay_path == path, "State keys appear on the actor with readable track names")
	seek(2); selector.item_selected.emit(1); await settle()
	track = actor.animation_track(path)
	check(track.keys.size() == 2 and is_equal_approx(track.keys[1].time, 2), "Changing a keyed state inserts a key at the playhead")
	check(track.keys[0].interpolation == ActorKeyframe.Interpolation.LINEAR, "State keyframes morph rather than defaulting to discrete enum steps")
	seek(1); await settle()
	var sample := ActorTransformationStates.samples(actor, runtime.session.document, 1, ActorAnimation.sampled_values(actor, 1))[item.id] as Dictionary
	check(sample.a.id == item.states[0].id and sample.b.id == item.states[1].id and is_equal_approx(sample.t, .5), "Keyframes preserve both state endpoints and morph progress")
	check(track.sample(1) == item.states[0].id, "State reference sampling never creates invalid partial text IDs")
	var deadline := Time.get_ticks_msec() + 15000
	while (runtime.renderer.cache.worker != null or not runtime.renderer.cache.requests.is_empty()) and Time.get_ticks_msec() < deadline: await process_frame
	await settle(); await RenderingServer.frame_post_draw
	check(runtime.renderer.views[item.id].get("prepared", {}).get("valid", false), "Background geometry morph preparation reaches the paused scene actor")
	var midpoint := runtime.renderer.texture().get_image()
	check(centroid(midpoint).x > 55 and centroid(midpoint).x < 97, "Rendered morph actually appears between the source and target states")
	seek(0); await settle(); await RenderingServer.frame_post_draw
	check(centroid(runtime.renderer.texture().get_image()).x < 45, "Seeking backward restores the exact initial state")
	seek(2); await settle(); await RenderingServer.frame_post_draw
	check(centroid(runtime.renderer.texture().get_image()).x > 105, "Seeking forward restores the exact target state")
	var panel := editor.keyframe_editor; panel._actor = actor; panel.lanes.selected_keys.assign([track.keys[0].id]); panel._build_details()
	var state_value := panel.details.find_child("KeyframeTransformationState", true, false) as OptionButton
	check(state_value != null and state_value.get_item_text(0) == "Rest", "Keyframe details edit named states rather than opaque IDs")
	var curve := Curve.new(); curve.add_point(Vector2.ZERO); curve.add_point(Vector2(.5, .1)); curve.add_point(Vector2.ONE)
	panel._change_keys(track.keys[0].id, {"value_curve": curve})
	seek(1); track = actor.animation_track(path)
	check(is_equal_approx(track.transition_at(1).weight, .1), "Value curves control the outgoing state morph timing")
	editor.model.undo(); track = actor.animation_track(path)
	check(is_equal_approx(track.transition_at(1).weight, .5), "Morph curve edits undo")
	editor.model.redo(); track = actor.animation_track(path)
	check(is_equal_approx(track.transition_at(1).weight, .1), "Morph curve edits redo")
	var stepped := track.copy_track(); stepped.keys[0].interpolation = ActorKeyframe.Interpolation.STEP
	check(is_zero_approx(stepped.transition_at(1).weight) and stepped.sample(2) == item.states[1].id, "Step keys hold until the exact target key")
	check(track.transition_at(-1).from == item.states[0].id and track.transition_at(20).from == item.states[1].id, "State sampling clamps safely outside its keyed interval")
	ActorTransformationStates.choose(editor.model, actor, detail, detail.states[1].id)
	check(actor.values[&"component_states"].get(detail.id) == detail.states[1].id and actor.animation_track(path).keys.size() == 2, "Editing a second component does not change the first component's keys")
	var copied := actor.copy_actor()
	check(copied.animation_track(path).keys.size() == 2 and copied.values[&"component_states"].get(detail.id) == detail.states[1].id, "Actor duplication preserves independent state choices and morph tracks")
	var scene_path := folder.path_join("Morph Scene.tres")
	check(ResourceSaver.save(editor.capture_scene_data(), scene_path) == OK, "Scene saves the transformation actor and keyframes")
	var loaded := ResourceLoader.load(scene_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorSceneData
	var loaded_actor := loaded.actors.filter(func(candidate: ActorData): return candidate.id == actor.id)[0] as ActorData
	check(loaded_actor.animation_track(path).keys.size() == 2 and loaded_actor.values[&"component_states"].get(detail.id) == detail.states[1].id, "Native scene reload preserves component state IDs and tracks")
	check(is_equal_approx(loaded_actor.animation_track(path).transition_at(1).weight, .1), "Scene reload preserves custom morph easing")
	var previous := tabs._active_index; tabs.new_scene(); await settle(); tabs._capture_current(); tabs._open_index(previous); await settle()
	actor = editor.model.actor_for_id(actor.id); runtime = editor._runtime_for_clip(clip.id) as ActorTransformImage2DRuntime
	check(actor != null and runtime != null and actor.animation_track(path).keys.size() == 2, "Scene tab round trips restore the actor and its morph keys")
	var before := runtime.session.document
	document.components[0].states[1].title = "Changed externally"; ResourceSaver.save(document, source)
	ActorTransformationStates.invalidate(source); editor.model.changed.emit(); await settle()
	check(runtime.session.document != before and runtime.session.document.components[0].states[1].title == "Changed externally", "Reloading a saved transformation refreshes scene actors")
	selector = inspector.fields.find_child("TransformationState_" + item.id, true, false) as OptionButton
	check(selector != null and selector.get_item_text(1) == "Changed externally", "Asset reload refreshes inspector state labels")
	editor.model.edit_property(actor, definition, &"transformation", ""); await settle()
	check(runtime.visual.texture == null, "Clearing the source removes its scene image safely")
	editor.model.undo(); await settle()
	check(runtime.visual.texture != null, "Clearing the transformation source is undoable")
	var embedded := editor.model.create_actor(definition, 4, {&"transformation": source, &"play_asset_animation": true})
	var animated := editor.model.selected_actor(); seek(5); await settle()
	var embedded_runtime := editor._runtime_for_clip(embedded.id) as ActorTransformImage2DRuntime
	check(is_equal_approx(embedded_runtime.renderer.views[item.id].node.material.get_shader_parameter("progress"), .5), "Optional embedded animation uses the asset's own morph timeline")
	check(ActorTransformationStates.current(animated, item, 2.1) == item.states[1].id, "Inspector state sampling follows the embedded animation")
	seek(20); var retained := embedded_runtime.session.document; inspector.refresh(); await settle(); inspector.refresh()
	check(embedded_runtime.session.document == retained and ActorTransformationStates.load_asset(animated).document == retained, "Inactive actors retain their source document without inspector reload churn")
	seek(5)
	ActorTransformationStates.choose(editor.model, animated, item, item.states[0].id); seek(6.1); await settle()
	check(animated.values[&"component_states"].get(item.id) == item.states[0].id and is_zero_approx(embedded_runtime.renderer.views[item.id].node.material.get_shader_parameter("progress")), "Choosing the currently displayed embedded state explicitly holds that state")
	var saved_state: Dictionary = animated.values[&"component_states"].duplicate(); saved_state.erase(item.id)
	editor.model.edit_property(animated, definition, &"component_states", saved_state); await settle()
	var native_key_button := inspector.fields.find_child("state_" + item.id + "_insert_keyframe", true, false) as Button
	native_key_button.pressed.emit(); await settle()
	check(animated.animation_track(path).keys[0].value == item.states[1].id, "Keying an embedded pose records the currently displayed state, not the default")
	var second_clip := editor.model.create_actor(definition, 4, {&"transformation": source})
	var second_actor := editor.model.selected_actor()
	editor.model.select(embedded.id); editor.model.select(second_clip.id, true)
	ActorTransformationStates.choose(editor.model, second_actor, detail, detail.states[1].id)
	check(animated.values[&"component_states"].get(detail.id) == detail.states[1].id and second_actor.values[&"component_states"].get(detail.id) == detail.states[1].id, "Multi-actor state edits change all selected actors using the same asset")
	editor.model.undo()
	check(not animated.values[&"component_states"].has(detail.id) and not second_actor.values[&"component_states"].has(detail.id), "One undo restores all actors from a batch state edit")
	editor.model.redo()
	check(animated.values[&"component_states"].get(detail.id) == detail.states[1].id and second_actor.values[&"component_states"].get(detail.id) == detail.states[1].id, "Batch state edits redo together")
	var sample_document := ActorTransformationStates.load_asset(actor).document as KiwiTransformationImage2D
	var base_track := actor.animation_track(path)
	var combined := ActorTransformationStates.samples(actor, sample_document, 1, ActorAnimation.sampled_values(actor, 1))
	check(combined[detail.id].a.id == detail.states[1].id and combined[item.id].b.id == item.states[1].id, "Independent components retain their own morph and held state")
	var alternate := sample_document.snapshot(); var alternate_item := alternate.components[0]
	alternate_item.keys[0].mode = "Guided Morph"
	alternate_item.keys[0].points_a = PackedVector2Array([Vector2(.2, .3)])
	alternate_item.keys[0].points_b = PackedVector2Array([Vector2(.6, .7)])
	var guided := ActorTransformationStates.samples(actor, alternate, 1, ActorAnimation.sampled_values(actor, 1))[item.id] as Dictionary
	check(guided.key.points_a.size() == 1, "Scene state transitions retain matching authored morph guidance")
	var third := alternate_item.states[1].copy_state(true); third.title = "Alternate"; alternate_item.states.append(third)
	var alternate_actor := actor.copy_actor(); alternate_actor.animation_track(path).keys[1].value = third.id
	guided = ActorTransformationStates.samples(alternate_actor, alternate, 1, ActorAnimation.sampled_values(alternate_actor, 1))[item.id]
	check(guided.key.points_a.is_empty() and guided.key.mode == "Auto Morph", "Different state pairs do not reuse incompatible guidance points")
	panel._actor = actor; panel.lanes.selected_keys.assign([base_track.keys[0].id]); panel._details_signature = ""; panel._build_details()
	# A different component has different state IDs: multi-key value edits skip it.
	seek(1); editor.model.add_keyframe(actor, ActorTransformationStates.path_for(detail.id), "States / Detail", detail.states[1].id)
	var detail_track := actor.animation_track(ActorTransformationStates.path_for(detail.id))
	panel.lanes.selected_keys.assign([actor.animation_track(path).keys[0].id, detail_track.keys[0].id])
	panel._change_keys(actor.animation_track(path).keys[0].id, {"value": item.states[1].id})
	check(actor.animation_track(ActorTransformationStates.path_for(detail.id)).keys[0].value == detail.states[1].id, "Editing multiple state keys never assigns invalid IDs across different components")
	editor.model.undo()
	editor.model.select(clip.id); seek(1); await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/verification/transform_image_actor_full_application.png")
	main.queue_free(); await settle(); StaticData.loaded_project = null
	print("TRANSFORM_IMAGE_ACTOR checks=%d failures=%d" % [checks, failures]); quit(failures)
