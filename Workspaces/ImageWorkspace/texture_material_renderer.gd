extends RefCounted
const Library=preload("res://Workspaces/ImageWorkspace/texture_material_library.gd")
const Source=preload("res://scripts/materials/natural_material_shader_source.gd")
static var shader_cache: Dictionary={}
static var noise_cache: Dictionary={}
static var CODE: String="""shader_type canvas_item;
render_mode unshaded;
uniform sampler2D noise_map : repeat_enable, filter_linear;
uniform sampler2D coverage_map : hint_default_white, repeat_disable, filter_linear;
uniform sampler2D coordinate_map : repeat_disable, filter_linear;
uniform bool has_coordinate_map=false;
uniform vec4 coordinate_rect=vec4(0.,0.,1.,1.);
uniform sampler2D image_map : repeat_enable, filter_linear_mipmap;
uniform sampler2D base_map : hint_default_white, repeat_disable;
uniform sampler2D mix_mask : hint_default_white;
uniform bool imported=false;
uniform vec2 image_aspect=vec2(1.);
uniform float tint_strength=0.; uniform int tiling=0;
uniform bool masked=false;
uniform float coverage_opacity=1.;
uniform bool seamless=true;
uniform int output_mode=0;
uniform float metallic_override=-1.;
uniform int family=1;
uniform int variant=0;
uniform vec4 primary : source_color=vec4(.2,.1,.05,1.);
uniform vec4 secondary : source_color=vec4(.7,.4,.2,1.);
uniform float density=1.; uniform float thickness=.15;
uniform float roughness=.45; uniform float distortion=.35; uniform float detail=.6; uniform float knots=.35;
uniform float contrast=1.; uniform float brightness=0.; uniform float seed=0.;
uniform vec2 extent=vec2(256.); uniform float texture_size=64.; uniform float angle=0.;
uniform vec2 origin=vec2(0.); uniform vec2 axis_x=vec2(1.,0.); uniform vec2 axis_y=vec2(0.,1.);
uniform int blend_mode=0; uniform float relief=0.; uniform float light_angle=.7;
uniform float highlight=1.; uniform float shadow=1.;
uniform float relief_softness=.3;
uniform bool mixer_enabled=false;
uniform float mix_amount=0.; uniform int mix_distribution=0;
uniform float secondary_texture_size=64.; uniform float secondary_angle=0.;
uniform vec4 secondary_primary:source_color=vec4(0.); uniform vec4 secondary_secondary:source_color=vec4(1.);
uniform sampler2D secondary_noise_map:repeat_enable,filter_linear;
uniform sampler2D secondary_image_map:repeat_enable,filter_linear_mipmap;
uniform bool secondary_imported=false;
uniform bool secondary_seamless=true;
uniform vec2 secondary_image_aspect=vec2(1.);
uniform int secondary_family=0; uniform int secondary_variant=0;
uniform float secondary_density=1.; uniform float secondary_thickness=.15;
uniform float secondary_roughness=.45; uniform float secondary_distortion=.35; uniform float secondary_detail=.6; uniform float secondary_knots=.35;
uniform float secondary_contrast=1.; uniform float secondary_brightness=0.; uniform float secondary_seed=0.;
"""+Source.source+"""
void fragment(){float paint_coverage=coverage_opacity*(masked ? texture(coverage_map,UV).a : 1.);if(paint_coverage<=0.){discard;}
 vec2 local=UV*extent; vec2 p=origin+axis_x*local.x+axis_y*local.y;
 if(has_coordinate_map){p=texture(coordinate_map,(UV-coordinate_rect.xy)/max(coordinate_rect.zw,vec2(.000001))).rg;local=p;}
 p=mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)))*p/max(.01,texture_size)*16.;
 vec2 image_uv=p/16./image_aspect;
 if(tiling==1){image_uv=1.-abs(mod(image_uv,2.)-1.);}if(tiling==2){image_uv=clamp(image_uv,vec2(.001),vec2(.999));}
 float height=pattern(p); vec4 c=imported ? texture(image_map,image_uv) : natural_color(p,height);
 if(imported){c.rgb=mix(c.rgb,c.rgb*primary.rgb,tint_strength);c.rgb=(c.rgb-.5)*contrast+.5+brightness;height=dot(c.rgb,vec3(.2126,.7152,.0722));}
 if(mixer_enabled){vec2 p2=mat2(vec2(cos(secondary_angle),sin(secondary_angle)),vec2(-sin(secondary_angle),cos(secondary_angle)))*local/max(.01,secondary_texture_size)*16.;
 float height2=secondary_pattern(p2);vec4 c2=secondary_imported ? texture(secondary_image_map,p2/16./secondary_image_aspect) : secondary_natural_color(p2,height2);
 if(secondary_imported){height2=dot(c2.rgb,vec3(.2126,.7152,.0722));}
 float amount=mix_amount;if(mix_distribution==1){amount*=smoothstep(.25,.75,n(p*4.))*2.;}if(mix_distribution==2){amount*=smoothstep(.25,.75,cell(p*.3).z)*2.;}if(mix_distribution==3){amount*=texture(mix_mask,UV).a;}
 c=mix(c,c2,clamp(amount,0.,1.));height=mix(height,height2,clamp(amount,0.,1.));}
 if(!imported && family==6){c.a*=smoothstep(.15,.6,height);}
 vec2 pdx=dFdx(p),pdy=dFdy(p);float determinant=pdx.x*pdy.y-pdx.y*pdy.x;vec2 slope=vec2(dFdx(height)*pdy.y-dFdy(height)*pdx.y,dFdy(height)*pdx.x-dFdx(height)*pdy.x)/max(.000001,abs(determinant))*sign(determinant);
 if(relief!=0.){float r=dot(slope,vec2(cos(light_angle),sin(light_angle)))*relief*mix(.4,.12,relief_softness);c.rgb*=1.+max(r,0.)*highlight+min(r,0.)*shadow;}
 vec4 old=texture(base_map,UV); float lum=dot(c.rgb,vec3(.2126,.7152,.0722));
 if(blend_mode==1){c.rgb=mix(2.*old.rgb*c.rgb,1.-2.*(1.-old.rgb)*(1.-c.rgb),step(vec3(.5),old.rgb));}
 if(blend_mode==2){c.rgb*=dot(old.rgb,vec3(.2126,.7152,.0722))/max(.01,lum);}
 if(blend_mode==3){c.rgb=old.rgb*(.65+height*.7);}
 if(output_mode==1){c=vec4(vec3(height),1.);}
 if(output_mode==2){c=vec4(normalize(vec3(-slope*max(.1,abs(relief))*.5,1.))*.5+.5,1.);}
 vec2 surface=natural_surface(p,height);
 if(output_mode==3){c=vec4(vec3(surface.x),1.);}
 if(output_mode==4){c=vec4(vec3(metallic_override<0.?surface.y:metallic_override),1.);}
 c.a*=paint_coverage; COLOR=vec4(clamp(c.rgb,vec3(0.),vec3(1.)),c.a);
}
"""
static func material(value: KiwiTextureMaterial,extent: Vector2,frame: Transform2D=Transform2D.IDENTITY,straight_output: bool=false) -> ShaderMaterial:
	var mixed:=value.secondary!=null and value.mix_amount>0
	var cache_key:=value.material_id+"/"+str(straight_output)+("/"+value.secondary.material_id if mixed else "")
	if not shader_cache.has(cache_key):
		var code:=CODE.substr(0,CODE.find("// Single structural evaluator"))+Source.pattern_source(value.material_id)+"\n"+CODE.substr(CODE.find("void fragment()"))
		code=Source.constants(code,value.material_id)
		if mixed:
			var duplicate:=Source.pattern_source(value.secondary.material_id)
			for key in ["seamless","family","variant","density","thickness","roughness","distortion","detail","knots","contrast","brightness","seed","noise_map","primary","secondary","h","n","cell","line","pattern","raw_pattern","natural_color","natural_surface","nm_fbm","nm_threads","nm_wood","nm_metal","nm_fabric","nm_stone","nm_ground","nm_organic","nm_weather","nm_illustration","nm_geometry","nm_noise"]:
				var regex:=RegEx.new();regex.compile("\\b"+key+"\\b");duplicate=regex.sub(duplicate,"secondary_"+key,true)
			code=code.replace("void fragment()",duplicate+"\nvoid fragment()")
			code=Source.constants(code,value.secondary.material_id,"secondary_")
		else:
			var start:=code.find("if(mixer_enabled)");var end:=Source.block_end(code,code.find("{",start))
			code=code.substr(0,start)+code.substr(end+1)
		if straight_output: code=code.replace("render_mode unshaded;","render_mode unshaded, blend_disabled;")
		var compiled:=Shader.new();compiled.code=code
		if shader_cache.size()>=32: shader_cache.erase(shader_cache.keys()[0])
		shader_cache[cache_key]=compiled
	var result:=ShaderMaterial.new();result.shader=shader_cache[cache_key]
	var family:=Library.CATEGORIES.keys().find(Library.category(value.material_id))
	result.set_shader_parameter("family",maxi(0,family)); result.set_shader_parameter("variant",Library.variant(value.material_id))
	var defaults:=Library.create(value.material_id).parameters
	for key in ["primary","secondary","density","thickness","roughness","distortion","detail","knots","contrast","brightness","seed"]:
		result.set_shader_parameter(key,value.parameters.get(key,defaults.get(key)))
	var noise_key:=hash([family,Library.variant(value.material_id),value.parameters.get("seed",0),value.parameters.get("frequency",.035),value.parameters.get("octaves",4),value.parameters.get("gain",.5),value.parameters.get("lacunarity",2)])
	if not noise_cache.has(noise_key):
		if noise_cache.size()>=64: noise_cache.erase(noise_cache.keys()[0])
		var noise:=FastNoiseLite.new(); noise.seed=value.parameters.get("seed",0); noise.frequency=value.parameters.get("frequency",.035); noise.fractal_octaves=value.parameters.get("octaves",4); noise.fractal_gain=value.parameters.get("gain",.5); noise.fractal_lacunarity=value.parameters.get("lacunarity",2)
		if family==9:
			noise.noise_type=FastNoiseLite.TYPE_PERLIN if Library.variant(value.material_id)==3 else (FastNoiseLite.TYPE_VALUE if Library.variant(value.material_id) in [1,2] else FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
		noise_cache[noise_key]=ImageTexture.create_from_image(noise.get_seamless_image(128,128))
	result.set_shader_parameter("noise_map",noise_cache[noise_key]); result.set_shader_parameter("extent",extent)
	result.set_shader_parameter("seamless",value.parameters.get("tileable",true)); result.set_shader_parameter("metallic_override",value.metallic)
	result.set_shader_parameter("texture_size",value.texture_size); result.set_shader_parameter("angle",deg_to_rad(value.rotation))
	result.set_shader_parameter("origin",frame.origin if value.alignment=="canvas" else (-value.mapping_origin if value.alignment=="stroke" else Vector2.ZERO))
	result.set_shader_parameter("axis_x",frame.x if value.alignment=="canvas" else Vector2.RIGHT); result.set_shader_parameter("axis_y",frame.y if value.alignment=="canvas" else Vector2.DOWN)
	result.set_shader_parameter("coverage_map",value.coverage); result.set_shader_parameter("masked",value.coverage!=null)
	result.set_shader_parameter("base_map",value.source); result.set_shader_parameter("image_map",value.image); result.set_shader_parameter("imported",value.image!=null)
	if value.image!=null: result.set_shader_parameter("image_aspect",value.image.get_size()/float(maxi(1,mini(value.image.get_width(),value.image.get_height()))))
	result.set_shader_parameter("tint_strength",value.tint_strength); result.set_shader_parameter("tiling",["repeat","mirror","clamp"].find(value.tiling))
	result.set_shader_parameter("blend_mode",["replace","overlay","colorize","detail"].find(value.blending))
	result.set_shader_parameter("relief",value.relief); result.set_shader_parameter("light_angle",deg_to_rad(value.light_direction)); result.set_shader_parameter("highlight",value.highlight); result.set_shader_parameter("shadow",value.shadow)
	result.set_shader_parameter("relief_softness",value.relief_softness)
	result.set_shader_parameter("mixer_enabled",value.secondary!=null and value.mix_amount>0)
	if value.secondary!=null:
		var second:=value.secondary.copy_material(); second.secondary=null
		var other:=material(second,extent)
		for key in ["seamless","family","variant","primary","secondary","density","thickness","roughness","distortion","detail","knots","contrast","brightness","seed","noise_map","image_map","image_aspect","imported","texture_size"]:
			result.set_shader_parameter("secondary_"+key,other.get_shader_parameter(key))
		result.set_shader_parameter("secondary_angle",deg_to_rad(second.rotation)); result.set_shader_parameter("mix_amount",value.mix_amount)
		result.set_shader_parameter("mix_distribution",["uniform","noise","patches","selection"].find(value.mix_distribution)); result.set_shader_parameter("mix_mask",value.mix_mask)
	return result

static func preview(host: Node,value: KiwiTextureMaterial,size: Vector2i=Vector2i(256,256),extent: Vector2=Vector2.ZERO,frame: Transform2D=Transform2D.IDENTITY,coordinates: Texture2D=null,coordinate_rect: Rect2=Rect2(0,0,1,1)) -> Image:
	var viewport:=SubViewport.new(); viewport.disable_3d=true; viewport.transparent_bg=true; viewport.size=size; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; host.add_child(viewport)
	var rect:=ColorRect.new(); rect.size=Vector2(size); rect.material=material(value,extent if extent!=Vector2.ZERO else Vector2(size),frame,true); viewport.add_child(rect)
	rect.material.set_shader_parameter("has_coordinate_map",coordinates!=null)
	rect.material.set_shader_parameter("coordinate_map",coordinates)
	rect.material.set_shader_parameter("coordinate_rect",Vector4(coordinate_rect.position.x,coordinate_rect.position.y,coordinate_rect.size.x,coordinate_rect.size.y))
	for i in 3:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(viewport): return null
	var image:=viewport.get_texture().get_image(); viewport.queue_free(); return image
