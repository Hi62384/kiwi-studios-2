shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled, depth_prepass_alpha;
uniform vec4 root_color : source_color=vec4(.08,.025,.01,1);
uniform vec4 tip_color : source_color=vec4(.32,.14,.045,1);
uniform vec4 highlight_color : source_color=vec4(.9,.8,.65,1);
uniform float roughness=.5;
uniform float specular=.55;
uniform float secondary_highlight=.2;
uniform float highlight_shift=.15;
uniform float backlight=.15;
uniform float opacity=1.;
uniform vec4 emission : source_color=vec4(0,0,0,1);
uniform float variation=.12;
uniform bool stylized=false;
uniform int bands=3;
uniform float edge_softness=.08;
uniform float outline=0.;
uniform vec4 outline_color : source_color=vec4(.015,.01,.02,1);
uniform vec4 shaft_color : source_color=vec4(.6,.42,.22,1);
uniform float feather_detail=.2;
uniform float iridescence=0.;
uniform int feather_pattern=0;
uniform vec4 feather_pattern_color : source_color=vec4(.08,.04,.015,1);
uniform float feather_pattern_scale=5.;
uniform float feather_pattern_width=.2;
uniform vec4 left_vane_color : source_color=vec4(1);
uniform vec4 right_vane_color : source_color=vec4(1);
uniform float shaft_roughness=.65;
uniform int pattern=0;
uniform vec4 pattern_color : source_color=vec4(.015,.01,.005,1);
uniform float pattern_scale=4.;
uniform float pattern_rotation=0.;
uniform float pattern_mix=.7;
uniform float pattern_seed=31.;
uniform sampler2D albedo_texture : source_color,filter_linear_mipmap,repeat_enable;
uniform sampler2D roughness_texture : filter_linear_mipmap,repeat_enable;
uniform sampler2D normal_texture : hint_normal,filter_linear_mipmap,repeat_enable;
uniform sampler2D alpha_texture : filter_linear_mipmap,repeat_enable;
uniform sampler2D gradient_texture : source_color,filter_linear;
uniform bool use_albedo_texture=false;
uniform bool use_roughness_texture=false;
uniform bool use_normal_texture=false;
uniform bool use_alpha_texture=false;
uniform bool use_gradient=false;
uniform float lod_density=1.;
uniform float coverage_scale=1.;
uniform bool growth_skin_attachment=false;
uniform bool growth_guide_motion=false;
uniform float growth_motion_influence=1.;
uniform sampler2D growth_triangles : filter_nearest;
uniform sampler2D growth_rest_points : filter_nearest;
uniform sampler2D growth_posed_points : filter_nearest;
uniform sampler2D growth_guide_indices : filter_nearest;
uniform sampler2D growth_guide_weights : filter_nearest;
uniform sampler2D growth_guide_points : filter_nearest;
uniform vec2 texture_scale=vec2(1);
uniform vec2 texture_offset=vec2(0);
uniform float texture_rotation=0.;
varying vec3 strand_direction;
varying vec3 root_position;
varying float strand_seed;
varying float feather;
varying float shaft;
float noise_hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
vec4 table_value(sampler2D data,int index) {
	int width=textureSize(data,0).x;
	return texelFetch(data,ivec2(index%width,index/width),0);
}
mat3 surface_frame(vec3 a,vec3 b,vec3 c) {
	vec3 tangent=normalize(b-a);
	vec3 normal=normalize(cross(c-a,b-a));
	return mat3(tangent,normal,normalize(cross(tangent,normal)));
}
vec3 guide_delta(int root_index,float t) {
	vec4 guides=table_value(growth_guide_indices,root_index);
	vec4 weights=table_value(growth_guide_weights,root_index);
	float at=clamp(t,0.,1.)*8.;
	int segment=min(int(at),7);
	vec3 delta=vec3(0);
	for(int i=0;i<4;i++) {
		if(guides[i]<0. || weights[i]<=0.) continue;
		int offset=int(guides[i])*9+segment;
		delta+=mix(table_value(growth_guide_points,offset).xyz,table_value(growth_guide_points,offset+1).xyz,at-float(segment))*weights[i];
	}
	return delta*growth_motion_influence;
}
vec3 rotate_between(vec3 value,vec3 from,vec3 to) {
	vec3 axis=cross(from,to);
	float sine=length(axis),cosine=clamp(dot(from,to),-1.,1.);
	if(sine<.00001) return value;
	axis/=sine;
	return value*cosine+cross(axis,value)*sine+axis*dot(axis,value)*(1.-cosine);
}
void vertex() {
	vec3 center=CUSTOM1.xyz;
	if(growth_skin_attachment || growth_guide_motion) {
		int root_index=int(CUSTOM2.w);
		vec4 triangle=table_value(growth_triangles,root_index);
		vec3 a=table_value(growth_rest_points,int(triangle.x)).xyz;
		vec3 b=table_value(growth_rest_points,int(triangle.y)).xyz;
		vec3 c=table_value(growth_rest_points,int(triangle.z)).xyz;
		mat3 rest_frame=surface_frame(a,b,c);
		vec3 root=a*CUSTOM2.x+b*CUSTOM2.y+c*CUSTOM2.z;
		if(growth_guide_motion) {
			vec3 delta=rest_frame*guide_delta(root_index,UV.y);
			vec3 derivative=rest_frame*(guide_delta(root_index,min(1.,UV.y+.02))-guide_delta(root_index,max(0.,UV.y-.02)))/max(.001,triangle.w*.04);
			vec3 next_tangent=normalize(TANGENT+derivative);
			vec3 side=rotate_between(VERTEX-center,TANGENT,next_tangent);
			NORMAL=normalize(rotate_between(NORMAL,TANGENT,next_tangent));
			TANGENT=next_tangent;
			center+=delta; VERTEX=center+side;
		}
		if(growth_skin_attachment) {
			vec3 pa=table_value(growth_posed_points,int(triangle.x)).xyz;
			vec3 pb=table_value(growth_posed_points,int(triangle.y)).xyz;
			vec3 pc=table_value(growth_posed_points,int(triangle.z)).xyz;
			mat3 deformation=surface_frame(pa,pb,pc)*transpose(rest_frame);
			vec3 next_root=pa*CUSTOM2.x+pb*CUSTOM2.y+pc*CUSTOM2.z;
			VERTEX=next_root+deformation*(VERTEX-root);
			center=next_root+deformation*(center-root);
			NORMAL=normalize(deformation*NORMAL); TANGENT=normalize(deformation*TANGENT);
		}
	}
	VERTEX=center+(VERTEX-center)*coverage_scale;
	strand_direction=normalize((MODELVIEW_MATRIX*vec4(TANGENT,0)).xyz);
	root_position=CUSTOM0.xyz;
	strand_seed=abs(CUSTOM0.w);
	feather=step(1.,CUSTOM0.w);
	shaft=step(CUSTOM0.w,-.5);
}
void fragment() {
	vec2 uv=UV*texture_scale;
	float c=cos(texture_rotation),s=sin(texture_rotation);
	uv=mat2(vec2(c,s),vec2(-s,c))*(uv-.5)+.5+texture_offset;
	vec3 color=mix(root_color.rgb,tip_color.rgb,UV.y);
	if(use_gradient) color=texture(gradient_texture,vec2(UV.y,.5)).rgb;
	color*=1.+(fract(strand_seed)*2.-1.)*variation;
	vec3 p=root_position*pattern_scale;
	c=cos(pattern_rotation); s=sin(pattern_rotation);
	p.xz=mat2(vec2(c,s),vec2(-s,c))*p.xz;
	float mark=0.;
	if(pattern==1) mark=smoothstep(.1,.3,sin(p.x*6.283+sin(p.z*2.)));
	if(pattern==2) mark=1.-smoothstep(.17,.28,length(fract(p.xz)-.5));
	if(pattern==3) mark=step(.8,noise_hash(floor(p*5.)+pattern_seed));
	if(pattern==4) mark=.5+.5*sin(p.x*4.+sin(p.y*3.)+sin(p.z*3.));
	if(pattern==5) mark=smoothstep(.35,.6,noise_hash(floor(p)+pattern_seed));
	color=mix(color,pattern_color.rgb,mark*pattern_mix);
	color=mix(color,shaft_color.rgb,shaft);
	color*=mix(vec3(1),mix(left_vane_color.rgb,right_vane_color.rgb,step(.5,UV.x)),feather);
	float marking=0.;
	if(feather_pattern==1) marking=1.-smoothstep(feather_pattern_width,feather_pattern_width+.05,fract(UV.y*feather_pattern_scale));
	if(feather_pattern==2) marking=1.-smoothstep(feather_pattern_width,feather_pattern_width+.05,length(fract(UV*feather_pattern_scale)-.5));
	if(feather_pattern==3) marking=1.-smoothstep(feather_pattern_width,feather_pattern_width+.05,min(UV.x,1.-UV.x));
	if(feather_pattern==4) marking=smoothstep(1.-feather_pattern_width-.05,1.-feather_pattern_width,UV.y);
	if(feather_pattern==5) marking=step(1.-feather_pattern_width,noise_hash(floor(vec3(UV*feather_pattern_scale*5.,strand_seed))));
	color=mix(color,feather_pattern_color.rgb,marking*feather);
	color*=1.-feather*feather_detail*.3*(.5+.5*sin(UV.y*250.+abs(UV.x-.5)*60.));
	if(use_albedo_texture) color*=texture(albedo_texture,uv).rgb;
	if(stylized && outline>0.) color=mix(color,outline_color.rgb,1.-smoothstep(outline,outline+.025,min(UV.x,1.-UV.x)));
	ALBEDO=color*COLOR.rgb;
	ROUGHNESS=clamp(roughness*(texture(roughness_texture,uv).r*float(use_roughness_texture)+float(!use_roughness_texture)),.04,1.);
	ROUGHNESS=mix(ROUGHNESS,shaft_roughness,shaft);
	EMISSION=emission.rgb;
	BACKLIGHT=ALBEDO*backlight;
	if(use_normal_texture) { NORMAL_MAP=texture(normal_texture,uv).rgb; }
	ALPHA=opacity*(texture(alpha_texture,uv).r*float(use_alpha_texture)+float(!use_alpha_texture));
	ALPHA*=smoothstep(fract(strand_seed)-.025,fract(strand_seed)+.025,lod_density);
	ALPHA_SCISSOR_THRESHOLD=.4;
}
void light() {
	float nl=abs(dot(NORMAL,LIGHT));
	if(stylized) {
		float levels=float(max(1,bands));
		nl=(floor(nl*levels)+smoothstep(.5-edge_softness,.5+edge_softness,fract(nl*levels)))/levels;
	}
	DIFFUSE_LIGHT+=ALBEDO*LIGHT_COLOR*ATTENUATION*nl/3.141593;
	vec3 h=normalize(LIGHT+VIEW);
	vec3 t=normalize(strand_direction+NORMAL*highlight_shift);
	float th=dot(t,h);
	float power=mix(180.,3.,ROUGHNESS);
	float primary=pow(sqrt(max(0.,1.-th*th)),power);
	t=normalize(strand_direction-NORMAL*highlight_shift);
	th=dot(t,h);
	float secondary=pow(sqrt(max(0.,1.-th*th)),power*.45)*secondary_highlight;
	vec3 tint=mix(highlight_color.rgb,vec3(.5+.5*sin(dot(NORMAL,VIEW)*10.),.6,.9),iridescence*feather);
	SPECULAR_LIGHT+=tint*(primary+secondary)*specular*LIGHT_COLOR*ATTENUATION*nl;
}
