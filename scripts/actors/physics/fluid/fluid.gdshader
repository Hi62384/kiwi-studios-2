shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
uniform vec4 liquid_color : source_color = vec4(0.12,0.46,0.8,1.0);
uniform vec4 foam_color : source_color = vec4(0.94,0.98,1.0,1.0);
uniform float opacity = 0.96;
uniform float roughness = 0.16;
uniform float metallic = 0.0;
uniform float specular = 0.7;
uniform float glow = 0.0;
uniform float foam_amount = 0.45;
uniform bool has_texture = false;
uniform bool has_normal = false;
uniform sampler2D detail_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float texture_scale = 1.0;
uniform vec3 texture_offset = vec3(0.0);
uniform float texture_rotation = 0.0;
uniform vec3 texture_flow = vec3(0.03,-0.05,0.02);
uniform float texture_blend = 1.0;
uniform float normal_strength = 0.25;
uniform float liquid_time = 0.0;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
 world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
 world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
 vec3 p = world_position * texture_scale + texture_offset + texture_flow * liquid_time;
 float c = cos(texture_rotation); float s = sin(texture_rotation);
 p.xz = mat2(vec2(c,-s),vec2(s,c)) * p.xz;
 vec3 weights = pow(abs(world_normal),vec3(4.0)); weights /= max(dot(weights,vec3(1.0)),0.0001);
 vec3 detail = texture(detail_texture,p.yz).rgb*weights.x + texture(detail_texture,p.xz).rgb*weights.y + texture(detail_texture,p.xy).rgb*weights.z;
 vec3 base = liquid_color.rgb;
 if (has_texture) { base *= mix(vec3(1.0),detail,texture_blend); }
 float foam = clamp(COLOR.r*foam_amount,0.0,1.0);
 ALBEDO = mix(base,foam_color.rgb,foam);
 ROUGHNESS = mix(roughness,0.85,foam); METALLIC = metallic; SPECULAR = specular;
 EMISSION = base * glow; ALPHA = liquid_color.a * opacity;
 if (has_normal) { NORMAL_MAP = texture(normal_texture,p.xz).rgb; NORMAL_MAP_DEPTH = normal_strength; }
}
