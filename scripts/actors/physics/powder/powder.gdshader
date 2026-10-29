shader_type spatial;
render_mode cull_back, depth_prepass_alpha;
uniform vec4 base_color : source_color = vec4(0.79,0.61,0.34,1.0);
uniform vec4 secondary_color : source_color = vec4(0.94,0.81,0.56,1.0);
uniform float variation = 0.4;
uniform float roughness = 0.85;
uniform float roughness_variation = 0.15;
uniform float metallic = 0.0;
uniform float specular = 0.4;
uniform float opacity = 1.0;
uniform vec2 texture_scale = vec2(1.0);
uniform vec2 texture_offset = vec2(0.0);
uniform float texture_rotation = 0.0;
uniform float texture_blend = 1.0;
uniform vec4 texture_tint : source_color = vec4(1.0);
uniform float detail_intensity = 0.2;
uniform float normal_strength = 0.5;
uniform bool flat_shading = false;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap, repeat_enable;
uniform bool has_albedo = false;
uniform bool has_normal = false;
uniform bool has_roughness = false;
varying vec4 grain_data;
varying vec3 grain_local;
void vertex(){ grain_data=INSTANCE_CUSTOM; grain_local=VERTEX; }
void fragment(){
	vec2 p=UV*texture_scale;
	float c=cos(texture_rotation),s=sin(texture_rotation);
	p=mat2(vec2(c,s),vec2(-s,c))*p+texture_offset;
	vec4 tint=mix(base_color,secondary_color,grain_data.x*variation);
	float mineral=sin(dot(grain_local,vec3(87.1,113.7,63.3))+grain_data.z*31.0)*0.5+0.5;
	tint.rgb*=mix(1.0,mix(0.62,1.18,mineral),detail_intensity);
	if(has_albedo){ tint*=mix(vec4(1.0),texture(albedo_map,p)*texture_tint,texture_blend); }
	ALBEDO=tint.rgb;
	ROUGHNESS=clamp(roughness+(grain_data.y-0.5)*roughness_variation,0.0,1.0);
	if(has_roughness){ ROUGHNESS*=mix(1.0,texture(roughness_map,p).r,texture_blend); }
	METALLIC=metallic; SPECULAR=specular;
	if(has_normal){ NORMAL_MAP=texture(normal_map,p).rgb; NORMAL_MAP_DEPTH=normal_strength; }
	if(flat_shading){ EMISSION=ALBEDO; ALBEDO=vec3(0.0); }
	ALPHA=tint.a*opacity;
}
