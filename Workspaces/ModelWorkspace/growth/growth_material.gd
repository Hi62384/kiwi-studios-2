class_name KiwiGrowthMaterial
extends Resource
## Appearance is independent of roots, guides, and simulation state.
@export var title: String="Growth material"
@export var asset_id: String=ActorData.new_id()
@export var linked_source: String=""
@export_enum("Realistic","Stylized","Custom") var mode: int=0
@export var custom: Material
@export var custom_asset: ActorObjectData
@export var root_color:=Color(.08,.025,.01)
@export var tip_color:=Color(.32,.14,.045)
@export var highlight_color:=Color(.9,.8,.65)
@export var roughness: float=.5
@export var specular: float=.55
@export var secondary_highlight: float=.2
@export var highlight_shift: float=.15
@export var backlight: float=.15
@export var opacity: float=1.0
@export_enum("Cutout / automatic translucent hash","Alpha hash","Alpha to coverage (MSAA)") var coverage: int=0
@export var emission:=Color.BLACK
@export var variation: float=.12
@export var bands: int=3
@export var edge_softness: float=.08
@export var outline: float=0.0
@export var outline_color:=Color(.015,.01,.02)
@export var shaft_color:=Color(.6,.42,.22)
@export var feather_detail: float=.2
@export var iridescence: float=0.0
@export_enum("None","Bands","Spots","Edges","Tips","Speckles") var feather_pattern: int=0
@export var feather_pattern_color:=Color(.08,.04,.015)
@export var feather_pattern_scale: float=5.
@export var feather_pattern_width: float=.2
@export var left_vane_color:=Color.WHITE
@export var right_vane_color:=Color.WHITE
@export var shaft_roughness: float=.65
@export_enum("None","Stripes","Spots","Speckles","Mottle","Patches") var pattern: int=0
@export var pattern_color:=Color(.015,.01,.005)
@export var pattern_scale: float=4.0
@export var pattern_rotation: float=0.0
@export var pattern_mix: float=.7
@export var pattern_seed: float=31.0
@export var albedo_texture: Texture2D
@export var roughness_texture: Texture2D
@export var normal_texture: Texture2D
@export var alpha_texture: Texture2D
@export var texture_scale:=Vector2.ONE
@export var texture_offset:=Vector2.ZERO
@export var texture_rotation: float=0.0
@export var gradient: Gradient
@export var texture_sources: Dictionary={}
var runtime: ShaderMaterial
var runtime_key: int=0
var texture_stamps: Dictionary={}
var custom_runtime: Material
var custom_key: int=0
var custom_asset_key: int=0
static var shader: Shader
static var variants: Dictionary={}
static var source_versions: Dictionary={}
const PRESETS:=["Black hair","Warm hair","Pale fur","Striped coat","Flight feathers","Iridescent feathers","Stylized ink"]
static func preset(name: String) -> KiwiGrowthMaterial:
	var result:=KiwiGrowthMaterial.new(); result.title=name
	match name:
		"Black hair": result.root_color=Color(.012,.009,.008); result.tip_color=Color(.055,.03,.02); result.roughness=.4; result.specular=.35
		"Warm hair": result.root_color=Color(.08,.025,.01); result.tip_color=Color(.32,.12,.035); result.roughness=.45
		"Pale fur": result.root_color=Color(.28,.25,.22); result.tip_color=Color(.75,.72,.65); result.roughness=.8
		"Striped coat": result.root_color=Color(.3,.18,.065); result.tip_color=Color(.65,.42,.15); result.pattern=1; result.pattern_color=Color(.025,.02,.01); result.pattern_scale=3.; result.roughness=.7
		"Flight feathers": result.root_color=Color(.42,.23,.08); result.tip_color=Color(.12,.055,.02); result.feather_pattern=1; result.feather_pattern_width=.3; result.specular=.2
		"Iridescent feathers": result.root_color=Color(.015,.07,.08); result.tip_color=Color(.12,.2,.25); result.iridescence=.8; result.roughness=.28
		"Stylized ink": result.mode=1; result.root_color=Color(.025,.03,.06); result.tip_color=Color(.13,.18,.3); result.bands=3; result.outline=.04; result.specular=.15
	return result
func thumbnail() -> Texture2D: return load("res://Workspaces/ModelWorkspace/growth/growth_thumbnail.gd").texture(null,self)
static func source_version(path: String) -> int: return int(source_versions.get(ProjectSettings.globalize_path(path).replace("\\","/").simplify_path(),0))
static func invalidate_source(source: Variant) -> void:
	var path: String=source.resource_path if source is Resource else str(source)
	if path.is_empty(): return
	var identity:=ProjectSettings.globalize_path(path).replace("\\","/").simplify_path(); source_versions[identity]=source_version(path)+1
func copy_material(unique: bool=false) -> KiwiGrowthMaterial:
	var result:=duplicate(false) as KiwiGrowthMaterial
	if unique: result.asset_id=ActorData.new_id(); result.linked_source=""
	if unique and custom_asset!=null: result.custom_asset=custom_asset.copy_object()
	if unique and custom!=null: result.custom=custom.duplicate(false)
	result.texture_sources=texture_sources.duplicate(true); result.texture_stamps=texture_stamps.duplicate()
	if gradient!=null: result.gradient=gradient.duplicate(true)
	for field: String in ["albedo_texture","roughness_texture","normal_texture","alpha_texture"]:
		if get(field) is NoiseTexture2D: result.set(field,get(field).duplicate(true))
	return result
static func noise_signature(texture: NoiseTexture2D) -> Array:
	var settings:=[]
	if texture.noise!=null:
		for property: Dictionary in texture.noise.get_property_list():
			if int(property.usage)&PROPERTY_USAGE_STORAGE and typeof(texture.noise.get(property.name)) in [TYPE_FLOAT,TYPE_INT,TYPE_BOOL,TYPE_VECTOR3]: settings.append([property.name,texture.noise.get(property.name)])
	return [texture.width,texture.height,texture.as_normal_map,texture.bump_strength,texture.seamless,settings]
func signature() -> int:
	var values:=[]
	for property: Dictionary in get_property_list():
		if int(property.usage)&PROPERTY_USAGE_STORAGE and str(property.name) not in ["script","resource_name","resource_path","resource_local_to_scene"]:
			var value: Variant=get(property.name)
			if value is Gradient: values.append([value.colors,value.offsets,value.interpolation_mode,value.interpolation_color_space])
			elif value is NoiseTexture2D: values.append(noise_signature(value))
			else: values.append(value)
	return hash(values)
func material() -> Material:
	if mode==2:
		if custom_asset!=null:
			var next_asset:=hash(asset_values(custom_asset))
			if next_asset!=custom_asset_key: custom_asset_key=next_asset; custom=from_asset(custom_asset)
		if custom!=null: return prepare_custom()
	for slot: String in texture_sources:
		var path:=str(texture_sources[slot]); var stamp: Array=[FileAccess.get_modified_time(path),source_version(path)]
		var cached_resource: Resource
		if path.get_extension().to_lower() in ["tres","res"] and ResourceLoader.exists(path):
			cached_resource=ResourceLoader.load(path)
			if cached_resource is ActorObjectData: stamp.append(hash(asset_values(cached_resource)))
		if texture_stamps.get(slot,[])==stamp: continue
		var previous: Array=texture_stamps.get(slot,[])
		var texture: Texture2D
		if path.get_extension().to_lower() in ["tres","res"]:
			var resource:=cached_resource
			if previous.is_empty() or previous[0]!=stamp[0] or previous[1]!=stamp[1]: resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_REPLACE)
			texture=ActorImageGenerator.texture_for_object(resource) if resource is ActorObjectData else resource as Texture2D
			if resource is ActorObjectData and stamp.size()>2: stamp[2]=hash(asset_values(resource))
		else:
			var image:=Image.load_from_file(path)
			if image!=null and not image.is_empty(): image.generate_mipmaps(); texture=ImageTexture.create_from_image(image)
		texture_stamps[slot]=stamp
		set(slot,texture)
	if shader==null: shader=load("res://Workspaces/ModelWorkspace/growth/growth_surface.gdshader")
	var variant:=1 if coverage==0 and opacity<.999 else coverage
	if variant>0 and not variants.has(variant):
		var generated:=Shader.new(); var code:=shader.code
		if variant==1: code=code.replace("ALPHA_SCISSOR_THRESHOLD=.4;","ALPHA_HASH_SCALE=1.;")
		else: code=code.replace("depth_prepass_alpha;","depth_prepass_alpha, alpha_to_coverage;").replace("ALPHA_SCISSOR_THRESHOLD=.4;","ALPHA_SCISSOR_THRESHOLD=.4; ALPHA_ANTIALIASING_EDGE=.3;")
		generated.code=code; variants[variant]=generated
	var selected: Shader=variants.get(variant,shader)
	if runtime==null: runtime=ShaderMaterial.new()
	if runtime.shader!=selected: runtime.shader=selected; runtime_key=0
	var key:=signature()
	if key==runtime_key: return runtime
	runtime_key=key
	for name: String in ["root_color","tip_color","highlight_color","roughness","specular","secondary_highlight","highlight_shift","backlight","opacity","emission","variation","bands","edge_softness","outline","outline_color","shaft_color","feather_detail","iridescence","feather_pattern","feather_pattern_color","feather_pattern_scale","feather_pattern_width","left_vane_color","right_vane_color","shaft_roughness","pattern","pattern_color","pattern_scale","pattern_rotation","pattern_mix","pattern_seed","texture_scale","texture_offset","texture_rotation"]: runtime.set_shader_parameter(name,get(name))
	runtime.set_shader_parameter("stylized",mode==1)
	for name: String in ["albedo_texture","roughness_texture","normal_texture","alpha_texture"]:
		runtime.set_shader_parameter("use_"+name,get(name)!=null); runtime.set_shader_parameter(name,get(name))
	var texture: GradientTexture1D
	if gradient!=null: texture=GradientTexture1D.new(); texture.gradient=gradient
	runtime.set_shader_parameter("use_gradient",gradient!=null); runtime.set_shader_parameter("gradient_texture",texture)
	return runtime
static func asset_values(value: Variant,depth: int=0) -> Variant:
	if depth>12: return null
	if value is ActorObjectData: return [value.type_id,asset_values(value.values,depth+1)]
	if value is ActorObjectReference: return asset_values(ActorAnimation.resolve_reference(value),depth+1)
	if value is Shader: return value.code
	if value is String and str(value).get_extension().to_lower()=="gdshader": return [value,FileAccess.get_modified_time(value),source_version(value)]
	if value is Dictionary:
		var result:={}
		for key: Variant in value: result[key]=asset_values(value[key],depth+1)
		return result
	if value is Array:
		var result:=[]
		for child: Variant in value: result.append(asset_values(child,depth+1))
		return result
	return value
static func from_asset(resource: Resource) -> Material:
	if resource is Material: return resource
	if not resource is ActorObjectData: return null
	if resource.type_id==&"natural_material": return preload("res://scripts/materials/natural_material_engine.gd").create_spatial_material(resource.get_value(&"material_settings",{}))
	var adapter: Variant=load("res://scripts/actors/examples/basic_actor.gd").new(); var result: Material
	if resource.type_id==&"shader_material": result=adapter._create_shader_material(resource)
	elif resource.type_id==&"material": adapter.material=StandardMaterial3D.new(); adapter._apply_standard_material(resource); result=adapter.material
	adapter.free()
	if result is ShaderMaterial and (result.shader==null or result.shader.get_mode()!=Shader.MODE_SPATIAL): return null
	return result
func prepare_custom() -> Material:
	if not custom is ShaderMaterial: runtime_key=hash(custom); return custom
	var source:=custom as ShaderMaterial
	if source.shader==null: return source
	var uniforms:=[]
	for property: Dictionary in source.shader.get_shader_uniform_list(): uniforms.append([property.name,source.get_shader_parameter(property.name)])
	var key:=hash([source.shader.code,uniforms])
	if custom_runtime is ShaderMaterial and key==custom_key: return custom_runtime
	var prepared:=ActorShaderTime.prepare(source.shader.code); var copy:=custom_runtime as ShaderMaterial
	if copy==null: copy=ShaderMaterial.new()
	if copy.shader==null or copy.shader.code!=str(prepared.code): var shader_copy:=Shader.new(); shader_copy.code=prepared.code; copy.shader=shader_copy
	for uniform: Array in uniforms: copy.set_shader_parameter(uniform[0],uniform[1])
	var time_name:=str(prepared.uniform)
	if time_name.is_empty(): time_name=str(source.get_meta("kiwi_time_uniform",""))
	copy.set_meta("kiwi_time_uniform",time_name); custom_runtime=copy; custom_key=key; runtime_key=key; return copy
