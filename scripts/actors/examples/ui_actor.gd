class_name ActorUIRuntime
extends ActorRuntime
var canvas_layer: CanvasLayer
var anchor := Node2D.new()
var visual := Visual.new()
var label := Label.new()
var _values: Dictionary = {}
var _time := 0.0
var _image_signature := ""
var _video_path := ""
var _text_signature := -1
var particles_2d: GPUParticles2D
var particle_material_2d: ParticleProcessMaterial
var _particles_emitting := true
var _particle_settings_hash := -1
var canvas_shader_material: ShaderMaterial
var _canvas_shader_key := ""

class Visual:
	extends Node2D
	static var shared_solid_texture: Texture2D
	var dimensions := Vector2(400, 240)
	var texture: Texture2D
	var shape := -1
	var fill := Color.WHITE
	var outline := Color.WHITE
	var width := 0.0
	var solid_texture: Texture2D
	func _ready() -> void:
		if shared_solid_texture == null:
			var white := Image.create(1, 1, false, Image.FORMAT_RGBA8)
			white.fill(Color.WHITE)
			shared_solid_texture = ImageTexture.create_from_image(white)
		solid_texture = shared_solid_texture
	func _draw() -> void:
		var rect := Rect2(-dimensions / 2, dimensions)
		if texture != null:
			var ratio := minf(dimensions.x / texture.get_width(), dimensions.y / texture.get_height())
			var fitted := texture.get_size() * ratio
			draw_texture_rect(texture, Rect2(-fitted / 2, fitted), false)
		elif shape >= 0:
			if shape == 5:
				draw_line(Vector2(-dimensions.x / 2, 0), Vector2(dimensions.x / 2, 0), fill, maxf(width, 1.0), true)
				return
			var polygon := PackedVector2Array()
			match shape:
				1:
					for point in 64: polygon.append(Vector2(cos(point * TAU / 64), sin(point * TAU / 64)) * dimensions / 2)
				2: polygon = PackedVector2Array([Vector2(0, -dimensions.y / 2), dimensions / 2, Vector2(-dimensions.x / 2, dimensions.y / 2)])
				3: polygon = PackedVector2Array([Vector2(0, -dimensions.y / 2), Vector2(dimensions.x / 2, 0), Vector2(0, dimensions.y / 2), Vector2(-dimensions.x / 2, 0)])
				4:
					for point in 10:
						var angle := point * TAU / 10 - PI / 2
						polygon.append(Vector2(cos(angle), sin(angle)) * dimensions / 2 * (1.0 if point % 2 == 0 else 0.45))
				_: polygon = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
			# Procedural CanvasItem shaders need real shape-local UVs and a
			# non-null TEXTURE, just as image actors provide. Otherwise texture()
			# and UV-based effects sample a blank/constant input on basic shapes.
			var uvs := PackedVector2Array()
			for point in polygon:
				uvs.append((point - rect.position) / dimensions)
			draw_colored_polygon(polygon, fill, uvs, solid_texture)
			if width > 0:
				polygon.append(polygon[0])
				draw_polyline(polygon, outline, width, true)

func _ready() -> void:
	add_to_group("actor_shader_runtimes")
	canvas_layer = CanvasLayer.new()
	canvas_layer.layer = 10
	add_child(canvas_layer)
	canvas_layer.add_child(anchor)
	anchor.add_child(visual)
	visual.add_child(label)
	label.use_parent_material = true
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = actor.type_id == &"text_2d"
	if actor.type_id == &"particles_2d":
		particles_2d = GPUParticles2D.new()
		particles_2d.use_fixed_seed = true
		particles_2d.seed = actor.id.hash() & 0x7fffffff
		particle_material_2d = ParticleProcessMaterial.new()
		particle_material_2d.particle_flag_disable_z = true
		particles_2d.process_material = particle_material_2d
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
		var particle_texture := GradientTexture2D.new()
		particle_texture.width = 32
		particle_texture.height = 32
		particle_texture.fill = GradientTexture2D.FILL_RADIAL
		particle_texture.fill_from = Vector2(0.5, 0.5)
		particle_texture.fill_to = Vector2(1.0, 0.5)
		particle_texture.gradient = gradient
		particles_2d.texture = particle_texture
		anchor.add_child(particles_2d)

func bounds() -> Rect2:
	var rect := Rect2(-visual.dimensions / 2, visual.dimensions)
	return rect.merge(label.get_rect()) if label.visible else rect

func evaluate_transform(values: Dictionary) -> void:
	var position: Vector2 = values.get(&"position", Vector2.ZERO)
	var transform := Transform2D(deg_to_rad(float(values.get(&"rotation", 0.0))), values.get(&"scale", Vector2.ONE), 0.0, position)
	var ancestor := get_parent()
	while ancestor != null and not ancestor is ActorRuntime: ancestor = ancestor.get_parent()
	if ancestor is ActorUIRuntime: anchor.transform = ancestor.anchor.transform * transform
	else:
		transform.origin += Vector2(get_viewport().get_visible_rect().size) / 2
		anchor.transform = transform

func set_active(value: bool) -> void:
	super.set_active(value)
	visual.visible = value
	if particles_2d != null:
		particles_2d.visible = value
		if particles_2d.emitting != (value and _particles_emitting):
			particles_2d.emitting = value and _particles_emitting

func evaluate(time: float, values: Dictionary) -> void:
	_time = time
	_values = values
	visual.dimensions = Vector2(values.get(&"size", Vector2(400, 240))).abs().max(Vector2.ONE)
	match actor.type_id:
		&"text_2d":
			label.text = str(values.get(&"text", "Text"))
			label.position = -visual.dimensions / 2
			label.size = visual.dimensions
			var settings := ActorTextSettings.values(values.get(&"text_settings"))
			if settings.hash() != _text_signature:
				_text_signature = settings.hash()
				ActorTextSettings.apply_label(label, settings)
		&"basic_shape_2d":
			visual.shape = int(values.get(&"shape", 0))
			visual.fill = values.get(&"color", Color.WHITE)
			visual.outline = values.get(&"outline_color", Color.WHITE)
			visual.width = maxf(0, float(values.get(&"outline_size", 0.0)))
		&"image_2d":
			var reference: Variant = values.get(&"image_path")
			var object: ActorObjectData = ActorAnimation.resolve_reference(reference) if reference is ActorObjectReference else null
			var signature := str(object.values.hash()) if object != null else "empty"
			if signature != _image_signature:
				_image_signature = signature
				visual.texture = ActorImageGenerator.texture_for_object(object)
		&"video_2d":
			var path := str(values.get(&"video", ""))
			if path != _video_path:
				_video_path = path
				visual.texture = null
			var texture := ActorVideo.frame(path, time, true)
			if texture != null: visual.texture = texture
		&"line_2d":
			visual.shape = 5
			visual.fill = values.get(&"color", Color.WHITE)
			visual.width = maxf(0.1, float(values.get(&"width", 4.0)))
		&"particles_2d": _apply_particles_2d(values)
	_apply_canvas_material(values.get(&"material"))
	visual.queue_redraw()


func _apply_canvas_material(value: Variant) -> void:
	var reference := value as ActorObjectReference if value is ActorObjectReference else null
	var object := reference.resolve(_load_object_resource) if reference != null else null
	if object == null or object.type_id != &"canvas_shader_material":
		canvas_shader_material = null
		_canvas_shader_key = ""
		visual.material = null
		if particles_2d != null: particles_2d.material = null
		return
	var shader_source: Variant = object.get_value(&"shader_path", "")
	# A newly-created Canvas ShaderMaterial intentionally starts with an empty
	# string until its nested Shader resource is created. `as Shader` cannot cast
	# scalar Variants, so only cast actual Resource objects.
	var source_shader := shader_source as Shader if shader_source is Shader else null
	var shader_path := str(shader_source) if shader_source is String else ""
	if source_shader == null and not shader_path.is_empty():
		source_shader = ResourceLoader.load(_resource_path(shader_path), "", ResourceLoader.CACHE_MODE_IGNORE) as Shader
	var key := str(source_shader.get_instance_id()) + ":" + str(source_shader.code.hash()) if source_shader != null else "empty"
	if canvas_shader_material == null or key != _canvas_shader_key:
		_canvas_shader_key = key
		canvas_shader_material = ShaderMaterial.new()
		if source_shader != null and _is_canvas_shader(source_shader.code):
			var runtime_shader := Shader.new()
			var timed := ActorShaderTime.prepare(source_shader.code)
			runtime_shader.code = timed.code
			canvas_shader_material.shader = runtime_shader
			canvas_shader_material.set_meta("kiwi_time_uniform", timed.uniform)
	visual.material = canvas_shader_material if canvas_shader_material.shader != null else null
	if particles_2d != null:
		particles_2d.material = visual.material
	if canvas_shader_material.shader == null:
		return
	var uniforms: Dictionary = object.get_value(&"uniforms", {})
	for info: Dictionary in canvas_shader_material.shader.get_shader_uniform_list():
		var uniform_name := StringName(info.get("name", ""))
		if uniform_name.is_empty() or not uniforms.has(uniform_name):
			continue
		var uniform_value: Variant = uniforms[uniform_name]
		if int(info.get("type", TYPE_NIL)) == TYPE_OBJECT:
			uniform_value = _texture_for_value(uniform_value)
		canvas_shader_material.set_shader_parameter(uniform_name, uniform_value)


func _is_canvas_shader(code: String) -> bool:
	return RegEx.create_from_string("(?m)^\\s*shader_type\\s+canvas_item\\s*;").search(code) != null


func _load_object_resource(path: String) -> ActorObjectData:
	var localized := _resource_path(path)
	return ResourceLoader.load(localized, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData \
		if ResourceLoader.exists(localized) else null


func _resource_path(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if normalized.begins_with("res://") or normalized.begins_with("user://"):
		return normalized
	return ProjectSettings.localize_path(normalized)


func _texture_for_value(value: Variant) -> Texture2D:
	if value is Texture2D:
		return value
	if value is ActorObjectReference:
		return ActorImageGenerator.texture_for_object((value as ActorObjectReference).resolve(_load_object_resource))
	if value is ActorObjectData:
		return ActorImageGenerator.texture_for_object(value)
	var path := _resource_path(str(value))
	if path.is_empty():
		return null
	if path.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg", "hdr", "exr"]:
		var image := ActorImageGenerator.image_from_value(path)
		return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
	var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource is Texture2D:
		return resource
	if resource is ActorObjectData:
		return ActorImageGenerator.texture_for_object(resource)
	return null


func refresh_saved_image(_source: Variant) -> void:
	_image_signature = ""


func _apply_particles_2d(values: Dictionary) -> void:
	if particles_2d == null or particle_material_2d == null:
		return
	_particles_emitting = values.get(&"emitting", true)
	if particles_2d.emitting != (active and _particles_emitting):
		particles_2d.emitting = active and _particles_emitting
	var settings_hash := [values.get(&"amount", 64), values.get(&"lifetime", 1.0),
		values.get(&"one_shot", false), values.get(&"explosiveness", 0.0),
		values.get(&"direction", -90.0), values.get(&"spread", 30.0),
		values.get(&"velocity", 120.0), values.get(&"gravity", Vector2(0, 98)),
		values.get(&"color", Color.WHITE), values.get(&"particle_size", 1.0)].hash()
	if settings_hash == _particle_settings_hash: return
	_particle_settings_hash = settings_hash
	particles_2d.amount = maxi(1, int(values.get(&"amount", 64)))
	particles_2d.lifetime = maxf(0.05, float(values.get(&"lifetime", 1.0)))
	particles_2d.one_shot = values.get(&"one_shot", false)
	particles_2d.explosiveness = values.get(&"explosiveness", 0.0)
	var angle := deg_to_rad(float(values.get(&"direction", -90.0)))
	particle_material_2d.direction = Vector3(cos(angle), sin(angle), 0)
	particle_material_2d.spread = values.get(&"spread", 30.0)
	var velocity := float(values.get(&"velocity", 120.0))
	particle_material_2d.initial_velocity_min = velocity
	particle_material_2d.initial_velocity_max = velocity
	var gravity: Vector2 = values.get(&"gravity", Vector2(0, 98))
	particle_material_2d.gravity = Vector3(gravity.x, gravity.y, 0)
	particle_material_2d.color = values.get(&"color", Color.WHITE)
	var particle_scale := maxf(0.01, float(values.get(&"particle_size", 1.0)))
	particle_material_2d.scale_min = particle_scale
	particle_material_2d.scale_max = particle_scale

func _process(_delta: float) -> void:
	if active and actor.type_id == &"video_2d" and not _values.is_empty(): evaluate(_time, _values)


func set_timeline_time(timeline_time: float) -> void:
	if canvas_shader_material == null:
		return
	var uniform_name := str(canvas_shader_material.get_meta("kiwi_time_uniform", ""))
	if not uniform_name.is_empty():
		canvas_shader_material.set_shader_parameter(uniform_name, timeline_time)


func refresh_saved_shader(_source: Variant) -> void:
	_canvas_shader_key = ""
	if not _values.is_empty():
		_apply_canvas_material(_values.get(&"material"))
