extends ActorRuntime
## Runtime implementation shared by the catalog's lightweight 3D actors.

const ShaderTime = preload("res://scripts/actors/core/actor_shader_time.gd")
const NaturalEngine = preload("res://scripts/materials/natural_material_engine.gd")

var content: Node
var parenting_anchor: Node3D
var material: StandardMaterial3D
var shader_material: ShaderMaterial
var natural_material: ShaderMaterial
var _natural_settings: Dictionary = {}
var loaded_shader_path := ""
var loaded_image_path := ""
var loaded_model_path := ""
var texture_cache: Dictionary = {}
var noise_texture_cache: Dictionary = {}
var _watched_shader: Shader
var _shape_kind := -1
var _light_kind := -1
var _world_environment_resource: Environment
var _previous_environment: Environment
var _previous_environment_captured := false
var text_shadow: Label3D
var particle_material: ParticleProcessMaterial
var _particle_emitting := true
var _particle_settings_hash := -1
var fog_material: FogMaterial
var fog_shader_material: ShaderMaterial
var fog_shader_key := ""
var camera_shader_material: ShaderMaterial
var camera_shader_key := ""
var camera_canvas: CanvasLayer
var camera_overlay: ColorRect


func _exit_tree() -> void:
	if _watched_shader != null and _watched_shader.changed.is_connected(_source_shader_changed):
		_watched_shader.changed.disconnect(_source_shader_changed)
	_restore_environment()


func _ready() -> void:
	add_to_group("actor_shader_runtimes")
	match actor.type_id:
		&"basic_shape":
			content = _new_mesh_instance()
			material = _new_standard_material()
			_assign_material_override(material)
		&"basic_mesh": content = Node3D.new()
		&"text_3d":
			content = Label3D.new()
			content.layers = 1
			text_shadow = Label3D.new()
			text_shadow.layers = 1
			content.add_child(text_shadow)
		&"light_3d": content = _new_light(0)
		&"directional_light": content = _new_light(0)
		&"camera_3d":
			content = Camera3D.new()
			content.cull_mask = 1
			_add_camera_guide(content)
			camera_canvas = CanvasLayer.new()
			camera_canvas.layer = 100
			add_child(camera_canvas)
			camera_overlay = ColorRect.new()
			camera_overlay.color = Color.WHITE
			camera_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			camera_canvas.add_child(camera_overlay)
			camera_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			camera_overlay.hide()
		&"image_3d":
			var mesh := _new_mesh_instance()
			var quad := QuadMesh.new()
			quad.size = Vector2.ONE
			mesh.mesh = quad
			content = mesh
			material = _new_standard_material()
			_assign_material_override(material)
		&"world_environment":
			_world_environment_resource = Environment.new()
			content = Node3D.new()
		&"decal_3d": content = Decal.new()
		&"particles_3d":
			var particles := GPUParticles3D.new()
			particles.use_fixed_seed = true
			particles.seed = actor.id.hash() & 0x7fffffff
			particle_material = ParticleProcessMaterial.new()
			particles.process_material = particle_material
			var particle_mesh := SphereMesh.new()
			particle_mesh.radius = 0.08
			particle_mesh.height = 0.16
			particles.draw_pass_1 = particle_mesh
			content = particles
		&"fog_volume":
			var fog := FogVolume.new()
			fog_material = FogMaterial.new()
			fog.material = fog_material
			content = fog
		&"reflection_probe": content = ReflectionProbe.new()
	if content != null:
		add_child(content)
	parenting_anchor = Node3D.new()
	parenting_anchor.name = "ParentingAnchor"
	add_child(parenting_anchor)


func _add_camera_guide(camera: Camera3D) -> void:
	# Layer 2 is editor-only: render cameras see layer 1 exclusively.
	var lines := ImmediateMesh.new()
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.albedo_color = Color("70d7f2")
	paint.no_depth_test = true
	lines.surface_begin(Mesh.PRIMITIVE_LINES, paint)
	var back := [Vector3(-0.16, -0.11, 0.08), Vector3(0.16, -0.11, 0.08),
		Vector3(0.16, 0.11, 0.08), Vector3(-0.16, 0.11, 0.08)]
	var front := [Vector3(-0.42, -0.24, -0.65), Vector3(0.42, -0.24, -0.65),
		Vector3(0.42, 0.24, -0.65), Vector3(-0.42, 0.24, -0.65)]
	for index in 4:
		for ring in [back, front]:
			lines.surface_add_vertex(ring[index])
			lines.surface_add_vertex(ring[(index + 1) % 4])
		lines.surface_add_vertex(back[index])
		lines.surface_add_vertex(front[index])
	lines.surface_add_vertex(Vector3(0, 0.11, 0.08))
	lines.surface_add_vertex(Vector3(0, 0.26, 0.08))
	lines.surface_end()
	var guide := MeshInstance3D.new()
	guide.name = "EditorCameraGuide"
	guide.layers = 2
	guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	guide.mesh = lines
	camera.add_child(guide)


func parenting_node() -> Node:
	return parenting_anchor if parenting_anchor != null else self


func supports_remote_transform() -> bool:
	return content is Node3D


func remote_transform() -> Transform3D:
	return (content as Node3D).global_transform if content is Node3D else Transform3D.IDENTITY


func apply_remote_transform(source: Transform3D, use_position: bool, use_rotation: bool, use_scale: bool) -> void:
	if not content is Node3D:
		return
	var spatial := content as Node3D
	var result := spatial.global_transform
	if use_position:
		result.origin = source.origin
	var rotation := source.basis.get_rotation_quaternion() if use_rotation else result.basis.get_rotation_quaternion()
	var actor_scale := source.basis.get_scale() if use_scale else result.basis.get_scale()
	result.basis = Basis(rotation) * Basis.from_scale(actor_scale)
	spatial.global_transform = result
	parenting_anchor.global_transform = result


func set_active(value: bool) -> void:
	super.set_active(value)
	if content != null:
		if content is Node3D:
			(content as Node3D).visible = value
		if actor != null and actor.type_id == &"world_environment" and not value:
			var world := _runtime_world()
			if world != null and world.environment == _world_environment_resource:
				world.environment = _previous_environment
		if content is Camera3D and not value:
			content.clear_current()
			update_camera_overlay()
		if content is GPUParticles3D:
			var particles := content as GPUParticles3D
			if particles.emitting != (value and _particle_emitting):
				particles.emitting = value and _particle_emitting


func evaluate_transform(values: Dictionary) -> void:
	if actor.type_id == &"light_3d":
		_ensure_light(int(values.get(&"light_type", 0)))
	if content is Node3D:
		var spatial := content as Node3D
		var position: Vector3 = values.get(&"position", Vector3.ZERO)
		var rotation: Vector3 = values.get(&"rotation", Vector3.ZERO)
		var actor_scale: Vector3 = values.get(&"scale", Vector3.ONE)
		spatial.position = position
		spatial.rotation_degrees = rotation
		spatial.scale = actor_scale
		parenting_anchor.position = position
		parenting_anchor.rotation_degrees = rotation
		parenting_anchor.scale = actor_scale
		if values.has(&"model_basis_residual"):
			var exact: Basis=Basis.from_euler(spatial.rotation)*Basis.from_scale(actor_scale)*values[&"model_basis_residual"]
			spatial.basis=exact; parenting_anchor.basis=exact


func evaluate(_time: float, values: Dictionary) -> void:
	if content == null:
		return
	match actor.type_id:
		&"basic_shape":
			_update_shape(int(values.get(&"shape", 0)))
			_apply_shape_properties((content as MeshInstance3D).mesh, values)
			_apply_material_reference(values.get(&"material"), null, false)
		&"basic_mesh":
			_update_model(values.get(&"mesh_path", ""))
			_apply_material_reference(values.get(&"material"), null, true)
		&"text_3d":
			content.text = values[&"text"]
			var settings := ActorTextSettings.values(values.get(&"text_settings"))
			content.font = ActorTextSettings.font(settings)
			content.font_size = maxi(1, int(settings.get(&"font_size", values.get(&"font_size", 48))))
			content.modulate = settings.get(&"color", values.get(&"color", Color.WHITE))
			content.outline_size = maxi(0, int(settings.get(&"outline_size", 0)))
			content.outline_modulate = settings.get(&"outline_color", Color.BLACK)
			text_shadow.visible = settings.get(&"shadow", false)
			text_shadow.text = content.text
			text_shadow.font = content.font
			text_shadow.font_size = content.font_size
			text_shadow.outline_size = 0
			text_shadow.modulate = settings.get(&"shadow_color", Color(0, 0, 0, 0.65))
			var offset: Vector2 = settings.get(&"shadow_offset", Vector2(2, 2))
			text_shadow.position = Vector3(offset.x * content.pixel_size, -offset.y * content.pixel_size, -0.001)
		&"light_3d": _apply_light(values)
		&"directional_light": _apply_directional_light(values)
		&"camera_3d":
			content.fov = values[&"fov"]
			_apply_camera_shader(values.get(&"material"))
		&"image_3d":
			var image_source: Variant = values.get(&"image_path", "")
			loaded_image_path = _resource_identity(image_source)
			_apply_material_reference(values.get(&"material"), _texture_for_value(image_source), false)
		&"world_environment": _apply_environment(values.get(&"environment"))
		&"decal_3d": _apply_decal(values)
		&"particles_3d": _apply_particles(values)
		&"fog_volume": _apply_fog(values)
		&"reflection_probe": _apply_reflection_probe(values)


func _apply_decal(values: Dictionary) -> void:
	var decal := content as Decal
	decal.size = values.get(&"decal_size", Vector3(2, 2, 2))
	decal.texture_albedo = _texture_for_value(values.get(&"texture"))
	decal.modulate = values.get(&"modulate", Color.WHITE)
	decal.upper_fade = values.get(&"upper_fade", 0.3)
	decal.lower_fade = values.get(&"lower_fade", 0.3)
	decal.cull_mask = 1


func _apply_particles(values: Dictionary) -> void:
	var particles := content as GPUParticles3D
	_particle_emitting = values.get(&"emitting", true)
	if particles.emitting != (active and _particle_emitting):
		particles.emitting = active and _particle_emitting
	var settings_hash := [values.get(&"amount", 64), values.get(&"lifetime", 1.0),
		values.get(&"one_shot", false), values.get(&"explosiveness", 0.0),
		values.get(&"direction", Vector3.UP), values.get(&"spread", 45.0),
		values.get(&"velocity", 2.0), values.get(&"gravity", Vector3(0, -9.8, 0)),
		values.get(&"color", Color.WHITE), values.get(&"particle_size", 0.08)].hash()
	if settings_hash == _particle_settings_hash: return
	_particle_settings_hash = settings_hash
	particles.amount = maxi(1, int(values.get(&"amount", 64)))
	particles.lifetime = maxf(0.05, float(values.get(&"lifetime", 1.0)))
	particles.one_shot = values.get(&"one_shot", false)
	particles.explosiveness = values.get(&"explosiveness", 0.0)
	if particle_material != null:
		particle_material.direction = values.get(&"direction", Vector3.UP)
		particle_material.spread = values.get(&"spread", 45.0)
		var velocity := float(values.get(&"velocity", 2.0))
		particle_material.initial_velocity_min = velocity
		particle_material.initial_velocity_max = velocity
		particle_material.gravity = values.get(&"gravity", Vector3(0, -9.8, 0))
		particle_material.color = values.get(&"color", Color.WHITE)
	var mesh := particles.draw_pass_1 as SphereMesh
	if mesh != null:
		var radius := maxf(0.001, float(values.get(&"particle_size", 0.08)))
		mesh.radius = radius
		mesh.height = radius * 2.0


func _apply_fog(values: Dictionary) -> void:
	var fog := content as FogVolume
	fog.shape = int(values.get(&"shape", 3))
	fog.size = values.get(&"volume_size", Vector3(4, 2, 4))
	var reference := values.get(&"material") as ActorObjectReference if values.get(&"material") is ActorObjectReference else null
	var object := reference.resolve(_load_object_resource) if reference != null else null
	if object != null and object.type_id == &"fog_shader_material":
		var source: Variant = object.get_value(&"shader_path", "")
		var key := _shader_source_key(source)
		if fog_shader_material == null or key != fog_shader_key:
			fog_shader_key = key
			fog_shader_material = _runtime_shader_material(_shader_from_value(source), "fog")
		fog.material = fog_shader_material if fog_shader_material.shader != null else fog_material
		_apply_shader_uniforms(fog_shader_material, object)
	else:
		fog.material = fog_material
		fog_shader_material = null
		fog_shader_key = ""
	if fog_material != null:
		fog_material.density = values.get(&"density", 1.0)
		fog_material.albedo = values.get(&"albedo", Color.WHITE)
		var emission: Color = values.get(&"emission", Color.BLACK)
		fog_material.emission = emission * float(values.get(&"emission_energy", 1.0))
		fog_material.edge_fade = values.get(&"edge_fade", 0.1)


func _apply_camera_shader(value: Variant) -> void:
	var reference := value as ActorObjectReference if value is ActorObjectReference else null
	var object := reference.resolve(_load_object_resource) if reference != null else null
	if object == null or object.type_id != &"canvas_shader_material":
		camera_shader_material = null
		camera_shader_key = ""
		camera_overlay.material = null
		update_camera_overlay()
		return
	var source: Variant = object.get_value(&"shader_path", "")
	var key := _shader_source_key(source)
	if camera_shader_material == null or key != camera_shader_key:
		camera_shader_key = key
		camera_shader_material = _runtime_shader_material(_shader_from_value(source), "canvas_item", true)
	camera_overlay.material = camera_shader_material if camera_shader_material.shader != null else null
	_apply_shader_uniforms(camera_shader_material, object)
	update_camera_overlay()


func update_camera_overlay() -> void:
	if camera_overlay != null:
		camera_overlay.visible = active and content is Camera3D and (content as Camera3D).is_current() \
			and camera_shader_material != null and camera_shader_material.shader != null


func _shader_from_value(value: Variant) -> Shader:
	if value is Shader:
		return value
	if value is String and not str(value).is_empty():
		return ResourceLoader.load(_godot_resource_path(value), "", ResourceLoader.CACHE_MODE_IGNORE) as Shader
	return null


func _shader_source_key(value: Variant) -> String:
	if value is Shader:
		return str(value.get_instance_id()) + ":" + str(value.code.hash())
	if value is String and not str(value).is_empty():
		var path := _godot_resource_path(value)
		return path + ":" + FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing:" + path
	return "empty"


func _runtime_shader_material(source: Shader, kind: String, screen_input: bool = false) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	if source == null or RegEx.create_from_string("(?m)^\\s*shader_type\\s+" + kind + "\\s*;").search(source.code) == null:
		return result
	var code := source.code
	if screen_input:
		# A camera's CanvasItem material sees a full-screen ColorRect. Feed its
		# input COLOR and standard TEXTURE sampler from the already-rendered frame.
		var screen_name := "kiwi_camera_screen"
		while code.contains(screen_name): screen_name += "_"
		code = RegEx.create_from_string("\\bTEXTURE_PIXEL_SIZE\\b").sub(code, "SCREEN_PIXEL_SIZE", true)
		var texture_token := RegEx.create_from_string("\\bTEXTURE\\b")
		code = texture_token.sub(code, screen_name, true)
		var shader_declaration := RegEx.create_from_string("shader_type\\s+canvas_item\\s*;")
		var declaration := shader_declaration.search(code)
		if declaration != null:
			code = code.insert(declaration.get_end(),
				"\nuniform sampler2D %s : hint_screen_texture, filter_linear;\n" % screen_name)
		var fragment := RegEx.create_from_string("\\bvoid\\s+fragment\\s*\\(\\s*\\)\\s*\\{").search(code)
		if fragment != null:
			code = code.insert(fragment.get_end(), "\nCOLOR = texture(%s, SCREEN_UV);\n" % screen_name)
		else:
			code += "\nvoid fragment() { COLOR = texture(%s, SCREEN_UV); }\n" % screen_name
	var timed := ShaderTime.prepare(code)
	var runtime_shader := Shader.new()
	runtime_shader.code = timed.code
	result.shader = runtime_shader
	result.set_meta("kiwi_time_uniform", timed.uniform)
	return result


func _apply_shader_uniforms(target: ShaderMaterial, object: ActorObjectData) -> void:
	if target == null or target.shader == null:
		return
	var uniforms: Dictionary = object.get_value(&"uniforms", {})
	for info: Dictionary in target.shader.get_shader_uniform_list():
		var name := StringName(info.get("name", ""))
		if name.is_empty() or not uniforms.has(name): continue
		var uniform_value: Variant = uniforms[name]
		if int(info.get("type", TYPE_NIL)) == TYPE_OBJECT:
			uniform_value = _texture_for_value(uniform_value)
		target.set_shader_parameter(name, uniform_value)


func _apply_reflection_probe(values: Dictionary) -> void:
	var probe := content as ReflectionProbe
	probe.size = values.get(&"probe_size", Vector3(6, 4, 6))
	probe.origin_offset = values.get(&"origin_offset", Vector3.ZERO)
	probe.intensity = values.get(&"intensity", 1.0)
	probe.max_distance = values.get(&"max_distance", 0.0)
	probe.box_projection = values.get(&"box_projection", true)
	probe.interior = values.get(&"interior", false)
	probe.enable_shadows = values.get(&"shadows", false)
	probe.update_mode = int(values.get(&"update_mode", 0))
	probe.cull_mask = 1


func _new_mesh_instance() -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.layers = 1
	return mesh


func _new_standard_material() -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	result.cull_mode = BaseMaterial3D.CULL_BACK
	return result


func _update_shape(kind: int) -> void:
	if kind == _shape_kind:
		return
	_shape_kind = kind
	var mesh_instance := content as MeshInstance3D
	match kind:
		1: mesh_instance.mesh = SphereMesh.new()
		2: mesh_instance.mesh = CylinderMesh.new()
		3: mesh_instance.mesh = CapsuleMesh.new()
		4: mesh_instance.mesh = PlaneMesh.new()
		5: mesh_instance.mesh = PrismMesh.new()
		6: mesh_instance.mesh = QuadMesh.new()
		7: mesh_instance.mesh = TorusMesh.new()
		_: mesh_instance.mesh = BoxMesh.new()
	_apply_shape_properties(mesh_instance.mesh, actor.values)


func _apply_shape_properties(mesh: PrimitiveMesh, values: Dictionary) -> void:
	mesh.flip_faces = values.get(&"flip_faces", false)
	mesh.add_uv2 = values.get(&"add_uv2", false)
	mesh.uv2_padding = values.get(&"uv2_padding", 2.0)
	if mesh is BoxMesh:
		mesh.size = values.get(&"box_size", Vector3.ONE)
		mesh.subdivide_width = values.get(&"box_subdivide_width", 0)
		mesh.subdivide_height = values.get(&"box_subdivide_height", 0)
		mesh.subdivide_depth = values.get(&"box_subdivide_depth", 0)
	elif mesh is SphereMesh:
		mesh.radius = values.get(&"sphere_radius", 0.5)
		mesh.height = values.get(&"sphere_height", 1.0)
		mesh.radial_segments = values.get(&"sphere_radial_segments", 64)
		mesh.rings = values.get(&"sphere_rings", 32)
		mesh.is_hemisphere = values.get(&"sphere_hemisphere", false)
	elif mesh is CylinderMesh:
		mesh.top_radius = values.get(&"cylinder_top_radius", 0.5)
		mesh.bottom_radius = values.get(&"cylinder_bottom_radius", 0.5)
		mesh.height = values.get(&"cylinder_height", 2.0)
		mesh.radial_segments = values.get(&"cylinder_radial_segments", 64)
		mesh.rings = values.get(&"cylinder_rings", 4)
		mesh.cap_top = values.get(&"cylinder_cap_top", true)
		mesh.cap_bottom = values.get(&"cylinder_cap_bottom", true)
	elif mesh is CapsuleMesh:
		mesh.radius = values.get(&"capsule_radius", 0.5)
		mesh.height = values.get(&"capsule_height", 2.0)
		mesh.radial_segments = values.get(&"capsule_radial_segments", 64)
		mesh.rings = values.get(&"capsule_rings", 8)
	elif mesh is PlaneMesh or mesh is QuadMesh:
		mesh.size = values.get(&"plane_size", Vector2.ONE)
		mesh.subdivide_width = values.get(&"plane_subdivide_width", 0)
		mesh.subdivide_depth = values.get(&"plane_subdivide_depth", 0)
		mesh.orientation = values.get(&"plane_orientation", 1)
	elif mesh is PrismMesh:
		mesh.size = values.get(&"prism_size", Vector3.ONE)
		mesh.left_to_right = values.get(&"prism_left_to_right", 0.5)
		mesh.subdivide_width = values.get(&"prism_subdivide_width", 0)
		mesh.subdivide_height = values.get(&"prism_subdivide_height", 0)
		mesh.subdivide_depth = values.get(&"prism_subdivide_depth", 0)
	elif mesh is TorusMesh:
		mesh.inner_radius = values.get(&"torus_inner_radius", 0.5)
		mesh.outer_radius = values.get(&"torus_outer_radius", 1.0)
		mesh.rings = values.get(&"torus_rings", 64)
		mesh.ring_segments = values.get(&"torus_ring_segments", 32)


func _update_model(source: Variant) -> void:
	var component_id := str(actor.values.get(&"model_component_id",""))
	var key := _resource_identity(source)+":"+component_id
	if key == loaded_model_path:
		_bind_model_skin()
		return
	loaded_model_path = key
	for child in content.get_children():
		child.free()
	var resource: Resource = source if source is Resource else null
	var path := str(source)
	var load_path := _godot_resource_path(path)
	if resource == null and not load_path.is_empty() and ResourceLoader.exists(load_path):
		resource = ResourceLoader.load(load_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	var instance: Node3D
	var item: KiwiModelComponent=resource.component(component_id) if resource is KiwiModelDocument else (actor.values.get(&"model_component_data") as KiwiModelComponent if str(source)==str(actor.values.get(&"model_component_source","")) else null)
	if item!=null and resource is KiwiModelDocument and actor.values.has(&"model_rig_bind_signature"):
		var source_rig: KiwiModelComponent=resource.component(item.skeleton_id)
		if source_rig==null or KiwiRigMath.bind_signature(source_rig.bones)!=int(actor.values[&"model_rig_bind_signature"]): item=actor.values.get(&"model_component_data") as KiwiModelComponent
	if item!=null or (resource is KiwiModelDocument and not component_id.is_empty() and str(source)==str(actor.values.get(&"model_component_source",""))):
		if item!=null and item.mesh!=null:
			var visual := _new_mesh_instance(); visual.mesh=item.skin_mesh if item.skin_mesh!=null else (item.binding.source_mesh if item.binding!=null else KiwiModelModifiers.evaluate(item).render_mesh(item.surface_materials))
			visual.skin=item.skin
			for i in mini(item.surface_materials.size(),visual.mesh.get_surface_count()): visual.set_surface_override_material(i,item.surface_materials[i])
			visual.visible=not bool(actor.values.get(&"model_component_hidden",false)); instance=visual
	elif resource is PackedScene:
		instance = resource.instantiate() as Node3D
	elif resource is KiwiModelDocument:
		instance = resource.instantiate_model()
	elif resource is Mesh:
		var mesh_instance := _new_mesh_instance()
		mesh_instance.mesh = resource
		instance = mesh_instance
	elif not path.is_empty() and path.get_extension().to_lower() in ["glb", "gltf"]:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		if document.append_from_file(path, state) == OK:
			instance = document.generate_scene(state)
	if instance != null:
		content.add_child(instance)
		_bind_model_skin()


func _bind_model_skin() -> void:
	if actor.values.has(&"model_rigid_bone"): return
	var id := str(actor.values.get(&"model_skeleton_actor",""))
	if id.is_empty() or not is_inside_tree(): return
	for rig in get_tree().get_nodes_in_group("actor_skeleton_rigs"):
		if rig.actor.id!=id: continue
		for node in content.get_children():
			if node is MeshInstance3D:
				node.skeleton=node.get_path_to(rig.skeleton)
				if bool(actor.values.get(&"model_skin_in_rig_space",false)): node.global_transform=rig.skeleton.global_transform
		return

func apply_rig_attachment() -> void:
	if not actor.values.has(&"model_rigid_bone"):
		# Mesh actors can be evaluated before their sibling rig. Resolve its final
		# transform again after all actors, without waiting for the next frame.
		if bool(actor.values.get(&"model_skin_in_rig_space",false)): _bind_model_skin()
		return
	for rig in get_tree().get_nodes_in_group("actor_skeleton_rigs"):
		if rig.actor.id!=str(actor.values.get(&"model_skeleton_actor","")): continue
		var index := int(actor.values[&"model_rigid_bone"])
		if index<0 or index>=rig.skeleton.get_bone_count(): return
		var delta: Transform3D=rig.skeleton.global_transform*rig.skeleton.get_bone_global_pose(index)*actor.values[&"model_rigid_rest_inverse"]*rig.skeleton.global_transform.affine_inverse()
		var moved: Transform3D=delta*(content as Node3D).global_transform
		(content as Node3D).global_transform=moved; parenting_anchor.global_transform=moved; return


func refresh_saved_model(path: String) -> void:
	if actor==null or actor.type_id!=&"basic_mesh": return
	var source := str(actor.values.get(&"mesh_path",""))
	if ProjectSettings.globalize_path(source).replace("\\","/").simplify_path()==ProjectSettings.globalize_path(path).replace("\\","/").simplify_path():
		loaded_model_path=""
		_update_model(source)


func _new_light(kind: int) -> Light3D:
	var light: Light3D
	match kind:
		1: light = OmniLight3D.new()
		2: light = SpotLight3D.new()
		_: light = DirectionalLight3D.new()
	light.light_cull_mask = 1
	return light


func _ensure_light(kind: int) -> void:
	if kind == _light_kind and content is Light3D:
		return
	_light_kind = kind
	var old := content
	content = _new_light(kind)
	add_child(content)
	if old != null:
		old.queue_free()


func _apply_light(values: Dictionary) -> void:
	var light := content as Light3D
	light.light_color = values.get(&"color", Color.WHITE)
	light.light_energy = values.get(&"energy", 1.0)
	light.shadow_enabled = values.get(&"shadows", true)
	if light is OmniLight3D:
		light.omni_range = values.get(&"range", 5.0)
	elif light is SpotLight3D:
		light.spot_range = values.get(&"range", 5.0)
		light.spot_angle = values.get(&"spot_angle", 45.0)


func _apply_directional_light(values: Dictionary) -> void:
	var light := content as DirectionalLight3D
	light.light_color = values.get(&"color", Color.WHITE)
	light.light_energy = values.get(&"energy", 1.0)
	light.light_indirect_energy = values.get(&"indirect_energy", 1.0)
	light.light_volumetric_fog_energy = values.get(&"volumetric_fog_energy", 1.0)
	light.light_angular_distance = values.get(&"angular_distance", 0.5)
	light.light_negative = values.get(&"negative", false)
	light.light_specular = values.get(&"specular", 1.0)
	light.shadow_enabled = values.get(&"shadows", true)
	light.shadow_bias = values.get(&"shadow_bias", 0.1)
	light.shadow_normal_bias = values.get(&"shadow_normal_bias", 2.0)
	light.shadow_opacity = values.get(&"shadow_opacity", 1.0)
	light.shadow_blur = values.get(&"shadow_blur", 1.0)
	light.directional_shadow_mode = values.get(&"shadow_mode", 2)
	light.directional_shadow_blend_splits = values.get(&"blend_splits", false)
	light.directional_shadow_max_distance = values.get(&"shadow_max_distance", 100.0)
	light.directional_shadow_fade_start = values.get(&"shadow_fade_start", 0.8)
	light.sky_mode = values.get(&"sky_mode", 0)


func _apply_environment(value: Variant) -> void:
	var reference := value as ActorObjectReference
	var object := reference.resolve(_load_object_resource) if reference != null else null
	var world := _runtime_world()
	if world == null:
		return
	if object == null or object.type_id != &"environment":
		_restore_environment()
		return
	var environment := _world_environment_resource
	if not _previous_environment_captured:
		_previous_environment = world.environment
		_previous_environment_captured = true
	world.environment = environment
	_configure_environment(environment, object)


func _configure_environment(environment: Environment, object: ActorObjectData) -> void:
	_apply_environment_background(environment, object)
	var environment_properties := {
		&"sky_rotation": "sky_rotation", &"ambient_source": "ambient_light_source", &"ambient_color": "ambient_light_color",
		&"ambient_sky_contribution": "ambient_light_sky_contribution", &"ambient_energy": "ambient_light_energy",
		&"reflected_source": "reflected_light_source", &"tone_mapper": "tonemap_mode", &"exposure": "tonemap_exposure", &"white_point": "tonemap_white",
		&"ssr_enabled": "ssr_enabled", &"ssr_max_steps": "ssr_max_steps", &"ssr_fade_in": "ssr_fade_in", &"ssr_fade_out": "ssr_fade_out", &"ssr_depth_tolerance": "ssr_depth_tolerance",
		&"ssil_enabled": "ssil_enabled", &"ssil_radius": "ssil_radius", &"ssil_intensity": "ssil_intensity", &"ssil_sharpness": "ssil_sharpness", &"ssil_normal_rejection": "ssil_normal_rejection",
		&"sdfgi_enabled": "sdfgi_enabled", &"sdfgi_use_occlusion": "sdfgi_use_occlusion", &"sdfgi_read_sky_light": "sdfgi_read_sky_light", &"sdfgi_bounce_feedback": "sdfgi_bounce_feedback", &"sdfgi_cascades": "sdfgi_cascades", &"sdfgi_min_cell_size": "sdfgi_min_cell_size", &"sdfgi_energy": "sdfgi_energy",
		&"glow_enabled": "glow_enabled", &"glow_intensity": "glow_intensity", &"glow_strength": "glow_strength", &"glow_mix": "glow_mix", &"glow_bloom": "glow_bloom", &"glow_blend_mode": "glow_blend_mode", &"glow_hdr_threshold": "glow_hdr_threshold",
		&"fog_enabled": "fog_enabled", &"fog_mode": "fog_mode", &"fog_color": "fog_light_color", &"fog_light_energy": "fog_light_energy", &"fog_sun_scatter": "fog_sun_scatter", &"fog_density": "fog_density", &"fog_sky_affect": "fog_sky_affect", &"fog_height": "fog_height", &"fog_height_density": "fog_height_density",
		&"volumetric_fog_enabled": "volumetric_fog_enabled", &"volumetric_fog_density": "volumetric_fog_density", &"volumetric_fog_albedo": "volumetric_fog_albedo", &"volumetric_fog_emission": "volumetric_fog_emission", &"volumetric_fog_emission_energy": "volumetric_fog_emission_energy", &"volumetric_fog_gi_inject": "volumetric_fog_gi_inject", &"volumetric_fog_anisotropy": "volumetric_fog_anisotropy", &"volumetric_fog_length": "volumetric_fog_length", &"volumetric_fog_detail_spread": "volumetric_fog_detail_spread", &"volumetric_fog_sky_affect": "volumetric_fog_sky_affect",
		&"adjustment_enabled": "adjustment_enabled", &"adjustment_brightness": "adjustment_brightness", &"adjustment_contrast": "adjustment_contrast", &"adjustment_saturation": "adjustment_saturation"
	}
	for key: StringName in environment_properties:
		if object.values.has(key):
			environment.set(environment_properties[key], object.values[key])


func _apply_environment_background(environment: Environment, object: ActorObjectData) -> void:
	var mode := int(object.get_value(&"background_mode", 0))
	environment.background_energy_multiplier = object.get_value(&"background_energy", 1.0)
	if mode == 0:
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = object.get_value(&"background_color", Color("20252d"))
		environment.sky = null
		return
	var sky := Sky.new()
	if mode == 1:
		var panorama := PanoramaSkyMaterial.new()
		panorama.panorama = _texture_for_value(object.get_value(&"background_image", ""))
		sky.sky_material = panorama
	elif mode == 2:
		var procedural := ProceduralSkyMaterial.new()
		procedural.sky_top_color = object.get_value(&"sky_top_color", Color("385a8c"))
		procedural.sky_horizon_color = object.get_value(&"sky_horizon_color", Color("d6eafa"))
		procedural.sky_curve = object.get_value(&"sky_curve", 0.15)
		procedural.sky_energy_multiplier = object.get_value(&"sky_energy", 1.0)
		procedural.ground_bottom_color = object.get_value(&"ground_bottom_color", Color("282f3d"))
		procedural.ground_horizon_color = object.get_value(&"ground_horizon_color", Color("d6eafa"))
		procedural.ground_curve = object.get_value(&"ground_curve", 0.02)
		procedural.ground_energy_multiplier = object.get_value(&"ground_energy", 1.0)
		procedural.sun_angle_max = object.get_value(&"sun_angle_max", 30.0)
		procedural.sun_curve = object.get_value(&"sun_curve", 0.15)
		procedural.use_debanding = object.get_value(&"sky_debanding", true)
		sky.sky_material = procedural
	else:
		var reference := object.get_value(&"sky_material") as ActorObjectReference
		var material_object := reference.resolve(_load_object_resource) if reference != null else null
		if material_object != null and material_object.type_id == &"shader_material":
			sky.sky_material = _create_shader_material(material_object)
			if not str(sky.sky_material.get_meta("kiwi_time_uniform", "")).is_empty():
				sky.process_mode = Sky.PROCESS_MODE_REALTIME
	environment.sky = sky
	environment.background_mode = Environment.BG_SKY


func _restore_environment() -> void:
	if actor == null or actor.type_id != &"world_environment" or not _previous_environment_captured:
		return
	var world := _runtime_world(false)
	if world != null and world.environment == _world_environment_resource:
		world.environment = _previous_environment
	_previous_environment_captured = false


func _apply_material_reference(value: Variant, albedo_texture: Texture2D, preserve_null: bool) -> void:
	var reference := value as ActorObjectReference
	var object := reference.resolve(_load_object_resource) if reference != null else null
	if object != null and object.type_id == &"natural_material":
		_apply_natural_material(object)
		return
	if object != null and object.type_id == &"shader_material":
		_apply_shader_material(object)
		return
	if object == null and preserve_null:
		_assign_material_override(null)
		return
	_ensure_standard_material()
	_reset_standard_material(albedo_texture)
	if object != null and object.type_id == &"material":
		_apply_standard_material(object)


func _apply_natural_material(object: ActorObjectData) -> void:
	# This adapter owns no procedural code: painting and scene surfaces evaluate
	# the same engine definition. Preserve the GPU material between frame updates.
	var stored: Dictionary = object.get_value(&"material_settings", {})
	if natural_material == null:
		natural_material = NaturalEngine.create_spatial_material(stored)
		_natural_settings = stored.duplicate(true)
	elif stored != _natural_settings:
		NaturalEngine.configure_spatial(natural_material, stored)
		_natural_settings = stored.duplicate(true)
	_assign_material_override(natural_material)


func _ensure_standard_material() -> void:
	if material == null:
		material = _new_standard_material()
	_assign_material_override(material)


func _reset_standard_material(albedo_texture: Texture2D) -> void:
	var image_surface := actor != null and actor.type_id == &"image_3d"
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if image_surface else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.albedo_texture = albedo_texture
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.roughness_texture = null
	material.metallic = 0.0
	material.metallic_texture = null
	material.metallic_specular = 0.5
	material.emission_enabled = false
	material.emission = Color.BLACK
	material.emission_texture = null
	material.normal_enabled = false
	material.normal_scale = 1.0
	material.uv1_scale = Vector3.ONE
	material.uv1_offset = Vector3.ZERO
	material.uv1_triplanar = false
	material.uv1_world_triplanar = false
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if image_surface else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if image_surface else BaseMaterial3D.CULL_BACK
	material.no_depth_test = false


func _apply_standard_material(object: ActorObjectData) -> void:
	var tint: Color = object.get_value(&"tint", Color.WHITE)
	tint.a *= object.get_value(&"opacity", 1.0)
	material.albedo_color = tint
	var albedo_map := _texture_for_value(object.get_value(&"albedo_map", null))
	if albedo_map != null:
		material.albedo_texture = albedo_map
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if tint.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.roughness = object.get_value(&"roughness", 1.0)
	material.roughness_texture = _texture_for_value(object.get_value(&"roughness_map", ""))
	material.metallic = object.get_value(&"metallic", 0.0)
	material.metallic_texture = _texture_for_value(object.get_value(&"metallic_map", ""))
	material.metallic_specular = object.get_value(&"specular", 0.5)
	material.set_meta("specular_texture", _texture_for_value(object.get_value(&"specular_map", "")))
	var normal_texture := _texture_for_value(object.get_value(&"normal_map", ""))
	material.normal_texture = normal_texture
	material.normal_enabled = normal_texture != null
	material.normal_scale = object.get_value(&"normal_strength", 1.0)
	var uv_scale: Vector2 = object.get_value(&"uv_scale", Vector2.ONE)
	var uv_offset: Vector2 = object.get_value(&"uv_offset", Vector2.ZERO)
	material.uv1_scale = Vector3(uv_scale.x, uv_scale.y, 1.0)
	material.uv1_offset = Vector3(uv_offset.x, uv_offset.y, 0.0)
	material.uv1_triplanar = object.get_value(&"uv_triplanar", false)
	material.uv1_world_triplanar = object.get_value(&"uv_world_triplanar", false)
	material.emission_enabled = object.get_value(&"emission_enabled", false)
	material.emission = object.get_value(&"emission_color", Color.BLACK)
	material.emission_texture = _texture_for_value(object.get_value(&"emission_map", ""))
	material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY if int(object.get_value(&"emission_operator", 0)) == 1 else BaseMaterial3D.EMISSION_OP_ADD
	material.emission_energy_multiplier = object.get_value(&"emission_energy", 1.0)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if object.get_value(&"unshaded", false) else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	material.cull_mode = BaseMaterial3D.CULL_DISABLED if object.get_value(&"double_sided", true) else BaseMaterial3D.CULL_BACK
	material.no_depth_test = object.get_value(&"no_depth_test", false)


func _assign_material_override(value: Material) -> void:
	if content is MeshInstance3D:
		(content as MeshInstance3D).material_override = value
	else:
		for mesh in content.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_override = value


func _apply_shader_material(object: ActorObjectData) -> void:
	var shader_source: Variant = object.get_value(&"shader_path", "")
	var shader_path := _resource_identity(shader_source)
	var shader_key := shader_path
	if shader_source is Shader:
		shader_key += ":" + str(shader_source.code.hash())
	elif shader_source is String and FileAccess.file_exists(shader_path):
		shader_key += ":" + FileAccess.get_sha256(shader_path)
	var source_shader: Shader = shader_source if shader_source is Shader else null
	if shader_material == null or shader_key != loaded_shader_path:
		if shader_source is String and not shader_path.is_empty():
			source_shader = ResourceLoader.load(shader_path, "", ResourceLoader.CACHE_MODE_IGNORE) as Shader
		_watch_shader(source_shader)
		loaded_shader_path = shader_key
		shader_material = ShaderMaterial.new()
		if source_shader != null:
			var runtime_shader := Shader.new()
			var timed: Dictionary = ShaderTime.prepare(source_shader.code)
			runtime_shader.code = timed.code
			shader_material.shader = runtime_shader
			shader_material.set_meta("kiwi_time_uniform", timed.uniform)
	_assign_material_override(shader_material)
	if shader_material.shader == null:
		return
	var uniforms: Dictionary = object.get_value(&"uniforms", {})
	for info: Dictionary in shader_material.shader.get_shader_uniform_list():
		var uniform_name := StringName(info.get("name", ""))
		if uniform_name.is_empty() or not uniforms.has(uniform_name):
			continue
		var uniform_value: Variant = uniforms[uniform_name]
		if int(info.get("type", TYPE_NIL)) == TYPE_OBJECT:
			uniform_value = _texture_for_value(uniform_value)
		shader_material.set_shader_parameter(uniform_name, uniform_value)


func _create_shader_material(object: ActorObjectData) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	var shader_source: Variant = object.get_value(&"shader_path", "")
	var source_shader: Shader = shader_source if shader_source is Shader else null
	if source_shader == null and shader_source is String and not str(shader_source).is_empty():
		source_shader = ResourceLoader.load(_godot_resource_path(str(shader_source)), "",
			ResourceLoader.CACHE_MODE_IGNORE) as Shader
	if source_shader == null:
		return result
	var runtime_shader := Shader.new()
	var timed: Dictionary = ShaderTime.prepare(source_shader.code)
	runtime_shader.code = timed.code
	result.shader = runtime_shader
	result.set_meta("kiwi_time_uniform", timed.uniform)
	var uniforms: Dictionary = object.get_value(&"uniforms", {})
	for info: Dictionary in runtime_shader.get_shader_uniform_list():
		var uniform_name := StringName(info.get("name", ""))
		if uniform_name.is_empty() or not uniforms.has(uniform_name):
			continue
		var uniform_value: Variant = uniforms[uniform_name]
		if int(info.get("type", TYPE_NIL)) == TYPE_OBJECT:
			uniform_value = _texture_for_value(uniform_value)
		result.set_shader_parameter(uniform_name, uniform_value)
	return result


func set_timeline_time(timeline_time: float) -> void:
	if shader_material != null and shader_material.shader != null:
		var uniform_name := str(shader_material.get_meta("kiwi_time_uniform", ""))
		if not uniform_name.is_empty():
			shader_material.set_shader_parameter(uniform_name, timeline_time)
	for special_material in [camera_shader_material, fog_shader_material]:
		if special_material == null or special_material.shader == null: continue
		var uniform_name := str(special_material.get_meta("kiwi_time_uniform", ""))
		if not uniform_name.is_empty():
			special_material.set_shader_parameter(uniform_name, timeline_time)
	if _world_environment_resource != null and _world_environment_resource.sky != null:
		var sky_material := _world_environment_resource.sky.sky_material as ShaderMaterial
		if sky_material != null:
			var uniform_name := str(sky_material.get_meta("kiwi_time_uniform", ""))
			if not uniform_name.is_empty():
				sky_material.set_shader_parameter(uniform_name, timeline_time)


func _watch_shader(source: Shader) -> void:
	if source == _watched_shader:
		return
	if _watched_shader != null and _watched_shader.changed.is_connected(_source_shader_changed):
		_watched_shader.changed.disconnect(_source_shader_changed)
	_watched_shader = source
	if _watched_shader != null and not _watched_shader.changed.is_connected(_source_shader_changed):
		_watched_shader.changed.connect(_source_shader_changed)


func _source_shader_changed() -> void:
	loaded_shader_path = ""
	call_deferred("_reload_actor_shader")


func _current_material_object() -> ActorObjectData:
	if actor == null or actor.type_id not in [&"image_3d", &"basic_shape", &"basic_mesh"]:
		return null
	var reference := actor.get_value(&"material") as ActorObjectReference
	return reference.resolve(_load_object_resource) if reference != null else null


func _reload_actor_shader() -> void:
	if not is_inside_tree():
		return
	var object := _current_material_object()
	if object != null and object.type_id == &"shader_material":
		_apply_shader_material(object)


func refresh_saved_shader(_source: Variant) -> void:
	var object := _current_material_object()
	if object != null and object.type_id == &"shader_material":
		loaded_shader_path = ""
		_apply_shader_material(object)
	elif actor != null and actor.type_id == &"camera_3d":
		camera_shader_key = ""
		_apply_camera_shader(actor.get_value(&"material"))
	elif actor != null and actor.type_id == &"fog_volume":
		fog_shader_key = ""
		_apply_fog(ActorAnimation.sampled_values(actor, actor.animation_time))


func refresh_saved_image(source: Variant) -> void:
	if source is String:
		texture_cache.clear()


func _load_external_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


func _texture_for_path(path: String) -> Texture2D:
	if path.is_empty(): return null
	if texture_cache.has(path): return texture_cache[path]
	var texture := _load_external_texture(path)
	texture_cache[path] = texture
	return texture


func _texture_for_value(value: Variant) -> Texture2D:
	if value is ActorObjectReference:
		var object: ActorObjectData = value.resolve(_load_object_resource)
		if object == null:
			return null
		if object.type_id == &"noise_image":
			var cache_key := var_to_str(object.values)
			if not noise_texture_cache.has(cache_key):
				noise_texture_cache.clear()
				noise_texture_cache[cache_key] = ActorImageGenerator.texture_for_object(object)
			return noise_texture_cache[cache_key]
		return ActorImageGenerator.texture_for_object(object)
	if value is ActorObjectData:
		return ActorImageGenerator.texture_for_object(value)
	if value is Texture2D: return value
	if value is Image: return ImageTexture.create_from_image(value)
	if value is String and str(value).get_extension().to_lower() in ["tres", "res"]:
		var loaded := ResourceLoader.load(_godot_resource_path(value))
		if loaded is ActorObjectData: return ActorImageGenerator.texture_for_object(loaded)
		if loaded is Texture2D: return loaded
	return _texture_for_path(str(value))


func _resource_identity(value: Variant) -> String:
	if value is Resource: return "embedded:" + str(value.get_instance_id())
	return str(value)


func _load_object_resource(path: String) -> ActorObjectData:
	if path.is_empty() or not FileAccess.file_exists(path): return null
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ActorObjectData


func _godot_resource_path(path: String) -> String:
	if path.is_empty() or path.begins_with("res://") or path.begins_with("user://"):
		return path
	var project_root := ProjectSettings.globalize_path("res://").replace("\\", "/").rstrip("/")
	var normalized := path.replace("\\", "/")
	if normalized.begins_with(project_root + "/"):
		return "res://" + normalized.substr(project_root.length() + 1)
	return path


func _runtime_world(create_if_missing: bool = true) -> World3D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	if viewport.world_3d == null and create_if_missing:
		viewport.world_3d = World3D.new()
	return viewport.world_3d
