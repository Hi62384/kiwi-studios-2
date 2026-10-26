extends SubViewport
## One isolated renderer reused by many library entries. No stand-in shader is
## ever substituted: canvas, surface, sky, volume and particles run their source.
const DiagnosticLogger = preload("res://Workspaces/ShaderWorkspace/shader_preview_logger.gd")
var material := ShaderMaterial.new()
var shader := Shader.new()
var error_text := ""
var kind := ""
var _root := Node3D.new()
var _mesh := MeshInstance3D.new()
var _camera := Camera3D.new()
var _environment := WorldEnvironment.new()
var _fog := FogVolume.new()
var _particles := GPUParticles3D.new()
var _canvas := TextureRect.new()
var _background := TextureRect.new()
var _logger := DiagnosticLogger.new()
var _distance := 3.5
var _yaw := 0.35
var _pitch := -0.15
var _geometry := "sphere"
var _active := false
static var _test_texture: ImageTexture
static var _normal_texture: ImageTexture
static var _particle_texture: ImageTexture

func _ready() -> void:
	size = Vector2i(384, 256)
	own_world_3d = true
	transparent_bg = false
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	OS.add_logger(_logger)
	add_child(_root)
	_root.add_child(_mesh)
	_root.add_child(_camera)
	_camera.current = true
	_camera.fov = 46
	_root.add_child(_environment)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("152233")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c8dcf5")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_environment.environment = environment
	for spec in [[Vector3(-40, -35, 0), 1.8, Color.WHITE], [Vector3(25, 140, 0), 0.8, Color("7dadf2")]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = spec[0]
		light.light_energy = spec[1]
		light.light_color = spec[2]
		_root.add_child(light)
	_root.add_child(_fog)
	_fog.size = Vector3(2.8, 2.8, 2.8)
	_root.add_child(_particles)
	_particles.amount = 180
	_particles.lifetime = 3.0
	_particles.preprocess = 1.8
	_particles.visibility_aabb = AABB(Vector3(-8, -8, -8), Vector3(16, 16, 16))
	_particles.draw_pass_1 = particle_draw_mesh()
	for rectangle in [_background, _canvas]:
		rectangle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rectangle.stretch_mode = TextureRect.STRETCH_SCALE
		rectangle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rectangle.size = Vector2(size)
		rectangle.texture = test_texture()
		add_child(rectangle)
	set_geometry("sphere")
	_update_camera()

func _exit_tree() -> void:
	_logger.capturing = false
	OS.remove_logger(_logger)

func show_entry(entry: Dictionary) -> String:
	_logger.capturing = false
	_logger.clear()
	error_text = ""
	kind = str(entry.get("shader_type", "spatial"))
	if DisplayServer.get_name() == "headless":
		error_text = "Rendered previews require a graphics display; headless mode cannot render these shaders."
	elif kind == "fog" and RenderingServer.get_current_rendering_method() != "forward_plus":
		error_text = "FogVolume previews require the Forward+ renderer."
	if not error_text.is_empty():
		set_active(false)
		return error_text
	var source := str(entry.get("source", ""))
	if source.is_empty() and FileAccess.file_exists(str(entry.get("path", ""))):
		source = FileAccess.get_file_as_string(str(entry.path))
	if not RegEx.create_from_string("(?m)^\\s*shader_type\\s+" + kind + "\\s*;").search(source):
		error_text = "Missing or mismatched shader_type declaration."
		set_active(false)
		return error_text
	_logger.capturing = true
	shader = Shader.new()
	shader.code = source
	material = ShaderMaterial.new()
	material.shader = shader
	# Asking the rendering server for uniforms forces semantic shader compilation.
	var uniforms := shader.get_shader_uniform_list()
	for uniform in uniforms:
		if int(uniform.get("type", 0)) == TYPE_OBJECT:
			var uniform_name := str(uniform.name)
			var declaration := RegEx.create_from_string("uniform\\s+sampler2D\\s+" + uniform_name + "\\b[^;]*;").search(source)
			if declaration == null: continue
			var declaration_text := declaration.get_string()
			if declaration_text.contains("hint_screen_texture") or declaration_text.contains("hint_depth_texture") or declaration_text.contains("hint_normal_roughness_texture"): continue
			if declaration_text.contains("hint_normal") or uniform_name.contains("normal"):
				material.set_shader_parameter(uniform_name, normal_texture())
			elif uniform_name in ["source_texture", "albedo_texture", "texture_a", "texture_b"]:
				material.set_shader_parameter(uniform_name, test_texture())
	_mesh.visible = kind == "spatial"
	_fog.visible = kind == "fog"
	_particles.visible = kind == "particles"
	_particles.emitting = kind == "particles"
	_canvas.visible = kind == "canvas_item"
	_background.visible = kind == "canvas_item" and source.contains("hint_screen_texture")
	for rectangle in [_background, _canvas]:
		rectangle.size = Vector2(size)
	_canvas.material = material if kind == "canvas_item" else null
	_mesh.material_override = material if kind == "spatial" else null
	_fog.material = material if kind == "fog" else null
	_particles.process_material = material if kind == "particles" else null
	_environment.environment.volumetric_fog_enabled = kind == "fog"
	_environment.environment.volumetric_fog_density = 0.0
	_environment.environment.background_mode = Environment.BG_SKY if kind == "sky" else Environment.BG_COLOR
	if kind == "sky":
		var sky := Sky.new()
		sky.sky_material = material
		_environment.environment.sky = sky
	else:
		_environment.environment.sky = null
	set_geometry(str(entry.get("preview_mesh", "sphere")))
	if kind == "particles":
		_particles.restart()
	_distance = 4.6 if kind in ["fog", "particles"] else 3.5
	_yaw = 0.35
	_pitch = 0.35 if kind == "sky" else -0.15
	_update_camera()
	set_active(true)
	return check_errors()

func check_errors() -> String:
	var errors := _logger.messages()
	if not errors.is_empty():
		error_text = "Shader compilation failed:\n" + "\n".join(errors)
		set_active(false)
	return error_text

func finish_compilation() -> void:
	# Later thumbnail compilation must not be attributed to the live selection.
	_logger.capturing = false

func set_active(value: bool) -> void:
	_active = value
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if value else SubViewport.UPDATE_DISABLED
	_particles.speed_scale = 1.0 if value else 0.0
	if not value:
		_logger.capturing = false

func set_geometry(value: String) -> void:
	_geometry = value
	match value:
		"plane":
			var plane := PlaneMesh.new()
			plane.size = Vector2(2.1, 2.1)
			plane.subdivide_width = 64
			plane.subdivide_depth = 64
			_mesh.mesh = plane
			_mesh.rotation_degrees = Vector3(70, 0, 0)
		"cube", "box":
			var box := BoxMesh.new()
			box.size = Vector3.ONE * 1.55
			box.subdivide_width = 20
			box.subdivide_height = 20
			box.subdivide_depth = 20
			_mesh.mesh = box
			_mesh.rotation_degrees = Vector3.ZERO
		_:
			var sphere := SphereMesh.new()
			sphere.radius = 0.95
			sphere.height = 1.9
			sphere.radial_segments = 64
			sphere.rings = 32
			_mesh.mesh = sphere
			_mesh.rotation_degrees = Vector3.ZERO

func orbit(delta: Vector2) -> void:
	_yaw -= delta.x * 0.008
	_pitch = clampf(_pitch - delta.y * 0.008, -1.3, 1.3)
	_update_camera()

func zoom(factor: float) -> void:
	_distance = clampf(_distance * factor, 1.5, 10.0)
	_update_camera()

func _update_camera() -> void:
	_camera.position = Vector3(sin(_yaw) * cos(_pitch), sin(-_pitch), cos(_yaw) * cos(_pitch)) * _distance
	_camera.look_at(Vector3.ZERO, Vector3.UP)

static func test_texture() -> Texture2D:
	if _test_texture != null:
		return _test_texture
	var image := Image.create(192, 192, false, Image.FORMAT_RGBA8)
	for y in 192:
		for x in 192:
			var uv := Vector2(x, y) / 192.0
			var checker := (x / 24 + y / 24) % 2
			var color := Color("e5c37e") if checker == 0 else Color("4687b9")
			var distance := (uv - Vector2(0.5, 0.5)).length()
			if distance < 0.3:
				color = Color("e96e60").lerp(Color("fff0b7"), uv.y)
			color.a = 1.0 - smoothstep(0.45, 0.49, maxf(absf(uv.x - 0.5), absf(uv.y - 0.5)))
			image.set_pixel(x, y, color)
	_test_texture = ImageTexture.create_from_image(image)
	return _test_texture

static func normal_texture() -> Texture2D:
	if _normal_texture == null:
		var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.5, 0.5, 1.0, 1.0))
		_normal_texture = ImageTexture.create_from_image(image)
	return _normal_texture

static func particle_draw_mesh() -> QuadMesh:
	# The process shader controls scale; billboard facing must retain that scale.
	# A neutral radial sprite exposes COLOR/ALPHA without square sprite edges.
	if _particle_texture == null:
		var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var distance := (Vector2(x, y) + Vector2(0.5, 0.5) - Vector2(32, 32)).length() / 32.0
				image.set_pixel(x, y, Color(1, 1, 1, 1.0 - smoothstep(0.25, 1.0, distance)))
		_particle_texture = ImageTexture.create_from_image(image)
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var surface := StandardMaterial3D.new()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.vertex_color_use_as_albedo = true
	surface.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	surface.billboard_keep_scale = true
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.albedo_texture = _particle_texture
	mesh.material = surface
	return mesh
