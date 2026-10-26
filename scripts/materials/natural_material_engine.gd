extends RefCounted
## One material definition and evaluator, adapted to 2D coverage, generated maps and 3D.
const Definitions=preload("res://scripts/materials/natural_material_definitions.gd")
const CanvasRenderer=preload("res://Workspaces/ImageWorkspace/texture_material_renderer.gd")
const MATERIAL_FIELDS=["label","texture_size","rotation","relief","relief_softness","light_direction","highlight","shadow","alignment","mapping_origin","tint_strength","tiling","blending","metallic","image","mix_amount","mix_distribution","mix_mask"]
const PARAMETERS=["family","variant","primary","secondary","density","thickness","roughness","distortion","detail","knots","contrast","brightness","seed","noise_map","seamless","texture_size","angle","relief","metallic_override","image_map","imported","image_aspect","tint_strength"]
const ShaderSource=preload("res://scripts/materials/natural_material_shader_source.gd")
static var _spatial_shaders: Dictionary={}
static var _maps_cache: Dictionary={}
static var _map_order: Array[String]=[]

static func definitions() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for id in Definitions.ids(): result.append(Definitions.definition(id))
	return result

static func defaults(id: String="wood/oak") -> Dictionary:
	return settings_from_material(Definitions.create(id))

static func normalize(settings: Dictionary) -> Dictionary:
	return settings_from_material(material_from_settings(settings))

static func material_from_settings(settings: Dictionary) -> KiwiTextureMaterial:
	var id:=str(settings.get("material_id","wood/oak"))
	if not Definitions.ids().has(id): id="wood/oak"
	var value:=Definitions.create(id)
	var parameters: Dictionary=settings.get("parameters",{})
	for key in value.parameters:
		if parameters.has(key):
			var next=parameters[key]
			if key in ["primary","secondary"]:
				if next is String: next=Color.from_string(next,value.parameters[key])
				elif next is Array and next.size()>=3: next=Color(next[0],next[1],next[2],next[3] if next.size()>3 else 1.)
			value.parameters[key]=next
	for key in MATERIAL_FIELDS:
		if settings.has(key): value.set(key,settings[key])
	value.texture_size=maxf(1.,value.texture_size)
	value.surface_mapping=str(settings.get("mapping",settings.get("surface_mapping","uv")))
	value.triplanar_sharpness=clampf(float(settings.get("triplanar_sharpness",4.)),1.,16.)
	value.format_version=Definitions.VERSION
	if settings.get("secondary") is Dictionary: value.secondary=material_from_settings(settings.secondary)
	return value

static func settings_from_material(value: KiwiTextureMaterial) -> Dictionary:
	var result:={"version":Definitions.VERSION,"material_id":value.material_id,"parameters":value.parameters.duplicate(true),"mapping":value.surface_mapping,"triplanar_sharpness":value.triplanar_sharpness}
	for key in MATERIAL_FIELDS: result[key]=value.get(key)
	if value.secondary!=null: result.secondary=settings_from_material(value.secondary)
	return result

static func canvas_material(value: KiwiTextureMaterial,extent: Vector2,frame: Transform2D=Transform2D.IDENTITY,straight_output: bool=false) -> ShaderMaterial:
	return CanvasRenderer.material(value,extent,frame,straight_output)

static func create_spatial_material(settings: Dictionary) -> ShaderMaterial:
	var material:=ShaderMaterial.new()
	configure_spatial(material,settings)
	return material

static func spatial_material(value: KiwiTextureMaterial) -> ShaderMaterial:
	return create_spatial_material(settings_from_material(value))

static func configure_spatial(material: ShaderMaterial,settings: Dictionary) -> void:
	var value:=material_from_settings(settings)
	var key:=value.material_id+("/"+value.secondary.material_id if value.secondary!=null and value.mix_amount>0. else "")
	if not _spatial_shaders.has(key):
		var shader:=Shader.new();shader.code=ShaderSource.constants(_spatial_source(value),value.material_id)
		if _spatial_shaders.size()>=32: _spatial_shaders.erase(_spatial_shaders.keys()[0])
		_spatial_shaders[key]=shader
	material.shader=_spatial_shaders[key]
	var canvas:=CanvasRenderer.material(value,Vector2(256,256))
	for parameter in PARAMETERS: material.set_shader_parameter(parameter,canvas.get_shader_parameter(parameter))
	if value.secondary!=null:
		for parameter in PARAMETERS: material.set_shader_parameter("secondary_"+parameter,canvas.get_shader_parameter("secondary_"+parameter))
		for parameter in ["mix_amount","mix_distribution","mix_mask"]: material.set_shader_parameter(parameter,canvas.get_shader_parameter(parameter))
	material.set_shader_parameter("triplanar",value.surface_mapping=="triplanar")
	material.set_shader_parameter("triplanar_sharpness",value.triplanar_sharpness)
	material.resource_name=value.label

static func _spatial_source(value: KiwiTextureMaterial) -> String:
	var code:="""shader_type spatial;
render_mode diffuse_burley,specular_schlick_ggx;
uniform sampler2D noise_map:repeat_enable,filter_linear;
uniform sampler2D image_map:repeat_enable,filter_linear_mipmap;
uniform bool imported=false;
uniform vec2 image_aspect=vec2(1.);
uniform float tint_strength=0.;
uniform int family=1; uniform int variant=0;
uniform vec4 primary:source_color=vec4(.2,.1,.05,1.);
uniform vec4 secondary:source_color=vec4(.7,.4,.2,1.);
uniform float density=1.; uniform float thickness=.15; uniform float roughness=.45;
uniform float distortion=.35; uniform float detail=.6; uniform float knots=.35;
uniform float contrast=1.; uniform float brightness=0.; uniform float seed=0.;
uniform bool seamless=true;
uniform float texture_size=64.; uniform float angle=0.; uniform float relief=.3;
uniform float metallic_override=-1.;
uniform bool triplanar=false; uniform float triplanar_sharpness=4.;
varying vec3 object_position; varying vec3 object_normal;
void vertex(){object_position=VERTEX;object_normal=NORMAL;}
"""+ShaderSource.pattern_source(value.material_id)+"""
vec2 mapped(vec2 uv){return mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)))*uv*256./max(1.,texture_size)*16.;}
float surface_height(vec2 p){return pattern(p);}
void fragment(){
 vec2 p=mapped(UV);float height=surface_height(p);vec4 color=natural_color(p,height);vec2 surface=natural_surface(p,height);
 if(triplanar){
  vec3 weights=pow(abs(normalize(object_normal)),vec3(triplanar_sharpness));weights/=max(.0001,weights.x+weights.y+weights.z);
  vec2 px=mapped(object_position.zy*.5),py=mapped(object_position.xz*.5),pz=mapped(object_position.xy*.5);
  float hx=surface_height(px),hy=surface_height(py),hz=surface_height(pz);
  height=dot(vec3(hx,hy,hz),weights);
  color=natural_color(px,hx)*weights.x+natural_color(py,hy)*weights.y+natural_color(pz,hz)*weights.z;
  surface=natural_surface(px,hx)*weights.x+natural_surface(py,hy)*weights.y+natural_surface(pz,hz)*weights.z;
 }
 if(imported){color=texture(image_map,p/16./image_aspect);color.rgb=mix(color.rgb,color.rgb*primary.rgb,tint_strength);height=dot(color.rgb,vec3(.2126,.7152,.0722));}
 // SECONDARY_SAMPLE
 ALBEDO=color.rgb;ROUGHNESS=surface.x;METALLIC=metallic_override<0.?surface.y:metallic_override;
 // Screen derivatives produce a surface gradient in the actual tangent plane.
 // This works for UV and triplanar projections without an external normal texture.
 vec3 dpdx=dFdx(VERTEX),dpdy=dFdy(VERTEX);vec3 r1=cross(dpdy,NORMAL),r2=cross(NORMAL,dpdx);
 float det=dot(dpdx,r1);float dhdx=dFdx(height),dhdy=dFdy(height);
 vec3 gradient=sign(det)*(dhdx*r1+dhdy*r2);
 NORMAL=normalize(abs(det)*NORMAL-clamp(relief,-2.,2.)*.015*gradient);
}
"""
	if value.secondary!=null and value.mix_amount>0.:
		var header:="""uniform sampler2D secondary_noise_map:repeat_enable,filter_linear;
uniform sampler2D secondary_image_map:repeat_enable,filter_linear_mipmap;
uniform sampler2D mix_mask:hint_default_white;
uniform int secondary_family=0;uniform int secondary_variant=0;
uniform vec4 secondary_primary:source_color=vec4(0.);uniform vec4 secondary_secondary:source_color=vec4(1.);
uniform float secondary_density=1.;uniform float secondary_thickness=.15;uniform float secondary_roughness=.45;
uniform float secondary_distortion=.35;uniform float secondary_detail=.6;uniform float secondary_knots=.35;
uniform float secondary_contrast=1.;uniform float secondary_brightness=0.;uniform float secondary_seed=0.;
uniform bool secondary_seamless=true;uniform bool secondary_imported=false;uniform vec2 secondary_image_aspect=vec2(1.);
uniform float secondary_texture_size=64.;uniform float secondary_angle=0.;uniform float mix_amount=0.;uniform int mix_distribution=0;
"""
		code=code.replace("varying vec3 object_position;",header+"varying vec3 object_position;")
		code=code.replace("vec2 mapped(vec2 uv)",ShaderSource.secondary_source(value.secondary.material_id)+"\nvec2 mapped(vec2 uv)")
		code=ShaderSource.constants(code,value.secondary.material_id,"secondary_")
		code=code.replace("// SECONDARY_SAMPLE","""vec2 p2=mat2(vec2(cos(secondary_angle),sin(secondary_angle)),vec2(-sin(secondary_angle),cos(secondary_angle)))*UV*256./max(1.,secondary_texture_size)*16.;
 float height2=secondary_pattern(p2);vec4 color2=secondary_natural_color(p2,height2);vec2 surface2=secondary_natural_surface(p2,height2);
 if(secondary_imported){color2=texture(secondary_image_map,p2/16./secondary_image_aspect);height2=dot(color2.rgb,vec3(.2126,.7152,.0722));}
 float amount=mix_amount;
 if(mix_distribution==1){amount*=smoothstep(.25,.75,n(p*4.))*2.;}
 if(mix_distribution==2){amount*=smoothstep(.25,.75,cell(p*.3).z)*2.;}
 if(mix_distribution==3){amount*=texture(mix_mask,UV).a;}
 amount=clamp(amount,0.,1.);color=mix(color,color2,amount);height=mix(height,height2,amount);surface=mix(surface,surface2,amount);
""")
	return code

## Generate only requested maps. GPU evaluation uses the same code as live painting.
## Bounded cache prevents previews from retaining unbounded texture memory.
static func render_maps(host: Node,value: KiwiTextureMaterial,size: Vector2i=Vector2i(256,256),outputs: Array=["albedo"]) -> Dictionary:
	var result: Dictionary={}
	var signature_data:=settings_from_material(value)
	if value.image!=null: signature_data.image_identity=value.image.get_instance_id()
	var signature:=var_to_bytes(signature_data).hex_encode().sha256_text()
	var safe_size:=Vector2i(clampi(size.x,1,4096),clampi(size.y,1,4096))
	var modes:={"albedo":0,"height":1,"normal":2,"roughness":3,"metallic":4}
	for output in outputs:
		if not modes.has(output): continue
		var key:="%s/%s/%s" % [signature,safe_size,output]
		if _maps_cache.has(key): result[output]=_maps_cache[key].duplicate(); continue
		var viewport:=SubViewport.new();viewport.disable_3d=true;viewport.transparent_bg=true;viewport.size=safe_size
		viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;host.add_child(viewport)
		var rect:=ColorRect.new();rect.size=Vector2(safe_size)
		var copy:=value.copy_material();copy.coverage=null;copy.source=null;copy.blending="replace"
		if output=="albedo": copy.relief=0.
		rect.material=CanvasRenderer.material(copy,Vector2(256,256),Transform2D.IDENTITY,true)
		rect.material.set_shader_parameter("output_mode",modes[output]);viewport.add_child(rect)
		for frame in 3: await RenderingServer.frame_post_draw
		var image:=viewport.get_texture().get_image();viewport.queue_free()
		if image==null: continue
		result[output]=image
		if safe_size.x*safe_size.y<=512*512:
			while _map_order.size()>=32: _maps_cache.erase(_map_order.pop_front())
			_map_order.append(key);_maps_cache[key]=image.duplicate()
	return result

static func clear_cache() -> void:
	_maps_cache.clear();_map_order.clear()
