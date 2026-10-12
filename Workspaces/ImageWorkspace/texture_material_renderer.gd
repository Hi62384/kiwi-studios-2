extends RefCounted
const Library=preload("res://Workspaces/ImageWorkspace/texture_material_library.gd")
static var shader: Shader
static var straight_shader: Shader
static var noise_cache: Dictionary={}
const CODE="""shader_type canvas_item;
render_mode unshaded;
uniform sampler2D noise_map : repeat_enable, filter_linear;
uniform sampler2D coverage_map : hint_default_white, repeat_disable, filter_linear;
uniform sampler2D image_map : repeat_enable, filter_linear_mipmap;
uniform sampler2D base_map : hint_default_white, repeat_disable;
uniform sampler2D mix_mask : hint_default_white;
uniform bool imported=false;
uniform vec2 image_aspect=vec2(1.);
uniform float tint_strength=0.; uniform int tiling=0;
uniform bool masked=false;
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
uniform vec2 secondary_image_aspect=vec2(1.);
uniform int secondary_family=0; uniform int secondary_variant=0;
uniform float secondary_density=1.; uniform float secondary_thickness=.15;
uniform float secondary_roughness=.45; uniform float secondary_distortion=.35; uniform float secondary_detail=.6; uniform float secondary_knots=.35;
uniform float secondary_contrast=1.; uniform float secondary_brightness=0.; uniform float secondary_seed=0.;
float h(vec2 p){return fract(sin(dot(p+seed,vec2(127.1,311.7)))*43758.5453);}
float n(vec2 p){return texture(noise_map,p/128.).r;}
vec3 cell(vec2 p){vec2 g=floor(p),f=fract(p); float d=10.,d2=10.,id=0.;
 for(int y=-1;y<=1;y++){for(int x=-1;x<=1;x++){vec2 q=g+vec2(float(x),float(y)); vec2 r=vec2(h(q),h(q+13.))-f+vec2(float(x),float(y)); float v=dot(r,r); if(v<d){d2=d;d=v;id=h(q+27.);}else if(v<d2){d2=v;}}}return vec3(sqrt(d),sqrt(d2)-sqrt(d),id);}
float line(float v,float width){return 1.-smoothstep(width,width+.06,abs(v));}
float pattern(vec2 p){p*=density; p+=(vec2(n(p*.7),n(p*.7+41.))-.5)*distortion*2.;float coarse=n(p*2.),fine=n(p*(8.+detail*48.)); vec3 cells=cell(p*.18); float v=coarse;
 if(family==0){
  float brushed=n(vec2(p.x*.8,p.y*42.)); float scratch=line(fract(p.y*(3.+detail*18.)+coarse*.1)-.5,.015)*step(.45,n(vec2(p.x*.15,p.y*7.)));
  v=.55+(brushed-.5)*roughness+scratch*.2;
  if(variant==2 || variant==8 || variant==9){v=.5+.22*sin(p.y*.4)+fine*.06;}
  if(variant==3 || variant==4){v=.35+fine*.45-cells.x*.15;}
  if(variant==10){v=.3+cells.z*.5+line(cells.y,.035)*.2;}
  if(variant==11){v=smoothstep(.35,.7,coarse)+fine*.04;}
  if(variant==12){v-=scratch*.5;}
  if(variant==13){v=.5+.35*cos(cells.x*9.)+fine*.06;}
  if(variant==14){vec2 q=fract(p*.35)-.5; v=.35+.5*line(abs(q.x)+abs(q.y)-.28,.06);}
 }else if(family==1){
  vec2 g=p; float bend=(n(vec2(p.x*.1,p.y*.3))-.5)*distortion*12.;
	vec2 center=vec2(8.+sin(seed)*3.,8.); vec2 delta=p-center;
	float knot_weight=knots*exp(-dot(delta*vec2(.55,1.5),delta*vec2(.55,1.5))*.025);
	float grain=.5+.5*sin(g.y*3.+bend+(n(p*.7)-.5)*distortion*5.);
	grain=mix(grain,.5+.5*sin(length(delta*vec2(.6,1.))*4.+coarse*.3),knot_weight);
  v=.25+grain*.5+(n(vec2(p.x*.2,p.y*25.))-.5)*detail*.2;
  if(variant==5){v+=line(fract(p.x*.1)-.5,.03)*.25;}
  if(variant==6){v=.3+.5*sin(p.y*7.+bend)*sin(p.y*.5);}
  if(variant==7){v=.15+pow(grain,3.)*.6+coarse*.15;}
  if(variant==8 || variant==12){v-=line(fract(p.y*1.3+coarse)-.5,.05)*roughness*.3;}
  if(variant==9){v=.65+grain*.1-step(.7,fine)*.3;}
  if(variant==10){v*=smoothstep(.025,.08,fract(p.y*.12));}
 }else if(family==2){
  vec2 q=p*.7+vec2(n(p)*distortion); float warp=cos(q.x*6.283),weft=cos(q.y*6.283); float parity=mod(floor(q.x)+floor(q.y),2.);
  v=.3+.4*pow(.5+.5*mix(warp,weft,parity),.3+thickness*4.)+detail*(fine-.5)*.15;
  if(variant==1){v=.4+.3*sin((q.x+q.y)*6.283)+fine*.1;}
  if(variant==3 || variant==13){v=.3+fine*.4+n(p*4.)*.2;}
  if(variant==4){v=.55+.25*sin(p.y*1.5+coarse*.4)+fine*.04;}
  if(variant==5 || variant==7){v=.4+fine*.15+coarse*.15;}
  if(variant==6){v=.3+cells.z*.4+line(cells.y,.025)*.2;}
  if(variant==9){v=.25+.5*abs(sin(q.x*3.14159+sin(q.y*3.14159)*1.2));}
  if(variant==12){v=.25+.6*pow(abs(sin(q.y*2.)),2.);}
  if(variant==14){v=step(abs(warp)*abs(weft),thickness);}
 }else if(family==3){
  v=.3+fine*.25+coarse*.35;
  if(variant==0){v=.15+fine*.7+coarse*.15+step(.76,fine)*.15-step(fine,.2)*.15;}
  if(variant==1){v=.75-line(sin(p.x*.3+p.y*.15+coarse*distortion*10.),thickness)*.55;}
  if(variant==4){v=.3+n(vec2(p.x*.3,p.y*7.))*.5;}
  if(variant==7 || variant==8 || variant==14){vec2 q=p*.15; q.x+=mod(floor(q.y),2.)*.5; vec2 f=fract(q); float mortar=step(thickness*.3,min(min(f.x,f.y),min(1.-f.x,1.-f.y))); v=mix(.15,.4+h(floor(q))*.35,mortar)+fine*.06;}
  if(variant==9 || variant==13){v=.3+cells.z*.5-line(cells.y,thickness*.2)*.3;}
  if(variant==11){v-=line(cells.y,thickness*.1)*.5;}
  if(variant==10){v=.1+fine*.22+step(.85,fine)*.35;}
 }else if(family==4){
  v=.2+coarse*.4+fine*roughness*.4;
  if(variant==0){vec2 q=p*vec2(.8,.18),f=fract(q)-.5;float blade=line(f.x+f.y*f.y*distortion*sin(h(floor(q))*6.283),.035*(.7-f.y));v=.15+coarse*.15+blade*(.4+h(floor(q))*.3);}
  if(variant==1){v=.25+pow(n(p*5.),2.)*.6;}
  if(variant==4 || variant==12){v-=line(cells.y,thickness*.2)*.4;}
  if(variant==6 || variant==7 || variant==10){v=.2+cells.z*.6+cos(cells.x*8.)*.1;}
  if(variant==8){v=.75+fine*.15+coarse*.1;}
  if(variant==9){v=.7-line(cells.y,.04)*.4+coarse*.12;}
  if(variant>=11 && variant!=12 && variant!=13){v=.2+step(.6,cells.z)*.5+fine*.1;}
 }else if(family==5){
  v=.5+fine*.1-line(cells.x-.04,thickness*.15)*.25;
  if(variant==1 || variant==2){vec2 q=p*.5; q.x+=mod(floor(q.y),2.)*.5; vec2 f=fract(q)-.5; v=.25+.6*(1.-smoothstep(.1,.5,length(f*vec2(1.,1.7))));}
  if(variant==3 || variant==4){v=.3+line(fract(p.y*5.+n(p*.8)*distortion)-.5,.06)*.55;}
  if(variant==5 || variant==6){v=.5+coarse*.2-line(fract(p.x*.4+sin(p.y*.3))-.5,thickness*.1)*.35;}
  if(variant==7){v=.25+.5*sin(p.y*3.+n(p)*distortion*8.);}
  if(variant==9){v=.4+.4*sin(length(p)*2.+coarse*.4);}
  if(variant==10){v=.4+cells.z*.3-line(cells.y,.08)*.2;}
 }else if(family==6){
  v=smoothstep(.3,.75,coarse)+fine*.1;
  if(variant==1){v=pow(fine,3.)*.8;}
  if(variant==2){v=smoothstep(.4,.75,coarse)*(.4+fine*.5);}
  if(variant==3){v=line(fract(p.y*(2.+detail*10.)+coarse*.15)-.5,thickness*.1)*step(.45,n(p*.3));}
  if(variant==4){v=line(cells.y,thickness*.15);}
  if(variant==5 || variant==6){v=step(.6,cells.z)*smoothstep(0.,.12,cells.y);}
  if(variant==7){v=line(cells.x-.28,thickness*.4)*.6+coarse*.2;}
  if(variant==8){v=smoothstep(.45,.68,n(p*.6));}
  if(variant==9){v=smoothstep(.35,.8,coarse)*fine;}
  if(variant==10){v=smoothstep(.3,.7,coarse)*step(.6,fine);}
  if(variant==11){v=line(cells.y,thickness*.3)*coarse;}
  if(variant==12){v=pow(smoothstep(.25,.85,n(p*.5)),3.);}
  if(variant==13){v=pow(n(p*4.),3.);}
  if(variant==14){v=line(cells.x-.03,.025);}
 }else if(family==7){
  vec2 q=p*.5; v=step(length(fract(q)-.5),thickness*2.);
  if(variant==2 || variant==10){v=step(1.-thickness,h(floor(p*5.)));}
  if(variant==3 || variant==4){v=line(fract(q.x+q.y)-.5,thickness);if(variant==3){v=max(v,line(fract(q.x-q.y)-.5,thickness));}}
  if(variant==5 || variant==6 || variant==9 || variant==11 || variant==12){v=pow(fine,1.+detail*3.);}
  if(variant==7 || variant==8){v=line(sin(q.y*6.+sin(q.x*4.)*distortion*5.),thickness);}
  if(variant==13){v=.5+.3*sin(q.y*3.+coarse);}
 }else if(family==8){
  vec2 q=p*.3,f=fract(q)-.5; v=step(0.,sin(q.y*6.283));
  if(variant==1){v=mod(floor(q.x)+floor(q.y),2.);}
  if(variant==2 || variant==9){v=variant==2 ? step(length(f),thickness*2.) : line(length(f)-.3,thickness*.3);}
  if(variant==3 || variant==11){v=max(line(f.x,thickness*.2),line(f.y,thickness*.2));}
  if(variant==4 || variant==12){vec2 z=q*vec2(1.,1.1547);z.x+=mod(floor(z.y),2.)*.5;vec2 c=abs(fract(z)-.5);v=line(max(c.x*.866+c.y*.5,c.y)-.45,thickness*.2);}
  if(variant==5){v=step(fract(q.x)+fract(q.y),1.);}
  if(variant==6){v=step(abs(f.x)+abs(f.y),.35);}
  if(variant==7){v=.5+.5*sin(q.y*6.283+sin(q.x*6.283));}
  if(variant==8){v=step(fract(q.y)+abs(f.x),.5);}
  if(variant==10){q.x+=mod(floor(q.y),2.)*.5;f=fract(q);v=step(thickness,min(min(f.x,f.y),min(1.-f.x,1.-f.y)));}
  if(variant==13){v=max(step(abs(f.x),thickness)*step(abs(f.y),.35),step(abs(f.y),thickness)*step(abs(f.x),.35));}
 }else{
  v=n(p*4.);
  if(variant==0){v=h(floor(p*8.));}
  if(variant==5 || variant==6 || variant==12){v=variant==6 ? cells.z : cells.x;}
  if(variant==7 || variant==13){v=(n(p)+n(p*2.)*.5+n(p*4.)*.25+n(p*8.)*.125)/1.875;}
  if(variant==8){v=1.-abs(v*2.-1.);}
  if(variant==9 || variant==10){v=abs(v*2.-1.);}
  if(variant==11){v=n(p*4.+vec2(coarse,n(p+27.))*distortion*30.);}
 }
 return clamp((v-.5)*contrast+.5+brightness,0.,1.);
}
void fragment(){vec2 local=UV*extent; vec2 p=origin+axis_x*local.x+axis_y*local.y; p=mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)))*p/max(.01,texture_size)*16.;
 vec2 image_uv=p/16./image_aspect;
 if(tiling==1){image_uv=1.-abs(mod(image_uv,2.)-1.);}if(tiling==2){image_uv=clamp(image_uv,vec2(.001),vec2(.999));}
 float height=pattern(p); vec4 c=imported ? texture(image_map,image_uv) : mix(primary,secondary,height);
 if(imported){c.rgb=mix(c.rgb,c.rgb*primary.rgb,tint_strength);c.rgb=(c.rgb-.5)*contrast+.5+brightness;}
 if(mixer_enabled){vec2 p2=mat2(vec2(cos(secondary_angle),sin(secondary_angle)),vec2(-sin(secondary_angle),cos(secondary_angle)))*local/max(.01,secondary_texture_size)*16.;
 float height2=secondary_pattern(p2);vec4 c2=secondary_imported ? texture(secondary_image_map,p2/16./secondary_image_aspect) : mix(secondary_primary,secondary_secondary,height2);
 float amount=mix_amount;if(mix_distribution==1){amount*=smoothstep(.25,.75,n(p*4.))*2.;}if(mix_distribution==2){amount*=smoothstep(.25,.75,cell(p*.3).z)*2.;}if(mix_distribution==3){amount*=texture(mix_mask,UV).a;}
 c=mix(c,c2,clamp(amount,0.,1.));height=mix(height,height2,clamp(amount,0.,1.));}
 if(!imported && family==6){c.a*=smoothstep(.15,.6,height);}
 if(relief!=0.){float e=mix(.025,.25,relief_softness);float dx=(pattern(p+vec2(e,0.))-pattern(p-vec2(e,0.)))/e,dy=(pattern(p+vec2(0.,e))-pattern(p-vec2(0.,e)))/e;float r=(dx*cos(light_angle)+dy*sin(light_angle))*relief*.2;c.rgb*=1.+max(r,0.)*highlight+min(r,0.)*shadow;}
 vec4 old=texture(base_map,UV); float lum=dot(c.rgb,vec3(.2126,.7152,.0722));
 if(blend_mode==1){c.rgb=mix(2.*old.rgb*c.rgb,1.-2.*(1.-old.rgb)*(1.-c.rgb),step(vec3(.5),old.rgb));}
 if(blend_mode==2){c.rgb*=dot(old.rgb,vec3(.2126,.7152,.0722))/max(.01,lum);}
 if(blend_mode==3){c.rgb=old.rgb*(.65+height*.7);}
 c.a*=masked ? texture(coverage_map,UV).a : 1.; COLOR=vec4(clamp(c.rgb,vec3(0.),vec3(1.)),c.a);
}
"""
static func material(value: KiwiTextureMaterial,extent: Vector2,frame: Transform2D=Transform2D.IDENTITY,straight_output: bool=false) -> ShaderMaterial:
	if shader==null:
		shader=Shader.new()
		var duplicate:=CODE.substr(CODE.find("float h("),CODE.find("void fragment()")-CODE.find("float h("))
		for key in ["family","variant","density","thickness","roughness","distortion","detail","knots","contrast","brightness","seed","noise_map","h","n","cell","line","pattern"]:
			var regex:=RegEx.new(); regex.compile("\\b"+key+"\\b"); duplicate=regex.sub(duplicate,"secondary_"+key,true)
		shader.code=CODE.replace("void fragment()",duplicate+"\nvoid fragment()")
	if straight_output and straight_shader==null:
		straight_shader=Shader.new(); straight_shader.code=shader.code.replace("render_mode unshaded;","render_mode unshaded, blend_disabled;")
	var result:=ShaderMaterial.new(); result.shader=straight_shader if straight_output else shader
	var family:=Library.CATEGORIES.keys().find(Library.category(value.material_id))
	result.set_shader_parameter("family",maxi(0,family)); result.set_shader_parameter("variant",Library.variant(value.material_id))
	var defaults:=Library.create(value.material_id).parameters
	for key in ["primary","secondary","density","thickness","roughness","distortion","detail","knots","contrast","brightness","seed"]:
		result.set_shader_parameter(key,value.parameters.get(key,defaults.get(key)))
	var noise_key:=hash([family,Library.variant(value.material_id),value.parameters.get("seed",0),value.parameters.get("frequency",.035),value.parameters.get("octaves",4),value.parameters.get("gain",.5),value.parameters.get("lacunarity",2)])
	if not noise_cache.has(noise_key):
		if noise_cache.size()>64: noise_cache.erase(noise_cache.keys()[0])
		var noise:=FastNoiseLite.new(); noise.seed=value.parameters.get("seed",0); noise.frequency=value.parameters.get("frequency",.035); noise.fractal_octaves=value.parameters.get("octaves",4); noise.fractal_gain=value.parameters.get("gain",.5); noise.fractal_lacunarity=value.parameters.get("lacunarity",2)
		if family==9:
			noise.noise_type=FastNoiseLite.TYPE_PERLIN if Library.variant(value.material_id)==3 else (FastNoiseLite.TYPE_VALUE if Library.variant(value.material_id) in [1,2] else FastNoiseLite.TYPE_SIMPLEX_SMOOTH)
		noise_cache[noise_key]=ImageTexture.create_from_image(noise.get_seamless_image(128,128))
	result.set_shader_parameter("noise_map",noise_cache[noise_key]); result.set_shader_parameter("extent",extent)
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
		for key in ["family","variant","primary","secondary","density","thickness","roughness","distortion","detail","knots","contrast","brightness","seed","noise_map","image_map","image_aspect","imported","texture_size"]:
			result.set_shader_parameter("secondary_"+key,other.get_shader_parameter(key))
		result.set_shader_parameter("secondary_angle",deg_to_rad(second.rotation)); result.set_shader_parameter("mix_amount",value.mix_amount)
		result.set_shader_parameter("mix_distribution",["uniform","noise","patches","selection"].find(value.mix_distribution)); result.set_shader_parameter("mix_mask",value.mix_mask)
	return result

static func preview(host: Node,value: KiwiTextureMaterial,size: Vector2i=Vector2i(256,256),extent: Vector2=Vector2.ZERO,frame: Transform2D=Transform2D.IDENTITY) -> Image:
	var viewport:=SubViewport.new(); viewport.disable_3d=true; viewport.transparent_bg=true; viewport.size=size; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; host.add_child(viewport)
	var rect:=ColorRect.new(); rect.size=Vector2(size); rect.material=material(value,extent if extent!=Vector2.ZERO else Vector2(size),frame,true); viewport.add_child(rect)
	for i in 3:
		await RenderingServer.frame_post_draw
		if not is_instance_valid(viewport): return null
	var image:=viewport.get_texture().get_image(); viewport.queue_free(); return image
