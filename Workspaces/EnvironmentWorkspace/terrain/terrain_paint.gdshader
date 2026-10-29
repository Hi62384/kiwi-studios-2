shader_type spatial;
uniform vec2 terrain_size = vec2(32.0);
uniform sampler2D paint_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D ground_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D paint_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D paint_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D paint_roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D ground_metallic_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D paint_metallic_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 ground_roughness_channel = vec4(1.0,0.0,0.0,0.0);
uniform vec4 paint_roughness_channel = vec4(1.0,0.0,0.0,0.0);
uniform vec4 ground_metallic_channel = vec4(1.0,0.0,0.0,0.0);
uniform vec4 paint_metallic_channel = vec4(1.0,0.0,0.0,0.0);
uniform vec4 ground_color : source_color = vec4(1.0);
uniform vec4 paint_color : source_color = vec4(1.0);
uniform vec3 ground_scale = vec3(1.0);
uniform vec3 paint_scale = vec3(1.0);
uniform vec3 ground_offset = vec3(0.0);
uniform vec3 paint_offset = vec3(0.0);
uniform float ground_roughness = 1.0;
uniform float paint_roughness = 1.0;
uniform float ground_metallic = 0.0;
uniform float paint_metallic = 0.0;
uniform float ground_normal_strength = 0.0;
uniform float paint_normal_strength = 0.0;
varying vec3 local_position;
varying vec3 local_normal;
varying mat3 normal_to_view;
void vertex() { local_position = VERTEX; local_normal = NORMAL; normal_to_view = mat3(VIEW_MATRIX) * MODEL_NORMAL_MATRIX; }
vec3 triplanar_color(sampler2D tex, vec3 p, vec3 weights) {
 return texture(tex,p.zy).rgb*weights.x + texture(tex,p.xz).rgb*weights.y + texture(tex,p.xy).rgb*weights.z;
}
float triplanar_value(sampler2D tex,vec3 p,vec3 weights,vec4 channel) {
 return dot(texture(tex,p.zy),channel)*weights.x+dot(texture(tex,p.xz),channel)*weights.y+dot(texture(tex,p.xy),channel)*weights.z;
}
vec3 triplanar_normal(sampler2D tex,vec3 p,vec3 weights,vec3 signs) {
 vec3 x=texture(tex,p.zy).rgb*2.0-1.0; vec3 y=texture(tex,p.xz).rgb*2.0-1.0; vec3 z=texture(tex,p.xy).rgb*2.0-1.0;
 return normalize(vec3(x.z*signs.x,x.y,x.x)*weights.x+vec3(y.x,y.z*signs.y,y.y)*weights.y+vec3(z.x,z.y,z.z*signs.z)*weights.z);
}
void fragment() {
 vec3 normal=normalize(local_normal); vec3 weights=pow(abs(normal),vec3(4.0)); weights/=max(dot(weights,vec3(1.0)),0.00001);
 float amount=clamp(texture(paint_mask,local_position.xz/terrain_size+vec2(0.5)).r,0.0,1.0);
 vec3 ground_uv=local_position*ground_scale+ground_offset; vec3 paint_uv=local_position*paint_scale+paint_offset;
 vec3 base=ground_color.rgb*triplanar_color(ground_texture,ground_uv,weights);
 vec3 painted=paint_color.rgb*triplanar_color(paint_texture,paint_uv,weights);
 ALBEDO=mix(base,painted,amount);
 ROUGHNESS=mix(ground_roughness*triplanar_value(ground_roughness_texture,ground_uv,weights,ground_roughness_channel),paint_roughness*triplanar_value(paint_roughness_texture,paint_uv,weights,paint_roughness_channel),amount);
 METALLIC=mix(ground_metallic*triplanar_value(ground_metallic_texture,ground_uv,weights,ground_metallic_channel),paint_metallic*triplanar_value(paint_metallic_texture,paint_uv,weights,paint_metallic_channel),amount);
 vec3 signs=sign(normal+vec3(0.000001));
 vec3 base_normal=normalize(mix(normal,triplanar_normal(ground_normal,ground_uv,weights,signs),ground_normal_strength));
 vec3 painted_normal=normalize(mix(normal,triplanar_normal(paint_normal,paint_uv,weights,signs),paint_normal_strength));
 NORMAL=normalize(normal_to_view*normalize(mix(base_normal,painted_normal,amount)));
}
