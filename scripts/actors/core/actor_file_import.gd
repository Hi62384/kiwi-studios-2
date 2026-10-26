class_name ActorFileImport
extends RefCounted
## File-to-actor mapping is shared by timeline drag validation and creation.

static func type_for_path(path: String) -> StringName:
	if not ActorProjectFilePicker.is_allowed_path(ActorProjectFilePicker.root_directory(), path, PackedStringArray()): return &""
	var extension := path.get_extension().to_lower()
	if extension in ActorVideo.EXTENSIONS: return &"video"
	if extension in ["mp3", "wav", "ogg", "flac"]: return &"audio"
	if extension in ["glb", "gltf", "fbx", "obj", "dae", "blend", "mesh"]: return &"basic_mesh"
	if extension in ["png", "jpg", "jpeg", "webp", "bmp", "svg", "tga", "exr", "hdr"]: return &"image_3d"
	if extension in ["tres", "res"]:
		var resource := ResourceLoader.load(path)
		if resource is ActorSceneData: return &"scene_instance"
		if resource is KiwiModelDocument: return &"basic_mesh"
		if resource is KiwiTransformationImage2D: return &"transform_image_2d"
		if resource is ActorObjectData:
			if resource.type_id == &"text_settings": return &"text_3d"
			if resource.type_id == &"environment": return &"world_environment"
			if resource.type_id in [&"image", &"noise_image"]: return &"image_3d"
		if resource is Environment: return &"world_environment"
		if resource is Mesh or resource is PackedScene: return &"basic_mesh"
		if resource is Texture2D: return &"image_3d"
		if resource is AudioStream: return &"audio"
	return &""


static func scene_duration(scene: ActorSceneData) -> float:
	if scene == null or scene.clips.is_empty(): return 5.0
	var first := INF
	var last := -INF
	for clip in scene.clips:
		first = minf(first, clip.start_time)
		last = maxf(last, clip.start_time + clip.duration)
	return maxf(ActorTimeline.MIN_DURATION, last - first)

static func values_for_path(path: String, registry: ActorRegistry) -> Dictionary:
	var type := type_for_path(path)
	var extension := path.get_extension().to_lower()
	var resource: Resource = ResourceLoader.load(path) if extension in ["tres", "res"] else null
	match type:
		&"transform_image_2d": return {&"transformation": path}
		&"text_3d": return {&"text_settings": ActorObjectReference.from_asset(path, &"text_settings")}
		&"video": return {&"video": path}
		&"audio": return {&"audio": resource if resource is AudioStream else path}
		&"basic_mesh": return {&"mesh_path": path}
		&"image_3d":
			if resource is ActorObjectData:
				return {&"image_path": ActorObjectReference.from_asset(path, resource.type_id)}
			var image := registry.get_object_definition(&"image").create_object()
			image.set_value(&"source", resource if resource is Texture2D else path)
			return {&"image_path": ActorObjectReference.from_object(image)}
		&"world_environment":
			if resource is ActorObjectData:
				return {&"environment": ActorObjectReference.from_asset(path, &"environment")}
			if resource is Environment:
				return {&"environment": ActorObjectReference.from_object(environment_from_native(resource, registry))}
	return {}

static func environment_from_native(native: Environment, registry: ActorRegistry) -> ActorObjectData:
	var object := registry.get_object_definition(&"environment").create_object()
	var aliases := {"ambient_source": "ambient_light_source", "ambient_color": "ambient_light_color",
		"ambient_energy": "ambient_light_energy", "ambient_sky_contribution": "ambient_light_sky_contribution",
		"reflected_source": "reflected_light_source", "tone_mapper": "tonemap_mode", "exposure": "tonemap_exposure",
		"white_point": "tonemap_white", "fog_color": "fog_light_color", "background_energy": "background_energy_multiplier"}
	var names: Dictionary = {}
	for property in native.get_property_list(): names[property.name] = true
	for key in object.values:
		var name := str(aliases.get(str(key), str(key)))
		if key != &"background_mode" and names.has(name): object.values[key] = native.get(name)
	object.values[&"background_mode"] = 0
	if native.background_mode != Environment.BG_SKY or native.sky == null: return object
	var material := native.sky.sky_material
	if material is PanoramaSkyMaterial:
		object.values[&"background_mode"] = 1
		object.values[&"background_image"] = material.panorama
	elif material is ProceduralSkyMaterial:
		object.values[&"background_mode"] = 2
		for key in [&"sky_top_color", &"sky_horizon_color", &"sky_curve", &"ground_bottom_color", &"ground_horizon_color", &"ground_curve", &"sun_angle_max", &"sun_curve"]:
			object.values[key] = material.get(key)
		object.values[&"sky_energy"] = material.sky_energy_multiplier
		object.values[&"ground_energy"] = material.ground_energy_multiplier
		object.values[&"sky_debanding"] = material.use_debanding
	elif material is ShaderMaterial:
		object.values[&"background_mode"] = 3
		var shader_material := registry.get_object_definition(&"shader_material").create_object()
		shader_material.values[&"shader"] = material.shader
		var uniforms: Dictionary = {}
		if material.shader != null:
			for uniform in material.shader.get_shader_uniform_list(): uniforms[uniform.name] = material.get_shader_parameter(uniform.name)
		shader_material.values[&"uniforms"] = uniforms
		object.values[&"sky_material"] = ActorObjectReference.from_object(shader_material)
	return object
