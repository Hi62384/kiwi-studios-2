class_name ActorUIGizmo
extends Control
var editor: ActorTimelineEditor
var display: TextureRect
var drag_key := &"position"
var batch := ActorPropertyBatch.new()
var before: Array[Dictionary] = []
var start_mouse := Vector2.ZERO
var center := Vector2.ZERO
var parents: Dictionary = {}
var origins: Dictionary = {}
var final_values: Dictionary = {}
var resize_axis := Vector2.ONE
var visual_transform := Transform2D.IDENTITY
var camera_preview: SubViewport
var preview_lens: Camera3D
var preview_shader_overlay: ColorRect
var preview_active := false
var preview_clones: Dictionary = {}
var preview_position := Vector2(-1, -1)
var preview_dragging := false
var preview_drag_delta := Vector2.ZERO
var preview_user_moved := false
var spatial:=preload("res://scripts/actors/core/actor_spatial_gizmo.gd").new()

func display_transform() -> Transform2D:
	if display == null or not is_instance_valid(editor) or not is_instance_valid(editor.runtime_holder): return Transform2D.IDENTITY
	var dimensions := Vector2(editor.runtime_holder.get_viewport().get_visible_rect().size)
	var ratio := minf(display.size.x / dimensions.x, display.size.y / dimensions.y)
	return Transform2D(0.0, Vector2(ratio, ratio), 0.0, (display.size - dimensions * ratio) / 2)

func scene_point(point: Vector2) -> Vector2:
	return display_transform().affine_inverse() * point

func handle_points(runtime: ActorUIRuntime) -> Dictionary:
	var points := corners(runtime)
	var origin := display_transform() * runtime.anchor.position
	var top := (points[0] + points[1]) / 2
	var rotate := top + (top - origin).normalized() * 30
	var scale := points[2] + (points[2] - origin).normalized() * 28
	return {"rotation": rotate, "scale": scale, "edges": [(points[0] + points[3]) / 2, (points[1] + points[2]) / 2, (points[0] + points[1]) / 2, (points[2] + points[3]) / 2]}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	focus_mode = Control.FOCUS_ALL
	batch.model = editor.model
	batch.registry = editor.registry
	spatial.editor=editor;spatial.gizmo=self;add_child(spatial)
	camera_preview = SubViewport.new()
	camera_preview.name = "SelectedCameraPreview"
	camera_preview.size = Vector2i(640, 360)
	camera_preview.render_target_update_mode = SubViewport.UPDATE_DISABLED
	camera_preview.world_3d = editor.runtime_holder.get_viewport().find_world_3d()
	add_child(camera_preview)
	preview_lens = Camera3D.new()
	preview_lens.cull_mask = 1
	camera_preview.add_child(preview_lens)
	preview_lens.make_current()
	var overlay_layer := CanvasLayer.new()
	overlay_layer.layer = 100
	camera_preview.add_child(overlay_layer)
	preview_shader_overlay = ColorRect.new()
	preview_shader_overlay.color = Color.WHITE
	preview_shader_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_layer.add_child(preview_shader_overlay)
	preview_shader_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview_shader_overlay.hide()

func selected_runtime() -> ActorUIRuntime:
	if not is_instance_valid(editor): return null
	var clip := editor.model.selected_clip()
	return editor._runtime_for_clip(clip.id) as ActorUIRuntime if clip != null else null

func corners(runtime: ActorUIRuntime) -> PackedVector2Array:
	var rect := runtime.bounds()
	var result := PackedVector2Array()
	for point in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]: result.append(display_transform() * runtime.anchor.transform * point)
	return result

func _process(_delta: float) -> void:
	spatial.sync()
	preview_active = false
	var preview_material: Material
	if is_instance_valid(editor) and is_instance_valid(editor.runtime_holder):
		var selected := editor.model.selected_actor()
		if selected != null and selected.type_id == &"camera_3d":
			var clip := editor.model.clip_for_actor_id(selected.id)
			var runtime := editor._runtime_for_clip(clip.id) if clip != null else null
			if runtime != null and runtime.active and runtime.get("content") is Camera3D:
				var source := runtime.get("content") as Camera3D
				var scene_viewport := editor.runtime_holder.get_viewport()
				if camera_preview.world_3d != scene_viewport.find_world_3d():
					camera_preview.world_3d = scene_viewport.find_world_3d()
				preview_lens.global_transform = source.global_transform
				preview_lens.fov = source.fov
				preview_lens.near = source.near
				preview_lens.far = source.far
				preview_lens.environment = scene_viewport.find_world_3d().environment
				preview_material = runtime.get("camera_shader_material") as ShaderMaterial
				preview_active = true
	_sync_preview_2d()
	preview_shader_overlay.material = preview_material
	preview_shader_overlay.visible = preview_active and preview_material != null
	camera_preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS if preview_active else SubViewport.UPDATE_DISABLED
	queue_redraw()


func _sync_preview_2d() -> void:
	var live: Dictionary = {}
	if preview_active:
		var source_size := Vector2(editor.runtime_holder.get_viewport().size)
		var ratio := Vector2(camera_preview.size) / source_size
		for index in editor.model.actors.size():
			var actor := editor.model.actors[index]
			if not actor.type_id.ends_with("_2d"): continue
			var clip := editor.model.clips[index]
			var original := editor._runtime_for_clip(clip.id) as ActorUIRuntime
			if original == null or not original.active: continue
			live[clip.id] = true
			var mirror: ActorUIRuntime = preview_clones.get(clip.id)
			if not is_instance_valid(mirror):
				var definition := editor.registry.get_definition(actor.type_id)
				mirror = definition.create_runtime(actor) as ActorUIRuntime if definition != null else null
				if mirror == null: continue
				camera_preview.add_child(mirror)
				preview_clones[clip.id] = mirror
			mirror.evaluate_clip(clip, editor.canvas.playhead)
			mirror.anchor.transform = Transform2D.IDENTITY.scaled(ratio) * original.anchor.transform
	for id in preview_clones.keys():
		if live.has(id): continue
		var old: Variant = preview_clones[id]
		if is_instance_valid(old): (old as Node).queue_free()
		preview_clones.erase(id)


func _preview_rect() -> Rect2:
	var width := minf(220.0, maxf(1.0, size.x - 24.0))
	var height := 24.0 + width * 9.0 / 16.0
	if not preview_user_moved:
		preview_position = Vector2(12, maxf(12.0, size.y - height - 12.0))
	preview_position = preview_position.clamp(Vector2(12, 12),
		(size - Vector2(width, height) - Vector2(12, 12)).max(Vector2(12, 12)))
	return Rect2(preview_position, Vector2(width, height))

func _draw() -> void:
	if not is_instance_valid(editor) or editor.exporting:return
	spatial.draw()
	for actor in editor.model.selected_actors():
		if actor==editor.model.selected_actor():continue
		var clip:=editor.model.clip_for_actor_id(actor.id)
		var other:=editor._runtime_for_clip(clip.id) as ActorUIRuntime if clip!=null else null
		if other==null or not other.active:continue
		var outline:=corners(other);outline.append(outline[0]);draw_polyline(outline,Color("7ebadf"),2,true)
	if preview_active:
		var card := _preview_rect()
		draw_rect(card.grow(2), Color("0b1720"))
		draw_rect(Rect2(card.position, Vector2(card.size.x, 24)), Color("1c3944"))
		draw_string(ThemeDB.fallback_font, card.position + Vector2(9, 17),
			"CAMERA  ·  " + editor.model.selected_actor().display_name,
			HORIZONTAL_ALIGNMENT_LEFT, card.size.x - 16, 12, Color("b5f1e8"))
		draw_texture_rect(camera_preview.get_texture(), Rect2(card.position + Vector2(0, 24),
			Vector2(card.size.x, card.size.y - 24)), false)
		draw_rect(card.grow(2), Color("70d7f2"), false, 1)
	var runtime := selected_runtime()
	if runtime == null or not runtime.active: return
	var points := corners(runtime)
	var handles := handle_points(runtime)
	var blue := Color("80bdff")
	draw_line((points[0] + points[1]) / 2, handles.rotation, blue, 2)
	draw_circle(handles.rotation, 8, Color("152a40"))
	draw_arc(handles.rotation, 8, 0, TAU, 32, blue, 3, true)
	draw_line(points[2], handles.scale, blue, 2)
	draw_circle(handles.scale, 9, Color("152a40"))
	draw_arc(handles.scale, 9, 0, TAU, 32, Color("bfa4ed"), 3, true)
	draw_line(handles.scale - Vector2(4, 4), handles.scale + Vector2(4, 4), Color("bfa4ed"), 2)
	for point in Array(points) + handles.edges:
		draw_rect(Rect2(point - Vector2(6, 6), Vector2(12, 12)), Color("152a40"))
		draw_rect(Rect2(point - Vector2(6, 6), Vector2(12, 12)), blue, false, 2)
	points.append(points[0])
	draw_polyline(points, blue, 3, true)

func begin_drag(key: StringName, position: Vector2) -> void:
	var runtime := selected_runtime()
	if runtime == null: return
	drag_key = key
	start_mouse = position
	center = runtime.anchor.position
	visual_transform = runtime.anchor.transform
	var actors: Array[ActorData] = []
	for actor in editor.model.selected_actors():
		if not actor.type_id.ends_with("_2d"): continue
		var ancestor := editor.model.actor_for_id(actor.parent_id)
		var nested := false
		while ancestor != null:
			if editor.model.selected_actors().has(ancestor): nested = true; break
			ancestor = editor.model.actor_for_id(ancestor.parent_id)
		if nested: continue
		actors.append(actor)
		var sampled := ActorAnimation.sampled_values(actor, actor.animation_time)
		origins[actor.id] = sampled.get(key, actor.get_value(key))
		var clip := editor.model.clip_for_actor_id(actor.id)
		var actor_runtime := editor._runtime_for_clip(clip.id) as ActorUIRuntime
		if actor_runtime != null:
			var local := Transform2D(deg_to_rad(float(sampled.get(&"rotation", 0.0))), sampled.get(&"scale", Vector2.ONE), 0.0, sampled.get(&"position", Vector2.ZERO))
			parents[actor.id] = actor_runtime.anchor.transform * local.affine_inverse()
	before = batch.capture(actors, key)
	final_values.clear()
	grab_focus()
	editor.hints.begin(self, "Esc cancels " + ("resize" if key == &"size" else "transform"))

func update_drag(position: Vector2) -> void:
	for state in before:
		var value: Variant = origins.get(state.actor.id, state.value)
		match drag_key:
			&"size":
				var delta := visual_transform.basis_xform_inv(position - start_mouse)
				value = (value + delta * resize_axis * 2).max(Vector2(16, 16))
			&"position": value += (parents.get(state.actor.id, Transform2D.IDENTITY) as Transform2D).basis_xform_inv(position - start_mouse)
			&"rotation": value += (position.x - start_mouse.x) * 0.5 if start_mouse.distance_to(center) < 12 else rad_to_deg((position - center).angle() - (start_mouse - center).angle())
			&"scale": value *= maxf(0.01, 1.0 + (position.x - start_mouse.x - position.y + start_mouse.y) / 160.0 if start_mouse.distance_to(center) < 24 else position.distance_to(center) / start_mouse.distance_to(center))
		final_values[state.actor.id] = value
		editor.model.preview_property(state.actor, editor.registry.get_definition(state.actor.type_id), drag_key, value)

func finish_drag(cancel: bool = false) -> void:
	if before.is_empty(): return
	if cancel: batch.restore(before)
	elif not final_values.is_empty():
		var actors: Array[ActorData] = []
		editor.model.property_batch_active = true
		for state in before:
			actors.append(state.actor)
			editor.model.commit_property_preview(state.actor, editor.registry.get_definition(state.actor.type_id), drag_key, state.value, final_values.get(state.actor.id, state.value))
		editor.model.property_batch_active = false
		batch.commit(before, batch.capture(actors, drag_key), drag_key)
	before = []
	parents.clear()
	origins.clear()
	final_values.clear()
	editor.hints.end(self)

func _gui_input(event: InputEvent) -> void:
	if not is_instance_valid(editor) or editor.exporting or editor.audio_recorder.recording or editor.screen_recorder.recording: return
	if preview_dragging:
		if event is InputEventMouseMotion:
			preview_user_moved = true
			preview_position = event.position - preview_drag_delta
			_preview_rect()
			queue_redraw()
			accept_event()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			preview_dragging = false
			accept_event()
			return
	if preview_active and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and _preview_rect().has_point(event.position):
		if event.pressed and event.position.y < preview_position.y + 24:
			preview_dragging = true
			preview_drag_delta = event.position - preview_position
		accept_event()
		return
	if spatial.handle_event(event):accept_event();return
	if event is InputEventKey and event.pressed and not event.echo and has_focus() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if event.is_action_pressed("undo") or event.is_action_pressed("redo"):
			if not spatial.rig.before.is_empty():spatial.rig.finish(true)
			elif not spatial.before.is_empty():spatial.finish(true)
			elif not before.is_empty():finish_drag(true)
			elif event.is_action_pressed("redo"):editor.redo()
			else:editor.undo()
			accept_event();return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and not before.is_empty(): finish_drag(true); accept_event(); return
	if event is InputEventMouseMotion and not before.is_empty(): update_drag(scene_point(event.position)); accept_event(); return
	if event is InputEventMouseMotion:
		tooltip_text = ""
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		if preview_active and _preview_rect().has_point(event.position):
			if event.position.y < preview_position.y + 24:
				tooltip_text = "Drag to move camera preview"
				mouse_default_cursor_shape = Control.CURSOR_MOVE
			return
		var hovered := selected_runtime()
		if hovered != null and hovered.active:
			var handles := handle_points(hovered)
			if handles.rotation.distance_to(event.position) < 16:
				tooltip_text = "Rotate"
				mouse_default_cursor_shape = Control.CURSOR_CROSS
			elif handles.scale.distance_to(event.position) < 16:
				tooltip_text = "Scale"
				mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
			else:
				for point in Array(corners(hovered)) + handles.edges:
					if point.distance_to(event.position) < 14:
						tooltip_text = "Resize"
						mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
				if tooltip_text.is_empty() and Geometry2D.is_point_in_polygon(event.position, corners(hovered)):
					tooltip_text = "Move"
					mouse_default_cursor_shape = Control.CURSOR_MOVE
		if hovered==null:spatial.hover(event.position)
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT: return
	if not event.pressed:
		if not before.is_empty(): finish_drag(); accept_event()
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):return
	var runtime := selected_runtime()
	if runtime != null and runtime.active and not event.ctrl_pressed and not event.shift_pressed:
		var points := corners(runtime)
		var handles := handle_points(runtime)
		if handles.rotation.distance_to(event.position) < 16: begin_drag(&"rotation", scene_point(event.position)); accept_event(); return
		if handles.scale.distance_to(event.position) < 16: begin_drag(&"scale", scene_point(event.position)); accept_event(); return
		var resize_handles: Array = Array(points) + handles.edges
		var axes := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
		for index in resize_handles.size():
			if resize_handles[index].distance_to(event.position) < 14:
				resize_axis = axes[index]
				begin_drag(&"size", scene_point(event.position)); accept_event(); return
	for index in range(editor.model.clips.size() - 1, -1, -1):
		var candidate := editor._runtime_for_clip(editor.model.clips[index].id) as ActorUIRuntime
		if candidate != null and candidate.active and Geometry2D.is_point_in_polygon(event.position, corners(candidate)):
			var id:=editor.model.clips[index].id
			if event.ctrl_pressed:editor.model.toggle_selection(id)
			else:editor.model.select(id,event.shift_pressed or editor.model.is_selected(id))
			if not event.ctrl_pressed and not event.shift_pressed:begin_drag(&"position", scene_point(event.position))
			accept_event()
			return
	var hit:String=spatial.pick(event.position)
	if not hit.is_empty():
		if event.ctrl_pressed:editor.model.toggle_selection(hit)
		else:editor.model.select(hit,event.shift_pressed or editor.model.is_selected(hit))
		grab_focus();accept_event()
	elif not event.ctrl_pressed and not event.shift_pressed and spatial.in_picture(event.position):
		editor.model.select("");grab_focus();accept_event()
