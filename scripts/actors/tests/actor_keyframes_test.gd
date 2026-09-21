extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var editor := ActorTimelineEditor.new()
	root.add_child(editor)
	await process_frame
	var model := editor.model
	var definition := editor.registry.get_definition(&"point_3d")
	var clip := model.create_actor(definition, 10)
	var actor := model.selected_actor()
	var path := PackedStringArray(["position"])
	model.playhead_time = 10
	editor.canvas.playhead = 10
	model.add_keyframe(actor, path, "Transform / Position", Vector3.ZERO)
	model.playhead_time = 14
	editor.canvas.playhead = 14
	model.add_keyframe(actor, path, "Transform / Position", Vector3(8, 4, 2))
	var track := actor.animation_track(path)
	check(track.keys.size() == 2 and track.keys[0].time == 0 and track.keys[1].time == 4,
		"Keys use clip source-local time")
	check(track.sample(2).is_equal_approx(Vector3(4, 2, 1)), "Vector tracks interpolate")
	var first_id := track.keys[0].id
	model.edit_keyframe(actor, first_id, {"interpolation": ActorKeyframe.Interpolation.EASE, "attenuation": 2.0})
	check(actor.animation_track(path).sample(2).is_equal_approx(Vector3(2, 1, 0.5)), "Attenuation controls easing")
	model.undo()
	check(actor.animation_track(path).sample(2).is_equal_approx(Vector3(4, 2, 1)), "Undo restores interpolation")
	model.redo()
	check(actor.animation_track(path).sample(2).is_equal_approx(Vector3(2, 1, 0.5)), "Redo restores attenuation")
	var before := model.animation_snapshot(actor)
	model.preview_keyframe(actor, first_id, {"value": Vector3.ONE})
	model.restore_animation(actor, before)
	check(actor.animation_track(path).keys[0].value == Vector3.ZERO, "Cancelled preview restores key value")
	model.edit_keyframe(actor, first_id, {"time": 1.0})
	check(actor.animation_track(path).keys[0].time == 1.0, "Key time can be edited")
	model.undo()
	model.playhead_time = 12
	editor.canvas.playhead = 12
	model.preview_property(actor, definition, &"position", Vector3(7, 7, 7))
	check(ActorAnimation.sampled_values(actor, 2)[&"position"] == Vector3(7, 7, 7), "Animated property drag previews immediately")
	check(actor.values[&"position"] == Vector3.ZERO, "Animation preview never mutates base actor values")
	model.commit_property_preview(actor, definition, &"position", Vector3.ZERO, Vector3(7, 7, 7))
	check(actor.animation_track(path).key_at(2).value == Vector3(7, 7, 7), "Existing property editors record a key at cursor")
	model.undo()
	check(actor.animation_track(path).key_at(2) == null and actor.animation_previews.is_empty(), "One undo removes recorded preview key")
	var runtime := definition.create_runtime(actor)
	root.add_child(runtime)
	runtime.evaluate_clip(clip, 12)
	check(actor.get_value(&"position") == Vector3(2, 1, 0.5), "Runtime samples actor animation when seeking")
	model.move_clip(clip.id, 20)
	check(actor.animation_track(path).keys[1].time == 4, "Moving actor keeps keys in clip-local coordinates")
	model.undo()
	var material_definition := editor.registry.get_object_definition(&"material")
	var material := material_definition.create_object()
	var asset_path := "user://keyframe_material_" + ActorData.new_id() + ".tres"
	check(ResourceSaver.save(material, asset_path) == OK, "Create file-backed object for animation test")
	actor.values[&"material"] = ActorObjectReference.from_asset(asset_path, &"material")
	var material_path := PackedStringArray(["material", "roughness"])
	model.playhead_time = 10
	editor.canvas.playhead = 10
	model.add_keyframe(actor, material_path, "Material / Roughness", 0.0)
	model.playhead_time = 14
	editor.canvas.playhead = 14
	model.add_keyframe(actor, material_path, "Material / Roughness", 1.0)
	var values := ActorAnimation.sampled_values(actor, 2)
	var sampled_material := (values[&"material"] as ActorObjectReference).resolve()
	check(is_equal_approx(sampled_material.get_value(&"roughness"), 0.5), "File-backed object property animates privately")
	var original := ResourceLoader.load(asset_path) as ActorObjectData
	var original_roughness: Variant = original.get_value(&"roughness")
	model.playhead_time = 12
	editor.canvas.playhead = 12
	model.edit_object_property(actor, original, material_definition, &"roughness", 0.75)
	check(actor.animation_track(material_path).key_at(2).value == 0.75, "Object inspector edits become actor-owned keys")
	var unchanged := ResourceLoader.load(asset_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData
	check(unchanged.get_value(&"roughness") == original_roughness, "Animated editing does not write to asset file")
	model.undo()
	check(actor.animation_track(material_path).key_at(2) == null, "Object key editing supports undo")
	var copy := actor.copy_actor()
	check(copy.animation_tracks.size() == actor.animation_tracks.size() and copy.animation_tracks[0] != actor.animation_tracks[0], "Copies own their animation tracks")
	var save_path := "user://keyframed_actor_" + ActorData.new_id() + ".tres"
	check(ResourceSaver.save(actor, save_path) == OK, "Animated actor is saveable")
	var loaded := ResourceLoader.load(save_path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorData
	check(loaded.animation_track(path).keys.size() == 2, "Tracks and keys survive resource round trip")
	model.delete_keyframes(actor, [first_id])
	check(model.keyframe_for_id(actor, first_id) == null, "Key deletion works")
	model.undo()
	check(model.keyframe_for_id(actor, first_id) != null, "Undo restores deleted key")
	editor.keyframe_editor.lanes.selected_keys.assign([first_id])
	editor.keyframe_editor._build_details()
	check(editor.keyframe_editor.details.get_child_count() >= 6, "Clicking a vector key exposes time, interpolation, attenuation and components")
	editor.keyframe_editor._move_keys([first_id], 0.5)
	check(model.keyframe_for_id(actor, first_id).time == 0.5, "Timeline key drag moves keys")
	model.undo()
	check(model.keyframe_for_id(actor, first_id).time == 0, "Key drag undoes as one action")
	var lanes := editor.keyframe_editor.lanes
	var row := actor.animation_tracks.find(actor.animation_track(path))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = lanes.key_position(model.keyframe_for_id(actor, first_id), row)
	press.global_position = Vector2(100, 100)
	lanes._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(100 + editor.canvas.pixels_per_second * 0.5, 100)
	lanes._input(motion)
	check(model.keyframe_for_id(actor, first_id).time == 0.5, "Pointer key drag previews real track changes live")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	lanes._input(release)
	model.undo()
	check(model.keyframe_for_id(actor, first_id).time == 0, "Pointer key drag produces one undo entry")
	press.position = lanes.key_position(model.keyframe_for_id(actor, first_id), row)
	lanes._gui_input(press)
	lanes._input(motion)
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	lanes._input(escape)
	check(model.keyframe_for_id(actor, first_id).time == 0, "Esc cancels pointer keyframe movement")
	model.playhead_time = 10
	editor.canvas.playhead = 10
	var switch_path := PackedStringArray(["test_switch"])
	model.add_keyframe(actor, switch_path, "Test / Switch", false)
	model.playhead_time = 14
	editor.canvas.playhead = 14
	model.add_keyframe(actor, switch_path, "Test / Switch", true)
	check(actor.animation_track(switch_path).sample(2) == false and actor.animation_track(switch_path).sample(4) == true,
		"Boolean animation uses discrete steps")
	model.playhead_time = 10
	editor.canvas.playhead = 10
	var color_path := PackedStringArray(["test_color"])
	model.add_keyframe(actor, color_path, "Test / Color", Color.BLACK)
	model.playhead_time = 14
	editor.canvas.playhead = 14
	model.add_keyframe(actor, color_path, "Test / Color", Color.WHITE)
	check(actor.animation_track(color_path).sample(2).is_equal_approx(Color(0.5, 0.5, 0.5)), "Color keys interpolate")
	var shader_definition := editor.registry.get_object_definition(&"shader_material")
	var shader_object := shader_definition.create_object()
	actor.values[&"test_shader"] = ActorObjectReference.from_object(shader_object)
	var uniform_path := PackedStringArray(["test_shader", "uniforms", "gain"])
	model.add_keyframe(actor, uniform_path, "Shader / Gain", 0.2)
	model.playhead_time = 12
	editor.canvas.playhead = 12
	model.edit_shader_uniform(actor, shader_object, shader_definition, &"gain", 0.8)
	check(actor.animation_track(uniform_path).key_at(2).value == 0.8, "Shader uniforms are individually keyframed")
	check(not shader_object.get_value(&"uniforms", {}).has(&"gain"), "Animating uniform does not modify shared object values")
	model.edit_shader_uniform(actor, shader_object, shader_definition, &"other", 0.4)
	check(shader_object.get_value(&"uniforms")[&"other"] == 0.4, "Unanimated uniform remains editable alongside animated uniforms")
	var shader_values := ActorAnimation.sampled_values(actor, 2)
	check((shader_values[&"test_shader"] as ActorObjectReference).resolve().get_value(&"uniforms")[&"gain"] == 0.8,
		"Runtime sampling applies animated uniforms into private object overrides")
	model.preview_animation_value(actor, uniform_path, 0.1)
	model.preview_animation_value(actor, uniform_path, 0.8)
	check(actor.animation_previews.is_empty(), "Restoring original animated value clears cancelled preview")
	var inspector := ActorInspector.new()
	root.add_child(inspector)
	inspector.setup(model, editor.registry)
	check(inspector.fields.find_child("position_keyframe", true, false) != null, "Actor inspector exposes keyframe button")
	var shape := model.create_actor(editor.registry.get_definition(&"basic_shape"), 0)
	var shape_actor := model.actor_for_id(shape.actor_id)
	shape_actor.values[&"material"] = ActorObjectReference.from_asset(asset_path, &"material")
	inspector._rebuild_selected()
	check(inspector.fields.find_child("roughness_keyframe", true, false) != null, "File-backed nested object inspector exposes keyframe buttons")
	inspector.queue_free()
	runtime.queue_free()
	editor.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(asset_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	await process_frame
	print("Actor keyframe checks: %d failures" % failures)
	quit(failures)
